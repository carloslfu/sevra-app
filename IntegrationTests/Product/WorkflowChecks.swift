import Foundation
import SevraAI
import SevraCore
import SevraProduct

private actor PausedInterpretation: WorkbookInference {
  let identity = "Synthetic structured workflow model"
  let lastMetrics: Value = .object(["synthetic": .bool(true)])
  private var started = false
  private var released = false
  private(set) var count = 0
  private(set) var leased = false
  private(set) var unloaded = false
  func beginRun() throws {
    try expect(!leased, "Overlapping workflow inference")
    leased = true
  }
  func endRun() { leased = false }
  func releaseResources() -> Bool {
    if leased { return false }
    unloaded = true
    return true
  }
  func waitUntilStarted() async throws {
    let until = Date().addingTimeInterval(10)
    while !started {
      try expect(Date() < until, "Workflow model never started")
      try await Task.sleep(nanoseconds: 1_000_000)
    }
  }
  func resume() { released = true }
  func interpret(
    request: Value, directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void
  ) async throws -> Value {
    try expect(leased, "Workflow inference had no model lease")
    count += 1
    started = true
    while !released {
      try cancellation.check()
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    try cancellation.check()
    return .object([
      "request": request, "metrics": lastMetrics,
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
  }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    throw SevraError("test", "Workflow interpretation used conversation tools")
  }
}

func checkWorkflowModelLifecycle() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-workflow-model-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  for mode in ["complete", "cancel", "pressure"] {
    let book = try Workbook.create(at: root.appendingPathComponent(mode + ".sevra"), title: mode)
    let source = try book.addItem(
      category: "source", kind: "observation", title: "Receipt", text: "Received5 bolts.")
    let parameter: Value = .object([
      "id": .string("evidence"), "label": .string("Evidence"), "type": .string("item"),
      "required": .bool(true),
    ])
    let interpretation = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("interpretation"), "title": .string("Count"),
        "description": .string("Synthetic"), "parameters": .array([parameter]),
        "payload": .object([
          "instruction": .string("Extract the count."), "evidence": .array([.string("evidence")]),
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
        "kind": .string("workflow"), "title": .string("Read"), "description": .string("Synthetic"),
        "parameters": .array([parameter]),
        "payload": .object([
          "readPolicy": .string("latest-at-step"),
          "steps": .array([
            .object([
              "id": .string("read"), "kind": .string("interpret"),
              "binding": .object([
                "mode": .string("exact"), "versionID": .string(interpretation.id),
              ]), "arguments": .object(["evidence": .object(["parameter": .string("evidence")])]),
            ])
          ]),
        ]),
      ]))
    let run = try book.startWorkflow(
      workflow.id, arguments: .object(["evidence": .string(source.id)]), token: "start")
    let session = try book.authorizeWorkflowExecution(run["id"].text)
    let model = PausedInterpretation()
    let service = ProductAI(qualifying: model)
    let task = Task {
      try await service.continueWorkflow(
        workbook: book, session: session, owner: "synthetic", modelDirectory: root)
    }
    try await model.waitUntilStarted()
    // A distinct connection commits while the model is suspended. Waiting for
    // inference must not retain the workbook write lock.
    let second = try Workbook(book.url)
    _ = try second.addItem(
      category: "source", kind: "observation", title: "Written during inference")
    do {
      _ = try await service.run("Hello", workbook: book)
      throw SevraError("test", "Conversation overlapped workflow model resources")
    } catch let error as SevraError {
      try expect(error.code == "busy", "Unexpected overlapping model refusal")
    }
    if mode == "cancel" {
      _ = try second.cancelWorkflow(second.authorizeWorkflowExecution(session.runID), token: "stop")
    } else if mode == "pressure" {
      let pressure = await service.handleMemoryPressure(critical: true)
      try expect(
        pressure == .stopping,
        "Critical pressure did not stop workflow")
    }
    await model.resume()
    if mode == "complete" {
      let done = try await task.value
      try expect(done["state"] == .string("completed"), "Workflow did not complete")
      let copy = try book.reconstruct(to: root.appendingPathComponent("copy.sevra"))
      _ = try await service.continueWorkflow(
        workbook: copy, session: copy.authorizeWorkflowExecution(session.runID),
        owner: "explicit inspect", modelDirectory: root)
      let count = await model.count
      try expect(count == 1, "Completed interpretation reran after reconstruction")
      try expect(try copy.verify()["ok"] == .bool(true), "Reconstructed workflow failed integrity")
    } else {
      do {
        _ = try await task.value
        throw SevraError("test", "Late/cancelled model output published")
      } catch let error as SevraError {
        try expect(
          error.code == (mode == "cancel" ? "workflow_fenced" : "cancelled"),
          "Unexpected workflow cancellation error: " + error.code)
      }
      try expect(
        try book.items().filter { $0.category == "record" }.isEmpty,
        "Cancelled interpretation published a Record")
      try expect(
        try book.workflowRun(session.runID)["state"]
          == .string(mode == "cancel" ? "cancelled" : "needs_attention"),
        "Workflow saved the wrong terminal state")
      if mode == "pressure" {
        let unloaded = await model.unloaded
        try expect(unloaded, "Pressure did not release resources after model lease")
      }
    }
    let leased = await model.leased
    try expect(leased == false, "Workflow retained its model lease")
    try expect(try book.verify()["ok"] == .bool(true), "Workflow failed integrity")
  }
  print(
    "PASS workflow model lock release, shared resource exclusion, cancellation/pressure fencing and completed-result inert reconstruction"
  )
}
