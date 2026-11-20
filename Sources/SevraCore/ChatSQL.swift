import CSQLite
import Foundation

/// The `sql` chat tool of the general chat tools plan.
///
/// The model's statements never touch the workbook file. They run on a private in-memory
/// copy of the tables they name. What changed on the copy, rows or a table's shape, is then
/// applied through the recorded write paths, so history and Undo hold.
extension Workbook {
  public func chatSQL(
    statements: [String], readOnly: Bool, draft: Bool = false, token: String,
    requestSourceID: String?, inputs: [String: Value]? = nil,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      (1...8).contains(statements.count) && statements.allSatisfy { $0.utf8.count <= 8_000 },
      "sql", "Send one to eight statements, each under 8,000 bytes.")
    return try synchronized(cancellation: cancellation) {
      let session = try ChatSQLSession(
        self, readOnly: readOnly, draft: draft, inputs: inputs, cancellation: cancellation)
      defer { session.close() }
      let results = try session.run(statements)
      return try saveChatSQL(
        session.scratch, results: results, draft: draft, token: token,
        requestSourceID: requestSourceID, cancellation: cancellation)
    }
  }

  /// Applies what the statements did on the copy through the recorded write paths.
  func saveChatSQL(
    _ scratch: SQLScratch, results: [Value], draft: Bool, token: String,
    requestSourceID: String?, cancellation: Cancellation
  ) throws -> Value {
    try synchronized(cancellation: cancellation) {
      let reshapes = try scratch.reshapes()
      let created = try scratch.createdTables()
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
            change.table.id, edits: edits, token: token + "-" + change.key)
          saved.append(
            .object([
              "table": .string(change.name), "title": .string(change.table.title),
              "draftRows": .number(Double(edits.count)), "proposal": try encoded(proposal),
            ]))
        }
      }
      let changing = !changes.isEmpty || !reshapes.isEmpty || !created.isEmpty
      var shaped: [Value] = []
      var current: [String: Dataset] = [:]
      var applied = 0
      do {
        try withChatChangeActor(needed: !draft && changing, cancellation: cancellation) {
          for reshape in reshapes {
            let before = reshape.table
            try updateDatasetDefinition(
              before.id, expectedVersion: before.version,
              expectedDefinitionID: before.definitionID, title: reshape.title,
              columns: reshape.columns, archived: reshape.archived ? true : nil,
              token: token + "-shape-" + reshape.key, cancellation: cancellation)
            applied += 1
            let after = try dataset(before.id)
            current[reshape.key] = after
            shaped.append(
              .object([
                "table": .string(reshape.name), "title": .string(after.title),
                "change": .string(reshape.archived ? "archived" : "reshaped"),
                "what": .array(reshape.notes.map(Value.string)),
              ]))
          }
          for table in created {
            let source =
              try requestSourceID
              ?? addItem(
                category: "source", kind: "note", title: table.title + " (created with sql)",
                text: "A sql statement created this table.", status: "accepted").id
            let made = try createDataset(
              title: table.title, columns: table.columns, rows: table.rows, sourceID: source,
              token: token + "-create-" + table.name)
            applied += 1
            shaped.append(
              .object([
                "table": .string(table.name), "title": .string(made.title),
                "change": .string("created"), "id": .string(made.id),
                "columns": .array(made.columns.map { .string($0.title) }),
                "rows": .number(Double(table.rows.count)),
              ]))
          }
          for change in draft ? [] : changes {
            let table = current[change.key] ?? change.table
            try chatTableTransaction(
              table.id, expectedDefinitionID: table.definitionID,
              operations: change.operations, token: token + "-" + change.key,
              requestSourceID: requestSourceID, limit: SQLScratch.changeLimit,
              cancellation: cancellation)
            applied += 1
            saved.append(
              .object([
                "table": .string(change.name), "title": .string(table.title),
                "inserted": .number(Double(change.inserted)),
                "updated": .number(Double(change.updated)),
                "deleted": .number(Double(change.deleted)),
              ]))
          }
        }
      } catch let failure as SevraError where applied > 0 {
        // A call saves all of its changes or none: take back the steps already saved.
        do {
          try withChatChangeActor(needed: true, cancellation: cancellation) {
            try undoChatSQLSteps(
              chatSQLSteps(token), token: token + "~rollback", cancellation: cancellation)
          }
        } catch {
          throw SevraError(
            failure.code,
            failure.message
              + " Part of this call was saved before that and could not be taken back. Inspect the tables."
          )
        }
        throw SevraError(failure.code, failure.message + " Nothing was changed.")
      }
      // What the answer rests on: the rows of small tables, or the table's own Source.
      // Rows this call replaced are no longer current, so a changed table offers none.
      let read = scratch.readTables.filter { key in
        !changes.contains { $0.key == key } && !reshapes.contains { $0.key == key }
      }
      let few = read.reduce(0) { $0 + scratch.rowIDs($1).count } <= SQLScratch.namedRowLimit
      var inputs: [String] = scratch.ledgerRead ? Array(scratch.ledgerSources.prefix(24)) : []
      for key in read {
        let ids = scratch.rowIDs(key)
        if few {
          inputs += ids
        } else if let source = try datasetSource(scratch.table(key).id) {
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
      if !shaped.isEmpty { fields["shape"] = .array(shaped) }
      if !saved.isEmpty { fields[draft ? "drafts" : "changes"] = .array(saved) }
      if draft, !saved.isEmpty {
        fields["notice"] = .string(
          "Saved as a proposal for the user to review. The table is unchanged.")
      } else if !saved.isEmpty || !shaped.isEmpty {
        fields["undo"] = .string(token)
        fields["notice"] = .string(
          "Saved. If the user asks to undo this, the undo action takes this result's undo value as its token.")
      }
      return .object(fields)
    }
  }
}

