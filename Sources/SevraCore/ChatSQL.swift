import CSQLite
import Foundation

/// The `sql` chat tool, first slice of the general chat tools plan.
///
/// The model's statements never touch the workbook file. They run on a private in-memory
/// copy of the tables they name. Row changes found on the copy are applied through the
/// recorded row transaction, so history and Undo hold. Changing a table's shape is refused.
extension Workbook {
  public func chatSQL(
    statements: [String], readOnly: Bool, draft: Bool = false, token: String,
    requestSourceID: String?, cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      (1...8).contains(statements.count) && statements.allSatisfy { $0.utf8.count <= 8_000 },
      "sql", "Send one to eight statements, each under 8,000 bytes.")
    return try synchronized(cancellation: cancellation) {
      let scratch = try SQLScratch(
        tables: datasets(), readOnly: readOnly, cancellation: cancellation)
      defer { scratch.close() }
      try scratch.discover(statements)
      try scratch.fill { table in
        var loaded: [(String, [String: Value])] = []
        while true {
          let page = try rows(table.id, offset: loaded.count, limit: 200)
          loaded += page.map { ($0.id, calculatedValues($0, columns: table.columns)) }
          if page.count < 200 { return loaded }
          try cancellation.check()
        }
      }
      let results = try scratch.run(statements)
      let changes = try scratch.changes()
      try require(
        changes.allSatisfy { $0.operations.count <= SQLScratch.changeLimit }, "sql_limit",
        "One call can change at most \(SQLScratch.changeLimit) rows of a table for now. Nothing was changed. Split the change.")
      var saved: [Value] = []
      if draft {
        // A draft changes nothing. Today's proposals cover edits to existing rows.
        try require(
          changes.allSatisfy { $0.inserted == 0 && $0.deleted == 0 }, "sql_draft",
          "A draft can hold UPDATEs only for now. Nothing was changed or saved.")
        for change in changes {
          let edits = change.operations.map {
            RowEdit(id: $0["id"].text, values: $0["values"].object)
          }
          let proposal = try proposeTableEdit(
            change.table.id, edits: edits, token: token + "-" + change.name)
          saved.append(
            .object([
              "table": .string(change.name), "title": .string(change.table.title),
              "draftRows": .number(Double(edits.count)), "proposal": try encoded(proposal),
            ]))
        }
      }
      // The write path records an AI change only under an exact saved rule Source.
      var actor = ChangeAttribution.actor
      if !draft, !changes.isEmpty, let model = actor, model.kind == "ai" {
        actor = .ai(
          model.component, model: model.model!,
          policy: try chatTableChangePolicy(cancellation: cancellation))
      }
      for change in draft ? [] : changes {
        let transaction = try ChangeAttribution.$actor.withValue(actor) {
          try chatTableTransaction(
            change.table.id, expectedDefinitionID: change.table.definitionID,
            operations: change.operations, token: token + "-" + change.name,
            requestSourceID: requestSourceID, cancellation: cancellation)
        }
        saved.append(
          .object([
            "table": .string(change.name), "title": .string(change.table.title),
            "inserted": .number(Double(change.inserted)),
            "updated": .number(Double(change.updated)),
            "deleted": .number(Double(change.deleted)),
            "undo": .object([
              "id": .string(change.table.id),
              "expectedDefinitionID": .string(change.table.definitionID),
              "token": transaction["token"],
            ]),
          ]))
      }
      // What the answer rests on: the rows of small tables, or the table's own Source.
      // Rows this call replaced are no longer current, so a changed table offers none.
      let read = scratch.readTables.filter { name in !changes.contains { $0.name == name } }
      let few = read.reduce(0) { $0 + scratch.rowIDs($1).count } <= SQLScratch.namedRowLimit
      var inputs: [String] = []
      for name in read {
        let ids = scratch.rowIDs(name)
        if few {
          inputs += ids
        } else if let source = try datasetSource(scratch.table(name).id) {
          inputs.append(source)
        } else {
          inputs += ids.prefix(8)
        }
      }
      var fields: [String: Value] = [
        "results": .array(results),
        "read": .array(
          scratch.readTables.map {
            .object([
              "table": .string($0), "title": .string(scratch.table($0).title),
              "rows": .number(Double(scratch.rowIDs($0).count)),
            ])
          }),
        "inputs": .array(inputs.map(Value.string)),
      ]
      if !saved.isEmpty {
        fields[draft ? "drafts" : "changes"] = .array(saved)
        fields["notice"] = .string(
          draft
            ? "Saved as a proposal for the user to review. The table is unchanged."
            : "Saved. Each changed table has one Undo: workspace_action table.undo_rows with its undo values.")
      }
      return .object(fields)
    }
  }
}

