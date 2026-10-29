import Darwin
import Foundation
import SevraCore

@main private struct WorkflowDurabilityWorker {
  static func emit(_ value: Value) throws {
    print(try value.json())
    fflush(stdout)
  }
  static func barrier(_ stage: String, _ value: Value) {
    do { try emit(.object(["stage": .string(stage), "value": value])) } catch { exit(70) }
    guard readLine() == "continue" else { exit(71) }
  }
  static func snapshot(_ book: Workbook, runID: String) throws -> Value {
    .object([
      "run": try book.workflowRun(runID), "counts": try book.counts(),
      "balance": try book.balance(subject: "bolts"), "events": try book.workflowEvents(limit: 50),
      "integrity": try book.verify(),
    ])
  }
  static func main() {
    do {
      let args = Array(CommandLine.arguments.dropFirst())
      try require(args.count == 2, "usage", "Expected operation and disposable fixture directory.")
      let operation = args[0]
      let root = URL(fileURLWithPath: args[1])
      let path = root.appendingPathComponent("Workflow.sevra")
      let plan = root.appendingPathComponent("run.json")
      if operation == "setup" {
        let book = try Workbook.create(at: path, title: "Synthetic workflow")
        let source = try book.addItem(
          category: "source", kind: "observation", title: "Synthetic delivery", status: "accepted")
        try book.setOpeningBalance(
          subject: "bolts", quantity: "20", effective: "2026-01-01", sourceID: source.id)
        let f = try book.saveApplicationDefinition(
          logicalID: identifier(),
          content: .object([
            "kind": .string("function"), "title": .string("Preflight count"),
            "description": .string("Synthetic deterministic step"),
            "parameters": .array([]), "payload": .object(["expression": .string("1+1")]),
          ]))
        let action = try book.saveApplicationDefinition(
          logicalID: identifier(), content: ActionRegistry.receivingDefinition())
        let workflow = try book.saveApplicationDefinition(
          logicalID: identifier(),
          content: .object([
            "kind": .string("workflow"), "title": .string("Receive evidence"),
            "description": .string("Synthetic fixture"),
            "parameters": action.parameters,
            "payload": .object([
              "readPolicy": .string("latest-at-step"),
              "steps": .array([
                .object([
                  "id": .string("count"), "kind": .string("evaluate"),
                  "binding": .object(["mode": .string("exact"), "versionID": .string(f.id)]),
                  "arguments": .object([:]),
                ]),
                .object([
                  "id": .string("delivery"), "kind": .string("action"),
                  "binding": .object(["mode": .string("exact"), "versionID": .string(action.id)]),
                  "arguments": .object(
                    Dictionary(
                      uniqueKeysWithValues: action.parameters.array.map {
                        ($0["id"].text, .object(["parameter": $0["id"]]))
                      })),
                ]),
                .object([
                  "id": .string("review"), "kind": .string("review"), "review": .string("delivery"),
                ]),
              ]),
            ]),
          ]))
        let run = try book.startWorkflow(
          workflow.id,
          arguments: .object([
            "delivery": .string("delivery-one"), "effective": .string("2026-10-28"),
            "evidence": .string(source.id),
            "lines": .array([
              .object([
                "line": .string("one"), "subject": .string("bolts"), "quantity": .string("5"),
              ])
            ]),
          ]), token: "start")
        let runID = run["id"].text
        try Data(try Value.object(["runID": .string(runID)]).json().utf8).write(to: plan)
        _ = try book.advanceWorkflow(
          book.authorizeWorkflowExecution(runID), owner: "fixture-preflight")
        try emit(snapshot(book, runID: runID))
        return
      }
      let runID = try Value.parse(String(contentsOf: plan, encoding: .utf8))["runID"].text
      let book = try Workbook(path)
      if operation == "inspect" {
        try emit(snapshot(book, runID: runID))
        return
      }
      if operation == "inert-copies" {
        let reconstructed = try book.reconstruct(
          to: root.appendingPathComponent("Reconstructed.sevra"))
        let archive = root.appendingPathComponent("Workflow.sevraz")
        try book.export(to: archive)
        let restored = try Workbook.openArchive(
          archive, at: root.appendingPathComponent("Restored.sevra"))
        try emit(
          .object([
            "reconstructed": try snapshot(reconstructed, runID: runID),
            "restored": try snapshot(restored, runID: runID),
          ]))
        return
      }
      let session = try book.authorizeWorkflowExecution(runID)
      if operation == "advance" {
        _ = try book.advanceWorkflow(session, owner: "resumed-fixture")
      } else if operation == "accept" {
        let run = try book.workflowRun(runID)
        for proposal in run["steps"].array[1]["output"]["value"]["proposals"].array {
          _ = try book.accept(proposal.text, actor: .human("fixture-review"))
        }
      } else if operation == "late" {
        let claim = try Value.parse(
          String(contentsOf: root.appendingPathComponent("claim.json"), encoding: .utf8))
        _ = try book.completeWorkflowStep(session, claim: claim)
      } else {
        try require(
          ["claimed", "prepared", "committed"].contains(operation), "usage",
          "Unknown worker operation.")
        let claim = try book.claimWorkflowStep(
          session, owner: "fixture:" + identifier(), leaseSeconds: 2)
        if operation == "claimed" {
          barrier(operation, claim)
        } else {
          let observer: @Sendable (WorkflowPublicationProbe.Stage, String) -> Void = { stage, _ in
            if (operation == "prepared" && stage == .prepared)
              || (operation == "committed" && stage == .committed)
            {
              barrier(operation, claim)
            }
          }
          _ = try WorkflowPublicationProbe.$observer.withValue(observer) {
            try book.completeWorkflowStep(session, claim: claim)
          }
        }
      }
      try emit(snapshot(book, runID: runID))
    } catch {
      let e = error as? SevraError ?? SevraError("fixture", String(describing: error))
      fputs((try! encoded(e).json()) + "\n", stderr)
      exit(1)
    }
  }
}
