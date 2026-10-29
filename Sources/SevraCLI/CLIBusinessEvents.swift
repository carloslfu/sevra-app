import Foundation
import SevraCore

extension CLI {
  static func runBusinessFeed(
    _ args: [String], book: Workbook, cancellation: Cancellation
  ) throws -> Value {
    if args[0] == "business-batch" {
      try require(
        (3...5).contains(args.count), "usage",
        "business-batch WORKBOOK BATCH_ID [AFTER_ORDINAL|-] [LIMIT]")
      let ordinal: Int?
      if args.count > 3 && args[3] != "-" {
        guard let value = Int(args[3]), value >= 0 else {
          throw SevraError("business_cursor", "Choose a nonnegative entry ordinal, or -.")
        }
        ordinal = value
      } else {
        ordinal = nil
      }
      return try book.businessBatch(
        args[2], afterOrdinal: ordinal, limit: args.count == 5 ? Int(args[4]) ?? 0 : 50,
        cancellation: cancellation)
    }
    try require(
      args.count == 2 || args.count == 3 || args.count == 4 || args.count == 6, "usage",
      "business-batches WORKBOOK [AFTER_BATCH_ID|-] [LIMIT] [SCOPE_KIND SCOPE_KEY]")
    return try book.businessBatches(
      after: args.count > 2 && args[2] != "-" ? args[2] : nil,
      limit: args.count > 3 ? Int(args[3]) ?? 0 : 20,
      scopeKind: args.count == 6 ? args[4] : nil, scopeKey: args.count == 6 ? args[5] : nil,
      cancellation: cancellation)
  }
}