extension Workbook {
  /// The tables as sql names them, for the request's context, so the model need not look
  /// them up. Long workbooks list what fits and point at the catalog for the rest.
  public func chatSQLTables(byteLimit: Int = 2_400) throws -> String {
    let named = SQLScratch.named(try datasets())
    var lines: [String] = []
    var bytes = 0
    for entry in named {
      let line =
        entry.name + "("
        + entry.columns.map {
          $0.name + ($0.column.formula != nil ? " formula" : $0.column.type == "decimal" ? " number" : "")
        }.joined(separator: ", ") + ") \(entry.dataset.rowCount) rows"
      guard bytes + line.utf8.count <= byteLimit else { break }
      bytes += line.utf8.count
      lines.append(line)
    }
    guard !lines.isEmpty else { return "" }
    return "Tables for sql: " + lines.joined(separator: "; ")
      + (lines.count < named.count
        ? "; \(named.count - lines.count) more in SELECT * FROM tables" : "")
  }

  /// A host-owned, exact rule Source for row changes a person asks for in chat.
  /// It is published programmatically, never fabricated as a human acceptance or model rule.
  func chatTableChangePolicy(cancellation: Cancellation) throws -> String {
    let text = """
      Sevra chat table changes policy v1. A current user request in chat may authorize the local
      model to insert, update and delete rows of the workbook's tables with the sql tool. The host
      runs the model's statements on a private copy, applies the row changes through the recorded
      row transaction, attributes them to this rule and keeps one Undo for each changed table.
      This policy does not authorize changing a table's columns, accepting or withdrawing drafts,
      running apps or automations, or any change in a request that forbids changes.
      """
    let result = try mutation(
      "chat_table_change_policy", token: "sevra-chat-table-change-policy-v1",
      request: .string(text), cancellation: cancellation,
      actor: .programmatic("Sevra.chat.tableChangePolicy"),
      readBack: { value in
        let rule = try self.item(value.text)
        try require(
          rule.id == value.text && self.item(rule.logicalID).id == rule.id
            && rule.category == "source" && rule.kind == "rule" && rule.meaning == "rule"
            && rule.status == "accepted" && rule.text == text,
          "decision_policy",
          "The saved chat table changes policy changed. Inspect its history before continuing.")
      },
      {
        .string(
          try insertItem(
            category: "source", kind: "rule", title: "Chat table changes policy",
            text: text, data: .object(["contract": .string("chat-table-change-policy-v1")]),
            meaning: "rule", status: "accepted", scenario: "actual", inputs: [],
            transformation: "chat-table-change-policy-v1"))
      })
    return result.text
  }
}

final class SQLScratch {
  static let changeLimit = 64
  static let namedRowLimit = 24
  static let rowLimit = 20_000
  static let shownRows = 50
  static let shownBytes = 9_000
  private static let log = "_sevra_log"
  private static let shapeRefusal =
    "sql reads tables and changes rows. It cannot create, drop or reshape a table yet. Use WITH for intermediate results. For a new table use propose_table; to add, rename or remove a column use workspace_action table.edit_schema."
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  struct Change {
    let name: String
    let table: Dataset
    let operations: [Value]
    let inserted: Int
    let updated: Int
    let deleted: Int
  }
  private struct Entry {
    let name: String
    let dataset: Dataset
    let columns: [(name: String, column: Column)]
    var rows: [Int64: String] = [:]
    var loaded: [Int64: [Value]] = [:]
  }

  private var handle: OpaquePointer?
  private var entries: [String: Entry] = [:]
  private var order: [String] = []
  private let readOnly: Bool
  private let cancellation: Cancellation
  private var guarded = false
  private var read = Set<String>()
  private var written = Set<String>()
  private var refusal: SevraError?
  private var deadline = Date.distantFuture
  private var shown = 0

  var readTables: [String] { order.filter(read.contains) }
  func table(_ name: String) -> Dataset { entries[name]!.dataset }
  func rowIDs(_ name: String) -> [String] {
    entries[name]!.rows.sorted { $0.key < $1.key }.map(\.value)
  }

