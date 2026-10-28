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
    let raw = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    let revision = try book.revision()
    let commits = try book.committedHistory()
    try raw.script(
      "CREATE TRIGGER fail_space BEFORE INSERT ON space_versions WHEN new.version=2 BEGIN SELECT RAISE(ABORT,'fixture publication failure'); END;"
    )
    try refuses {
      _ = try book.editSpace(
        "home", expectedVersion: 1, edits: [.init(operation: "rename", title: "Failed")],
        token: "fault")
    }
    try raw.script("DROP TRIGGER fail_space")
    try expect(try book.space("home").version == 1 && book.space("home").title == "Home")
    try expect(try book.revision() == revision && book.committedHistory() == commits)
    _ = try book.editSpace(
      "home", expectedVersion: 1, edits: [.init(operation: "rename", title: "Recovered")],
      token: "fault")
    try expect(try book.space("home").version == 2 && book.spaceHistory("home").count == 2)
    _ = try book.verify()
    try raw.execute("DELETE FROM space_versions WHERE id='home' AND version=1")
    try refuses("integrity") { _ = try book.verify() }
  }

}
