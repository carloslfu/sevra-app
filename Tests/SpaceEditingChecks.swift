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
  check(
    "Home app composition shares bindings, survives reopen and resets without changing app data"
  ) {
    let book = try fixture()
    let app = try book.installNativeAppContents(
      NativeAppPackage(
        name: "Orders", source: "Sevra.mount(Sevra.h(Sevra.Text,{text:'Orders'}));", datasets: [:]))
    let initial = try book.space("home")
    let component = Component(id: "orders", type: "app", title: "Orders", spaceID: app.id)
    let tools = WorkbookTools(book)
    let result = try tools.execute(
      "edit_space",
      .object([
        "id": .string("home"), "expectedVersion": .number(Double(initial.version)),
        "edits": try encoded([SpaceEdit(operation: "insert", at: "last", component: component)]),
      ]))
    try expect(result["version"].int == 2)
    try expect(try book.space("home").definition.components.last == component)
    try expect(try Workbook(book.url).space("home").definition.components.last == component)
    try expect(try book.space(app.id).version == 1)
    try refuses("space_conflict") {
      _ = try book.editSpace("home", expectedVersion: 1, edits: [.init(operation: "reset")])
    }
    try refuses("view") {
      _ = try book.editSpace(
        "home", expectedVersion: 2,
        edits: [
          .init(
            operation: "insert", at: "last",
            component: .init(id: "bad", type: "app", title: "Bad", spaceID: "home"))
        ])
    }
    try refuses("view") {
      _ = try book.saveSpace(
        title: "Invalid binding",
        definition: .init(components: [
          .init(type: "text", title: "Text", spaceID: app.id)
        ]))
    }
    let onlyApp = try book.saveSpace(title: "Live", definition: .init(components: [component]))
    try refuses("view_limit") { _ = try book.pinSpace(onlyApp) }
    try refuses("view") {
      _ = try book.editSpace(onlyApp, expectedVersion: 1, edits: [.init(operation: "reset")])
    }
    try refuses("read_only_request") {
      _ = try WorkbookTools(book, readOnly: true).execute(
        "edit_space",
        .object([
          "id": .string("home"), "expectedVersion": .number(2),
          "edits": try encoded([SpaceEdit(operation: "reset")]),
        ]))
    }
    _ = try book.editSpace("home", expectedVersion: 2, edits: [.init(operation: "reset")])
    try expect(try book.space("home").definition == .defaultHome)
    _ = try book.restoreSpace("home", version: 2, expectedVersion: 3)
    try expect(try book.space("home").definition.components.last == component)
    let replay = try book.reconstruct(to: temp.appendingPathComponent(identifier() + ".sevra"))
    try expect(try replay.space("home").definition == book.space("home").definition)
    try expect(try replay.space(app.id).definition.app == book.space(app.id).definition.app)
    try expect(try book.spaceHistory("home").map(\.version) == [4, 3, 2, 1])
    let snapshot = try book.workspaceSnapshot(conversation: book.startChat)!
    try expect(
      snapshot.pendingWorkflows.isEmpty && snapshot.chatApproval == nil
        && snapshot.homeDocuments.isEmpty)
    let evidence = try book.addItem(
      category: "source", kind: "observation", title: "Technical observation", status: "accepted")
    let document = try book.addItem(
      category: "record", kind: "document", title: "Delivery notes", text: "Synthetic draft",
      inputs: [evidence.id])
    try expect(
      try book.workspaceSnapshot(conversation: book.startChat)!.homeDocuments.map(\.id) == [document.id])
    let function = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("function"), "title": .string("Order total"),
        "description": .string("Synthetic"),
        "parameters": .array([]), "payload": .object(["expression": .string("2*2")]),
      ]))
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(), content: book.workflowTemplate(function.id))
    for _ in 0..<6 {
      _ = try book.startWorkflow(workflow.id, arguments: .object([:]), token: identifier())
    }
    let pending = try book.workspaceSnapshot(conversation: book.startChat)!.pendingWorkflows
    try expect(
      pending.count == 4
        && pending.allSatisfy { $0["title"].text == workflow.title && $0["state"].text == "queued" }
    )

    _ = try book.prepareChatApproval(
      action: "app.enable",
      arguments: .object([
        "id": .string(app.id), "expectedVersion": .number(1),
      ]), title: "Enable Orders", conversation: book.startChat)
    try expect(
      try book.workspaceSnapshot(conversation: book.startChat)!.chatApproval?.title == "Enable Orders")
    let empty = SpaceDefinition(components: [
      .init(id: "home-attention", type: "text", title: "Note")
    ])
    let protected = empty.homeComponents(pendingReview: true, pendingAttention: true)
    try expect(protected.count == 2 && protected[0].type == "attention")
    try expect(Set(protected.map(\.id)).count == 2)
    try expect(
      SpaceDefinition.defaultHome.homeComponents(pendingReview: true, pendingAttention: true)
        == SpaceDefinition.defaultHome.components)
    _ = try book.verify()
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
    let edits = [SpaceEdit(operation: "title", componentID: "shortcuts", title: "Recent evidence")]
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
        "home", expectedVersion: 1, edits: [.init(operation: "remove", componentID: "shortcuts")])
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
  check("an insertion beside a comparison's column joins it while it has room") {
    let book = try fixture()
    func text(_ id: String) -> Component { .init(id: id, type: "text", title: id, text: id) }
    let id = try book.saveSpace(
      title: "Side by side",
      definition: .init(components: [
        .init(id: "group", type: "comparison", title: "Together", children: [text("a"), text("b")])
      ]))
    func message(_ body: () throws -> Void) -> String {
      do { try body() } catch { return (error as? SevraError)?.message ?? "\(error)" }
      return "saved"
    }
    let joined = try book.editSpace(
      id, expectedVersion: 1,
      edits: [.init(operation: "insert", beforeID: "b", component: text("c"))])
    try expect(joined.definition.components.map(\.id) == ["group"])
    try expect(joined.definition.components[0].children?.map(\.id) == ["a", "c", "b"])
    // Full, the refusal says where the component can go instead.
    let full = message {
      _ = try book.editSpace(
        id, expectedVersion: 2,
        edits: [.init(operation: "insert", beforeID: "a", component: text("d"))])
    }
    try expect(
      full
        == "a is inside comparison group, which already has three columns. Place the new component before group or with at first or last, or replace group to change its columns.",
      full)
    let unknown = message {
      _ = try book.editSpace(
        id, expectedVersion: 2,
        edits: [.init(operation: "insert", beforeID: "nowhere", component: text("d"))])
    }
    try expect(unknown.hasPrefix("No component is named nowhere."), unknown)
    try expect(try book.space(id).version == 2)
  }
  check("a component with no table says to make one only when the workbook has none") {
    let book = try fixture()
    let metric = SpaceDefinition(components: [
      .init(id: "visits", type: "metric", title: "Visits", aggregation: "COUNT")
    ])
    func message() -> String {
      do { _ = try book.saveSpace(title: "Counts", definition: metric) } catch {
        return (error as? SevraError)?.message ?? "\(error)"
      }
      return "saved"
    }
    let none = message()
    try expect(none.contains("The workbook has no tables yet. Create the table it shows first"), none)
    try expect(!none.contains("do not create"), none)
    _ = try book.chatSQL(
      statements: ["CREATE TABLE visits (customer TEXT)"], readOnly: false, token: identifier(),
      requestSourceID: nil)
    let some = message()
    try expect(some.contains("such as Visits (") || some.contains("such as visits ("), some)
    try expect(some.contains("do not create a table of totals for it"), some)
    try expect(some.contains("If the table it should show does not exist yet, create it first"), some)
  }
  check("a stray or unknown visual says what to change") {
    let book = try fixture()
    let tools = WorkbookTools(book)
    func refusal(_ component: Value) -> String {
      let arguments: Value = .object([
        "title": .string("My Debt"),
        "definition": .object(["version": .number(1), "components": .array([component])]),
      ])
      do { _ = try tools.execute("save_space", arguments) } catch {
        return (error as? SevraError)?.message ?? "\(error)"
      }
      return "saved"
    }
    let button = refusal(
      .object([
        "id": .string("pay"), "type": .string("button"), "title": .string("Pay"),
        "visual": .object(["version": .number(1), "kind": .string("button")]),
      ]))
    try expect(
      button == "definition.components[0] is a button, which does not take a visual. Leave visual out.",
      button)
    let visual = refusal(
      .object([
        "id": .string("debt"), "type": .string("visual"), "title": .string("Debt"),
        "visual": .object(["version": .number(1), "kind": .string("badge")]),
      ]))
    try expect(
      visual.hasSuffix(
        "visual.kind is not a value it accepts. Use one of: image, chart, work, diagram, overview, text."),
      visual)
    // A button's arguments are its tool's inputs, which may be named type and visual. With no
    // such tool saved the refusal is about the tool, not a stray visual.
    let arguments = refusal(
      .object([
        "id": .string("tag"), "type": .string("button"), "title": .string("Tag"),
        "definitionBinding": .object(["tool": .string("tag")]),
        "arguments": .object(["type": .string("x"), "visual": .string("y")]),
      ]))
    try expect(!arguments.contains("does not take a visual"), arguments)
  }
  check("a button whose table nothing shows says to add it") {
    let book = try fixture()
    let tools = WorkbookTools(book)
    _ = try tools.execute(
      "sql", .object(["statements": .array([.string("CREATE TABLE clicks (at TEXT)")])]))
    _ = try tools.execute(
      "save",
      .object([
        "kind": .string("tool"), "name": .string("add_click"),
        "description": .string("Adds a click."), "inputs": .array([]),
        "statements": .array([.string("INSERT INTO clicks (at) VALUES (datetime('now'))")]),
      ]))
    let table = try book.datasets().first { $0.title == "Clicks" }!.id
    let button: Value = .object([
      "id": .string("b"), "type": .string("button"), "title": .string("Click"),
      "definitionBinding": .object(["tool": .string("add_click")]),
    ])
    func save(_ title: String, _ components: [Value]) throws -> Value {
      try tools.execute(
        "save_space",
        .object([
          "title": .string(title),
          "definition": .object(["version": .number(1), "components": .array(components)]),
        ]))
    }
    let alone = try save("Alone", [button])
    try expect(alone["notice"].text.contains("Nothing on this view shows Clicks"), alone["notice"].text)
    let counted = try save(
      "Counted",
      [
        .object([
          "id": .string("n"), "type": .string("metric"), "title": .string("Clicks"),
          "datasetID": .string(table), "aggregation": .string("COUNT"),
        ]), button,
      ])
    try expect(counted["notice"] == .null, counted["notice"].text)
    // A script names its tables in the SQL it runs.
    _ = try tools.execute(
      "save",
      .object([
        "kind": .string("tool"), "name": .string("add_click_script"),
        "description": .string("Adds a click."), "inputs": .array([]),
        "source": .string("await sql(\"INSERT INTO clicks (at) VALUES ('now')\")"),
      ]))
    let script = try save(
      "Script",
      [
        .object([
          "id": .string("s"), "type": .string("button"), "title": .string("Click"),
          "definitionBinding": .object(["tool": .string("add_click_script")]),
        ])
      ])
    try expect(script["notice"].text.contains("which add_click_script changes"), script["notice"].text)
  }
  check("agent layout tools preserve read-only authority and exact saved identities") {
    let book = try fixture()
    let run = try book.startAgentRequest(
      "Hide pinned spaces on Home", conversation: book.startChat, model: "local-test-model"
    ).runID
    let tools = WorkbookTools(book, runID: run)
    let arguments: Value = .object([
      "id": .string("home"), "expectedVersion": .number(1),
      "edits": try encoded([SpaceEdit(operation: "remove", componentID: "shortcuts")]),
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
  check(
    "a move says where, an unplaced insertion goes last, and unrelated fields never become silent edits"
  ) {
    let book = try fixture()
    let initial = try book.space("home")
    let revision = try book.revision()
    for edit in [
      SpaceEdit(operation: "move", componentID: "continue", title: "Tables"),
      SpaceEdit(operation: "move", componentID: "continue"),
      SpaceEdit(operation: "move", componentID: "continue", beforeID: "attention", at: "first"),
      SpaceEdit(operation: "remove", componentID: "shortcuts", text: "Unused"),
      SpaceEdit(
        operation: "insert", component: .init(type: "text", title: "Titled"), title: "Tables"),
    ] {
      try refuses("view") { _ = try book.editSpace("home", expectedVersion: 1, edits: [edit]) }
    }
    try expect(
      try book.revision() == revision && book.space("home").definition == initial.definition)
    let first = try book.editSpace(
      "home", expectedVersion: 1,
      edits: [
        .init(operation: "move", componentID: "continue", at: "first"),
        .init(operation: "remove", componentID: "shortcuts"),
      ])
    try expect(
      first.definition.components.map(\.id) == [
        "continue", "attention",
      ])
    let last = try book.editSpace(
      "home", expectedVersion: 2,
      edits: [
        .init(operation: "move", componentID: "continue", at: "last")
      ])
    try expect(last.definition.components.last?.id == "continue")
    // An insertion that names no position goes last: a default, where a move has none.
    let appended = try book.editSpace(
      "home", expectedVersion: 3,
      edits: [
        SpaceEdit(
          operation: "insert", component: .init(id: "unplaced", type: "text", title: "Unplaced"))
      ])
    try expect(appended.definition.components.last?.id == "unplaced")
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
  check("a table, chart and metric show a query's rows, live, and say when none match or it fails")
  {
    let book = try fixture()
    func sql(_ statements: [String]) throws {
      _ = try book.chatSQL(
        statements: statements, readOnly: false, token: identifier(), requestSourceID: nil)
    }
    try sql([
      "CREATE TABLE invoices (client TEXT, amount REAL, due TEXT, status TEXT)",
      "INSERT INTO invoices VALUES ('Harbor', 850, date('now', '-9 days'), 'open'), ('Leaf', 430.5, date('now', '-2 days'), 'open'), ('Lopez', 980, date('now', '+5 days'), 'open'), ('Pine', 200, date('now', '-20 days'), 'paid')",
    ])
    let invoices = try book.datasets().first { $0.title == "Invoices" }!
    let overdue =
      "SELECT client, amount, due FROM invoices WHERE status = 'open' AND due < date('now') ORDER BY due"
    let table = Component(
      id: "overdue", type: "table", title: "Overdue invoices", datasetID: invoices.id,
      query: overdue)
    let chart = Component(
      id: "by_client", type: "chart", title: "Overdue by client", query: overdue, x: "client",
      y: "amount")
    let total = Component(
      id: "total", type: "metric", title: "Overdue total", query: overdue, aggregation: "SUM")
    var missingY = total
    missingY.id = "nothing"
    // A metric over a query reads one of its result columns; the refusal lists them.
    let refusal = refusalMessage { _ = try book.saveSpace(title: "Bad", definition: .init(components: [missingY])) }
    try expect(refusal.contains("its query's result: client, amount, due"), refusal)
    var totalWithY = total
    totalWithY.y = "amount"
    let id = try book.saveSpace(
      title: "Overdue", definition: .init(components: [table, chart, totalWithY]))
    let data = try book.componentData(table)
    try expect(data.totalRows == 2 && data.rows.map { $0.values["client"]?.text } == ["Harbor", "Leaf"])
    // A result column named like a table column keeps its title and type.
    try expect(data.columns.map(\.title) == ["Client", "Amount", "Due"] && data.columns[1].type == "decimal")
    try expect(try book.componentMetric(totalWithY, data: book.componentData(totalWithY)) == "1280.5")
    // Live: a paid invoice leaves the view with no edit to it.
    try sql(["UPDATE invoices SET status = 'paid' WHERE client = 'Harbor'"])
    try expect(try book.componentData(table).rows.map { $0.values["client"]?.text } == ["Leaf"])
    try sql(["UPDATE invoices SET status = 'paid'"])
    try expect(try book.componentData(chart).rows.isEmpty)
    try expect(try book.componentMetric(totalWithY, data: book.componentData(totalWithY)) == "0")
    // A query that stops running says so, and edits around it still save.
    try sql(["ALTER TABLE invoices RENAME COLUMN amount TO total"])
    let failure = refusalMessage { _ = try book.componentData(chart) }
    try expect(failure.hasPrefix("This view's query no longer runs") && failure.contains("amount"), failure)
    let saved = try book.space(id)
    _ = try book.editSpace(
      id, expectedVersion: saved.version,
      edits: [
        .init(
          operation: "insert", at: "first",
          component: .init(id: "note", type: "text", title: "Note", text: "Ask about late ones."))
      ])
    // A pinned copy keeps the result it had, as a table of values.
    var live = totalWithY
    live.query = "SELECT client, total AS amount FROM invoices"
    let pinnedSource = try book.saveSpace(title: "Pinned", definition: .init(components: [live]))
    let pinned = try book.space(try book.pinSpace(pinnedSource)).definition.components[0]
    try expect(pinned.snapshot?.rows.count == 4)
  }
  check("view fields are refused on types that do not use them, and queries only read") {
    let book = try fixture()
    _ = try book.chatSQL(
      statements: ["CREATE TABLE stock (part TEXT, quantity REAL)"], readOnly: false,
      token: "stock", requestSourceID: nil)
    let stock = try book.datasets()[0]
    func refusal(_ component: Component) -> String {
      refusalMessage { _ = try book.saveSpace(title: identifier(), definition: .init(components: [component])) }
    }
    let text = refusal(.init(id: "note", type: "text", title: "Note", query: "SELECT 1", text: "x"))
    try expect(text.contains("note is a text, which does not use query") && text.contains("table, chart or metric with query"), text)
    let table = refusal(.init(id: "t", type: "table", title: "T", datasetID: stock.id, x: "part", y: "quantity"))
    try expect(table.contains("does not use x, y") && table.contains("x belongs to a chart"), table)
    let write = refusal(.init(id: "t", type: "table", title: "T", query: "DELETE FROM stock"))
    try expect(write.contains("only reads"), write)
    let sneaky = refusal(.init(id: "t", type: "table", title: "T", query: "WITH x AS (SELECT 1) DELETE FROM stock"))
    try expect(sneaky.contains("only reads"), sneaky)
    let two = refusal(.init(id: "t", type: "table", title: "T", query: "SELECT 1; SELECT 2"))
    try expect(two.contains("one SELECT"), two)
    let unknown = refusal(.init(id: "t", type: "table", title: "T", query: "SELECT nope FROM stock"))
    try expect(unknown.hasPrefix("t: ") && unknown.contains("nope"), unknown)
    _ = try book.chatSQL(
      statements: ["CREATE TABLE orders (part TEXT)"], readOnly: false, token: "orders",
      requestSourceID: nil)
    let orders = try book.datasets().first { $0.title == "Orders" }!
    let other = refusal(
      .init(id: "t", type: "table", title: "T", datasetID: orders.id, query: "SELECT part FROM stock"))
    try expect(other.contains("does not read Orders"), other)
  }
  check("inserting a component id the view has says to replace it") {
    let book = try fixture()
    let note = Component(id: "note", type: "text", title: "Note", text: "First")
    let id = try book.saveSpace(title: "Notes", definition: .init(components: [note]))
    var changed = note
    changed.text = "Second"
    let refused = refusalMessage {
      _ = try book.editSpace(
        id, expectedVersion: 1, edits: [.init(operation: "insert", at: "last", component: changed)])
    }
    try expect(refused.contains("operation: \"replace\", componentID: \"note\""), refused)
    let replaced = try book.editSpace(
      id, expectedVersion: 1,
      edits: [.init(operation: "replace", componentID: "note", component: changed)])
    try expect(replaced.definition.components == [changed])
  }
}

/// What a refused call said, or "saved" when nothing refused it.
private func refusalMessage(_ body: () throws -> Void) -> String {
  do { try body() } catch { return (error as? SevraError)?.message ?? "\(error)" }
  return "saved"
}
