import Foundation
import SevraAI
import SevraCore
import SevraProduct

/// A model whose start waits until the check lets it finish or the start is cancelled.
private actor StartingModel: WorkbookInference {
  let identity = "Synthetic prewarm qualification"
  var lastMetrics: Value { .null }
  var supportsCompaction: Bool { false }
  private(set) var events: [String] = []
  private var finishStart = false
  func prewarm(directory: URL, cancellation: Cancellation) async -> Bool {
    events.append("start")
    while !finishStart && !cancellation.isCancelled {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
    events.append(cancellation.isCancelled ? "start cancelled" : "started")
    return !cancellation.isCancelled
  }
  func letStartFinish() { finishStart = true }
  func beginRun() { events.append("run") }
  func endRun() {}
  func releaseResources() -> Bool {
    events.append("release")
    return true
  }
  func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, toolScope: InferenceToolScope, citationIDs: [String],
    progress: @escaping @Sendable (String) -> Void
  ) throws -> ContextMeasurement {
    .init(promptTokens: 1000, capacity: 65536, templateIdentity: "prewarm-check")
  }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    events.append("respond")
    throw SevraError("check_stop", "The request reached the model.")
  }
}

private func waitFor(_ model: StartingModel, _ event: String) async throws {
  for _ in 0..<400 {
    if await model.events.contains(event) { return }
    try await Task.sleep(nanoseconds: 5_000_000)
  }
  throw SevraError("prewarm_check", "The model never reported: " + event)
}

/// No model. Starting the engine ahead of Send must not race a request or an unload: a request
/// waits for a start under way and then uses it, and unloading stops a start first.
func checkPrewarm(book: Workbook) async throws {
  let model = StartingModel()
  let service = ProductAI(qualifying: model)
  await service.prewarm()
  try await waitFor(model, "start")
  await service.prewarm()  // A second call while starting does nothing.
  let request = Task { _ = try? await service.run("hi", workbook: book) }
  try await Task.sleep(nanoseconds: 50_000_000)
  let waited = await !model.events.contains("run")
  try expect(waited, "A request did not wait for the start under way.")
  await model.letStartFinish()
  await request.value
  let events = await model.events
  try expect(
    events.prefix(4) == ["start", "started", "run", "respond"],
    "Prewarm and the request ran out of order: \(events)")

  let unloading = StartingModel()
  let other = ProductAI(qualifying: unloading)
  await other.prewarm()
  try await waitFor(unloading, "start")
  let unloaded = await other.unload()
  let after = await unloading.events
  try expect(unloaded, "Unloading during a start failed.")
  try expect(
    after == ["start", "start cancelled", "release"],
    "Unloading did not stop the start first: \(after)")
  print("PASS prewarm: a request waits for a start under way, and unloading cancels it first")
}
