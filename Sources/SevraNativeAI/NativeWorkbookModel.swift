import CryptoKit
import Darwin
import Foundation
import SevraAI
import SevraCore
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

/// Internal qualification backend. Production does not depend on this target
/// until native setup, packaging and application acceptance gates have passed.
package actor NativeWorkbookModel: WorkbookInference {
  package enum Activations: String, Sendable { case bf16, auto }
  package enum ModelLayout: Sendable { case localPack, installed }
  package struct Configuration: Sendable {
    package let engine: URL
    package let engineFiles: [String: String]
    package let grammarLibrary: URL
    package let grammarSHA256: String
    package let modelsRoot: URL
    package let memoryBytes: UInt64
    package let activations: Activations
    package let contextBudget: ContextBudget
    package let reasoning: NativeReasoning
    package let modelLayout: ModelLayout
    package let contextMaintenanceEnabled: Bool
    /// Evaluation-only startup status sampling; absent from product and timing cohorts.
    package let observeAdmission: (@Sendable (Value) -> Void)?
    package let observeRequest: (@Sendable (Value) -> Void)?
    package let observeMask: (@Sendable ([UInt32], [UInt32], UInt32, [UInt32]) -> Void)?
    /// Qualification intervention only. Product callers retain shared caching.
    package let diagnosticRequestCacheIsolation: Bool
    /// The product restores the prepared header from `location` before every engine start
    /// and never computes it. `compute` is the check harness's comparison setting only: the
    /// engine reads the header again in each process, as before the prepared header.
    package enum Header: Sendable { case restore(URL?), compute }
    package let header: Header
    /// The engine's disk cache while it runs. Emptied at every start and stop.
    package let cacheDirectory: URL
    /// Check-harness seam: the first header check of a session reports a missed resume.
    package let diagnosticMissedResume: Bool
    package static var defaultCacheDirectory: URL {
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Caches/Sevra/PromptCache")
    }
    package init(
      engine: URL, engineFiles: [String: String], grammarLibrary: URL,
      grammarSHA256: String, modelsRoot: URL, memoryBytes: UInt64,
      contextBudget: ContextBudget = .init(), reasoning: NativeReasoning = .off,
      modelLayout: ModelLayout = .localPack, contextMaintenanceEnabled: Bool = true,
      observeRequest: (@Sendable (Value) -> Void)? = nil,
      observeMask: (@Sendable ([UInt32], [UInt32], UInt32, [UInt32]) -> Void)? = nil,
      diagnosticRequestCacheIsolation: Bool = false, activations: Activations = .bf16,
      observeAdmission: (@Sendable (Value) -> Void)? = nil,
      header: Header = .restore(PromptHeader.location()),
      cacheDirectory: URL = Configuration.defaultCacheDirectory,
      diagnosticMissedResume: Bool = false
    ) {
      self.header = header
      self.cacheDirectory = cacheDirectory
      self.diagnosticMissedResume = diagnosticMissedResume
      self.engine = engine
      self.engineFiles = engineFiles
      self.grammarLibrary = grammarLibrary
      self.grammarSHA256 = grammarSHA256
      self.modelsRoot = modelsRoot
      self.memoryBytes = memoryBytes
      self.activations = activations
      self.contextBudget = contextBudget
      self.reasoning = reasoning
      self.modelLayout = modelLayout
      self.contextMaintenanceEnabled = contextMaintenanceEnabled
      self.observeAdmission = observeAdmission
      self.observeRequest = observeRequest
      self.observeMask = observeMask
      self.diagnosticRequestCacheIsolation = diagnosticRequestCacheIsolation
    }
  }
  package let identity: String
  package private(set) var lastMetrics: Value = .null
  private let worker: NativeWorker
  private let contextMaintenanceEnabled: Bool
  private var leased = false
  private var active = false
  private var processLock: Int32 = -1
  private var idleRelease: Task<Void, Never>?
  private var idleGeneration: UUID?
  package init(configuration: Configuration) {
    worker = NativeWorker(configuration)
    contextMaintenanceEnabled = configuration.contextMaintenanceEnabled
    identity =
      "Splash 1.6.1; d8af1054aab0f97de21d043e01aa98af3754f10e; Qwen3.6-35B-A3B-4bit + DFlash2; native Swift candidate"
      + "; context \(configuration.contextBudget.contextTokens); memory \(configuration.memoryBytes); activations \(configuration.activations.rawValue); KV int8; state fp32; ANE on"
      + "; reasoning budget \(configuration.reasoning.rawValue); within-request reasoning retained"
  }

  package func beginRun() throws {
    try require(!leased && !active, "busy", "Sevra is already answering another question.")
    if processLock < 0 {
      let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/Sevra")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let fd = Darwin.open(
        directory.appendingPathComponent("inference.lock").path,
        O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
      try require(fd >= 0, "model_lock", "Cannot open local inference lock.")
      guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        Darwin.close(fd)
        throw SevraError(
          "model_busy",
          "Another Sevra process has the model loaded. Unload it or close that process, then try again."
        )
      }
      processLock = fd
    }
    idleGeneration = nil
    idleRelease?.cancel()
    idleRelease = nil
    leased = true
  }

  package func endRun() async {
    guard !active else { return }
    leased = false
    idleGeneration = nil
    idleRelease?.cancel()
    // With no helper to keep warm, the idle wait would only hold the lock against other processes.
    guard await worker.hasSession() else {
      _ = await unload()
      return
    }
    guard !leased else { return }
    let generation = UUID()
    idleGeneration = generation
    idleRelease = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: 600_000_000_000) } catch { return }
      await self?.releaseIfIdle(generation)
    }
  }

  private func releaseIfIdle(_ generation: UUID) async {
    guard generation == idleGeneration else { return }
    _ = await unload()
  }

  package func releaseResources() async -> Bool { await unload() }

  /// Starts the engine before a request needs it, so Send does not wait for the model to load.
  /// Nothing is sent to the model. It holds the same lock as a run and leaves the engine on the
  /// ordinary idle timer. A failure is not reported here: the request that follows meets it.
  package func prewarm(
    directory: URL, cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) async -> Bool {
    guard !leased && !active else { return false }
    do { try beginRun() } catch { return false }
    active = true
    let started = await worker.prewarm(
      directory: directory, cancellation: cancellation, progress: progress)
    active = false
    await endRun()
    return started
  }

  @discardableResult package func unload() async -> Bool {
    guard !active && !leased else { return false }
    active = true
    idleGeneration = nil
    idleRelease?.cancel()
    idleRelease = nil
    guard await worker.close() else {
      active = false
      return false
    }
    if processLock >= 0 {
      flock(processLock, LOCK_UN)
      Darwin.close(processLock)
      processLock = -1
    }
    active = false
    return true
  }

  deinit {
    idleGeneration = nil
    idleRelease?.cancel()
    // Release the lease only after the worker has reaped its helper, including
    // when an owner disappears without an explicit unload.
    worker.shutdown(releasing: processLock)
  }

  package var supportsCompaction: Bool { contextMaintenanceEnabled }
  package func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, toolScope: InferenceToolScope, citationIDs: [String],
    progress: @escaping @Sendable (String) -> Void
  ) async throws -> ContextMeasurement {
    try require(leased && !active, "busy", "The native model needs an exclusive workbook run.")
    active = true
    defer { active = false }
    return try await withTaskCancellationHandler {
      if Task.isCancelled { cancellation.cancel() }
      try cancellation.check()
      return try await worker.measureContext(
        messages: messages, directory: directory,
        cancellation: cancellation, summary: summary, toolScope: toolScope,
        citationIDs: citationIDs, progress: progress)
    } onCancel: {
      cancellation.cancel()
    }
  }
  package func boundToolResult(
    _ value: Value, receiptID: String, directory: URL, cancellation: Cancellation,
    toolScope: InferenceToolScope, nativeAppAuthoring: Bool
  ) async throws -> Value {
    try require(leased && !active, "busy", "The native model needs an exclusive workbook run.")
    active = true
    defer { active = false }
    return try await worker.boundToolResult(
      value, receiptID: receiptID, directory: directory, cancellation: cancellation,
      toolScope: toolScope, nativeAppAuthoring: nativeAppAuthoring)
  }
  package func summarize(
    messages: [InferenceMessage], allowedMessageIDs: [String], directory: URL,
    cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) async throws -> String {
    try require(leased && !active, "busy", "The native model needs an exclusive workbook run.")
    active = true
    defer { active = false }
    return try await withTaskCancellationHandler {
      if Task.isCancelled { cancellation.cancel() }
      try cancellation.check()
      let result = try await worker.summarize(
        messages: messages, allowedMessageIDs: allowedMessageIDs,
        directory: directory, cancellation: cancellation, progress: progress)
      try cancellation.check()
      lastMetrics = result.1
      return result.0
    } onCancel: {
      cancellation.cancel()
    }
  }

  package func interpret(
    request: Value, directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void
  ) async throws -> Value {
    try require(leased && !active, "busy", "The native model needs an exclusive workflow step.")
    try require(
      request["model"] == .string(identity), "workflow_model",
      "The saved request names a different model.")
    active = true
    lastMetrics = .null
    defer { active = false }
    return try await withTaskCancellationHandler {
      if Task.isCancelled { cancellation.cancel() }
      try cancellation.check()
      let messages = request["messages"].array.map {
        InferenceMessage(role: $0["role"].text, content: $0["content"].text)
      }
      let result = try await worker.respond(
        messages: messages, directory: directory, cancellation: cancellation,
        progress: progress, toolScope: .inspection, citationIDs: [], interpretation: request)
      try cancellation.check()
      guard result.0.calls.count == 1, let call = result.0.calls.first,
        call.name == "interpretation_result"
      else {
        throw SevraError("interpretation_output", "Expected one structured interpretation result.")
      }
      lastMetrics = result.1
      return .object([
        "request": request, "response": try Value.parse(call.inputJSON)["result"],
        "metrics": result.1,
      ])
    } onCancel: {
      cancellation.cancel()
    }
  }

  package func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    try await respondStreaming(
      messages: messages, directory: directory, cancellation: cancellation,
      progress: progress, toolScope: toolScope, citationIDs: citationIDs, answerPreview: { _ in },
      reasoningPreview: { _ in })
  }

  package func respondStreaming(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String], answerPreview: @escaping @Sendable (String) -> Void,
    reasoningPreview: @escaping @Sendable (String) -> Void
  ) async throws -> NativeReply {
    try require(leased && !active, "busy", "The native model needs an exclusive workbook run.")
    active = true
    lastMetrics = .null
    defer { active = false }
    return try await withTaskCancellationHandler {
      if Task.isCancelled { cancellation.cancel() }
      try cancellation.check()
      let result = try await worker.respond(
        messages: messages, directory: directory, cancellation: cancellation,
        progress: progress, toolScope: toolScope, citationIDs: citationIDs,
        answerPreview: answerPreview, reasoningPreview: reasoningPreview)
      try cancellation.check()
      lastMetrics = result.1
      return result.0
    } onCancel: {
      cancellation.cancel()
    }
  }
}

