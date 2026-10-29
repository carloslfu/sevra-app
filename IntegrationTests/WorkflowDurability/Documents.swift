import Darwin
import Foundation
import SevraCore

enum WorkflowDocumentDurability {
  static func emit(_ value: Value) throws {
    print(try value.json())
    fflush(stdout)
  }
  static func snapshot(_ book: Workbook, _ runID: String) throws -> Value {
    .object([
      "run": try book.workflowRun(runID), "counts": try book.counts(),
      "documents": .array(
        try book.items().filter { $0.kind == "document" }.map { try encoded($0) }),
      "reportHits": .number(Double(try book.search("ReceivingSummary").hits.count)),
      "events": try book.workflowEvents(limit: 50), "integrity": try book.verify(),
    ])
  }
  static func run(_ operation: String, root: URL) throws {
    let package = root.appendingPathComponent("Documents.sevra")
    let plan = root.appendingPathComponent("plan.json")
    if operation == "document-setup" {
      let book = try Workbook.create(at: package, title: "Synthetic report recovery")
      let source = try book.addItem(
        category: "source", kind: "observation", title: "Receipt", text: "Received5 bolts.")
      let primitive = ActionRegistry.actions().array.first {
        $0["id"] == .string("records.draftDocument")
      }!
      let action = try book.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("action"), "title": .string("Draft report"),
          "description": .string("Synthetic"), "parameters": primitive["parameters"],
          "payload": .object([
            "primitive": .object(["id": primitive["id"], "version": primitive["version"]]),
            "arguments": .object(
              Dictionary(
                uniqueKeysWithValues: primitive["parameters"].array.map {
                  ($0["id"].text, Value.object(["parameter": $0["id"]]))
                })),
          ]),
        ]))
      let workflow = try book.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("workflow"), "title": .string("Draft and review"),
          "description": .string("Synthetic report recovery"), "parameters": action.parameters,
          "payload": .object([
            "readPolicy": .string("latest-at-step"),
            "steps": .array([
              .object([
                "id": .string("report"), "kind": .string("action"),
                "binding": .object(["mode": .string("exact"), "versionID": .string(action.id)]),
                "arguments": .object(
                  Dictionary(
                    uniqueKeysWithValues: action.parameters.array.map {
                      ($0["id"].text, Value.object(["parameter": $0["id"]]))
                    })),
              ]),
              .object([
                "id": .string("review"), "kind": .string("review"), "review": .string("report"),
              ]),
            ]),
          ]),
        ]))
      let run = try book.startWorkflow(
        workflow.id,
        arguments: .object([
          "title": .string("Receiving report"),
          "body": .string("ReceivingSummary: five bolts reported."),
          "evidence": .string(source.id), "meaning": .string("estimate"),
          "scenario": .string("actual"),
        ]), token: "start")
      try Data(run.json().utf8).write(to: plan)
      try emit(snapshot(book, run["id"].text))
      return
    }
    let book = try Workbook(package)
    let runID = try Value.parse(String(contentsOf: plan, encoding: .utf8))["id"].text
    if operation == "document-inspect" {
      try emit(snapshot(book, runID))
      return
    }
    if operation == "document-copies" {
      let copy = try book.reconstruct(to: root.appendingPathComponent("Reconstructed.sevra"))
      let archive = root.appendingPathComponent("Documents.sevraz")
      try book.export(to: archive)
      let restored = try Workbook.openArchive(
        archive, at: root.appendingPathComponent("Restored.sevra"))
      try emit(
        .object([
          "reconstructed": try snapshot(copy, runID), "restored": try snapshot(restored, runID),
        ]))
      return
    }
    let session = try book.authorizeWorkflowExecution(runID)
    if operation == "document-late" {
      let claim = try Value.parse(
        String(contentsOf: root.appendingPathComponent("claim.json"), encoding: .utf8))
      _ = try book.completeWorkflowStep(session, claim: claim)
      throw SevraError("fixture", "A late report checkpoint committed")
    }
    if operation == "document-accept" {
      let proposal = try book.items().first { $0.kind == "document" }!
      _ = try book.accept(proposal.id, actor: .human("synthetic-review"))
      try emit(snapshot(book, runID))
      return
    }
    if operation == "document-review" {
      _ = try book.continueWorkflow(session, owner: "review")
      try emit(snapshot(book, runID))
      return
    }
    if operation == "document-resume" {
      let state = try book.workflowRun(runID)["steps"].array[0]["state"]
      if state != .string("completed") {
        _ = try book.advanceWorkflow(session, owner: "resume")
      }
      try emit(snapshot(book, runID))
      return
    }
    try require(
      ["document-prepared", "document-committed"].contains(operation), "usage",
      "Unknown report fixture operation.")
    let claim = try book.claimWorkflowStep(session, owner: identifier(), leaseSeconds: 2)
    let observer: @Sendable (WorkflowPublicationProbe.Stage, String) -> Void = { stage, _ in
      if (operation == "document-prepared" && stage == .prepared)
        || (operation == "document-committed" && stage == .committed)
      {
        do { try emit(.object(["stage": .string(operation), "value": claim])) } catch { exit(70) }
        guard readLine() == "continue" else { exit(71) }
      }
    }
    _ = try WorkflowPublicationProbe.$observer.withValue(observer) {
      try book.completeWorkflowStep(session, claim: claim)
    }
    try emit(snapshot(book, runID))
  }
}
