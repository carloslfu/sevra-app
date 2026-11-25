import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash

/// One application model, shared by the native UI and CLI.
public actor ProductAI {
  public static let shared = ProductAI()
  private var active = false
  private var activeCancellation: Cancellation?
  private var releaseRequested = false
  private var model: (any WorkbookInference)?
  private var pressureSource: DispatchSourceMemoryPressure?
  private let observesSystemPressure: Bool
  private var prewarming: Task<Void, Never>?
  /// The engine's memory budget, known once its configuration has been read.
  private var engineBytes: UInt64?
  private var prewarmCancellation: Cancellation?
  /// Naming the work after a reply. Any request stops it first, so it never delays one.
  private var naming: Task<Bool, Never>?
  private var namingCancellation: Cancellation?
  /// The start's progress, for a request that comes to wait for it.
  private let prewarmProgress = ProgressRelay()

  private init() {
    observesSystemPressure = true
  }
  /// Internal qualification seam, shared with the workbook agent's synthetic and native checks.
  package init(qualifying model: any WorkbookInference) {
    self.model = model
    observesSystemPressure = false
  }

  deinit {
    pressureSource?.cancel()
    pressureSource?.setEventHandler(handler: nil)
  }

  private func observeMemoryPressure() {
    guard observesSystemPressure, pressureSource == nil else { return }
    let source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.warning, .critical], queue: .global(qos: .utility))
    source.setEventHandler { [weak self] in
      let critical = source.data.contains(.critical)
      Task { await self?.handleMemoryPressure(critical: critical) }
    }
    pressureSource = source
    source.resume()
  }

  public enum PressureResponse: String, Sendable {
    case released, deferred, stopping, releasePending
  }
  public static let name = "Local AI"
  public static let detail = "Qwen3.6 35B · Splash · DFlash 2"
  public static let revision = "splash-1.7.2"
  public static let preferenceKey = "nativeModelsRoot"
  public static var defaultDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/Sevra/Models")
  }
  public static var downloadBytes: Int64 {
    guard let pack = try? SplashModelPack.selected() else { return 0 }
    return (pack.target.files + pack.draft.files).reduce(0) { $0 + $1.bytes }
  }

  public static func checkResources(validateMetal: Bool = true) async throws -> Value {
    try require(
      FileManager.default.isExecutableFile(atPath: ExtractionWorker.bundledExecutable.path),
      "resources", "The installed document extractor is missing.")
    let result = try await Task.detached {
      try NativeProductResources.check(validateMetal: validateMetal)
    }.value
    var fields = result.object
    fields["extractionWorker"] = .bool(true)
    return .object(fields)
  }

  /// `sevra header make` and `sevra header status`.
  public static func makeHeader(
    output: URL, modelsRoot: URL = ProductAI.defaultDirectory,
    progress: @escaping @Sendable (String) -> Void
  ) async throws -> Value {
    try await Task.detached(priority: .userInitiated) {
      try NativeProductResources.makeHeader(
        output: output, modelsRoot: modelsRoot, progress: progress)
    }.value
  }
  public static func headerStatus(at location: URL?) throws -> Value {
    guard let location else { return try NativeProductResources.headerState().report }
    return PromptHeader.state(at: location, identity: try NativeProductResources.headerIdentity())
      .report
  }

  /// Presence is a quick UI hint. Setup and every new native session perform
  /// verification; this never claims that file existence proves usable weights.
  public func installed(at directory: URL = ProductAI.defaultDirectory) async -> Bool {
    guard let pack = try? SplashModelPack.selected() else { return false }
    return FileManager.default.fileExists(
      atPath: directory.appendingPathComponent(pack.name + "/model.json").path)
  }

  public func setup(
    at directory: URL = ProductAI.defaultDirectory, reusing source: URL? = nil,
    cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) async throws {
    try await perform(cancellation: cancellation) {
      let released = await model?.releaseResources() ?? true
      releaseRequested = !released
      try require(released, "busy", "The model has not stopped yet. Retry setup.")
      try await Task.detached(priority: .userInitiated) {
        let updates = SetupProgress(progress)
        _ = try SplashModelSetup.install(
          modelsRoot: directory, reusingTarget: source,
          reusingDraft: source?.appendingPathComponent("dflash"),
          cancelled: { cancellation.isCancelled || cancellation.isExpired },
          progress: updates.receive)
        try cancellation.check()
      }.value
    }
  }

  /// Starts the local engine as soon as a window opens, so the first request does not wait for
  /// it. Nothing is sent to the model. It does nothing while the model is in use, already
  /// starting, not set up, held by another process, or when this Mac lacks the memory to hold it
  /// with room to spare; the next request then starts it, or reports why it cannot. The engine
  /// follows the ordinary idle timer and memory-pressure release.
  public func prewarm(modelDirectory: URL = ProductAI.defaultDirectory) {
    guard !active, prewarming == nil, naming == nil, !releaseRequested else { return }
    if model == nil {
      guard let pack = try? SplashModelPack.selected(),
        FileManager.default.fileExists(
          atPath: modelDirectory.appendingPathComponent(pack.name + "/model.json").path),
        let configuration = try? NativeProductResources.configuration(modelsRoot: modelDirectory)
      else { return }
      engineBytes = configuration.memoryBytes
      model = NativeWorkbookModel(configuration: configuration)
    }
    guard let model else { return }
    // A loaded engine holds its memory already, so this can only decline a start that is not
    // needed; a start after the idle release is checked like the first.
    if observesSystemPressure, let engineBytes, !Self.hasRoom(forEngineBytes: engineBytes) {
      return
    }
    observeMemoryPressure()
    let cancellation = Cancellation()
    prewarmCancellation = cancellation
    prewarmProgress.reset()
    let relay = prewarmProgress
    ChatTiming.beginBackground("prewarm")
    prewarming = Task { [weak self] in
      let started = await model.prewarm(
        directory: modelDirectory, cancellation: cancellation, progress: relay.send)
      ChatTiming.endBackground("prewarm", outcome: started ? "started" : "not_started")
      await self?.prewarmEnded()
    }
  }
  private func prewarmEnded() {
    prewarming = nil
    prewarmCancellation = nil
  }
  /// A request waits for a start already under way, since it needs the engine too, and is told
  /// how far it has come. Its own Stop ends the wait and leaves the start running for the next
  /// request. Unloading and memory pressure stop the start first.
  private func settlePrewarm(
    cancelling: Bool, request: Cancellation? = nil,
    progress: (@Sendable (String) -> Void)? = nil
  ) async {
    guard let task = prewarming else { return }
    if cancelling { prewarmCancellation?.cancel() }
    guard let request else {
      await ChatTiming.asyncSpan("product.wait_for_prewarm") { await task.value }
      return
    }
    prewarmProgress.listen(progress)
    defer { prewarmProgress.listen(nil) }
    await ChatTiming.asyncSpan("product.wait_for_prewarm") {
      // The start clears `prewarming` when it ends; the actor runs that while this sleeps.
      while prewarming == task, !request.isCancelled, !request.isExpired {
        try? await Task.sleep(nanoseconds: 50_000_000)
      }
    }
  }

  /// Whether this Mac can take the engine now and keep several gigabytes for everything else:
  /// free, inactive, purgeable and speculative memory, which macOS gives back without swapping.
  /// A load past that would push other apps into swap, so the start waits for Send instead.
  package static func hasRoom(
    forEngineBytes engine: UInt64, reclaimable: UInt64? = ProductAI.reclaimableBytes()
  ) -> Bool {
    guard let reclaimable else { return false }
    return reclaimable >= engine + 6 * 1024 * 1024 * 1024
  }
  static func reclaimableBytes() -> UInt64? {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    let pages =
      UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.purgeable_count)
      + UInt64(stats.speculative_count)
    return pages * UInt64(vm_kernel_page_size)
  }

  /// Ordinary user unload does not interrupt an active job. Exiting calls this too: the inference
  /// lock ends with the process, so the helper has to stop first or another process could load
  /// the model while this one still holds the memory.
  @discardableResult public func unload() async -> Bool {
    await settleNaming()
    await settlePrewarm(cancelling: true)
    guard !active else { return false }
    active = true
    let released = await model?.releaseResources() ?? true
    releaseRequested = !released
    active = false
    return released
  }

  /// For exiting, once a running job has been told to stop.
  @discardableResult public func unload(waitingSeconds seconds: TimeInterval) async -> Bool {
    let giveUp = ProcessInfo.processInfo.systemUptime + seconds
    while active, ProcessInfo.processInfo.systemUptime < giveUp {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return await unload()
  }

  /// Warnings defer release until the current transaction/job finishes. Critical
  /// pressure reaches the existing cancellation path, then releases after endRun.
  @discardableResult public func handleMemoryPressure(critical: Bool) async -> PressureResponse {
    if active {
      releaseRequested = true
      if critical, let cancellation = activeCancellation {
        cancellation.cancel(
          reason:
            "Local AI stopped because this Mac is low on memory. Completed workbook changes are saved. Close other apps and try again."
        )
        return .stopping
      }
      return .deferred
    }
    return await unload() ? .released : .releasePending
  }

  private func perform<T>(
    cancellation: Cancellation, progress: (@Sendable (String) -> Void)? = nil,
    operation: () async throws -> T
  ) async throws -> T {
    await settleNaming()
    await settlePrewarm(cancelling: false, request: cancellation, progress: progress)
    try cancellation.check()
    try require(!active, "busy", "Sevra is already using its local model.")
    active = true
    activeCancellation = cancellation
    observeMemoryPressure()
    // If the prior helper could not be reaped, no new operation may reuse it.
    if releaseRequested {
      let released = await model?.releaseResources() ?? true
      releaseRequested = !released
      if !released {
        activeCancellation = nil
        active = false
        throw SevraError(
          "model_release", "The previous local model has not stopped yet. Retry after it finishes.")
      }
    }
    do {
      try cancellation.check()
      let result = try await operation()
      await finishOperation()
      return result
    } catch {
      await finishOperation()
      if cancellation.isCancelled { try cancellation.check() }
      throw error
    }
  }

  private func finishOperation() async {
    activeCancellation = nil
    if releaseRequested {
      let released = await model?.releaseResources() ?? true
      releaseRequested = !released
    }
    active = false
  }

  /// Names a chat and its workbook from what was said, when Sevra still names them: after the
  /// first reply and the third. Runs on the engine the reply left running, never loads it, and
  /// stops at once for any request. True when a name changed.
  public func nameWork(
    _ workbook: Workbook, conversation: String,
    modelDirectory: URL = ProductAI.defaultDirectory
  ) async -> Bool {
    func skip(_ reason: String) -> Bool {
      ChatTiming.beginBackground("naming")
      ChatTiming.endBackground("naming", outcome: "skipped: " + reason)
      return false
    }
    if active { return skip("model in use") }
    if naming != nil { return skip("already naming") }
    if prewarming != nil { return skip("engine starting") }
    if releaseRequested { return skip("release pending") }
    guard let model else { return skip("no model") }
    let plan: WorkTitles.Plan
    do {
      guard let planned = try WorkTitles.plan(workbook, conversation: conversation) else {
        return skip("nothing to name")
      }
      plan = planned
    } catch { return skip("plan failed: " + error.localizedDescription) }
    let cancellation = Cancellation()
    namingCancellation = cancellation
    ChatTiming.beginBackground("naming")
    let task = Task<Bool, Never> {
      // The outcome goes to the debug timing log, so a name that did not change says why.
      var outcome = "not_started"
      defer { ChatTiming.endBackground("naming", outcome: outcome) }
      do {
        try await model.beginRun()
      } catch {
        outcome = "busy"
        return false
      }
      let reply: WorkTitlesReply?
      do {
        reply = try await model.titles(
          messages: plan.messages, directory: modelDirectory, cancellation: cancellation)
      } catch {
        await model.endRun()
        outcome = cancellation.isCancelled ? "cancelled" : "failed: " + error.localizedDescription
        return false
      }
      await model.endRun()
      guard let reply, !cancellation.isCancelled else {
        outcome = cancellation.isCancelled ? "cancelled" : "no_engine"
        return false
      }
      do {
        let changed = try WorkTitles.apply(reply, plan: plan, to: workbook)
        outcome = (changed ? "named" : "kept") + " chat=\(reply.chat) workbook=\(reply.workbook)"
        return changed
      } catch {
        outcome = "not_saved: " + error.localizedDescription
        return false
      }
    }
    naming = task
    let changed = await task.value
    if naming == task {
      naming = nil
      namingCancellation = nil
    }
    return changed
  }
  private func settleNaming() async {
    guard let task = naming else { return }
    namingCancellation?.cancel()
    _ = await task.value
    if naming == task {
      naming = nil
      namingCancellation = nil
    }
  }

  private func workflowModel(directory: URL) throws -> any WorkbookInference {
    if model == nil {
      model = NativeWorkbookModel(
        configuration: try NativeProductResources.configuration(modelsRoot: directory))
    }
    guard let model else { throw SevraError("model", "The local model is unavailable.") }
    return model
  }

  public func continueWorkflow(
    workbook: Workbook, session: WorkflowExecutionSession, owner: String,
    modelDirectory: URL = ProductAI.defaultDirectory, cancellation: Cancellation = .init(),
    progress: @escaping @Sendable (String) -> Void = { _ in }
  ) async throws -> Value {
    try await perform(cancellation: cancellation, progress: progress) {
      try await WorkflowCoordinator.run(
        workbook: workbook, session: session, owner: owner, directory: modelDirectory,
        cancellation: cancellation, progress: progress,
        model: { try self.workflowModel(directory: modelDirectory) })
    }
  }

  public func run(
    _ prompt: String, workbook: Workbook, conversation: String, context: String = "",
    modelDirectory: URL = ProductAI.defaultDirectory, cancellation: Cancellation = .init(),
    progress: @escaping @Sendable (String) -> Void = { _ in },
    answerPreview: @escaping @Sendable (AnswerPreview) -> Void = { _ in },
    requestStarted: @escaping @Sendable (AgentRequest, String) -> Void = { _, _ in },
    openSpace: SpaceOpener? = nil,
    openReviews: ReviewQueueOpener? = nil,
    workspaceAction: WorkspaceActionHandler? = nil,
    excelConversion: ExcelConversionBuild? = nil,
    conversationInput: Bool = false, inputAnswerID: String? = nil
  ) async throws -> AgentResult {
    // The app starts its turn at Send. A caller without a screen gets one from here.
    let ownsTiming = ChatTiming.beginTurn(origin: "product", conversation: conversation)
    ChatTiming.mark("product.run")
    defer {
      ChatTiming.mark("product.run_returned")
      if ownsTiming { ChatTiming.endTurn(outcome: "returned") }
    }
    return try await perform(cancellation: cancellation, progress: progress) {
      if model == nil {
        let configuration = try ChatTiming.span("product.model_configuration") {
          try NativeProductResources.configuration(modelsRoot: modelDirectory)
        }
        engineBytes = configuration.memoryBytes
        model = NativeWorkbookModel(configuration: configuration)
      }
      guard let model else { throw SevraError("model", "The local model is unavailable.") }
      ChatTiming.mark("product.model_lease")
      return try await WorkbookAgent.run(
        prompt, workbook: workbook, conversation: conversation, context: context,
        modelDirectory: modelDirectory, cancellation: cancellation, progress: progress,
        answerPreview: answerPreview, model: model, requestStarted: requestStarted,
        openSpace: openSpace, openReviews: openReviews, workspaceAction: workspaceAction,
        excelConversion: excelConversion, conversationInput: conversationInput,
        inputAnswerID: inputAnswerID
      )
    }
  }

  public func analyzeExcel(
    _ conversion: ExcelConversion, workbook: Workbook,
    modelDirectory: URL = ProductAI.defaultDirectory,
    cancellation: Cancellation = .init(), progress: @escaping @Sendable (String) -> Void = { _ in }
  ) async throws -> Value {
    try await perform(cancellation: cancellation, progress: progress) {
      let model = try self.workflowModel(directory: modelDirectory)
      let plan = try await ExcelConversionAgent.analyze(
        conversion, workbook: workbook, model: model,
        directory: modelDirectory, cancellation: cancellation, progress: progress)
      return .object(["plan": plan, "model": .string(await model.identity)])
    }
  }

}

