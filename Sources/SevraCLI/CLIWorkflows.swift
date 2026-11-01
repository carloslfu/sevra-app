import Foundation
import SevraCore
import SevraProduct

extension CLI {
  static func runWorkflowCommand(
    _ command: String, book: Workbook, args: [String],
    cancellation: Cancellation
  ) async throws -> Value? {
    guard command.hasPrefix("workflow-") else { return nil }
    let actor = ChangeActor.programmatic("SevraCLI.manualWorkflow")
    switch command {
    case "workflow-activity":
      try require(
        (2...4).contains(args.count), "usage", "workflow-activity WORKBOOK [STATE|- [CURSOR]]")
      return try book.workflowActivity(
        state: args.count > 2 && args[2] != "-" ? args[2] : nil,
        cursor: args.count > 3 ? args[3] : nil, cancellation: cancellation)
    case "workflow-inspect":
      try require(args.count == 3, "usage", "workflow-inspect WORKBOOK RUN_ID")
      return try book.inspectWorkflow(args[2], cancellation: cancellation)
    case "workflow-start":
      try require(
        args.count == 5, "usage", "workflow-start WORKBOOK EXACT_DEFINITION_ID ARGUMENTS_JSON TOKEN"
      )
      return try book.startWorkflow(
        args[2], arguments: Value.parseExact(args[3]), token: args[4],
        actor: actor, cancellation: cancellation)
    case "workflow-read":
      try require(args.count == 3, "usage", "workflow-read WORKBOOK RUN_ID")
      return try book.workflowRun(args[2])
    case "workflow-clarification":
      try require(args.count == 3, "usage", "workflow-clarification WORKBOOK RUN_ID")
      return try book.workflowClarification(args[2])
    case "workflow-clarify":
      try require(
        args.count == 7, "usage",
        "workflow-clarify WORKBOOK RUN_ID TARGET_JSON VALUES_JSON REASON TOKEN")
      return try book.clarifyWorkflow(
        book.authorizeWorkflowExecution(args[2]), target: Value.parseExact(args[3]),
        values: Value.parseExact(args[4]), reason: args[5], token: args[6],
        actor: .programmatic("SevraCLI.workflowClarification"), cancellation: cancellation)
    case "workflow-list":
      try require((2...3).contains(args.count), "usage", "workflow-list WORKBOOK [STATE]")
      return .array(try book.workflowRuns(state: args.count == 3 ? args[2] : nil))
    case "workflow-events":
      try require(
        (2...3).contains(args.count), "usage", "workflow-events WORKBOOK [AFTER_SEQUENCE]")
      return try book.workflowEvents(after: args.count == 3 ? Int(args[2]) ?? -1 : 0)
    case "workflow-continue", "workflow-advance", "workflow-finish", "workflow-claim",
      "workflow-heartbeat",
      "workflow-retry", "workflow-cancel":
      let counts = [
        "workflow-continue": 3, "workflow-advance": 3, "workflow-finish": 4, "workflow-claim": 6,
        "workflow-heartbeat": 6, "workflow-retry": 4, "workflow-cancel": 4,
      ]
      try require(
        args.count == counts[command] || (command == "workflow-continue" && args.count == 4),
        "usage", "Use the workflow command fields shown in help.")
      if command == "workflow-cancel" {
        return try book.cancelWorkflow(
          args[2], token: args[3], actor: actor, cancellation: cancellation)
      }
      let session = try book.authorizeWorkflowExecution(args[2])
      switch command {
      case "workflow-continue":
        return try await ProductAI.shared.continueWorkflow(
          workbook: book, session: session, owner: "cli:" + identifier(),
          modelDirectory: args.count == 4
            ? URL(fileURLWithPath: args[3]) : ProductAI.defaultDirectory, cancellation: cancellation
        )
      case "workflow-advance":
        return try book.advanceWorkflow(
          session, owner: "cli:" + identifier(), cancellation: cancellation)
      case "workflow-finish":
        return try book.completeWorkflowStep(
          session, claim: Value.parseExact(args[3]), cancellation: cancellation)
      case "workflow-claim":
        return try book.claimWorkflowStep(
          session, owner: args[3], leaseSeconds: Double(args[4]) ?? -1,
          token: args[5], cancellation: cancellation)
      case "workflow-heartbeat":
        return try book.heartbeatWorkflowStep(
          session, claim: Value.parseExact(args[3]),
          leaseSeconds: Double(args[4]) ?? -1, token: args[5])
      case "workflow-retry": return try book.retryWorkflow(session, token: args[3])
      default: return try book.cancelWorkflow(session, token: args[3])
      }
    default: throw SevraError("usage", "Unknown workflow command. See help.")
    }
  }
}
