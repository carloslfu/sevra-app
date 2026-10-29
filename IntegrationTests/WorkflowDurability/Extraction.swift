import Darwin
import Foundation
import SevraCore

enum WorkflowExtractionDurability {
  static func emit(_ value: Value) throws {
    print(try value.json())
    fflush(stdout)
  }
  static func snapshot(_ book: Workbook, _ runID: String) throws -> Value {
    let run = try book.workflowRun(runID)
    return .object([
      "run": run, "extraction": try book.extractionStatus(run["arguments"]["file"].text),
      "priorHits": .number(Double(try book.search("Prior").hits.count)),
      "receivedHits": .number(Double(try book.search("Received5").hits.count)),
      "counts": try book.counts(), "events": try book.workflowEvents(limit: 50),
      "integrity": try book.verify(),
    ])
  }
  static func run(_ operation: String, root: URL) throws {
    let package = root.appendingPathComponent("Extraction.sevra")
    let plan = root.appendingPathComponent("plan.json")
    if operation == "extract-setup" {
      let book = try Workbook.create(at: package, title: "Synthetic document workflow recovery")
      let url = root.appendingPathComponent("Receipt.txt")
      try Data("Received5 bolts.".utf8).write(to: url)
      let item = try book.importFile(url)
      try book.index(item.id, chunks: [Chunk("Prior searchable text")])
      let parameters: Value = .array([
        .object([
          "id": .string("file"), "label": .string("Document"), "type": .string("item"),
          "required": .bool(true),
        ])
      ])
      let extraction = try book.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("extraction"), "title": .string("Prepare document"),
          "description": .string("Synthetic"), "parameters": parameters,
          "payload": .object(["parser": .string("native-v1"), "file": .string("file")]),
        ]))
      let workflow = try book.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("workflow"), "title": .string("Prepare"),
          "description": .string("Synthetic"),
          "parameters": parameters,
          "payload": .object([
            "readPolicy": .string("latest-at-step"),
            "steps": .array([
              .object([
                "id": .string("prepare"), "kind": .string("extract"),
                "binding": .object(["mode": .string("exact"), "versionID": .string(extraction.id)]),
                "arguments": .object(["file": .object(["parameter": .string("file")])]),
              ])
            ]),
          ]),
        ]))
      let run = try book.startWorkflow(
        workflow.id, arguments: .object(["file": .string(item.id)]), token: "start")
      try Data(run.json().utf8).write(to: plan)
      try emit(snapshot(book, run["id"].text))
      return
    }
    let book = try Workbook(package)
    let runID = try Value.parse(String(contentsOf: plan, encoding: .utf8))["id"].text
    if operation == "extract-inspect" {
      try emit(snapshot(book, runID))
      return
    }
    if operation == "extract-copies" {
      let copy = try book.reconstruct(to: root.appendingPathComponent("Reconstructed.sevra"))
      let archive = root.appendingPathComponent("Extraction.sevraz")
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
    if operation == "extract-late" {
      let saved = try Value.parse(
        String(
          contentsOf: root.appendingPathComponent("capture.json"), encoding: .utf8))
      _ = try book.completeWorkflowStep(
        session, claim: saved["claim"], extraction: saved["envelope"])
      throw SevraError("fixture", "A late document checkpoint committed")
    }
    if operation == "extract-resume", try book.workflowRun(runID)["state"] == .string("completed") {
      try emit(snapshot(book, runID))
      return
    }
    try require(
      [
        "extract-request", "extract-parsed", "extract-prepared", "extract-committed",
        "extract-resume",
      ].contains(operation), "usage", "Unknown extraction fixture operation.")
    let claim = try book.claimWorkflowStep(session, owner: identifier(), leaseSeconds: 2)
    let worker = ExtractionWorker()
    let request = try book.prepareWorkflowExtraction(
      session, claim: claim, worker: worker.workflowIdentity())
    @Sendable func barrier(_ envelope: Value) {
      do {
        try emit(
          .object([
            "stage": .string(operation), "value": .object(["claim": claim, "envelope": envelope]),
          ]))
      } catch { exit(70) }
      guard readLine() == "continue" else { exit(71) }
    }
    if operation == "extract-request" { barrier(.object(["request": request, "result": .null])) }
    let envelope = try book.performWorkflowExtraction(session, claim: claim, request: request)
    if operation == "extract-parsed" { barrier(envelope) }
    let observer: @Sendable (WorkflowPublicationProbe.Stage, String) -> Void = { stage, _ in
      if (operation == "extract-prepared" && stage == .prepared)
        || (operation == "extract-committed" && stage == .committed)
      {
        barrier(envelope)
      }
    }
    _ = try WorkflowPublicationProbe.$observer.withValue(observer) {
      try book.completeWorkflowStep(session, claim: claim, extraction: envelope)
    }
    try emit(snapshot(book, runID))
  }
}
