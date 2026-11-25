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
  func prewarm(
    directory: URL, cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) async -> Bool {
    events.append("start")
    progress("Preparing local AI · 2 of 5 steps")
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
  let seen = ProgressSeen()
  let request = Task {
    _ = try? await service.run("hi", workbook: book, progress: { seen.add($0) })
  }
  try await Task.sleep(nanoseconds: 100_000_000)
  let waited = await !model.events.contains("run")
  try expect(waited, "A request did not wait for the start under way.")
  // The waiting request is told where the start is, not left on a bare "Preparing".
  try expect(
    seen.values.contains("Preparing local AI · 2 of 5 steps"),
    "The waiting request saw none of the start's progress: \(seen.values)")
  await model.letStartFinish()
  await request.value
  let events = await model.events
  try expect(
    events.prefix(4) == ["start", "started", "run", "respond"],
    "Prewarm and the request ran out of order: \(events)")

  // Stop ends a request's wait at once and leaves the start running for the next request.
  let stopping = StartingModel()
  let stopService = ProductAI(qualifying: stopping)
  await stopService.prewarm()
  try await waitFor(stopping, "start")
  let stop = Cancellation()
  let outcome = ProgressSeen()
  Task {
    do {
      _ = try await stopService.run("hi", workbook: book, cancellation: stop)
      outcome.add("returned")
    } catch { outcome.add((error as? SevraError)?.code ?? "other") }
  }
  try await Task.sleep(nanoseconds: 50_000_000)
  stop.cancel()
  // A stopped request ends promptly, not when the start does.
  for _ in 0..<200 where outcome.values.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
  let stoppedCode = outcome.values.first
  let stopEvents = await stopping.events
  try expect(stoppedCode == "cancelled", "Stop during the wait ended with \(String(describing: stoppedCode)).")
  try expect(
    stopEvents == ["start"], "Stop during the wait reached the model or ended the start: \(stopEvents)")
  await stopping.letStartFinish()
  try await waitFor(stopping, "started")

  // Memory: a start needs the engine's budget plus 4 GiB for everything else.
  let gigabyte: UInt64 = 1024 * 1024 * 1024
  try expect(ProductAI.hasRoom(forEngineBytes: 12 * gigabyte, reclaimable: 16 * gigabyte), "Enough memory was refused.")
  try expect(!ProductAI.hasRoom(forEngineBytes: 12 * gigabyte, reclaimable: 16 * gigabyte - 1), "Too little memory was accepted.")
  try expect(!ProductAI.hasRoom(forEngineBytes: 12 * gigabyte, reclaimable: nil), "Unknown memory was accepted.")

  // The engine's size: the whole model on a 48 GiB Mac with 22 + 4 GiB free, else the streamed store.
  let choices: [(physical: UInt64, reclaimable: UInt64?, expected: UInt64, case: String)] = [
    (48 * gigabyte, 26 * gigabyte, EngineMemory.resident, "48 GiB Mac with room"),
    (48 * gigabyte, 26 * gigabyte - 1, EngineMemory.streamed, "48 GiB Mac just short of room"),
    (36 * gigabyte, 30 * gigabyte, EngineMemory.streamed, "36 GiB Mac"),
    (48 * gigabyte, nil, EngineMemory.streamed, "unknown free memory"),
  ]
  for choice in choices {
    let chosen = EngineMemory.choose(physicalMemory: choice.physical, reclaimable: choice.reclaimable)
    try expect(chosen == choice.expected, "The \(choice.case) chose \(chosen / gigabyte) GiB.")
  }

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
  print(
    "PASS prewarm: a request waits for a start under way and sees its progress, Stop ends the wait and leaves the start, a start needs memory to spare, and unloading cancels it first"
  )
}

private final class ProgressSeen: @unchecked Sendable {
  private let lock = NSLock()
  private var seen: [String] = []
  func add(_ value: String) {
    lock.lock()
    seen.append(value)
    lock.unlock()
  }
  var values: [String] {
    lock.lock()
    defer { lock.unlock() }
    return seen
  }
}


