import Foundation
import SevraCore

extension CLI {
  static func runAutomationInspection(
    _ args: [String], book: Workbook, cancellation: Cancellation
  ) throws -> Value? {
    switch args[0] {
    case "automation-causality":
      try require(args.count == 3, "usage", "automation-causality WORKBOOK RUN_ID")
      return try book.automationCausality(args[2], cancellation: cancellation)
    case "automation-list":
      try require(
        (2...4).contains(args.count), "usage", "automation-list WORKBOOK [AFTER_ID_OR_-] [LIMIT]")
      return try book.automationActivations(
        after: args.count > 2 && args[2] != "-" ? args[2] : "",
        limit: scheduleLimit(args, 3, default: 20))
    case "automation-activation":
      try require(
        args.count == 3, "usage", "automation-activation WORKBOOK ACTIVATION_ID")
      return try book.automationActivation(args[2])
    case "automation-occurrences":
      try require(
        (3...5).contains(args.count), "usage",
        "automation-occurrences WORKBOOK ACTIVATION_ID [AFTER_ID_OR_-] [LIMIT]")
      return try book.automationOccurrences(
        args[2], after: args.count > 3 && args[3] != "-" ? args[3] : nil,
        limit: scheduleLimit(args, 4, default: 20))
    case "automation-events":
      try require(
        (2...4).contains(args.count), "usage", "automation-events WORKBOOK [AFTER_SEQUENCE] [LIMIT]"
      )
      return try book.automationEvents(
        after: scheduleLimit(args, 2, default: 0), limit: scheduleLimit(args, 3, default: 20))
    case "automation-pause":
      try require(
        args.count == 5, "usage",
        "automation-pause WORKBOOK ACTIVATION_ID EXPECTED_GENERATION TOKEN")
      guard let generation = Int(args[3]), (1...1_000_000_000).contains(generation) else {
        throw SevraError("automation_generation", "Use a positive exact generation.")
      }
      return try book.pauseAutomation(
        args[2], expectedGeneration: generation, token: args[4],
        actor: .programmatic("SevraCLI.automation-pause"),
        cancellation: cancellation)
    default: return nil
    }
  }
}
