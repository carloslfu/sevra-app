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
  /// What `loadedMemoryBytes` reports while started; a check sets it.
  var loaded: UInt64?
  func setLoaded(_ bytes: UInt64?) { loaded = bytes }
  func loadedMemoryBytes() -> UInt64? { loaded }
  func prewarm(
    directory: URL, size: StartSize, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void
  ) async -> Bool {
    switch size {
    case .chosen: events.append("start")
    case .growing: events.append("resizing start")
    case .growingLoaded: events.append("grow only")
    case .atMost(let limit): events.append("start at most \(limit / (1024 * 1024 * 1024)) GiB")
    }
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
    loaded = nil
    return true
  }
  func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, toolScope: InferenceToolScope, citationIDs: [String],
    progress: @escaping @Sendable (String) -> Void
  ) throws -> ContextMeasurement {
    .init(promptTokens: 1000, capacity: 65536, templateIdentity: "prewarm-check")
  }
  /// While set, a request stays in the model until the check clears it.
  var holdRespond = false
  func setHoldRespond(_ hold: Bool) { holdRespond = hold }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    events.append("respond")
    while holdRespond { try? await Task.sleep(nanoseconds: 5_000_000) }
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

  // Memory: a background start needs the smallest engine plus 4 GiB for everything else.
  let gigabyte: UInt64 = 1024 * 1024 * 1024
  func roomAt(_ reclaimable: UInt64?) -> Bool {
    ProductAI.hasRoom(
      forEngineBytes: EngineMemory.choose(reclaimable: reclaimable), reclaimable: reclaimable)
  }
  let smallest = EngineMemory.floor + EngineMemory.headroom
  try expect(roomAt(smallest), "Enough memory was refused.")
  try expect(!roomAt(smallest - 1), "Too little memory was accepted.")
  try expect(!roomAt(nil), "Unknown memory was accepted.")

  // The engine's size: free memory less 4 GiB, in whole GiB, from the floor (8 GiB and the
  // 64 MiB that keeps 64K on Splash 1.7.3) to 20 GiB. Just past the floor's start, whole GiB
  // would round under it, so the floor holds.
  let floor = EngineMemory.floor
  let choices: [(reclaimable: UInt64?, expected: UInt64)] = [
    (nil, floor), (10 * gigabyte, floor), (smallest + 1, floor), (13 * gigabyte - 1, floor),
    (13 * gigabyte, 9 * gigabyte), (16 * gigabyte + gigabyte / 2, 12 * gigabyte),
    (24 * gigabyte - 1, 19 * gigabyte), (24 * gigabyte, 20 * gigabyte), (40 * gigabyte, 20 * gigabyte),
  ]
  for choice in choices {
    let chosen = EngineMemory.choose(reclaimable: choice.reclaimable)
    try expect(
      chosen == choice.expected,
      "\(choice.reclaimable.map { String($0) } ?? "Unknown") bytes free chose \(chosen) bytes.")
  }
  // Only a small engine grows, and only by a step that repays the restart.
  let growth: [(loaded: UInt64, chosen: UInt64, grows: Bool)] = [
    (8, 12, true), (12, 16, true), (12, 15, false), (16, 20, false), (20, 20, false),
  ]
  try expect(
    EngineMemory.grows(loaded: EngineMemory.floor, chosen: 12 * gigabyte),
    "The smallest engine did not grow to 12 GiB.")
  try expect(
    !EngineMemory.grows(loaded: EngineMemory.floor, chosen: 11 * gigabyte),
    "The smallest engine grew by less than a step.")
  for case let (loaded, chosen, grows) in growth {
    try expect(
      EngineMemory.grows(loaded: loaded * gigabyte, chosen: chosen * gigabyte) == grows,
      "\(loaded) to \(chosen) GiB should \(grows ? "" : "not ")grow.")
  }
  // A start resizes only when asked, and a request waits for it like any start.
  let resizing = StartingModel()
  let resizeService = ProductAI(qualifying: resizing)
  await resizeService.prewarm(resizing: true)
  try await waitFor(resizing, "resizing start")
  let afterResize = Task { _ = try? await resizeService.run("hi", workbook: book) }
  try await Task.sleep(nanoseconds: 50_000_000)
  let resizeWaited = await !resizing.events.contains("run")
  try expect(resizeWaited, "A request did not wait for a resizing start.")
  await resizing.letStartFinish()
  await afterResize.value
  let resizeEvents = await resizing.events
  try expect(
    resizeEvents.prefix(4) == ["resizing start", "started", "run", "respond"],
    "A resizing start and a request ran out of order: \(resizeEvents)")

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