/// All native process, grammar and tokenizer state is confined to this serial
/// worker. Blocking pipe reads never occupy the main actor or cooperative pool.
private final class NativeWorker: @unchecked Sendable {
  private let queue = DispatchQueue(label: "app.sevra.native-inference", qos: .userInitiated)
  private let configuration: NativeWorkbookModel.Configuration
  private var session: Session?
  init(_ configuration: NativeWorkbookModel.Configuration) { self.configuration = configuration }
  private final class Session {
    let directory: URL
    let frontend: SplashTextFrontend
    let factory: SplashGrammarFactory
    var helper: SplashNativeProcess?
    let assembly: URL
    let configuration: NativeWorkbookModel.Configuration
    var capacity: Int {
      min(
        configuration.contextBudget.contextTokens,
        helper?.ready.map { Int($0.context) } ?? configuration.contextBudget.contextTokens)
    }
    // Measurement and dispatch share prepared requests on the serial inference worker.
    // Compare exact encoded bytes including all host-only schema and authority fields.
    private struct PreparationKey: Encodable {
      let messages: [InferenceMessage]
      let scope: String
      let citations: [String]
    }
    // Maintenance alternates the full conversation and its minimum admissible context.
    private var measuredRequests: [(key: Data, request: NativePreparedRequest)] = []
    func prepare(
      _ messages: [InferenceMessage], scope: InferenceToolScope, citations: [String],
      interpretation: Value? = nil
    ) throws -> NativePreparedRequest {
      try ContextBudget.validateEnvelope(messages)
      if let interpretation {
        return try NativePreparedRequest(
          messages: messages, frontend: frontend, configuredReasoning: configuration.reasoning,
          toolScope: scope, citationIDs: citations, interpretation: interpretation)
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let key = try encoder.encode(PreparationKey(messages: messages, scope: scope.rawValue, citations: citations))
      if let match = measuredRequests.firstIndex(where: { $0.key == key }) {
        let cached = measuredRequests.remove(at: match)
        measuredRequests.append(cached)
        ChatTiming.mark(
          "model.prepare_reused",
          ["promptTokens": .number(Double(cached.request.prompt.tokens.count))])
        return cached.request
      }
      let started = ChatTiming.now
      let prepared = try NativePreparedRequest(
        messages: messages, frontend: frontend, configuredReasoning: configuration.reasoning,
        toolScope: scope, citationIDs: citations)
      ChatTiming.record(
        "model.prepare", since: started,
        ["promptTokens": .number(Double(prepared.prompt.tokens.count)),
         "scope": .string(scope.rawValue)])
      if measuredRequests.count == 2 { measuredRequests.removeFirst() }
      measuredRequests.append((key, prepared))
      return prepared
    }
    // Engine checkpoints are process-local. Retain the exact token identity, including schemas.
    private var checkpointPrefixes: [[UInt32]] = []
    /// Page-aligned prompt prefixes whose replay states earlier requests left at the end of
    /// their saved conversation. A prompt that starts with one resumes past the header.
    private var replayPrefixes: [[UInt32]] = []
    func recordReplay(_ prompt: [UInt32], boundary: Int) {
      let prefix = Array(prompt.prefix(boundary / 32 * 32))
      replayPrefixes.removeAll { $0 == prefix }
      if replayPrefixes.count == 4 { replayPrefixes.removeFirst() }
      replayPrefixes.append(prefix)
    }
    func primePrefix(
      _ prompt: SplashTextFrontend.Prompt, common: Int, scope: Int, helper: SplashNativeProcess,
      cancellation: Cancellation
    ) throws -> (tokens: Int, matched: Int, seconds: Double, prefill: Double) {
      guard common >= 2048, !configuration.diagnosticRequestCacheIsolation else { return (0, 0, 0, 0) }
      // Prime the shared boundary first. An additional large stable scope earns a separate
      // checkpoint on a later dispatch. Never introduce more than one prime per dispatch.
      // A deeper replay state the prompt starts with already covers both boundaries.
      let count = [common, scope].first { size in
        (size == common || size >= common + 2048)
          && !checkpointPrefixes.contains { $0.count == size && prompt.tokens.prefix(size).elementsEqual($0) }
          && !replayPrefixes.contains { $0.count >= size && prompt.tokens.starts(with: $0) }
      }
      guard let count else { return (0, 0, 0, 0) }
      let prefix = Array(prompt.tokens.prefix(count))
      requestID += 1
      var seed = SplashWire.Request(
        id: requestID, prompt: prefix,
        absoluteDeadline: UInt64((Date().timeIntervalSince1970 + 180) * 1e6),
        remainingDeadline: 180_000_000)
      // This engine takes a restorable checkpoint at the last complete prefix page.
      // One discarded token closes the wire request; it cannot execute workbook tools.
      seed.maxOutput = 1
      var matched = 0
      let primeStarted = ChatTiming.now
      let result = try helper.generate(
        seed, cancelled: { cancellation.isCancelled || cancellation.isExpired },
        event: { if case .start(_, _, let reused) = $0 { matched = Int(reused) } })
      ChatTiming.record(
        "engine.prime", since: primeStarted,
        ["tokens": .number(Double(count)), "matched": .number(Double(matched)),
         "prefillSeconds": .number(Double(result.done.prefillMicros) / 1e6)])
      try cancellation.check()
      if checkpointPrefixes.count == 4 { checkpointPrefixes.removeFirst() }
      checkpointPrefixes.append(prefix)
      return (count, matched, result.requestSeconds, Double(result.done.prefillMicros) / 1e6)
    }
    func observeResume(prompt: [UInt32], matched: Int) {
      // A live process can evict old KV pages under its memory budget. Re-prime a missing
      // boundary on a later request instead of trusting the host's record indefinitely.
      // Splash 1.6.1 checkpoints complete 32-token pages before the suffix.
      checkpointPrefixes.removeAll { prefix in
        let lastCompletePage = ((prefix.count - 1) / 32) * 32
        return matched < lastCompletePage && prompt.starts(with: prefix)
      }
      replayPrefixes.removeAll { matched < $0.count && prompt.starts(with: $0) }
    }
    var requestID: UInt64 = 0
    /// The prepared header this build restores, its tokens and how often a start had to be
    /// repeated because the engine did not resume it. Empty with the comparison setting.
    var headerTokens: [UInt32] = []
    var header: (folder: URL, manifest: PromptHeader.Manifest)?
    var headerRestarts = 0
    var missedResumeSeam = false
    init(
      directory: URL, configuration: NativeWorkbookModel.Configuration,
      cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
    ) throws {
      self.directory = directory
      self.configuration = configuration
      try require(
        configuration.memoryBytes >= 4 * 1024 * 1024 * 1024,
        "model_setup", "Invalid candidate engine memory budget.")
      try require(
        Set(configuration.engineFiles.keys) == ["splash", "splash.metallib", "host-step.metallib"],
        "model_setup", "Native executable and Metal identities are required.")
      let folder = configuration.engine.deletingLastPathComponent()
      try ChatTiming.span("session.verify_engine_files") {
        for (name, digest) in configuration.engineFiles {
          try Self.verify(folder.appendingPathComponent(name), digest, cancellation)
        }
      }
      try require(
        configuration.engine.lastPathComponent == "splash", "model_setup",
        "Invalid native executable.")
      progress("Checking local model files")
      let modelFilesStarted = ChatTiming.now
      let pack = try SplashModelPack.selected()
      let tokenizer: URL
      switch configuration.modelLayout {
      case .localPack:
        assembly = try SplashModelPreparation.prepare(
          pack: pack, target: directory, draft: directory.appendingPathComponent("dflash"),
          modelsRoot: configuration.modelsRoot,
          cancelled: { cancellation.isCancelled || cancellation.isExpired })
        tokenizer = directory
      case .installed:
        do {
          assembly = try SplashModelPreparation.installed(
            pack: pack, modelsRoot: directory,
            cancelled: { cancellation.isCancelled || cancellation.isExpired })
        } catch {
          try cancellation.check()
          throw SevraError(
            "model_setup",
            "Local AI needs setup or repair. Open Model Settings to download, verify or reuse the selected model. "
              + error.localizedDescription)
        }
        tokenizer = assembly.appendingPathComponent("tokenizer")
      }
      ChatTiming.record("session.model_files", since: modelFilesStarted)
      try cancellation.check()
      let loaded = try ChatTiming.span("session.tokenizer") {
        try SplashTextFrontend(modelFolder: tokenizer)
      }
      frontend = loaded
      factory = try ChatTiming.span("session.grammar_library") {
        try SplashGrammarFactory(
          frontend: loaded, library: configuration.grammarLibrary,
          librarySHA256: configuration.grammarSHA256)
      }
      try cancellation.check()
      let headerCheckStarted = ChatTiming.now
      defer { ChatTiming.record("session.header_check", since: headerCheckStarted) }
      missedResumeSeam = configuration.diagnosticMissedResume
      if case .restore(let location) = configuration.header {
        // Without a matching header the engine is not started: nothing computes one.
        let identity = try PromptHeader.Identity(
          engineSHA256: configuration.engineFiles["splash"] ?? "",
          activations: configuration.activations.rawValue, reasoning: configuration.reasoning)
        switch PromptHeader.state(at: location, identity: identity) {
        case .absent: throw PromptHeader.missing()
        case .mismatched(let reason): throw PromptHeader.missing(reason)
        case .present(let folder, let manifest):
          try require(
            manifest.assemblyKey == PromptHeader.assemblyKey(assembly), "model_header",
            PromptHeader.missing("the installed model").message)
          let tokens = try PromptHeader.tokens(frontend: frontend, reasoning: configuration.reasoning)
          try require(
            tokens.count == manifest.tokens
              && PromptHeader.tokenDigest(tokens) == manifest.tokenSHA256, "model_header",
            PromptHeader.missing("the model's tokenizer").message)
          headerTokens = tokens
          header = (folder, manifest)
        }
      }
    }
    func start(
      cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
    ) throws -> SplashNativeProcess {
      if let helper, helper.isOpen { return helper }
      try require(
        helper?.close() != false, "native_shutdown", "The previous native helper has not stopped.")
      checkpointPrefixes.removeAll()
      progress("Preparing local AI. The first start can take longer…")
      guard let (folder, manifest) = header else {
        return try launch(
          [
            "serve-native", assembly.path, String(configuration.contextBudget.contextTokens),
            String(configuration.memoryBytes), "--persistent-cache", "off",
          ] + PromptHeader.engineOptions(activations: configuration.activations.rawValue),
          cancellation: cancellation, progress: progress)
      }
      let cache = configuration.cacheDirectory
      try require(
        PromptHeader.freeBytes(cache.deletingLastPathComponent())
          >= PromptHeader.requiredFreeBytes(manifest), "model_disk",
        PromptHeader.noDisk(manifest).message)
      // A start whose engine did not take every restore point back is repeated once from the
      // app's own files. A second is a damaged installation, never a reason to compute.
      for attempt in 0..<2 {
        try ChatTiming.span("engine.header_restore") {
          try PromptHeader.restore(folder, manifest, into: cache)
        }
        let started = try ChatTiming.span("engine.launch", ["attempt": .number(Double(attempt))]) {
          try launch(
            PromptHeader.arguments(
              assembly: assembly, contextTokens: configuration.contextBudget.contextTokens,
              memoryBytes: configuration.memoryBytes, cache: cache,
              activations: configuration.activations.rawValue),
            cancellation: cancellation, progress: progress)
        }
        let status = try ChatTiming.span("engine.status_check") {
          try Value.parse(String(decoding: started.status(id: UInt64.max - 1), as: UTF8.self))
        }
        switch PromptHeader.check(status: status, manifest) {
        case .whole:
          checkpointPrefixes = [headerTokens]
          return started
        case .notPersistent:
          stop()
          throw PromptHeader.noDisk(manifest)
        case .short:
          stop()
          headerRestarts += 1
          if attempt == 1 { throw PromptHeader.damaged() }
        }
      }
      throw PromptHeader.damaged()
    }
    /// Stops the helper, then removes what the engine wrote, so no conversation stays on disk.
    @discardableResult func stop() -> Bool {
      guard helper?.close() != false else { return false }
      helper = nil
      if header != nil { try? FileManager.default.removeItem(at: configuration.cacheDirectory) }
      return true
    }
    private func launch(
      _ arguments: [String], cancellation: Cancellation,
      progress: @escaping @Sendable (String) -> Void
    ) throws -> SplashNativeProcess {
      do {
        let started = try SplashNativeProcess(
          executable: configuration.engine,
          arguments: arguments,
          timeout: 360, cancelled: { cancellation.isCancelled || cancellation.isExpired },
          warming: { completed, total in
            ChatTiming.mark(
              "engine.warming",
              ["completed": .number(Double(completed)), "total": .number(Double(total))])
            progress("Preparing local AI · \(completed) of \(total) steps")
          },
          onLaunch: {
            self.helper = $0
            ChatTiming.mark("engine.process_launched")
          })
        helper = started
        guard let ready = started.ready,
          ready.vocabulary == SplashTextFrontend.vocabularySize,
          ready.stopTokens.count == SplashTextFrontend.stopTokens.count,
          Set(ready.stopTokens) == Set(SplashTextFrontend.stopTokens),
          ready.maskRows <= 33 && !ready.vision
        else {
          _ = started.close()
          throw SevraError(
            "model_setup",
            "The native model vocabulary or mask contract does not match the verified frontend.")
        }
        if let observe = configuration.observeAdmission {
          var status = try Value.parse(
            String(decoding: started.status(id: UInt64.max), as: UTF8.self)
          ).object
          status["probeHostPID"] = .number(Double(getpid()))
          status["probeHelperPID"] = .number(Double(started.processID))
          status["servedContextTokens"] = .number(Double(ready.context))
          observe(.object(status))
        }
        return started
      } catch {
        if let failure = error as? SplashWire.StartFailure {
          configuration.observeAdmission?(
            .object([
              "startupFailure": .object([
                "kind": .number(Double(failure.kind)), "bound": .number(Double(failure.bound)),
                "requiredBytes": .number(Double(failure.requiredBytes)),
                "budgetBytes": .number(Double(failure.budgetBytes)),
                "planContextTokens": .number(Double(failure.planContext)),
                "message": .string(String(decoding: failure.message, as: UTF8.self)),
              ])
            ]))
        }
        throw nativeFailure(error, helperStopped: helper?.isOpen == false, diagnostic: "")
      }
    }
    deinit { stop() }
    private static func verify(_ url: URL, _ digest: String, _ cancellation: Cancellation) throws {
      try require(
        url.isFileURL && digest.count == 64, "model_setup", "Missing native runtime identity.")
      let file = try FileHandle(forReadingFrom: url)
      defer { try? file.close() }
      var hash = SHA256()
      var size = 0
      while let bytes = try file.read(upToCount: 1024 * 1024), !bytes.isEmpty {
        try cancellation.check()
        size += bytes.count
        try require(size <= 128 * 1024 * 1024, "model_setup", "Native runtime file is oversized.")
        hash.update(data: bytes)
      }
      try require(
        hash.finalize().map { String(format: "%02x", $0) }.joined() == digest,
        "model_setup", "Native runtime file failed verification: " + url.lastPathComponent)
    }
  }

