import CSQLite
import Foundation

final class Database {
  var handle: OpaquePointer?
  var changes: ChangeCapture?
  var changeColumns: [String: [String]] = [:]
  var queryControl: DatasetQueryControl?
  /// The running budget, until a commit makes its outcome final.
  private var activeBudget: Cancellation?
  init(_ url: URL, create: Bool = false) throws {
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | (create ? SQLITE_OPEN_CREATE : 0)
    guard
      sqlite3_open_v2(url.path == "/:memory:" ? ":memory:" : url.path, &handle, flags, nil)
        == SQLITE_OK
    else {
      sqlite3_close(handle)
      handle = nil
      throw SevraError("database", "Cannot open workbook database.")
    }
    sqlite3_busy_timeout(handle, 5000)
    try execute("PRAGMA foreign_keys=ON")
    try execute("PRAGMA trusted_schema=OFF")
    // Decimal collation preserves ordering beyond binary floating-point precision.
    sqlite3_create_collation_v2(
      handle, "SEVRA_DECIMAL", SQLITE_UTF8, nil,
      { _, n1, p1, n2, p2 in
        guard let p1, let p2 else { return 0 }
        let a = String(decoding: UnsafeRawBufferPointer(start: p1, count: Int(n1)), as: UTF8.self)
        let b = String(decoding: UnsafeRawBufferPointer(start: p2, count: Int(n2)), as: UTF8.self)
        if let x = try? Numbers.decimal(a), let y = try? Numbers.decimal(b) {
          return x < y ? -1 : x > y ? 1 : 0
        }
        return a < b ? -1 : a > b ? 1 : 0
      }, nil)
    // Apple system SQLite omits loadable extensions.
    try installDatasetQueryFunctions()
  }
  deinit {
    sqlite3_close(handle)
  }
  func script(_ sql: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
      let message = error.map { String(cString: $0) } ?? "Database statement failed"
      sqlite3_free(error)
      throw SevraError("database", message)
    }
  }
  @discardableResult func execute(
    _ sql: String, _ values: [Value] = [], maxRows: Int = Int.max, maxBytes: Int = Int.max
  ) throws -> [[String: Value]] {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
      throw failure()
    }
    defer { sqlite3_finalize(stmt) }
    try require(
      Int(sqlite3_bind_parameter_count(stmt)) == values.count, "database",
      "Incorrect argument count.")
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (i, v) in values.enumerated() {
      let n = Int32(i + 1)
      switch v {
      case .null: sqlite3_bind_null(stmt, n)
      case .number(let d): sqlite3_bind_double(stmt, n, d)
      case .bool(let b): sqlite3_bind_int(stmt, n, b ? 1 : 0)
      default:
        let text = v.text
        try require(
          text.utf8.count <= Int(Int32.max), "value_limit", "A database value is too large.")
        sqlite3_bind_text(stmt, n, text, Int32(text.utf8.count), transient)
      }
    }
    var result: [[String: Value]] = []
    var bytes = 0
    while true {
      let rc = sqlite3_step(stmt)
      if rc == SQLITE_DONE { break }
      guard rc == SQLITE_ROW else { throw queryControl?.failure ?? changes?.failure ?? failure() }
      try require(
        result.count < maxRows, "query_result_limit", "Query result exceeds its row budget.")
      var row: [String: Value] = [:]
      for i in 0..<sqlite3_column_count(stmt) {
        let type = sqlite3_column_type(stmt, i)
        bytes += Int(sqlite3_column_bytes(stmt, i)) + 16
        try require(
          bytes <= maxBytes, "query_result_limit", "Query result exceeds its byte budget.")
        let key = String(cString: sqlite3_column_name(stmt, i))
        switch type {
        case SQLITE_NULL: row[key] = .null
        case SQLITE_INTEGER: row[key] = .number(Double(sqlite3_column_int64(stmt, i)))
        case SQLITE_FLOAT: row[key] = .number(sqlite3_column_double(stmt, i))
        default:
          let count = Int(sqlite3_column_bytes(stmt, i))
          if let bytes = sqlite3_column_text(stmt, i) {
            row[key] = .string(
              String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self))
          } else {
            row[key] = .string("")
          }
        }
      }
      result.append(row)
    }
    return result
  }
  func scalar(_ sql: String, _ values: [Value] = []) throws -> Value {
    try execute(sql, values).first?.values.first ?? .null
  }
  func budget<T>(cancellation: Cancellation, seconds: TimeInterval, _ body: () throws -> T) throws
    -> T
  {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: seconds)
    try control.check()
    let outer = activeBudget
    activeBudget = control
    watchProgress(control)
    defer {
      activeBudget = outer
      watchProgress(outer)
    }
    do {
      let result = try body()
      try activeBudget?.check()
      return result
    } catch {
      try control.check()
      throw error
    }
  }
  private func watchProgress(_ control: Cancellation?) {
    guard let control else {
      sqlite3_progress_handler(handle, 0, nil, nil)
      return
    }
    sqlite3_progress_handler(
      handle, 5000,
      { context in
        guard let context else { return 1 }
        let control = Unmanaged<Cancellation>.fromOpaque(context).takeUnretainedValue()
        return (try? control.check()) == nil ? 1 : 0
      }, Unmanaged.passUnretained(control).toOpaque())
  }
  func failure() -> SevraError { .init("database", String(cString: sqlite3_errmsg(handle))) }
  func shortWait<T>(_ body: () throws -> T) rethrows -> T {
    sqlite3_busy_timeout(handle, 100)
    defer { sqlite3_busy_timeout(handle, 5000) }
    return try body()
  }
  func transaction<T>(beforeCommit: (() throws -> Void)? = nil, _ body: () throws -> T) throws -> T
  {
    try execute("BEGIN IMMEDIATE")
    do {
      try changes?.begin(self)
      let value = try body()
      try changes?.publish(self)
      try beforeCommit?()
      // Past COMMIT the change is saved, so a limit can only refuse it here.
      try activeBudget?.check()
      try execute("COMMIT")
      activeBudget = nil
      changes?.reset()
      return value
    } catch {
      _ = try? execute("ROLLBACK")
      changes?.reset()
      changes?.schemaCookie = nil
      changeColumns.removeAll()
      throw error
    }
  }
  func readTransaction<T>(_ body: () throws -> T) throws -> T {
    if sqlite3_get_autocommit(handle) == 0 { return try body() }
    try execute("BEGIN")
    do {
      let result = try body()
      try execute("COMMIT")
      return result
    } catch {
      _ = try? execute("ROLLBACK")
      throw error
    }
  }
  func backup(to destination: URL, cancellation: Cancellation = .init()) throws {
    let other = try Database(destination, create: true)
    guard let backup = sqlite3_backup_init(other.handle, "main", handle, "main") else {
      throw other.failure()
    }
    let deadline = ProcessInfo.processInfo.systemUptime + 30
    var finished = false
    defer { if !finished { sqlite3_backup_finish(backup) } }
    while true {
      try cancellation.check()
      try require(
        ProcessInfo.processInfo.systemUptime < deadline, "backup_busy",
        "The workbook remained busy while taking a snapshot. Retry when other writers finish.")
      let rc = sqlite3_backup_step(backup, 256)
      if rc == SQLITE_DONE {
        let result = sqlite3_backup_finish(backup)
        finished = true
        try require(result == SQLITE_OK, "backup", "Could not finish a coherent snapshot.")
        break
      }
      try require(
        [SQLITE_OK, SQLITE_BUSY, SQLITE_LOCKED].contains(rc), "backup",
        "Could not copy the workbook snapshot.")
      if rc != SQLITE_OK { Thread.sleep(forTimeInterval: 0.01) }
    }
  }
}
