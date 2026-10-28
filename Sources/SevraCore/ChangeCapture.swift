import CSQLite
import Foundation

/// One per connection, driven only under its existing SQLite transaction and
/// package lock. Connection-local capture triggers use only public SQLite APIs.
final class ChangeCapture {
  let workbookID: String
  let writerID = identifier()
  var actor = ChangeActor.programmatic("SevraCore")
  var pending: [RowChange]?
  var failure: SevraError?
  var bytes = 0
  var publishing = false

  init(workbookID: String) { self.workbookID = workbookID }
  func begin(_ database: Database) throws {
    try actor.validate()
    try require(pending == nil, "change_transaction", "A change transaction is already active.")
    pending = []
    failure = nil
    bytes = 0
  }
  func reset() {
    pending = nil
    failure = nil
    bytes = 0
    publishing = false
  }
  func receive(_ arguments: [OpaquePointer?]) {
    guard arguments.count >= 4, let nameBytes = sqlite3_value_text(arguments[0]),
      let operationBytes = sqlite3_value_text(arguments[1])
    else {
      failure = .init("change_capture", "Invalid capture arguments.")
      return
    }
    let name = String(decodingCString: nameBytes, as: UTF8.self)
    let operation = String(decodingCString: operationBytes, as: UTF8.self)
    if name == "committed_changes" {
      if !publishing {
        failure = .init(
          "change_integrity", "Committed history cannot be edited by an ordinary mutation.")
      }
      return
    }
    guard ChangeFormat.tables.contains(name), pending != nil else {
      failure = .init(
        "change_untracked", "A durable write has no declared change transaction: " + name)
      return
    }
    guard failure == nil else { return }
    let count = (arguments.count - 4) / 2
    func row(_ previous: Bool) throws -> ChangeRow {
      let offset = previous ? 4 : 4 + count
      let id = sqlite3_value_int64(arguments[previous ? 2 : 3])
      var values: [ChangeCell] = []
      for index in offset..<(offset + count) {
        let cell = try ChangeCell.read(arguments[index])
        switch cell {
        case .text(let data), .blob(let data): bytes += data.count
        default: bytes += 16
        }
        try require(
          bytes <= 67_108_864, "change_limit",
          "This transaction exceeds the 64 MB saved-change limit. Split the operation into smaller batches."
        )
        values.append(cell)
      }
      return .init(rowID: String(id), values: values)
    }
    do {
      let before = operation == "insert" ? nil : try row(true)
      let after = operation == "delete" ? nil : try row(false)
      let portableBefore = ChangeFormat.portable(before, table: name)
      let portableAfter = ChangeFormat.portable(after, table: name)
      if portableBefore != portableAfter {
        try require(
          (pending?.count ?? 0) < 250_000, "change_limit", "Too many changes in one transaction.")
        pending?.append(.init(table: name, before: portableBefore, after: portableAfter))
      }
    } catch {
      failure = error as? SevraError ?? .init("change_capture", error.localizedDescription)
    }
  }
  func publish(_ database: Database) throws {
    if let failure { throw failure }
    guard let pending, !pending.isEmpty else { return }
    let prior = try database.execute(
      "SELECT id,hash FROM committed_changes ORDER BY rowid DESC LIMIT 1"
    ).first
    // An ordinary operation and its receipt use the same global identity. Small
    // infrastructure writes have a separate identity without a business revision.
    let operationIDs = pending.filter { $0.table == "operations" && $0.before == nil }.compactMap {
      $0.after?.values.first?.string
    }
    try require(
      operationIDs.count <= 1, "change_transaction",
      "A transaction cannot contain independent operation receipts.")
    let change = CommittedChange(
      version: 1, storageVersion: Schema.version, id: operationIDs.first ?? identifier(),
      workbookID: workbookID, previousID: prior?["id"]?.string,
      previousHash: prior?["hash"]?.string,
      recorded: timestamp(), writerID: writerID, actor: actor, changes: pending)
    let payload = try ChangeFormat.encode(change)
    publishing = true
    defer { publishing = false }
    try database.execute(
      "INSERT INTO committed_changes VALUES(?,?,?,?,?,?,?,?)",
      [
        .string(change.id), change.previousID.map(Value.string) ?? .null, .string(payload),
        .string(ChangeFormat.hash(payload)), .string(change.recorded), .string(change.writerID),
        .string(try ChangeFormat.encode(change.actor)), .number(Double(change.changes.count)),
      ])
  }
}