  init(tables: [Dataset], readOnly: Bool, cancellation: Cancellation) throws {
    self.readOnly = readOnly
    self.cancellation = cancellation
    guard
      sqlite3_open_v2(
        ":memory:", &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_MEMORY, nil)
        == SQLITE_OK
    else {
      close()
      throw SevraError("sql", "The query workspace could not be opened.")
    }
    sqlite3_limit(handle, SQLITE_LIMIT_ATTACHED, 0)
    try execute("PRAGMA trusted_schema=OFF")
    try execute("PRAGMA recursive_triggers=ON")
    // 4 KiB pages: 128 MiB for the copy and everything a statement builds.
    try execute("PRAGMA max_page_count=32768")
    try execute(
      "CREATE TABLE tables(table_name TEXT, title TEXT, row_count INTEGER, id TEXT, version INTEGER, definition_id TEXT)")
    try execute(
      "CREATE TABLE columns(table_name TEXT, column_name TEXT, title TEXT, type TEXT, formula TEXT)")
    try execute("CREATE TABLE \"\(Self.log)\"(tbl TEXT, id INTEGER)")
    for (name, dataset, columns) in Self.named(tables) {
      try execute(
        "CREATE TABLE \"\(name)\"("
          + columns.map {
            "\"\($0.name)\" " + ($0.column.type == "decimal" || $0.column.formula != nil ? "REAL" : "TEXT")
          }.joined(separator: ",") + ")")
      try execute(
        "INSERT INTO tables VALUES(?,?,?,?,?,?)",
        [
          .string(name), .string(dataset.title), .number(Double(dataset.rowCount)),
          .string(dataset.id), .number(Double(dataset.version)), .string(dataset.definitionID),
        ])
      for entry in columns {
        try execute(
          "INSERT INTO columns VALUES(?,?,?,?,?)",
          [
            .string(name), .string(entry.name), .string(entry.column.title),
            .string(entry.column.formula == nil ? entry.column.type : "formula"),
            entry.column.formula.map(Value.string) ?? .null,
          ])
      }
      entries[name] = Entry(name: name, dataset: dataset, columns: columns)
      order.append(name)
    }
    let context = Unmanaged.passUnretained(self).toOpaque()
    sqlite3_set_authorizer(
      handle,
      { context, action, first, second, _, trigger in
        Unmanaged<SQLScratch>.fromOpaque(context!).takeUnretainedValue().authorize(
          action, first.map { String(cString: $0) }, second.map { String(cString: $0) },
          inTrigger: trigger != nil)
      }, context)
    sqlite3_progress_handler(
      handle, 20_000,
      { context in
        Unmanaged<SQLScratch>.fromOpaque(context!).takeUnretainedValue().expired() ? 1 : 0
      }, context)
  }

  func close() {
    sqlite3_close_v2(handle)
    handle = nil
  }

  // MARK: Names

  /// The name each table and column has in sql: its title in lower case with underscores.
  static func named(_ tables: [Dataset]) -> [(
    name: String, dataset: Dataset, columns: [(name: String, column: Column)]
  )] {
    var taken: Set<String> = ["tables", "columns", log]
    return tables.filter { !$0.archived && !$0.columns.isEmpty }.map { dataset in
      let name = unique(identifier(dataset.title, fallback: "table"), in: &taken)
      var columnNames: Set<String> = ["rowid", "oid", "_rowid_"]
      let columns = dataset.columns.map { column in
        (
          name: unique(identifier(column.title, fallback: column.id), in: &columnNames),
          column: column
        )
      }
      return (name, dataset, columns)
    }
  }

