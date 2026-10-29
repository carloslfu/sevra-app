import Darwin
import Foundation
import SevraCore

@main private struct AutomationDurabilityWorker {
  static let start = ISO8601DateFormatter().date(from: "2026-10-01T08:00:00Z")!
  static let due = start.addingTimeInterval(3600)
  static func snapshot(_ book: Workbook, id: String) throws -> Value {
    .object([
      "activation": try book.automationActivation(id),
      "occurrences": try book.automationOccurrences(id),
      "events": try book.automationEvents(limit: 50), "runs": .array(try book.workflowRuns()),
      "counts": try book.counts(), "integrity": try book.verify(),
    ])
  }
  static func main() {
    do {
      let args = Array(CommandLine.arguments.dropFirst())
      try require(args.count == 2, "usage", "Expected operation and synthetic fixture directory.")
      let root = URL(fileURLWithPath: args[1])
      let path = root.appendingPathComponent("Automation.sevra")
      let identity = root.appendingPathComponent("identity.json")
      let book: Workbook
      let info: Value
      if args[0] == "setup" {
        book = try Workbook.create(at: path, title: "Synthetic foreground automation")
        let f = try book.saveApplicationDefinition(
          logicalID: identifier(),
          content: .object([
            "kind": .string("function"), "title": .string("Synthetic total"),
            "description": .string("Deterministic"), "parameters": .array([]),
            "payload": .object(["expression": .string("1+2")]),
          ]))
        let workflow = try book.saveApplicationDefinition(
          logicalID: identifier(),
          content: .object([
            "kind": .string("workflow"), "title": .string("Calculate"),
            "description": .string("Synthetic"), "parameters": .array([]),
            "payload": .object([
              "readPolicy": .string("latest-at-step"),
              "steps": .array([
                .object([
                  "id": .string("calculate"), "kind": .string("evaluate"),
                  "binding": .object(["mode": .string("exact"), "versionID": .string(f.id)]),
                  "arguments": .object([:]),
                ])
              ]),
            ]),
          ]))
        let definition = try book.saveApplicationDefinition(
          logicalID: identifier(),
          content: .object([
            "kind": .string("automation"), "title": .string("Scheduled total"),
            "description": .string("Synthetic"), "parameters": .array([]),
            "payload": .object([
              "policy": .string("calendar-drafts-v1"),
              "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow.id)]),
              "arguments": .object([:]),
              "schedule": .object([
                "policy": .string("native-calendar-v1"), "timeZone": .string("UTC"),
                "hour": .number(9), "minute": .number(0),
                "recurrence": .object(["kind": .string("daily")]),
              ]),
            ]),
          ]))
        let session = try book.authorizeAutomationExecution(
          definition.id, expectedGeneration: 0, after: start, token: "authorize")
        _ = try book.planAutomationOccurrences(session.planning, through: due, token: "plan")
        info = .object([
          "definitionID": .string(definition.id),
          "activationID": .string(session.planning.activationID),
        ])
        try Data(info.json().utf8).write(to: identity)
      } else {
        book = try Workbook(path)
        info = try Value.parse(String(contentsOf: identity, encoding: .utf8))
      }
      let id = info["activationID"].text
      switch args[0] {
      case "prepared", "committed", "dispatch":
        // An explicit repeat of the same authorization operation can recover its
        // current receipt. Opening the workbook alone does not issue permission.
        let session = try book.authorizeAutomationExecution(
          info["definitionID"].text, expectedGeneration: 0, after: start, token: "authorize")
        let operation = args[0]
        let observer: @Sendable (AutomationPublicationProbe.Stage, String) -> Void = {
          stage, activation in
          if operation == "prepared" && stage == .prepared
            || operation == "committed" && stage == .committed
          {
            print("{\"stage\":\"" + operation + "\",\"activationID\":\"" + activation + "\"}")
            fflush(stdout)
            guard readLine() == "continue" else { exit(71) }
          }
        }
        _ = try AutomationPublicationProbe.$observer.withValue(observer) {
          try book.dispatchAutomationOccurrence(session, observedAt: due, token: "dispatch")
        }
      case "resume":
        let activation = try book.automationActivation(id)
        let session = try book.authorizeAutomationExecution(
          info["definitionID"].text, expectedGeneration: 1,
          after: start, token: "explicit-resume")
        if let runID = activation["active_run_id"].string {
          _ = try book.continueWorkflow(
            book.authorizeAutomationWorkflowExecution(session, runID: runID),
            owner: "explicit-resume")
        }
      case "copies":
        let copy = try book.reconstruct(to: root.appendingPathComponent("Inert.sevra"))
        try book.export(to: root.appendingPathComponent("Automation.sevraz"))
        let restored = try Workbook.openArchive(
          root.appendingPathComponent("Automation.sevraz"),
          at: root.appendingPathComponent("Restored.sevra"))
        print(
          try Value.object([
            "reconstructed": try snapshot(copy, id: id), "restored": try snapshot(restored, id: id),
          ]).json())
        return
      case "setup", "inspect": break
      default: throw SevraError("usage", "Unknown automation durability operation.")
      }
      print(try snapshot(book, id: id).json())
    } catch {
      fputs(
        (try? encoded(error as? SevraError ?? SevraError("error", error.localizedDescription))
          .json()) ?? "{}", stderr)
      exit(1)
    }
  }
}
