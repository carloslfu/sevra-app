import Foundation

@testable import SevraCore

/// The `tools.run` action primitive: a saved action, a form, a workflow step and chat each run
/// a saved tool through the button's path, recorded, with one Undo.
func checkToolActions(at root: URL) {
  struct Shop {
    let book: Workbook
    let tool: ApplicationDefinition
    let parts: Dataset
  }
  func shop(_ name: String) throws -> Shop {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ToolAction-" + name + ".sevra"), title: name)
    let source = try book.addItem(
      category: "source", kind: "observation", title: "Parts list", status: "accepted")
    let parts = try book.createDataset(
      title: "Parts",
      columns: [
        .init(id: "name", title: "Name"), .init(id: "qty", title: "Qty", type: "decimal"),
      ], rows: [["name": .string("bolts"), "qty": .string("20")]], sourceID: source.id)
    _ = try book.chatSaveTool(
      name: "add_part", description: "Adds a part with its quantity.",
      inputs: [("name", "text"), ("qty", "decimal")],
      statements: ["INSERT INTO parts (name, qty) VALUES (:name, :qty)"], source: nil,
      token: "save-add-part", requestSourceID: nil)
    let tool = try book.applicationDefinition(
      try book.savedTools().first { $0.name == "add_part" }!.definitionID)
    return Shop(book: book, tool: tool, parts: parts)
  }
  func rows(_ shop: Shop) throws -> [String] {
    try shop.book.rows(shop.parts.id).map { $0.data["name"].text }.sorted()
  }
  let input: Value = .object(["name": .string("nuts"), "qty": .string("5")])

  check("a form on a saved tool adds a row once, with one Undo, and an exact retry returns its receipt") {
    let shop = try shop("Form")
    let b = shop.book
    let action = try b.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.toolActionDefinition(tool: shop.tool))
    let form = try b.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.formDefinition(target: action))
    let revision = try b.revision()
    let preview = try b.previewApplicationAction(form.id, arguments: input)
    try expect(
      preview["tool"]["name"] == .string("add_part") && preview["documents"] == .null
        && b.revision() == revision)
    try expect(preview["resolvedDefinitions"].array.contains { $0["id"] == .string(shop.tool.id) })
    let result = try b.invokeApplicationAction(
      form.id, arguments: input, preview: preview, token: "add-nuts", actor: .human("test form"))
    try expect(result["state"] == .string("applied") && result["undo"].string != nil)
    try expect(try rows(shop) == ["bolts", "nuts"])
    let invocation = try b.item(result["sourceID"].text)
    try expect(
      invocation.kind == "application_invocation" && !invocation.isBusinessEvidence
        && invocation.data["actor"]["kind"] == .string("human"))
    let after = try b.revision()
    try expect(
      try b.invokeApplicationAction(
        form.id, arguments: input, preview: preview, token: "add-nuts", actor: .human("test form"))
        == result)
    try expect(try b.revision() == after && rows(shop) == ["bolts", "nuts"])
    _ = try b.chatSQLUndo(result["undo"].text, actor: .human("test form"))
    try expect(try rows(shop) == ["bolts"])
    try refuses("sql_undo") { _ = try b.chatSQLUndo(result["undo"].text) }
    // A changed tool makes the preview stale, so the form runs only what was previewed.
    _ = try b.chatSaveTool(
      name: "add_part", description: "Adds a part.", inputs: [("name", "text"), ("qty", "decimal")],
      statements: ["INSERT INTO parts (name, qty) VALUES (upper(:name), :qty)"], source: nil,
      token: "save-add-part-2", requestSourceID: nil)
    try refuses("stale_action_preview") {
      _ = try b.invokeApplicationAction(form.id, arguments: input, preview: preview, token: "late")
    }
    try expect(try rows(shop) == ["bolts"])
    _ = try b.verify()
  }

  check("a tool action refuses wrong inputs, a missing input mapping and a tool not enabled here") {
    let shop = try shop("Inputs")
    let b = shop.book
    let action = try b.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.toolActionDefinition(tool: shop.tool))
    let revision = try b.revision()
    try refuses("definition_input") {
      _ = try b.previewApplicationAction(action.id, arguments: .object(["name": .string("nuts")]))
    }
    try refuses {
      _ = try b.previewApplicationAction(
        action.id, arguments: .object(["name": .string("nuts"), "qty": .string("five")]))
    }
    try refuses("definition_input") {
      _ = try b.previewApplicationAction(
        action.id,
        arguments: .object(["name": .string("nuts"), "qty": .string("5"), "drop": .bool(true)]))
    }
    var content = ActionRegistry.toolActionDefinition(tool: shop.tool).object
    var payload = content["payload"]!.object
    payload["arguments"] = .object(["name": .object(["parameter": .string("name")])])
    content["payload"] = .object(payload)
    try refuses { _ = try b.saveApplicationDefinition(logicalID: identifier(), content: .object(content)) }
    payload["tool"] = nil
    content["payload"] = .object(payload)
    try refuses("definition_action") {
      _ = try b.saveApplicationDefinition(logicalID: identifier(), content: .object(content))
    }
    try b.disableTool(shop.tool.id)
    try refuses("tool_disabled") { _ = try b.previewApplicationAction(action.id, arguments: input) }
    try expect(try b.revision() == revision && rows(shop) == ["bolts"])
    _ = try b.verify()
  }

  check("a function result feeds a tool input, with the function in the run's lineage") {
    let shop = try shop("Computed")
    let b = shop.book
    let cases: Value = .object([
      "id": .string("cases"), "label": .string("Cases"), "type": .string("decimal"),
      "required": .bool(true),
    ])
    let function = try b.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("function"), "title": .string("Items per case"),
        "description": .string("Twelve to a case"), "parameters": .array([cases]),
        "payload": .object(["expression": .string("cases*12"), "calls": .array([])]),
      ]))
    let name = shop.tool.parameters.array.first { $0["id"] == .string("name") }!
    let action = try b.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("action"), "title": .string("Add cases"),
        "description": .string("Adds a part counted in cases"), "parameters": .array([name, cases]),
        "payload": .object([
          "primitive": .object(["id": .string(ActionRegistry.toolID), "version": .number(1)]),
          "tool": .object(["mode": .string("live"), "logicalID": .string(shop.tool.logicalID)]),
          "arguments": .object([
            "name": .object(["parameter": .string("name")]),
            "qty": .object([
              "function": .object([
                "mode": .string("live"), "logicalID": .string(function.logicalID),
              ]),
              "arguments": .object(["cases": .object(["parameter": .string("cases")])]),
            ]),
          ]),
        ]),
      ]))
    let arguments: Value = .object(["name": .string("washers"), "cases": .string("3")])
    let preview = try b.previewApplicationAction(action.id, arguments: arguments)
    try expect(preview["primitiveArguments"]["qty"] == .string("36"))
    let result = try b.invokeApplicationAction(
      action.id, arguments: arguments, preview: preview, token: "cases")
    let added = try b.rows(shop.parts.id).first { $0.data["name"] == .string("washers") }
    try expect(added.map { Numbers.string(try Numbers.decimal($0.data["qty"].text)) } == "36")
    try expect(
      try b.lineage(result["sourceID"].text).contains { $0["parent"] == .string(function.sourceID) })
    _ = try b.verify()
  }

  check("a workflow step runs an exact saved tool with no review, once, and its change undoes") {
    let shop = try shop("Workflow")
    let b = shop.book
    let action = try b.saveApplicationDefinition(
      logicalID: identifier(),
      content: ActionRegistry.toolActionDefinition(tool: shop.tool, exact: true))
    let template = try b.workflowTemplate(action.id)
    try expect(template["payload"]["steps"].array.count == 1)
    let workflow = try b.saveApplicationDefinition(logicalID: identifier(), content: template)
    // A review on a step that changes tables at once is refused.
    var reviewed = template.object
    var payload = reviewed["payload"]!.object
    payload["steps"] = .array(
      template["payload"]["steps"].array + [
        .object(["id": .string("review"), "kind": .string("review"), "review": .string("prepare")])
      ])
    reviewed["payload"] = .object(payload)
    try refuses("workflow_definition") {
      _ = try b.saveApplicationDefinition(logicalID: identifier(), content: .object(reviewed))
    }
    let run = try b.startWorkflow(workflow.id, arguments: input, token: "start")
    let session = try b.authorizeWorkflowExecution(run["id"].text)
    let done = try b.advanceWorkflow(session, owner: "test")
    try expect(done["state"] == .string("completed"))
    let output = done["steps"].array[0]["output"]["value"]
    try expect(output["kind"] == .string("tool") && output["undo"].string != nil)
    try expect(try rows(shop) == ["bolts", "nuts"])
    // The step's tool token is fixed, so a second run of the same plan finds its saved change.
    let plan = try b.applicationActionPlan(action.id, arguments: input, cancellation: .init())
    let again = try b.runPlannedTool(
      plan, token: "workflow-tool:" + run["id"].text + ":prepare", requestSourceID: nil,
      actor: .programmatic("test"), cancellation: .init())
    try expect(again["recovered"] == .bool(true) && rows(shop) == ["bolts", "nuts"])
    _ = try b.chatSQLUndo(output["undo"].text, actor: .human("test"))
    try expect(try rows(shop) == ["bolts"])
    // An automation can run it on a schedule. Its preview names the tool and says the change
    // applies without review, and its run applies the change once with an Undo.
    let automation = try executionAutomation(b, workflow: workflow, arguments: input)
    let preview = try b.previewAutomation(automation.id, after: Date())
    try expect(preview["tools"] == .array([.string("add_part")]))
    try expect(
      preview["notice"].text.contains("runs the saved tool add_part without asking")
        && preview["notice"].text.contains("apply without review")
        && !preview["notice"].text.contains(";") && !preview["notice"].text.contains("\u{2014}"))
    let start = automationDate("2026-10-01T08:00:00Z")
    let due = automationDate("2026-10-01T09:00:00Z")
    let granted = try b.authorizeAutomationExecution(
      automation.id, expectedGeneration: 0, after: start, token: "enable",
      actor: .human("test"))
    _ = try b.planAutomationOccurrences(granted.planning, through: due, token: "plan")
    let dispatched = try b.dispatchAutomationOccurrence(granted, observedAt: due, token: "go")
    let worker = try b.authorizeAutomationWorkflowExecution(
      granted, runID: dispatched["runID"].text)
    let automatic = try b.advanceWorkflow(worker, owner: "test")
    try expect(automatic["state"] == .string("completed"))
    let applied = automatic["steps"].array[0]["output"]["value"]
    try expect(applied["kind"] == .string("tool") && applied["undo"].string != nil)
    try expect(try rows(shop) == ["bolts", "nuts"])
    try expect(
      try b.workflowRuns().contains { $0["id"] == dispatched["runID"] }
        && b.workflowRun(dispatched["runID"].text)["policy"] == .string("automation-drafts-v1"),
      "The automatic tool run is not listed in Workflow runs")
    _ = try b.chatSQLUndo(applied["undo"].text, actor: .human("test"))
    try expect(try rows(shop) == ["bolts"])
    // A drafting workflow says it drafts and names no tool.
    let evidence = try b.addItem(
      category: "source", kind: "observation", title: "Note", status: "accepted")
    let noteWorkflow = try b.saveApplicationDefinition(
      logicalID: identifier(), content: b.workflowTemplate(noteAction(b).id))
    let drafting = try b.previewAutomation(
      executionAutomation(b, workflow: noteWorkflow, arguments: noteArguments(evidence.id)).id,
      after: Date())
    try expect(drafting["tools"] == .array([]) && drafting["notice"].text.contains("drafts"))
    _ = try b.verify()
  }

  check("chat runs a tool action from this run's preview, refuses read-only requests and retries exactly") {
    let shop = try shop("Chat")
    let b = shop.book
    let prompt = "Add nuts with the saved action."
    let request = try b.startAgentRequest(prompt, conversation: b.startChat, model: "synthetic")
    let source = try b.addItem(
      category: "source", kind: "request", title: "Current request", text: prompt,
      data: .object([
        "conversationID": .string(b.startChat), "messageID": .string(request.messageID),
      ]))
    let tools = WorkbookTools(b, runID: request.runID, requestSourceID: source.id)
    let action = try b.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.toolActionDefinition(tool: shop.tool))
    let arguments: Value = .object(["id": .string(action.id), "arguments": input])
    let receipt = try b.prepareToolCall(
      runID: request.runID, callID: identifier(), tool: "preview_action", arguments: arguments)
    let preview = try tools.execute("preview_action", arguments, receiptID: receipt)
    _ = try b.completeToolCall(receipt, result: preview)
    try expect(preview["notice"].text.contains("action.prepare") && rows(shop) == ["bolts"])
    let submit: Value = .object(["previewReceiptID": .string(receipt)])
    let readOnly = WorkbookTools(
      b, runID: request.runID, requestSourceID: source.id, readOnly: true)
    try refuses("read_only_request") { _ = try readOnly.execute("commit_action_preview", submit) }
    let result = try tools.execute("commit_action_preview", submit)
    try expect(result["state"] == .string("applied") && rows(shop) == ["bolts", "nuts"])
    try refuses("item_scope") { _ = try tools.execute("read", .object(["id": result["sourceID"]])) }
    let revision = try b.revision()
    try expect(try tools.execute("commit_action_preview", submit) == result)
    try expect(try b.revision() == revision && rows(shop) == ["bolts", "nuts"])
    // A document action is still submitted only through its form or workflow.
    let note = try noteAction(b)
    let evidence = try b.addItem(
      category: "source", kind: "observation", title: "Quote", text: "Quote R1.")
    let noteArgs: Value = .object([
      "id": .string(note.id), "arguments": noteArguments(evidence.id, meaning: "estimate"),
    ])
    let noteReceipt = try b.prepareToolCall(
      runID: request.runID, callID: identifier(), tool: "preview_action", arguments: noteArgs)
    _ = try b.completeToolCall(
      noteReceipt, result: try tools.execute("preview_action", noteArgs, receiptID: noteReceipt))
    try refuses("action_capability") {
      _ = try tools.execute(
        "commit_action_preview", .object(["previewReceiptID": .string(noteReceipt)]))
    }
    try expect(try b.items(kind: "document").isEmpty)
    _ = try b.verify()
  }

  check("an optional interpretation output left out leaves the tool's optional input empty") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ToolAction-Optional.sevra"), title: "Optional")
    let source = try book.addItem(
      category: "source", kind: "observation", title: "Receipt", text: "Received5 bolts.")
    let counts = try book.createDataset(
      title: "Counts",
      columns: [
        .init(id: "qty", title: "Qty", type: "decimal"), .init(id: "note", title: "Note"),
      ], rows: [], sourceID: source.id)
    let note: Value = .object([
      "id": .string("note"), "label": .string("Note"), "type": .string("text"),
      "required": .bool(false),
    ])
    let quantity = ActionRegistry.field("qty", "Count", "decimal", unit: "items")
    let tool = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("tool"), "title": .string("log_count"),
        "description": .string("Logs a count with an optional note."),
        "parameters": .array([quantity, note]),
        "payload": .object([
          "name": .string("log_count"), "language": .string("sql"),
          "statements": .array([.string("INSERT INTO counts (qty, note) VALUES (:qty, :note)")]),
        ]),
      ]))
    try book.enableTool(tool.id)
    let action = try book.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.toolActionDefinition(tool: tool, exact: true))
    let interpretation = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("interpretation"), "title": .string("Read the receipt"),
        "description": .string("Synthetic"),
        "parameters": .array([ActionRegistry.field("evidence", "Evidence", "item")]),
        "payload": .object([
          "instruction": .string("Extract the received count and any note."),
          "evidence": .array([.string("evidence")]),
          "outputs": .array([ActionRegistry.field("quantity", "Count", "decimal", unit: "items"), note]),
          "meaning": .string("actual"), "scenario": .string("actual"),
        ]),
      ]))
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("workflow"), "title": .string("Read then log"),
        "description": .string("Synthetic"),
        "parameters": .array([ActionRegistry.field("evidence", "Evidence", "item")]),
        "payload": .object([
          "readPolicy": .string("latest-at-step"),
          "steps": .array([
            .object([
              "id": .string("read"), "kind": .string("interpret"),
              "binding": .object(["mode": .string("exact"), "versionID": .string(interpretation.id)]),
              "arguments": .object(["evidence": .object(["parameter": .string("evidence")])]),
            ]),
            .object([
              "id": .string("log"), "kind": .string("action"),
              "binding": .object(["mode": .string("exact"), "versionID": .string(action.id)]),
              "arguments": .object([
                "qty": .object([
                  "step": .string("read"), "field": .string("quantity"), "unit": .string("items"),
                ]),
                "note": .object(["step": .string("read"), "field": .string("note")]),
              ]),
            ]),
          ]),
        ]),
      ]))
    let run = try book.startWorkflow(
      workflow.id, arguments: .object(["evidence": .string(source.id)]), token: "start")
    let session = try book.authorizeWorkflowExecution(run["id"].text)
    let claim = try book.claimWorkflowStep(session, owner: "synthetic")
    let request = try book.prepareWorkflowInterpretation(session, claim: claim, model: "synthetic")
    _ = try book.completeWorkflowStep(
      session, claim: claim,
      interpretation: .object([
        "request": request, "metrics": .object(["synthetic": .bool(true)]),
        "response": .object([
          "state": .string("ready"), "values": .object(["quantity": .string("5")]),
          "citations": .array([
            .object([
              "field": .string("quantity"), "itemID": .string(source.id),
              "quote": .string("Received5 bolts."),
            ])
          ]), "issues": .array([]),
        ]),
      ]))
    let done = try book.continueWorkflow(session, owner: "continue")
    try expect(done["state"] == .string("completed"), done["detail"].text)
    try expect(done["steps"].array[1]["output"]["arguments"].object["note"] == nil)
    let logged = try book.rows(counts.id)
    try expect(
      logged.count == 1 && logged[0].data["note"].text.isEmpty
        && Numbers.string(try Numbers.decimal(logged[0].data["qty"].text)) == "5")
    _ = try book.verify()
  }
}
