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

  check("UNIQUE and a key that is not INTEGER are kept, a duplicate is refused naming its column, and OR IGNORE, ON CONFLICT and REPLACE work") {
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
      // The copy has the constraint, so the statement that repeats the value is named, with
      // the ways SQLite skips or updates such a row.
      try expect(
        error.message.hasPrefix("Statement 2: people.email must hold distinct values")
          && error.message.contains("INSERT OR IGNORE"), error.message)
    }
    try expect(try b.dataset(people.id).rowCount == 1)
    try expect(try b.datasets().count == 2)
    // INSERT OR IGNORE, ON CONFLICT and REPLACE meet a real unique column in the copy.
    let ignored = try sql(
      b, "INSERT OR IGNORE INTO people VALUES ('a@example.com', 'Again')",
      "INSERT INTO people VALUES ('a@example.com', 'Upd') ON CONFLICT(email) DO UPDATE SET name = excluded.name",
      "SELECT email, name FROM people")
    try expect(rows(ignored) == [["a@example.com", "Upd"]], "\(rows(ignored))")
    let replaced = try sql(
      b, "REPLACE INTO people VALUES ('a@example.com', 'New')", "SELECT email, name FROM people")
    try expect(rows(replaced) == [["a@example.com", "New"]] && b.dataset(people.id).rowCount == 1)
  }

  check("UNIQUE over several columns is kept, shown, enforced at save and met by INSERT OR IGNORE") {
    let b = try book("UniqueSet")
    // The scenario that rolled back a whole call, the habits table with it.
    _ = try sql(
      b, "CREATE TABLE habits (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE)",
      "CREATE TABLE habit_logs (id INTEGER PRIMARY KEY, habit_id INTEGER NOT NULL, log_date TEXT NOT NULL, UNIQUE(habit_id, log_date))",
      "INSERT INTO habits (name) VALUES ('Read')",
      "INSERT INTO habit_logs (habit_id, log_date) VALUES (1, '2026-11-26')")
    let logs = try b.datasets().first { $0.title == "Habit logs" }!
    try expect(try b.datasets().count == 2)
    try expect(
      logs.columns[1].uniqueWith == [[logs.columns[2].id]] && logs.columns[1].unique == nil,
      "\(logs.columns)")
    try expect(try b.chatSQLTables().contains("UNIQUE(habit_id, log_date)"), try b.chatSQLTables())
    let catalog = try sql(b, "SELECT name, unique_with FROM columns WHERE table_name = 'habit_logs' AND unique_with IS NOT NULL")
    try expect(rows(catalog) == [["habit_id", "log_date"], ["log_date", "habit_id"]], "\(rows(catalog))")
    // A later call that repeats the pair is ignored, as SQLite would, and a new day is added.
    let again = try sql(
      b, "INSERT OR IGNORE INTO habit_logs (habit_id, log_date) VALUES (1, '2026-11-26')",
      "INSERT INTO habit_logs (habit_id, log_date) VALUES (1, '2026-11-27') ON CONFLICT DO NOTHING",
      "INSERT OR IGNORE INTO habits (name) VALUES ('Read')",
      "SELECT count(*) FROM habit_logs")
    try expect(rows(again) == [["2"]] && b.dataset(logs.id).rowCount == 2, "\(rows(again))")
    // A plain duplicate is refused in the copy, and nothing of the call is saved.
    try refuses {
      _ = try sql(
        b, "INSERT INTO habits (name) VALUES ('Walk')",
        "INSERT INTO habit_logs (habit_id, log_date) VALUES (1, '2026-11-27')")
    }
    try expect(try b.dataset(b.chatTableID("habits")).rowCount == 1)
    // A row change from outside sql, as an app sends it, is refused naming both values.
    do {
      _ = try b.chatTableTransaction(
        logs.id, expectedDefinitionID: logs.definitionID,
        operations: [
          .object([
            "op": .string("insert"),
            "values": .object([
              logs.columns[1].id: .string("1"), logs.columns[2].id: .string("2026-11-26"),
            ]),
          ])
        ])
      throw SevraError("test", "A duplicate pair was saved.")
    } catch let error as SevraError where error.code == "unique" {
      try expect(
        error.message.contains("Habit id and Log date together") && error.message.contains("\"2026-11-26\""),
        error.message)
    }
    // A composite key is a set too, with each of its columns required.
    _ = try sql(b, "CREATE TABLE prices (supplier TEXT, part TEXT, price REAL, PRIMARY KEY (supplier, part))")
    let prices = try b.datasets().first { $0.title == "Prices" }!
    try expect(
      prices.columns[0].uniqueWith == [[prices.columns[1].id]] && prices.columns[0].required == true
        && prices.columns[1].required == true && prices.columns[0].autoNumber == nil, "\(prices.columns)")
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

  check("Tables for sql lists the few values of a category column, follows the data and leaves out names, ids and dates") {
    let b = try book("Values")
    _ = try sql(
      b,
      "CREATE TABLE entries (id INTEGER PRIMARY KEY, ref_id TEXT, label TEXT, state TEXT, kind TEXT, day TEXT, amount REAL)",
      "INSERT INTO entries (ref_id, label, state, kind, day, amount) VALUES ('r1', 'Alpha', 'open', 'x', '2026-11-01', 10), ('r2', 'Beta', 'done', 'x', '2026-11-02', 20), ('r3', 'Gamma', 'open', 'y', '2026-11-01', 30), ('r4', 'Delta', 'void', 'x', '2026-11-02', 40), ('r5', 'Epsilon', 'open', 'y', '2026-11-01', 50), ('r6', 'Zeta', 'done', 'x', '2026-11-02', 60)")
    let listed = try b.chatSQLTables()
    try expect(
      listed.contains("state TEXT (values 'done', 'open', 'void'), kind TEXT (values 'x', 'y')"),
      listed)
    // Six names in six rows are free text, an id-named column and dates are not categories.
    try expect(
      listed.contains("label TEXT,") && listed.contains("ref_id TEXT,") && listed.contains("day TEXT,"),
      listed)
    // A new value shows up on the next request, and a column past eight values is left out.
    _ = try sql(b, "UPDATE entries SET state = 'held' WHERE label = 'Delta'")
    try expect(try b.chatSQLTables().contains("state TEXT (values 'done', 'held', 'open')"), try b.chatSQLTables())
    _ = try sql(
      b, "INSERT INTO entries (label, kind) VALUES ('a', 'k1'), ('b', 'k2'), ('c', 'k3'), ('d', 'k4'), ('e', 'k5'), ('f', 'k6'), ('g', 'k7'), ('h', 'k8'), ('i', 'k9'), ('j', 'k9'), ('k', 'k9'), ('l', 'k9'), ('m', 'k9'), ('n', 'k9'), ('o', 'k9'), ('p', 'k9'), ('q', 'k9'), ('r', 'k9')")
    try expect(try b.chatSQLTables().contains("kind TEXT,"), try b.chatSQLTables())
    // The values have their own budget: past it a column is listed without them.
    try expect(!(try b.chatSQLTables(valueByteLimit: 10).contains("(values")))
  }

  check("a table filled from a summary of another, and a row of column totals, get a notice; plain copies and data rows do not") {
    let b = try book("Derived")
    _ = try sql(
      b, "CREATE TABLE facts (area TEXT, amount REAL, units REAL)",
      "INSERT INTO facts VALUES ('a', 10, 1), ('b', 20, 2), ('a', 5, 3), ('c', 7, 4)")
    let made = try sql(
      b, "CREATE TABLE by_area (area TEXT, amount REAL)",
      "INSERT INTO by_area (area, amount) SELECT area, SUM(amount) FROM facts GROUP BY area")
    try expect(
      made["notice"].text.contains("by_area is a snapshot worked out from facts now")
        && made["notice"].text.contains("chart facts itself"), made["notice"].text)
    let created = try sql(b, "CREATE TABLE counted AS SELECT area, count(*) AS n FROM facts GROUP BY area")
    try expect(created["notice"].text.contains("counted is a snapshot"), created["notice"].text)
    // A copy of rows with no summary, and a value read inside VALUES, are not snapshots.
    let copied = try sql(
      b, "CREATE TABLE kept (area TEXT, amount REAL)",
      "INSERT INTO kept (area, amount) SELECT area, amount FROM facts WHERE amount > 6",
      "INSERT INTO kept (area, amount) VALUES ('z', (SELECT 1))")
    try expect(!copied["notice"].text.contains("snapshot"), copied["notice"].text)
    // A row whose number is the sum of the other rows' is a total row, whatever its label.
    let total = try sql(b, "INSERT INTO by_area (area, amount) VALUES ('All', 42)")
    try expect(
      total["notice"].text.contains("repeats the totals of its other rows")
        && total["notice"].text.contains("offer to undo"), total["notice"].text)
    // A genuine row, and a row of two columns where only one adds up, are not.
    let row = try sql(b, "INSERT INTO facts VALUES ('d', 12, 5)")
    try expect(!row["notice"].text.contains("repeats"), row["notice"].text)
    let half = try sql(b, "INSERT INTO facts VALUES ('e', 54, 1)")
    try expect(!half["notice"].text.contains("repeats"), half["notice"].text)
    let sums = try sql(b, "INSERT INTO facts VALUES ('Sum', 108, 16)")
    try expect(sums["notice"].text.contains("repeats the totals"), sums["notice"].text)
  }

  check("a saved query or tool that compares with today or now written out gets 'now'; other dates and written values stay") {
    let zone = TimeZone(identifier: "America/New_York")!
    var parts = DateComponents()
    (parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second) = (2026, 11, 26, 14, 5, 30)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let now = calendar.date(from: parts)!
    func rewrite(_ sql: String) -> String {
      CurrentDateLiterals.rewrite(sql, now: [now], timeZone: zone).text
    }
    for (given, expected) in [
      ("SELECT * FROM t WHERE status = 'open' AND due < '2026-11-26'",
       "SELECT * FROM t WHERE status = 'open' AND due < date('now')"),
      ("SELECT * FROM t WHERE '2026-11-26' >= due", "SELECT * FROM t WHERE date('now') >= due"),
      ("SELECT * FROM t WHERE due BETWEEN '2026-11-01' AND '2026-11-26'",
       "SELECT * FROM t WHERE due BETWEEN '2026-11-01' AND date('now')"),
      ("SELECT * FROM t WHERE strftime('%Y-%m', due) = '2026-11'",
       "SELECT * FROM t WHERE strftime('%Y-%m', due) = strftime('%Y-%m','now')"),
      ("SELECT * FROM t WHERE at >= '2026-11-26 14:05'",
       "SELECT * FROM t WHERE at >= strftime('%Y-%m-%d %H:%M','now')"),
      ("SELECT * FROM t WHERE due <= date('2026-11-26', '+7 days')",
       "SELECT * FROM t WHERE due <= date('now', '+7 days')"),
      ("UPDATE t SET done = '2026-11-26' WHERE due < '2026-11-26'",
       "UPDATE t SET done = '2026-11-26' WHERE due < date('now')"),
    ] {
      try expect(rewrite(given) == expected, rewrite(given))
    }
    // Another day is data, as is today written into a row, a month without a month format,
    // and a quoted name.
    for kept in [
      "SELECT * FROM t WHERE due < '2026-11-20'",
      "INSERT INTO t (due) VALUES ('2026-11-26')",
      "SELECT * FROM t WHERE substr(due, 1, 7) = '2026-11'",
      "SELECT \"2026-11-26\" FROM t",
      "SELECT * FROM t WHERE at >= '2026-11-26 15:05'",
    ] {
      try expect(rewrite(kept) == kept, rewrite(kept))
    }
    try expect(
      CurrentDateLiterals.notice(["date('now')"])
        == "Wrote date('now') for today's date so it stays current.")

    // Through the chat tools: a view's query and a saved tool are saved with date('now').
    let b = try book("Today")
    _ = try sql(
      b, "CREATE TABLE items (name TEXT, status TEXT, due TEXT)",
      "INSERT INTO items VALUES ('a', 'open', '2026-01-01'), ('b', 'open', '2999-01-01')")
    let format = DateFormatter()
    format.locale = Locale(identifier: "en_US_POSIX")
    format.dateFormat = "yyyy-MM-dd"
    let today = format.string(from: Date())
    let tools = WorkbookTools(b, conversation: "")
    let saved = try tools.execute(
      "save_space",
      .object([
        "title": .string("Due"),
        "definition": .object([
          "version": .number(1),
          "components": .array([
            .object([
              "id": .string("t1"), "type": .string("table"), "title": .string("Past due"),
              "query": .string("SELECT name, due FROM items WHERE status = 'open' AND due < '\(today)'"),
            ])
          ]),
        ]),
      ]))
    try expect(
      try b.space(saved["spaceID"].text).definition.components.first?.query
        == "SELECT name, due FROM items WHERE status = 'open' AND due < date('now')")
    try expect(saved["notice"].text.contains("Wrote date('now') for today's date"), "\(saved)")
    let tool = try tools.execute(
      "save",
      .object([
        "kind": .string("tool"), "name": .string("past_due"), "description": .string("Rows past due"),
        "inputs": .array([]),
        "statements": .array([.string("SELECT name FROM items WHERE due < '\(today)' AND due > '2000-01-01'")]),
      ]))
    try expect(tool["notice"].text.hasPrefix("Wrote date('now') for today's date"), "\(tool)")
    try expect(
      try b.savedTools().first { $0.name == "past_due" }?.statements
        == ["SELECT name FROM items WHERE due < date('now') AND due > '2000-01-01'"])
  }
}
