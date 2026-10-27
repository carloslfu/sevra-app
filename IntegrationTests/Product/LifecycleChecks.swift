import Foundation
import SevraAI
import SevraCore
import SevraProduct

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
  if try !condition() { throw SevraError("lifecycle_check", message) }
}

actor PausedModel: WorkbookInference {
  let identity = "Synthetic lifecycle qualification"
  var lastMetrics: Value { .null }
  private var leased = false
  private var events: [String] = []
  private var calls = 0
  private var continuation: CheckedContinuation<Void, Never>?
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?
  private var releaseWaiting: [CheckedContinuation<Void, Never>] = []
  private var failRelease = false
  private var pause = true
  private let holdRelease: Bool
  init(holdRelease: Bool = false) { self.holdRelease = holdRelease }
  func beginRun() throws {
    try expect(!leased, "Overlapping model lease")
    leased = true
    calls = 0
    events.append("begin")
  }
  func endRun() {
    leased = false
    events.append("end")
  }
  func releaseResources() async -> Bool {
    events.append(leased ? "invalid-unload-during-lease" : "unload")
    if holdRelease {
      await withCheckedContinuation { continuation in
        releaseContinuation = continuation
        releaseWaiting.forEach { $0.resume() }
        releaseWaiting = []
      }
    }
    return !leased && !failRelease
  }
  func setReleaseFailure(_ value: Bool) { failRelease = value }
  func setPause(_ value: Bool) { pause = value }
  func snapshot() -> [String] { events }
  func waitForResponse() async {
    if continuation != nil { return }
    await withCheckedContinuation { waiting.append($0) }
  }
  func resume() {
    continuation?.resume()
    continuation = nil
  }
  func waitForRelease() async {
    if releaseContinuation != nil { return }
    await withCheckedContinuation { releaseWaiting.append($0) }
  }
  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    calls += 1
    events.append("respond")
    if calls == 1 {
      return NativeReply(
        text: "",
        calls: [
          .init(
            id: "save", name: "save_space",
            inputJSON:
              "{\"title\":\"Memory check\",\"definition\":{\"version\":1,\"components\":[{\"id\":\"note\",\"type\":\"text\",\"title\":\"Memory check\",\"text\":\"Saved before pressure.\"}]}}"
          )
        ])
    }
    if pause {
      await withCheckedContinuation { continuation in
        self.continuation = continuation
        waiting.forEach { $0.resume() }
        waiting = []
      }
    }
    try cancellation.check()
    return NativeReply(
      text: "",
      calls: [
        .init(
          id: "finish", name: "finish",
          inputJSON:
            "{\"answer\":\"Saved the Memory check space.\",\"basis\":\"completed_action\",\"citations\":[]}"
        )
      ])
  }
}

