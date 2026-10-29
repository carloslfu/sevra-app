import CSQLite
import CryptoKit
import Foundation

extension Database {
  func savedRow(_ table: String, id: String) throws -> ChangeRow? {
    try rows(table, where: "WHERE rowid=?", id: id).first
  }
  func rows(_ table: String, where clause: String = "", id: String? = nil) throws -> [ChangeRow] {
    var rows: [ChangeRow] = []
    try visitRows(table, where: clause, id: id) { rows.append($0) }
    return rows
  }
  func visitRows(
    _ table: String, where clause: String = "", id: String? = nil,
    _ visit: (ChangeRow) throws -> Void
  ) throws {
    try require(try isDurableTable(table), "change_table", "Unknown saved-change table.")
    var statement: OpaquePointer?
    let sql = "SELECT rowid,* FROM " + ChangeFormat.quote(table) + " " + clause + " ORDER BY rowid"
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw failure()
    }
    defer { sqlite3_finalize(statement) }
    if let id {
      guard let id = Int64(id), sqlite3_bind_int64(statement, 1, id) == SQLITE_OK else {
        throw SevraError("change_value", "Invalid saved row identity.")
      }
    }
    while true {
      let rc = sqlite3_step(statement)
      if rc == SQLITE_DONE { break }
      guard rc == SQLITE_ROW else { throw failure() }
      var cells: [ChangeCell] = []
      for index in 1..<sqlite3_column_count(statement) {
        cells.append(try ChangeCell.read(sqlite3_column_value(statement, index)))
      }
      try visit(.init(rowID: String(sqlite3_column_int64(statement, 0)), values: cells))
    }
  }
  /// Only saved row values reach SQL. Neither executable SQL nor a tool name in
  /// the payload is ever evaluated as an instruction.
  func apply(_ change: RowChange) throws {
    try require(
      try isDurableTable(change.table), "change_table", "Unknown saved-change table.")
    if change.resetProjection == true {
      try require(
        !ChangeFormat.tables.contains(change.table)
          && change.before == nil && change.after == nil,
        "change_payload", "Only a registered native projection may be reset.")
      try execute("DELETE FROM " + ChangeFormat.quote(change.table))
      return
    }
    try require(change.resetProjection == nil, "change_payload", "Invalid projection reset marker.")
    try require(
      change.before != nil || change.after != nil, "change_payload",
      "An empty row change is invalid.")
    let identity = change.before?.rowID ?? change.after!.rowID
    let current = try ChangeFormat.portable(
      savedRow(change.table, id: identity), table: change.table)
    try require(
      current == change.before, "change_base",
      "A saved change does not match its exact predecessor: " + change.table)
    if let after = change.after, after.rowID != identity {
      try require(
        try savedRow(change.table, id: after.rowID) == nil, "change_base",
        "A saved row identity is already in use.")
    }
    let columns: [String]
    if let cached = changeColumns[change.table] {
      columns = cached
    } else {
      columns = try execute("PRAGMA table_info(" + ChangeFormat.quote(change.table) + ")")
        .compactMap { $0["name"]?.string }
      changeColumns[change.table] = columns
    }
    var sql: String
    var cells: [ChangeCell]
    if let after = change.after {
      try require(
        after.values.count == columns.count
          && ChangeFormat.portable(after, table: change.table) == after, "change_payload",
        "Saved values do not match the portable table schema.")
      if change.before == nil {
        sql =
          "INSERT INTO " + ChangeFormat.quote(change.table) + "(rowid,"
          + columns.map(ChangeFormat.quote).joined(separator: ",") + ") VALUES("
          + Array(repeating: "?", count: columns.count + 1).joined(separator: ",") + ")"
        cells = [.integer(after.rowID)] + after.values
      } else {
        sql =
          "UPDATE " + ChangeFormat.quote(change.table) + " SET rowid=?,"
          + columns.map { ChangeFormat.quote($0) + "=?" }.joined(separator: ",") + " WHERE rowid=?"
        cells = [.integer(after.rowID)] + after.values + [.integer(identity)]
      }
    } else {
      sql = "DELETE FROM " + ChangeFormat.quote(change.table) + " WHERE rowid=?"
      cells = [.integer(identity)]
    }
    try executeCells(sql, cells)
    if change.table == "datasets" {
      try materializeManagedSchema(
        before: ManagedDatasetSchema.decode(change.before),
        after: ManagedDatasetSchema.decode(change.after))
    }
  }
  func executeCells(_ sql: String, _ cells: [ChangeCell]) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw failure()
    }
    defer { sqlite3_finalize(statement) }
    try require(
      Int(sqlite3_bind_parameter_count(statement)) == cells.count, "change_payload",
      "Invalid saved value count.")
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (offset, cell) in cells.enumerated() {
      let index = Int32(offset + 1)
      let rc: Int32
      switch cell {
      case .null: rc = sqlite3_bind_null(statement, index)
      case .integer(let text):
        guard let value = Int64(text), String(value) == text else {
          throw SevraError("change_value", "Invalid saved integer.")
        }
        rc = sqlite3_bind_int64(statement, index, value)
      case .real(let text):
        guard let bits = UInt64(text), String(bits) == text, Double(bitPattern: bits).isFinite
        else { throw SevraError("change_value", "Invalid saved real number.") }
        rc = sqlite3_bind_double(statement, index, Double(bitPattern: bits))
      case .text(let bytes):
        try require(
          String(data: bytes, encoding: .utf8) != nil && bytes.count <= Int(Int32.max),
          "change_value", "Invalid saved UTF-8 text.")
        if bytes.isEmpty {
          rc = sqlite3_bind_text(statement, index, "", 0, transient)
        } else {
          rc = bytes.withUnsafeBytes { buffer in
            sqlite3_bind_text(
              statement, index, buffer.baseAddress!.assumingMemoryBound(to: CChar.self),
              Int32(bytes.count), transient)
          }
        }
      case .blob(let bytes):
        try require(bytes.count <= Int(Int32.max), "change_value", "Saved blob exceeds the limit.")
        if bytes.isEmpty {
          rc = sqlite3_bind_zeroblob(statement, index, 0)
        } else {
          rc = bytes.withUnsafeBytes {
            sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(bytes.count), transient)
          }
        }
      }
      try require(rc == SQLITE_OK, "change_value", "Cannot bind a saved value.")
    }
    try require(
      sqlite3_step(statement) == SQLITE_DONE, "change_apply",
      String(cString: sqlite3_errmsg(handle)))
  }
  func applyCommitted(_ payload: String, hash: String, cancellation: Cancellation = .init()) throws
  {
    try cancellation.check()
    try require(
      changes == nil && sevra_trigger_state(handle) == 0, "change_execution",
      "Saved changes can only be applied to an inert reconstruction connection.")
    try require(
      ChangeFormat.hash(payload) == hash, "change_hash",
      "A committed change failed its content hash.")
    let change = try JSONDecoder().decode(CommittedChange.self, from: Data(payload.utf8))
    try require(
      change.version == 1 && change.storageVersion == Schema.version, "change_version",
      "Unsupported saved-change schema.")
    try change.actor.validate()
    try require(
      !change.id.isEmpty && !change.writerID.isEmpty && !change.changes.isEmpty
        && change.changes.count <= 250_000, "change_payload", "Invalid committed change metadata.")
    try require(
      change.workbookID == scalar("SELECT value FROM meta WHERE key='workbook-id'").text,
      "change_workbook", "Saved change belongs to another workbook.")
    try transaction {
      if let prior = try execute(
        "SELECT payload,hash FROM committed_changes WHERE id=?", [.string(change.id)]
      ).first {
        try require(
          prior["payload"]?.text == payload && prior["hash"]?.text == hash, "idempotency",
          "A committed change identity was reused with different content.")
        return
      }
      let previous = try execute(
        "SELECT id,hash FROM committed_changes ORDER BY rowid DESC LIMIT 1"
      ).first
      try require(
        previous?["id"]?.string == change.previousID
          && previous?["hash"]?.string == change.previousHash, "change_predecessor",
        "Missing or out-of-order saved change predecessor.")
      try execute("PRAGMA defer_foreign_keys=ON")
      for row in change.changes {
        try cancellation.check()
        try apply(row)
      }
      // Deferred foreign keys validate this transaction at COMMIT. A full
      // database scan per small change would make long histories quadratic.
      // The finished reconstruction also runs the ordinary integrity verifier.
      try execute(
        "INSERT INTO committed_changes VALUES(?,?,?,?,?,?,?,?)",
        [
          .string(change.id), change.previousID.map(Value.string) ?? .null, .string(payload),
          .string(hash), .string(change.recorded), .string(change.writerID),
          .string(try ChangeFormat.encode(change.actor)), .number(Double(change.changes.count)),
        ])
    }
  }
  func authorityDigest(cancellation: Cancellation = .init()) throws -> String {
    var hash = SHA256()
    for table in try durableTables().sorted() {
      hash.update(data: Data((table + "\n").utf8))
      try visitRows(table) { raw in
        try cancellation.check()
        guard let row = ChangeFormat.portable(raw, table: table) else { return }
        // Presentation rows can leave harmless holes in meta's physical row IDs.
        let stable = table == "meta" ? ChangeRow(rowID: "", values: row.values) : row
        hash.update(data: Data((try ChangeFormat.encode(stable) + "\n").utf8))
      }
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