  /// Creates the session and starts its engine, restoring the prepared header, without a request.
  func prewarm(
    directory: URL, cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) async -> Bool {
    (try? await perform(directory: directory, cancellation: cancellation, progress: progress) {
      (session: Session) -> Void in
      _ = try session.start(cancellation: cancellation, progress: progress)
      // Nobody waited for this setup, so no request reports it.
      self.unreportedSessionSetup = 0
    }) != nil
  }

  /// Seconds the last new session spent on its model files, tokenizer, grammar and header check.
  /// The next request reports them once, so a request that found a ready session reports zero.
  private var unreportedSessionSetup: Double = 0

  func hasSession() async -> Bool {
    await withCheckedContinuation { continuation in
      queue.async { continuation.resume(returning: self.session?.helper != nil) }
    }
  }

  func close() async -> Bool {
    await withCheckedContinuation { continuation in
      queue.async {
        guard self.session?.helper?.close() != false else {
          continuation.resume(returning: false)
          return
        }
        self.session = nil
        continuation.resume(returning: true)
      }
    }
  }

  func shutdown(releasing descriptor: Int32) {
    queue.async {
      guard self.session?.helper?.close() != false else { return }
      self.session = nil
      if descriptor >= 0 {
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
      }
    }
  }

  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String], interpretation: Value? = nil,
    answerPreview: @escaping @Sendable (String) -> Void = { _ in },
    reasoningPreview: @escaping @Sendable (String) -> Void = { _ in }
  ) async throws -> (NativeReply, Value) {
    try await perform(directory: directory, cancellation: cancellation, progress: progress) {
      session in
      try self.generate(
        messages, session, cancellation, progress, toolScope, citationIDs, interpretation,
        answerPreview, reasoningPreview)
    }
  }
  private func perform<T>(
    directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, action: @escaping (Session) throws -> T
  ) async throws -> T {
    let queued = ChatTiming.now
    return try await withCheckedThrowingContinuation { continuation in
      queue.async {
        ChatTiming.record("model.queue_wait", since: queued)
        do {
          try cancellation.check()
          let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
          // A helper that died while idle is replaced here, so this request never meets it.
          if self.session?.directory != directory || self.session?.helper?.isOpen == false {
            try require(
              self.session?.helper?.close() != false, "native_shutdown",
              "The previous native helper has not stopped. Retry unloading it.")
            self.session = nil
            let setupStart = ProcessInfo.processInfo.systemUptime
            self.session = try ChatTiming.span("model.session_setup") {
              try Session(
                directory: directory, configuration: self.configuration,
                cancellation: cancellation, progress: progress)
            }
            self.unreportedSessionSetup = ProcessInfo.processInfo.systemUptime - setupStart
          }
          let result = try action(self.session!)
          try cancellation.check()
          continuation.resume(returning: result)
        } catch {
          // Only a failure that closed the helper ends the session. Reloading the model after a
          // cancelled request or an oversized prompt would cost minutes and help nothing.
          let helper = self.session?.helper
          let stopped = helper?.isOpen == false
          let failure = nativeFailure(
            error, helperStopped: stopped, diagnostic: helper?.lastDiagnostic ?? "")
          if stopped, helper?.close() != false { self.session = nil }
          continuation.resume(throwing: failure)
        }
      }
    }
  }
  func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, toolScope: InferenceToolScope, citationIDs: [String],
    progress: @escaping @Sendable (String) -> Void
  ) async throws -> ContextMeasurement {
    try await perform(directory: directory, cancellation: cancellation, progress: progress) {
      session in
      try ContextBudget.validateEnvelope(messages)
      if summary {
        let prompt = try session.frontend.prepare(
          messages: messages.map(nativeTemplateMessage), contextLimit: SplashWire.maxTokens)
        return .init(
          promptTokens: prompt.tokens.count, capacity: session.capacity,
          templateIdentity: session.frontend.templateIdentity,
          outputTokens: ContextDigest.maximumOutputTokens, toolResultTokens: 0)
      }
      return try session.prepare(messages, scope: toolScope, citations: citationIDs).measurement(capacity: session.capacity)
    }
  }
  func boundToolResult(
    _ value: Value, receiptID: String, directory: URL, cancellation: Cancellation,
    toolScope: InferenceToolScope, nativeAppAuthoring: Bool
  ) async throws -> Value {
    try await perform(
      directory: directory, cancellation: cancellation, progress: { _ in },
      action: { session in
        let reserve = try NativePreparedRequest.toolResultReserve(
          frontend: session.frontend, toolScope: toolScope, nativeAppAuthoring: nativeAppAuthoring)
        return try ToolResultProjection.bounded(value, receiptID: receiptID, maximumTokens: reserve)
        {
          try NativePreparedRequest.resultTokens($0, frontend: session.frontend)
        }
      })
  }
  func summarize(
    messages: [InferenceMessage], allowedMessageIDs: [String], directory: URL,
    cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) async throws -> (String, Value) {
    try await perform(directory: directory, cancellation: cancellation, progress: progress) {
      session in
      try require(
        !allowedMessageIDs.isEmpty && allowedMessageIDs.count <= 540,
        "context_digest", "The summary needs a bounded set of original messages.")
      try ContextBudget.validateEnvelope(messages)
      let prompt = try session.frontend.prepare(
        messages: messages.map(nativeTemplateMessage), contextLimit: SplashWire.maxTokens)
      _ = try self.configuration.contextBudget.allowance(
        promptTokens: prompt.tokens.count, outputTokens: ContextDigest.maximumOutputTokens,
        capacity: session.capacity, toolResultTokens: 0)
      let helper = try session.start(cancellation: cancellation, progress: progress)
      _ = try self.configuration.contextBudget.allowance(
        promptTokens: prompt.tokens.count, outputTokens: ContextDigest.maximumOutputTokens,
        capacity: session.capacity, toolResultTokens: 0)
      let constraint = try session.factory.create(
        grammar: ContextDigest.schema(allowedMessageIDs: allowedMessageIDs), type: "json")
      let output = try SplashOutputStream(frontend: session.frontend, structured: true)
      session.requestID += 1
      var request = SplashWire.Request(
        id: session.requestID, prompt: prompt.tokens,
        absoluteDeadline: UInt64((Date().timeIntervalSince1970 + 180) * 1e6),
        remainingDeadline: 180_000_000)
      request.maxOutput = UInt32(ContextDigest.maximumOutputTokens)
      request.generationTokens = prompt.generationTokens
      request.tokenMask = true
      try cancellation.check()
      progress("Keeping conversation context")
      var matchedPromptTokens = 0
      let generated = try helper.generate(
        request,
        cancelled: { cancellation.isCancelled || cancellation.isExpired },
        mask: { try constraint.masks(committed: $0, simulation: $1, words: $2) },
        event: { event in
          if case .tokens(_, _, let tokens) = event { _ = try output.append(tokens: tokens) }
          if case .start(_, _, let matched) = event { matchedPromptTokens = Int(matched) }
        })
      try cancellation.check()
      try require(
        generated.done.reason == .stop && !generated.done.bounded,
        "context_digest", "Context maintenance did not finish. Original history is preserved.")
      try constraint.finish(committed: generated.tokens, requireComplete: true)
      let parsed = try output.finish(generated.done.reason).0
      try require(parsed.calls.isEmpty, "context_digest", "Context maintenance cannot call tools.")
      _ = try ContextDigest.validate(parsed.text, allowedMessageIDs: Set(allowedMessageIDs))
      return (
        parsed.text,
        .object([
          "phase": .string("context_summary"), "backend": .string("splash"),
          "promptTokens": .number(Double(prompt.tokens.count)),
          "contextTokens": .number(Double(session.capacity)),
          "matchedPromptTokens": .number(Double(matchedPromptTokens)),
          "deduplicatedKVTokens": .number(Double(generated.done.deduplicated)),
          "generatedTokens": .number(Double(generated.tokens.count)),
          "requestSeconds": .number(generated.requestSeconds),
          "firstTokenSeconds": generated.firstTokenSeconds.map(Value.number) ?? .null,
          "prefillSeconds": .number(Double(generated.done.prefillMicros) / 1e6),
          "decodeSeconds": .number(Double(generated.done.decodeMicros) / 1e6),
        ])
      )
    }
  }

  private func generate(
    _ messages: [InferenceMessage], _ session: Session,
    _ cancellation: Cancellation, _ progress: @escaping @Sendable (String) -> Void,
    _ toolScope: InferenceToolScope, _ citationIDs: [String], _ interpretation: Value? = nil,
    _ answerPreview: @escaping @Sendable (String) -> Void = { _ in },
    _ reasoningPreview: @escaping @Sendable (String) -> Void = { _ in }
  ) throws -> (NativeReply, Value) {
    let hostStart = ProcessInfo.processInfo.systemUptime
    let prepared = try session.prepare(
      messages, scope: toolScope, citations: citationIDs, interpretation: interpretation)
    let budget = configuration.contextBudget
    // Refuse an impossible request before allocating the model, then recheck the
    // actual admitted capacity from Ready before dispatching the same token array.
    _ = try budget.allowance(
      promptTokens: prepared.prompt.tokens.count,
      outputTokens: prepared.outputBudget, capacity: session.capacity,
      toolResultTokens: prepared.toolResultTokens)
    let preparedAt = ProcessInfo.processInfo.systemUptime
    let sessionSetup = unreportedSessionSetup
    unreportedSessionSetup = 0
    var helper = try ChatTiming.span("model.engine_ready") {
      try session.start(cancellation: cancellation, progress: progress)
    }
    let helperReadyAt = ProcessInfo.processInfo.systemUptime
    let allowance = try budget.allowance(
      promptTokens: prepared.prompt.tokens.count,
      outputTokens: prepared.outputBudget, capacity: session.capacity,
      toolResultTokens: prepared.toolResultTokens)
    let measurement = prepared.measurement(capacity: session.capacity)
    let prompt = prepared.prompt
    let policy = prepared.policy
    let reasoning = prepared.reasoning
    let outputBudget = prepared.outputBudget
    // Every ordinary chat prompt starts with the prepared header, so its start event must
    // report the header resumed to its last complete page. A request that resumed less is
    // cancelled before it generates and sent once more after a restart from the app's files.
    let checksHeader =
      !session.headerTokens.isEmpty && prompt.tokens.starts(with: session.headerTokens)
    let headerPage = PromptHeader.lastCompletePage(session.headerTokens.count)
    var headerResumed: Bool?
    var constraint = try ChatTiming.span("model.grammar_compile") {
      try session.factory.create(grammar: policy.grammar)
    }
    var output = try SplashOutputStream(
      frontend: session.frontend, tools: policy.outputTools, thinking: reasoning.enabled)
    var seed = try session.primePrefix(
      prompt, common: prepared.stablePrefixCount, scope: prepared.scopePrefixCount,
      helper: helper, cancellation: cancellation)
    session.requestID += 1
    var request = SplashWire.Request(
      id: session.requestID, prompt: prompt.tokens,
      absoluteDeadline: UInt64((Date().timeIntervalSince1970 + 180) * 1e6),
      remainingDeadline: 180_000_000)
    request.maxOutput = UInt32(outputBudget)
    request.generationTokens = prompt.generationTokens
    // Splash keeps a request's reusable state on the last whole page before its last
    // `generationTokens`. The first decision of a request leaves it at the end of the saved
    // conversation, which the next turn extends; the host state, request and tool pairs
    // after it change each turn. Later decisions resume where the previous one stopped.
    let replayBoundary =
      interpretation == nil && messages.first?.initialChatDecision == true
      ? prepared.historyBoundary : nil
    if let replayBoundary {
      request.generationTokens = UInt32(prompt.tokens.count - replayBoundary)
    }
    request.tokenMask = true
    request.thinking = try reasoning.budget(outputTokens: outputBudget)
    if configuration.diagnosticRequestCacheIsolation {
      request.saltLow = session.requestID
      request.saltHigh = 0x5345_5652_4149_3200
    }
    try cancellation.check()
    progress("Reading the working context")
    let dispatchAt = ProcessInfo.processInfo.systemUptime
    var previewAt: Double?
    var generationPhase: String?
    var matchedPromptTokens = 0
    var lastPreview = ""
    var lastPreviewAt = ProcessInfo.processInfo.systemUptime
    // The reasoning as it is written, for the person to read. It never reaches the answer.
    var reasoningText = ""
    var reasoningSent = 0
    var reasoningSentAt = 0.0
    var missed = false
    var resent = false
    var generated: SplashNativeProcess.Result
    // Debug timing only: where the engine request's time goes on the host side.
    var masks = 0
    var maskSeconds = 0.0
    var eventSeconds = 0.0
    var startEventAt: Double?
    var firstTokensAt: Double?
    var answerPhaseAt: Double?
    var answerPhaseTokens = 0
    var tokenEvents = 0
    var streamedTokens = 0
    while true {
    generated = try helper.generate(
      request,
      cancelled: { cancellation.isCancelled || cancellation.isExpired || missed },
      mask: { committed, simulation, words in
        let maskStarted = ChatTiming.enabled ? ChatTiming.now : 0
        let values = try constraint.masks(
          committed: committed, simulation: simulation, words: words)
        self.configuration.observeMask?(committed, simulation, words, values)
        if ChatTiming.enabled {
          masks += 1
          maskSeconds += ChatTiming.now - maskStarted
        }
        return values
      },
      event: { event in
        let eventStarted = ChatTiming.enabled ? ChatTiming.now : 0
        defer { if ChatTiming.enabled { eventSeconds += ChatTiming.now - eventStarted } }
        if case .tokens(_, _, let tokens) = event {
          if ChatTiming.enabled {
            tokenEvents += 1
            streamedTokens += tokens.count
            if firstTokensAt == nil { firstTokensAt = eventStarted }
          }
          let deltas = try output.append(tokens: tokens)
          for case .reasoning(let part) in deltas
          where reasoningText.utf8.count < ActivityThought.limit * 4 {
            reasoningText += part
          }
          if reasoningText.utf8.count > reasoningSent,
            !cancellation.isCancelled && !cancellation.isExpired
          {
            let now = ProcessInfo.processInfo.systemUptime
            if reasoningSent == 0 || now - reasoningSentAt >= 0.1 || !output.isReasoning {
              reasoningSent = reasoningText.utf8.count
              reasoningSentAt = now
              reasoningPreview(reasoningText)
            }
          }
          if let text = output.answerPreview, text != lastPreview,
            !cancellation.isCancelled && !cancellation.isExpired
          {
            let now = ProcessInfo.processInfo.systemUptime
            if lastPreview.isEmpty || now - lastPreviewAt >= 0.08 {
              if previewAt == nil { previewAt = now }
              lastPreview = text
              lastPreviewAt = now
              answerPreview(text)
            }
          }
          let phase = output.isReasoning ? ActivityThought.reasoningPhase : "Preparing a response"
          if phase != generationPhase {
            if ChatTiming.enabled, !output.isReasoning, answerPhaseAt == nil {
              answerPhaseAt = ChatTiming.now
              answerPhaseTokens = streamedTokens
            }
            generationPhase = phase
            progress(phase)
          }
        }
        if case .start(_, _, let matched) = event {
          if ChatTiming.enabled, startEventAt == nil { startEventAt = eventStarted }
          matchedPromptTokens = Int(matched)
          if checksHeader {
            let seam = session.missedResumeSeam
            session.missedResumeSeam = false
            missed = seam || matchedPromptTokens < headerPage
          }
        }
      })
    try cancellation.check()
    guard missed else { break }
    // The restart restores the files from the app. Restoring a clean directory resets the
    // engine's own count of failed starts, so the host counts.
    missed = false
    try require(!resent, "model_header", PromptHeader.damaged().message)
    resent = true
    session.headerRestarts += 1
    session.stop()
    helper = try session.start(cancellation: cancellation, progress: progress)
    constraint = try session.factory.create(grammar: policy.grammar)
    output = try SplashOutputStream(
      frontend: session.frontend, tools: policy.outputTools, thinking: reasoning.enabled)
    reasoningText = ""
    reasoningSent = 0
    seed = try session.primePrefix(
      prompt, common: prepared.stablePrefixCount, scope: prepared.scopePrefixCount,
      helper: helper, cancellation: cancellation)
    session.requestID += 1
    request.id = session.requestID
    previewAt = nil
    generationPhase = nil
    lastPreview = ""
    }
    if checksHeader { headerResumed = matchedPromptTokens >= headerPage }
    let engineDoneAt = ChatTiming.now
    try require(
      generated.done.reason == .stop && !generated.done.bounded,
      "truncated",
      "The model did not finish its response. No action from this response was applied.")
    try constraint.finish(committed: generated.tokens, requireComplete: true)
    let parsed = try output.finish(generated.done.reason).0
    session.observeResume(prompt: prompt.tokens, matched: matchedPromptTokens)
    if let replayBoundary { session.recordReplay(prompt.tokens, boundary: replayBoundary) }
    let reasoningTokens = try reasoning.generatedTokens(generated.tokens)
    try require(
      parsed.calls.count == 1 || parsed.refusal != nil, "model_format",
      "Expected one complete native tool call.")
    var refusal = parsed.refusal
    var calls: [InferenceCall] = []
    do {
      calls = try parsed.calls.map { candidate in
        try policy.validate(candidate)
        return InferenceCall(
          id: "call_" + identifier(), name: candidate.name,
          inputJSON: String(decoding: candidate.arguments, as: UTF8.self))
      }
    } catch let refused as SplashError {
      refusal = refused.description
    }
    try cancellation.check()
    let metrics: Value = .object([
      "backend": .string("splash"),
      "runtimeRelease": .string("1.6.1"),
      "activations": .string(configuration.activations.rawValue),
      "requestedContextTokens": .number(Double(budget.contextTokens)),
      "requestedMemoryBytes": .number(Double(configuration.memoryBytes)),
      "engineSHA256": .string(configuration.engineFiles["splash"] ?? ""),
      "grammarSHA256": .string(configuration.grammarSHA256),
      "templateIdentity": .string(prepared.templateIdentity),
      "toolScope": .string(interpretation == nil ? toolScope.rawValue : "workflow_interpretation"),
      "requestSeconds": .number(generated.requestSeconds),
      "sessionSetupSeconds": .number(sessionSetup),
      "hostPreparationSeconds": .number(preparedAt - hostStart),
      "helperStartSeconds": .number(helperReadyAt - preparedAt),
      "beforeDispatchSeconds": .number(dispatchAt - hostStart),
      "firstAnswerPreviewSeconds": previewAt.map { .number($0 - hostStart) } ?? .null,
      "stablePrefixTokens": .number(Double(prepared.stablePrefixCount)),
      "scopePrefixTokens": .number(Double(prepared.scopePrefixCount)),
      "replayBoundaryTokens": .number(
        Double(
          replayBoundary.map { $0 / 32 * 32 }
            ?? (prompt.tokens.count - Int(prompt.generationTokens)) / 32 * 32)),
      "prefixPrimeTokens": .number(Double(seed.tokens)),
      "prefixPrimeMatchedTokens": .number(Double(seed.matched)),
      "prefixPrimeSeconds": .number(seed.seconds),
      "prefixPrimePrefillSeconds": .number(seed.prefill),
      "firstTokenSeconds": generated.firstTokenSeconds.map(Value.number) ?? .null,
      "promptTokens": .number(Double(prompt.tokens.count)),
      "matchedPromptTokens": .number(Double(matchedPromptTokens)),
      "deduplicatedKVTokens": .number(Double(generated.done.deduplicated)),
      "contextTokens": .number(Double(session.capacity)),
      "maintenanceThreshold": .number(Double(measurement.threshold)),
      "maintenanceRecommended": .bool(allowance.maintenanceRecommended),
      "nextToolResultReserve": .number(Double(prepared.toolResultTokens)),
      "recoveryReserve": .number(Double(budget.recoveryReserve)),
      "outputBudget": .number(Double(outputBudget)),
      "requestedOutputBudget": .number(Double(prepared.requestedOutputBudget)),
      "generatedTokens": .number(Double(generated.tokens.count)),
      "reasoningBudget": .number(Double(reasoning.rawValue)),
      "reasoningHistory": .string("within-request"),
      "reasoningTokens": .number(Double(reasoningTokens)),
      "reasoningBudgetOverrun": .number(Double(max(0, reasoningTokens - reasoning.rawValue))),
      "prefillSeconds": .number(Double(generated.done.prefillMicros) / 1e6),
      "decodeSeconds": .number(Double(generated.done.decodeMicros) / 1e6),
      "draftedTokens": .number(Double(generated.done.drafted)),
      "acceptedDraftTokens": .number(Double(generated.done.accepted)),
      "speculativeMethod": .string("DFlash2"),
      "diagnosticRequestCacheIsolation": .bool(configuration.diagnosticRequestCacheIsolation),
      "headerTokens": .number(Double(session.headerTokens.count)),
      "headerInputs": session.header.map { .string($0.manifest.inputs) } ?? .null,
      "headerResumed": headerResumed.map(Value.bool) ?? .null,
      "headerRestarts": .number(Double(session.headerRestarts)),
    ])
    if ChatTiming.enabled {
      func after(_ time: Double?) -> Value { time.map { .number($0 - dispatchAt) } ?? .null }
      ChatTiming.record(
        "engine.request", from: dispatchAt, to: engineDoneAt,
        [
          "promptTokens": .number(Double(prompt.tokens.count)),
          "matchedTokens": .number(Double(matchedPromptTokens)),
          "computedTokens": .number(Double(prompt.tokens.count - matchedPromptTokens)),
          "generatedTokens": .number(Double(generated.tokens.count)),
          "reasoningTokens": .number(Double(reasoningTokens)),
          "tokensBeforeAnswerPhase": .number(Double(answerPhaseTokens)),
          "outputBudget": .number(Double(outputBudget)),
          "startEventAfter": after(startEventAt),
          "firstTokenAfter": after(firstTokensAt),
          "answerPhaseAfter": after(answerPhaseAt),
          "firstPreviewAfter": after(previewAt),
          "prefillSeconds": .number(Double(generated.done.prefillMicros) / 1e6),
          "decodeSeconds": .number(Double(generated.done.decodeMicros) / 1e6),
          "engineWallSeconds": .number(Double(generated.done.wallMicros) / 1e6),
          "deduplicatedTokens": .number(Double(generated.done.deduplicated)),
          "draftedTokens": .number(Double(generated.done.drafted)),
          "acceptedDraftTokens": .number(Double(generated.done.accepted)),
          "cycles": .number(Double(generated.done.cycles)),
          "masks": .number(Double(masks)),
          "maskSeconds": .number(maskSeconds),
          "tokenEvents": .number(Double(tokenEvents)),
          "eventHandlingSeconds": .number(eventSeconds),
          "headerResent": .bool(resent),
        ])
      ChatTiming.record(
        "model.finish_and_validate", from: engineDoneAt, to: ChatTiming.now,
        ["calls": .number(Double(calls.count)), "refused": .bool(refusal != nil)])
      ChatTiming.mark("model.call", ["metrics": metrics])
    }
    // Opt-in qualification observation is absent from product configurations.
    if let observe = configuration.observeRequest {
      var normalized = request
      normalized.id = 1
      normalized.absoluteDeadline = 1
      normalized.remainingDeadline = 180_000_000
      observe(
        .object([
          "promptTokens": .array(prompt.tokens.map { .number(Double($0)) }),
          "generationTokens": .number(Double(prompt.generationTokens)),
          "tokens": .array(generated.tokens.map { .number(Double($0)) }),
          "requestFrame": .string(try normalized.encoded().base64EncodedString()),
          "grammar": configuration.observeMask == nil ? .null : .string(policy.grammar),
          "metrics": metrics,
        ]))
    }
    return (
      NativeReply(
        text: parsed.text, calls: calls, reasoning: parsed.reasoning, refusal: refusal), metrics
    )
  }

}

