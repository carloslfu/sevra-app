import Foundation
import SevraAI

@testable import SevraCore

private actor SpaceActionModel: WorkbookInference {
  let identity = "synthetic space actions"
  let lastMetrics: Value = .object(["fixture": .bool(true)])
  let actions: [(String, Value)]
  var calls = 0
  init(_ actions: [(String, Value)]) { self.actions = actions }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    let index = calls
    calls += 1
    if index < actions.count {
      return .init(
        text: "",
        calls: [
          try .init(
            id: "space-\(index)", operation: actions[index].0, actions[index].1, scope: toolScope)
        ])
    }
    let refused = messages.last?.content.contains("error") == true
    return .init(
      text: "",
      calls: [
        .init(
          id: "finish", name: "finish",
          inputJSON: try Value.object([
            "answer": .string(
              refused ? "No shortcut was changed." : "The requested actions are complete."),
            "basis": .string(refused ? "general" : "completed_action"), "citations": .array([]),
          ]).json())
      ])
  }
}

@MainActor func checkSpaceActions() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-space-actions-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root, title: "Space actions")
  let id = try book.saveSpace(title: "Purchasing", definition: .init(components: []))
  let definitions = try encoded(book.spaces())
  let target: Value = .object(["target": .string("Purchasing")])
  let pin: Value = .object(["target": .string("Purchasing"), "pinned": .bool(true)])
  let unpin: Value = .object(["target": .string("Purchasing"), "pinned": .bool(false)])
  var opened: [String] = []
  let model = SpaceActionModel([
    ("set_space_pinned", pin), ("open_space", target),
    ("sql", .object(["statements": .array([.string("SELECT 9 - 2")])])),
  ])
  _ = try await WorkbookAgent.run(
    "Pin Purchasing, open it and calculate 9 minus 2.", workbook: book, model: model,
    openSpace: { opened.append($0.id) })
  try expectEqual(opened, [id])
  try expectEqual(await model.calls, 4)
  try expectEqual(try book.workspaceSnapshot(conversation: book.startChat)!.spaceNavigation.pinned, [id])
  try expectEqual(try encoded(book.spaces()), definitions)
  let ordered = try await WorkbookAgent.run(
    "Save a space called Overview, then open Purchasing.", workbook: book,
    model: SpaceActionModel([
      (
        "save_space",
        .object([
          "title": .string("Overview"),
          "definition": .object([
            "version": .number(1), "components": .array([]),
          ]),
        ])
      ), ("open_space", target),
    ]), openSpace: { opened.append($0.id) })
  try expectEqual(ordered.focus == nil, true)
  try expectEqual(opened.last, id)
  try expectEqual(try book.spaceTarget("Overview").title, "Overview")
  let receipts = try book.agentRuns()
  try expectEqual(receipts.last?["status"].text, "complete")
  _ = try await WorkbookAgent.run(
    "Unpin Purchasing.", workbook: book, model: SpaceActionModel([("set_space_pinned", unpin)]))
  try expectEqual(try book.workspaceSnapshot(conversation: book.startChat)!.spaceNavigation.pinned, [])
  _ = try await WorkbookAgent.run(
    "Explain only.", workbook: book, model: SpaceActionModel([("set_space_pinned", pin)]))
  try expectEqual(try book.workspaceSnapshot(conversation: book.startChat)!.spaceNavigation.pinned, [])

  for unavailable in [true, false] {
    let probe = SpaceActionModel([("open_space", target)])
    var opener: SpaceOpener?
    if !unavailable {
      opener = { _ in
        throw SevraError("workspace_changed", "You moved elsewhere. No space was opened.")
      }
    }
    let result = try await WorkbookAgent.run(
      "Take me to Purchasing.", workbook: book, model: probe, openSpace: opener)
    try expectEqual(await probe.calls, 1)
    try expectEqual(
      result.answer.contains("No space was opened") || result.answer.contains("No view was opened"),
      true)
    try expectEqual(result.focus == nil, true)
  }
  var reviewOpenings = 0
  let reviews = SpaceActionModel([("open_reviews", .object([:]))])
  let shown = try await WorkbookAgent.run(
    "Show my pending drafts.", workbook: book, model: reviews,
    openReviews: { reviewOpenings += 1 })
  try expectEqual(reviewOpenings, 1)
  try expectEqual(shown.steps, 2)
  let unavailableReviews = SpaceActionModel([("open_reviews", .object([:]))])
  let refusedReviews = try await WorkbookAgent.run(
    "Show my pending drafts.", workbook: book,
    model: unavailableReviews)
  try expectEqual(await unavailableReviews.calls, 1)
  try expectEqual(refusedReviews.answer.contains("No view was opened"), true)
  try expectThrows(try WorkbookTools(book, readOnly: true).execute("open_reviews", .object([:])))

  // Asking for an automation reaches its native review. It enables nothing, and only an exact
  // name gets there.
  func automation(_ title: String) throws -> ApplicationDefinition {
    let function = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("function"), "title": .string(title + " rule"),
        "description": .string("Synthetic"), "parameters": .array([]),
        "payload": .object(["expression": .string("2*2"), "unit": .string("items")]),
      ]))
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(), content: book.workflowTemplate(function.id))
    return try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("automation"), "title": .string(title),
        "description": .string("Synthetic"), "parameters": .array([]),
        "payload": .object([
          "policy": .string("calendar-v1"),
          "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow.id)]),
          "arguments": .object([:]),
          "schedule": .object([
            "policy": .string("native-calendar-v1"), "timeZone": .string("America/Bogota"),
            "hour": .number(9), "minute": .number(0),
            "recurrence": .object(["kind": .string("weekly"), "weekdays": .array([.number(1)])]),
          ]),
        ]),
      ]))
  }
  let weekly = try automation("Weekly stock check")
  func opening(_ target: String, window: Bool = true) async throws -> AgentResult {
    try await WorkbookAgent.run(
      "Enable " + target, workbook: book,
      model: SpaceActionModel([("open_automation", .object(["target": .string(target)]))]),
      openSpace: window ? { _ in } : nil)
  }
  let reviewed = try await opening("weekly STOCK check")
  try expectEqual(reviewed.focus?.kind, "automation")
  try expectEqual(reviewed.focus?.id, weekly.id)
  try expectEqual(reviewed.steps, 1)
  try expectEqual(reviewed.answer.contains("Nothing was enabled"), true)
  _ = try automation("Stock [check](https://example.com)")
  let linked = try await opening("Stock [check](https://example.com)")
  try expectEqual(linked.answer.hasPrefix("Review “Stock \\[check\\](https://example.com)”"), true)
  let noWindow = try await opening("Weekly stock check", window: false)
  try expectEqual(noWindow.answer.contains("No view was opened"), true)
  try expectEqual(noWindow.focus == nil, true)
  let unknown = try await opening("Weekly stock")
  try expectEqual(unknown.answer.contains("No saved automation has that exact name"), true)
  try expectEqual(unknown.focus == nil, true)
  _ = try automation("Weekly stock check")
  let twoNamed = try await opening("Weekly stock check")
  try expectEqual(twoNamed.answer.contains("More than one automation"), true)
  try expectEqual(twoNamed.focus == nil, true)

  // Exact history is reviewable even after its head changes. Names and logical IDs
  // still resolve current versions, and a title cannot shadow an explicit ID.
  var renamedContent = weekly.content.object
  renamedContent["title"] = .string("Current weekly check")
  let renamed = try book.saveApplicationDefinition(
    logicalID: weekly.logicalID, content: .object(renamedContent),
    expectedDefinitionID: weekly.id)
  _ = try automation(weekly.id)
  let historical = try await opening(weekly.id)
  try expectEqual(historical.focus?.id, weekly.id)
  try expectEqual(historical.answer.contains("Nothing was enabled"), true)
  try expectEqual(try book.automationTarget(weekly.logicalID).id, renamed.id)
  try expectEqual(try book.automationTarget("Current weekly check").id, renamed.id)
  try expectEqual(try book.automationTarget("Weekly stock check").id != weekly.id, true)
  try expectEqual(try book.automationTarget(renamed.id).id, renamed.id)
  try expectEqual(try book.workflowRuns().isEmpty, true)
  try expectEqual(try book.automationActivations()["activations"].array.isEmpty, true)

  // A plain request for a draft gets one correction if the model only answers in chat.
  try expectEqual(DraftRequest.asks("Draft a brief summary of the report."), true)
  try expectEqual(DraftRequest.asks("Please write me a short draft of it."), true)
  try expectEqual(DraftRequest.asks("Redacta un borrador breve en español."), true)
  try expectEqual(DraftRequest.asks("What does the draft say?"), false)
  try expectEqual(DraftRequest.asks("Can you write a short draft of it?"), true)
  try expectEqual(
    DraftRequest.asks("Should I make a draft order for Brio or wait for tax terms?"), false)
  try expectEqual(DraftRequest.asks("Did you make a draft yet?"), false)
  try expectEqual(DraftRequest.asks("How do I create a draft?"), false)
  try expectEqual(DraftRequest.asks("¿Cómo hago un borrador?"), false)
  try expectEqual(DraftRequest.asks("Show my pending drafts."), false)
  let chatAnswer: Value = .object([
    "answer": .string("Here it is in chat."), "basis": .string("general"),
    "citations": .array([]),
  ])
  let corrected = SpaceActionModel([
    ("finish", chatAnswer),
    (
      "draft",
      .object(["title": .string("Note"), "text": .string("New words."), "inputs": .array([])])
    ),
  ])
  let drafting = try Workbook.create(
    at: FileManager.default.temporaryDirectory.appendingPathComponent(identifier() + ".sevra"),
    title: "Drafts")
  defer { try? FileManager.default.removeItem(at: drafting.url) }
  let saved = try await WorkbookAgent.run(
    "Draft a short note about delivery.", workbook: drafting, model: corrected)
  try expectEqual(saved.state, "complete")
  try expectEqual(await corrected.calls, 3)
  try expectEqual(try drafting.items(kind: "document").contains { $0.title == "Note" }, true)
  // A second answer ends the run, so a false alarm can never trap it.
  let answeredTwice = SpaceActionModel([("finish", chatAnswer), ("finish", chatAnswer)])
  let notDraft = try await WorkbookAgent.run(
    "Draft dates are in the report, right?", workbook: drafting, model: answeredTwice)
  try expectEqual(notDraft.state, "complete")
  try expectEqual(await answeredTwice.calls, 2)
  let readQueue = try WorkbookTools(book, readOnly: true).execute("review_queue", .object([:]))
  try expectEqual(readQueue["items"].array.isEmpty, true)
  _ = try book.saveSpace(title: "Purchasing", definition: .init(components: []))
  let ambiguous = SpaceActionModel([("set_space_pinned", pin)])
  let clarification = try await WorkbookAgent.run(
    "Pin Purchasing.", workbook: book, model: ambiguous)
  try expectEqual(await ambiguous.calls, 1)
  try expectEqual(clarification.answer.contains("More than one space"), true)
  try expectEqual(try book.workspaceSnapshot(conversation: book.startChat)!.spaceNavigation.pinned, [])
  try expectEqual(try book.spaceTarget(id).id, id)
  try expectThrows(try book.spaceTarget("Purch"))
  try expectEqual(
    try WorkbookTools(book).execute("open_space", .object(["target": .string(id)]))["status"].text,
    "resolved")
  try expectThrows(try WorkbookTools(book, readOnly: true).execute("open_space", target))
  try expectEqual(try book.verify()["ok"], .bool(true))
  let homeBook = try Workbook.create(
    at: root.appendingPathComponent("Home.sevra"), title: "Home actions")
  let app = try homeBook.installNativeAppContents(
    NativeAppPackage(
      name: "Orders", source: "Sevra.mount(Sevra.h(Sevra.Text,{text:'Orders'}));", datasets: [:]))
  let embed: Value = .object([
    "id": .string("home"), "expectedVersion": .number(1),
    "edits": try encoded([
      SpaceEdit(
        operation: "insert", at: "last",
        component:
          Component(id: "orders", type: "app", title: "Orders", spaceID: app.id))
    ]),
  ])
  _ = try await WorkbookAgent.run(
    "Show Orders on Home as a live app view.", workbook: homeBook,
    model: SpaceActionModel([("spaces", .object([:])), ("edit_space", embed)]))
  try expectEqual(try homeBook.space("home").definition.components.last?.spaceID, app.id)
  try expectEqual(try homeBook.space(app.id).version, 1)
  let reset: Value = .object([
    "id": .string("home"), "expectedVersion": .number(2),
    "edits": try encoded([SpaceEdit(operation: "reset")]),
  ])
  _ = try await WorkbookAgent.run(
    "Explain only how Home reset works.", workbook: homeBook,
    model: SpaceActionModel([("edit_space", reset)]))
  try expectEqual(try homeBook.space("home").version, 2)
  _ = try await WorkbookAgent.run(
    "Reset Home to default.", workbook: homeBook,
    model: SpaceActionModel([("edit_space", reset)]))
  try expectEqual(try Workbook(homeBook.url).space("home").definition, SpaceDefinition.defaultHome)
  try expectEqual(try homeBook.spaceHistory("home").map(\.version), [3, 2, 1])
  // An edit as the model writes it under its grammar: the component before any position,
  // an empty text where it reached for a field it had passed, and a replacement that names
  // its target only by the component's own ID. The insertion goes last.
  let asWritten = try homeBook.editSpace(
    "home", expectedVersion: 3,
    edits: [
      SpaceEdit(
        operation: "replace",
        component: Component(id: "attention", type: "attention", title: "Needs attention"),
        text: ""),
      SpaceEdit(
        operation: "insert",
        component: Component(id: "note", type: "text", title: "Note", text: "Hello"), text: ""),
    ])
  try expectEqual(
    asWritten.definition.components.map(\.id), ["attention", "continue", "shortcuts", "note"])
  // Counterexamples: a move still says where, and text that carries something is refused
  // on an insertion, with the order to write the fields in.
  try expectThrows(
    try homeBook.editSpace(
      "home", expectedVersion: 4, edits: [SpaceEdit(operation: "move", componentID: "note")]))
  do {
    _ = try homeBook.editSpace(
      "home", expectedVersion: 4,
      edits: [
        SpaceEdit(
          operation: "insert",
          component: Component(id: "other", type: "text", title: "Other", text: "x"),
          text: "first")
      ])
    throw SevraError("fixture", "Text on an insertion was accepted.")
  } catch let error as SevraError where error.code == "view" {
    try expectEqual(
      error.message.hasSuffix("in this order: operation, at, beforeID, component."), true)
  }
  // A count is of rows: it needs no column, and it reads 0 over an empty table. A total
  // still names the column it adds up.
  _ = try WorkbookTools(homeBook).execute(
    "sql", .object(["statements": .array([.string("CREATE TABLE items (name TEXT)")])]))
  let items = try homeBook.datasets().first { $0.title == "Items" }!.id
  let counted = try homeBook.editSpace(
    "home", expectedVersion: 4,
    edits: [
      SpaceEdit(
        operation: "insert", at: "first",
        component: Component(
          id: "counter", type: "metric", title: "Items", datasetID: items, aggregation: "COUNT"))
    ])
  let counter = counted.definition.components[0]
  try expectEqual(
    try homeBook.componentMetric(counter, data: try homeBook.componentData(counter)), "0")
  try expectThrows(
    try homeBook.editSpace(
      "home", expectedVersion: 5,
      edits: [
        SpaceEdit(
          operation: "insert",
          component: Component(id: "total", type: "metric", title: "Total", datasetID: items))
      ]))
  // A button runs a saved tool. The tool is the action, so the same component counts a visit,
  // adds a named row or changes one, and a press can be taken back like any change. Inputs
  // the button does not set itself are filled in by the person who presses it.
  func tool(_ name: String, _ inputs: [(name: String, type: String)], _ statement: String) throws {
    _ = try homeBook.chatSaveTool(
      name: name, description: "", inputs: inputs, statements: [statement], source: nil,
      token: "tool-" + name, requestSourceID: nil)
  }
  try tool("log_item", [], "INSERT INTO items (name) VALUES (NULL)")
  try tool("add_item", [("name", "text")], "INSERT INTO items (name) VALUES (:name)")
  try tool(
    "rename_item", [("old", "text"), ("new", "text")],
    "UPDATE items SET name = :new WHERE name = :old")
  // A tool that touches no table does nothing when run, and a button over it counts nothing.
  do {
    try tool("counter", [], "SELECT 1 AS result")
    throw SevraError("fixture", "A tool that touches no table was saved.")
  } catch let error as SevraError where error.code == "tool" {
    try expectEqual(error.message.hasPrefix("Tool counter reads and changes no table"), true)
  }
  try tool("item_count", [], "SELECT count(*) AS items FROM items")
  // A tool over a table that does not exist yet says to create the table first.
  do {
    try tool("add_expense", [("amount", "decimal")], "INSERT INTO expenses (amount) VALUES (:amount)")
    throw SevraError("fixture", "A tool over a missing table was saved.")
  } catch let error as SevraError where error.code == "sql" {
    try expectEqual(
      error.message,
      "There is no table expenses yet. Create it first with sql (CREATE TABLE ...), then save the tool.")
  }
  func edit(_ edits: [SpaceEdit]) throws -> Space {
    try homeBook.editSpace("home", expectedVersion: homeBook.space("home").version, edits: edits)
  }
  func button(_ id: String, _ tool: String, _ fixed: [String: Value]? = nil, size: String? = nil)
    -> Component
  {
    Component(
      id: id, type: "button", title: id, definitionBinding: .object(["tool": .string(tool)]),
      arguments: fixed.map(Value.object), size: size)
  }
  let pressable = try edit([
    SpaceEdit(
      operation: "replace",
      component: Component(
        id: "counter", type: "metric", title: "Items", datasetID: items, aggregation: "COUNT",
        size: "large")),
    SpaceEdit(operation: "insert", component: button("log", "log_item", size: "large")),
    SpaceEdit(operation: "insert", component: button("add", "add_item")),
    SpaceEdit(operation: "insert", component: button("bolt", "add_item", ["name": .string("Bolt")])),
    SpaceEdit(
      operation: "insert", component: button("rename", "rename_item", ["new": .string("Nut")])),
    SpaceEdit(
      operation: "insert", component: Component(id: "big", type: "text", title: "Note", text: "Hi", size: "large")),
  ])
  try expectEqual(pressable.definition.component("counter")?.size, "large")
  func count() throws -> String {
    let counter = try expectValue(try homeBook.space("home").definition.component("counter"))
    return try homeBook.componentMetric(counter, data: try homeBook.componentData(counter))
  }
  let first = try homeBook.pressButton(spaceID: "home", componentID: "log")
  try expectEqual(Workbook.describeRun(first), "Added 1 row.")
  let second = try homeBook.pressButton(spaceID: "home", componentID: "log")
  try expectEqual(try count(), "2")
  try homeBook.undoButtonPress(try expectValue(second["undo"].string))
  try expectEqual(try count(), "1")
  try homeBook.pressButton(spaceID: "home", componentID: "add", values: ["name": .string("Washer")])
  try homeBook.pressButton(spaceID: "home", componentID: "bolt")
  try expectEqual(try count(), "3")
  let changedName = try homeBook.pressButton(
    spaceID: "home", componentID: "rename", values: ["old": .string("Bolt")])
  try expectEqual(Workbook.describeRun(changedName), "Changed 1 row.")
  let itemColumns = try homeBook.dataset(items).columns
  try expectEqual(
    try homeBook.rows(items).map { homeBook.calculatedValues($0, columns: itemColumns)["name"] }
      .filter { $0 == .string("Nut") }.count, 1)
  // Counterexamples: only a button can be pressed; the person cannot leave out an input the
  // button does not set, nor override one it does; a tool this Mac has not enabled does not
  // run; a button names a saved tool and only that tool's inputs; a size has three values and
  // belongs to a table, chart, metric, text or button; a snapshot cannot hold a button.
  try expectThrows(try homeBook.pressButton(spaceID: "home", componentID: "counter"))
  try expectThrows(try homeBook.pressButton(spaceID: "home", componentID: "add"))
  try expectThrows(
    try homeBook.pressButton(spaceID: "home", componentID: "bolt", values: ["name": .string("X")]))
  // A null argument is an input left for the person, as a model writes one it means to leave
  // open, and pressing without it says what to fill in.
  _ = try edit([SpaceEdit(operation: "insert", component: button("ask", "add_item", ["name": .null]))])
  do {
    try homeBook.pressButton(spaceID: "home", componentID: "ask")
    throw SevraError("fixture", "A button ran without a required input.")
  } catch let error as SevraError where error.code == "tool_inputs" {
    try expectEqual(error.message, "Fill in name before pressing this button. Nothing ran.")
  }
  try homeBook.pressButton(spaceID: "home", componentID: "ask", values: ["name": .string("Pin")])
  _ = try edit([SpaceEdit(operation: "remove", componentID: "ask")])
  let logTool = try expectValue(try homeBook.savedTools().first { $0.name == "log_item" })
  try homeBook.disableTool(logTool.definitionID)
  do {
    try homeBook.pressButton(spaceID: "home", componentID: "log")
    throw SevraError("fixture", "A tool this Mac has not enabled ran.")
  } catch let error as SevraError where error.code == "tool_disabled" {}
  try homeBook.enableTool(logTool.definitionID)
  for refused in [
    Component(id: "bare", type: "button", title: "Add"),
    button("unknown", "no_such_tool"),
    button("stray", "add_item", ["colour": .string("red")]),
    button("blank", "add_item", ["name": .string("")]),
    button("placeholder", "add_item", ["name": .string(":name")]),
    button("huge", "log_item", size: "huge"),
  ] {
    try expectThrows(try edit([SpaceEdit(operation: "insert", component: refused)]))
  }
  // A size on a type that has none changes nothing, so it is left out instead of refused.
  let unsized = try edit([
    SpaceEdit(
      operation: "insert",
      component: Component(id: "sized", type: "search", title: "Find", query: "bolt", size: "large"))
  ])
  try expectEqual(unsized.definition.components.first { $0.id == "sized" }?.size, nil)
  _ = try edit([SpaceEdit(operation: "remove", componentID: "sized")])
  // An edit that changes nothing is refused and keeps the version, naming a field to include.
  let before = try homeBook.space("home")
  let savedCounter = try expectValue(before.definition.component("counter"))
  for same in [
    SpaceEdit(operation: "replace", component: savedCounter),
    SpaceEdit(operation: "title", componentID: "counter", title: savedCounter.title),
  ] {
    do {
      _ = try edit([same])
      throw SevraError("fixture", "An edit that changes nothing was saved.")
    } catch let error as SevraError where error.code == "nothing_changed" {
      try expectEqual(
        error.message,
        "Nothing changed: counter already has these values. It already shows aggregation COUNT, size large. If the user asked for what it already shows, say so. To change it, include the field that changes, for example aggregation. To add something beside it, such as a total, insert a new component, such as a metric.")
    }
  }
  try expectEqual(try homeBook.space("home").version, before.version)
  // The repeated-call guard counts a retry against a newer version as the same call.
  func call(_ version: Int) -> Value {
    .object([
      "tool": .string("run"),
      "arguments": .object([
        "action": .string("view.edit"),
        "arguments": .object([
          "id": .string("home"), "expectedVersion": .number(Double(version)),
          "edits": .array([]),
        ]),
      ]),
    ])
  }
  try expectEqual(try WorkbookAgent.repeatKey(call(3)), try WorkbookAgent.repeatKey(call(4)))
  let buttons = try homeBook.saveSpace(
    title: "Buttons", definition: .init(components: [button("log", "log_item")]))
  try expectThrows(try homeBook.pinSpace(buttons))
  // A count is of every row, past the 1,000 a total loads. A total of nothing is 0, a blank cell
  // is not a number yet, and an average of nothing has no value.
  func metric(_ aggregation: String, _ cells: [String], total: Int? = nil) throws -> String {
    try homeBook.componentMetric(
      Component(type: "metric", title: "M", y: "v", aggregation: aggregation),
      data: ComponentSnapshot(
        columns: [Column(id: "v", title: "V", type: "decimal")],
        rows: cells.enumerated().map { ComponentRow(id: "r\($0.offset)", values: ["v": .string($0.element)]) },
        totalRows: total ?? cells.count, captured: ""))
  }
  try expectEqual(try metric("COUNT", Array(repeating: "", count: 1_000), total: 1_500), "1500")
  try expectEqual(try metric("SUM", []), "0")
  try expectEqual(try metric("SUM", ["2", "", "3.5"]), "5.5")
  try expectEqual(try metric("AVERAGE", ["", " "]), "No values yet")
  try expectThrows(try metric("SUM", ["2", "two"]))
  try expectThrows(try metric("SUM", ["1"], total: 1_001))
  // AUTOINCREMENT numbers rows as an INTEGER PRIMARY KEY does, and a UNIQUE column or a text
  // key is kept as a unique column, not refused as an index the statement never wrote.
  _ = try homeBook.chatSQL(
    statements: [
      "CREATE TABLE visits (id INTEGER PRIMARY KEY AUTOINCREMENT, who TEXT)",
      "CREATE TABLE counts (id INTEGER PRIMARY KEY, name TEXT UNIQUE, value INTEGER)",
      "CREATE TABLE invoices2 (number TEXT PRIMARY KEY, status TEXT)",
    ], readOnly: false, token: "autoincrement", requestSourceID: nil)
  let kept = try homeBook.datasets()
  try expectEqual(kept.first { $0.title == "Visits" }?.columns.first?.autoNumber, true)
  try expectEqual(kept.first { $0.title == "Counts" }?.columns.map(\.distinct), [true, true, false])
  try expectEqual(kept.first { $0.title == "Invoices2" }?.columns.first?.required, true)
  // A real index statement keeps its own message.
  do {
    _ = try homeBook.chatSQL(
      statements: ["CREATE INDEX items_name ON items (name)"], readOnly: false, token: "index",
      requestSourceID: nil)
    throw SevraError("fixture", "CREATE INDEX was accepted.")
  } catch let error as SevraError where error.code == "sql_shape" {
    try expectEqual(error.message.hasPrefix("sql can create, alter and drop tables."), true)
  }
  // The word inside a quoted value is data.
  _ = try homeBook.chatSQL(
    statements: [
      "CREATE TABLE sql_notes (id INTEGER PRIMARY KEY, body TEXT)",
      "INSERT INTO sql_notes (body) VALUES ('Use AUTOINCREMENT only when ''reuse'' matters')",
    ], readOnly: false, token: "autoincrement-value", requestSourceID: nil)
  // A malformed call names the field to fix, not Foundation's "data is missing".
  do {
    _ = try WorkbookTools(homeBook).execute(
      "edit_space",
      .object([
        "id": .string("home"), "expectedVersion": .number(Double(try homeBook.space("home").version)),
        "edits": .array([.object(["at": .string("last")])]),
      ]))
    throw SevraError("fixture", "An edit with no operation was accepted.")
  } catch let error as SevraError where error.code == "arguments" {
    try expectEqual(error.message, "edits[0].operation is missing.")
  }
  print("PASS a button runs any saved tool, takes the person's inputs and can be undone; sizes and refusals; a tool over a missing table and an edit that changes nothing are refused")
  print("PASS chat Home composition, default reset, history, reopen and read-only refusal")
  print(
    "PASS scoped space opening, compound continuation, shortcut/snapshot separation, read-only denial and terminal ambiguity/window refusal"
  )
}
