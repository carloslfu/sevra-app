import Darwin
import Foundation
import SevraCore

enum WorkflowClarificationDurability {
  static func run(_ operation: String, root: URL) throws {
    let book = try Workbook(root.appendingPathComponent("Clarification.sevra"))
    let plan = try Value.parse(
      String(contentsOf: root.appendingPathComponent("plan.json"), encoding: .utf8))
    let runID = plan["runID"].text
    let session = try book.authorizeWorkflowExecution(runID)
    func snapshot() throws -> Value {
      .object([
        "run": try book.workflowRun(runID), "counts": try book.counts(),
        "balance": try book.balance(subject: "bolts"), "events": try book.workflowEvents(),
        "integrity": try book.verify(),
      ])
    }
    if operation == "clarify-pause" {
      let claim = try book.claimWorkflowStep(session, owner: "synthetic-clarification")
      let request = try book.prepareWorkflowInterpretation(
        session, claim: claim, model: "Synthetic clarification fixture, no inference")
      _ = try book.completeWorkflowStep(
        session, claim: claim,
        interpretation: .object([
          "request": request, "metrics": .object(["synthetic": .bool(true)]),
          "response": .object([
            "state": .string("needs_input"), "values": .object([:]), "citations": .array([]),
            "issues": .array([.string("The received count is missing. Please supply it.")]),
          ]),
        ]))
      print(try snapshot().json())
      return
    }
    try require(
      ["clarify-prepared", "clarify-committed", "clarify-resume"].contains(operation),
      "usage", "Unknown clarification fixture operation.")
    let observer: @Sendable (WorkflowPublicationProbe.Stage, String) -> Void = { stage, _ in
      if (operation == "clarify-prepared" && stage == .prepared)
        || (operation == "clarify-committed" && stage == .committed)
      {
        print("{\"stage\":\"" + operation + "\"}")
        fflush(stdout)
        guard readLine() == "continue" else { exit(71) }
      }
    }
    _ = try WorkflowPublicationProbe.$observer.withValue(observer) {
      try book.clarifyWorkflow(
        session, target: plan["target"], values: .object(["quantity": .string("5")]),
        reason: "The synthetic calling program supplies five received units.",
        token: "supplied-count",
        actor: .programmatic("SevraWorkflowDurability.clarification"))
    }
    print(try snapshot().json())
  }
}
