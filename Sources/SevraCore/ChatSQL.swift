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
    requestSourceID: String?, inputs: [String: Value]? = nil, confirmLarge: Bool = false,
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
        requestSourceID: requestSourceID, confirmLarge: confirmLarge, cancellation: cancellation)
    }
  }

  /// Applies what the statements did on the copy through the recorded write paths.
  func saveChatSQL(
    _ scratch: SQLScratch, results: [Value], draft: Bool, token: String,
    requestSourceID: String?, confirmLarge: Bool = false, cancellation: Cancellation
  ) throws -> Value {
    try synchronized(cancellation: cancellation) {
      let reshapes = try scratch.reshapes()
      let created = try scratch.createdTables()
      let changes = try scratch.changes()
      try require(
        changes.allSatisfy { $0.operations.count <= SQLScratch.changeLimit }, "sql_limit",
        "One call can change at most \(SQLScratch.changeLimit) rows of a table for now. Nothing was changed. Split the change.")
      // A change that empties or removes a table, or reaches most of its rows, waits for the
      // person. Nothing is saved, and the host asks them with this preview.
      if confirmLarge, !draft,
        let preview = Self.largeChangePreview(
          changes.map { ($0.table.title, $0.table.rowCount, $0.deleted, $0.updated) }
            + reshapes.filter(\.archived).map { ($0.table.title, $0.table.rowCount, -1, 0) })
      {
        return .object([
          "status": .string("confirmation_required"), "preview": .string(preview),
          "notice": .string(
            "Nothing was changed. This change waits for the user's confirmation, which the host asks for."),
        ])
      }
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
      var inputs: [String] = []
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
  /// Whether a change to one table needs the person's confirmation before it is saved. Every
  /// change keeps an Undo, so this asks only where a misread request costs the most: emptying
  /// a table of two or more rows, or deleting or overwriting more than 20 rows, or more than
  /// half of a table of more than five. A small table's change is listed in full in the reply
  /// and taken back with one Undo, so it applies at once. A deleted count of -1 is the table
  /// itself removed, which asks whenever the table has rows.
  public static func needsConfirmation(rows: Int, deleted: Int, updated: Int) -> Bool {
    if deleted < 0 { return rows > 0 }
    let changed = deleted + updated
    if deleted > 0 && deleted >= rows && rows >= 2 { return true }
    return changed > 20 || (rows > 5 && changed * 2 > rows)
  }

  /// What a sql call, script or saved tool changed, in words for the person, one sentence a
  /// change, tables named by their titles. Empty when it changed no table.
  public static func tableChangeSummary(_ result: Value) -> [String] {
    func rows(_ n: Int) -> String { n == 1 ? "1 row" : "\(n) rows" }
    func named(_ entry: Value) -> String {
      "“" + (entry["title"].string ?? entry["table"].text) + "”"
    }
    var lines: [String] = []
    for shape in result["shape"].array {
      let rowsMade = shape["rows"].int ?? 0
      switch shape["change"].text {
      case "created":
        lines.append(
          "Created table " + named(shape) + (rowsMade > 0 ? " with " + rows(rowsMade) : "") + ".")
      case "archived": lines.append("Removed table " + named(shape) + ".")
      case "reshaped": lines.append("Changed the columns of " + named(shape) + ".")
      default: break
      }
    }
    for change in result["changes"].array {
      if let n = change["inserted"].int, n > 0 {
        lines.append("Added " + rows(n) + " to " + named(change) + ".")
      }
      if let n = change["updated"].int, n > 0 {
        lines.append("Updated " + rows(n) + " in " + named(change) + ".")
      }
      if let n = change["deleted"].int, n > 0 {
        lines.append("Deleted " + rows(n) + " from " + named(change) + ".")
      }
    }
    return lines
  }

  /// What the person is asked to confirm, one sentence a table, or nil when nothing needs it.
  public static func largeChangePreview(
    _ tables: [(title: String, rows: Int, deleted: Int, updated: Int)]
  ) -> String? {
    func rows(_ n: Int) -> String { n == 1 ? "1 row" : "\(n) rows" }
    let lines = tables.filter {
      needsConfirmation(rows: $0.rows, deleted: $0.deleted, updated: $0.updated)
    }.map { table -> String in
      let title = "“" + table.title + "”"
      if table.deleted < 0 {
        return "This removes the table " + title + " and its " + rows(table.rows) + "."
      }
      var parts: [String] = []
      if table.deleted > 0 {
        parts.append(
          table.deleted >= table.rows
            ? "deletes all " + rows(table.rows) + " of " + title
            : "deletes \(table.deleted) of the " + rows(table.rows) + " of " + title)
      }
      if table.updated > 0 {
        parts.append(
          table.deleted > 0
            ? "changes " + rows(table.updated)
            : "changes \(table.updated) of the " + rows(table.rows) + " of " + title)
      }
      return "This " + parts.joined(separator: " and ") + "."
    }
    return lines.isEmpty ? nil : lines.joined(separator: " ")
  }

  /// The tables as sql names them, for the request's context, so the model need not look
  /// them up. Long workbooks list what fits and point at the catalog for the rest.
  public func chatSQLTables(byteLimit: Int = 2_400) throws -> String {
    let named = SQLScratch.named(try datasets())
    var lines: [String] = []
    var bytes = 0
    for entry in named {
      let line =
        entry.name + "("
        + entry.columns.map { SQLScratch.declaration($0.name, $0.column) }.joined(separator: ", ")
        + ") \(entry.dataset.rowCount) rows"
      guard bytes + line.utf8.count <= byteLimit else { break }
      bytes += line.utf8.count
      lines.append(line)
    }
    guard !lines.isEmpty else { return "" }
    return "Tables for sql: " + lines.joined(separator: "; ")
      + (lines.count < named.count ? "; \(named.count - lines.count) more in SELECT * FROM tables" : "")
  }

  /// A table by its id, or by its exact sql name or title when one current table has it.
  /// Anything else is refused with the tables listed, so the model can pick the right one.
  public func chatTableID(_ reference: String) throws -> String {
    if let table = try? dataset(reference) { return table.id }
    let named = SQLScratch.named(try datasets())
    let wanted = reference.trimmingCharacters(in: .whitespacesAndNewlines)
    var matches = named.filter { $0.name == wanted }
    if matches.isEmpty { matches = named.filter { $0.dataset.title == wanted } }
    if matches.isEmpty {
      matches = named.filter {
        $0.name == wanted.lowercased() || $0.dataset.title.lowercased() == wanted.lowercased()
      }
    }
    if matches.count == 1 { return matches[0].dataset.id }
    let listed = named.prefix(12).map { "\($0.dataset.title) (\($0.name), \($0.dataset.id))" }
    throw SevraError(
      "unknown_table",
      (matches.isEmpty ? "No table has the id or name \(reference)." : "More than one table is named \(reference).")
        + (named.isEmpty
          ? " The workbook has no tables yet. Create one with sql first."
          : " Use a table's id. Tables, as title (sql name, id): " + listed.joined(separator: "; ")
            + (named.count > listed.count ? "; more in SELECT title, name, id FROM tables." : "."))
    )
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

  /// The token of the sql call a chat answer saved changes with, when it was the only one, or
  /// of the change the person confirmed in chat.
  public func conversationSQLReceipt(_ messageID: String, conversation: String) throws -> String? {
    try synchronized {
      try db.scalar(
        """
        SELECT CASE WHEN m.role='assistant' THEN json_extract(p.payload,'$.reversibleOutcome.sql')
          WHEN json_type(p.payload,'$.result.undo')='text' THEN json_extract(p.payload,'$.result.undo')
          END
        FROM messages m JOIN message_payloads p ON p.message_id=m.id
        WHERE m.id=? AND m.conversation_id=? AND m.state='complete'
          AND ((m.role='assistant' AND json_extract(p.payload,'$.tool')='finish')
            OR (m.role='event' AND json_extract(p.payload,'$.kind')='chat_approval_result'))
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

  /// `now` is the one time the call's date functions and defaults read.
  init(
    _ workbook: Workbook, readOnly: Bool, draft: Bool = false, inputs: [String: Value]? = nil,
    now: Date = Date(), cancellation: Cancellation
  ) throws {
    self.workbook = workbook
    self.cancellation = cancellation
    let tables = try workbook.datasets()
    rehearsal = try SQLScratch(
      tables: tables, readOnly: readOnly, draft: draft, inputs: inputs, now: now,
      cancellation: cancellation)
    do {
      scratch = try SQLScratch(
        tables: tables, readOnly: readOnly, draft: draft, inputs: inputs, now: now,
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
    /// A computed column this call added, which SQLite itself computes in the copy.
    var generated = false
    /// A default of the current time added by ALTER TABLE, which the copy cannot hold. The
    /// saved table gives rows added in this call the time.
    var savedDefaultOnly = false
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
  struct Layout {
    let actual: String
    let columns: [LayoutColumn]
    /// The CREATE TABLE text SQLite keeps, with each added column appended.
    let sql: String
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
  private var filledRows = 0
  private let cancellation: Cancellation
  private var guarded = false
  private var shaping: Shape?
  private var read = Set<String>()
  private var written = Set<String>()
  private var refusal: SevraError?
  private var deadline = Date.distantFuture
  private var shown = 0
  /// The time 'now' means in this call, in the Mac's time zone, and the copy of SQLite whose
  /// own date functions do the work once 'now' is replaced with it.
  private let clockText: String
  private let clockOffset: String
  private var clockHandle: OpaquePointer?
  private var clocks: [Clock] = []

  var readTables: [String] { order.filter(read.contains) }
  func table(_ key: String) -> Dataset { entries[key]!.dataset }
  func rowIDs(_ key: String) -> [String] {
    entries[key]!.rows.sorted { $0.key < $1.key }.map(\.value)
  }

  init(
    tables: [Dataset], readOnly: Bool, draft: Bool,
    inputs: [String: Value]? = nil, now: Date = Date(), timeZone: TimeZone = .current,
    cancellation: Cancellation
  ) throws {
    self.readOnly = readOnly
    self.draft = draft
    self.inputs = inputs
    self.cancellation = cancellation
    let format = DateFormatter()
    format.calendar = Calendar(identifier: .gregorian)
    format.locale = Locale(identifier: "en_US_POSIX")
    format.timeZone = timeZone
    format.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    clockText = format.string(from: now)
    format.dateFormat = "xxxxx"
    clockOffset = format.string(from: now)
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
    try installClock()
    try execute("PRAGMA trusted_schema=OFF")
    try execute("PRAGMA recursive_triggers=ON")
    // 4 KiB pages: 128 MiB for the copy and everything a statement builds.
    try execute("PRAGMA max_page_count=32768")
    try execute(
      "CREATE TABLE tables(name TEXT, title TEXT, row_count INTEGER, id TEXT, version INTEGER, definition_id TEXT)")
    try execute(
      "CREATE TABLE columns(table_name TEXT, name TEXT, title TEXT, type TEXT, formula TEXT, id TEXT, required INTEGER, is_unique INTEGER, default_value TEXT, auto_number INTEGER)")
    try execute("CREATE TABLE \"\(Self.log)\"(tbl TEXT, id INTEGER)")
    for (name, dataset, columns) in Self.named(tables) {
      // A numbering column is the table's INTEGER PRIMARY KEY here too, and a default is the
      // column's DEFAULT, so later statements and saved tools add rows as SQLite would.
      let numbered = columns.first { $0.column.autoNumber == true }?.column.id
      try execute(
        "CREATE TABLE \"\(name)\"("
          + columns.map {
            "\"\($0.name)\" "
              + ($0.column.id == numbered
                ? "INTEGER PRIMARY KEY"
                : ($0.column.type == "decimal" || $0.column.formula != nil ? "REAL" : "TEXT")
                  + defaultClause($0.column))
          }.joined(separator: ",") + ")")
      try execute(
        "INSERT INTO tables VALUES(?,?,?,?,?,?)",
        [
          .string(name), .string(dataset.title), .number(Double(dataset.rowCount)),
          .string(dataset.id), .number(Double(dataset.version)), .string(dataset.definitionID),
        ])
      for entry in columns {
        try execute(
          "INSERT INTO columns VALUES(?,?,?,?,?,?,?,?,?,?)",
          [
            .string(name), .string(entry.name), .string(entry.column.title),
            .string(entry.column.formula == nil ? entry.column.type : "formula"),
            entry.column.formula.map(Value.string) ?? .null, .string(entry.column.id),
            .number(entry.column.required == true || entry.column.autoNumber == true ? 1 : 0),
            .number(entry.column.distinct ? 1 : 0),
            entry.column.defaultValue.map { .string($0.sql(entry.column.type)) } ?? .null,
            .number(entry.column.autoNumber == true ? 1 : 0),
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
    sqlite3_close_v2(clockHandle)
    clockHandle = nil
  }

  // MARK: The clock

  /// One date function. 'now' in it means the call's local time, the same in every statement.
  final class Clock {
    let name: String
    unowned let scratch: SQLScratch
    init(_ name: String, _ scratch: SQLScratch) {
      self.name = name
      self.scratch = scratch
    }
  }

  /// SQLite's date functions read 'now' as UTC. Here they read the Mac's local time, fixed
  /// for the call: each one replaces 'now' with that time and asks a plain copy of SQLite.
  private func installClock() throws {
    guard sqlite3_open_v2(":memory:", &clockHandle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_MEMORY, nil)
      == SQLITE_OK
    else { throw SevraError("sql", "The query workspace could not be opened.") }
    for name in ["date", "time", "datetime", "julianday", "strftime", "unixepoch"] {
      let clock = Clock(name, self)
      clocks.append(clock)
      guard
        sqlite3_create_function_v2(
          handle, name, -1, SQLITE_UTF8 | SQLITE_INNOCUOUS,
          Unmanaged.passUnretained(clock).toOpaque(),
          { context, count, values in
            guard let context, let pointer = sqlite3_user_data(context) else { return }
            let clock = Unmanaged<Clock>.fromOpaque(pointer).takeUnretainedValue()
            clock.scratch.tell(clock.name, context, Int(count), values)
          }, nil, nil, nil) == SQLITE_OK
      else { throw SevraError("sql", "The query workspace could not be opened.") }
    }
  }

  private func tell(
    _ name: String, _ context: OpaquePointer, _ count: Int,
    _ values: UnsafeMutablePointer<OpaquePointer?>?
  ) {
    let at = name == "strftime" ? 1 : 0
    func text(_ index: Int) -> String? {
      guard let value = values?[index], sqlite3_value_type(value) == SQLITE_TEXT,
        let raw = sqlite3_value_text(value)
      else { return nil }
      return String(cString: raw).trimmingCharacters(in: .whitespaces).lowercased()
    }
    // Each argument is the caller's value, or the call's time in place of 'now'.
    var binds: [(text: String?, source: Int)] = []
    var local = false
    for index in 0..<count {
      if index == at, text(index) == "now" {
        binds.append((clockText, index))
        local = true
      } else if local, index > at, text(index) == "localtime" {
        continue  // The time is local already.
      } else {
        binds.append((nil, index))
      }
    }
    // With no time value the functions mean now.
    if count <= at { binds.append((clockText, -1)) }
    var statement: OpaquePointer?
    let sql = "SELECT \(name)(" + Array(repeating: "?", count: binds.count).joined(separator: ",") + ")"
    guard sqlite3_prepare_v2(clockHandle, sql, -1, &statement, nil) == SQLITE_OK else {
      sqlite3_result_error(context, sqlite3_errmsg(clockHandle), -1)
      return
    }
    defer { sqlite3_finalize(statement) }
    for (position, bind) in binds.enumerated() {
      if let text = bind.text {
        sqlite3_bind_text(statement, Int32(position + 1), text, -1, Self.transient)
      } else {
        sqlite3_bind_value(statement, Int32(position + 1), values?[bind.source])
      }
    }
    if sqlite3_step(statement) == SQLITE_ROW {
      sqlite3_result_value(context, sqlite3_column_value(statement, 0))
    } else {
      sqlite3_result_error(context, sqlite3_errmsg(clockHandle), -1)
    }
  }

  /// A column's default as SQLite declares it in the copy.
  private func defaultClause(_ column: Column) -> String {
    guard let initial = column.defaultValue, column.formula == nil else { return "" }
    switch initial.now {
    case "date"?: return " DEFAULT (date('now'))"
    case "time"?: return " DEFAULT (time('now'))"
    case "datetime"?:
      return column.type == "date"
        ? " DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now')||'\(clockOffset)')"
        : " DEFAULT (datetime('now'))"
    default:
      if column.type == "decimal", let number = try? Numbers.decimal(initial.value ?? "") {
        return " DEFAULT " + Numbers.string(number)
      }
      return " DEFAULT " + initial.sql()
    }
  }

  // MARK: Names

  /// A column as the request's list of tables declares it, with what its table keeps.
  static func declaration(_ name: String, _ column: Column) -> String {
    if column.formula != nil { return name + " REAL GENERATED" }
    if column.autoNumber == true { return name + " INTEGER PRIMARY KEY" }
    return name + (column.type == "decimal" ? " REAL" : " TEXT")
      + (column.required == true ? " NOT NULL" : "") + (column.unique == true ? " UNIQUE" : "")
      + (column.defaultValue.map { " DEFAULT " + $0.sql(column.type) } ?? "")
  }

  /// The name each table and column has in sql: its title in lower case with underscores.
  static func named(_ tables: [Dataset]) -> [(
    name: String, dataset: Dataset, columns: [(name: String, column: Column)]
  )] {
    var taken = reserved
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
    case SQLITE_CREATE_INDEX where name.hasPrefix("sqlite_autoindex_"):
      // SQLite makes this index itself for a UNIQUE column or a key that is not INTEGER. The
      // new table keeps the column unique.
      return shaping == .create ? SQLITE_OK : refuse("sql_shape", Self.shapeRefusal)
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
          : message.contains("cannot drop PRIMARY KEY column")
            ? ". That column numbers the table's rows. To remove it, change the table's columns with the action table.edit_schema."
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
  /// Computed columns are listed too, in their place.
  private func layouts() throws -> [String: Layout] {
    var names: [(String, String)] = []
    let list = try prepare("SELECT name, sql FROM sqlite_master WHERE type='table'")
    defer { sqlite3_finalize(list) }
    while sqlite3_step(list) == SQLITE_ROW {
      let name = String(cString: sqlite3_column_text(list, 0))
      if !Self.reserved.contains(name.lowercased()), !name.lowercased().hasPrefix("sqlite_") {
        names.append((name, sqlite3_column_text(list, 1).map { String(cString: $0) } ?? ""))
      }
    }
    var found: [String: Layout] = [:]
    for (name, sql) in names {
      let info = try prepare("PRAGMA table_xinfo(" + Self.quoted(name) + ")")
      defer { sqlite3_finalize(info) }
      var columns: [LayoutColumn] = []
      func text(_ index: Int32) -> String? {
        sqlite3_column_text(info, index).map { String(cString: $0) }
      }
      while sqlite3_step(info) == SQLITE_ROW {
        columns.append(
          LayoutColumn(
            name: text(1) ?? "", type: text(2) ?? "", notNull: sqlite3_column_int(info, 3) != 0,
            defaultSQL: text(4), key: Int(sqlite3_column_int(info, 5)),
            generated: [2, 3].contains(sqlite3_column_int(info, 6))))
      }
      found[name.lowercased()] = Layout(actual: name, columns: columns, sql: sql)
    }
    return found
  }

  /// What each column of a table asks the workbook to keep, by lower-case name. Constraints
  /// over several columns are refused, since a workbook column keeps its own.
  private func shapes(_ layout: Layout) throws -> [String: ColumnShape] {
    var shapes: [String: ColumnShape] = [:]
    let declarations = Self.declarations(layout.sql)
    let keys = layout.columns.filter { $0.key > 0 }
    try require(
      keys.count <= 1, "sql_shape",
      "\(layout.actual) has a PRIMARY KEY over several columns, which a table cannot keep. Give it one id INTEGER PRIMARY KEY column, or mark a single column UNIQUE. Nothing was changed.")
    var unique = Set<String>()
    let indexes = try prepare("PRAGMA index_list(" + Self.quoted(layout.actual) + ")")
    defer { sqlite3_finalize(indexes) }
    while sqlite3_step(indexes) == SQLITE_ROW {
      let index = String(cString: sqlite3_column_text(indexes, 1))
      let info = try prepare("PRAGMA index_info(" + Self.quoted(index) + ")")
      defer { sqlite3_finalize(info) }
      var named: [String] = []
      while sqlite3_step(info) == SQLITE_ROW {
        named.append(sqlite3_column_text(info, 2).map { String(cString: $0) } ?? "")
      }
      try require(
        named.count == 1, "sql_shape",
        "\(layout.actual) has a UNIQUE or PRIMARY KEY constraint over several columns, which a table cannot keep. Mark single columns UNIQUE instead. Nothing was changed.")
      unique.insert(named[0].lowercased())
    }
    for column in layout.columns {
      var shape = ColumnShape()
      if column.key > 0 {
        // Only a column declared exactly INTEGER is SQLite's row number.
        if column.type.uppercased() == "INTEGER" {
          shape.autoNumber = true
        } else {
          shape.required = true
          shape.unique = true
        }
      }
      if column.notNull, !shape.autoNumber { shape.required = true }
      if unique.contains(column.name.lowercased()), !shape.autoNumber { shape.unique = true }
      if column.generated {
        guard let declaration = declarations[column.name.lowercased()],
          let expression = Self.generatedExpression(declaration)
        else {
          throw SevraError(
            "sql_shape", "\(column.name) is computed in a way sql cannot read. \(Self.computedHelp) Nothing was changed.")
        }
        shape.generated = expression
      } else if let sql = column.defaultSQL {
        shape.initial = try Self.columnDefault(sql, column: column.name)
      }
      shapes[column.name.lowercased()] = shape
    }
    return shapes
  }

  /// The column a layout column becomes, with what its declaration asks the table to keep.
  private static func kept(_ column: Column, _ shape: ColumnShape?) -> Column {
    guard let shape else { return column }
    var column = column
    if shape.autoNumber {
      column.type = "decimal"
      column.autoNumber = true
    }
    if shape.required { column.required = true }
    if shape.unique { column.unique = true }
    if let initial = shape.initial {
      column.defaultValue = initial
      if initial.now != nil { column.type = "text" }
    }
    return column
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
      // A numbering column is the row number here, so it is filled as the rowid.
      let numbered = entry.fields.first { $0.column.autoNumber == true }
      let filling = entry.fields.filter { !$0.generated && $0.column.id != numbered?.column.id }
      let insert = try prepare(
        "INSERT INTO \"\(key)\"(rowid,"
          + filling.map { "\"\($0.name)\"" }.joined(separator: ",") + ") VALUES(?"
          + String(repeating: ",?", count: filling.count) + ")")
      defer { sqlite3_finalize(insert) }
      for (offset, row) in rows.enumerated() {
        var id = Int64(offset + 1)
        if let numbered {
          guard let number = try? Numbers.decimal(row.1[numbered.column.id]?.text ?? ""),
            Workbook.whole(number), abs(number) < 1_000_000_000_000_000
          else {
            throw SevraError(
              "sql", "\(entry.dataset.title) has a row without a whole number in \(numbered.column.title), which numbers its rows. Give that row a number first.")
          }
          id = NSDecimalNumber(decimal: number).int64Value
        }
        sqlite3_reset(insert)
        sqlite3_bind_int64(insert, 1, id)
        for (index, field) in filling.enumerated() {
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

  func run(_ statements: [String]) throws -> [Value] {
    deadline = Date().addingTimeInterval(3)
    defer {
      guarded = false
      shaping = nil
      deadline = .distantFuture
    }
    var results: [Value] = []
    for (index, written) in statements.enumerated() {
      var sql = Self.prepared(written)
      let shape = Self.shape(sql)
      try require(
        shape == nil || !draft, "sql_draft",
        "A draft can hold UPDATEs only for now. Nothing was changed or saved.")
      // SQLite adds no column whose default is the current time, since the rows already there
      // would need one. Here those rows stay empty and rows added later get the time.
      var clock: String?
      if shape == .alter,
        let match = sql.range(
          of: #"\bDEFAULT\s*\(\s*(datetime|date|time)\s*\(\s*'now'\s*\)\s*\)"#,
          options: [.regularExpression, .caseInsensitive])
      {
        let found = sql[match].lowercased()
        clock = ["datetime", "date", "time"].first { found.contains($0 + "(") }
        sql.removeSubrange(match)
      }
      let before = try shape.map { _ in try layouts() }
      guarded = true
      shaping = shape
      let result = try step(sql, index: index)
      guarded = false
      shaping = nil
      if let shape, let before {
        do {
          let after = try layouts()
          try reshaped(shape, from: before, to: after, clock: clock)
          // A new table's declaration is read now, so a refusal names its statement.
          for name in created {
            guard let layout = after[name] else { continue }
            let shapes = try self.shapes(layout)
            let names = Dictionary(
              layout.columns.map { ($0.name.lowercased(), (id: $0.name, numeric: true)) }
            ) { first, _ in first }
            for column in layout.columns {
              if let expression = shapes[column.name.lowercased()]?.generated {
                _ = try Self.formula(expression, column: column.name, columns: names)
              }
            }
          }
        } catch let error as SevraError {
          throw SevraError(error.code, "Statement \(index + 1): " + error.message)
        }
      }
      if shape == nil { try refreshFormulas() }
      results.append(result)
    }
    return results
  }

  /// Formula columns in the copy are plain values filled when a table is loaded. After a
  /// statement changes rows, those rows' formulas are computed again from their new values,
  /// so a later statement in the same call reads what the workbook will hold. A formula that
  /// names another cell cannot be computed here and reads as NULL until the call is saved.
  private func refreshFormulas() throws {
    for key in order {
      guard let entry = entries[key], !entry.dropped,
        entry.fields.contains(where: { $0.column.formula != nil })
      else { continue }
      let changed = try prepare("SELECT DISTINCT id FROM \"\(Self.log)\" WHERE tbl=?")
      defer { sqlite3_finalize(changed) }
      _ = key.withCString { sqlite3_bind_text(changed, 1, $0, -1, Self.transient) }
      var rowIDs: [Int64] = []
      while sqlite3_step(changed) == SQLITE_ROW { rowIDs.append(sqlite3_column_int64(changed, 0)) }
      guard !rowIDs.isEmpty else { continue }
      let columns = entry.fields.map(\.column)
      let names = entry.fields.map { "\"\($0.name)\"" }.joined(separator: ",")
      let select = try prepare("SELECT \(names) FROM \"\(entry.name)\" WHERE rowid=?")
      defer { sqlite3_finalize(select) }
      for rowID in rowIDs {
        sqlite3_reset(select)
        sqlite3_bind_int64(select, 1, rowID)
        guard sqlite3_step(select) == SQLITE_ROW else { continue }
        var raw: [String: Value] = [:]
        for (index, field) in entry.fields.enumerated() where field.column.formula == nil {
          raw[field.column.id] = cell(select, Int32(index))
        }
        var cache: [String: Decimal] = [:]
        func resolve(_ column: Column, depth: Int) throws -> Decimal {
          if let found = cache[column.id] { return found }
          guard let formula = column.formula else {
            return try Numbers.decimal(raw[column.id]?.text ?? "")
          }
          try require(depth < 128, "formula_limit", "Column dependency depth exceeds 128.")
          let value = try Numbers.decimal(
            Numbers.calculate(
              formula, values: raw,
              units: { name in columns.first { $0.id == name }?.unit },
              resolve: { name in
                guard let other = columns.first(where: { $0.id == name }) else {
                  throw SevraError("cell", "A cell reference is computed when the call is saved.")
                }
                return try resolve(other, depth: depth + 1)
              }))
          cache[column.id] = value
          return value
        }
        for field in entry.fields where field.column.formula != nil && !field.generated {
          let value = try? resolve(field.column, depth: 0)
          try execute(
            "UPDATE \"\(entry.name)\" SET \"\(field.name)\"=? WHERE rowid=?",
            [value.map { .number(Double(Numbers.string($0)) ?? 0) } ?? .null, .number(Double(rowID))])
        }
      }
    }
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
  private func reshaped(
    _ shape: Shape, from before: [String: Layout], to after: [String: Layout], clock: String?
  ) throws {
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
          let shapes = added.isEmpty ? [:] : try self.shapes(layout)
          for column in added {
            let id = Self.unique(Self.identifier(column.name, fallback: "column"), in: &ids)
            let title = Self.title(column.name)
            var shape = shapes[column.name.lowercased()]
            if let clock { shape?.initial = ColumnDefault(now: clock) }
            var kept = Self.kept(
              Column(id: id, title: title, type: Self.numeric(column.type) ? "decimal" : "text"),
              shape)
            if let expression = shape?.generated {
              // A computed column is a formula column, which names the others by id.
              let others = Dictionary(
                entry.fields.map {
                  ($0.name.lowercased(),
                   (id: $0.column.id, numeric: $0.column.type == "decimal" || $0.column.formula != nil))
                }) { first, _ in first }
              kept.type = "decimal"
              kept.formula = try Self.formula(expression, column: column.name, columns: others)
            }
            // SQLite's NOT NULL on an added column needs a default, which fills the rows
            // already there, so required holds for them.
            entry.fields.append(
              Field(
                name: column.name, column: kept, added: true, generated: kept.formula != nil,
                savedDefaultOnly: clock != nil))
            entry.notes.append(
              (kept.formula != nil ? "added computed column " : "added column ") + title)
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
      let shapes = try self.shapes(layout)
      // A column a computed column reads holds numbers when every value it has is one.
      var read = Set<String>()
      for shape in shapes.values {
        guard let expression = shape.generated else { continue }
        for piece in Self.pieces(expression) {
          for word in piece.text.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }) {
            read.insert(word.lowercased())
          }
          if !piece.code, let name = Self.leadingName(piece.text) { read.insert(name.lowercased()) }
        }
      }
      var ids = Set<String>()
      var columns = layout.columns.enumerated().map { index, column in
        let shape = shapes[column.name.lowercased()]
        // A declared number column holds numbers. An undeclared one does if every value is one.
        let decimal =
          numbers[index]
          && (Self.numeric(column.type) || (column.type.isEmpty && filled[index])
            || shape?.generated != nil || read.contains(column.name.lowercased()))
        return Self.kept(
          Column(
            id: Self.unique(Self.identifier(column.name, fallback: "column"), in: &ids),
            title: Self.title(column.name), type: decimal ? "decimal" : "text"),
          shape)
      }
      let names = Dictionary(
        zip(layout.columns, columns).map {
          ($0.name.lowercased(), (id: $1.id, numeric: $1.type == "decimal"))
        }) { first, _ in first }
      for (index, column) in layout.columns.enumerated() {
        guard let expression = shapes[column.name.lowercased()]?.generated else { continue }
        do {
          columns[index].type = "decimal"
          columns[index].formula = try Self.formula(
            expression, column: column.name, columns: names)
        } catch let error as SevraError {
          throw SevraError(error.code, layout.actual + ": " + error.message)
        }
      }
      tables.append(
        Created(
          name: layout.actual, title: Self.title(layout.actual), columns: columns,
          rows: cells.map { row in
            var values: [String: Value] = [:]
            for (index, value) in row.enumerated()
            where value != .null && columns[index].formula == nil {
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
          // An empty cell in a column with a default was set empty, so it stays empty.
          for index in writable
          where now[index] != .null
            || entry.fields[index].column.defaultValue != nil && !entry.fields[index].savedDefaultOnly
          {
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