extension Workbook {
  /// The tables as sql names them, for the request's context, so the model need not look
  /// them up. Long workbooks list what fits and point at the catalog for the rest.
  public func chatSQLTables(byteLimit: Int = 2_400) throws -> String {
    let ledger = try hasStockLedger()
    let named = SQLScratch.named(try datasets(), ledger: ledger)
    let stock = ledger && SQLScratch.ledgerListing.utf8.count <= byteLimit
    var lines: [String] = stock ? [SQLScratch.ledgerListing] : []
    var bytes = stock ? SQLScratch.ledgerListing.utf8.count : 0
    for entry in named {
      let line =
        entry.name + "("
        + entry.columns.map {
          $0.name
            + ($0.column.formula != nil
              ? " REAL GENERATED" : $0.column.type == "decimal" ? " REAL" : " TEXT")
        }.joined(separator: ", ") + ") \(entry.dataset.rowCount) rows"
      guard bytes + line.utf8.count <= byteLimit else { break }
      bytes += line.utf8.count
      lines.append(line)
    }
    guard !lines.isEmpty else { return "" }
    let listed = lines.count - (stock ? 1 : 0)
    return "Tables for sql: " + lines.joined(separator: "; ")
      + (listed < named.count ? "; \(named.count - listed) more in SELECT * FROM tables" : "")
  }

  func hasStockLedger() throws -> Bool {
    try synchronized { try db.scalar("SELECT count(*) FROM bases").int ?? 0 > 0 }
  }

  /// The current balance of every item with an opening basis, by the ledger's own rules.
  /// An item whose basis is not yet in effect has no balance and is left out.
  func stockBalances() throws -> [Value] {
    try synchronized {
      try db.execute("SELECT subject FROM bases ORDER BY subject LIMIT 2000").compactMap {
        try? balance(subject: $0["subject"]!.text)
      }
    }
  }


  /// A host-owned, exact rule Source for table changes a person asks for in chat.
  /// It is published programmatically, never fabricated as a human acceptance or model rule.
  func chatTableChangePolicy(cancellation: Cancellation) throws -> String {
    let text = """
      Sevra chat table changes policy v2. A current user request in chat may authorize the local
      model to change the workbook's tables with the sql tool: insert, update and delete rows,
      create a table, rename or archive a table, and add, rename and remove columns. The host
      runs the model's statements on a private copy, applies what changed through the recorded
      write paths, attributes it to this rule and keeps an Undo for each changed table. This
      policy does not authorize accepting or withdrawing drafts, running apps or automations, or
      any change in a request that forbids changes.
      """
    let result = try mutation(
      "chat_table_change_policy", token: "sevra-chat-table-change-policy-v2",
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
            text: text, data: .object(["contract": .string("chat-table-change-policy-v2")]),
            meaning: "rule", status: "accepted", scenario: "actual", inputs: [],
            transformation: "chat-table-change-policy-v2"))
      })
    return result.text
  }
}

/// One saved step of a sql call, as its own operation receipt recorded it.
struct SQLStep {
  enum Kind { case rows, shape, created }
  let operation: String
  let kind: Kind
  let tableID: String
  /// A shape change's table definitions, before and after.
  var before: String?
  var after: String?
}

extension Workbook {
  /// Runs a change under the rule Source the write path needs from the model.
  func withChatChangeActor<T>(
    needed: Bool, cancellation: Cancellation, _ body: () throws -> T
  ) throws -> T {
    var actor = ChangeAttribution.actor
    if needed, let model = actor, model.kind == "ai" {
      actor = .ai(
        model.component, model: model.model!,
        policy: try chatTableChangePolicy(cancellation: cancellation))
    }
    return try ChangeAttribution.$actor.withValue(actor) { try body() }
  }

  /// What one sql call saved, oldest first. Each step kept the call's token in its own.
  func chatSQLSteps(_ token: String) throws -> [SQLStep] {
    try db.execute(
      "SELECT id,kind,request,result FROM operations WHERE id>=? AND id<? ORDER BY revision",
      [.string(token + "-"), .string(token + ".")]
    ).compactMap { row in
      let id = row["id"]!.text
      let request = try Value.parse(row["request"]!.text)
      let arguments = request.object["arguments"] ?? request
      let result = try Value.parse(row["result"]!.text)
      switch row["kind"]!.text {
      case "native_app_transaction":
        let space = arguments["space"].text
        guard space.hasPrefix("table:"), arguments["undo"] == .null else { return nil }
        return SQLStep(operation: id, kind: .rows, tableID: String(space.dropFirst(6)))
      case "dataset_definition":
        return SQLStep(
          operation: id, kind: .shape, tableID: arguments["datasetID"].text,
          before: arguments["baseDefinitionID"].text, after: result.text)
      case "dataset": return SQLStep(operation: id, kind: .created, tableID: result.text)
      default: return nil
      }
    }
  }

