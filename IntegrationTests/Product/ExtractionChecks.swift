import Foundation
import SevraAI
import SevraCore
import SevraProduct

func checkWorkflowExtractionLifecycle() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-workflow-extraction-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  func fixture(_ name: String) throws -> (Workbook, Item, WorkflowExecutionSession) {
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    let file = root.appendingPathComponent(name + ".txt")
    try Data("Received5 bolts.".utf8).write(to: file)
    let source = try book.importFile(file)
    try book.index(source.id, chunks: [Chunk("Previous text")])
    let parameter: Value = .object([
      "id": .string("file"), "label": .string("Document"), "type": .string("item"),
      "required": .bool(true),
    ])
    let extraction = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("extraction"), "title": .string("Prepare document"),
        "description": .string("Synthetic"), "parameters": .array([parameter]),
        "payload": .object(["parser": .string("native-v1"), "file": .string("file")]),
      ]))
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("workflow"), "title": .string("Prepare"),
        "description": .string("Synthetic"),
        "parameters": .array([parameter]),
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
      workflow.id, arguments: .object(["file": .string(source.id)]), token: "start")
    return (book, source, try book.authorizeWorkflowExecution(run["id"].text))
  }
  do {
    let (book, _, session) = try fixture("NativeHelper")
    let model = PausedModel()
    let ai = ProductAI(qualifying: model)
    let run = try await ai.continueWorkflow(
      workbook: book, session: session, owner: "synthetic",
      modelDirectory: root.appendingPathComponent("intentionally-absent-model"))
    try expect(run["state"] == .string("completed"), "Document preparation did not complete")
    let events = await model.snapshot()
    try expect(events.isEmpty, "Document preparation loaded or leased a model")
    let copied = try book.reconstruct(to: root.appendingPathComponent("NativeHelperCopy.sevra"))
    let done = try await ai.continueWorkflow(
      workbook: copied, session: copied.authorizeWorkflowExecution(session.runID), owner: "inspect")
    try expect(done == run, "Completed preparation changed on explicit continued copy")
    try expect(try copied.verify()["ok"] == .bool(true), "Document copy integrity failed")
  }
  for mode in ["complete", "cancel"] {
    let (book, _, session) = try fixture("Waiting-" + mode)
    let started = root.appendingPathComponent(mode + "-started")
    let release = root.appendingPathComponent(mode + "-release")
    let reply = root.appendingPathComponent(mode + "-reply.json")
    try Data(
      "{\"version\":1,\"result\":{\"chunks\":[{\"text\":\"Received5 bolts.\",\"locator\":\"body\"}],\"state\":\"ready\",\"detail\":\"Synthetic delayed parser\"}}"
        .utf8
    ).write(to: reply)
    func quote(_ value: String) -> String {
      "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    let helper = root.appendingPathComponent(mode + "-helper")
    let script =
      "#!/bin/sh\n/usr/bin/touch " + quote(started.path)
      + "\nwhile [ ! -f " + quote(release.path) + " ]; do /bin/sleep 0.01; done\n/bin/cat "
      + quote(reply.path) + "\n"
    try Data(script.utf8).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let worker = ExtractionWorker(executable: helper, timeout: 5)
    let claim = try book.claimWorkflowStep(session, owner: "delayed-parser")
    let request = try book.prepareWorkflowExtraction(
      session, claim: claim, worker: worker.workflowIdentity())
    let cancellation = Cancellation()
    let task = Task.detached {
      try book.performWorkflowExtraction(
        session, claim: claim, request: request, worker: worker, cancellation: cancellation)
    }
    let until = Date().addingTimeInterval(10)
    while !FileManager.default.fileExists(atPath: started.path) {
      try expect(Date() < until, "Delayed document parser never started")
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    let other = try Workbook(book.url)
    let writeStarted = Date()
    _ = try other.addItem(category: "source", kind: "observation", title: "During parsing")
    try expect(Date().timeIntervalSince(writeStarted) < 1, "Parser held the workbook write lock")
    try expect(try other.search("Previous").hits.count == 1, "Parsing replaced the old index early")
    if mode == "cancel" {
      cancellation.cancel(reason: "Synthetic user cancellation")
      do {
        _ = try await task.value
        throw SevraError("test", "Cancelled parser returned a publishable result")
      } catch let error as SevraError {
        try expect(error.code == "cancelled", "Wrong parser cancellation: " + error.code)
      }
      _ = try book.failWorkflowStep(
        session, claim: claim, detail: "Synthetic cancelled preparation")
      try expect(try book.search("Previous").hits.count == 1, "Cancellation lost prior index")
    } else {
      try Data().write(to: release)
      let result = try await task.value
      let done = try book.completeWorkflowStep(session, claim: claim, extraction: result)
      try expect(done["state"] == .string("completed"), "Delayed document result did not complete")
    }
    try expect(try book.verify()["ok"] == .bool(true), "Document lifecycle integrity failed")
  }
  print(
    "PASS document preparation uses the native helper without a model, releases workbook locks, cancels and reconstructs inertly"
  )
}
