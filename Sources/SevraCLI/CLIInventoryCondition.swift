import Foundation
import SevraCore

extension CLI {
  static func runInventoryCondition(_ args: [String], book: Workbook, cancellation: Cancellation)
    throws -> Value
  {
    switch args[0] {
    case "condition-create":
      try require(
        args.count == 6, "usage",
        "condition-create WORKBOOK SUBJECT RULE_JSON EFFECTIVE_THROUGH TOKEN")
      try require(args[3].utf8.count <= 4096, "condition_limit", "Rule input is limited to 4 KiB.")
      return try book.createInventoryCondition(
        subject: args[2], rule: Value.parse(args[3]), effectiveThrough: args[4], token: args[5],
        cancellation: cancellation, actor: .programmatic("SevraCLI"))
    case "condition-step":
      try require(args.count == 5, "usage", "condition-step WORKBOOK CONSUMER_ID THROUGH TOKEN")
      return try book.stepInventoryCondition(
        args[2], through: args[3], token: args[4], cancellation: cancellation)
    case "condition-state":
      try require(args.count == 3, "usage", "condition-state WORKBOOK CONSUMER_ID")
      return try book.inventoryCondition(args[2], cancellation: cancellation)
    case "condition-observations":
      try require(
        (3...5).contains(args.count), "usage",
        "condition-observations WORKBOOK CONSUMER_ID [AFTER_ID|-] [LIMIT]")
      return try book.inventoryConditionObservations(
        args[2], after: args.count > 3 && args[3] != "-" ? args[3] : nil,
        limit: args.count == 5 ? Int(args[4]) ?? 0 : 20, cancellation: cancellation)
    default:
      try require(args.count == 5, "usage", "condition-dismiss WORKBOOK CANDIDATE_ID REASON TOKEN")
      return try book.dismissInventoryConditionCandidate(
        args[2], reason: args[3], token: args[4], cancellation: cancellation,
        actor: .programmatic("SevraCLI"))
    }
  }
}