  /// The token of the sql call a chat answer saved changes with, when it was the only one.
  public func conversationSQLReceipt(_ messageID: String, conversation: String) throws -> String? {
    try synchronized {
      try db.scalar(
        """
        SELECT json_extract(p.payload,'$.reversibleOutcome.sql')
        FROM messages m JOIN message_payloads p ON p.message_id=m.id
        WHERE m.id=? AND m.conversation_id=? AND m.role='assistant' AND m.state='complete'
          AND json_extract(p.payload,'$.tool')='finish'
        """, [.string(messageID), .string(conversation)]
      ).string
    }
  }

  /// Where a sql call's changes stand: "saved" while one Undo can take them all back,
  /// "undone" after that, "fixed" once a later change built on them. Nil if it saved nothing.
  public func chatSQLState(_ token: String) throws -> String? {
    try synchronized {
      let steps = try chatSQLSteps(token)
      if steps.isEmpty { return nil }
      if try db.scalar(
        "SELECT count(*) FROM operations WHERE id>=? AND id<?",
        [.string(token + "~undo-"), .string(token + "~undo.")]
      ).int ?? 0 > 0 {
        return "undone"
      }
      for step in steps {
        guard let table = try? dataset(step.tableID) else { return "fixed" }
        switch step.kind {
        case .created: if table.archived { return "fixed" }
        case .shape: if table.definitionID != step.after { return "fixed" }
        case .rows:
          if table.archived { return "fixed" }
          let access = try NativeAppAccess(
            workbook: self, table: table, requestSourceID: nil, cancellation: .init())
          defer { access.revoke() }
          guard let now = try nativeAppReversal(access, original: step.operation), !now.redo
          else { return "fixed" }
        }
      }
      return "saved"
    }
  }

  /// One Undo for everything a sql call saved: rows, new tables and table shapes.
  /// The person's Undo passes their actor; a model's undo keeps the rule Source it needs.
  public func chatSQLUndo(
    _ token: String, actor: ChangeActor? = nil, cancellation: Cancellation = .init()
  ) throws -> Value {
    try ChangeAttribution.$actor.withValue(actor ?? ChangeAttribution.actor) {
      try chatSQLUndoAttributed(token, cancellation: cancellation)
    }
  }

  private func chatSQLUndoAttributed(_ token: String, cancellation: Cancellation) throws -> Value {
    try synchronized(cancellation: cancellation) {
      let state = try chatSQLState(token)
      try require(state != nil, "sql_undo", "No saved change has that undo value.")
      try require(state != "undone", "sql_undo", "That change is already undone.")
      try require(
        state == "saved", "sql_undo",
        "A later change built on that one. Undo the later change first.")
      let steps = try chatSQLSteps(token)
      try withChatChangeActor(needed: true, cancellation: cancellation) {
        try undoChatSQLSteps(steps, token: token + "~undo", cancellation: cancellation)
      }
      return .object([
        "undone": .bool(true),
        "tables": .array(
          try Set(steps.map(\.tableID)).sorted().map { .string(try dataset($0).title) }),
      ])
    }
  }

  func undoChatSQLSteps(_ steps: [SQLStep], token: String, cancellation: Cancellation) throws {
    for (index, step) in steps.enumerated().reversed() {
      let table = try dataset(step.tableID)
      let own = token + "-\(index)"
      switch step.kind {
      case .rows:
        try chatTableTransaction(
          table.id, expectedDefinitionID: table.definitionID, operations: [],
          undo: step.operation, token: own, cancellation: cancellation)
      case .shape:
        try restoreDatasetDefinition(
          table.id, definitionID: step.before!, expectedVersion: table.version,
          expectedDefinitionID: table.definitionID, token: own, cancellation: cancellation)
      case .created:
        try updateDatasetDefinition(
          table.id, expectedVersion: table.version, expectedDefinitionID: table.definitionID,
          archived: true, token: own, cancellation: cancellation)
      }
    }
  }
}

/// The copies one sql call, or one script, works on. Each statement is rehearsed on empty
/// tables first, which finds mistakes and the tables to copy in before it runs.
final class ChatSQLSession {
  let scratch: SQLScratch
  private let rehearsal: SQLScratch
  private let workbook: Workbook
  private let cancellation: Cancellation
  private var filled = Set<String>()
  private var ledgerFilled = false

  init(
    _ workbook: Workbook, readOnly: Bool, draft: Bool = false, inputs: [String: Value]? = nil,
    cancellation: Cancellation
  ) throws {
    self.workbook = workbook
    self.cancellation = cancellation
    let tables = try workbook.datasets()
    let ledger = try workbook.hasStockLedger()
    rehearsal = try SQLScratch(
      tables: tables, ledger: ledger, readOnly: readOnly, draft: draft, inputs: inputs,
      cancellation: cancellation)
    do {
      scratch = try SQLScratch(
        tables: tables, ledger: ledger, readOnly: readOnly, draft: draft, inputs: inputs,
        cancellation: cancellation)
    } catch {
      rehearsal.close()
      throw error
    }
  }

  func run(_ statements: [String], inputs: [String: Value]? = nil) throws -> [Value] {
    if let inputs {
      rehearsal.inputs = inputs
      scratch.inputs = inputs
    }
    let named = try rehearsal.rehearse(statements).subtracting(filled)
    let workbook = workbook
    let cancellation = cancellation
    try scratch.fill(named) { table in
      var loaded: [(String, [String: Value])] = []
      while true {
        let page = try workbook.rows(table.id, offset: loaded.count, limit: 200)
        loaded += page.map { ($0.id, workbook.calculatedValues($0, columns: table.columns)) }
        if page.count < 200 { return loaded }
        try cancellation.check()
      }
    }
    filled.formUnion(named)
    if rehearsal.ledgerRead, !ledgerFilled {
      try scratch.fillLedger(workbook.stockBalances())
      ledgerFilled = true
    }
    return try scratch.run(statements)
  }

