import Foundation

@testable import SevraCore

func checkSpaceEditing(at temp: URL) {
  func fixture() throws -> Workbook {
    try Workbook.create(at: temp.appendingPathComponent(identifier() + ".sevra"), title: "Layouts")
  }
  check("Home sections are editable definitions and an emptied authored Home stays empty") {
    let book = try fixture()
    let initial = try book.space("home")
    try expect(initial.version == 1 && initial.definition == .defaultHome)
    let draft = try book.addItem(category: "source", kind: "submission", title: "Pending")
    let emptied = try book.editSpace(
      "home", expectedVersion: 1,
      edits: initial.definition.components.map { .init(operation: "remove", componentID: $0.id) },
      token: "empty-home", actor: .human("layout-test"))
    try expect(emptied.version == 2 && emptied.definition.components.isEmpty)
    try expect(try Workbook(book.url).space("home").definition.components.isEmpty)
    try expect(try book.reviewQueue().items.contains { $0.id == draft.id })
    let history = try book.spaceHistory("home")
    try expect(history.map(\.version) == [2, 1] && history[1].definition == .defaultHome)
    let restored = try book.restoreSpace(
      "home", version: 1, expectedVersion: 2, token: "restore-home")
    try expect(restored.version == 3 && restored.definition == .defaultHome)
    try expect(try book.spaceHistory("home", before: 3, limit: 1).map(\.version) == [2])
    let rebuilt = try book.reconstruct(to: temp.appendingPathComponent(identifier() + ".sevra"))
    try expect(try rebuilt.space("home").definition == .defaultHome)
    try expect(try rebuilt.spaceHistory("home").map(\.version) == [3, 2, 1])
    try expect(try rebuilt.item(draft.id).status == "draft")
  }
  check("a view that went stale under a saved space does not block edits around it") {
    let book = try fixture()
    let source = try book.addItem(category: "source", kind: "observation", title: "Stock")
    let table = try book.createDataset(
      title: "Stock",
      columns: [
        Column(id: "name", title: "Name", type: "text"),
        Column(id: "qty", title: "Quantity", type: "decimal"),
      ], rows: [["name": .string("bolts"), "qty": .string("5")]], sourceID: source.id
    ).id
    let logical = identifier()
    func function(_ parameters: [Value]) -> Value {
      .object([
        "kind": .string("function"), "title": .string("Double"), "description": .string("Test"),
        "parameters": .array(parameters),
        "payload": .object(["expression": .string("a*2")]),
      ])
    }
    let a = ActionRegistry.field("a", "A", "decimal")
    let first = try book.saveApplicationDefinition(
      logicalID: logical, content: function([a]))
    let calculation = Component(
      id: "calc", type: "calculation", title: "Doubled",
      definitionBinding: .object(["mode": .string("live"), "logicalID": .string(logical)]),
      arguments: .object(["a": .string("3")]))
    let chart = Component(
      id: "chart", type: "chart", title: "Quantity", datasetID: table, x: "name", y: "qty")
    let metric = Component(
      id: "metric", type: "metric", title: "Total", datasetID: table, y: "qty")
    let live = try book.saveSpace(
      title: "Stock", definition: SpaceDefinition(components: [chart, metric, calculation]))
    let noCalculation = try book.saveSpace(
      title: "Charts", definition: SpaceDefinition(components: [chart, metric]))
    let pinned = try book.pinSpace(noCalculation, title: "Snapshot")
    _ = try book.saveApplicationDefinition(
      logicalID: logical,
      content: function([a, ActionRegistry.field("b", "Rate", "decimal")]),
      expectedDefinitionID: first.id)
    let definition = try book.datasetDefinition(table)
    _ = try book.updateDatasetDefinition(
      table, expectedVersion: definition.version, expectedDefinitionID: definition.id,
      columns: [definition.columns[0]])
    let renamed = try book.editSpace(
      live, expectedVersion: 1, edits: [.init(operation: "rename", title: "Renamed")])
    try expect(renamed.title == "Renamed")
    // A changed view still answers for itself, and a snapshot for the columns it kept.
    try refuses("definition_input") {
      _ = try book.editSpace(
        live, expectedVersion: 2,
        edits: [
          .init(operation: "remove", componentID: "calc"),
          .init(
            operation: "insert", at: "last",
            component: Component(
              id: "calc2", type: "calculation", title: "New",
              definitionBinding: calculation.definitionBinding, arguments: calculation.arguments)),
        ])
    }
    let relabelled = try book.editSpace(
      pinned, expectedVersion: 1,
      edits: [.init(operation: "title", componentID: "chart", title: "Saved quantity")])
    try expect(relabelled.definition.components[0].title == "Saved quantity")
    _ = try book.verify()
  }
  check("a snapshot title obeys the same bounds as any space title") {
    let book = try fixture()
    let live = try book.saveSpace(
      id: "long", title: String(repeating: "t", count: 500),
      definition: SpaceDefinition(components: []))
    for title in ["", "   ", String(repeating: "x", count: 501)] {
      try refuses("view") { _ = try book.pinSpace(live, title: title) }
    }
    let snapshot = try book.pinSpace(live)
    try expect(try book.space(snapshot).title.utf8.count <= 500)
    _ = try book.editSpace(
      snapshot, expectedVersion: 1, edits: [.init(operation: "rename", title: "Kept")])
  }
  check("space edits compare exact bases and retries keep the original saved version") {
    let book = try fixture()
    let other = try Workbook(book.url)
    let edits = [SpaceEdit(operation: "title", componentID: "recent", title: "Recent evidence")]
    let first = try book.editSpace("home", expectedVersion: 1, edits: edits, token: "layout-once")
    _ = try other.editSpace(
      "home", expectedVersion: 2, edits: [.init(operation: "rename", title: "Operations")])
    let revision = try book.revision()
    let commits = try book.committedHistory()
    try expect(
      try book.editSpace("home", expectedVersion: 1, edits: edits, token: "layout-once").version
        == first.version)
    try refuses("space_conflict") {
      _ = try other.editSpace(
        "home", expectedVersion: 1, edits: [.init(operation: "remove", componentID: "recent")])
    }
    try refuses("space_conflict") {
      _ = try book.saveSpace(id: "home", title: "Overwrite", definition: .init(components: []))
    }
    try refuses("idempotency") {
      _ = try book.editSpace("home", expectedVersion: 3, edits: edits, token: "layout-once")
    }
    try expect(try book.revision() == revision && book.committedHistory() == commits)
    try expect(try book.space("home").title == "Operations")
    try expect(try book.space("home").definition.components.last?.title == "Recent evidence")
  }
  check("semantic edits preserve groups, identities and snapshot binding mode") {
    let book = try fixture()
    let note = try book.addItem(
      category: "source", kind: "note", title: "Original", text: "Keep me")
    let id = try book.saveSpace(
      title: "Grouped",
      definition: .init(components: [
        .init(
          id: "group", type: "comparison", title: "Together",
          children: [
            .init(id: "left", type: "text", title: "Left", text: "Original text"),
            .init(id: "right", type: "document", title: "Evidence", itemID: note.logicalID),
          ]), .init(id: "tail", type: "text", title: "After", text: "Tail"),
      ]))
    let edited = try book.editSpace(
      id, expectedVersion: 1,
      edits: [
        .init(operation: "text", componentID: "left", text: "Revised"),
        .init(operation: "move", componentID: "right", beforeID: "left"),
        .init(
          operation: "insert", beforeID: "tail",
          component: .init(id: "new", type: "text", title: "New", text: "Added")),
        .init(operation: "move", componentID: "tail", beforeID: "group"),
      ])
    try expect(edited.definition.components.map(\.id) == ["tail", "group", "new"])
    try expect(edited.definition.components[1].children?.map(\.id) == ["right", "left"])
    let pinned = try book.pinSpace(id)
    let saved = try book.space(pinned)
    let changed = try book.editSpace(
      pinned, expectedVersion: 1,
      edits: [.init(operation: "title", componentID: "right", title: "Pinned evidence")])
    try expect(changed.definition.pinnedAt == saved.definition.pinnedAt)
    let revision = try book.revision()
    try refuses("space_snapshot") {
      _ = try book.editSpace(
        pinned, expectedVersion: 2,
        edits: [
          .init(
            operation: "replace", componentID: "right",
            component: .init(id: "right", type: "document", title: "Live", itemID: note.logicalID))
        ])
    }
    try refuses("view") {
      _ = try book.editSpace(
        id, expectedVersion: 2,
        edits: [
          .init(operation: "insert", at: "last", component: .init(type: "execute", title: "Unsafe"))
        ])
    }
    try refuses("view") {
      _ = try book.editSpace(
        id, expectedVersion: 2, edits: [.init(operation: "remove", componentID: "left")])
    }
    try expect(try book.revision() == revision && book.item(note.id).text == "Keep me")
    try refuses("view_limit") { _ = try book.pinSpace("home") }
  }
  check("agent layout tools preserve read-only authority and exact saved identities") {
    let book = try fixture()
    let run = try book.startAgentRequest(
      "Hide recent work on Home", conversation: "main", model: "local-test-model"
    ).runID
    let tools = WorkbookTools(book, runID: run)
    let arguments: Value = .object([
      "id": .string("home"), "expectedVersion": .number(1),
      "edits": try encoded([SpaceEdit(operation: "remove", componentID: "recent")]),
    ])
    let result = try tools.execute("edit_space", arguments)
    try expect(result["spaceID"].text == "home" && result["version"].int == 2)
    try expect(try tools.execute("edit_space", arguments) == result)
    let history = try tools.execute("space_history", .object(["id": .string("home")]))
    try expect(history.array.count == 2)
    try expect(try book.committedHistory().first?["actor"]["kind"].text == "ai")
    try expect(try book.committedHistory().first?["actor"]["model"].text == "local-test-model")
    let readOnly = WorkbookTools(book, readOnly: true)
    try refuses("read_only_request") { _ = try readOnly.execute("edit_space", arguments) }
    _ = try readOnly.execute("space_history", .object(["id": .string("home")]))
    let archive = temp.appendingPathComponent(identifier() + ".sevraz")
    try book.export(to: archive)
    let portable = try Workbook.openArchive(
      archive, at: temp.appendingPathComponent(identifier() + ".sevra"))
    try expect(try portable.space("home").version == 2 && portable.spaceHistory("home").count == 2)
    try expect(try portable.verify()["ok"] == .bool(true))
  }
  check("layout positions are explicit and unrelated fields never become silent edits") {
    let book = try fixture()
    let initial = try book.space("home")
    let revision = try book.revision()
    for edit in [
      SpaceEdit(operation: "move", componentID: "tables", title: "Tables"),
      SpaceEdit(operation: "move", componentID: "tables"),
      SpaceEdit(operation: "move", componentID: "tables", beforeID: "input", at: "first"),
      SpaceEdit(operation: "remove", componentID: "recent", text: "Unused"),
      SpaceEdit(operation: "insert", component: .init(type: "text", title: "Unplaced")),
    ] {
      try refuses("view") { _ = try book.editSpace("home", expectedVersion: 1, edits: [edit]) }
    }
    try expect(
      try book.revision() == revision && book.space("home").definition == initial.definition)
    let first = try book.editSpace(
      "home", expectedVersion: 1,
      edits: [
        .init(operation: "move", componentID: "tables", at: "first"),
        .init(operation: "remove", componentID: "recent"),
      ])
    try expect(
      first.definition.components.map(\.id) == [
        "tables", "input", "reviews", "shortcuts", "intake",
      ])
    let last = try book.editSpace(
      "home", expectedVersion: 2,
      edits: [
        .init(operation: "move", componentID: "tables", at: "last")
      ])
    try expect(last.definition.components.last?.id == "tables")
  }
  check(
    "failed layout publication rolls back history, state and receipts; missing history is detected"
  ) {
    let book = try fixture()
    let revision = try book.revision()
    let commits = try book.committedHistory()
    try book.db.script(
      "CREATE TEMP TRIGGER fail_space BEFORE INSERT ON space_versions WHEN new.version=2 BEGIN SELECT RAISE(ABORT,'fixture publication failure'); END;"
    )
    try refuses {
      _ = try book.editSpace(
        "home", expectedVersion: 1, edits: [.init(operation: "rename", title: "Failed")],
        token: "fault")
    }
    try book.db.script("DROP TRIGGER temp.fail_space")
    try expect(try book.space("home").version == 1 && book.space("home").title == "Home")
    try expect(try book.revision() == revision && book.committedHistory() == commits)
    _ = try book.editSpace(
      "home", expectedVersion: 1, edits: [.init(operation: "rename", title: "Recovered")],
      token: "fault")
    try expect(try book.space("home").version == 2 && book.spaceHistory("home").count == 2)
    _ = try book.verify()
    let raw = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    try raw.execute("DELETE FROM space_versions WHERE id='home' AND version=1")
    try refuses("integrity") { _ = try book.verify() }
  }

}