/// Engine and transport failures as typed errors, in words a person can act on. The engine's own
/// words stay in brackets. Anything else, such as a refused prompt, passes through unchanged.
package func nativeFailure(_ error: Error, helperStopped: Bool, diagnostic: String) -> Error {
  let output = diagnostic.isEmpty ? "" : " Last engine output: " + diagnostic
  switch error {
  case let failure as SplashWire.StartFailure:
    let message = String(decoding: failure.message, as: UTF8.self)
      .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    if [3, 4].contains(failure.kind) {
      return SevraError(
        "model_capacity",
        "Local AI cannot fit this request with its current memory allowance. Saved work is intact. This configuration needs a smaller working context or a larger verified memory allowance. ("
          + message + ")")
    }
    if [1, 2, 8].contains(failure.kind) {
      return SevraError(
        "model_capacity",
        "Local AI could not start with the available memory or context. Saved work is intact. Close other memory-heavy apps, then try again. ("
          + message + ")")
    }
    return SevraError("model_setup", "Local AI could not start: " + message)
  case let failure as SplashWire.Failure where failure.classification == 1:
    guard failure.retryable else {
      return SevraError(
        "model_refused", "The local model refused this request (\(failure.description)).")
    }
    let wait = failure.retryAfter > 0 ? " in about \(failure.retryAfter / 60 + 1) minutes" : ""
    return SevraError(
      "model_retry",
      "The local model could not finish this request (\(failure.description)). Try again\(wait).")
  case let failure as SplashWire.Failure:
    return SevraError(
      "model_engine", "The local model stopped (\(failure.description)). Try again." + output)
  case let failure as SplashError where helperStopped:
    return SevraError(
      "model_stopped",
      "The local model stopped unexpectedly (\(failure.description)). Try again." + output)
  default:
    return error
  }
}

package func nativeTemplateMessage(_ message: InferenceMessage) throws -> [String: any Sendable] {
  var value: [String: any Sendable] = ["role": message.role, "content": message.content]
  if message.role == "tool", message.hasCalculationResult {
    value["content"] = message.content
      + "\nThe host has completed this calculation for these inputs. Use its returned values and attached sources to answer. Use another call only for additional information required by the user."
  }
  if message.role == "assistant", !message.reasoning.isEmpty {
    value["reasoning_content"] = message.reasoning
  }
  if let id = message.toolCallId { value["tool_call_id"] = id }
  if let name = message.toolName { value["name"] = name }
  if !message.toolCalls.isEmpty {
    value["tool_calls"] = try message.toolCalls.map { call -> [String: any Sendable] in
      guard
        let arguments = try JSONSerialization.jsonObject(with: Data(call.inputJSON.utf8))
          as? [String: any Sendable]
      else {
        throw SevraError("model_format", "Tool history requires object arguments.")
      }
      return [
        "type": "function", "id": call.id,
        "function": ["name": call.name, "arguments": arguments] as [String: any Sendable],
      ]
    }
  }
  return value
}