  func close() {
    rehearsal.close()
    scratch.close()
  }
}

final class SQLScratch {
  /// Changed rows of one table in one call. Measured on the test Mac: see the plan.
  static let changeLimit = 5_000
  static let applySeconds: TimeInterval = 60
  static let namedRowLimit = 24
  static let rowLimit = 20_000
  static let createdRowLimit = 5_000
  static let shownRows = 50
  static let shownBytes = 9_000
  private static let log = "_sevra_log"
  /// The stock ledger as two read-only tables, present when the ledger holds a basis.
  static let ledger: Set<String> = ["stock", "stock_movements"]
  static let ledgerListing =
    "stock(subject TEXT, quantity REAL, opening REAL, opening_date TEXT) read-only, the current stock of each inventory item; stock_movements(subject TEXT, quantity REAL, effective TEXT) read-only, the movements counted in it"
  private static let reserved: Set<String> = ["tables", "columns", log]
  private static let shapeRefusal =
    "sql can create, alter and drop tables. It cannot make indexes, views, triggers or temporary tables. Use WITH for intermediate results."
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  struct Change {
    let key: String
    let name: String
    let table: Dataset
    let operations: [Value]
    let inserted: Int
    let updated: Int
    let deleted: Int
  }
  struct Reshape {
    let key: String
    let name: String
    let table: Dataset
    let title: String?
    let columns: [Column]?
    let archived: Bool
    let notes: [String]
  }
  struct Created {
    let name: String
    let title: String
    let columns: [Column]
    let rows: [[String: Value]]
  }
  private enum Shape { case create, alter, drop }
  private struct Field {
    var name: String
    var column: Column
    var added = false
  }
  /// One workbook table. `key` is its name when the call began, which the change log keeps.
  private struct Entry {
    let key: String
    var name: String
    let dataset: Dataset
    var fields: [Field]
    var rows: [Int64: String] = [:]
    var loaded: [Int64: [String: Value]] = [:]
    var title: String?
    var dropped = false
    var reshaped = false
    var notes: [String] = []
  }
  private struct Layout {
    let actual: String
    let columns: [(name: String, type: String)]
  }

  private var handle: OpaquePointer?
  private var entries: [String: Entry] = [:]
  private var order: [String] = []
  /// Current lower-case table name to the entry it belongs to.
  private var current: [String: String] = [:]
  /// Lower-case names of tables this call created.
  private var created = Set<String>()
  private let readOnly: Bool
  private let draft: Bool
  /// Values for `:name` parameters. Plain sql calls have none, so a parameter is a mistake.
  var inputs: [String: Value]?
  /// What one result may show. A script reads more rows than a model is shown.
  var shownRows = SQLScratch.shownRows
  var shownBytes = SQLScratch.shownBytes
  /// A script gets numbers as numbers. A model is shown them as exact decimal text.
  var numbers = false
  private let hasLedger: Bool
  /// Whether a statement has read the stock tables, and the Sources their figures rest on.
  private(set) var ledgerRead = false
  private(set) var ledgerSources: [String] = []
  private var filledRows = 0
  private let cancellation: Cancellation
  private var guarded = false
  private var shaping: Shape?
  private var read = Set<String>()
  private var written = Set<String>()
  private var refusal: SevraError?
  private var deadline = Date.distantFuture
  private var shown = 0

  var readTables: [String] { order.filter(read.contains) }
  func table(_ key: String) -> Dataset { entries[key]!.dataset }
  func rowIDs(_ key: String) -> [String] {
    entries[key]!.rows.sorted { $0.key < $1.key }.map(\.value)
  }

