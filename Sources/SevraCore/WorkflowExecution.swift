import Foundation

extension Workbook {
  public func completeWorkflowStep(
    _ session: WorkflowExecutionSession, claim: Value,
    interpretation: Value? = nil, extraction: Value? = nil,
    intake: WorkflowIntakePreparation? = nil,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try workflowSession(session)
    guard let attemptID = claim["id"].string, UUID(uuidString: attemptID) != nil else {
      throw SevraError("workflow_claim", "Use a saved worker claim.")
    }
    if let intake {
      let committed = try synchronized {
        try db.scalar(
          "SELECT EXISTS(SELECT 1 FROM operations WHERE id=?)",
          [
            .string("workflow-step:" + attemptID)
          ]
        ).int == 1
      }
      if !committed {
        // Exact retries need no original/helper. A new publication verifies the
        // included original again before taking the workbook transaction lock.
        _ = try assetURL(intake.request["assetID"].text, verify: true, cancellation: cancellation)
      }
    }
    var deadline: Double?
    let guardLease: () throws -> Void = {
      try session.automation?.deviceFence?()
      if let deadline {
        try require(
          Date().timeIntervalSince1970 < deadline, "workflow_fenced",
          "The worker lease expired before its checkpoint could commit.")
      }
    }
    let result = try mutation(
      "workflow_step", token: "workflow-step:" + attemptID,
      request: .object([
        "claim": claim, "interpretation": interpretation ?? .null,
        "extractionDigest": try extraction.map {
          .string(ToolResultProjection.digest(try $0.json()))
        }
          ?? .null,
        "intakeDigest": intake.map { .string($0.digest) } ?? .null,
      ]),
      cancellation: cancellation,
      actor: interpretation.map {
        .ai(
          "SevraCore.workflowInterpretation", model: $0["request"]["model"].text,
          policy: "workflow-evidence-only-v1")
      } ?? .programmatic("SevraCore.workflowWorker"), commitGuard: guardLease
    ) {
      let saved = try self.validateWorkflowClaim(session, claim: claim)
      deadline = Double(saved["deadline"].text)
      let run = try self.workflowRun(session.runID)
      let definition = try self.applicationDefinition(run["definition_id"].text)
      let descriptor = try DefinitionDescriptor(definition.content)
      let workflow = try DefinitionWorkflow(descriptor)
      guard let step = workflow.steps.first(where: { $0.id == saved["step_id"].text }) else {
        throw SevraError(
          "workflow_integrity", "The claimed step is missing from its pinned definition.")
      }
      let outputs = Dictionary(
        uniqueKeysWithValues: run["steps"].array.filter {
          $0["state"] == .string("completed")
        }.map { ($0["step_id"].text, $0["output"]["value"]) })
      let args = try self.workflowArguments(
        step, descriptor: descriptor,
        supplied: run["arguments"], outputs: outputs)
      var revision = try self.revision()
      var output: Value
      var state = "completed"
      var detail = ""
      try require(
        step.kind == "interpret" || interpretation == nil, "workflow_model",
        "Only an interpretation step consumes a model result.")
      try require(
        step.kind == "extract" || extraction == nil, "workflow_extraction",
        "Only document preparation consumes a native extraction result.")
      try require(
        step.kind == "intake" || intake == nil, "workflow_intake",
        "Only structured intake consumes a prepared table update.")
      if step.kind == "evaluate" {
        output = try self.evaluateApplicationDefinition(
          step.binding!.target,
          arguments: args, cancellation: cancellation)
        try require(
          output["nextCursor"] == .null, "workflow_partial",
          "This query has more pages. A partial result cannot complete this workflow step.")
        if output["kind"] == .string("query") {
          try self.validateWorkflowLookupResult(output, stepID: step.id, workflow: workflow)
          var retained = output.object
          retained["inputPopulation"] = .array(
            try self.definitionQueryPopulation(output, cancellation: cancellation))
          output = .object(retained)
        }
      } else if step.kind == "extract" {
        guard let extraction else {
          throw SevraError(
            "workflow_extraction", "Continue document preparation through the workflow coordinator."
          )
        }
        output = try self.insertWorkflowExtraction(
          extraction, run: run, step: step, arguments: args,
          attemptID: attemptID, cancellation: cancellation)
        revision = output["request"]["readRevision"].int!
        if output["complete"] != .bool(true) {
          state = "needs_attention"
          detail = String(output["detail"].text.prefix(1000))
        }
      } else if step.kind == "intake" {
        guard let intake else {
          throw SevraError(
            "workflow_intake", "Continue structured intake through the workflow coordinator.")
        }
        output = try self.insertWorkflowIntake(
          intake, run: run, step: step, arguments: args,
          attemptID: attemptID, cancellation: cancellation)
        revision = output["request"]["readRevision"].int!
        let review = workflow.steps.first { $0.review == step.id }!
        for proposal in output["proposals"].array {
          try self.db.execute(
            "INSERT INTO workflow_approvals VALUES(?,?,?,NULL)",
            [.string(session.runID), .string(review.id), proposal])
        }
      } else if step.kind == "interpret" {
        guard let interpretation else {
          throw SevraError(
            "workflow_model", "Continue this step through the local AI workflow coordinator.")
        }
        output = try self.insertWorkflowInterpretation(
          interpretation, run: run, step: step, attemptID: attemptID)
        revision = output["request"]["readRevision"].int!
        if output["response"]["state"] == .string("needs_input") {
          state = "needs_attention"
          detail = String(
            output["response"]["issues"].array.map(\.text).joined(separator: " ").prefix(1000))
        }
      } else if step.kind == "action" {
        let plan = try self.applicationActionPlan(
          step.binding!.target, arguments: args,
          cancellation: cancellation)
        let interpretationInputs = try self.workflowValueInputs(
          step, workflow: workflow, outputs: outputs)
        for movement in plan["movements"].array where movement["meaning"] == .string("actual") {
          try require(
            interpretationInputs.data.allSatisfy {
              $0.meaning == "actual" && $0.scenario == "actual"
            }, "interpretation_meaning",
            "Actual proposals cannot promote a mapped estimate, plan or another scenario into actuals."
          )
        }
        for document in plan["documents"].array where document["meaning"] == .string("actual") {
          try require(
            interpretationInputs.data.allSatisfy {
              $0.meaning == "actual" && $0.scenario == document["scenario"].text
            }, "interpretation_meaning",
            "Actual documents cannot promote mapped estimates, plans or another scenario.")
        }
        output = try self.insertApplicationAction(
          plan: plan,
          request: .object([
            "workflowRunID": .string(session.runID), "stepID": .string(step.id),
            "operationID": .string("workflow-effect:" + session.runID + ":" + step.id),
            "arguments": args,
          ]), actor: .programmatic("SevraCore.workflowWorker"),
          additionalInputs: interpretationInputs.data.map(\.id),
          controlInputs: interpretationInputs.controls, producerInputs: [run["source_id"].text],
          cancellation: cancellation)
        let review = workflow.steps.first { $0.review == step.id }!
        for proposal in output["proposals"].array {
          try self.db.execute(
            "INSERT INTO workflow_approvals VALUES(?,?,?,NULL)",
            [.string(session.runID), .string(review.id), proposal])
        }
      } else {
        output = try self.workflowReview(session.runID, stepID: step.id)
        if output["ready"] != .bool(true) { state = "waiting_review" }
      }
      output = .object([
        "value": output, "readRevision": .number(Double(revision)),
        "arguments": args, "definitionID": step.binding.map { .string($0.target) } ?? .null,
      ])
      try require(
        try output.json().utf8.count <= 524_288, "workflow_limit",
        "A step output and its provenance exceed 512 KiB.")
      try cancellation.check()
      // The final guard also runs after saved-change capture, immediately before
      // COMMIT. Expiry rolls back effects, receipts and outbox together.
      _ = try self.validateWorkflowClaim(session, claim: claim)
      try self.db.execute(
        "UPDATE workflow_attempts SET state=?,updated=? WHERE id=?",
        [.string(state == "needs_attention" ? "failed" : state), .string(timestamp()), saved["id"]])
      try self.db.execute(
        "UPDATE workflow_steps SET state=?,output=?,detail=?,updated=? WHERE run_id=? AND step_id=?",
        [
          .string(state), .string(try output.json()), .string(detail), .string(timestamp()),
          .string(session.runID),
          .string(step.id),
        ])
      let remaining =
        try self.db.scalar(
          "SELECT count(*) FROM workflow_steps WHERE run_id=? AND state!='completed'",
          [.string(session.runID)]
        ).int ?? 0
      let runState =
        ["waiting_review", "needs_attention"].contains(state)
        ? state : (remaining == 0 ? "completed" : "queued")
      try self.db.execute(
        "UPDATE workflow_runs SET state=?,detail=?,updated=? WHERE id=?",
        [.string(runState), .string(detail), .string(timestamp()), .string(session.runID)])
      try self.workflowEvent(session.runID, stepID: step.id, kind: state, payload: output)
      WorkflowPublicationProbe.observer?(.prepared, session.runID)
      return try self.workflowRun(session.runID)
    }
    WorkflowPublicationProbe.observer?(.committed, session.runID)
    return result
  }

