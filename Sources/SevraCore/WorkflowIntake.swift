import Foundation

/// Trusted host preparation. Callers cannot manufacture or edit parsed rows.
/// Canonical retention happens with the proposal and step checkpoint, not here.
public struct WorkflowIntakePreparation: Sendable {
  let request: Value
  let plan: TableUpdatePlan
  let digest: String
  public var preview: TableUpdatePreview { plan.preview }

  fileprivate init(request: Value, plan: TableUpdatePlan) throws {
    self.request = request
    self.plan = plan
    digest = ChangeFormat.hash(
      try Value.object([
        "request": request, "preview": encoded(plan.preview),
        "incoming": .array(plan.incoming.map(Value.object)),
        "changes": encoded(plan.changes), "additions": .array(plan.additions.map(Value.object)),
        "changeRecords": encoded(plan.changeRecords),
        "additionRecords": encoded(plan.additionRecords),
      ]).json())
  }
}

extension Workbook {
  public func prepareWorkflowIntake(
    _ session: WorkflowExecutionSession, claim: Value, worker: Value,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try workflowSession(session)
    try ExtractionWorker.validateWorkflowIdentity(worker)
    var deadline: Double?
    let guardLease: () throws -> Void = {
      if let deadline {
        try require(
          Date().timeIntervalSince1970 < deadline, "workflow_fenced",
          "The intake lease expired before input capture.")
      }
    }
    let result = try mutation(
      "workflow_intake_request", token: "workflow-intake:" + claim["id"].text,
      request: .object(["claim": claim, "worker": worker]), cancellation: cancellation,
      actor: .programmatic("SevraCore.workflowIntake"), commitGuard: guardLease
    ) {
      let saved = try self.validateWorkflowClaim(session, claim: claim)
      deadline = Double(saved["deadline"].text)
      let run = try self.workflowRun(session.runID)
      let descriptor = try DefinitionDescriptor(
        self.applicationDefinition(run["definition_id"].text).content)
      guard
        let step = try DefinitionWorkflow(descriptor).steps.first(where: {
          $0.id == saved["step_id"].text
        }), step.kind == "intake", let binding = step.binding
      else {
        throw SevraError("workflow_intake", "This claim is not a structured-intake step.")
      }
      let definition = try self.resolveDefinition(binding)
      let target = try DefinitionDescriptor(definition.content)
      try self.validateIntakeDefinition(target)
      let intake = try DefinitionIntake(target)
      let outputs = Dictionary(
        uniqueKeysWithValues: run["steps"].array.filter { $0["state"] == .string("completed") }
          .map { ($0["step_id"].text, $0["output"]["value"]) })
      let args = try self.workflowArguments(
        step, descriptor: descriptor, supplied: run["arguments"], outputs: outputs)
      let normalized = try self.definitionArguments(target, args)
      let source = try self.item(normalized[intake.file]!.text)
      try require(
        source.id == normalized[intake.file]!.text && source.isBusinessEvidence
          && source.category == "source" && source.assetID != nil,
        "workflow_intake_scope", "Choose an exact included business-file Source.")
      let asset = try self.asset(source.assetID!)
      try require(
        asset.mode == "included", "workflow_intake_scope",
        "Include this file in the workbook before preparing a structured update.")
      try require(
        intake.meaning != "actual"
          || (source.meaning == "actual" && source.scenario == intake.scenario),
        "intake_meaning", "An actual import cannot promote an estimate or another scenario.")
      return .object([
        "requestID": .string("workflow-intake:" + saved["id"].text),
        "attemptID": saved["id"], "workbookID": .string(self.id), "runID": run["id"],
        "stepID": saved["step_id"], "definitionID": .string(definition.id),
        "arguments": .object(normalized), "itemID": .string(source.id),
        "assetID": .string(asset.id), "assetHash": .string(asset.hash), "worker": worker,
        "parser": .string(DefinitionExtraction.parser),
        "policy": .string("workflow-table-intake-v1"),
        "datasetID": .string(intake.datasetID), "datasetDefinitionID": .string(intake.definitionID),
        "fingerprint": .string(try self.tableFingerprint(intake.datasetID)),
        "readRevision": .number(Double(try self.revision())),
        "limits": .object([
          "incomingRows": .number(1000), "targetRows": .number(10_000),
          "targetBytes": .number(16_000_000), "mappedBytes": .number(8_000_000),
        ]),
      ])
    }
    _ = try synchronized { try validateWorkflowClaim(session, claim: claim) }
    return result
  }

