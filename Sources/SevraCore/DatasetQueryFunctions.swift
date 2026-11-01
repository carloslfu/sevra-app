import CSQLite
import Foundation

final class DatasetQueryControl {
  let cancellation: Cancellation
  var instructions = 0
  var rows = 0
  var bytes = 0
  var failure: SevraError?
  init(_ cancellation: Cancellation) { self.cancellation = cancellation }
  func check() throws {
    if let failure { throw failure }
    try cancellation.check()
    try require(
      instructions <= 4_000_000, "query_work_limit", "Query exceeded four million VM instructions.")
  }
  func fail(_ error: Error) {
    if failure == nil {
      failure = error as? SevraError ?? .init("query", error.localizedDescription)
    }
  }
}

private final class DatasetDecimalAggregate {
  var sum: Decimal = 0
  var count = 0
  var failed = false
}

extension Database {
  func installDatasetQueryFunctions() throws {
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    let flags = SQLITE_UTF8 | SQLITE_DIRECTONLY
    let result = sqlite3_create_function_v2(
      handle, "SEVRA_QUERY_GUARD", -1, flags, pointer,
      { context, count, values in
        guard let context, let pointer = sqlite3_user_data(context), let values else { return }
        let db = Unmanaged<Database>.fromOpaque(pointer).takeUnretainedValue()
        guard let control = db.queryControl else {
          sqlite3_result_error(context, "A managed query budget is required.", -1)
          return
        }
        do {
          try control.check()
          control.rows += 1
          for index in 0..<Int(count) {
            control.bytes += Int(sqlite3_value_bytes(values[index])) + 16
          }
          try require(
            control.rows <= 100_000 && control.bytes <= 33_554_432, "query_input_limit",
            "Query exceeds 100,000 contributing rows or 32 MiB of referenced inputs. Narrow its scope."
          )
          sqlite3_result_int(context, 1)
        } catch {
          control.fail(error)
          sqlite3_result_error(context, "Managed query input budget exhausted.", -1)
        }
      }, nil, nil, nil)
    try require(result == SQLITE_OK, "query_function", "Cannot install query input accounting.")
    let rowHolds = sqlite3_create_function_v2(
      handle, "SEVRA_ROW_HOLDS", 3, flags, nil,
      { context, _, values in
        guard let context, let values else { return }
        let texts = (0..<3).map { index -> String in
          guard let bytes = sqlite3_value_text(values[index]) else { return "" }
          return String(
            decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_value_bytes(values[index]))),
            as: UTF8.self)
        }
        sqlite3_result_int(
          context, Workbook.rowHolds(texts[0], query: texts[1], columns: texts[2]) ? 1 : 0)
      }, nil, nil, nil)
    try require(rowHolds == SQLITE_OK, "query_function", "Cannot install the table row filter.")
    for name in ["SEVRA_DECIMAL_SUM"] {
      let result = sqlite3_create_function_v2(
        handle, name, 1, flags, pointer, nil,
        { context, _, values in
          guard let context, let values,
            let memory = sqlite3_aggregate_context(
              context, Int32(MemoryLayout<UnsafeMutableRawPointer?>.size))
          else { return }
          let slot = memory.assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
          if slot.pointee == nil {
            slot.pointee = Unmanaged.passRetained(DatasetDecimalAggregate()).toOpaque()
          }
          let state = Unmanaged<DatasetDecimalAggregate>.fromOpaque(slot.pointee!)
            .takeUnretainedValue()
          guard !state.failed, sqlite3_value_type(values[0]) != SQLITE_NULL else { return }
          let length = Int(sqlite3_value_bytes(values[0]))
          guard length > 0, let text = sqlite3_value_text(values[0]) else { return }
          do {
            let raw = String(
              decoding: UnsafeBufferPointer(start: text, count: length), as: UTF8.self)
            var value = try Numbers.decimal(raw)
            var total = state.sum
            var output = Decimal()
            try require(
              NSDecimalAdd(&output, &total, &value, .plain) == .noError, "query_precision",
              "Exact sum exceeds Decimal precision or range. No approximate total was returned.")
            state.sum = output
            state.count += 1
          } catch {
            state.failed = true
            if let pointer = sqlite3_user_data(context) {
              Unmanaged<Database>.fromOpaque(pointer).takeUnretainedValue().queryControl?.fail(
                error)
            }
            sqlite3_result_error(context, "Decimal aggregation failed.", -1)
          }
        },
        { context in
          guard let context else { return }
          guard let memory = sqlite3_aggregate_context(context, 0),
            let pointer = memory.assumingMemoryBound(to: UnsafeMutableRawPointer?.self).pointee
          else {
            sqlite3_result_null(context)
            return
          }
          let state = Unmanaged<DatasetDecimalAggregate>.fromOpaque(pointer).takeRetainedValue()
          memory.assumingMemoryBound(to: UnsafeMutableRawPointer?.self).pointee = nil
          if state.failed {
            sqlite3_result_error(context, "Decimal aggregation failed.", -1)
            return
          }
          guard state.count > 0 else {
            sqlite3_result_null(context)
            return
          }
          let text = Numbers.string(state.sum)
          sqlite3_result_text(
            context, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }, nil)
      try require(result == SQLITE_OK, "query_function", "Cannot install exact decimal aggregates.")
    }
    // Average is division of the exact sum by COUNT of known values in the compiler.
    // Its scalar division stays in Decimal, including explicit plain rounding.
    let divide = sqlite3_create_function_v2(
      handle, "SEVRA_DECIMAL_DIVIDE", 2, flags, pointer,
      { context, _, values in
        guard let context, let values else { return }
        guard sqlite3_value_type(values[0]) != SQLITE_NULL,
          let bytes = sqlite3_value_text(values[0])
        else {
          sqlite3_result_null(context)
          return
        }
        do {
          let sum = try Numbers.decimal(String(cString: bytes))
          let count = sqlite3_value_int64(values[1])
          let text = try Numbers.string(Numbers.binary(sum, Decimal(count), op: "/"))
          sqlite3_result_text(
            context, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } catch {
          if let pointer = sqlite3_user_data(context) {
            Unmanaged<Database>.fromOpaque(pointer).takeUnretainedValue().queryControl?.fail(error)
          }
          sqlite3_result_error(context, "Decimal division failed.", -1)
        }
      }, nil, nil, nil)
    try require(divide == SQLITE_OK, "query_function", "Cannot install decimal division.")
  }

  func datasetQueryBudget<T>(cancellation: Cancellation, _ body: (DatasetQueryControl) throws -> T)
    throws -> T
  {
    try require(queryControl == nil, "query_budget", "A managed query is already running.")
    let control = DatasetQueryControl(cancellation)
    try control.check()
    let automatic = try scalar("PRAGMA automatic_index").int == 1
    try execute("PRAGMA automatic_index=OFF")
    queryControl = control
    let pointer = Unmanaged.passUnretained(control).toOpaque()
    sqlite3_progress_handler(
      handle, 1000,
      { pointer in
        guard let pointer else { return 1 }
        let control = Unmanaged<DatasetQueryControl>.fromOpaque(pointer).takeUnretainedValue()
        control.instructions += 1000
        do {
          try control.check()
          return 0
        } catch {
          control.fail(error)
          return 1
        }
      }, pointer)
    defer {
      sqlite3_progress_handler(handle, 0, nil, nil)
      queryControl = nil
      _ = try? execute("PRAGMA automatic_index=" + (automatic ? "ON" : "OFF"))
    }
    do {
      let result = try body(control)
      try control.check()
      return result
    } catch {
      try control.check()
      throw error
    }
  }
}