extension ChangeCell {
  static func read(_ value: OpaquePointer?) throws -> Self {
    switch sqlite3_value_type(value) {
    case SQLITE_NULL: return .null
    case SQLITE_INTEGER: return .integer(String(sqlite3_value_int64(value)))
    case SQLITE_FLOAT: return .real(String(sqlite3_value_double(value).bitPattern))
    case SQLITE_TEXT:
      let pointer = sqlite3_value_text(value)
      let count = Int(sqlite3_value_bytes(value))
      if count == 0 { return .text(Data()) }
      guard let pointer else { throw SevraError("change_value", "Missing text bytes.") }
      return .text(Data(bytes: pointer, count: count))
    case SQLITE_BLOB:
      let count = Int(sqlite3_value_bytes(value))
      if count == 0 { return .blob(Data()) }
      guard let pointer = sqlite3_value_blob(value) else {
        throw SevraError("change_value", "Missing blob bytes.")
      }
      return .blob(Data(bytes: pointer, count: count))
    default: throw SevraError("change_value", "Unknown SQLite value type.")
    }
  }
}

extension Database {
  func enableChangeCapture(workbookID: String) throws {
    let ordinary = try execute(
      "SELECT name FROM sqlite_master WHERE type='table' AND sql NOT LIKE 'CREATE VIRTUAL TABLE%' AND name NOT LIKE 'sqlite_%'"
    ).compactMap { $0["name"]?.string }.filter {
      !ChangeFormat.isIndex($0) && $0 != "committed_changes" && $0 != "extraction_attempts"
    }
    try require(
      Set(ordinary) == ChangeFormat.tables, "change_schema",
      "The current schema has unclassified durable tables.")
    let capture = ChangeCapture(workbookID: workbookID)
    changes = capture
    let context = Unmanaged.passUnretained(capture).toOpaque()
    let result = sqlite3_create_function_v2(
      handle, "sevra_capture", -1, SQLITE_UTF8, context,
      { context, count, arguments in
        guard let context, let pointer = sqlite3_user_data(context), let arguments else { return }
        let capture = Unmanaged<ChangeCapture>.fromOpaque(pointer).takeUnretainedValue()
        capture.receive(Array(UnsafeBufferPointer(start: arguments, count: Int(count))))
        if let failure = capture.failure {
          sqlite3_result_error(context, failure.message, -1)
        } else {
          sqlite3_result_null(context)
        }
      }, nil, nil, nil)
    try require(
      result == SQLITE_OK, "change_capture", "Cannot install the durable capture function.")
    for table in (ChangeFormat.tables.union(["committed_changes"])).sorted() {
      let columns = try execute("PRAGMA table_info(" + ChangeFormat.quote(table) + ")").compactMap {
        $0["name"]?.string
      }
      for operation in ["insert", "update", "delete"] {
        let old = columns.map { operation == "insert" ? "NULL" : "old." + ChangeFormat.quote($0) }
        let new = columns.map { operation == "delete" ? "NULL" : "new." + ChangeFormat.quote($0) }
        let arguments =
          [
            "'" + table + "'", "'" + operation + "'", operation == "insert" ? "NULL" : "old.rowid",
            operation == "delete" ? "NULL" : "new.rowid",
          ] + old + new
        try script(
          "CREATE TEMP TRIGGER " + ChangeFormat.quote("capture_" + table + "_" + operation)
            + " AFTER " + operation.uppercased() + " ON main." + ChangeFormat.quote(table)
            + " BEGIN SELECT sevra_capture(" + arguments.joined(separator: ",") + "); END;")
      }
    }
  }
}