  /// Verify/hash/parse outside all workbook locks. The child never receives a
  /// database handle. The deterministic plan then reads one target snapshot.
  public func performWorkflowIntake(
    _ session: WorkflowExecutionSession, claim: Value, request: Value,
    worker: ExtractionWorker = .init(), cancellation: Cancellation = .init()
  ) throws -> WorkflowIntakePreparation {
    let intake = try synchronized {
      _ = try validateWorkflowClaim(session, claim: claim)
      try require(
        request["attemptID"] == claim["id"] && request["runID"] == .string(session.runID),
        "workflow_intake_request", "Use this worker's exact intake request.")
      return try validateWorkflowIntakeRequest(request)
    }
    try require(
      try worker.workflowIdentity(cancellation: cancellation) == request["worker"],
      "workflow_extraction_worker", "The intake parser changed. Retry the step.")
    let input = try tableUpdateInput(
      request["itemID"].text, headerRow: intake.headerRow, worker: worker,
      cancellation: cancellation)
    try require(
      input.sheet == nil, "update_format", "Workflow intake supports CSV and TSV originals.")
    try require(
      input.assetID == request["assetID"].text && input.assetHash == request["assetHash"].text
        && (try worker.workflowIdentity(cancellation: cancellation)) == request["worker"],
      "workflow_intake_request", "The original or native helper changed during intake.")
    let plan = try tableUpdatePlan(
      input: input, datasetID: intake.datasetID, mode: intake.mode,
      mapping: intake.mapping, keys: intake.keys, cancellation: cancellation)
    try require(
      plan.preview.fingerprint == request["fingerprint"].text, "stale_revision",
      "The target changed during preparation. Review the target before retrying.")
    try cancellation.check()
    return try WorkflowIntakePreparation(request: request, plan: plan)
  }

  @discardableResult func validateWorkflowIntakeRequest(_ request: Value) throws -> DefinitionIntake
  {
    let saved = try db.execute(
      "SELECT kind,result FROM operations WHERE id=?", [request["requestID"]]
    ).first
    try require(
      saved?["kind"] == .string("workflow_intake_request")
        && (try saved?["result"]?.string.map(Value.parse)) == request
        && request["workbookID"] == .string(id)
        && request["requestID"] == .string("workflow-intake:" + request["attemptID"].text)
        && request["policy"] == .string("workflow-table-intake-v1")
        && request["parser"] == .string(DefinitionExtraction.parser),
      "workflow_intake_request", "Use the exact retained structured-intake request.")
    try ExtractionWorker.validateWorkflowIdentity(request["worker"])
    let intake = try DefinitionIntake(
      DefinitionDescriptor(applicationDefinition(request["definitionID"].text).content))
    let source = try item(request["itemID"].text)
    let asset = try self.asset(request["assetID"].text)
    try require(
      source.id == request["itemID"].text && source.isBusinessEvidence
        && source.category == "source" && source.assetID == asset.id && asset.mode == "included"
        && asset.hash == request["assetHash"].text
        && request["arguments"][intake.file] == .string(source.id)
        && request["datasetID"] == .string(intake.datasetID)
        && request["datasetDefinitionID"] == .string(intake.definitionID),
      "workflow_intake_request", "The structured-intake request lost its exact source or mapping.")
    return intake
  }

