import Foundation

@testable import SevraCore

/// Remove and restore, for each kind of saved thing, and the refusals around them.
func checkRemoval(at root: URL) {
  let person = ChangeActor.human("Sevra.chat-confirmation")
  func book(_ name: String) throws -> Workbook {
    try Workbook.create(at: root.appendingPathComponent("Removal-" + name + ".sevra"), title: name)
  }
  func document(_ book: Workbook, _ title: String, _ text: String, status: String = "draft") throws
    -> Item
  {
    let source = try book.addItem(category: "source", kind: "note", title: "Notes")
    return try book.addItem(
      category: "record", kind: "document", title: title, text: text, status: status,
      inputs: [source.id])
  }

  check("removing a draft document takes it out of lists and search, and restore brings it back")
  {
    let book = try book("DraftDocument")
    let story = try document(book, "Elara and the Silver Leaf", "Elara found a silver leaf.")
    try expect(try book.search("silver leaf").hits.contains { $0.itemID == story.id })
    // The way the model emptied it before: an empty edit is refused and names remove.
    try refuses("document_edit") { _ = try book.editDocument(story.id, text: "  ") }

    let removed = try book.remove(story.id, actor: person)
    try expect(removed["status"] == .string("removed") && removed["type"] == .string("item"))
    try expect(try book.isRemoved(story.logicalID))
    try expect(try book.item(story.logicalID).status == "rejected")
    try expect(try book.recentItemSummaries().allSatisfy { $0.title != story.title })
    try expect(try book.items().allSatisfy { $0.logicalID != story.logicalID })
    try expect(try book.search("silver leaf").hits.isEmpty)
    try book.rebuildSearch()
    try expect(try book.search("silver leaf").hits.isEmpty)
    try expect(try book.removedThings().contains { $0["id"] == .string(story.logicalID) })
    try refuses("already_removed") { _ = try book.remove(story.logicalID, actor: person) }

    _ = try book.restore(story.logicalID, actor: person)
    let back = try book.item(story.logicalID)
    try expect(back.status == "draft" && back.text == story.text && back.title == story.title)
    try expect(try !book.isRemoved(story.logicalID))
    try expect(try book.search("silver leaf").hits.contains { $0.itemID == back.id })
    try expect(try book.removedThings().isEmpty)
    try refuses("not_removed") { _ = try book.restore(story.logicalID, actor: person) }
    // History keeps every step.
    try expect(try book.item(story.id).text == story.text)
    _ = try book.verify()
  }

  check("an accepted document comes back accepted, and a second removal works") {
    let book = try book("AcceptedDocument")
    let draft = try document(book, "Supplier summary", "Cedar Tools was cheapest.")
    let accepted = try book.accept(draft.id, actor: person)
    _ = try book.remove(accepted.logicalID, actor: person)
    _ = try book.restore(accepted.logicalID, actor: person)
    try expect(try book.item(accepted.logicalID).status == "accepted")
    _ = try book.remove(accepted.logicalID, actor: person)
    try expect(try book.isRemoved(accepted.logicalID))
    _ = try book.verify()
  }

  check("only a person removes: an AI actor without a saved rule is refused") {
    let book = try book("Actor")
    let draft = try document(book, "Memo", "Text.")
    try refuses("decision_policy") {
      _ = try book.remove(draft.id, actor: .ai("Sevra.chat", model: "m", policy: "no-such-rule"))
    }
    try expect(try !book.isRemoved(draft.logicalID))
  }

  check("sources, rows, decisions and Home are refused with what to do instead") {
    let book = try book("Refusals")
    let source = try book.addItem(category: "source", kind: "observation", title: "Costs file")
    try refuses("remove") { _ = try book.remove(source.id, actor: person) }
    let table = try book.createDataset(
      title: "Costs", columns: [.init(id: "price", title: "Price", type: "decimal")],
      rows: [["price": .string("2.10")]], sourceID: source.id)
    let row = try book.rows(table.id).first!
    try refuses("remove") { _ = try book.remove(row.logicalID, actor: person) }
    try refuses("remove") { _ = try book.remove("home", actor: person) }
    try refuses("not_found") { _ = try book.remove("no-such-thing", actor: person) }
  }

  check("a table is archived by remove and unarchived by restore") {
    let book = try book("Table")
    let source = try book.addItem(category: "source", kind: "observation", title: "Costs file")
    let table = try book.createDataset(
      title: "Costs", columns: [.init(id: "price", title: "Price", type: "decimal")],
      rows: [["price": .string("2.10")]], sourceID: source.id)
    let removed = try book.remove(table.id, actor: person)
    try expect(removed["type"] == .string("table"))
    try expect(try book.dataset(table.id).archived)
    try expect(try book.removedThings().contains { $0["id"] == .string(table.id) })
    _ = try book.restore(table.id, actor: person)
    try expect(try !book.dataset(table.id).archived)
    try expect(try book.rows(table.id).count == 1)
    _ = try book.verify()
  }

  check("a view leaves the list of views, cannot be found by name, and comes back") {
    let book = try book("View")
    let id = try book.saveSpace(
      title: "Purchasing", definition: SpaceDefinition(components: []))
    try expect(try book.removalTarget(id).type == "view")
    _ = try book.remove(id, actor: person)
    try expect(try book.spaces().allSatisfy { $0.id != id })
    try refuses("space_not_found") { _ = try book.spaceTarget("Purchasing") }
    _ = try book.restore(id, actor: person)
    try expect(try book.spaces().contains { $0.id == id })
    try expect(try book.spaceTarget("Purchasing").id == id)
    _ = try book.verify()
  }

  check("a removed function is hidden from search and cannot run until restored") {
    let book = try book("Definition")
    let saved = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("function"), "title": .string("Double the price"),
        "description": .string("Twice the input."),
        "parameters": .array([
          .object([
            "id": .string("x"), "label": .string("x"), "type": .string("decimal"),
            "required": .bool(true),
          ])
        ]),
        "payload": .object(["expression": .string("x*2"), "calls": .array([])]),
      ]),
      expectedDefinitionID: nil)
    let arguments: Value = .object(["x": .string("3")])
    _ = try book.evaluateApplicationDefinition(saved.id, arguments: arguments)
    let target = try book.remove(saved.id, actor: person)
    try expect(target["type"] == .string("definition") && target["id"] == .string(saved.logicalID))
    try expect(try book.searchApplicationDefinitions("Double")["hits"].array.isEmpty)
    try refuses("removed") {
      _ = try book.evaluateApplicationDefinition(saved.id, arguments: arguments)
    }
    _ = try book.restore(saved.logicalID, actor: person)
    _ = try book.evaluateApplicationDefinition(saved.id, arguments: arguments)
    try expect(try book.searchApplicationDefinitions("Double")["hits"].array.count == 1)
    _ = try book.verify()
  }

  check("a saved tool is retired by remove, comes back enabled, and verifies") {
    let book = try book("Tool")
    let source = try book.addItem(category: "source", kind: "observation", title: "Visits")
    _ = try book.createDataset(
      title: "Visits", columns: [.init(id: "name", title: "Name", type: "text")], rows: [],
      sourceID: source.id)
    _ = try book.chatSaveTool(
      name: "log_visit", description: "", inputs: [],
      statements: ["INSERT INTO visits (name) VALUES (NULL)"], source: nil, token: "tool",
      requestSourceID: nil)
    let tool = try book.savedTools().first { $0.name == "log_visit" }!
    _ = try book.remove(tool.definitionID, actor: person)
    try expect(try book.savedTools().allSatisfy { $0.name != "log_visit" })
    try expect(try book.removedThings().contains { $0["id"] == .string(tool.logicalID) })
    _ = try book.restore(tool.logicalID, actor: person)
    let back = try book.savedTools().first { $0.name == "log_visit" }
    try expect(back != nil && book.isToolEnabled(back!.definitionID))
    _ = try book.verify()
    // A tool binds nothing, so a dependency recorded for it is damage verify must find.
    _ = try book.db.transaction {
      try book.db.execute(
        "INSERT INTO app_definition_dependencies VALUES(?,0,'definition','exact',?,?,NULL,NULL)",
        [.string(back!.definitionID), .string(back!.logicalID), .string(back!.definitionID)])
    }
    try refuses("definition_integrity") { _ = try book.verify() }
  }

  check("an app is hidden and restored, and one that Home shows is refused until taken off") {
    let book = try book("App")
    let app = try book.installNativeAppContents(
      NativeAppPackage(
        name: "Orders", source: "Sevra.mount(Sevra.h(Sevra.Text,{text:'Orders'}));", datasets: [:]))
    try expect(try book.removalTarget(app.id).type == "app")
    _ = try book.remove(app.id, actor: person)
    try expect(try book.spaces().allSatisfy { $0.id != app.id })
    try expect(try book.removedThings().contains { $0["type"] == .string("app") })
    let back = try book.restore(app.id, actor: person)
    try expect(back["note"].text.contains("turned off"))
    try expect(try book.spaces().contains { $0.id == app.id })

    let home = try book.space("home")
    _ = try book.editSpace(
      "home", expectedVersion: home.version,
      edits: [
        .init(
          operation: "insert", at: "last",
          component: Component(id: "orders", type: "app", title: "Orders", spaceID: app.id))
      ])
    try refuses("remove_in_use") { _ = try book.remove(app.id, actor: person) }
    try expect(try !book.isRemoved(app.id))
    _ = try book.verify()
  }

  check("an automation is hidden, cannot be found by name or start its workflow, and comes back")
  {
    let book = try book("Automation")
    let function = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("function"), "title": .string("Double count"),
        "description": .string("Synthetic automation fixture."),
        "parameters": .array([ActionRegistry.field("quantity", "Count", "decimal", unit: "items")]),
        "payload": .object(["expression": .string("quantity*2"), "unit": .string("items")]),
      ]))
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(), content: book.workflowTemplate(function.id))
    let automation = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("automation"), "title": .string("Weekday count"),
        "description": .string("An inert intention, not permission to execute."),
        "parameters": .array([]),
        "payload": .object([
          "policy": .string("calendar-v1"),
          "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow.id)]),
          "arguments": .object(["quantity": .string("5.00")]),
          "schedule": .object([
            "policy": .string("native-calendar-v1"), "timeZone": .string("America/Bogota"),
            "hour": .number(9), "minute": .number(0),
            "recurrence": .object(["kind": .string("weekly"), "weekdays": .array([.string("monday")])]),
          ]),
        ]),
      ]))
    _ = try book.remove(automation.id, actor: person)
    try refuses("automation_not_found") { _ = try book.automationTarget("Weekday count") }
    _ = try book.remove(workflow.id, actor: person)
    try refuses("removed") {
      _ = try book.startWorkflow(
        workflow.id, arguments: .object(["quantity": .string("5.00")]), token: identifier())
    }
    let back = try book.restore(automation.logicalID, actor: person)
    try expect(back["note"].text.contains("turned off"))
    try expect(try book.automationTarget("Weekday count").id == automation.id)
    _ = try book.restore(workflow.logicalID, actor: person)
    _ = try book.verify()
  }

  check("a screen reads whether its subject is still here, from any version, whoever removed it") {
    let book = try book("Presence")
    let story = try document(book, "The Clockmaker's Secret", "Elias repaired time.")
    try expect(try book.presence(story.id) == .init(
      state: "present", target: try book.removalTarget(story.id), currentVersion: story.id))
    // The version open on screen predates the removal, and still answers "removed".
    _ = try book.remove(story.logicalID, actor: person)
    let opened = try book.presence(story.id)
    try expect(opened.state == "removed" && opened.gone && opened.restorable)
    try expect(opened.target?.id == story.logicalID && opened.currentVersion != story.id)
    _ = try book.restore(story.id, actor: person)
    try expect(try book.presence(story.id).state == "present")
    // Undo elsewhere withdraws it: not removable back, but plainly gone.
    _ = try book.undoItem(try book.item(story.logicalID).id, actor: person)
    let undone = try book.presence(story.id)
    try expect(undone.state == "withdrawn" && undone.gone && !undone.restorable)

    let source = try book.addItem(category: "source", kind: "observation", title: "Costs")
    try expect(try book.presence(source.id).state == "present")
    let table = try book.createDataset(
      title: "Costs", columns: [.init(id: "price", title: "Price", type: "decimal")],
      rows: [["price": .string("2.10")]], sourceID: source.id)
    _ = try book.remove(table.id, actor: person)
    try expect(try book.presence(table.id).state == "removed")
    let view = try book.saveSpace(title: "Purchasing", definition: SpaceDefinition(components: []))
    _ = try book.remove(view, actor: person)
    try expect(try book.presence(view).state == "removed")
    try expect(try book.presence("home").state == "present")
    try expect(try book.presence(identifier()).state == "missing")
  }
}
