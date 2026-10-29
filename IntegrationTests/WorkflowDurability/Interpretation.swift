import Darwin
import Foundation
import SevraCore

enum WorkflowInterpretationDurability {
  static func emit(_ value: Value) throws {
    print(try value.json())
    fflush(stdout)
  }
  static func snapshot(_ book: Workbook, _ runID: String) throws -> Value {
    .object([
      "inspection": try book.inspectWorkflow(runID), "counts": try book.counts(),
      "events": try book.workflowEvents(limit: 50), "integrity": try book.verify(),
    ])
  }
  static func run(_ operation: String, root: URL) throws {
    let package = root.appendingPathComponent("Interpretation.sevra")
    let planURL = root.appendingPathComponent("plan.json")
    if operation == "interpret-setup" {
      let book = try Workbook.create(at: package, title: "Synthetic interpretation recovery")
      let source = try book.addItem(
        category: "source", kind: "observation", title: "Receipt", text: "Received5 bolts.")
      let parameters: Value = .array([
        .object([
          "id": .string("evidence"), "label": .string("Evidence"), "type": .string("item"),
          "required": .bool(true),
        ])
      ])
      let definition = try book.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("interpretation"), "title": .string("Received count"),
          "description": .string("Synthetic durability fixture"), "parameters": parameters,
          "payload": .object([
            "instruction": .string("Extract the received count."),
            "evidence": .array([.string("evidence")]),
            "outputs": .array([
              .object([
                "id": .string("quantity"), "label": .string("Count"), "type": .string("decimal"),
                "required": .bool(true), "unit": .string("items"),
              ])
            ]), "meaning": .string("actual"), "scenario": .string("actual"),
          ]),
        ]))
      let workflow = try book.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("workflow"), "title": .string("Read"),
          "description": .string("Synthetic durability fixture"), "parameters": parameters,
          "payload": .object([
            "readPolicy": .string("latest-at-step"),
            "steps": .array([
              .object([
                "id": .string("read"), "kind": .string("interpret"),
                "binding": .object(["mode": .string("exact"), "versionID": .string(definition.id)]),
                "arguments": .object(["evidence": .object(["parameter": .string("evidence")])]),
              ])
            ]),
          ]),
        ]))
      let run = try book.startWorkflow(
        workflow.id, arguments: .object(["evidence": .string(source.id)]), token: "start")
      try Data(run.json().utf8).write(to: planURL)
      try emit(snapshot(book, run["id"].text))
      return
    }
    let book = try Workbook(package)
    let runID = try Value.parse(String(contentsOf: planURL, encoding: .utf8))["id"].text
    if operation == "interpret-inspect" {
      try emit(snapshot(book, runID))
      return
    }
    if operation == "interpret-copies" {
      let rebuilt = try book.reconstruct(to: root.appendingPathComponent("Reconstructed.sevra"))
      let archive = root.appendingPathComponent("Interpretation.sevraz")
      try book.export(to: archive)
      let restored = try Workbook.openArchive(
        archive, at: root.appendingPathComponent("Restored.sevra"))
      try emit(
        .object([
          "reconstructed": try snapshot(rebuilt, runID), "restored": try snapshot(restored, runID),
        ]))
      return
    }
    let session = try book.authorizeWorkflowExecution(runID)
    if operation == "interpret-late" {
      let saved = try Value.parse(
        String(contentsOf: root.appendingPathComponent("capture.json"), encoding: .utf8))
      _ = try book.completeWorkflowStep(
        session, claim: saved["claim"], interpretation: saved["envelope"])
      throw SevraError("fixture", "A late interpretation committed")
    }
    if operation == "interpret-resume", try book.workflowRun(runID)["state"] == .string("completed")
    {
      try emit(snapshot(book, runID))
      return
    }
    try require(
      [
        "interpret-request", "interpret-response", "interpret-prepared", "interpret-committed",
        "interpret-resume",
      ].contains(operation), "usage", "Unknown interpretation fixture operation.")
    let claim = try book.claimWorkflowStep(session, owner: identifier(), leaseSeconds: 2)
    let request = try book.prepareWorkflowInterpretation(
      session, claim: claim, model: "Synthetic durability model")
    let envelope: Value = .object([
      "request": request, "metrics": .object(["synthetic": .bool(true)]),
      "response": .object([
        "state": .string("ready"), "values": .object(["quantity": .string("5")]),
        "citations": .array([
          .object([
            "field": .string("quantity"), "itemID": request["evidence"].array[0]["id"],
            "quote": .string("Received5 bolts."),
          ])
        ]), "issues": .array([]),
      ]),
    ])
    @Sendable func barrier() {
      do {
        try emit(
          .object([
            "stage": .string(operation), "value": .object(["claim": claim, "envelope": envelope]),
          ]))
      } catch { exit(70) }
      guard readLine() == "continue" else { exit(71) }
    }
    if operation == "interpret-request" { barrier() }
    try book.retainWorkflowInterpretationResponse(session, claim: claim, response: envelope)
    if operation == "interpret-response" { barrier() }
    let observer: @Sendable (WorkflowPublicationProbe.Stage, String) -> Void = { stage, _ in
      if (operation == "interpret-prepared" && stage == .prepared)
        || (operation == "interpret-committed" && stage == .committed)
      {
        barrier()
      }
    }
    _ = try WorkflowPublicationProbe.$observer.withValue(observer) {
      try book.completeWorkflowStep(session, claim: claim, interpretation: envelope)
    }
    try emit(snapshot(book, runID))
  }
}
