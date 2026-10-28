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
  var tables = ChangeFormat.tables
  var schemaCookie: Int?
  var resettingProjection: String?
  private var fragment:
    (
      name: String, operation: String, before: String, after: String,
      old: [ChangeCell], new: [ChangeCell]
    )?

  init(workbookID: String) { self.workbookID = workbookID }
  func begin(_ database: Database) throws {
    try actor.validate()
    try require(pending == nil, "change_transaction", "A change transaction is already active.")
    if schemaCookie != (try database.scalar("PRAGMA main.schema_version").int) {
      try database.refreshCaptureSchema()
    }
    pending = []
    failure = nil
    bytes = 0
  }
  func reset() {
    pending = nil
    failure = nil
    bytes = 0
    publishing = false
    fragment = nil
    resettingProjection = nil
  }
  func receive(_ arguments: [OpaquePointer?]) {
    guard arguments.count >= 6, let nameBytes = sqlite3_value_text(arguments[0]),
      let operationBytes = sqlite3_value_text(arguments[1])
    else {
      failure = .init("change_capture", "Invalid capture arguments.")
      return
    }
    let name = String(decodingCString: nameBytes, as: UTF8.self)
    let operation = String(decodingCString: operationBytes, as: UTF8.self)
    if name == resettingProjection && operation == "delete" { return }
    if name == "committed_changes" {
      if !publishing {
        failure = .init(
          "change_integrity", "Committed history cannot be edited by an ordinary mutation.")
      }
      return
    }
    guard tables.contains(name), pending != nil else {
      failure = .init(
        "change_untracked", "A durable write has no declared change transaction: " + name)
      return
    }
    guard failure == nil else { return }
    let count = (arguments.count - 6) / 2
    let total = Int(sqlite3_value_int(arguments[4]))
    let start = Int(sqlite3_value_int(arguments[5]))
    func cells(_ previous: Bool) throws -> [ChangeCell] {
      let offset = previous ? 6 : 6 + count
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
      return values
    }
    do {
      let oldID = String(sqlite3_value_int64(arguments[2]))
      let newID = String(sqlite3_value_int64(arguments[3]))
      try require(
        total > 0 && total <= 2000 && count > 0 && start + count <= total,
        "change_capture", "Invalid capture fragment.")
      if start == 0 {
        try require(fragment == nil, "change_capture", "An incomplete row capture remains.")
        fragment = (name, operation, oldID, newID, [], [])
      }
      guard var part = fragment else {
        throw SevraError("change_capture", "Missing initial capture fragment.")
      }
      try require(
        part.name == name && part.operation == operation && part.before == oldID
          && part.after == newID && part.old.count == start,
        "change_capture", "Capture fragments are out of order.")
      part.old += try cells(true)
      part.new += try cells(false)
      fragment = part
      guard start + count == total else { return }
      fragment = nil
      let before: ChangeRow? = operation == "insert" ? nil : .init(rowID: oldID, values: part.old)
      let after: ChangeRow? = operation == "delete" ? nil : .init(rowID: newID, values: part.new)
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
    try require(fragment == nil, "change_capture", "An incomplete row capture cannot commit.")
    if pending?.contains(where: { !ChangeFormat.tables.contains($0.table) }) == true {
      try database.trimPerformanceIndexes()
    }
    guard pending?.isEmpty == false else { return }
    let prior = try database.execute(
      "SELECT id,hash FROM committed_changes ORDER BY rowid DESC LIMIT 1"
    ).first
    // An ordinary operation and its receipt use the same global identity. Small
    // infrastructure writes have a separate identity without a business revision.
    let operationIDs = pending!.filter { $0.table == "operations" && $0.before == nil }.compactMap {
      $0.after?.values.first?.string
    }
    try require(
      operationIDs.count <= 1, "change_transaction",
      "A transaction cannot contain independent operation receipts.")
    let changeID = operationIDs.first ?? identifier()
    // Cursor clocks share the transaction and captured metadata. Agent journal,
    // context and conversation writes must not stale their own next read page.
    // These are invalidation tokens, not another business ledger or cache value.
    var clocks: [String] = []
    if pending!.contains(where: {
      ["app_definitions", "app_definition_heads", "app_definition_dependencies"].contains($0.table)
    }) {
      clocks.append("definition-read-snapshot")
    }
    if pending!.contains(where: {
      ["items", "heads", "datasets", "dataset_rows", "column_versions"].contains($0.table)
        || !ChangeFormat.tables.contains($0.table)
    }) {
      clocks.append("dataset-read-snapshot")
    }
    for key in clocks {
      try database.execute(
        "INSERT INTO meta VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        [.string(key), .string(changeID)])
    }
    if let failure { throw failure }
    guard let pending else {
      throw SevraError("change_capture", "The change transaction lost its rows.")
    }
    let change = CommittedChange(
      version: 1, storageVersion: Schema.version, id: changeID,
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
    try refreshCaptureSchema()
  }

  func refreshCaptureSchema() throws {
    guard let capture = changes else { return }
    try validateCanonicalSchema()
    capture.tables = try durableTables()
    for table in capture.tables.union(["committed_changes"]).sorted() {
      try installCaptureTable(table)
    }
    capture.schemaCookie = try scalar("PRAGMA main.schema_version").int
  }

  func installCaptureTable(_ table: String) throws {
    guard let capture = changes else { return }
    capture.tables.insert(table)
    changeColumns[table] = nil
    let columns = try execute("PRAGMA table_info(" + ChangeFormat.quote(table) + ")")
      .compactMap { $0["name"]?.string }
    try require(!columns.isEmpty, "change_schema", "A registered capture table is missing.")
    // Fifty columns per callback stays below even SQLite's older 127-argument
    // limit. Fragments become one lossless row image before publication.
    for operation in ["insert", "update", "delete"] {
      let trigger = ChangeFormat.quote("capture_" + table + "_" + operation)
      try script("DROP TRIGGER IF EXISTS temp." + trigger)
      var calls: [String] = []
      for start in stride(from: 0, to: columns.count, by: 50) {
        let batch = columns[start..<min(start + 50, columns.count)]
        let old = batch.map { operation == "insert" ? "NULL" : "old." + ChangeFormat.quote($0) }
        let new = batch.map { operation == "delete" ? "NULL" : "new." + ChangeFormat.quote($0) }
        let arguments =
          [
            "'" + table + "'", "'" + operation + "'", operation == "insert" ? "NULL" : "old.rowid",
            operation == "delete" ? "NULL" : "new.rowid", String(columns.count), String(start),
          ] + old + new
        calls.append("SELECT sevra_capture(" + arguments.joined(separator: ",") + ");")
      }
      try script(
        "CREATE TEMP TRIGGER " + trigger + " AFTER " + operation.uppercased()
          + " ON main." + ChangeFormat.quote(table) + " BEGIN " + calls.joined(separator: " ")
          + " END;")
    }
    capture.schemaCookie = try scalar("PRAGMA main.schema_version").int
  }
}
