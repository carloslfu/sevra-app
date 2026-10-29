import Foundation

extension Workbook {
  public func prepareWorkflowExtraction(
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
          "The document preparation lease expired before input capture.")
      }
    }
    let result = try mutation(
      "workflow_extraction_request", token: "workflow-extraction:" + claim["id"].text,
      request: .object(["claim": claim, "worker": worker]), cancellation: cancellation,
      actor: .programmatic("SevraCore.workflowExtraction"), commitGuard: guardLease
    ) {
      let saved = try self.validateWorkflowClaim(session, claim: claim)
      deadline = Double(saved["deadline"].text)
      let run = try self.workflowRun(session.runID)
      let workflow = try self.applicationDefinition(run["definition_id"].text)
      let descriptor = try DefinitionDescriptor(workflow.content)
      guard
        let step = try DefinitionWorkflow(descriptor).steps.first(where: {
          $0.id == saved["step_id"].text
        }), step.kind == "extract", let binding = step.binding
      else {
        throw SevraError("workflow_extraction", "This claim is not a document preparation step.")
      }
      let definition = try self.resolveDefinition(binding)
      let target = try DefinitionDescriptor(definition.content)
      let extraction = try DefinitionExtraction(target)
      let outputs = Dictionary(
        uniqueKeysWithValues: run["steps"].array.filter {
          $0["state"] == .string("completed")
        }.map { ($0["step_id"].text, $0["output"]["value"]) })
      let args = try self.workflowArguments(
        step, descriptor: descriptor, supplied: run["arguments"], outputs: outputs)
      let normalized = try self.definitionArguments(target, args)
      let item = try self.item(normalized[extraction.file]!.text)
      try require(
        item.id == normalized[extraction.file]!.text && item.isBusinessEvidence,
        "workflow_extraction_scope", "Prepare an exact local business file item.")
      guard let assetID = item.assetID else {
        throw SevraError("workflow_extraction_scope", "Choose an included document file.")
      }
      let asset = try self.asset(assetID)
      try require(
        asset.mode == "included", "workflow_extraction_scope",
        "Include this file in the workbook before preparing it in a workflow.")
      try self.db.execute(
        "INSERT INTO extraction_attempts VALUES(?,?) ON CONFLICT(item_id) DO UPDATE SET attempt_id=excluded.attempt_id",
        [.string(item.id), saved["id"]])
      return .object([
        "requestID": .string("workflow-extraction:" + saved["id"].text),
        "attemptID": saved["id"], "workbookID": .string(self.id), "runID": run["id"],
        "stepID": saved["step_id"], "definitionID": .string(definition.id),
        "arguments": .object(normalized), "itemID": .string(item.id),
        "assetID": .string(asset.id), "assetHash": .string(asset.hash),
        "parser": .string(DefinitionExtraction.parser), "worker": worker,
        "policy": .string("workflow-included-document-v1"),
        "readRevision": .number(Double(try self.revision())), "timeoutSeconds": .number(180),
      ])
    }
    _ = try synchronized { try validateWorkflowClaim(session, claim: claim) }
    return result
  }

  /// Native parsing, including file verification, is outside any workbook write
  /// transaction. The child receives a file path, never a database handle.
  public func performWorkflowExtraction(
    _ session: WorkflowExecutionSession, claim: Value, request: Value,
    worker: ExtractionWorker = .init(), cancellation: Cancellation = .init()
  ) throws -> Value {
    try synchronized {
      _ = try validateWorkflowClaim(session, claim: claim)
      try require(
        request["attemptID"] == claim["id"] && request["runID"] == .string(session.runID),
        "workflow_extraction_request", "Use this worker's retained preparation request.")
      try validateWorkflowExtractionRequest(request)
    }
    try require(
      try worker.workflowIdentity(cancellation: cancellation) == request["worker"],
      "workflow_extraction_worker", "The document preparation helper changed. Retry the step.")
    let file = try assetURL(request["assetID"].text, verify: true, cancellation: cancellation)
    let result = try worker.extract(file, cancellation: cancellation)
    _ = try assetURL(request["assetID"].text, verify: true, cancellation: cancellation)
    try require(
      try worker.workflowIdentity(cancellation: cancellation) == request["worker"],
      "workflow_extraction_worker", "The document preparation helper changed during parsing.")
    try cancellation.check()
    return .object(["request": request, "result": try encoded(result)])
  }

  func validateWorkflowExtractionRequest(_ request: Value) throws {
    let saved = try db.execute(
      "SELECT kind,result FROM operations WHERE id=?", [request["requestID"]]
    ).first
    try require(
      saved?["kind"] == .string("workflow_extraction_request")
        && (try saved?["result"]?.string.map(Value.parse)) == request
        && request["workbookID"] == .string(id)
        && request["requestID"] == .string("workflow-extraction:" + request["attemptID"].text)
        && request["parser"] == .string(DefinitionExtraction.parser)
        && request["policy"] == .string("workflow-included-document-v1"),
      "workflow_extraction_request", "Use the exact retained document preparation request.")
    try ExtractionWorker.validateWorkflowIdentity(request["worker"])
    let item = try self.item(request["itemID"].text)
    let asset = try self.asset(request["assetID"].text)
    try require(
      item.id == request["itemID"].text && item.isBusinessEvidence
        && item.assetID == asset.id && asset.hash == request["assetHash"].text
        && asset.mode == "included",
      "workflow_extraction_request", "The document preparation input changed.")
  }

  func insertWorkflowExtraction(
    _ envelope: Value, run: Value, step: DefinitionWorkflow.Step, arguments: Value,
    attemptID: String, cancellation: Cancellation
  ) throws -> Value {
    let request = envelope["request"]
    try validateWorkflowExtractionRequest(request)
    try require(
      request["runID"] == run["id"] && request["stepID"] == .string(step.id)
        && request["attemptID"] == .string(attemptID)
        && request["definitionID"] == .string(step.binding!.target)
        && request["arguments"] == arguments,
      "workflow_extraction_request", "The document result belongs to another workflow step.")
    let extraction = try JSONDecoder().decode(
      ExtractionResult.self, from: Data(envelope["result"].json().utf8))
    try extraction.validate()
    try insertIndex(
      request["itemID"].text, chunks: extraction.chunks, state: extraction.state,
      detail: extraction.detail, parser: request["parser"].text,
      cancellation: cancellation, expectedAttemptID: attemptID)
    let set = try fileReferenceSet(request["itemID"].text)!
    let input = try fileReferenceInput(set["input_id"]!.text)
    let complete = extraction.state == "ready" && input["truncated"] == .number(0)
    return .object([
      "kind": .string("extraction"), "definitionID": request["definitionID"],
      "request": request, "itemID": request["itemID"], "assetHash": request["assetHash"],
      "snapshotID": set["id"]!, "extractionInputID": input["id"]!,
      "extractionContentHash": input["content_hash"]!, "state": .string(extraction.state),
      "complete": .bool(complete),
      "detail": .string(
        extraction.detail
          + (input["truncated"] == .number(0)
            ? "" : " Retained text is truncated; select a smaller complete document.")),
      "coverage": .string("Retained extracted text only. Check original content and OCR accuracy."),
    ])
  }

  func validateWorkflowExtractionOutput(
    _ value: Value, runID: String, step: DefinitionWorkflow.Step
  )
    throws
  {
    let request = value["request"]
    try validateWorkflowExtractionRequest(request)
    let definition = try applicationDefinition(step.binding!.target)
    let extraction = try DefinitionExtraction(DefinitionDescriptor(definition.content))
    let input = try fileReferenceInput(value["extractionInputID"].text)
    let set = try fileReferenceSet(value["itemID"].text, snapshotID: value["snapshotID"].text)
    try require(
      request["runID"] == .string(runID) && request["stepID"] == .string(step.id)
        && request["definitionID"] == .string(definition.id)
        && value["definitionID"] == request["definitionID"]
        && request["arguments"][extraction.file] == value["itemID"]
        && value["itemID"] == request["itemID"] && value["assetHash"] == request["assetHash"]
        && input["origin_id"] == value["itemID"] && input["asset_hash"] == value["assetHash"]
        && input["asset_id"] == request["assetID"]
        && input["extraction_parser"] == request["parser"]
        && input["content_hash"] == value["extractionContentHash"]
        && input["extraction_state"] == value["state"] && set?["input_id"] == input["id"]
        && value["complete"]
          == .bool(
            input["extraction_state"] == .string("ready") && input["truncated"] == .number(0)),
      "workflow_integrity", "Document preparation lost its exact retained extraction.")
  }
}
