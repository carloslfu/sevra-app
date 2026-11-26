import Foundation
import SevraAI
import SevraAppProtocol
import SevraCore

/// Fixes from a real-model re-run of exploratory scenarios, November 26, 2026: a failure that a
/// later save of the same thing settled no longer reads as unfinished, a view that cannot be
/// opened here does not replace the account of what was saved, the same refused call stops the
/// request on its second try, a script tool is tried once before it is saved, and the refusals
/// a model met first say what to send. No model runs.
func checkRunFollowups() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-run-followups-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  func book(_ name: String) throws -> Workbook {
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    _ = try book.chatSQL(
      statements: [
        "CREATE TABLE expenses (item TEXT, amount REAL)",
        "INSERT INTO expenses (item, amount) VALUES ('Paper', 12), ('Ink', 30)",
      ], readOnly: false, token: "fixture-" + identifier(), requestSourceID: nil)
    return book
  }
  func table(_ id: String, _ dataset: String) -> Value {
    .object([
      "id": .string(id), "type": .string("table"), "title": .string("Expenses"),
      "datasetID": .string(dataset),
    ])
  }

  // A failed save of Home, then an edit of Home that worked: the failure is settled, and the
  // model's summary stands above the host's line.
  let sales = try book("Sales")
  let expenses = try sales.chatTableID("expenses")
  let settled = try await WorkbookAgent.run(
    "Put my expenses on Home.", workbook: sales,
    model: ScriptedCalls([
      call(
        "save_space",
        .object([
          "title": .string("Home"),
          "definition": .object([
            "version": .number(1), "components": .array([table("t1", "dataset1")]),
          ]),
        ])),
      call(
        "edit_space",
        .object([
          "id": .string("home"), "expectedVersion": .number(1),
          "edits": .array([
            .object([
              "operation": .string("insert"), "at": .string("last"),
              "component": table("t1", expenses),
            ])
          ]),
        ])),
      finish("I added the Expenses table to Home.", basis: "completed_action"),
    ]))
  try expectEqual(settled.answer, "I added the Expenses table to Home.\n\nUpdated space “Home”.")

  // The same rule, unit by unit. A definition saved after a failure that named no kind or
  // title is settled by the same payload; another payload, or another view, is not.
  let payload: Value = .object(["policy": .string("check-v1"), "alert": .string("Over 500.")])
  var definitions = ActionConfirmations()
  definitions.recordFailure(
    tool: "save_definition", arguments: .object(["content": .object(["payload": payload])]),
    result: .object(["error": .string("Use content {kind,title,...}.")]), receiptID: "r1")
  definitions.record(
    tool: "save_definition",
    arguments: .object([
      "content": .object([
        "kind": .string("automation"), "title": .string("Expense alert"), "payload": payload,
      ])
    ]), result: .object(["id": .string("d1"), "title": .string("Expense alert")]),
    receiptID: "r2")
  try expectEqual(definitions.rendered?.contains("Couldn’t"), false)
  try expectEqual(definitions.keepsSummary, true)
  var other = ActionConfirmations()
  other.recordFailure(
    tool: "save_definition",
    arguments: .object(["content": .object(["payload": .object(["alert": .string("Other.")])])]),
    result: .object(["error": .string("Use content {kind,title,...}.")]), receiptID: "r1")
  other.record(
    tool: "save_definition",
    arguments: .object([
      "content": .object([
        "kind": .string("automation"), "title": .string("Expense alert"), "payload": payload,
      ])
    ]), result: .object(["id": .string("d1"), "title": .string("Expense alert")]),
    receiptID: "r2")
  try expectEqual(other.rendered?.contains("Couldn’t finish saving reusable behavior."), true)
  var views = ActionConfirmations()
  views.recordFailure(
    tool: "save_space", arguments: .object(["title": .string("Sales")]),
    result: .object(["error": .string("No table has the id or name dataset1.")]), receiptID: "r1")
  views.record(
    tool: "edit_space", arguments: .object(["id": .string("home")]),
    result: .object(["spaceID": .string("home"), "title": .string("Home")]), receiptID: "r2")
  try expectEqual(views.rendered?.contains("Couldn’t finish saving the space."), true)
  try expectEqual(views.keepsSummary, false)
  print("PASS a failed save is settled by a later save or edit of the same view or definition, and only that one")

  // A view that cannot be opened here, after a save: the model still gives its account.
  let opened = try book("Opened")
  let shown = try await WorkbookAgent.run(
    "Track my expenses.", workbook: opened,
    model: ScriptedCalls([
      call(
        "save_space",
        .object([
          "title": .string("Monthly"),
          "definition": .object([
            "version": .number(1),
            "components": .array([table("t1", try opened.chatTableID("expenses"))]),
          ]),
        ])),
      call("open_space", .object(["target": .string("Monthly")])),
      finish("I made a Monthly view of your expenses.", basis: "completed_action"),
    ]))
  try expectEqual(shown.answer, "I made a Monthly view of your expenses.\n\nSaved space “Monthly”.")
  // With nothing saved, the refusal is still the answer.
  let nothing = try await WorkbookAgent.run(
    "Open Monthly.", workbook: opened,
    model: ScriptedCalls([call("open_space", .object(["target": .string("Monthly")]))]))
  try expectEqual(
    nothing.answer, "Opening a space requires the active workbook window. No view was opened.")
  print("PASS a view that cannot be opened here leaves the model's account of what was saved")

  // The same refused call twice: the request closes, and the model gives the account.
  let again = try book("Repeated")
  let insert: Value = .object([
    "id": .string("home"), "expectedVersion": .number(1),
    "edits": .array([
      .object([
        "operation": .string("insert"), "componentID": .string("shortcuts"),
        "component": table("t2", try again.chatTableID("expenses")),
      ])
    ]),
  ])
  let repeated = ScriptedCalls([
    call("edit_space", insert), call("edit_space", insert),
    finish("I could not add the table to Home.", basis: "unresolved"),
  ])
  let stopped = try await WorkbookAgent.run(
    "Add my expenses to Home again.", workbook: again, model: repeated)
  try expectEqual(stopped.steps, 3)
  let closing = try expectValue(await repeated.prompts.last?.first?.content)
  try expectEqual(
    closing.contains("Host stop: The same call was refused twice, so sending it again will not help."),
    true)
  let refusal = try expectValue(await repeated.prompts.dropFirst().first?.last?.content)
  try expectEqual(refusal.contains("An insert has no componentID"), true)
  try expectEqual(refusal.contains("with beforeID: the id of the component it goes before"), true)
  print("PASS the same refused call stops the request on its second try with the model's account")

  // Fields a retry dropped are named together; a button names its tool's exact shape.
  let fields = try book("Fields")
  _ = try fields.chatSaveTool(
    name: "log_water", description: "", inputs: [], statements: [
      "INSERT INTO expenses (item) VALUES ('Water')"
    ], source: nil, token: "tool-log-water", requestSourceID: nil)
  func refusedEdit(_ components: [Component]) throws -> String {
    do {
      _ = try fields.editSpace(
        "home", expectedVersion: try fields.space("home").version,
        edits: components.map { SpaceEdit(operation: "insert", component: $0) })
    } catch let error as SevraError { return error.message }
    throw SevraError("fixture", "An incomplete component was saved.")
  }
  try expectEqual(
    try refusedEdit([
      Component(id: "m1", type: "metric", title: "Cost"),
      Component(
        id: "c1", type: "chart", title: "Cost by item", datasetID: try fields.chatTableID("expenses")),
    ]).hasPrefix(
      "Components lack fields they need: m1 (metric) needs datasetID or query and y; c1 (chart) needs x and y."
    ), true)
  try expectEqual(
    try refusedEdit([Component(id: "b1", type: "button", title: "Log")]).hasSuffix(
      #"Saved tools: {tool: "log_water"}."#), true)
  let unbound = try refusedEdit([
    Component(id: "b1", type: "button", title: "Log", definitionBinding: .object(["tool": .string("add_water")]))
  ])
  try expectEqual(
    unbound.hasPrefix(
      "No saved tool is named add_water. Save the tool first with save {tool}, then add the button."),
    true)
  print("PASS a view's refusal names every missing field at once and the button's exact binding")

  // A script tool is tried once at save with sample inputs on a throwaway copy.
  let scripts = try book("Scripts")
  let tools = WorkbookTools(scripts, conversation: "")
  func save(_ name: String, _ source: String, inputs: [Value] = []) throws -> String? {
    do {
      _ = try tools.execute(
        "save",
        .object([
          "kind": .string("tool"), "name": .string(name), "description": .string("A tool."),
          "inputs": .array(inputs), "source": .string(source),
        ]))
      return nil
    } catch let error as SevraError { return error.message }
  }
  let undefined = try expectValue(
    try save(
      "log_today",
      "const day = date('now'); await sql('INSERT INTO expenses (item) VALUES (:day)', {day}); return 1;"
    ))
  try expectEqual(undefined.hasPrefix("The script failed: 'date' is not defined."), true)
  try expectEqual(undefined.contains("Pass values as sql(text, {name: value})"), true)
  try expectEqual(try scripts.savedTools().contains { $0.name == "log_today" }, false)
  let badColumn = try expectValue(
    try save("bad_column", "await sql('SELECT colour FROM expenses'); return 1;"))
  try expectEqual(badColumn.contains("no such column"), true)
  // What only the data or the sample causes is not the code's mistake: no rows, its own throw.
  try expectEqual(
    try save(
      "first_big",
      "const rows = await sql('SELECT item FROM expenses WHERE amount > 1000'); return rows[0].item;"
    ), nil)
  try expectEqual(
    try save(
      "add_named",
      "if (inputs.item === 'sample') throw Error('Choose a real item.'); await sql('INSERT INTO expenses (item, amount) VALUES (:item, :amount)', {item: inputs.item, amount: inputs.amount}); return today;",
      inputs: [
        .object(["name": .string("item"), "type": .string("text")]),
        .object(["name": .string("amount"), "type": .string("number")]),
      ]), nil)
  // The trial kept nothing.
  try expectEqual(try scripts.rows(try scripts.chatTableID("expenses")).count, 2)
  print("PASS a script tool is tried once before saving: an undefined name or a bad statement is refused, data-only failures save, nothing is kept")

  // A script passes values to sql by name, or by position for ?, and today is the date.
  var run = WorkbookTools(scripts, conversation: try scripts.startChat)
  let positional = try run.execute(
    "run",
    .object([
      "code": .string(
        "await sql('INSERT INTO expenses (item, amount) VALUES (?, ?)', ['Tape', 4]); const r = await sql('SELECT amount FROM expenses WHERE item = :item', {item: 'Tape'}); return [r[0].amount, today.length];"
      )
    ]))
  try expectEqual(positional["value"], .array([.number(4), .number(10)]))
  run.confirmsLargeChanges = false
  do {
    _ = try run.execute(
      "run", .object(["code": .string("return await sql('SELECT * FROM expenses WHERE item = ?');")]))
    throw SevraError("fixture", "A ? with no value ran.")
  } catch let error as SevraError {
    try expectEqual(
      error.message.contains(
        "Pass values with the statement, as sql(text, {name: value}) with :name in the text, or sql(text, [value]) for each ?."
      ), true)
  }
  print("PASS a script's sql takes values by name or position, and a missing one says how to pass it")

  // Small first-try refusals.
  // An empty expectedDefinitionID is a new definition, not a malformed one.
  do {
    _ = try tools.execute(
      "save_definition", .object(["expectedDefinitionID": .string(""), "content": .object([:])]))
  } catch let error as SevraError {
    try expectEqual(error.message.contains("expectedDefinitionID"), false)
  }
  do {
    _ = try NativeAppAuthoring.package(
      .object([
        "package": .object([
          "sdkVersion": .number(1), "name": .string("Workouts"), "source": .string("x"),
          "datasets": .object([:]),
          "views": .object([
            "home": .object(["definition": .object(["version": .number(1)])])
          ]),
        ])
      ]))
    throw SevraError("fixture", "A view without its version was accepted.")
  } catch let error as SevraError where error.code == "app_package" {
    try expectEqual(error.message.hasPrefix("Missing package field: views.home.version. Each entry of views is a visual"), true)
  }
  // From the command line, an app's check cannot run, so that is said before its shape.
  if (try? NativeAppCheck.requireCheckService()) == nil {
    let malformed = ScriptedCalls([
      call(
        "save_native_app",
        .object([
          "package": .object([
            "sdkVersion": .number(1), "name": .string("Workouts"), "source": .string("x"),
            "datasets": .object([:]),
            "views": .object(["home": .object(["definition": .object([:])])]),
          ]),
          "tests": .array([.object(["kind": .string("expect_text"), "value": .string("x")])]),
        ]))
    ])
    let ended = try await WorkbookAgent.run(
      "build a small app to track my workouts", workbook: try book("App"), model: malformed)
    try expectEqual(ended.steps, 1)
    try expectEqual(
      ended.answer.hasPrefix("Couldn’t finish saving the app. Saving an app needs the Sevra app open"),
      true)
  }
  print("PASS an app's shape error says where the field goes, and the command line says the app is needed first")
}
