import Foundation
import SevraAI
import SevraAppProtocol
import SevraCore

/// The final reply says what happened: host lines for table changes with their Undo, a
/// confirmation before a change empties or mostly rewrites a table, no "I created" when
/// nothing was saved, numbers the request wrote count as grounded, a stray currency symbol is
/// removed by the host, and a failure of this Mac ends the request instead of six retries.
/// From exploratory real-model scenarios of November 26, 2026. No model runs.
func checkReplyTruth() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-reply-truth-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  func book(_ name: String, rows: Int = 0) throws -> Workbook {
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    _ = try book.chatSQL(
      statements: ["CREATE TABLE expenses (item TEXT, amount REAL)"]
        + (rows == 0
          ? []
          : [
            "INSERT INTO expenses (item, amount) VALUES "
              + (1...rows).map { "('Item \($0)', \($0))" }.joined(separator: ", ")
          ]),
      readOnly: false, token: "fixture-" + identifier(), requestSourceID: nil)
    return book
  }
  func sql(_ statements: String...) -> ScriptedCalls.Step {
    call("sql", .object(["statements": .array(statements.map(Value.string))]))
  }

  // Which changes ask first. Every change keeps an Undo, so only emptying or removing a table
  // and changes to most of a table, or to more than 20 rows, wait for the person.
  for (rows, deleted, updated, asks) in [
    (19, 19, 0, true), (2, 2, 0, true), (2, 1, 0, false), (1, 1, 0, false), (5, 0, 4, false),
    (6, 0, 4, true), (6, 3, 0, false), (100, 20, 0, false), (100, 0, 21, true), (0, -1, 0, false),
    (3, -1, 0, true),
  ] {
    try expectEqual(Workbook.needsConfirmation(rows: rows, deleted: deleted, updated: updated), asks)
  }
  try expectEqual(
    Workbook.largeChangePreview([("Expenses", 19, 19, 0), ("Notes", 3, 1, 0)]),
    "This deletes all 19 rows of “Expenses”.")
  try expectEqual(
    Workbook.largeChangePreview([("Expenses", 10, 0, 6)]),
    "This changes 6 of the 10 rows of “Expenses”.")
  try expectEqual(
    Workbook.largeChangePreview([("Old", 4, -1, 0)]), "This removes the table “Old” and its 4 rows.")
  try expectEqual(Workbook.largeChangePreview([("Expenses", 10, 1, 1)]), nil)

  // A small change applies at once. The host names it by the table's title and says it can be
  // undone, after the model's summary.
  let small = try book("Small", rows: 3)
  let deletedOne = try await WorkbookAgent.run(
    "Delete Item 1.", workbook: small,
    model: ScriptedCalls([
      sql("DELETE FROM expenses WHERE item = 'Item 1'"),
      finish("I deleted Item 1.", basis: "completed_action"),
    ]), workspaceAction: { _, _, _, _ in .object([:]) })
  try expectEqual(
    deletedOne.answer, "I deleted Item 1.\n\nDeleted 1 row from “Expenses”. You can undo this.")
  try expectEqual(try small.rows(try small.chatTableID("expenses")).count, 2)
  print("PASS small sql changes apply at once with a host line naming the table and its Undo")

  // "Delete everything": every row of a table waits for the person. In the app the change is
  // held for confirmation with its preview, and nothing is deleted until they confirm.
  let everything = try book("Everything", rows: 19)
  let table = try everything.chatTableID("expenses")
  let waiting = try await WorkbookAgent.run(
    "delete everything", workbook: everything,
    model: ScriptedCalls([sql("DELETE FROM expenses")]),
    workspaceAction: { _, _, _, _ in .object([:]) })
  try expectEqual(waiting.state, "needs_review")
  try expectEqual(try everything.rows(table).count, 19)
  let chat = try everything.startChat
  let approval = try expectValue(try everything.pendingChatApproval(conversation: chat))
  try expectEqual(approval.action, "table.confirm_change")
  try expectEqual(
    approval.title, "This deletes all 19 rows of “Expenses”.\nYou can undo it after it is applied.")
  // The model is never offered the action that applies it.
  try expectEqual(ChatOperations.offered.contains { $0.name == "table.confirm_change" }, false)
  // Confirmed, it runs as the person saw it, as their change, with an Undo on its line.
  let applied = try WorkbookTools(everything, conversation: chat).runConfirmedChange(
    approval.arguments)
  try expectEqual(try everything.rows(table).count, 0)
  try everything.finishChatApproval(approval, conversation: chat, result: applied)
  let report = try expectValue(try everything.messages().last { $0.role == "event" })
  try expectEqual(report.body, "Deleted 19 rows from “Expenses”. You can undo this.")
  let token = try expectValue(try everything.conversationSQLReceipt(report.id, conversation: chat))
  try expectEqual(try everything.chatSQLState(token), "saved")
  _ = try everything.chatSQLUndo(token)
  try expectEqual(try everything.rows(table).count, 19)
  try expectEqual(try everything.verify()["ok"], .bool(true))

  // With no app to ask, as from the command line, the change is refused and says why.
  let cli = try book("Command line", rows: 19)
  let refused = try await WorkbookAgent.run(
    "delete everything", workbook: cli,
    model: ScriptedCalls([
      sql("DELETE FROM expenses"),
      finish("I could not delete the rows.", basis: "unresolved"),
    ]))
  try expectEqual(try cli.rows(try cli.chatTableID("expenses")).count, 19)
  try expectEqual(
    refused.answer.contains(
      "This deletes all 19 rows of “Expenses”. It needs your confirmation, which only the Sevra app can ask for."
    ), true)
  // A chat script and a saved tool the model runs ask the same way. The same tool pressed on a
  // view's button is the person's own action and runs at once.
  let scripted = try book("Scripted", rows: 6)
  let scriptedTable = try scripted.chatTableID("expenses")
  var chatTools = WorkbookTools(scripted, conversation: try scripted.startChat)
  chatTools.confirmsLargeChanges = true
  let script = try chatTools.execute(
    "run", .object(["code": .string("await sql('DELETE FROM expenses'); return 1;")]))
  try expectEqual(script["status"], .string("confirmation_required"))
  _ = try chatTools.execute(
    "save",
    .object([
      "kind": .string("tool"), "name": .string("clear_all"), "inputs": .array([]),
      "statements": .array([.string("DELETE FROM expenses")]),
    ]))
  let viaTool = try chatTools.execute(
    "sql", .object(["tool": .string("clear_all"), "values": .object([:])]))
  try expectEqual(viaTool["preview"], .string("This deletes all 6 rows of “Expenses”."))
  try expectEqual(try scripted.rows(scriptedTable).count, 6)
  _ = try WorkbookTools(scripted, conversation: "").execute(
    "sql", .object(["tool": .string("clear_all"), "values": .object([:])]))
  try expectEqual(try scripted.rows(scriptedTable).count, 0)
  print("PASS emptying a table waits for confirmation in the app, is refused without it, and keeps its Undo; scripts and saved tools ask too, a button does not")

  // A failed remove of a table, settled by a later delete of its rows: the same intent done
  // another way, so the summary stands and no failure is shown.
  let removed = try book("Removed", rows: 3)
  let settled = try await WorkbookAgent.run(
    "Delete Item 3.", workbook: removed,
    model: ScriptedCalls([
      call("workspace_action", .object(["action": .string("remove"), "arguments": .object(["id": .string("expenses")])])),
      sql("DELETE FROM expenses WHERE item = 'Item 3'"),
      finish("I deleted Item 3.", basis: "completed_action"),
    ]))
  try expectEqual(
    settled.answer, "I deleted Item 3.\n\nDeleted 1 row from “Expenses”. You can undo this.")
  print("PASS a later table change settles a failed remove of the same table")

  // Nothing was saved and the closing account says "I created": it goes back once, and then
  // the host gives one account instead.
  func move(_ id: String) -> ScriptedCalls.Step {
    call(
      "edit_space",
      .object([
        "id": .string("home"), "expectedVersion": .number(1),
        "edits": .array([.object(["operation": .string("move"), "componentID": .string(id)])]),
      ]))
  }
  let claim = "I created a Home dashboard with two metrics. The view has been updated."
  let claimed = ScriptedCalls([
    move("attention"), move("continue"), move("shortcuts"),
    finish(claim, basis: "completed_action"), finish(claim, basis: "completed_action"),
  ])
  let unsaved = try await WorkbookAgent.run(
    "Build me a Home dashboard.", workbook: try book("Unsaved"), model: claimed)
  try expectEqual(unsaved.state, "complete")
  try expectEqual(await claimed.refusals.first?.contains(ChangeClaim.feedback), true)
  try expectEqual(unsaved.answer.hasPrefix("Nothing was changed.\nCouldn’t finish saving the space."), true)
  try expectEqual(unsaved.answer.contains("I created"), false)
  // Only once in the reply, though three calls failed the same way.
  try expectEqual(unsaved.answer.components(separatedBy: "Couldn’t finish").count, 2)
  for honest in ["I could not create the dashboard.", "I have not saved a schedule.", "Nothing changed."] {
    try expectEqual(ChangeClaim.claims(honest), false)
  }
  for made in ["I've added a chart.", "The view has been updated.", "Added a total to Home.", "Your tracker is ready!"] {
    try expectEqual(ChangeClaim.claims(made), true)
  }
  print("PASS a summary that claims a change nothing saved is sent back once, then replaced by the host's account")

  // Numbers the model wrote into calls that succeeded are what was saved, so the summary may
  // repeat them. A number nothing gave is still sent back.
  let numbers = ScriptedCalls([
    sql(
      "CREATE TABLE habits (name TEXT)",
      "INSERT INTO habits (name) VALUES ('Read for 30 minutes'), ('Drink 8 glasses')"),
    finish("I added Read for 30 minutes and Drink 8 glasses, with a 7-day chart.", basis: "completed_action"),
    finish("I added Read for 30 minutes and Drink 8 glasses.", basis: "completed_action"),
  ])
  let grounded = try await WorkbookAgent.run(
    "I want a habit tracker.", workbook: try book("Habits"), model: numbers)
  let refusals = await numbers.refusals
  try expectEqual(refusals.count, 1)
  try expectEqual(refusals.first?.contains("The summary states 7,"), true)
  try expectEqual(
    grounded.answer,
    "I added Read for 30 minutes and Drink 8 glasses.\n\nCreated table “Habits” with 2 rows. You can undo this."
  )
  try expectEqual(
    WorkbookAgent.argumentNumbers(
      .object([
        "id": .string("12"), "expectedVersion": .number(4),
        "datasetID": .string("0c7ecc64-5f2c-4255-97fa-26a5793b2c42"),
        "query": .string("SELECT * FROM t WHERE n > 500"),
      ])), ["500"])
  print("PASS numbers from the request's own successful calls count as grounded; invented ones are still refused")

  // A currency symbol nothing gave is the host's to remove when it sits beside a number.
  for (given, plain) in [
    ("$51.50", "51.50"), ("-$5", "-5"), ("12 €", "12"), ("US$3", "3"), ("costs in $", "costs in $"),
    ("Rent at $1,500.", "Rent at 1,500."),
  ] {
    try expectEqual(WorkbookAgent.removingCurrencySymbols(given), plain)
  }
  let currency = ScriptedCalls([
    sql("SELECT 51.5 AS total"), finish("The total is $51.50.", basis: "current_request"),
  ])
  let stripped = try await WorkbookAgent.run(
    "What is the total?", workbook: try book("Currency"), model: currency)
  try expectEqual(stripped.answer.hasPrefix("The total is 51.50."), true)
  try expectEqual(stripped.steps, 2)
  try expectEqual(await currency.refusals.isEmpty, true)
  print("PASS an unsupported currency symbol beside a grounded number is removed without a refusal")

  // Today's date, weekday and zone come with every request, not only one that says "today".
  let dated = ScriptedCalls([finish("Hello.", basis: "general")])
  _ = try await WorkbookAgent.run("Which invoices are overdue?", workbook: try book("Dated"), model: dated)
  let request = try expectValue(await dated.prompts.first?.first?.content)
  try expectEqual(request.contains("Now: "), true)
  try expectEqual(request.contains("time zone " + TimeZone.current.identifier), true)
  try expectEqual(GeneralTools.instructions.contains("no online connections"), true)
  print("PASS every chat request carries the Mac's date and time zone, and the guidance states what Sevra can bring in")

  // A failure of this Mac, not of the call: a helper the system could not reach.
  try expectEqual(
    WorkbookAgent.isSystemFailure(NSError(domain: NSCocoaErrorDomain, code: 4099)), true)
  try expectEqual(WorkbookAgent.isSystemFailure(SevraError("app_check", "Wrong.")), false)
  try expectEqual(
    WorkbookAgent.isSystemFailure(NSError(domain: NSCocoaErrorDomain, code: 260)), false)
  // A command line has no app checker: saving an app says the app is needed, and the request
  // ends there with what it did save, instead of retrying.
  if (try? NativeAppCheck.requireCheckService()) == nil {
    let package = NativeAppPackage(
      name: "Workouts", source: "Sevra.mount(Sevra.h(Sevra.Text,{text:'Ready'}));",
      datasets: [:])
    let save: Value = .object([
      "package": try encoded(package),
      "tests": .array([.object(["kind": .string("expect_text"), "value": .string("Ready")])]),
    ])
    let app = ScriptedCalls([
      call("native_app_sdk"), sql("CREATE TABLE workouts (exercise TEXT)"),
      call("save_native_app", save),
    ])
    let ended = try await WorkbookAgent.run(
      "build a small app to track my workouts", workbook: try book("App"), model: app)
    try expectEqual(ended.state, "complete")
    try expectEqual(ended.steps, 3)
    try expectEqual(
      ended.answer,
      "Couldn’t finish saving the app. Saving an app needs the Sevra app open: its isolated check runs only inside the app. Nothing was saved.\n\nCreated table “Workouts”. You can undo this."
    )
    print("PASS saving an app from the command line says the app is needed and ends the request at once")
  }
}