  init(
    tables: [Dataset], ledger: Bool, readOnly: Bool, draft: Bool,
    inputs: [String: Value]? = nil, cancellation: Cancellation
  ) throws {
    hasLedger = ledger
    self.readOnly = readOnly
    self.draft = draft
    self.inputs = inputs
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
    guard sevra_strict_quotes(handle) == SQLITE_OK else {
      close()
      throw SevraError("sql", "The query workspace could not be opened.")
    }
    try execute("PRAGMA trusted_schema=OFF")
    try execute("PRAGMA recursive_triggers=ON")
    // 4 KiB pages: 128 MiB for the copy and everything a statement builds.
    try execute("PRAGMA max_page_count=32768")
    try execute(
      "CREATE TABLE tables(name TEXT, title TEXT, row_count INTEGER, id TEXT, version INTEGER, definition_id TEXT)")
    try execute(
      "CREATE TABLE columns(table_name TEXT, name TEXT, title TEXT, type TEXT, formula TEXT, id TEXT)")
    try execute("CREATE TABLE \"\(Self.log)\"(tbl TEXT, id INTEGER)")
    if ledger {
      try execute("CREATE TABLE stock(subject TEXT, quantity REAL, opening REAL, opening_date TEXT)")
      try execute("CREATE TABLE stock_movements(subject TEXT, quantity REAL, effective TEXT)")
    }
    for (name, dataset, columns) in Self.named(tables, ledger: ledger) {
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
          "INSERT INTO columns VALUES(?,?,?,?,?,?)",
          [
            .string(name), .string(entry.name), .string(entry.column.title),
            .string(entry.column.formula == nil ? entry.column.type : "formula"),
            entry.column.formula.map(Value.string) ?? .null, .string(entry.column.id),
          ])
      }
      entries[name] = Entry(
        key: name, name: name, dataset: dataset,
        fields: columns.map { Field(name: $0.name, column: $0.column) })
      current[name] = name
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
  static func named(_ tables: [Dataset], ledger: Bool) -> [(
    name: String, dataset: Dataset, columns: [(name: String, column: Column)]
  )] {
    var taken = ledger ? reserved.union(Self.ledger) : reserved
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
  /// A title for a name the model typed: `price_each` reads as "Price each". A name typed
  /// with capitals or spaces is already a title.
  private static func title(_ name: String) -> String {
    let spaced = name.replacingOccurrences(of: "_", with: " ").trimmingCharacters(
      in: .whitespaces)
    guard spaced == spaced.lowercased(), let first = spaced.first else { return spaced }
    return first.uppercased() + spaced.dropFirst()
  }
  private static func numeric(_ type: String) -> Bool {
    let type = type.uppercased()
    return ["INT", "REAL", "NUM", "DEC", "FLOA", "DOUB", "MONEY"].contains { type.contains($0) }
  }
  /// CREATE TABLE, ALTER TABLE or DROP TABLE, from the statement's first words.
  private static func shape(_ sql: String) -> Shape? {
    var text = Substring(sql)
    while true {
      text = text.drop { $0.isWhitespace }
      if text.hasPrefix("--") {
        text = text.drop { $0 != "\n" }
      } else if text.hasPrefix("/*"), let end = text.range(of: "*/") {
        text = text[end.upperBound...]
      } else {
        break
      }
    }
    let words = text.prefix(40).uppercased().split { $0.isWhitespace }.prefix(2).joined(
      separator: " ")
    switch words {
    case "CREATE TABLE": return .create
    case "ALTER TABLE": return .alter
    case "DROP TABLE": return .drop
    default: return nil
    }
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
    func forbidden() -> Int32? {
      if readOnly {
        return refuse(
          "read_only_request", "The current request forbids changes. Read with SELECT and answer.")
      }
      return nil
    }
    func ownTable(_ name: String) -> Bool { current[name] != nil || created.contains(name) }
    let name = (first ?? "").lowercased()
    let schemaTable = name.hasPrefix("sqlite_")
    switch action {
    case SQLITE_SELECT, SQLITE_RECURSIVE: return SQLITE_OK
    case SQLITE_FUNCTION:
      return ["load_extension", "readfile", "writefile", "edit"].contains(
        (second ?? "").lowercased())
        ? refuse("sql", "That function is not available.") : SQLITE_OK
    case SQLITE_READ:
      if schemaTable, shaping != nil { return SQLITE_OK }
      if name == Self.log || schemaTable {
        return inTrigger
          ? SQLITE_OK
          : refuse("sql", "Use SELECT * FROM columns to see the tables and their columns.")
      }
      if let key = current[name] { read.insert(key) }
      if hasLedger, Self.ledger.contains(name) { ledgerRead = true }
      return SQLITE_OK
    case SQLITE_INSERT, SQLITE_UPDATE, SQLITE_DELETE:
      if name == Self.log, inTrigger { return SQLITE_OK }
      if schemaTable {
        // Creating, dropping or altering a table writes the schema table.
        return shaping != nil ? SQLITE_OK : refuse("sql_shape", Self.shapeRefusal)
      }
      if created.contains(name) { return forbidden() ?? SQLITE_OK }
      guard let key = current[name], let entry = entries[key] else {
        return refuse("sql", "The tables and columns lists are read-only.")
      }
      if let refused = forbidden() { return refused }
      if action == SQLITE_UPDATE, shaping == nil,
        let field = entry.fields.first(where: { $0.name.lowercased() == (second ?? "").lowercased() }),
        field.column.formula != nil
      {
        return refuse(
          "sql", "\(field.name) is a formula column. Change the columns it is calculated from.")
      }
      if shaping == nil { written.insert(key) }
      return SQLITE_OK
    case SQLITE_CREATE_TABLE:
      if let refused = forbidden() { return refused }
      return shaping == .create && !name.hasPrefix("_sevra") && !schemaTable
        ? SQLITE_OK : refuse("sql_shape", Self.shapeRefusal)
    case SQLITE_ALTER_TABLE:
      if let refused = forbidden() { return refused }
      return shaping == .alter && ownTable((second ?? "").lowercased())
        ? SQLITE_OK : refuse("sql", "The tables and columns lists are read-only.")
    case SQLITE_DROP_TABLE:
      if let refused = forbidden() { return refused }
      return shaping == .drop && ownTable(name)
        ? SQLITE_OK : refuse("sql", "The tables and columns lists are read-only.")
    case SQLITE_DROP_TRIGGER:
      // Dropping a table drops the host's own triggers on it.
      return shaping == .drop && name.hasPrefix("_sevra_")
        ? SQLITE_OK : refuse("sql_shape", Self.shapeRefusal)
    case SQLITE_TRANSACTION, SQLITE_SAVEPOINT:
      return refuse(
        "sql",
        "One sql call is one change, saved together. Remove BEGIN, COMMIT, ROLLBACK and SAVEPOINT.")
    case SQLITE_CREATE_TEMP_TABLE, SQLITE_DROP_TEMP_TABLE, SQLITE_CREATE_INDEX,
      SQLITE_CREATE_TEMP_INDEX, SQLITE_DROP_INDEX, SQLITE_DROP_TEMP_INDEX, SQLITE_CREATE_VIEW,
      SQLITE_CREATE_TEMP_VIEW, SQLITE_DROP_VIEW, SQLITE_DROP_TEMP_VIEW, SQLITE_CREATE_TRIGGER,
      SQLITE_CREATE_TEMP_TRIGGER, SQLITE_DROP_TEMP_TRIGGER, SQLITE_CREATE_VTABLE, SQLITE_DROP_VTABLE:
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
        + (message.contains("no such column")
          ? ". Use the exact names under Tables for sql, and write text values in single quotes."
          : ". SELECT * FROM columns lists every table and column name."))
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
    case SQLITE_INTEGER:
      let whole = sqlite3_column_int64(statement, index)
      return numbers ? .number(Double(whole)) : .string(String(whole))
    case SQLITE_FLOAT:
      let number = sqlite3_column_double(statement, index)
      let text = Self.decimalText(number) ?? String(number)
      return numbers ? .number(Double(text) ?? number) : .string(text)
    case SQLITE_TEXT: return .string(String(cString: sqlite3_column_text(statement, index)))
    default: return .string("(binary)")
    }
  }

