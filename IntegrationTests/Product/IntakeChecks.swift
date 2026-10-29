import Foundation
import SevraAI
import SevraCore
import SevraProduct

func checkWorkflowIntakeLifecycle() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-workflow-intake-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  func fixture(_ name: String) throws -> (Workbook, Dataset, WorkflowExecutionSession) {
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    let source = try book.addItem(category: "source", kind: "observation", title: "Starting values")
    let table = try book.createDataset(
      title: "Parts",
      columns: [
        .init(id: "sku", title: "SKU"), .init(id: "qty", title: "Quantity", type: "decimal"),
      ], rows: [["sku": .string("0012"), "qty": .string("4")]], sourceID: source.id)
    let file = root.appendingPathComponent(name + ".csv")
    try Data("code,amount\n0012,7\n0014,2\n".utf8).write(to: file)
    let original = try book.importFile(file)
    let parameter: Value = .object([
      "id": .string("file"), "label": .string("Incoming file"), "type": .string("item"),
      "required": .bool(true),
    ])
    let intake = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("intake"), "title": .string("Update parts"),
        "description": .string("Synthetic mapping"),
        "parameters": .array([parameter]),
        "payload": .object([
          "parser": .string("native-v1"), "file": .string("file"), "datasetID": .string(table.id),
          "definitionID": .string(table.definitionID), "mode": .string("merge"),
          "headerRow": .number(1),
          "mapping": .array([
            .object(["position": .number(0), "target": .string("sku")]),
            .object(["position": .number(1), "target": .string("qty")]),
          ]),
          "keys": .array([.string("sku")]), "newRowMeaning": .string("estimate"),
          "newRowScenario": .string("actual"),
        ]),
      ]))
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("workflow"), "title": .string("Update and review"),
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
              "id": .string("review"), "kind": .string("review"), "review": .string("import_rows"),
            ]),
          ]),
        ]),
      ]))
    let run = try book.startWorkflow(
      workflow.id, arguments: .object(["file": .string(original.id)]), token: "start")
    return (book, table, try book.authorizeWorkflowExecution(run["id"].text))
  }
  do {
    let (book, table, session) = try fixture("Coordinator")
    let model = PausedModel()
    let service = ProductAI(qualifying: model)
    let waiting = try await service.continueWorkflow(
      workbook: book, session: session, owner: "synthetic",
      modelDirectory: root.appendingPathComponent("absent-model"))
    try expect(waiting["state"] == .string("waiting_review"), "Intake did not stop for review")
    try expect(try book.dataset(table.id).rowCount == 1, "Continuation applied rows without review")
    let output = waiting["steps"].array[0]["output"]["value"]
    try expect(
      output["summary"]["added"] == .number(1) && output["summary"]["changed"] == .number(1),
      "Intake summary lost its mapped changes")
    let accepted = try book.accept(
      output["proposals"].array[0].text, actor: .human("synthetic-review"))
    let done = try await service.continueWorkflow(workbook: book, session: session, owner: "review")
    try expect(
      done["state"] == .string("completed") && accepted.status == "accepted",
      "Exact intake review did not complete")
    let events = await model.snapshot()
    try expect(events.isEmpty, "Deterministic table intake loaded or leased a model")
    try expect(
      try book.rows(table.id).map { $0.data["qty"].text } == ["7", "2"],
      "Reviewed rows differ from the preparation")
    let copy = try book.reconstruct(to: root.appendingPathComponent("CoordinatorCopy.sevra"))
    let unchanged = try await service.continueWorkflow(
      workbook: copy, session: copy.authorizeWorkflowExecution(session.runID),
      owner: "explicit inspect")
    let integrity = try copy.verify()
    try expect(
      unchanged == done && integrity["ok"] == .bool(true), "A completed copied intake ran again")
  }
  for mode in ["complete", "cancel"] {
    let (book, table, session) = try fixture("Delayed-" + mode)
    let started = root.appendingPathComponent(mode + "-started")
    let release = root.appendingPathComponent(mode + "-release")
    func quote(_ value: String) -> String {
      "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    let helper = root.appendingPathComponent(mode + "-helper")
    let script =
      "#!/bin/sh\n/usr/bin/touch " + quote(started.path)
      + "\nwhile [ ! -f " + quote(release.path) + " ]; do /bin/sleep 0.01; done\nexec "
      + quote(ExtractionWorker.bundledExecutable.path) + " \"$@\"\n"
    try Data(script.utf8).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let worker = ExtractionWorker(executable: helper, timeout: 10)
    let claim = try book.claimWorkflowStep(session, owner: "delayed-parser")
    let request = try book.prepareWorkflowIntake(
      session, claim: claim, worker: worker.workflowIdentity())
    let task = Task.detached {
      try book.performWorkflowIntake(session, claim: claim, request: request, worker: worker)
    }
    let until = Date().addingTimeInterval(5)
    while !FileManager.default.fileExists(atPath: started.path) {
      try expect(Date() < until, "Delayed intake parser never started")
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    let other = try Workbook(book.url)
    let time = Date()
    _ = try other.addItem(
      category: "source", kind: "observation", title: "Written during intake parsing")
    try expect(Date().timeIntervalSince(time) < 1, "Intake parsing held the workbook lock")
    if mode == "cancel" {
      _ = try other.cancelWorkflow(other.authorizeWorkflowExecution(session.runID), token: "cancel")
    }
    try Data().write(to: release)
    let prepared = try await task.value
    if mode == "complete" {
      _ = try book.completeWorkflowStep(session, claim: claim, intake: prepared)
    } else {
      do {
        _ = try book.completeWorkflowStep(session, claim: claim, intake: prepared)
        throw SevraError("test", "Cancelled intake published")
      } catch let error as SevraError {
        try expect(error.code == "workflow_fenced", "Unexpected intake cancellation error")
      }
    }
    try expect(
      try book.dataset(table.id).rowCount == 1 && book.verify()["ok"] == .bool(true),
      "Preparation changed working rows")
  }
}
