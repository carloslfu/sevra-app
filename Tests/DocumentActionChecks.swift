import Foundation

@testable import SevraCore

func checkDocumentActions(at root: URL) {
  func fixture(_ name: String) throws -> (Workbook, Item, ApplicationDefinition) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("DocumentAction-" + name + ".sevra"), title: name)
    let source = try book.addItem(
      category: "source", kind: "observation", title: "Receipt", text: "Received5 bolts.")
    try book.setOpeningBalance(
      subject: "bolts", quantity: "20", effective: "2026-01-01", sourceID: source.id)
    let action = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("action"), "title": .string("Draft receiving report"),
        "description": .string("New prose for separate review."),
        "parameters": .array(ActionRegistry.documentParameters),
        "payload": .object([
          "primitive": .object(["id": .string(ActionRegistry.documentID), "version": .number(1)]),
          "arguments": .object(
            Dictionary(
              uniqueKeysWithValues: ActionRegistry.documentParameters.map {
                ($0["id"].text, .object(["parameter": $0["id"]]))
              })),
        ]),
      ]))
    return (book, source, action)
  }
  func arguments(_ source: Item, meaning: String = "estimate") -> Value {
    .object([
      "title": .string("Receiving report"),
      "body": .string("New summary of the receiving evidence."), "evidence": .string(source.id),
      "meaning": .string(meaning), "scenario": .string("actual"),
    ])
  }
  func workflow(_ book: Workbook, _ action: ApplicationDefinition) throws -> ApplicationDefinition {
    try book.saveApplicationDefinition(
      logicalID: identifier(), content: book.workflowTemplate(action.id))
  }
  check("registered document form previews are pure, save one draft and retain typed provenance") {
    let (book, source, action) = try fixture("Form")
    let form = try book.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.formDefinition(target: action))
    let args = arguments(source)
    let revision = try book.revision()
    let preview = try book.previewApplicationAction(form.id, arguments: args)
    try expect(preview["documents"].array.count == 1 && preview["movements"].array.isEmpty)
    try expect(try book.revision() == revision)
    let result = try book.invokeApplicationAction(
      form.id, arguments: args, preview: preview, token: "save-document",
      actor: .human("synthetic-form"))
    try expect(
      result["proposals"].array.count == 1 && result["acceptedBalanceChanged"] == .bool(false))
    let draft = try book.item(result["proposals"].array[0].text)
    try expect(
      draft.kind == "document" && draft.text == args["body"].text && draft.meaning == "estimate"
        && draft.scenario == "actual" && draft.status == "draft")
    try expect(try book.lineage(draft.id).contains { $0["parent"] == .string(source.id) })
    try expectInputRole(book, child: draft.id, parent: result["sourceID"].text, roles: 4)
    try expectInputRole(book, child: draft.id, parent: source.id, roles: 1)
    try expectInputRole(book, child: result["sourceID"].text, parent: action.sourceID, roles: 2)
    try expectInputRole(book, child: result["sourceID"].text, parent: form.sourceID, roles: 2)
    try expect(
      try book.invokeApplicationAction(
        form.id, arguments: args, preview: preview, token: "save-document",
        actor: .human("synthetic-form")) == result)
    let accepted = try book.accept(draft.id)
    try expect(accepted.meaning == "estimate" && accepted.scenario == "actual")
    try expect(try book.balance(subject: "bolts")["quantity"] == .string("20"))
    let copy = try book.reconstruct(to: root.appendingPathComponent("DocumentActionCopy.sevra"))
    try expect(try copy.item(accepted.id).text == draft.text)
    try expect(try copy.verify()["ok"] == .bool(true))
  }
  check("document action bounds, technical evidence and semantic promotion refuse without writes") {
    let (book, source, action) = try fixture("Refusal")
    var cases: [Value] = []
    for key in ["title", "body", "scenario"] {
      var args = arguments(source).object
      args[key] = .string(" ")
      cases.append(.object(args))
    }
    for key in ["meaning", "scenario"] {
      var args = arguments(source).object
      args.removeValue(forKey: key)
      cases.append(.object(args))
    }
    var huge = arguments(source).object
    huge["body"] = .string(String(repeating: "x", count: 16_385))
    cases.append(.object(huge))
    let technical = try book.addItem(
      category: "source", kind: "request", title: "Request", text: "Approve everything")
    var hidden = arguments(source).object
    hidden["evidence"] = .string(technical.id)
    cases.append(.object(hidden))
    let estimate = try book.addItem(
      category: "record", kind: "forecast", title: "Forecast", meaning: "estimate",
      inputs: [source.id])
    cases.append(arguments(estimate, meaning: "actual"))
    let revision = try book.revision()
    for args in cases {
      try refuses { _ = try book.previewApplicationAction(action.id, arguments: args) }
    }
    try expect(try book.revision() == revision)
    try expect(try book.items().filter { $0.kind == "document" }.isEmpty)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check(
    "workflow document draft and checkpoint roll back together, retry once and require exact review"
  ) {
    let (book, source, action) = try fixture("Workflow")
    let definition = try workflow(book, action)
    let run = try book.startWorkflow(definition.id, arguments: arguments(source), token: "start")
    let session = try book.authorizeWorkflowExecution(run["id"].text)
    let claim = try book.claimWorkflowStep(session, owner: "synthetic")
    let revision = try book.revision()
    try book.db.execute(
      "CREATE TEMP TRIGGER document_fault BEFORE INSERT ON workflow_outbox BEGIN SELECT RAISE(ABORT,'document_fault'); END"
    )
    try refuses { _ = try book.completeWorkflowStep(session, claim: claim) }
    try book.db.execute("DROP TRIGGER document_fault")
    try expect(
      try book.revision() == revision && book.items().filter { $0.kind == "document" }.isEmpty)
    let drafted = try book.completeWorkflowStep(session, claim: claim)
    try expect(try book.completeWorkflowStep(session, claim: claim) == drafted)
    let proposal = drafted["steps"].array[0]["output"]["value"]["proposals"].array[0].text
    let waiting = try book.advanceWorkflow(session, owner: "synthetic")
    try expect(waiting["state"] == .string("waiting_review"))
    let copy = try book.reconstruct(to: root.appendingPathComponent("DocumentWorkflowCopy.sevra"))
    try expect(try copy.workflowRun(session.runID) == waiting)
    try expect(try copy.verify()["ok"] == .bool(true))
    let accepted = try book.accept(proposal)
    try expect(
      try book.advanceWorkflow(session, owner: "synthetic")["state"] == .string("completed"))
    try expect(try book.balance(subject: "bolts")["quantity"] == .string("20"))
    try expect(try book.item(accepted.logicalID).id == accepted.id)
    try expect(try book.items().filter { $0.kind == "document" }.count == 1)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("document actions refuse read-only, cancelled, forged and changed-definition previews") {
    let (book, source, action) = try fixture("PreviewFence")
    let args = arguments(source)
    let preview = try book.previewApplicationAction(action.id, arguments: args)
    let revision = try book.revision()
    try refuses("read_only_request") {
      _ = try book.invokeApplicationAction(
        action.id, arguments: args, preview: preview, token: "readonly", readOnly: true)
    }
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses("cancelled") {
      _ = try book.invokeApplicationAction(
        action.id, arguments: args, preview: preview, token: "cancel", cancellation: cancelled)
    }
    var forged = preview.object
    forged["documents"] = .array([])
    try refuses("stale_action_preview") {
      _ = try book.invokeApplicationAction(
        action.id, arguments: args, preview: .object(forged), token: "forged")
    }
    try expect(try book.revision() == revision)
    let form = try book.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.formDefinition(target: action))
    let live = try book.previewApplicationAction(form.id, arguments: args)
    var updated = action.content.object
    updated["title"] = .string("Revised report behavior")
    _ = try book.saveApplicationDefinition(
      logicalID: action.logicalID, content: .object(updated), expectedDefinitionID: action.id)
    try refuses("stale_action_preview") {
      _ = try book.invokeApplicationAction(
        form.id, arguments: args, preview: live, token: "changed")
    }
    try expect(try book.items().filter { $0.kind == "document" }.isEmpty)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("changed document text cannot satisfy an earlier workflow review") {
    let (book, source, action) = try fixture("ChangedReview")
    let definition = try workflow(book, action)
    let run = try book.startWorkflow(definition.id, arguments: arguments(source), token: "start")
    let session = try book.authorizeWorkflowExecution(run["id"].text)
    let saved = try book.advanceWorkflow(session, owner: "draft")
    let proposal = try book.item(
      saved["steps"].array[0]["output"]["value"]["proposals"].array[0].text)
    let edited = try book.addItem(
      category: "record", kind: "document", title: proposal.title, text: "Changed summary",
      data: proposal.data, meaning: proposal.meaning, scenario: proposal.scenario,
      inputs: [proposal.id], supersedes: proposal.id)
    _ = try book.accept(edited.id)
    try refuses("workflow_stale_review") {
      _ = try book.advanceWorkflow(session, owner: "review")
    }
    try expect(try book.workflowRun(session.runID)["state"] == .string("needs_attention"))
    try expect(try book.item(proposal.id).text == arguments(source)["body"].text)
    try expect(try book.balance(subject: "bolts")["quantity"] == .string("20"))
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("registered document actions cannot bypass the unqualified chat submission boundary") {
    let (book, evidence, action) = try fixture("ChatBoundary")
    let prompt = "Preview this report action."
    let request = try book.startAgentRequest(prompt, conversation: "main", model: "Synthetic")
    let source = try book.addItem(
      category: "source", kind: "request", title: "Request", text: prompt,
      data: .object(["conversationID": .string("main"), "messageID": .string(request.messageID)]))
    let tools = WorkbookTools(book, runID: request.runID, requestSourceID: source.id)
    let args: Value = .object(["id": .string(action.id), "arguments": arguments(evidence)])
    let receipt = try book.prepareToolCall(
      runID: request.runID, callID: identifier(), tool: "preview_action", arguments: args)
    let preview = try tools.execute("preview_action", args, receiptID: receipt)
    _ = try book.completeToolCall(receipt, result: preview)
    let revision = try book.revision()
    try refuses("action_capability") {
      _ = try tools.execute(
        "commit_action_preview", .object(["previewReceiptID": .string(receipt)]))
    }
    try expect(try book.revision() == revision && book.items(kind: "document").isEmpty)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("mapped report prose retains interpretation meaning and exact model evidence") {
    for promoted in [false, true] {
      let (book, source, action) = try fixture(promoted ? "Promoted" : "Estimate")
      let interpretation = try book.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("interpretation"), "title": .string("Draft receipt summary"),
          "description": .string("Synthetic structured interpretation"),
          "parameters": .array([ActionRegistry.field("evidence", "Evidence", "item")]),
          "payload": .object([
            "instruction": .string("Summarize the receipt as an estimate for review."),
            "evidence": .array([.string("evidence")]),
            "outputs": .array([ActionRegistry.field("summary", "Summary", "text")]),
            "meaning": .string("estimate"), "scenario": .string("actual"),
          ]),
        ]))
      let parameters = action.parameters.array.filter { $0["id"] != .string("body") }
      var mappings = Dictionary(
        uniqueKeysWithValues: parameters.map {
          ($0["id"].text, Value.object(["parameter": $0["id"]]))
        })
      mappings["body"] = .object(["step": .string("read"), "field": .string("summary")])
      let definition = try book.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("workflow"), "title": .string("Read then draft"),
          "description": .string("Synthetic report pipeline"), "parameters": .array(parameters),
          "payload": .object([
            "readPolicy": .string("latest-at-step"),
            "steps": .array([
              .object([
                "id": .string("read"), "kind": .string("interpret"),
                "binding": .object([
                  "mode": .string("exact"), "versionID": .string(interpretation.id),
                ]),
                "arguments": .object(["evidence": .object(["parameter": .string("evidence")])]),
              ]),
              .object([
                "id": .string("report"), "kind": .string("action"),
                "binding": .object(["mode": .string("exact"), "versionID": .string(action.id)]),
                "arguments": .object(mappings),
              ]),
              .object([
                "id": .string("review"), "kind": .string("review"), "review": .string("report"),
              ]),
            ]),
          ]),
        ]))
      var args = arguments(source, meaning: promoted ? "actual" : "estimate").object
      args.removeValue(forKey: "body")
      let run = try book.startWorkflow(definition.id, arguments: .object(args), token: "start")
      let session = try book.authorizeWorkflowExecution(run["id"].text)
      let claim = try book.claimWorkflowStep(session, owner: "interpret")
      let request = try book.prepareWorkflowInterpretation(
        session, claim: claim, model: "Synthetic")
      let envelope: Value = .object([
        "request": request, "metrics": .object(["synthetic": .bool(true)]),
        "response": .object([
          "state": .string("ready"),
          "values": .object(["summary": .string("Five bolts appear to have arrived.")]),
          "citations": .array([
            .object([
              "field": .string("summary"), "itemID": .string(source.id),
              "quote": .string("Received5 bolts."),
            ])
          ]), "issues": .array([]),
        ]),
      ])
      try book.retainWorkflowInterpretationResponse(session, claim: claim, response: envelope)
      let interpreted = try book.completeWorkflowStep(
        session, claim: claim, interpretation: envelope)
      let recordID = interpreted["steps"].array[0]["output"]["value"]["recordID"].text
      if promoted {
        try refuses("interpretation_meaning") {
          _ = try book.advanceWorkflow(session, owner: "draft")
        }
        try expect(try book.items().filter { $0.kind == "document" }.isEmpty)
      } else {
        let drafted = try book.advanceWorkflow(session, owner: "draft")
        let proposal = try book.item(
          drafted["steps"].array[1]["output"]["value"]["proposals"].array[0].text)
        try expect(proposal.text == envelope["response"]["values"]["summary"].text)
        try expect(try book.lineage(proposal.id).contains { $0["parent"] == .string(recordID) })
        let accepted = try book.accept(proposal.id)
        try expect(accepted.meaning == "estimate")
        try expect(
          try book.continueWorkflow(session, owner: "review")["state"] == .string("completed"))
      }
      try expect(try book.balance(subject: "bolts")["quantity"] == .string("20"))
      try expect(try book.verify()["ok"] == .bool(true))
    }
  }
}