  /// Every table of the copy that is not the host's, with its columns as SQLite declares them.
  private func layouts() throws -> [String: Layout] {
    var names: [String] = []
    let list = try prepare("SELECT name FROM sqlite_master WHERE type='table'")
    defer { sqlite3_finalize(list) }
    while sqlite3_step(list) == SQLITE_ROW {
      let name = String(cString: sqlite3_column_text(list, 0))
      if !Self.reserved.contains(name.lowercased()), !name.lowercased().hasPrefix("sqlite_"),
        !(hasLedger && Self.ledger.contains(name.lowercased()))
      {
        names.append(name)
      }
    }
    var found: [String: Layout] = [:]
    for name in names {
      let info = try prepare(
        "PRAGMA table_info(\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\")")
      defer { sqlite3_finalize(info) }
      var columns: [(name: String, type: String)] = []
      while sqlite3_step(info) == SQLITE_ROW {
        columns.append(
          (
            String(cString: sqlite3_column_text(info, 1)),
            sqlite3_column_text(info, 2).map { String(cString: $0) } ?? ""
          ))
      }
      found[name.lowercased()] = Layout(actual: name, columns: columns)
    }
    return found
  }

  /// One text of several statements, cut where SQLite itself says a statement ends.
  static func split(_ text: String) -> [String] {
    var statements: [String] = []
    var current = ""
    for character in text {
      current.append(character)
      if character == ";", sqlite3_complete(current) != 0 {
        statements.append(current)
        current = ""
      }
    }
    statements.append(current)
    return statements.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
      !$0.trimmingCharacters(in: CharacterSet(charactersIn: "; \n\t")).isEmpty
    }
  }

  private static func quoted(_ name: String) -> String {
    "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }

  /// Runs the statements on the empty tables. Mistakes surface before any row is copied,
  /// and the result is the set of workbook tables the statements name.
  func rehearse(_ statements: [String]) throws -> Set<String> {
    _ = try run(statements)
    return read.union(written).union(entries.values.filter { $0.reshaped || $0.dropped }.map(\.key))
  }

  /// Copies in the named tables, then starts recording row changes.
  func fill(_ named: Set<String>, _ load: (Dataset) throws -> [(String, [String: Value])]) throws {
    for key in order where named.contains(key) {
      var entry = entries[key]!
      let rows = try load(entry.dataset)
      filledRows += rows.count
      try require(
        filledRows <= Self.rowLimit, "sql_limit",
        "These tables hold more than \(Self.rowLimit) rows, which sql cannot read yet.")
      let insert = try prepare(
        "INSERT INTO \"\(key)\"(rowid,"
          + entry.fields.map { "\"\($0.name)\"" }.joined(separator: ",") + ") VALUES(?"
          + String(repeating: ",?", count: entry.fields.count) + ")")
      defer { sqlite3_finalize(insert) }
      for (offset, row) in rows.enumerated() {
        let id = Int64(offset + 1)
        sqlite3_reset(insert)
        sqlite3_bind_int64(insert, 1, id)
        for (index, field) in entry.fields.enumerated() {
          let value = row.1[field.column.id] ?? .null
          let numeric = field.column.type == "decimal" || field.column.formula != nil
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
      let select = try prepare("SELECT rowid,* FROM \"\(key)\"")
      defer { sqlite3_finalize(select) }
      while sqlite3_step(select) == SQLITE_ROW {
        var values: [String: Value] = [:]
        for (index, field) in entry.fields.enumerated() {
          values[field.column.id] = cell(select, Int32(index + 1))
        }
        entry.loaded[sqlite3_column_int64(select, 0)] = values
      }
      entries[key] = entry
      for (kind, event, rows) in [
        ("i", "INSERT", ["NEW"]), ("u", "UPDATE", ["OLD", "NEW"]), ("d", "DELETE", ["OLD"]),
      ] {
        try execute(
          "CREATE TRIGGER \"_sevra_\(kind)_\(key)\" AFTER \(event) ON \"\(key)\" BEGIN "
            + rows.map { "INSERT INTO \"\(Self.log)\" VALUES('\(key)',\($0).rowid);" }.joined()
            + " END")
      }
    }
  }

  /// Copies in the stock ledger: one row per item with a basis, and the movements counted.
  func fillLedger(_ balances: [Value]) throws {
    for balance in balances {
      try execute(
        "INSERT INTO stock VALUES(?,?,?,?)",
        [
          balance["subject"], .number(Double(balance["quantity"].text) ?? 0),
          .number(Double(balance["openingQuantity"].text) ?? 0),
          .string(String(balance["openingEffective"].text.prefix(10))),
        ])
      ledgerSources.append(balance["basis"].text)
      for effect in balance["effects"].array {
        try execute(
          "INSERT INTO stock_movements VALUES(?,?,?)",
          [
            balance["subject"], .number(Double(effect["quantity"].text) ?? 0),
            .string(String(effect["effective"].text.prefix(10))),
          ])
        ledgerSources.append(effect["item_id"].text)
      }
    }
  }

  func run(_ statements: [String]) throws -> [Value] {
    deadline = Date().addingTimeInterval(3)
    defer {
      guarded = false
      shaping = nil
      deadline = .distantFuture
    }
    var results: [Value] = []
    for (index, sql) in statements.enumerated() {
      let shape = Self.shape(sql)
      try require(
        shape == nil || !draft, "sql_draft",
        "A draft can hold UPDATEs only for now. Nothing was changed or saved.")
      let before = try shape.map { _ in try layouts() }
      guarded = true
      shaping = shape
      let result = try step(sql, index: index)
      guarded = false
      shaping = nil
      if let shape, let before { try reshaped(shape, from: before, to: try layouts()) }
      results.append(result)
    }
    return results
  }

  private func step(_ sql: String, index: Int) throws -> Value {
    guard let statement = try prepare(sql, index: index) else {
      return .object(["changedRows": .number(0)])
    }
    defer { sqlite3_finalize(statement) }
    let parameters = sqlite3_bind_parameter_count(statement)
    if parameters > 0 {
      for position in 1...parameters {
        let name = sqlite3_bind_parameter_name(statement, position).map {
          String(String(cString: $0).dropFirst())
        }
        guard let inputs, let name, let value = inputs[name] else {
          throw SevraError(
            "sql",
            inputs == nil
              ? "Write values into the statement. Only a saved tool's statements take :name inputs."
              : "Statement \(index + 1) uses an input the tool does not declare"
                + (name.map { ": " + $0 } ?? "") + ". Write each input as :name.")
        }
        bind(statement, position, value)
      }
    }
    let count = sqlite3_column_count(statement)
    var rows: [Value] = []
    var total = 0
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { break }
      guard code == SQLITE_ROW else { throw failure(index) }
      total += 1
      guard rows.count < shownRows, shown < shownBytes else { continue }
      let row = Value.array((0..<count).map { cell(statement, $0) })
      shown += (try? row.json().utf8.count) ?? 0
      rows.append(row)
    }
    if count == 0 {
      return shaping != nil
        ? .object(["done": .bool(true)])
        : .object(["changedRows": .number(Double(sqlite3_changes(handle)))])
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
    return .object(fields)
  }

  // MARK: Shape changes

  /// Reads what one CREATE, ALTER or DROP TABLE did from the copy's layout before and after.
  private func reshaped(_ shape: Shape, from before: [String: Layout], to after: [String: Layout])
    throws
  {
    let gone = Set(before.keys).subtracting(after.keys)
    let fresh = Set(after.keys).subtracting(before.keys)
    switch shape {
    case .create:
      created.formUnion(fresh)
    case .drop:
      for name in gone {
        if let key = current.removeValue(forKey: name) {
          entries[key]!.dropped = true
          entries[key]!.notes.append("archived the table")
        } else {
          created.remove(name)
        }
      }
    case .alter:
      if gone.count == 1, fresh.count == 1, let old = gone.first, let new = fresh.first {
        if let key = current.removeValue(forKey: old) {
          current[new] = key
          entries[key]!.name = after[new]!.actual
          entries[key]!.title = Self.title(after[new]!.actual)
          entries[key]!.reshaped = true
          entries[key]!.notes.append("renamed the table to " + Self.title(after[new]!.actual))
        } else {
          created.remove(old)
          created.insert(new)
        }
        return
      }
      for (name, layout) in after {
        guard let key = current[name], var entry = entries[key], let earlier = before[name] else {
          continue
        }
        let old = earlier.columns.map(\.name)
        let now = layout.columns.map(\.name)
        guard old != now else { continue }
        let removed = old.filter { !now.contains($0) }
        let added = layout.columns.filter { !old.contains($0.name) }
        if removed.count == 1, added.count == 1, old.count == now.count,
          let index = entry.fields.firstIndex(where: { $0.name == removed[0] })
        {
          let title = Self.title(added[0].name)
          entry.notes.append("renamed column \(entry.fields[index].column.title) to \(title)")
          entry.fields[index].name = added[0].name
          entry.fields[index].column.title = title
        } else {
          for name in removed {
            if let field = entry.fields.first(where: { $0.name == name }) {
              entry.notes.append("removed column " + field.column.title)
            }
          }
          entry.fields.removeAll { removed.contains($0.name) }
          var ids = Set(entry.dataset.columns.map { $0.id.lowercased() }).union(
            entry.fields.map { $0.column.id.lowercased() })
          for column in added {
            let id = Self.unique(Self.identifier(column.name, fallback: "column"), in: &ids)
            let title = Self.title(column.name)
            entry.fields.append(
              Field(
                name: column.name,
                column: Column(
                  id: id, title: title, type: Self.numeric(column.type) ? "decimal" : "text"),
                added: true))
            entry.notes.append("added column " + title)
          }
          entry.fields.sort {
            (now.firstIndex(of: $0.name) ?? 0) < (now.firstIndex(of: $1.name) ?? 0)
          }
        }
        entry.reshaped = true
        entries[key] = entry
      }
    }
  }

  /// The definition change each reshaped workbook table needs.
  func reshapes() throws -> [Reshape] {
    order.compactMap { key in
      let entry = entries[key]!
      guard entry.reshaped || entry.dropped else { return nil }
      let columns = entry.fields.map(\.column)
      return Reshape(
        key: key, name: entry.name, table: entry.dataset, title: entry.dropped ? nil : entry.title,
        columns: entry.dropped || columns == entry.dataset.columns ? nil : columns,
        archived: entry.dropped, notes: entry.notes)
    }
  }

  /// The tables this call created, with the rows it put in them.
  func createdTables() throws -> [Created] {
    let layouts = try layouts()
    var tables: [Created] = []
    for name in created.sorted() {
      guard let layout = layouts[name], !layout.columns.isEmpty else { continue }
      let select = try prepare("SELECT * FROM " + Self.quoted(layout.actual))
      defer { sqlite3_finalize(select) }
      var cells: [[Value]] = []
      var numbers = [Bool](repeating: true, count: layout.columns.count)
      var filled = [Bool](repeating: false, count: layout.columns.count)
      while sqlite3_step(select) == SQLITE_ROW {
        try require(
          cells.count < Self.createdRowLimit, "sql_limit",
          "A new table can start with at most \(Self.createdRowLimit) rows for now. Nothing was changed.")
        let row = layout.columns.indices.map { cell(select, Int32($0)) }
        for (index, value) in row.enumerated() where value != .null {
          filled[index] = true
          if (try? Numbers.decimal(value.text)) == nil { numbers[index] = false }
        }
        cells.append(row)
      }
      var ids = Set<String>()
      let columns = layout.columns.enumerated().map { index, column in
        // A declared number column holds numbers. An undeclared one does if every value is one.
        let decimal =
          numbers[index] && (Self.numeric(column.type) || (column.type.isEmpty && filled[index]))
        return Column(
          id: Self.unique(Self.identifier(column.name, fallback: "column"), in: &ids),
          title: Self.title(column.name), type: decimal ? "decimal" : "text")
      }
      tables.append(
        Created(
          name: layout.actual, title: Self.title(layout.actual), columns: columns,
          rows: cells.map { row in
            var values: [String: Value] = [:]
            for (index, value) in row.enumerated() where value != .null {
              values[columns[index].id] = value
            }
            return values
          }))
    }
    return tables
  }

  // MARK: Row changes

  /// The net effect on each table's rows, as operations the recorded row transaction takes.
  func changes() throws -> [Change] {
    var found: [Change] = []
    for key in order {
      let entry = entries[key]!
      let widened = entry.fields.contains { $0.added }
      guard !entry.dropped, written.contains(key) || widened else { continue }
      var touched: [Int64] = []
      if widened {
        // A new column can be filled by its default, which no trigger sees.
        touched = Array(entry.rows.keys)
      }
      let ids = try prepare("SELECT DISTINCT id FROM \"\(Self.log)\" WHERE tbl=?")
      defer { sqlite3_finalize(ids) }
      sqlite3_bind_text(ids, 1, key, -1, Self.transient)
      while sqlite3_step(ids) == SQLITE_ROW { touched.append(sqlite3_column_int64(ids, 0)) }
      let select = try prepare(
        "SELECT " + entry.fields.map { Self.quoted($0.name) }.joined(separator: ",") + " FROM "
          + Self.quoted(entry.name) + " WHERE rowid=?")
      defer { sqlite3_finalize(select) }
      var operations: [Value] = []
      var counts = (inserted: 0, updated: 0, deleted: 0)
      for id in Set(touched).sorted() {
        sqlite3_reset(select)
        sqlite3_bind_int64(select, 1, id)
        let now =
          sqlite3_step(select) == SQLITE_ROW
          ? entry.fields.indices.map { cell(select, Int32($0)) } : nil
        let before = entry.loaded[id]
        func stored(_ index: Int) throws -> Value {
          let field = entry.fields[index]
          let value = now![index]
          guard value != .null, field.column.type == "decimal" else { return value }
          guard (try? Numbers.decimal(value.text)) != nil else {
            throw SevraError(
              "sql_value",
              "\(field.name) holds numbers, and \"\(value.text.prefix(40))\" is not one. Nothing was changed.")
          }
          return value
        }
        let writable = entry.fields.indices.filter { entry.fields[$0].column.formula == nil }
        switch (before, now) {
        case (.some(let before), .some(let now)):
          let changed = writable.filter {
            (before[entry.fields[$0].column.id] ?? .null) != now[$0]
          }
          guard !changed.isEmpty else { continue }
          var values: [String: Value] = [:]
          for index in changed { values[entry.fields[index].column.id] = try stored(index) }
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
            values[entry.fields[index].column.id] = try stored(index)
          }
          operations.append(.object(["op": .string("insert"), "values": .object(values)]))
          counts.inserted += 1
        case (.none, .none): continue
        }
      }
      if !operations.isEmpty {
        found.append(
          Change(
            key: key, name: entry.name, table: entry.dataset, operations: operations,
            inserted: counts.inserted, updated: counts.updated, deleted: counts.deleted))
      }
    }
    return found
  }
}
