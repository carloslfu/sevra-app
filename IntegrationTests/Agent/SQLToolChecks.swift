import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

/// The `sql` tool as a model run reaches it: declared only under the general profile, its
/// results accepted as the basis of an answer, and its row changes saved under the AI actor.
func checkSQLTool() async throws {
  let general = Set(NativeTools.definitions(for: .general).map(\.name))
  try expectEqual(general.contains("sql"), true)
  try expectEqual(general.isDisjoint(with: NativeTools.generalReplaced), true)
  try expectEqual(NativeTools.definitions(for: .current).contains { $0.name == "sql" }, false)
  // The grammar accepts the declaration, and specialized phases keep today's tools.
  _ = try NativeCitationPolicy.make([], toolScope: .all, toolProfile: .general)
  for scope in InferenceToolScope.allCases where scope.specialized {
    try expectEqual(
      try NativeTools.serializedDefinitions(toolScope: scope, toolProfile: .general),
      try NativeTools.serializedDefinitions(toolScope: scope))
  }
  try expectEqual(general, NativeTools.generalKept.union(["sql"]))
  try expectEqual(ToolProfile.general.instructions(current: "today"), ToolProfile.generalInstructions)
  try expectEqual(ToolProfile.current.scopeInstructions(current: "today"), "today")

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

  // Today's instructions name the replaced tools. The general profile's do not.
  let read = ScriptedCalls(
    [
      sql("SELECT supplier, total FROM supplier_comparison ORDER BY total"),
      finish("Oak Supply has the lower total: 24 against 27.5.", basis: "evidence"),
    ], toolProfile: .general)
  let answered = try await WorkbookAgent.run(
    "Which supplier has the lower total?", workbook: book, model: read)
  let instructions = try expectValue(await read.prompts.first?.first?.cacheablePolicy)
  try expectEqual(instructions.contains("compare_rows"), false)
  try expectEqual(instructions.contains("use calculate"), false)
  try expectEqual(instructions.contains(ToolProfile.generalInstructions), true)
  try expectEqual(instructions.contains("datasets"), false)
  // The request names the tables as sql knows them, so the model need not look them up.
  let request = try expectValue(await read.prompts.first?.last { $0.role == "user" }).content
  try expectEqual(
    request.contains(
      "Tables for sql: supplier_comparison(supplier, quantity number, unit_cost number, total formula) 2 rows"),
    true)
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
    ], toolProfile: .general)
  let changed = try await WorkbookAgent.run(
    "Change the Cedar Tools unit cost to 2.60.", workbook: book, model: change)
  try expectEqual(changed.state, "complete")
  let saved = try await toolResult(change)
  try expectEqual(saved["error"], .null)
  try expectEqual(saved["changes"].array.first?["updated"], .number(1))
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
    ], toolProfile: .general)
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

  // A draft saves a proposal and leaves the table alone.
  let draft = ScriptedCalls(
    [
      sql("UPDATE supplier_comparison SET units = 12 WHERE supplier = 'Oak Supply'", draft: true),
      finish("The draft is ready for review.", basis: "completed_action"),
    ], toolProfile: .general)
  _ = try await WorkbookAgent.run(
    "Draft a change of the Oak Supply quantity to 12 for my review.", workbook: book, model: draft)
  try expectEqual(try await toolResult(draft)["drafts"].array.first?["draftRows"], .number(1))
  try expectEqual(try values(), updated)

  // A request that forbids changes cannot change rows through sql.
  let forbidden = ScriptedCalls(
    [
      sql("DELETE FROM supplier_comparison"),
      finish("Nothing was changed.", basis: "unresolved"),
    ], toolProfile: .general)
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
    ], toolProfile: .general)
  let asked = try await WorkbookAgent.run(
    "Add the new supplier to the Supplier comparison table.", workbook: book, model: repeated)
  try expectEqual(asked.state, "complete")
  let second = try Value.parse(
    try expectValue(await repeated.prompts.last?.last { $0.role == "tool" }).content)
  try expectEqual(second["reusedReceiptID"].string != nil, true)
  try expectEqual(try values(), updated)
  print("PASS sql tool: general declarations, answers from query results, AI row and shape changes under a rule Source, draft, forbidden change, repeated query")
}