  /// One explicit bounded step. No timer, hidden retry, model or background loop.
  public func advanceWorkflow(
    _ session: WorkflowExecutionSession, owner: String,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    let claim = try claimWorkflowStep(session, owner: owner, cancellation: cancellation)
    if claim == .null { return try workflowRun(session.runID) }
    do { return try completeWorkflowStep(session, claim: claim, cancellation: cancellation) } catch
    {
      let detail = String(String(describing: error).prefix(1000))
      _ = try? failWorkflowStep(session, claim: claim, detail: detail)
      throw error
    }
  }

  func workflowReview(_ runID: String, stepID: String, recordApprovals: Bool = true) throws -> Value
  {
    let rows = try db.execute(
      "SELECT * FROM workflow_approvals WHERE run_id=? AND step_id=? ORDER BY proposal_id LIMIT 51",
      [.string(runID), .string(stepID)])
    try require(
      !rows.isEmpty && rows.count <= 50, "workflow_integrity",
      "Review needs 1 to 50 exact proposals.")
    var accepted: [Value] = []
    var pending: [Value] = []
    for row in rows {
      let proposal = try item(row["proposal_id"]!.text)
      let current = try item(proposal.logicalID)
      if current.id == proposal.id && current.status == "draft" {
        pending.append(.string(proposal.id))
        continue
      }
      try require(
        try workflowAcceptedVersion(proposal, current),
        "workflow_stale_review",
        "A proposal changed or was withdrawn. Its old review request cannot approve the replacement."
      )
      accepted.append(.string(current.id))
    }
    if pending.isEmpty && recordApprovals {
      for row in rows {
        let proposal = try item(row["proposal_id"]!.text)
        let current = try item(proposal.logicalID)
        try db.execute(
          "UPDATE workflow_approvals SET accepted_id=? WHERE run_id=? AND step_id=? AND proposal_id=?",
          [.string(current.id), .string(runID), .string(stepID), .string(proposal.id)])
      }
    }
    return .object([
      "ready": .bool(pending.isEmpty), "accepted": .array(accepted), "pending": .array(pending),
      "meaning": .string("Acceptance preserves each proposal's meaning and scenario."),
    ])
  }