/// The latest progress of a start, and the one request waiting on it, if any. A request that
/// begins waiting is told where the start is at once.
final class ProgressRelay: @unchecked Sendable {
  private let lock = NSLock()
  private var latest: String?
  private var listener: (@Sendable (String) -> Void)?
  func reset() {
    lock.lock()
    latest = nil
    listener = nil
    lock.unlock()
  }
  func listen(_ next: (@Sendable (String) -> Void)?) {
    lock.lock()
    listener = next
    let current = latest
    lock.unlock()
    if let next, let current { next(current) }
  }
  @Sendable func send(_ value: String) {
    lock.lock()
    latest = value
    let current = listener
    lock.unlock()
    current?(value)
  }
}

/// Network callbacks may arrive many times per frame. Keep UI updates bounded
/// without delaying cancellation or disk writes.
private final class SetupProgress: @unchecked Sendable {
  private let lock = NSLock()
  private var lastTime = -Double.infinity
  private var lastFile = ""
  private let report: @Sendable (String) -> Void
  init(_ report: @escaping @Sendable (String) -> Void) { self.report = report }
  func receive(_ update: SplashModelSetup.Progress) {
    lock.lock()
    let now = ProcessInfo.processInfo.systemUptime
    let key = update.phase + "/" + update.file
    let emit =
      key != lastFile || now - lastTime >= 0.2 || update.completedBytes == update.totalBytes
    if emit {
      lastTime = now
      lastFile = key
    }
    lock.unlock()
    if emit {
      if update.totalBytes == 0 {
        report("\(update.phase): \(update.file)")
        return
      }
      let amount = ByteCountFormatter.string(
        fromByteCount: update.completedBytes, countStyle: .file)
      let total = ByteCountFormatter.string(fromByteCount: update.totalBytes, countStyle: .file)
      report("\(update.phase): \(update.file) · \(amount) of \(total)")
    }
  }
}
