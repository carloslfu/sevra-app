import Foundation

@testable import SevraCore

func checkDefinitionTools(at root: URL) {
  func setup(_ name: String) throws -> (Workbook, AgentRequest, Item, WorkbookTools) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("DefinitionTools-" + name + ".sevra"), title: name)
    let prompt = "Save a note action and draft a note about quote R1."
    let request = try book.startAgentRequest(
      prompt, conversation: book.startChat, model: "synthetic definition tools")
    let source = try book.addItem(
      category: "source", kind: "request", title: "Current request", text: prompt,
      data: .object(["conversationID": .string(book.startChat), "messageID": .string(request.messageID)]))
    return (
      book, request, source, WorkbookTools(book, runID: request.runID, requestSourceID: source.id)
    )
  }
  let note = ActionRegistry.documentDefinition(
    title: "Draft a supplier note", description: "Draft a note from a quote")
  func call(_ book: Workbook, _ tools: WorkbookTools, _ name: String, _ args: Value) throws -> (
    String, Value
  ) {
    let receipt = try book.prepareToolCall(
      runID: tools.runID, callID: identifier(), tool: name, arguments: args)
    let result = try tools.execute(name, args, receiptID: receipt)
    _ = try book.completeToolCall(receipt, result: result)
    return (receipt, result)
  }
  check(
    "agent definition authoring has stable create identity, exact base, actual AI request lineage and read-only refusal"
  ) {
    let (book, request, source, tools) = try setup("Authoring")
    let args: Value = .object(["content": note])
    let first = try call(book, tools, "save_definition", args).1
    let saved = try book.applicationDefinition(first["id"].text)
    let revision = try book.revision()
    try expect(try tools.execute("save_definition", args) == first)
    try expect(try book.revision() == revision)
    let provenance = try book.item(saved.sourceID)
    try expect(provenance.data["actor"]["kind"] == .string("ai"))
    try expect(provenance.data["actor"]["model"] == .string("synthetic definition tools"))
    try expect(try book.lineage(saved.sourceID).contains { $0["parent"] == .string(source.id) })
    let read = try tools.execute(
      "read_definition", .object(["id": .string(saved.id)]))
    try expect(read["content"] == note)
    try refuses("item_scope") {
      _ = try tools.execute("read", .object(["id": .string(saved.sourceID)]))
    }
    try expect(try book.item(saved.sourceID).id == saved.sourceID)
    try expect(try book.search("supplier note").hits.isEmpty)
    try expect(
      try book.search("supplier note", kind: "application_definition").hits.contains {
        $0.itemID == saved.sourceID
      })
    try expect(try book.recentItemSummaries().allSatisfy { $0.id != saved.sourceID })
    try refuses("definition_binding") {
      _ = try tools.execute(
        "read_definition", .object(["id": .string(saved.logicalID)]))
    }
    let readOnly = WorkbookTools(
      book, runID: request.runID, requestSourceID: source.id, readOnly: true)
    try refuses("read_only_request") { _ = try readOnly.execute("save_definition", args) }
    var content = saved.content.object
    content["title"] = .string("Supplier note v2")
    let edit: Value = .object([
      "expectedDefinitionID": .string(saved.id),
      "content": .object(content),
    ])
    let second = try tools.execute("save_definition", edit)
    try expect(second["version"] == .number(2))
    var conflicting = edit.object
    conflicting["content"] = saved.content
    try refuses("stale_definition") {
      _ = try tools.execute("save_definition", .object(conflicting))
    }
    // An edit base that names nothing saves a new definition, unless one of that kind already
    // has the title, which the refusal names.
    let invented = identifier()
    var fresh = saved.content.object
    fresh["title"] = .string("Customer note")
    let made = try tools.execute(
      "save_definition",
      .object(["expectedDefinitionID": .string(invented), "content": .object(fresh)]))
    try expect(made["version"] == .number(1) && made["id"].text != invented)
    try refuses("definition_not_found") {
      _ = try tools.execute(
        "save_definition",
        .object(["expectedDefinitionID": .string(identifier()), "content": .object(content)]))
    }
    _ = try book.verify()
  }
  check(
    "agent action previews bind to the current run, and chat cannot submit a document action"
  ) {
    let (book, request, source, tools) = try setup("Receipts")
    let action = try book.saveApplicationDefinition(
      logicalID: identifier(), content: note)
    let evidence = try book.addItem(
      category: "source", kind: "observation", title: "R1",
      text: "Quote R1: three bolts at 2.40 each.")
    let input = noteArguments(evidence.id, title: "Quote R1", meaning: "estimate")
    let previewArgs: Value = .object(["id": .string(action.id), "arguments": input])
    let prepared = try book.prepareToolCall(
      runID: request.runID, callID: "prepared-preview", tool: "preview_action",
      arguments: previewArgs)
    try refuses("action_preview_receipt") {
      _ = try book.applicationPreviewForRun(
        prepared, runID: request.runID, conversation: book.startChat, requestSourceID: source.id)
    }
    let (receipt, preview) = try call(book, tools, "preview_action", previewArgs)
    try expect(
      try book.applicationPreviewForRun(
        receipt, runID: request.runID, conversation: book.startChat, requestSourceID: source.id)
        == preview["plan"])
    let (wrongTool, _) = try call(
      book, tools, "find_definitions", .object(["query": .string("")]))
    try refuses("action_preview_receipt") {
      _ = try book.applicationPreviewForRun(
        wrongTool, runID: request.runID, conversation: book.startChat, requestSourceID: source.id)
    }
    // A document action is submitted through its form or workflow, never straight from chat.
    let submit: Value = .object(["previewReceiptID": .string(receipt)])
    let revision = try book.revision()
    try refuses("action_capability") { _ = try tools.execute("commit_action_preview", submit) }
    try expect(try book.revision() == revision && book.items(kind: "document").isEmpty)
    let other = try book.startAgentRequest(
      "Another request", conversation: book.startChat, model: "synthetic")
    let otherSource = try book.addItem(
      category: "source", kind: "request", title: "Other", text: "Another request",
      data: .object(["conversationID": .string(book.startChat), "messageID": .string(other.messageID)]))
    try refuses("action_preview_receipt") {
      _ = try book.applicationPreviewForRun(
        receipt, runID: other.runID, conversation: book.startChat, requestSourceID: otherSource.id)
    }
    try refuses("action_run") {
      _ = try book.applicationPreviewForRun(
        receipt, runID: request.runID, conversation: book.startChat, requestSourceID: source.id)
    }
    try refuses("action_run") {
      _ = try book.applicationPreviewForRun(
        receipt, runID: other.runID, conversation: "another-conversation",
        requestSourceID: otherSource.id)
    }
    _ = try book.verify()
  }
  check(
    "agent template saves copy exact current-run content, allow only title override and refuse foreign or incomplete receipts"
  ) {
    let (book, request, source, tools) = try setup("Templates")
    let action = try book.saveApplicationDefinition(logicalID: identifier(), content: note)
    let templateArguments: Value = .object(["id": .string(action.id)])
    let (templateID, template) = try call(book, tools, "form_template", templateArguments)
    let arguments: Value = .object([
      "templateReceiptID": .string(templateID), "title": .string("Quote notes"),
    ])
    let saved = try tools.execute("save_template", arguments)
    var expected = ActionRegistry.formDefinition(target: action).object
    expected["title"] = .string("Quote notes")
    try expect(try book.applicationDefinition(saved["id"].text).content == .object(expected))
    try expect(try tools.execute("save_template", arguments) == saved)
    try expect(template["content"] == ActionRegistry.formDefinition(target: action))
    try expect(
      saved["kind"] == .string("form") && saved["nativeComponent"]["type"] == .string("form"))
    try refuses("arguments") {
      _ = try tools.execute(
        "save_template",
        .object([
          "templateReceiptID": .string(templateID), "content": template["content"],
        ]))
    }
    let prepared = try book.prepareToolCall(
      runID: request.runID, callID: identifier(), tool: "form_template",
      arguments: templateArguments)
    try refuses("definition_template") {
      _ = try tools.execute("save_template", .object(["templateReceiptID": .string(prepared)]))
    }
    var altered = template.object
    var modifiedContent = template["content"].object
    modifiedContent["title"] = .string("Injected template change")
    altered["content"] = .object(modifiedContent)
    altered["receiptID"] = .string(prepared)
    _ = try book.completeToolCall(prepared, result: .object(altered))
    try refuses("definition_template") {
      _ = try tools.execute("save_template", .object(["templateReceiptID": .string(prepared)]))
    }
    let (wrong, _) = try call(book, tools, "definition_registry", .object([:]))
    try refuses("definition_template") {
      _ = try tools.execute("save_template", .object(["templateReceiptID": .string(wrong)]))
    }
    let readonly = WorkbookTools(
      book, runID: request.runID, requestSourceID: source.id, readOnly: true)
    try refuses("read_only_request") { _ = try readonly.execute("save_template", arguments) }
    let other = try book.startAgentRequest("Other", conversation: book.startChat, model: "synthetic")
    let otherSource = try book.addItem(
      category: "source", kind: "request", title: "Other", text: "Other",
      data: .object(["messageID": .string(other.messageID), "conversationID": .string(book.startChat)]))
    let foreign = WorkbookTools(book, runID: other.runID, requestSourceID: otherSource.id)
    try refuses("definition_template") { _ = try foreign.execute("save_template", arguments) }
    _ = try book.verify()
  }
  check("agent pure evaluation publishes no business data and refuses execution indirection") {
    let (book, _, _, tools) = try setup("Evaluation")
    let value: Value = .object([
      "kind": .string("function"), "title": .string("Double"),
      "description": .string("Decimal multiplication"),
      "parameters": .array([
        .object([
          "id": .string("x"), "label": .string("x"), "type": .string("decimal"),
          "required": .bool(true),
        ])
      ]), "payload": .object(["expression": .string("x*2"), "calls": .array([])]),
    ])
    let saved = try book.saveApplicationDefinition(logicalID: identifier(), content: value)
    let revision = try book.revision()
    let result = try tools.execute(
      "evaluate_definition",
      .object(["id": .string(saved.id), "arguments": .object(["x": .string("2.10")])]))
    try expect(result["result"] == .string("4.2") && result["readOnly"] == .bool(true))
    try expect(try book.revision() == revision)
    let action = try book.saveApplicationDefinition(
      logicalID: identifier(), content: note)
    try refuses("definition_kind") {
      _ = try tools.execute(
        "evaluate_definition", .object(["id": .string(action.id), "arguments": .object([:])]))
    }
    _ = try book.verify()
  }
  check(
    "failed or altered preview receipts and changed live bindings cannot publish action proposals"
  ) {
    let (book, request, source, tools) = try setup("PreviewGuards")
    let action = try book.saveApplicationDefinition(
      logicalID: identifier(), content: note)
    let form = try book.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.formDefinition(target: action))
    let evidence = try book.addItem(
      category: "source", kind: "observation", title: "R1", text: "Quote R1.")
    let input = noteArguments(evidence.id, title: "Quote R1", meaning: "estimate")
    let args: Value = .object(["id": .string(form.id), "arguments": input])
    let failedID = try book.prepareToolCall(
      runID: request.runID, callID: "failed", tool: "preview_action", arguments: args)
    let failedPlan = try tools.execute("preview_action", args, receiptID: failedID)
    _ = try book.completeToolCall(failedID, result: failedPlan, failed: true)
    try refuses("action_preview_receipt") {
      _ = try book.applicationPreviewForRun(
        failedID, runID: request.runID, conversation: book.startChat, requestSourceID: source.id)
    }
    let alteredID = try book.prepareToolCall(
      runID: request.runID, callID: "altered", tool: "preview_action", arguments: args)
    var altered = try tools.execute("preview_action", args, receiptID: alteredID).object
    var plan = altered["plan"]!.object
    plan["title"] = .string("Changed after preview")
    altered["plan"] = .object(plan)
    _ = try book.completeToolCall(alteredID, result: .object(altered))
    try refuses("integrity") {
      _ = try book.applicationPreviewForRun(
        alteredID, runID: request.runID, conversation: book.startChat, requestSourceID: source.id)
    }
    let (validID, valid) = try call(book, tools, "preview_action", args)
    var changed = action.content.object
    changed["description"] = .string("Edited live definition")
    _ = try book.saveApplicationDefinition(
      logicalID: action.logicalID, content: .object(changed), expectedDefinitionID: action.id)
    try refuses("action_capability") {
      _ = try tools.execute(
        "commit_action_preview", .object(["previewReceiptID": .string(validID)]))
    }
    try refuses("stale_action_preview") {
      _ = try book.invokeApplicationAction(
        form.id, arguments: input, preview: valid["plan"], token: "stale")
    }
    try expect(
      try book.items(kind: "document").isEmpty && book.items(kind: "application_invocation").isEmpty
    )
    try book.finishAgentRun(request.runID, status: "cancelled", steps: 0, metrics: .array([]))
    try refuses("action_run") {
      _ = try book.invokeApplicationAction(
        form.id, arguments: input, preview: valid["plan"], token: "late",
        requestSourceID: source.id, requestRunID: request.runID)
    }
    _ = try book.verify()
  }
  check(
    "catalog and saved query pages survive their own agent receipts but refuse actual definition/data changes"
  ) {
    let (book, _, source, tools) = try setup("Paging")
    for index in 0..<13 {
      var content = note.object
      content["title"] = .string("Supplier note \(index)")
      _ = try book.saveApplicationDefinition(logicalID: identifier(), content: .object(content))
    }
    let table = try book.createDataset(
      title: "Counts", columns: [.init(id: "count", title: "Count", type: "decimal")],
      rows: [["count": .string("1")], ["count": .string("2")]], sourceID: source.id)
    let content: Value = .object([
      "kind": .string("query"), "title": .string("Counts page"),
      "description": .string("One current row per page"), "parameters": .array([]),
      "payload": .object([
        "dataMode": .string("live"),
        "query": .object([
          "sources": .array([
            .object(["datasetID": .string(table.id), "definitionID": .string(table.definitionID)])
          ]),
          "select": .array([
            .object([
              "id": .string("count"),
              "column": .object(["source": .number(0), "column": .string("count")]),
            ])
          ]), "limit": .number(1),
        ]),
      ]),
    ])
    let query = try book.saveApplicationDefinition(logicalID: identifier(), content: content)
    let first = try call(
      book, tools, "find_definitions", .object(["query": .string("")])
    ).1
    let next = try call(
      book, tools, "find_definitions",
      .object(["query": .string(""), "cursor": first["nextCursor"]])
    ).1
    try expect(first["hits"].array.count == 12 && next["hits"].array.count == 2)
    let queryArgs: Value = .object(["id": .string(query.id), "arguments": .object([:])])
    let page = try call(book, tools, "evaluate_definition", queryArgs).1
    var continued = queryArgs.object
    continued["cursor"] = page["nextCursor"]
    let second = try call(book, tools, "evaluate_definition", .object(continued)).1
    try expect(second["result"]["rows"].array.count == 1 && second["nextCursor"] == .null)
    _ = try book.addItem(category: "source", kind: "observation", title: "New business evidence")
    try refuses("stale_query") { _ = try tools.execute("evaluate_definition", .object(continued)) }
    _ = try book.saveApplicationDefinition(
      logicalID: identifier(), content: note)
    try refuses("stale_definition_search") {
      _ = try tools.execute(
        "find_definitions",
        .object([
          "query": .string(""), "cursor": first["nextCursor"],
        ]))
    }
    let reconstructed = try book.reconstruct(
      to: root.appendingPathComponent("DefinitionTools-Reconstructed.sevra"))
    try expect(try reconstructed.verify()["ok"] == .bool(true))
    _ = try book.verify()
  }
  check(
    "result publication uses this active run's intact completed evaluation and refuses other receipts"
  ) {
    let (book, request, source, tools) = try setup("Publication")
    let definition = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("function"), "title": .string("Constant count"),
        "description": .string("Synthetic"),
        "parameters": .array([]),
        "payload": .object(["expression": .string("2*3"), "calls": .array([])]),
      ]))
    let args: Value = .object(["id": .string(definition.id), "arguments": .object([:])])
    let prepared = try book.prepareToolCall(
      runID: request.runID, callID: "pending-evaluation", tool: "evaluate_definition",
      arguments: args)
    func publish(_ receipt: String) throws -> Value {
      try tools.execute(
        "publish_result",
        .object([
          "evaluationReceiptID": .string(receipt), "title": .string("Count result"),
          "meaning": .string("estimate"),
        ]))
    }
    try refuses("definition_evaluation") { _ = try publish(prepared) }
    _ = try book.completeToolCall(
      prepared, result: .object(["error": .string("failure")]), failed: true)
    try refuses("definition_evaluation") { _ = try publish(prepared) }
    let wrong = try call(book, tools, "read_definition", .object(["id": .string(definition.id)])).0
    try refuses("definition_evaluation") { _ = try publish(wrong) }
    let (receipt, evaluation) = try call(book, tools, "evaluate_definition", args)
    try expect(evaluation["receiptID"] == .string(receipt))
    try expect(evaluation["snapshot"] != .string(receipt))
    let readOnly = WorkbookTools(
      book, runID: request.runID, requestSourceID: source.id, readOnly: true)
    try refuses("read_only_request") {
      _ = try readOnly.execute(
        "publish_result",
        .object([
          "evaluationReceiptID": .string(receipt), "title": .string("Count"),
          "meaning": .string("actual"),
        ]))
    }
    let result = try publish(receipt)
    try expect(result["status"] == .string("draft") && result["meaning"] == .string("estimate"))
    try expect(result["data"]["evaluation"]["receiptID"] == .null)
    let lineage = try book.lineage(result["id"].text)
    try expect(lineage.contains { $0["parent"] == .string(source.id) })
    let invocation = try lineage.map { try book.item($0["parent"].text) }.first {
      $0.kind == "application_invocation"
    }!
    try expect(invocation.data["actor"]["kind"] == .string("ai"))
    try expect(try publish(receipt)["id"] == result["id"])
    let tamper = Process()
    tamper.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    tamper.arguments = [
      book.url.appendingPathComponent("workbook.sqlite").path,
      "UPDATE tool_calls SET result='{}' WHERE id='\(receipt)';",
    ]
    try tamper.run()
    tamper.waitUntilExit()
    try expect(tamper.terminationStatus == 0)
    try refuses("integrity") { _ = try publish(receipt) }
    let other = try book.startAgentRequest(
      "Inspect this result", conversation: book.startChat, model: "synthetic")
    let otherSource = try book.addItem(
      category: "source", kind: "request", title: "Current request", text: "Inspect this result",
      data: .object(["conversationID": .string(book.startChat), "messageID": .string(other.messageID)]))
    let foreign = WorkbookTools(book, runID: other.runID, requestSourceID: otherSource.id)
    try refuses("action_run") { _ = try publish(receipt) }
    try refuses("definition_evaluation") {
      _ = try foreign.execute(
        "publish_result",
        .object([
          "evaluationReceiptID": .string(receipt), "title": .string("Foreign"),
          "meaning": .string("actual"),
        ]))
    }

  }

}