  func insertWorkflowIntake(
    _ preparation: WorkflowIntakePreparation, run: Value, step: DefinitionWorkflow.Step,
    arguments: Value, attemptID: String, cancellation: Cancellation
  ) throws -> Value {
    let request = preparation.request
    let intake = try validateWorkflowIntakeRequest(request)
    try require(
      request["runID"] == run["id"] && request["stepID"] == .string(step.id)
        && request["attemptID"] == .string(attemptID)
        && request["definitionID"] == .string(step.binding!.target)
        && request["arguments"] == arguments
        && preparation.plan.preview.fingerprint == request["fingerprint"].text,
      "workflow_intake_request", "The prepared plan belongs to another workflow step.")
    try validateIntakeDefinition(
      DefinitionDescriptor(applicationDefinition(step.binding!.target).content))
    let preview = preparation.preview
    // A file that matches the table is a finished step, not a failure to retry. Nothing is proposed,
    // so a repeated scheduled file cannot hold its automation open.
    let changes = preview.added + preview.changed + preview.removed > 0
    var proposals: [Value] = []
    var planDigest: Value = .null
    if changes {
      let proposal = try insertTableUpdatePlan(
        preparation.plan, newRowMeaning: intake.meaning, newRowScenario: intake.scenario,
        workflow: request,
        controlInputs: [try applicationDefinition(step.binding!.target).sourceID],
        producerInputs: [run["source_id"].text],
        cancellation: cancellation)
      proposals = [.string(proposal)]
      planDigest = .string(ChangeFormat.hash(try item(proposal).data.json()))
    } else {
      try require(
        try tableFingerprint(preview.datasetID) == preview.fingerprint, "stale_revision",
        "The target changed. Review it again.")
    }
    return .object([
      "kind": .string("intake"), "definitionID": request["definitionID"], "request": request,
      "proposals": .array(proposals), "planDigest": planDigest,
      "summary": .object([
        "datasetID": .string(intake.datasetID), "mode": .string(intake.mode.rawValue),
        "incoming": .number(Double(preview.incoming)), "added": .number(Double(preview.added)),
        "changed": .number(Double(preview.changed)), "removed": .number(Double(preview.removed)),
        "unchanged": .number(Double(preview.unchanged)),
        "repeatedIncomingRows": .number(Double(preview.repeatedIncomingRows)),
        "rowsMatchingTarget": .number(Double(preview.rowsMatchingTarget)),
        "newRowMeaning": .string(intake.meaning), "newRowScenario": .string(intake.scenario),
      ]),
      "notice": .string(
        changes
          ? "Draft update only. Review the exact mapped values before applying rows. No inventory or financial effects."
          : "This file matches the table, so nothing changed and nothing needs review."
      ),
    ])
  }

  func validateWorkflowIntakeOutput(_ value: Value, runID: String, step: DefinitionWorkflow.Step)
    throws
  {
    let request = value["request"]
    let intake = try validateWorkflowIntakeRequest(request)
    try require(
      value["kind"] == .string("intake") && request["runID"] == .string(runID)
        && request["stepID"] == .string(step.id)
        && value["definitionID"] == request["definitionID"]
        && request["definitionID"] == .string(step.binding!.target)
        && value["proposals"].array.count <= 1,
      "workflow_integrity", "The structured-intake output lost its exact definition or proposal.")
    var summary: [String: Value] = [
      "datasetID": .string(intake.datasetID), "mode": .string(intake.mode.rawValue),
      "newRowMeaning": .string(intake.meaning), "newRowScenario": .string(intake.scenario),
    ]
    let counts = [
      "incoming", "added", "changed", "removed", "unchanged", "repeatedIncomingRows",
      "rowsMatchingTarget",
    ]
    if let id = value["proposals"].array.first {
      let proposal = try item(id.text)
      try require(
        proposal.kind == "table-intake-update" && proposal.status == "draft"
          && proposal.data["workflow"] == request
          && proposal.data["preview"]["fingerprint"] == request["fingerprint"]
          && proposal.data["newRowMeaning"] == .string(intake.meaning)
          && proposal.data["newRowScenario"] == .string(intake.scenario)
          && value["planDigest"] == .string(ChangeFormat.hash(try proposal.data.json()))
          && proposal.data["incoming"].array.count == proposal.data["preview"]["incoming"].int,
        "workflow_integrity", "The structured-intake checkpoint differs from its retained plan.")
      for field in counts { summary[field] = proposal.data["preview"][field] }
    } else {
      try require(
        value["planDigest"] == .null
          && ["added", "changed", "removed"].allSatisfy { value["summary"][$0].int == 0 },
        "workflow_integrity", "A structured intake with no proposal changed nothing.")
      for field in counts { summary[field] = value["summary"][field] }
    }
    try require(
      value["summary"] == .object(summary), "workflow_integrity",
      "The structured-intake summary differs from its retained preview.")
  }
}
