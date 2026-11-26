import Foundation

@testable import SevraCore

/// What a table made or changed with chat `sql` keeps for later calls: an INTEGER PRIMARY KEY
/// that numbers rows, defaults, NOT NULL, UNIQUE and computed columns, and 'now' in local time.
func checkChatSQLShape(at root: URL) {
  func book(_ name: String) throws -> Workbook {
    try Workbook.create(at: root.appendingPathComponent("ChatSQLShape-" + name + ".sevra"), title: name)
  }
  func sql(_ b: Workbook, _ statements: String..., token: String = identifier()) throws -> Value {
    try b.chatSQL(statements: statements, readOnly: false, token: token, requestSourceID: nil)
  }
  func rows(_ result: Value, _ index: Int = -1) -> [[String]] {
    let results = result["results"].array
    return results[index < 0 ? results.count + index : index]["rows"].array.map {
      $0.array.map { $0 == .null ? "NULL" : $0.text }
    }
  }
  func today() -> String {
    let format = DateFormatter()
    format.locale = Locale(identifier: "en_US_POSIX")
    format.timeZone = .current
    format.dateFormat = "yyyy-MM-dd"
    return format.string(from: Date())
  }

  check("a table keeps its numbering, defaults and required columns for rows added later, from sql, a saved tool and a row change") {
    let b = try book("Numbering")
    _ = try sql(
      b,
      "CREATE TABLE jobs (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, status TEXT DEFAULT 'open', made TEXT DEFAULT CURRENT_DATE)")
    let jobs = try b.datasets()[0]
    try expect(
      jobs.columns.map(\.autoNumber) == [true, nil, nil, nil]
        && jobs.columns[1].required == true && jobs.columns[2].defaultValue == ColumnDefault(value: "open")
        && jobs.columns[3].defaultValue == ColumnDefault(now: "date"), "\(jobs.columns)")
    // The scenario that lost the shape: an INSERT in a later call stored NULL for all three.
    let later = try sql(b, "INSERT INTO jobs (name) VALUES ('a')", "SELECT * FROM jobs")
    try expect(rows(later) == [["1", "a", "open", today()]], "\(rows(later))")
    _ = try b.chatSaveTool(
      name: "add_job", description: "Adds a job.", inputs: [("name", "text")],
      statements: ["INSERT INTO jobs (name) VALUES (:name)"], source: nil, token: "save-add-job",
      requestSourceID: nil)
    let tools = WorkbookTools(b, conversation: "")
    let pressed = try tools.execute(
      "sql", .object(["tool": .string("add_job"), "values": .object(["name": .string("b")])]))
    let saved = try sql(b, "SELECT id, name, status FROM jobs ORDER BY id")
    try expect(rows(saved) == [["1", "a", "open"], ["2", "b", "open"]], "\(rows(saved))")
    // Undo takes the row back, and the next row gets its number again, as SQLite numbers.
    _ = try b.chatSQLUndo(pressed["undo"].text, actor: .human("ChatSQLShapeChecks"))
    try expect(try b.dataset(jobs.id).rowCount == 1)
    // A row change that leaves the columns out, as an app or a form sends it.
    _ = try b.chatTableTransaction(
      jobs.id, expectedDefinitionID: jobs.definitionID,
      operations: [.object(["op": .string("insert"), "values": .object(["name": .string("c")])])])
    let numbered = try b.rows(jobs.id).map { b.calculatedValues($0, columns: jobs.columns) }
    try expect(
      numbered.map { [$0["id"]?.text ?? "", $0["name"]?.text ?? "", $0["status"]?.text ?? ""] }
        == [["1", "a", "open"], ["2", "c", "open"]], "\(numbered)")
    // An explicit NULL keeps the cell empty; a missing required value is refused.
    let empty = try sql(b, "INSERT INTO jobs (name, status) VALUES ('d', NULL)", "SELECT status FROM jobs WHERE name = 'd'")
    try expect(rows(empty) == [["NULL"]], "\(rows(empty))")
    try refuses("required") { _ = try sql(b, "INSERT INTO jobs (status) VALUES ('x')") }
    try refuses { _ = try sql(b, "UPDATE jobs SET id = 2.5 WHERE name = 'a'") }
    let context = try b.chatSQLTables()
    try expect(
      context.contains("id INTEGER PRIMARY KEY, name TEXT NOT NULL, status TEXT DEFAULT 'open', made TEXT DEFAULT CURRENT_DATE"),
      context)
    try b.verify()
  }

  check("UNIQUE and a key that is not INTEGER are kept, and a duplicate is refused with its value") {
    let b = try book("Unique")
    _ = try sql(
      b, "CREATE TABLE people (email TEXT UNIQUE, name TEXT)", "CREATE TABLE codes (code TEXT PRIMARY KEY, label TEXT)",
      "INSERT INTO people VALUES ('a@example.com', 'A')")
    let people = try b.datasets().first { $0.title == "People" }!
    let codes = try b.datasets().first { $0.title == "Codes" }!
    try expect(people.columns[0].unique == true && people.columns[0].required == nil)
    try expect(codes.columns[0].unique == true && codes.columns[0].required == true)
    do {
      _ = try sql(b, "INSERT INTO people VALUES ('b@example.com', 'B')", "INSERT INTO people VALUES ('a@example.com', 'C')")
      throw SevraError("test", "A duplicate was saved.")
    } catch let error as SevraError where error.code == "unique" {
      try expect(error.message.contains("\"a@example.com\""), error.message)
    }
    try expect(try b.dataset(people.id).rowCount == 1)
    try refuses("sql_shape") { _ = try sql(b, "CREATE TABLE pairs (a TEXT, b TEXT, UNIQUE (a, b))") }
    try expect(try b.datasets().count == 2)
  }

  check("a computed column from sql is a formula column that follows its inputs, and other expressions are refused") {
    let b = try book("Computed")
    _ = try sql(
      b, "CREATE TABLE lines (item TEXT, quantity REAL, price REAL)",
      "INSERT INTO lines VALUES ('bolts', 2, 3), ('nuts', 1, 10)")
    let added = try sql(b, "ALTER TABLE lines ADD COLUMN total AS (quantity * price)", "SELECT item, total FROM lines ORDER BY item")
    try expect(rows(added) == [["bolts", "6"], ["nuts", "10"]], "\(rows(added))")
    let lines = try b.datasets()[0]
    try expect(lines.columns.last?.formula == "quantity * price", "\(lines.columns)")
    let followed = try sql(b, "UPDATE lines SET quantity = 5 WHERE item = 'bolts'", "SELECT item, total FROM lines ORDER BY item")
    try expect(rows(followed) == [["bolts", "15"], ["nuts", "10"]], "\(rows(followed))")
    _ = try sql(b, "CREATE TABLE orders (qty REAL, cost REAL, amount REAL GENERATED ALWAYS AS (round(qty * cost)))")
    try expect(
      try b.datasets().first { $0.title == "Orders" }!.columns.last?.formula == "ROUND(qty * cost, 0)")
    for refused in [
      "ALTER TABLE lines ADD COLUMN label AS (item || 'x')",
      "ALTER TABLE lines ADD COLUMN odd AS (abs(price))",
    ] {
      try refuses("sql_shape") { _ = try sql(b, refused) }
    }
    try expect(try b.dataset(lines.id).columns.count == 4)
    // SQLite adds no column with a current-time default. Here the rows already there stay
    // empty, and a row added in the same call gets the date.
    _ = try sql(
      b, "ALTER TABLE lines ADD COLUMN added TEXT DEFAULT CURRENT_DATE",
      "INSERT INTO lines (item, quantity, price) VALUES ('washers', 1, 1)")
    let dated = try b.rows(lines.id).map { ($0.data["item"].text, $0.data["added"]) }
    try expect(
      dated.map(\.0) == ["bolts", "nuts", "washers"]
        && dated.map(\.1) == [.null, .null, .string(today())], "\(dated)")
    try b.verify()
  }

  check("'now' and CURRENT_DATE are the Mac's local time, the same in every statement of a call") {
    // 01:30 UTC on November 26 is 20:30 on November 25 in New York.
    let scratch = try SQLScratch(
      tables: [], readOnly: false, draft: false,
      now: ISO8601DateFormatter().date(from: "2026-11-26T01:30:00Z")!,
      timeZone: TimeZone(identifier: "America/New_York")!, cancellation: .init())
    defer { scratch.close() }
    let read = try scratch.run([
      "SELECT date('now'), CURRENT_DATE, datetime('now', 'localtime'), strftime('%H:%M', 'now'), date('now', '+1 day'), date('2026-01-31', '+1 month')",
      "SELECT CURRENT_TIMESTAMP",
    ])
    try expect(
      rows(.object(["results": .array(read)]), 0)
        == [["2026-11-25", "2026-11-25", "2026-11-25 20:30:00", "20:30", "2026-11-26", "2026-03-03"]],
      "\(read)")
    try expect(rows(.object(["results": .array(read)]), 1) == [["2026-11-25 20:30:00"]], "\(read)")
    // The words inside a quoted value are data.
    try expect(
      SQLScratch.prepared("SELECT 'CURRENT_DATE AUTOINCREMENT', CURRENT_DATE")
        == "SELECT 'CURRENT_DATE AUTOINCREMENT', (date('now'))")
  }

  check("a table's sql name or title stands for its id where the model gives a table") {
    let b = try book("Names")
    _ = try sql(b, "CREATE TABLE open_invoices (customer TEXT, amount REAL)")
    let table = try b.datasets()[0]
    try expect(try b.chatTableID("open_invoices") == table.id && b.chatTableID("Open invoices") == table.id)
    try expect(try b.chatTableID(table.id) == table.id)
    do {
      _ = try b.chatTableID("invoices")
      throw SevraError("test", "An unknown table was accepted.")
    } catch let error as SevraError where error.code == "unknown_table" {
      try expect(error.message.contains("Open invoices (open_invoices, \(table.id))"), error.message)
    }
    let saved = try WorkbookTools(b, conversation: "").execute(
      "save_space",
      .object([
        "title": .string("Invoices"),
        "definition": .object([
          "version": .number(1),
          "components": .array([
            .object([
              "id": .string("t1"), "type": .string("table"), "title": .string("Invoices"),
              "datasetID": .string("open_invoices"),
            ])
          ]),
        ]),
      ]))
    try expect(
      try b.space(saved["spaceID"].text).definition.components.first?.datasetID == table.id)
  }
}
