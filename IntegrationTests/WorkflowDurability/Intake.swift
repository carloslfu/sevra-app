import Darwin
import Foundation
import SevraCore

enum WorkflowIntakeDurability {
  static func emit(_ value: Value) throws {
    print(try value.json())
    fflush(stdout)
  }
  static func barrier(_ stage: String, _ claim: Value) throws {
    try emit(.object(["stage": .string(stage), "value": claim]))
    guard readLine() == "continue" else { exit(71) }
  }
  static func snapshot(_ book: Workbook, _ runID: String, _ datasetID: String) throws -> Value {
    .object([
      "run": try book.workflowRun(runID), "counts": try book.counts(),
      "rows": .array(try book.rows(datasetID).map { try encoded($0) }),
      "proposals": .array(try book.items(kind: "table-intake-update").map { try encoded($0) }),
      "balance": try book.balance(subject: "stock"),
      "events": try book.workflowEvents(limit: 50), "integrity": try book.verify(),
    ])
  }
  static func run(_ operation: String, root: URL) throws {
    let package = root.appendingPathComponent("Intake.sevra")
    let planURL = root.appendingPathComponent("plan.json")
    let worker = ExtractionWorker()
    if operation == "intake-setup" {
      let book = try Workbook.create(at: package, title: "Synthetic structured intake")
      let basis = try book.addItem(
        category: "source", kind: "observation", title: "Starting values")
      try book.setOpeningBalance(
        subject: "stock", quantity: "20", effective: "2026-01-01", sourceID: basis.id)
      let table = try book.createDataset(
        title: "Parts",
        columns: [
          .init(id: "sku", title: "SKU"), .init(id: "qty", title: "Quantity", type: "decimal"),
        ],
        rows: [["sku": .string("0012"), "qty": .string("4")]], sourceID: basis.id)
      let csv = root.appendingPathComponent("Incoming.csv")
      try Data("code,amount\n0014,2\n".utf8).write(to: csv)
      let source = try book.importFile(csv)
      let parameter: Value = .object([
        "id": .string("file"), "label": .string("Incoming file"), "type": .string("item"),
        "required": .bool(true),
      ])
      let intake = try book.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("intake"), "title": .string("Append rows"),
          "description": .string("Synthetic"),
          "parameters": .array([parameter]),
          "payload": .object([
            "parser": .string("native-v1"), "file": .string("file"), "datasetID": .string(table.id),
            "definitionID": .string(table.definitionID), "mode": .string("append"),
            "headerRow": .number(1),
            "mapping": .array([
              .object(["position": .number(0), "target": .string("sku")]),
              .object(["position": .number(1), "target": .string("qty")]),
            ]),
            "keys": .array([]), "newRowMeaning": .string("estimate"),
            "newRowScenario": .string("actual"),
          ]),
        ]))
      let workflow = try book.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("workflow"), "title": .string("Append and review"),
          "description": .string("Synthetic"),
          "parameters": .array([parameter]),
          "payload": .object([
            "readPolicy": .string("latest-at-step"),
            "steps": .array([
              .object([
                "id": .string("import_rows"), "kind": .string("intake"),
                "binding": .object(["mode": .string("exact"), "versionID": .string(intake.id)]),
                "arguments": .object(["file": .object(["parameter": .string("file")])]),
              ]),
              .object([
                "id": .string("review"), "kind": .string("review"),
                "review": .string("import_rows"),
              ]),
            ]),
          ]),
        ]))
      let run = try book.startWorkflow(
        workflow.id, arguments: .object(["file": .string(source.id)]), token: "start")
      let plan: Value = .object(["runID": run["id"], "datasetID": .string(table.id)])
      try Data(plan.json().utf8).write(to: planURL)
      try emit(snapshot(book, run["id"].text, table.id))
      return
    }
    let book = try Workbook(package)
    let plan = try Value.parse(String(contentsOf: planURL, encoding: .utf8))
    let runID = plan["runID"].text
    let datasetID = plan["datasetID"].text
    if operation == "intake-inspect" {
      try emit(snapshot(book, runID, datasetID))
      return
    }
    if operation == "intake-copies" {
      let copy = try book.reconstruct(to: root.appendingPathComponent("Reconstructed.sevra"))
      let archive = root.appendingPathComponent("Intake.sevraz")
      try book.export(to: archive)
      let restored = try Workbook.openArchive(
        archive, at: root.appendingPathComponent("Restored.sevra"))
      try emit(
        .object([
          "reconstructed": try snapshot(copy, runID, datasetID),
          "restored": try snapshot(restored, runID, datasetID),
        ]))
      return
    }
    let session = try book.authorizeWorkflowExecution(runID)
    if operation == "intake-late" {
      let claim = try Value.parse(
        String(contentsOf: root.appendingPathComponent("claim.json"), encoding: .utf8))
      _ = try book.prepareWorkflowIntake(session, claim: claim, worker: worker.workflowIdentity())
      throw SevraError("fixture", "A late intake worker captured a new request")
    }
    if operation == "intake-review" {
      _ = try book.continueWorkflow(session, owner: "review")
      try emit(snapshot(book, runID, datasetID))
      return
    }
    if operation.hasPrefix("intake-accept") {
      let run = try book.workflowRun(runID)
      let proposal = run["steps"].array[0]["output"]["value"]["proposals"].array[0].text
      let observer: @Sendable (WorkflowPublicationProbe.Stage, String) -> Void = { stage, _ in
        if (operation == "intake-accept-prepared" && stage == .prepared)
          || (operation == "intake-accept-committed" && stage == .committed)
        {
          do { try barrier(operation, .null) } catch { exit(70) }
        }
      }
      _ = try WorkflowPublicationProbe.$observer.withValue(observer) {
        try book.accept(proposal, token: "accept-once", actor: .human("synthetic-review"))
      }
      try emit(snapshot(book, runID, datasetID))
      return
    }
    if operation == "intake-resume",
      try book.workflowRun(runID)["steps"].array[0]["state"] == .string("completed")
    {
      try emit(snapshot(book, runID, datasetID))
      return
    }
    try require(
      ["intake-request", "intake-parsed", "intake-prepared", "intake-committed", "intake-resume"]
        .contains(operation), "usage", "Unknown intake fixture operation.")
    let claim = try book.claimWorkflowStep(
      session, owner: identifier(), leaseSeconds: operation == "intake-resume" ? 30 : 2)
    let request = try book.prepareWorkflowIntake(
      session, claim: claim, worker: worker.workflowIdentity())
    if operation == "intake-request" { try barrier(operation, claim) }
    let result = try book.performWorkflowIntake(session, claim: claim, request: request)
    if operation == "intake-parsed" { try barrier(operation, claim) }
    let observer: @Sendable (WorkflowPublicationProbe.Stage, String) -> Void = { stage, _ in
      if (operation == "intake-prepared" && stage == .prepared)
        || (operation == "intake-committed" && stage == .committed)
      {
        do { try barrier(operation, claim) } catch { exit(70) }
      }
    }
    _ = try WorkflowPublicationProbe.$observer.withValue(observer) {
      try book.completeWorkflowStep(session, claim: claim, intake: result)
    }
    try emit(snapshot(book, runID, datasetID))
  }
}
