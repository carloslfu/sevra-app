import CSQLite
import Foundation

@testable import SevraCore

/// Cancel after the read transaction starts, with a real competing SQLite writer.
/// Dispatching a timer races the 100 ms busy timeout on a loaded CI machine.
func checkLockedReadCancellation(
  _ book: Workbook, read: (Cancellation) throws -> Void
) throws {
  let other = try Database(book.url.appendingPathComponent("workbook.sqlite"))
  try other.execute("BEGIN EXCLUSIVE")
  defer { _ = try? other.execute("ROLLBACK") }
  let cancellation = Cancellation()
  sqlite3_trace_v2(
    book.db.handle, UInt32(SQLITE_TRACE_STMT),
    { _, context, statement, _ in
      if let context, let statement,
        sqlite3_sql(OpaquePointer(statement)).map({ String(cString: $0) }) == "BEGIN"
      {
        Unmanaged<Cancellation>.fromOpaque(context).takeUnretainedValue().cancel()
      }
      return 0
    }, Unmanaged.passUnretained(cancellation).toOpaque())
  defer { sqlite3_trace_v2(book.db.handle, 0, nil, nil) }
  let start = ProcessInfo.processInfo.systemUptime
  try refuses("cancelled") { try read(cancellation) }
  try expect(cancellation.isCancelled, "The read must enter its transaction before cancellation.")
  try expect(ProcessInfo.processInfo.systemUptime - start < 1)
  sqlite3_trace_v2(book.db.handle, 0, nil, nil)
  // Without cancellation the same real lock must remain an ordinary busy error.
  let busyStart = ProcessInfo.processInfo.systemUptime
  try refuses("database") { try read(Cancellation()) }
  try expect(ProcessInfo.processInfo.systemUptime - busyStart < 1)
}