/// No model. After memory pressure releases a running engine, it starts again smaller once
/// pressure eases, only while the owner is in the app, and at most once until the owner uses it.
func checkPressureReload(book: Workbook) async throws {
  let gib: UInt64 = 1024 * 1024 * 1024
  let folder = FileManager.default.temporaryDirectory
  func service(
    loaded: UInt64?, host: (@Sendable () async -> URL?)?, settle: Double = 0
  ) async -> (StartingModel, ProductAI) {
    let model = StartingModel()
    await model.letStartFinish()
    await model.setLoaded(loaded)
    let ai = ProductAI(qualifying: model, settleSeconds: settle)
    await ai.setReloadHost(host)
    return (model, ai)
  }
  func eased(_ ai: ProductAI, wait: UInt64 = 100_000_000) async throws {
    await ai.handlePressureEased()
    try await Task.sleep(nanoseconds: wait)
  }
  func reloads(_ model: StartingModel) async -> [String] {
    await model.events.filter { $0 == "start" || $0.hasPrefix("start at most") }
  }
  let present: @Sendable () async -> URL? = { folder }

  // A 20 GiB engine released by pressure starts again at most 16 GiB once pressure eases.
  let (model, ai) = await service(loaded: 20 * gib, host: present)
  _ = await ai.handleMemoryPressure(critical: false)
  try await eased(ai)
  var seen = await reloads(model)
  try expect(seen == ["start at most 16 GiB"], "The reload after pressure was \(seen).")
  // Pressure releasing that reload too waits for the owner instead of cycling.
  await model.setLoaded(16 * gib)
  _ = await ai.handleMemoryPressure(critical: false)
  try await eased(ai)
  seen = await reloads(model)
  try expect(seen.count == 1, "A reload after pressure repeated without the owner: \(seen).")
  // The owner's request allows the next one, smaller again.
  _ = try? await ai.run("hi", workbook: book)
  await model.setLoaded(16 * gib)
  _ = await ai.handleMemoryPressure(critical: false)
  try await eased(ai)
  seen = await reloads(model)
  try expect(
    seen.last == "start at most 12 GiB" && seen.count == 2,
    "After a request, the next reload was \(seen).")

  // No reload: the owner away, no app (the CLI), the smallest engine, an Unload, an idle engine.
  let cases: [(String, UInt64?, (@Sendable () async -> URL?)?, Bool)] = [
    ("owner away", 20 * gib, { nil }, false), ("no app", 20 * gib, nil, false),
    ("8 GiB engine", 8 * gib, present, false), ("Unload", 20 * gib, present, true),
    ("no engine running", nil, present, false),
  ]
  for (name, loaded, host, unload) in cases {
    let (model, ai) = await service(loaded: loaded, host: host)
    if unload { _ = await ai.unload() } else { _ = await ai.handleMemoryPressure(critical: false) }
    try await eased(ai)
    let started = await reloads(model)
    try expect(started.isEmpty, "\(name) still reloaded: \(started).")
  }

  // Pressure rising again before it has stayed normal cancels the reload.
  let (rising, risingAI) = await service(loaded: 20 * gib, host: present, settle: 0.3)
  _ = await risingAI.handleMemoryPressure(critical: false)
  await risingAI.handlePressureEased()
  try await Task.sleep(nanoseconds: 50_000_000)
  _ = await risingAI.handleMemoryPressure(critical: false)
  try await Task.sleep(nanoseconds: 500_000_000)
  var risen = await reloads(rising)
  try expect(risen.isEmpty, "A reload began although pressure rose again: \(risen).")
  // It still waits, and the next ease that lasts starts it.
  try await eased(risingAI, wait: 500_000_000)
  risen = await reloads(rising)
  try expect(risen == ["start at most 16 GiB"], "The reload after renewed pressure was \(risen).")
  // Pressure that eases while a request holds the engine: the release after the request finds
  // pressure normal already and still reloads.
  let (busy, busyAI) = await service(loaded: 20 * gib, host: present)
  await busy.setHoldRespond(true)
  let held = Task { _ = try? await busyAI.run("hi", workbook: book) }
  try await waitFor(busy, "respond")
  let deferred = await busyAI.handleMemoryPressure(critical: false)
  try expect(deferred == .deferred, "Pressure during a request was \(deferred).")
  await busyAI.handlePressureEased()
  await busy.setHoldRespond(false)
  await held.value
  try await Task.sleep(nanoseconds: 100_000_000)
  let afterBusy = await reloads(busy)
  try expect(
    afterBusy == ["start at most 16 GiB"], "Pressure eased during a request reloaded \(afterBusy).")

  // Pressure rising while the app is asked whether the owner is there stops the reload.
  let (asked, askedAI) = await service(loaded: 20 * gib, host: nil)
  await askedAI.setReloadHost { [askedAI] in
    _ = await askedAI.handleMemoryPressure(critical: false)
    return folder
  }
  _ = await askedAI.handleMemoryPressure(critical: false)
  try await eased(askedAI)
  let afterAsked = await reloads(asked)
  try expect(afterAsked.isEmpty, "A reload began under renewed pressure: \(afterAsked).")

  // After a reply, growing never starts an engine that pressure released.
  let (replied, repliedAI) = await service(loaded: nil, host: present)
  await repliedAI.growIfLoaded(modelDirectory: folder)
  await replied.setLoaded(12 * gib)
  await repliedAI.growIfLoaded(modelDirectory: folder)
  try await Task.sleep(nanoseconds: 50_000_000)
  let grown = await replied.events
  try expect(grown == ["grow only", "started"], "Growing after a reply did \(grown).")
  print(
    "PASS pressure reload: once pressure eases, a released engine starts again smaller, only with the owner in the app, once until he uses it, and never after Unload or renewed pressure"
  )
}
