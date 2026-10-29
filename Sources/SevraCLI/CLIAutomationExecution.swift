import Foundation
import SevraCore
import SevraProduct

extension CLI {
  /// A deliberately requested bounded foreground operation. This does not install
  /// a timer or retain device permission when the process exits.
  static func runAutomationOnce(_ args: [String], book: Workbook, cancellation: Cancellation)
    async throws -> Value
  {
    try require(
      (7...9).contains(args.count) && (args.count == 7 || args[7] == "--allow-ai")
        && (args.count != 9 || !args[8].hasPrefix("--")), "usage",
      "automation-run-once WORKBOOK EXACT_DEFINITION_ID EXPECTED_GENERATION START_AFTER OBSERVED_AT TOKEN [--allow-ai [MODEL_DIRECTORY]]"
    )
    guard let generation = Int(args[3]), (0..<1_000_000_000).contains(generation) else {
      throw SevraError(
        "automation_generation",
        "Use the exact current generation, or zero for first authorization.")
    }
    try require(
      !args[6].isEmpty && args[6].utf8.count <= 240, "workflow_token",
      "Use a nonempty operation token up to 240 bytes.")
    let start = try scheduleInstant(args[4])
    let observed = try scheduleInstant(args[5])
    try require(
      start <= observed, "automation_time",
      "The observation must be at or after the requested starting instant.")
    let session = try book.authorizeAutomationExecution(
      args[2], expectedGeneration: generation, after: start,
      allowAI: args.count >= 8, token: args[6] + ":authorize",
      actor: .programmatic("SevraCLI.automation-run-once"), cancellation: cancellation)
    let planned = try book.planAutomationOccurrences(
      session.planning, through: observed, token: args[6] + ":plan", cancellation: cancellation)
    let dispatch: Value
    let run: Value
    if planned["catchUpRemaining"] == .bool(true) {
      dispatch = .object(["status": .string("catch_up"), "execution": .string("none")])
      run = .null
    } else {
      dispatch = try book.dispatchAutomationOccurrence(
        session, observedAt: observed, token: args[6] + ":dispatch", cancellation: cancellation)
      if let id = dispatch["runID"].string ?? dispatch["run"]["id"].string {
        let worker = try book.authorizeAutomationWorkflowExecution(session, runID: id)
        run = try await ProductAI.shared.continueWorkflow(
          workbook: book, session: worker, owner: "automation-cli:" + identifier(),
          modelDirectory: args.count == 9
            ? URL(fileURLWithPath: args[8]) : ProductAI.defaultDirectory, cancellation: cancellation
        )
      } else {
        run = .null
      }
    }
    return .object([
      "activationID": .string(session.planning.activationID),
      "generation": .number(Double(session.planning.generation)),
      "planning": planned, "dispatch": dispatch, "run": run, "timerInstalled": .bool(false),
      "permission": .string("this-process-only"),
    ])
  }
}