@main struct LifecycleChecks {
  static func main() async {
    do {
      #if !SEVRA_NATIVE_CANDIDATE
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--baseline" {
          try await baselinePressureChecks(modelFolder: CommandLine.arguments[2])
          print("PASS baseline product lifecycle checks")
          return
        }
      #endif
      if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--native" {
        try await nativePressureChecks(
          modelsRoot: CommandLine.arguments[2], packagedBin: CommandLine.arguments[3])
      } else {
        try expect(
          CommandLine.arguments.count == 1,
          "Usage: sevra-product-checks [--native MODELS_ROOT PACKAGED_BIN]")
        try await syntheticChecks()
      }
      print("PASS product lifecycle checks")
    } catch {
      fputs("\(error)\n", stderr)
      exit(1)
    }
  }
  static func syntheticChecks() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sevra-pressure-" + identifier())
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    func book(_ name: String) throws -> Workbook {
      let url = root.appendingPathComponent(name + ".sevra")
      _ = try Demo.create(at: url)
      return try Workbook(url)
    }
    let criticalBook = try book("critical")
    let criticalModel = PausedModel()
    let critical = ProductAI(qualifying: criticalModel)
    let token = Cancellation()
    let criticalJob = Task {
      try await critical.run(
        "Save a Memory check space.", workbook: criticalBook, cancellation: token)
    }
    await criticalModel.waitForResponse()
    let beforePressure = try criticalBook.items()
    let beforeSpaces = try criticalBook.spaces()
    try expect(
      beforeSpaces.contains { $0.title == "Memory check" }, "Fixture did not save before pressure")
    let ordinaryUnload = await critical.unload()
    try expect(!ordinaryUnload && !token.isCancelled, "Ordinary unload interrupted work")
    let pressureResponse = await critical.handleMemoryPressure(critical: true)
    try expect(
      pressureResponse == .stopping && token.isCancelled, "Critical pressure did not cancel")
    let beforeStopEvents = await criticalModel.snapshot()
    try expect(!beforeStopEvents.contains("unload"), "Release ran before operation unwound")
    do {
      _ = try await critical.run("Overlapping request", workbook: criticalBook)
      throw SevraError("test", "Concurrent request was accepted")
    } catch let error as SevraError {
      try expect(error.code == "busy", "Unexpected overlap refusal")
    }
    await criticalModel.resume()
    do {
      _ = try await criticalJob.value
      throw SevraError("test", "Critical pressure returned success")
    } catch let error as SevraError {
      try expect(
        error.code == "cancelled" && error.message.contains("low on memory"), "Pressure reason lost"
      )
    }
    let events = await criticalModel.snapshot()
    try expect(Array(events.suffix(2)) == ["end", "unload"], "Model released before endRun")
    try expect(
      try criticalBook.items() == beforePressure
        && encoded(criticalBook.spaces()) == encoded(beforeSpaces), "Pressure lost completed data")
    try expect(
      try criticalBook.agentRuns().first?["status"].text == "cancelled",
      "Interrupted job was recorded complete")
    try expect(
      try criticalBook.messages().last?.body.contains("low on memory") == true,
      "Saved history lost stop reason")
    try expect(
      try criticalBook.verify()["ok"] == .bool(true), "Interrupted workbook failed integrity")
    print(
      "PASS critical pressure cancels, preserves saved work, records the reason and releases only after endRun"
    )

    let warningBook = try book("warning")
    let warningModel = PausedModel(holdRelease: true)
    let warning = ProductAI(qualifying: warningModel)
    let warningToken = Cancellation()
    let warningJob = Task {
      try await warning.run(
        "Save a Memory check space.", workbook: warningBook, cancellation: warningToken)
    }
    await warningModel.waitForResponse()
    let warningResponse = await warning.handleMemoryPressure(critical: false)
    try expect(warningResponse == .deferred && !warningToken.isCancelled, "Warning cancelled work")
    await warningModel.resume()
    await warningModel.waitForRelease()
    do {
      _ = try await warning.run("Start too early", workbook: warningBook)
      throw SevraError("test", "Job started while release was pending")
    } catch let error as SevraError {
      try expect(error.code == "busy", "Unexpected release barrier refusal")
    }
    await warningModel.release()
    let warningResult = try await warningJob.value
    try expect(
      warningResult.state == "complete" && !warningToken.isCancelled,
      "Warning interrupted successful completion")
    print("PASS warning lets work complete and keeps new requests blocked until release finishes")

    let retryBook = try book("retry")
    let retryModel = PausedModel()
    await retryModel.setReleaseFailure(true)
    let retry = ProductAI(qualifying: retryModel)
    let retryJob = Task { try await retry.run("Save a Memory check space.", workbook: retryBook) }
    await retryModel.waitForResponse()
    _ = await retry.handleMemoryPressure(critical: false)
    await retryModel.resume()
    _ = try await retryJob.value
    let revision = try retryBook.revision()
    do {
      _ = try await retry.run("Cannot start yet", workbook: retryBook)
      throw SevraError("test", "Reused model after failed release")
    } catch let error as SevraError {
      try expect(error.code == "model_release", "Missing failed-release refusal")
    }
    try expect(try retryBook.revision() == revision, "Refused request changed workbook")
    await retryModel.setReleaseFailure(false)
    await retryModel.setPause(false)
    let recovered = try await retry.run("Save a Memory check space.", workbook: retryBook)
    try expect(recovered.state == "complete", "Explicit new request did not recover")
    let idlePressure = await retry.handleMemoryPressure(critical: true)
    try expect(idlePressure == .released, "Idle pressure did not release")
    print(
      "PASS failed release prevents reuse; a later explicit request recovers after successful release"
    )

    let setupBook = try book("setup-release")
    let setupModel = PausedModel()
    await setupModel.setReleaseFailure(true)
    let setupService = ProductAI(qualifying: setupModel)
    do {
      try await setupService.setup(cancellation: Cancellation(), progress: { _ in })
      throw SevraError("test", "Setup ignored failed release")
    } catch let error as SevraError {
      try expect(error.code == "busy", "Unexpected setup release refusal")
    }
    let setupRevision = try setupBook.revision()
    do {
      _ = try await setupService.run("Cannot reuse after setup failure", workbook: setupBook)
      throw SevraError("test", "Setup failure allowed model reuse")
    } catch let error as SevraError {
      try expect(error.code == "model_release", "Setup lost pending release")
    }
    try expect(
      try setupBook.revision() == setupRevision, "Refused setup follow-up changed workbook")
    print(
      "PASS setup release failure prevents subsequent model reuse without writing workbook data")

    let parent = Cancellation()
    let child = Cancellation(parent: parent)
    parent.cancel(reason: "First stop reason")
    parent.cancel(reason: "Later reason")
    do {
      try child.check()
      throw SevraError("test", "Child ignored cancellation")
    } catch let error as SevraError {
      try expect(error.message == "First stop reason", "Parent or first reason lost")
    }
    print("PASS cancellation preserves its first cause through child operations")
  }
}