  func workflowAcceptedVersion(_ proposal: Item, _ accepted: Item) throws -> Bool {
    guard
      ["movement", "document", "table-intake-update"].contains(proposal.kind)
        && proposal.status == "draft"
        && accepted.supersedes == proposal.id && accepted.status == "accepted"
        && accepted.kind == proposal.kind && accepted.category == proposal.category
        && accepted.logicalID == proposal.logicalID
        && accepted.meaning == proposal.meaning && accepted.scenario == proposal.scenario
        && accepted.title == proposal.title && accepted.text == proposal.text
        && accepted.assetID == proposal.assetID
    else { return false }
    if proposal.kind != "table-intake-update" && accepted.data != proposal.data { return false }
    let lineage = try db.scalar(
      "SELECT count(*) FROM lineage WHERE child=? AND parent=? AND relation='supersedes' AND transformation='accept-v1'",
      [.string(accepted.id), .string(proposal.id)]
    ).int
    guard lineage == 1 else { return false }
    let decisions = try db.execute(
      "SELECT i.* FROM lineage l JOIN items i ON i.id=l.parent WHERE l.child=? AND l.relation='derives-from' AND l.transformation='accept-v1' AND i.category='source' AND i.kind='decision' AND i.status='accepted' LIMIT 3",
      [.string(accepted.id)])
    for row in decisions {
      let source = try decodeItem(row)
      if source.data["record"] == .string(proposal.id)
        && source.data["transformation"] == .string("decision-evidence-v2")
      {
        try JSONDecoder().decode(
          ChangeActor.self, from: Data(source.data["attribution"].json().utf8)
        ).validate()
        if proposal.kind == "table-intake-update" {
          return try workflowAcceptedTableIntake(proposal, accepted, decision: source)
        }
        return true
      }
    }
    return false
  }

  /// A table application adds canonical row-result metadata. Require the exact
  /// original plan and the trusted acceptance receipt, without weakening the
  /// unchanged-data rule used for documents and inventory movements.
  func workflowAcceptedTableIntake(_ proposal: Item, _ accepted: Item, decision: Item) throws
    -> Bool
  {
    let applied: Set<String> = [
      "beforeMembership", "afterMembership", "rowVersions", "afterFingerprint",
      "acceptanceOperationID", "decisionID",
    ]
    guard proposal.data["workflow"] != .null,
      Set(accepted.data.object.keys) == Set(proposal.data.object.keys).union(applied),
      proposal.data.object.allSatisfy({ accepted.data[$0.key] == $0.value }),
      accepted.data["decisionID"] == .string(decision.id),
      case .array = accepted.data["beforeMembership"],
      case .array = accepted.data["afterMembership"],
      case .array = accepted.data["rowVersions"],
      let operationID = accepted.data["acceptanceOperationID"].string,
      let receipt = try db.execute(
        "SELECT kind,request,result FROM operations WHERE id=?", [.string(operationID)]
      ).first
    else { return false }
    let request = try Value.parse(receipt["request"]!.text)
    let result = try Value.parse(receipt["result"]!.text)
    return receipt["kind"] == .string("accept")
      && request["arguments"] == .string(proposal.id)
      && request["actor"] == decision.data["attribution"]
      && result == .string(accepted.id)
      && accepted.data["afterFingerprint"].text.range(
        of: "^[0-9a-f]{64}\\z", options: .regularExpression) != nil
  }
}