  private static func identifier(_ title: String, fallback: String) -> String {
    func slug(_ text: String) -> String {
      var out = ""
      for scalar in text.lowercased().unicodeScalars {
        if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
          out.unicodeScalars.append(scalar)
        } else if !out.hasSuffix("_") && !out.isEmpty {
          out += "_"
        }
      }
      while out.hasSuffix("_") { out.removeLast() }
      return String(out.prefix(48))
    }
    var name = slug(title)
    if name.isEmpty { name = slug(fallback) }
    if name.isEmpty { name = "x" }
    if name.first!.isNumber || name.hasPrefix("sqlite_") || name.hasPrefix("_sevra") {
      name = "t_" + name
    }
    return name
  }
  private static func unique(_ name: String, in taken: inout Set<String>) -> String {
    var candidate = name
    var suffix = 2
    while !taken.insert(candidate).inserted {
      candidate = name + "_\(suffix)"
      suffix += 1
    }
    return candidate
  }

  // MARK: What a statement may do

  private func expired() -> Bool {
    Date() > deadline || (try? cancellation.check()) == nil
  }

  private func authorize(_ action: Int32, _ first: String?, _ second: String?, inTrigger: Bool)
    -> Int32
  {
    guard guarded else { return SQLITE_OK }
    func refuse(_ code: String, _ message: String) -> Int32 {
      if refusal == nil { refusal = SevraError(code, message) }
      return SQLITE_DENY
    }
    let name = (first ?? "").lowercased()
    switch action {
    case SQLITE_SELECT, SQLITE_RECURSIVE: return SQLITE_OK
    case SQLITE_FUNCTION:
      return ["load_extension", "readfile", "writefile", "edit"].contains(
        (second ?? "").lowercased())
        ? refuse("sql", "That function is not available.") : SQLITE_OK
    case SQLITE_READ:
      if name == Self.log || name.hasPrefix("sqlite_") {
        return inTrigger
          ? SQLITE_OK
          : refuse("sql", "Use SELECT * FROM columns to see the tables and their columns.")
      }
      if entries[name] != nil { read.insert(name) }
      return SQLITE_OK
    case SQLITE_INSERT, SQLITE_UPDATE, SQLITE_DELETE:
      if name == Self.log, inTrigger { return SQLITE_OK }
      // Creating, dropping or altering a table first writes the schema table.
      if name.hasPrefix("sqlite_") { return refuse("sql_shape", Self.shapeRefusal) }
      guard let entry = entries[name] else {
        return refuse("sql", "The tables and columns lists are read-only.")
      }
      if readOnly {
        return refuse(
          "read_only_request",
          "The current request forbids changes. Read with SELECT and answer.")
      }
      if action == SQLITE_UPDATE,
        let column = entry.columns.first(where: { $0.name == (second ?? "").lowercased() }),
        column.column.formula != nil
      {
        return refuse(
          "sql", "\(column.name) is a formula column. Change the columns it is calculated from.")
      }
      written.insert(name)
      return SQLITE_OK
    case SQLITE_TRANSACTION, SQLITE_SAVEPOINT:
      return refuse(
        "sql",
        "One sql call is one change, saved together. Remove BEGIN, COMMIT, ROLLBACK and SAVEPOINT.")
    case SQLITE_CREATE_TABLE, SQLITE_CREATE_TEMP_TABLE, SQLITE_DROP_TABLE, SQLITE_DROP_TEMP_TABLE,
      SQLITE_ALTER_TABLE, SQLITE_CREATE_INDEX, SQLITE_CREATE_TEMP_INDEX, SQLITE_DROP_INDEX,
      SQLITE_DROP_TEMP_INDEX, SQLITE_CREATE_VIEW, SQLITE_CREATE_TEMP_VIEW, SQLITE_DROP_VIEW,
      SQLITE_DROP_TEMP_VIEW, SQLITE_CREATE_TRIGGER, SQLITE_CREATE_TEMP_TRIGGER, SQLITE_DROP_TRIGGER,
      SQLITE_DROP_TEMP_TRIGGER, SQLITE_CREATE_VTABLE, SQLITE_DROP_VTABLE:
      return refuse("sql_shape", Self.shapeRefusal)
    default:
      return refuse("sql", "That statement is not available in sql.")
    }
  }

  // MARK: Statements

  private func failure(_ index: Int?) -> SevraError {
    if let refusal { return refusal }
    let message = String(cString: sqlite3_errmsg(handle))
    if expired() {
      return SevraError("sql_limit", "The statement ran too long and was stopped. Narrow it.")
    }
    return SevraError(
      "sql",
      (index.map { "Statement \($0 + 1): " } ?? "") + message
        + ". SELECT * FROM columns lists every table and column name.")
  }

  private func prepare(_ sql: String, index: Int? = nil) throws -> OpaquePointer? {
    refusal = nil
    var statement: OpaquePointer?
    var failed = false
    var trailing = false
    sql.withCString { start in
      var tail: UnsafePointer<CChar>?
      failed = sqlite3_prepare_v2(handle, start, -1, &statement, &tail) != SQLITE_OK
      if let tail {
        trailing = !String(cString: tail).trimmingCharacters(
          in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";"))
        ).isEmpty
      }
    }
    if failed {
      sqlite3_finalize(statement)
      throw failure(index)
    }
    if trailing {
      sqlite3_finalize(statement)
      throw SevraError("sql", "Put each statement in its own entry of statements.")
    }
    return statement
  }

  private func execute(_ sql: String, _ values: [Value] = []) throws {
    guard let statement = try prepare(sql) else { return }
    defer { sqlite3_finalize(statement) }
    for (index, value) in values.enumerated() { bind(statement, Int32(index + 1), value) }
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return }
      if code != SQLITE_ROW { throw failure(nil) }
    }
  }

  private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Value) {
    switch value {
    case .null: sqlite3_bind_null(statement, index)
    case .number(let number): sqlite3_bind_double(statement, index, number)
    case .bool(let flag): sqlite3_bind_text(statement, index, flag ? "true" : "false", -1, Self.transient)
    default: sqlite3_bind_text(statement, index, value.text, -1, Self.transient)
    }
  }

  /// A number as the workbook writes it: fifteen significant digits, the most a
  /// floating-point number holds exactly, in plain decimal notation.
  static func decimalText(_ number: Double) -> String? {
    guard number.isFinite, let decimal = Decimal(string: String(format: "%.15g", number)) else {
      return nil
    }
    return Numbers.string(decimal)
  }

  private func cell(_ statement: OpaquePointer?, _ index: Int32) -> Value {
    switch sqlite3_column_type(statement, index) {
    case SQLITE_NULL: return .null
    case SQLITE_INTEGER: return .string(String(sqlite3_column_int64(statement, index)))
    case SQLITE_FLOAT:
      let number = sqlite3_column_double(statement, index)
      return .string(Self.decimalText(number) ?? String(number))
    case SQLITE_TEXT: return .string(String(cString: sqlite3_column_text(statement, index)))
    default: return .string("(binary)")
    }
  }

  /// Checks every statement against the empty tables, and learns which tables they name.
  func discover(_ statements: [String]) throws {
    guarded = true
    defer { guarded = false }
    for (index, sql) in statements.enumerated() {
      sqlite3_finalize(try prepare(sql, index: index))
    }
  }

  /// Copies in the tables the statements name, then starts recording row changes.
  func fill(_ load: (Dataset) throws -> [(String, [String: Value])]) throws {
    var total = 0
    for name in order where read.contains(name) || written.contains(name) {
      var entry = entries[name]!
      let rows = try load(entry.dataset)
      total += rows.count
      try require(
        total <= Self.rowLimit, "sql_limit",
        "These tables hold more than \(Self.rowLimit) rows, which sql cannot read yet.")
      let insert = try prepare(
        "INSERT INTO \"\(name)\"(rowid,"
          + entry.columns.map { "\"\($0.name)\"" }.joined(separator: ",") + ") VALUES(?"
          + String(repeating: ",?", count: entry.columns.count) + ")")
      defer { sqlite3_finalize(insert) }
      for (offset, row) in rows.enumerated() {
        let id = Int64(offset + 1)
        sqlite3_reset(insert)
        sqlite3_bind_int64(insert, 1, id)
        for (index, column) in entry.columns.enumerated() {
          let value = row.1[column.column.id] ?? .null
          let numeric = column.column.type == "decimal" || column.column.formula != nil
          if value == .null || value.text.isEmpty {
            sqlite3_bind_null(insert, Int32(index + 2))
          } else if numeric, let decimal = try? Numbers.decimal(value.text),
            let number = Double(Numbers.string(decimal))
          {
            sqlite3_bind_double(insert, Int32(index + 2), number)
          } else {
            sqlite3_bind_text(insert, Int32(index + 2), value.text, -1, Self.transient)
          }
        }
        guard sqlite3_step(insert) == SQLITE_DONE else { throw failure(nil) }
        entry.rows[id] = row.0
      }
      // Read back through the same rendering a later comparison uses.
      let select = try prepare("SELECT rowid,* FROM \"\(name)\"")
      defer { sqlite3_finalize(select) }
      while sqlite3_step(select) == SQLITE_ROW {
        entry.loaded[sqlite3_column_int64(select, 0)] = entry.columns.indices.map {
          cell(select, Int32($0 + 1))
        }
      }
      entries[name] = entry
      for (kind, event, rows) in [
        ("i", "INSERT", ["NEW"]), ("u", "UPDATE", ["OLD", "NEW"]), ("d", "DELETE", ["OLD"]),
      ] {
        try execute(
          "CREATE TRIGGER \"_sevra_\(kind)_\(name)\" AFTER \(event) ON \"\(name)\" BEGIN "
            + rows.map { "INSERT INTO \"\(Self.log)\" VALUES('\(name)',\($0).rowid);" }.joined()
            + " END")
      }
    }
    read = []
    written = []
  }

  func run(_ statements: [String]) throws -> [Value] {
    guarded = true
    deadline = Date().addingTimeInterval(3)
    defer {
      guarded = false
      deadline = .distantFuture
    }
    var results: [Value] = []
    for (index, sql) in statements.enumerated() {
      guard let statement = try prepare(sql, index: index) else {
        results.append(.object(["changedRows": .number(0)]))
        continue
      }
      defer { sqlite3_finalize(statement) }
      let count = sqlite3_column_count(statement)
      var rows: [Value] = []
      var total = 0
      while true {
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE { break }
        guard code == SQLITE_ROW else { throw failure(index) }
        total += 1
        guard rows.count < Self.shownRows, shown < Self.shownBytes else { continue }
        let row = Value.array((0..<count).map { cell(statement, $0) })
        shown += (try? row.json().utf8.count) ?? 0
        rows.append(row)
      }
      if count == 0 {
        results.append(.object(["changedRows": .number(Double(sqlite3_changes(handle)))]))
        continue
      }
      var fields: [String: Value] = [
        "columns": .array(
          (0..<count).map { .string(String(cString: sqlite3_column_name(statement, $0))) }),
        "rows": .array(rows), "rowCount": .number(Double(total)),
      ]
      if rows.count < total {
        fields["notice"] = .string(
          "Only the first \(rows.count) of \(total) rows are shown. Aggregate, filter, or page with LIMIT and OFFSET.")
      }
      results.append(.object(fields))
    }
    return results
  }

  // MARK: Row changes

  /// The net effect on each table's rows, as operations the recorded row transaction takes.
  func changes() throws -> [Change] {
    var found: [Change] = []
    for name in order where written.contains(name) {
      let entry = entries[name]!
      var touched: [Int64] = []
      let ids = try prepare("SELECT DISTINCT id FROM \"\(Self.log)\" WHERE tbl=? ORDER BY id")
      defer { sqlite3_finalize(ids) }
      sqlite3_bind_text(ids, 1, name, -1, Self.transient)
      while sqlite3_step(ids) == SQLITE_ROW { touched.append(sqlite3_column_int64(ids, 0)) }
      let select = try prepare("SELECT * FROM \"\(name)\" WHERE rowid=?")
      defer { sqlite3_finalize(select) }
      var operations: [Value] = []
      var counts = (inserted: 0, updated: 0, deleted: 0)
      for id in touched {
        sqlite3_reset(select)
        sqlite3_bind_int64(select, 1, id)
        let now =
          sqlite3_step(select) == SQLITE_ROW
          ? entry.columns.indices.map { cell(select, Int32($0)) } : nil
        let before = entry.loaded[id]
        func stored(_ index: Int) throws -> Value {
          let column = entry.columns[index].column
          let value = now![index]
          guard value != .null, column.type == "decimal" else { return value }
          guard (try? Numbers.decimal(value.text)) != nil else {
            throw SevraError(
              "sql_value",
              "\(entry.columns[index].name) holds numbers, and \"\(value.text.prefix(40))\" is not one. Nothing was changed.")
          }
          return value
        }
        let writable = entry.columns.indices.filter { entry.columns[$0].column.formula == nil }
        switch (before, now) {
        case (.some(let before), .some(let now)):
          let changed = writable.filter { before[$0] != now[$0] }
          guard !changed.isEmpty else { continue }
          var values: [String: Value] = [:]
          for index in changed { values[entry.columns[index].column.id] = try stored(index) }
          operations.append(
            .object([
              "op": .string("update"), "id": .string(entry.rows[id]!), "values": .object(values),
            ]))
          counts.updated += 1
        case (.some, .none):
          operations.append(.object(["op": .string("delete"), "id": .string(entry.rows[id]!)]))
          counts.deleted += 1
        case (.none, .some(let now)):
          var values: [String: Value] = [:]
          for index in writable where now[index] != .null {
            values[entry.columns[index].column.id] = try stored(index)
          }
          operations.append(.object(["op": .string("insert"), "values": .object(values)]))
          counts.inserted += 1
        case (.none, .none): continue
        }
      }
      if !operations.isEmpty {
        found.append(
          Change(
            name: name, table: entry.dataset, operations: operations, inserted: counts.inserted,
            updated: counts.updated, deleted: counts.deleted))
      }
    }
    return found
  }
}
