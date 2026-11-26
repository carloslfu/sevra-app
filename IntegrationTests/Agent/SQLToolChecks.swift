import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

/// The `sql` tool as a model run reaches it: one of the seven chat tools, its results
/// accepted as the basis of an answer, and its row changes saved under the AI actor.
func checkSQLTool() async throws {
  // Chat offers the seven tools and nothing else. Reviews and Excel conversion keep theirs.
  let chat = try NativeTools.referenceDefinitions(conversationInput: true).map(\.name)
  try expectEqual(chat, GeneralTools.names)
  try expectEqual(NativeTools.definitions.contains { $0.name == "sql" }, false)
  _ = try NativeCitationPolicy.make([], toolScope: .all)
  for scope in InferenceToolScope.allCases {
    let names = try NativeTools.referenceDefinitions(toolScope: scope).map(\.name)
    try expectEqual(
      Set(names).isSubset(of: GeneralTools.names), !scope.specialized || names.isEmpty)
  }
  // Every named action and kind routes to an operation that exists, and none shadows a
  // workspace action.
  let operations = Set(NativeTools.definitions.map(\.name))
  try expectEqual(Set(GeneralTools.actions.values).isSubset(of: operations), true)
  try expectEqual(
    Set(GeneralTools.actions.keys).isDisjoint(with: ChatOperations.operations.map(\.name)), true)
  let message = GeneralTools.route(
    "read", .object(["kind": .string("message"), "ref": .string("m1")]))
  try expectEqual(message.tool, "history_read")
  try expectEqual(message.arguments, .object(["id": .string("m1")]))
  try expectEqual(
    GeneralTools.route(
      "run", .object(["action": .object(["name": .string("table.schema")])])
    ).tool, "workspace_action")
  let document = GeneralTools.route(
    "save", .object(["document": .object(["title": .string("Note")])]))
  try expectEqual(document.tool, "draft")
  try expectEqual(document.arguments, .object(["title": .string("Note")]))
  let ownTool = GeneralTools.route("save", .object(["tool": .object(["name": .string("low")])]))
  try expectEqual(ownTool.tool, "save")
  try expectEqual(ownTool.arguments["kind"], .string("tool"))
  try expectEqual(GeneralTools.route("ask", .object([:])).tool, "request_input")

  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-sql-tool-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook(
    URL(fileURLWithPath: Demo.create(at: root.appendingPathComponent("SQL.sevra"))["path"].text))
  let tableID = try expectValue(try book.datasets().first { $0.title == "Supplier comparison" }).id
  func values() throws -> [[String: Value]] {
    let table = try book.dataset(tableID)
    return try book.rows(tableID).map { book.calculatedValues($0, columns: table.columns) }
  }
  func sql(_ statements: String..., draft: Bool = false) -> ScriptedCalls.Step {
    call(
      "sql",
      .object(
        ["statements": .array(statements.map(Value.string))].merging(
          draft ? ["draft": .bool(true)] : [:]) { first, _ in first }))
  }
  func toolResult(_ model: ScriptedCalls) async throws -> Value {
    try Value.parse(
      try expectValue(await model.prompts.dropFirst().first?.last { $0.role == "tool" }).content)
  }
  let start = try values()

  // The instructions name only the seven tools.
  let read = ScriptedCalls(
    [
      sql("SELECT supplier, total FROM supplier_comparison ORDER BY total"),
      finish("Oak Supply has the lower total: 24 against 27.5.", basis: "evidence"),
    ])
  let answered = try await WorkbookAgent.run(
    "Which supplier has the lower total?", workbook: book, model: read)
  let instructions = try expectValue(await read.prompts.first?.first?.cacheablePolicy)
  try expectEqual(instructions.contains("compare_rows"), false)
  try expectEqual(instructions.contains("use calculate"), false)
  try expectEqual(instructions.contains(GeneralTools.instructions), true)
  try expectEqual(instructions.contains("datasets"), false)
  // The request names the tables as sql knows them, so the model need not look them up.
  let request = try expectValue(await read.prompts.first?.last { $0.role == "user" }).content
  try expectEqual(
    request.contains(
      "supplier_comparison(supplier TEXT, quantity REAL, unit_cost REAL, total REAL GENERATED) 2 rows"),
    true)
  try expectEqual(request.contains("Tables for sql: supplier_comparison("), true)
  try expectEqual(try book.chatSQLTables(byteLimit: 10), "")
  // The answer rests on the query: its figures pass, and the host attaches the rows it read.
  try expectEqual(answered.state, "complete")
  try expectEqual(answered.answer.contains("24 against 27.5"), true)
  try expectEqual(answered.citations.count, 2)
  let shown = try await toolResult(read)
  try expectEqual(shown["results"].array.first?["rows"].array.count, 2)
  try expectEqual(shown["inputs"], .null)
  try expectEqual(try values(), start)

  // A row update is saved under the AI actor, which the write path accepts only with a rule.
  let change = ScriptedCalls(
    [
      sql("UPDATE supplier_comparison SET unit_cost = 2.60 WHERE supplier = 'Cedar Tools'"),
      finish("Cedar Tools now costs 2.60 each.", basis: "completed_action"),
    ])
  let changed = try await WorkbookAgent.run(
    "Change the Cedar Tools unit cost to 2.60.", workbook: book, model: change)
  try expectEqual(changed.state, "complete")
  let saved = try await toolResult(change)
  try expectEqual(saved["error"], .null)
  try expectEqual(saved["changes"].array.first?["updated"], .number(1))
  // The answer carries the call that saved the change, and the conversation can undo it.
  let saidSo = try expectValue(
    try book.messages().last { $0.role == "assistant" && $0.state == "complete" })
  let receipt = try expectValue(try book.conversationSQLReceipt(saidSo.id, conversation: book.startChat))
  try expectEqual(receipt, saved["undo"].string)
  try expectEqual(try book.chatSQLState(receipt), "saved")
  _ = try WorkbookTools(book).execute(
    "workspace_action",
    .object(["action": .string("table.undo_sql"), "arguments": .object(["token": .string(receipt)])]))
  try expectEqual(try values(), start)
  try expectEqual(try book.chatSQLState(receipt), "undone")
  try expectThrows(try book.chatSQLUndo(receipt))
  let again = ScriptedCalls(
    [
      sql("UPDATE supplier_comparison SET unit_cost = 2.60 WHERE supplier = 'Cedar Tools'"),
      finish("Cedar Tools now costs 2.60 each.", basis: "completed_action"),
    ])
  try expectEqual(
    try await WorkbookAgent.run(
      "Change the Cedar Tools unit cost to 2.60 again.", workbook: book, model: again
    ).state, "complete")
  let cedar = try expectValue(try values().first { $0["supplier"] == .string("Cedar Tools") })
  try expectEqual(try Numbers.decimal(cedar["unit_cost"]?.text ?? ""), try Numbers.decimal("2.6"))
  try expectEqual(try Numbers.decimal(cedar["total"]?.text ?? ""), try Numbers.decimal("26"))
  let updated = try values()

  // A new table and a renamed column are definition changes, which the write path also
  // accepts from the AI actor only under a rule.
  let shape = ScriptedCalls(
    [
      sql(
        "CREATE TABLE reorder_levels (item TEXT, level REAL)",
        "INSERT INTO reorder_levels VALUES ('Brass bolts', 12), ('Hex nuts', 25)",
        "ALTER TABLE supplier_comparison RENAME COLUMN quantity TO units"),
      finish("Created Reorder levels and renamed the column.", basis: "completed_action"),
    ])
  let shaped = try await WorkbookAgent.run(
    "Create a table named Reorder levels with Item and Level, and rename Quantity to Units.",
    workbook: book, model: shape)
  try expectEqual(shaped.state, "complete")
  let reshaped = try await toolResult(shape)
  try expectEqual(reshaped["error"], .null)
  try expectEqual(reshaped["shape"].array.count, 2)
  let levels = try expectValue(try book.datasets().first { $0.title == "Reorder levels" })
  try expectEqual(levels.columns.map(\.type), ["text", "decimal"])
  try expectEqual(try book.rows(levels.id).count, 2)
  try expectEqual(
    try book.dataset(tableID).columns.map(\.title), ["Supplier", "Units", "Unit cost", "Total"])
  try expectEqual(try values(), updated)

  // A saved tool: the model saves it, a later request sees it listed and runs it by name.
  let keep = ScriptedCalls(
    [
      call(
        "save",
        .object([
          "kind": .string("tool"), "name": .string("cheaper_than"),
          "description": .string("Suppliers whose unit cost is below a limit."),
          "inputs": .array([.object(["name": .string("limit"), "type": .string("number")])]),
          "statements": .array([
            .string("SELECT supplier FROM supplier_comparison WHERE unit_cost < :limit")
          ]),
        ])),
      finish("Saved the tool cheaper_than.", basis: "completed_action"),
    ])
  let kept = try await WorkbookAgent.run(
    "Save a tool named cheaper_than that lists suppliers below a unit cost limit.",
    workbook: book, model: keep)
  try expectEqual(kept.state, "complete")
  try expectEqual(try await toolResult(keep)["saved"], .string("cheaper_than"))
  let use = ScriptedCalls(
    [
      call(
        "sql",
        .object(["tool": .string("cheaper_than"), "values": .object(["limit": .string("2.5")])])),
      finish("Oak Supply is below 2.5.", basis: "evidence"),
    ])
  let used = try await WorkbookAgent.run(
    "Which suppliers are cheaper than 2.5?", workbook: book, model: use)
  try expectEqual(used.state, "complete")
  let listing = try expectValue(await use.prompts.first?.last { $0.role == "user" }).content
  try expectEqual(listing.contains("Saved tools: cheaper_than(limit REAL): Suppliers"), true)
  try expectEqual(
    try await toolResult(use)["results"].array.first?["rows"],
    .array([.array([.string("Oak Supply")])]))
  try expectEqual(try values(), updated)

  // A draft saves a proposal and leaves the table alone.
  let draft = ScriptedCalls(
    [
      sql("UPDATE supplier_comparison SET units = 12 WHERE supplier = 'Oak Supply'", draft: true),
      finish("The draft is ready for review.", basis: "completed_action"),
    ])
  _ = try await WorkbookAgent.run(
    "Draft a change of the Oak Supply quantity to 12 for my review.", workbook: book, model: draft)
  try expectEqual(try await toolResult(draft)["drafts"].array.first?["draftRows"], .number(1))
  try expectEqual(try values(), updated)

  // A request that forbids changes cannot change rows through sql.
  let forbidden = ScriptedCalls(
    [
      sql("DELETE FROM supplier_comparison"),
      finish("Nothing was changed.", basis: "unresolved"),
    ])
  _ = try await WorkbookAgent.run(
    "Do not change anything. What would happen if every supplier were removed?",
    workbook: book, model: forbidden)
  try expectEqual(try await toolResult(forbidden)["error"] != .null, true)
  try expectEqual(try values(), updated)
  // The same query sent again at once is answered with a pointer to the result it has.
  let query = sql("SELECT * FROM supplier_comparison")
  let repeated = ScriptedCalls(
    [
      query, query,
      finish("Which supplier should I add, and at what quantity and unit cost?", basis: "general"),
    ])
  let asked = try await WorkbookAgent.run(
    "Add the new supplier to the Supplier comparison table.", workbook: book, model: repeated)
  try expectEqual(asked.state, "complete")
  let second = try Value.parse(
    try expectValue(await repeated.prompts.last?.last { $0.role == "tool" }).content)
  try expectEqual(second["reusedReceiptID"].string != nil, true)
  try expectEqual(try values(), updated)
  // A script's changes are saved under the same rule, with one Undo, and its result is a
  // figure the answer may state.
  func script(_ code: String) -> ScriptedCalls.Step { call("run", .object(["code": .string(code)])) }
  let looping = ScriptedCalls(
    [
      script(
        """
        const rows = await sql('SELECT supplier, units FROM supplier_comparison');
        for (const row of rows) {
          await sql('UPDATE supplier_comparison SET units = :n WHERE supplier = :s', {n: row.units + 1, s: row.supplier});
        }
        return rows.length;
        """),
      finish("Raised the quantity of 2 suppliers by one.", basis: "completed_action"),
    ])
  let looped = try await WorkbookAgent.run(
    "Raise every supplier's quantity by one.", workbook: book, model: looping)
  try expectEqual(looped.state, "complete")
  let ran = try await toolResult(looping)
  try expectEqual(ran["error"], .null)
  try expectEqual(ran["value"], .number(2))
  try expectEqual(ran["changes"].array.first?["updated"], .number(2))
  let raised = try expectValue(
    try book.messages().last { $0.role == "assistant" && $0.state == "complete" })
  let scriptReceipt = try expectValue(
    try book.conversationSQLReceipt(raised.id, conversation: book.startChat))
  try expectEqual(try book.chatSQLState(scriptReceipt), "saved")
  _ = try book.chatSQLUndo(scriptReceipt)
  try expectEqual(try values(), updated)
  let blocked = ScriptedCalls(
    [
      script("await sql('DELETE FROM supplier_comparison'); return 1;"),
      finish("Nothing was changed.", basis: "unresolved"),
    ])
  _ = try await WorkbookAgent.run(
    "Do not change anything. What would happen if every supplier were removed?",
    workbook: book, model: blocked)
  try expectEqual(try await toolResult(blocked)["error"] != .null, true)
  try expectEqual(try values(), updated)
  // A file is exported only to a path the person wrote in the request.
  let exporting = ScriptedCalls(
    [
      call(
        "run",
        .object([
          "action": .object([
            "name": .string("file.export_table"),
            "arguments": .object([
              "id": .string(tableID), "path": .string("/tmp/sevra-check-export.csv"),
            ]),
          ])
        ])),
      finish("Where should I save the export?", basis: "general"),
    ])
  _ = try await WorkbookAgent.run(
    "Export the Supplier comparison table.", workbook: book, model: exporting)
  try expectEqual(
    try await toolResult(exporting)["error"].text.contains("path the user wrote"), true)
  try expectEqual(FileManager.default.fileExists(atPath: "/tmp/sevra-check-export.csv"), false)
  // A new table and its first rows, saved by one call, offer the same one Undo.
  let creating = ScriptedCalls(
    [
      sql(
        "CREATE TABLE bolt_levels(part TEXT, level REAL)",
        "INSERT INTO bolt_levels VALUES('Brass bolts', 10)"),
      finish("Added a reorder level of 10 for brass bolts.", basis: "completed_action"),
    ])
  _ = try await WorkbookAgent.run(
    "Add a reorder level of 10 for brass bolts.", workbook: book, model: creating)
  let created = try expectValue(
    try book.messages().last { $0.role == "assistant" && $0.state == "complete" })
  let createdReceipt = try expectValue(
    try book.conversationSQLReceipt(created.id, conversation: book.startChat))
  try expectEqual(try book.chatSQLState(createdReceipt), "saved")
  // The person's Undo, as the chat row sends it.
  _ = try book.chatSQLUndo(createdReceipt, actor: .human("Sevra chat undo"))
  try expectEqual(try book.chatSQLState(createdReceipt), "undone")
  // Listing actions for a ref that is no domain, such as a table's id, lists them all.
  try expectEqual(
    try ChatOperations.catalog(tableID).array.count, try ChatOperations.catalog().array.count)
  try expectEqual(
    try ChatOperations.catalog("file").array.allSatisfy { $0["action"].text.hasPrefix("file.") },
    true)
  // An export may name its table as sql does.
  try expectEqual(try book.chatTableID("supplier_comparison"), tableID)
  try expectEqual(try book.chatTableID(tableID), tableID)
  try expectThrows(try book.chatTableID("no_such_table"))
  print("PASS sql tool: general declarations, answers from query results, AI row and shape changes under a rule Source, one undo from the answer, saved tool, draft, forbidden change, repeated query, a script's changes and refusal, an export to an unnamed path, a new table's one undo, a table named for export")
}
