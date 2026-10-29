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
  for mode in [
    "complete", "cancel", "pressure", "automation-complete", "automation-pause",
    "automation-before-load", "automation-after-load",
  ] {
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
    let session: WorkflowExecutionSession
    let authority: AutomationExecutionSession?
    if mode.hasPrefix("automation-") {
      let automation = try book.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("automation"), "title": .string("Synthetic local-AI draft"),
          "description": .string("Permission boundary"), "parameters": .array([]),
          "payload": .object([
            "policy": .string("calendar-drafts-v1"),
            "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow.id)]),
            "arguments": .object(["evidence": .string(source.id)]),
            "schedule": .object([
              "policy": .string("native-calendar-v1"), "timeZone": .string("UTC"),
              "hour": .number(9), "minute": .number(0),
              "recurrence": .object(["kind": .string("daily")]),
            ]),
          ]),
        ]))
      let start = ISO8601DateFormatter().date(from: "2026-10-01T08:00:00Z")!
      let due = start.addingTimeInterval(3600)
      authority = try book.authorizeAutomationExecution(
        automation.id, expectedGeneration: 0, after: start, allowAI: true, token: "authorize")
      _ = try book.planAutomationOccurrences(authority!.planning, through: due, token: "plan")
      let dispatched = try book.dispatchAutomationOccurrence(
        authority!, observedAt: due, token: "dispatch")
      session = try book.authorizeAutomationWorkflowExecution(
        authority!, runID: dispatched["runID"].text)
    } else {
      authority = nil
      let run = try book.startWorkflow(
        workflow.id, arguments: .object(["evidence": .string(source.id)]), token: "start")
      session = try book.authorizeWorkflowExecution(run["id"].text)
    }
    let model = PausedInterpretation()
    if ["automation-before-load", "automation-after-load"].contains(mode) {
      var acquisitions = 0
      if mode == "automation-before-load" {
        _ = try book.pauseAutomation(
          authority!.planning.activationID, expectedGeneration: 1, token: "pause")
      }
      do {
        _ = try await WorkflowCoordinator.run(
          workbook: book, session: session, owner: "revoked", directory: root,
          cancellation: .init(), progress: { _ in },
          model: {
            acquisitions += 1
            _ = try book.pauseAutomation(
              authority!.planning.activationID, expectedGeneration: 1, token: "pause")
            return model
          })
        throw SevraError("test", "Revoked automation acquired inference")
      } catch let error as SevraError {
        try expect(error.code == "automation_authority", "Unexpected revoked-model boundary")
      }
      let leased = await model.leased
      let count = await model.count
      try expect(
        acquisitions == (mode == "automation-before-load" ? 0 : 1) && !leased && count == 0,
        "Revoked automation began inference")
      _ = try book.verify()
      continue
    }
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
    } else if mode == "automation-pause" {
      _ = try second.pauseAutomation(
        authority!.planning.activationID, expectedGeneration: 1, token: "pause")
    } else if mode == "pressure" {
      let pressure = await service.handleMemoryPressure(critical: true)
      try expect(
        pressure == .stopping,
        "Critical pressure did not stop workflow")
    }
    await model.resume()
    if ["complete", "automation-complete"].contains(mode) {
      let done = try await task.value
      try expect(done["state"] == .string("completed"), "Workflow did not complete")
      let copy = try book.reconstruct(to: root.appendingPathComponent(mode + "-copy.sevra"))
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
          error.code
            == (mode == "cancel"
              ? "workflow_fenced"
              : mode == "automation-pause" ? "automation_authority" : "cancelled"),
          "Unexpected workflow cancellation error: " + error.code)
      }
      try expect(
        try book.items().filter { $0.category == "record" }.isEmpty,
        "Cancelled interpretation published a Record")
      try expect(
        try book.workflowRun(session.runID)["state"]
          == .string(
            mode == "cancel"
              ? "cancelled" : mode == "automation-pause" ? "queued" : "needs_attention"),
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
    "PASS automation revocation before model acquisition, before lease, during inference, original provenance and explicit manual continuation"
  )
  print(
    "PASS workflow model lock release, shared resource exclusion, cancellation/pressure fencing and completed-result inert reconstruction"
  )
}