/// A model that names work: it answers once released, or stops when cancelled.
private actor NamingModel: WorkbookInference {
  let identity = "Synthetic naming qualification"
  var lastMetrics: Value { .null }
  var supportsCompaction: Bool { false }
  private(set) var events: [String] = []
  private var answer = false
  func release() { answer = true }
  func titles(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation
  ) async throws -> WorkTitlesReply? {
    events.append("titles")
    while !answer && !cancellation.isCancelled { try? await Task.sleep(nanoseconds: 5_000_000) }
    events.append(cancellation.isCancelled ? "titles cancelled" : "titled")
    return WorkTitlesReply(chat: "\"Brass bolt comparison.\"", workbook: "Supplier quotes")
  }
  func beginRun() { events.append("run") }
  func endRun() {}
  func releaseResources() -> Bool { true }
  func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, toolScope: InferenceToolScope, citationIDs: [String],
    progress: @escaping @Sendable (String) -> Void
  ) throws -> ContextMeasurement {
    .init(promptTokens: 1000, capacity: 65536, templateIdentity: "naming-check")
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

/// No model. Naming runs after the first and third replies on names that are still Sevra's,
/// cleans what the model wrote, and stops at once for a request.
func checkNaming(at root: URL) async throws {
  let url = root.appendingPathComponent("Naming.sevra")
  let book = try Workbook.create(at: url, title: "Untitled", automaticTitle: true)
  let chat = try book.chats()[0].id
  _ = try book.addMessage("hi", role: "user", conversation: chat)
  let model = NamingModel()
  let service = ProductAI(qualifying: model)
  let none = await service.nameWork(book, conversation: chat)
  let untouched = await model.events.isEmpty
  try expect(!none && untouched, "Named a chat with no reply yet.")
  _ = try book.addMessage("Hello.", role: "assistant", conversation: chat)

  // A request stops naming before it uses the model.
  let naming = Task { await service.nameWork(book, conversation: chat) }
  for _ in 0..<200 where !(await model.events.contains("titles")) {
    try await Task.sleep(nanoseconds: 5_000_000)
  }
  _ = try? await service.run("next", workbook: book, conversation: chat)
  let stopped = await naming.value
  let order = await model.events
  try expect(!stopped, "A stopped naming still changed a name.")
  try expect(
    order.prefix(4) == ["run", "titles", "titles cancelled", "run"],
    "A request did not stop naming first: \(order)")
  try expect(book.title == "Untitled", "A stopped naming renamed the workbook.")

  await model.release()
  let named = await service.nameWork(book, conversation: chat)
  try expect(named, "Naming after the first reply changed nothing.")
  try expect(
    try book.chats()[0].title == "Brass bolt comparison" && book.title == "Supplier quotes",
    "Names were not applied or cleaned: \(try book.chats()[0].title), \(book.title)")
  // After the third reply a name Sevra gave stays.
  for turn in 2...4 {
    _ = try book.addMessage("More \(turn)?", role: "user", conversation: chat)
    _ = try book.addMessage("Yes.", role: "assistant", conversation: chat)
  }
  let before = await model.events.count
  let fourth = await service.nameWork(book, conversation: chat)
  let after = await model.events.count
  try expect(!fourth && before == after, "Named again after the fourth reply.")
  // A stand-in name still gets a real one after a later reply.
  let late = try Workbook.create(
    at: root.appendingPathComponent("Late.sevra"), title: "Untitled", automaticTitle: true)
  let lateChat = try late.chats()[0].id
  for turn in 1...4 {
    _ = try late.addMessage("Question \(turn)", role: "user", conversation: lateChat)
    _ = try late.addMessage("Answer.", role: "assistant", conversation: lateChat)
  }
  let lateNamed = await service.nameWork(late, conversation: lateChat)
  try expect(
    lateNamed && late.title == "Supplier quotes" && !late.titleIsPlaceholder,
    "A stand-in name after the third reply was not replaced: \(late.title)")
  try expect(WorkTitles.clean("New chat") == nil && WorkTitles.clean("") == nil, "Kept a placeholder.")
  try expect(WorkTitles.clean("brass bolt quotes") == "Brass bolt quotes", "Left a lowercase title.")
  print(
    "PASS naming: stand-in names after any reply, given names improved only in the first three replies, cleaned, and stopped at once by a request without renaming"
  )
}
