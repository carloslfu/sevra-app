import Foundation

@testable import SevraCore

func checkWorkflowExtractions(at root: URL) {
  let worker = ExtractionWorker()
  func fixture(_ name: String, interpretation: Bool = false, linked: Bool = false) throws
    -> (Workbook, Item, WorkflowExecutionSession)
  {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Extraction-" + name + ".sevra"), title: name)
    let file = root.appendingPathComponent(name + ".txt")
    try Data("Received5 bolts.".utf8).write(to: file)
    let item = try book.importFile(file, linked: linked)
    try book.index(item.id, chunks: [Chunk("Prior searchable text")], parser: "synthetic-prior")
    let parameter = ActionRegistry.field("file", "Document", "item")
    let extraction = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("extraction"), "title": .string("Prepare document"),
        "description": .string("Synthetic native document preparation"),
        "parameters": .array([parameter]),
        "payload": .object(["parser": .string("native-v1"), "file": .string("file")]),
      ]))
    var steps: [Value] = [
      .object([
        "id": .string("prepare"), "kind": .string("extract"),
        "binding": .object(["mode": .string("exact"), "versionID": .string(extraction.id)]),
        "arguments": .object(["file": .object(["parameter": .string("file")])]),
      ])
    ]
    if interpretation {
      let definition = try book.saveApplicationDefinition(
        logicalID: identifier(), content: WorkbookTools.definitionFormats["interpretationExample"])
      steps.append(
        .object([
          "id": .string("read"), "kind": .string("interpret"),
          "binding": .object(["mode": .string("exact"), "versionID": .string(definition.id)]),
          "arguments": .object([
            "evidence": .object([
              "step": .string("prepare"), "field": .string("item"),
            ])
          ]),
        ]))
    }
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("workflow"), "title": .string(name), "description": .string("Synthetic"),
        "parameters": .array([parameter]),
        "payload": .object(["readPolicy": .string("latest-at-step"), "steps": .array(steps)]),
      ]))
    let run = try book.startWorkflow(
      workflow.id, arguments: .object(["file": .string(item.id)]), token: "start")
    return (book, item, try book.authorizeWorkflowExecution(run["id"].text))
  }
  func prepared(_ book: Workbook, _ session: WorkflowExecutionSession, lease: Double = 30)
    throws -> (Value, Value, Value)
  {
    let claim = try book.claimWorkflowStep(session, owner: "synthetic", leaseSeconds: lease)
    let request = try book.prepareWorkflowExtraction(
      session, claim: claim, worker: worker.workflowIdentity())
    let result = try book.performWorkflowExtraction(session, claim: claim, request: request)
    return (claim, request, result)
  }
  check("document preparation atomically publishes exact searchable text and reconstructs inertly")
  {
    let (book, item, session) = try fixture("Ready")
    let (claim, _, result) = try prepared(book, session)
    try expect(try book.search("Prior").hits.count == 1)
    let complete = try book.completeWorkflowStep(session, claim: claim, extraction: result)
    try expect(complete["state"] == .string("completed"))
    let output = complete["steps"].array[0]["output"]["value"]
    try expect(output["complete"] == .bool(true) && output["itemID"] == .string(item.id))
    try expect(try book.search("Prior").hits.isEmpty)
    try expect(try book.search("Received5").hits.count == 1)
    let revision = try book.revision()
    try expect(try book.completeWorkflowStep(session, claim: claim, extraction: result) == complete)
    try expect(try book.revision() == revision)
    let copy = try book.reconstruct(to: root.appendingPathComponent("ExtractionCopy.sevra"))
    try expect(try copy.workflowRun(session.runID) == complete)
    try expect(try copy.search("Received5").hits.count == 1)
    try refuses("workflow_authority") {
      _ = try copy.performWorkflowExtraction(session, claim: claim, request: result["request"])
    }
    try expect(try book.items().filter { $0.category == "record" }.isEmpty)
    try expect(try copy.verify()["ok"] == .bool(true))
  }
  check("interpretation consumes its prepared extraction after another index becomes current") {
    let (book, item, session) = try fixture("Pinned", interpretation: true)
    let (claim, _, result) = try prepared(book, session)
    let first = try book.completeWorkflowStep(session, claim: claim, extraction: result)
    let input = first["steps"].array[0]["output"]["value"]["extractionInputID"]
    try book.index(item.id, chunks: [Chunk("Changed999")], state: "partial", parser: "later")
    let second = try book.claimWorkflowStep(session, owner: "interpretation")
    let request = try book.prepareWorkflowInterpretation(session, claim: second, model: "synthetic")
    let evidence = request["evidence"].array[0]
    try expect(evidence["extractionInputID"] == input)
    try expect(evidence["extractionStepID"] == .string("prepare"))
    try expect(evidence["content"] == .string("Received5 bolts."))
    let envelope: Value = .object([
      "request": request, "metrics": .object(["synthetic": .bool(true)]),
      "response": .object([
        "state": .string("ready"), "values": .object(["quantity": .string("5")]),
        "citations": .array([
          .object([
            "field": .string("quantity"), "itemID": .string(item.id),
            "quote": .string("Received5 bolts."),
          ])
        ]), "issues": .array([]),
      ]),
    ])
    try book.retainWorkflowInterpretationResponse(session, claim: second, response: envelope)
    let done = try book.completeWorkflowStep(session, claim: second, interpretation: envelope)
    try expect(done["state"] == .string("completed"))
    let copy = try book.reconstruct(to: root.appendingPathComponent("ExtractionPinnedCopy.sevra"))
    try expect(try copy.workflowRun(session.runID) == done)
    try expect(try copy.verify()["ok"] == .bool(true))
  }
  check("stale document requests, cancelled claims and competing indexers cannot publish") {
    for mode in ["forged", "cancelled", "competing", "changed"] {
      let (book, item, session) = try fixture("Refuse-" + mode)
      let (claim, request, result) = try prepared(book, session)
      let expected: String
      var response = result.object
      if mode == "forged" {
        var forged = request.object
        forged["assetHash"] = .string(String(repeating: "a", count: 64))
        response["request"] = .object(forged)
        expected = "workflow_extraction_request"
      } else if mode == "cancelled" {
        _ = try book.cancelWorkflow(session, token: "stop")
        expected = "workflow_fenced"
      } else if mode == "competing" {
        try book.index(item.id, chunks: [Chunk("Prior replacement")])
        expected = "stale_extraction"
      } else {
        let url = try book.assetURL(item.assetID!)
        try Data("Changed file bytes".utf8).write(to: url)
        try refuses("changed_asset") {
          _ = try book.performWorkflowExtraction(session, claim: claim, request: request)
        }
        // Restore the exact owned bytes; preservation remains a useful invariant.
        try Data("Received5 bolts.".utf8).write(to: url)
        continue
      }
      try refuses(expected) {
        _ = try book.completeWorkflowStep(session, claim: claim, extraction: .object(response))
      }
      try expect(try book.search("Prior").hits.count == 1)
      try expect(try book.search("Received5").hits.isEmpty)
      try expect(try book.verify()["ok"] == .bool(true))
    }
  }
  check(
    "failed document checkpoint rolls back index, reference identity and workflow state together"
  ) {
    let (book, item, session) = try fixture("Rollback")
    let old = try book.fileReferenceSet(item.id)!["input_id"]!
    let (claim, _, result) = try prepared(book, session)
    try book.db.execute(
      "CREATE TEMP TRIGGER extraction_fault BEFORE INSERT ON workflow_outbox BEGIN SELECT RAISE(ABORT,'extraction_fault'); END"
    )
    do {
      _ = try book.completeWorkflowStep(session, claim: claim, extraction: result)
      throw SevraError("test", "Faulted document checkpoint committed")
    } catch let error as SevraError { try expect(error.code != "test") }
    try book.db.execute("DROP TRIGGER extraction_fault")
    try expect(try book.fileReferenceSet(item.id)!["input_id"]! == old)
    try expect(try book.search("Prior").hits.count == 1)
    try expect(try book.workflowRun(session.runID)["steps"].array[0]["state"] == .string("claimed"))
    let done = try book.completeWorkflowStep(session, claim: claim, extraction: result)
    try expect(done["state"] == .string("completed"))
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check(
    "partial, unsupported and truncated document output pauses without fabricating completeness"
  ) {
    for state in ["partial", "unsupported", "truncated"] {
      let (book, item, session) = try fixture("Coverage-" + state, interpretation: true)
      let (claim, request, _) = try prepared(book, session)
      let result = ExtractionResult(
        chunks: state == "unsupported"
          ? []
          : [
            Chunk(
              state == "truncated"
                ? String(repeating: "x", count: Workbook.referenceBodyLimit + 4) : "Partial text")
          ],
        state: state == "truncated" ? "ready" : state, detail: "Synthetic coverage limit")
      let done = try book.completeWorkflowStep(
        session, claim: claim,
        extraction: .object(["request": request, "result": try encoded(result)]))
      try expect(done["state"] == .string("needs_attention"))
      try expect(done["steps"].array[0]["output"]["value"]["complete"] == .bool(false))
      try expect(done["steps"].array[1]["state"] == .string("pending"))
      try expect(try book.item(item.id).assetID == item.assetID)
      try expect(try book.items().filter { $0.category == "record" }.isEmpty)
      try expect(try book.verify()["ok"] == .bool(true))
    }
  }
  check("document preparation refuses linked files and cannot start from saved metadata alone") {
    let (book, _, session) = try fixture("Linked", linked: true)
    let claim = try book.claimWorkflowStep(session, owner: "synthetic")
    try refuses("workflow_extraction_scope") {
      _ = try book.prepareWorkflowExtraction(
        session, claim: claim, worker: worker.workflowIdentity())
    }
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("document preparation rejects parser changes, defaults and untyped workflow mappings") {
    let (book, _, session) = try fixture("DefinitionRefusal", interpretation: true)
    let run = try book.workflowRun(session.runID)
    let workflow = try book.applicationDefinition(run["definition_id"].text)
    let original = try book.applicationDefinition(
      workflow.payload["steps"].array[0]["binding"]["versionID"].text)
    for parser in ["unknown", "", "native-v2"] {
      var content = original.content.object
      var payload = original.payload.object
      payload["parser"] = .string(parser)
      content["payload"] = .object(payload)
      try refuses("extraction_definition") {
        _ = try book.saveApplicationDefinition(logicalID: identifier(), content: .object(content))
      }
    }
    var content = original.content.object
    var field = original.parameters.array[0].object
    field["default"] = run["arguments"]["file"]
    content["parameters"] = .array([.object(field)])
    try refuses("extraction_definition") {
      _ = try book.saveApplicationDefinition(logicalID: identifier(), content: .object(content))
    }
    var steps = workflow.payload["steps"].array
    var read = steps[1].object
    read["arguments"] = .object([
      "evidence": .object([
        "step": .string("prepare"), "field": .string("path"),
      ])
    ])
    steps[1] = .object(read)
    content = workflow.content.object
    content["payload"] = .object([
      "readPolicy": .string("latest-at-step"), "steps": .array(steps),
    ])
    try refuses("workflow_mapping") {
      _ = try book.saveApplicationDefinition(logicalID: identifier(), content: .object(content))
    }
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("lease expiry during document checkpoint capture preserves the prior index and history") {
    let (book, item, session) = try fixture("CommitLease")
    let (claim, _, result) = try prepared(book, session)
    _ = try book.heartbeatWorkflowStep(session, claim: claim, leaseSeconds: 0.25)
    let history = try book.committedHistory(limit: 1000)
    try refuses("workflow_fenced") {
      _ = try WorkflowPublicationProbe.$observer.withValue({ stage, _ in
        if stage == .prepared { Thread.sleep(forTimeInterval: 0.35) }
      }) { try book.completeWorkflowStep(session, claim: claim, extraction: result) }
    }
    try expect(try book.committedHistory(limit: 1000) == history)
    try expect(try book.search("Prior").hits.count == 1)
    try expect(try book.extractionStatus(item.id)["parser"] == .string("synthetic-prior"))
    try expect(try book.workflowRun(session.runID)["steps"].array[0]["output"] == .null)
    try expect(try book.verify()["ok"] == .bool(true))
  }
}
