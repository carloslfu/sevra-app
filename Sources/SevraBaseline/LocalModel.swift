import Darwin
import Foundation
import SevraAI
import SevraCore
import Slotstream

public actor LocalModel: WorkbookInference {
  package var identity: String { "Slotstream Fast; " + Self.revision }
  public static let shared = LocalModel()
  public static let revision = "7578fb21e57ec362d19f5050922e0f583914935d"
  private var engine: Engine?
  private var loadedPath: String?
  private var active = false
  private var leased = false
  private var processLock: Int32 = -1
  private var idleRelease: Task<Void, Never>?
  private let contextMaintenanceEnabled: Bool
  public private(set) var lastMetrics: Value = .null
  public func beginRun() throws {
    try require(!leased, "busy", "Sevra is already answering another question.")
    if processLock < 0 {
      let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/Sevra")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let fd = Darwin.open(
        directory.appendingPathComponent("inference.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW,
        0o600)
      try require(fd >= 0, "model_lock", "Cannot open local inference lock.")
      guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        Darwin.close(fd)
        throw SevraError(
          "model_busy",
          "Another Sevra process has the model loaded. Unload it in Model Settings or close that process, then try again."
        )
      }
      processLock = fd
    }
    idleRelease?.cancel()
    idleRelease = nil
    leased = true
  }
  public func endRun() {
    leased = false
    if engine == nil {
      unload()
      return
    }
    idleRelease?.cancel()
    idleRelease = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
      await self?.unload()
    }
  }
  deinit { if processLock >= 0 { Darwin.close(processLock) } }
  public static var defaultDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      ".slotstream/models/" + ModelPackRegistry.fast.directoryName)
  }
  public static var downloadBytes: Int64 { ModelPackRegistry.fast.installationBytes }
  public init() { contextMaintenanceEnabled = false }
  package init(enableContextMaintenance: Bool) {
    contextMaintenanceEnabled = enableContextMaintenance
  }
  public func installed(at directory: URL = LocalModel.defaultDirectory) -> Bool {
    ModelPackRegistry.fast.installationFiles(at: directory).allSatisfy {
      FileManager.default.fileExists(atPath: $0.path)
    }
  }
  public func setup(
    at directory: URL = LocalModel.defaultDirectory, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void
  ) async throws {
    try require(!active, "busy", "Wait for the current local model operation.")
    active = true
    defer { active = false }
    let pack = ModelPackRegistry.fast
    try await Task.detached(priority: .userInitiated) {
      let pull = PullCancellation()
      let monitor = Task {
        while !Task.isCancelled {
          if cancellation.isCancelled {
            pull.cancel()
            return
          }
          try? await Task.sleep(nanoseconds: 100_000_000)
        }
      }
      defer { monitor.cancel() }
      for store in pack.installationStores(at: directory) {
        try cancellation.check()
        try store.download(.init(cancellation: pull), log: progress)
      }
    }.value
  }
  private func load(
    _ directory: URL, cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) async throws -> Engine {
    if let engine, loadedPath == directory.path { return engine }
    let pack = ModelPackRegistry.fast
    progress("Checking local model files")
    let ready = try await Task.detached {
      try pack.installationStatus(at: directory, shouldContinue: { !cancellation.isCancelled })
        .isReady
    }.value
    try require(
      ready, "model_setup",
      "The local model needs setup. Open Model Settings to download or choose the verified Fast model."
    )
    try cancellation.check()
    let tokenizerData = try Data(
      contentsOf: directory.appendingPathComponent("tokenizer_config.json"))
    let tokenizerConfig = try JSONSerialization.jsonObject(with: tokenizerData) as? [String: Any]
    try require(
      !(tokenizerConfig?["tokenizer_class"] as? String ?? "").isEmpty, "model_setup",
      "The qualified model must include its explicit tokenizer class. Verify the Fast pack in Model Settings."
    )
    try PackageResources.configureMetal()
    progress("Loading local AI")
    do {
      let plan = try pack.startupPlan(on: Machine.current(), mtpAvailable: true)
      let candidate = try await Engine(modelDir: directory, pack: pack, plan: plan)
      try candidate.configureStartupDefaults(for: pack)
      engine = candidate
      loadedPath = directory.path
      return candidate
    } catch {
      throw SevraError("model_load", String(describing: error))
    }
  }
  package func releaseResources() async -> Bool { unload() }

  @discardableResult public func unload() -> Bool {
    if !active && !leased {
      idleRelease?.cancel()
      idleRelease = nil
      engine = nil
      loadedPath = nil
      Engine.releaseUnusedMemory()
      if processLock >= 0 {
        flock(processLock, LOCK_UN)
        Darwin.close(processLock)
        processLock = -1
      }
      return true
    }
    return false
  }
  package var supportsCompaction: Bool { contextMaintenanceEnabled }
  package func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, citationIDs: [String], progress: @escaping @Sendable (String) -> Void
  ) async throws -> ContextMeasurement {
    try require(leased && !active, "busy", "The local model needs an exclusive workbook run.")
    active = true
    defer { active = false }
    let engine = try await load(directory, cancellation: cancellation, progress: progress)
    let tokens = try engine.encodeChat(
      try Self.baselineMessages(messages),
      tools: summary
        ? []
        : try Self.baselineDefinitions(
          itemReferenceIDs: ItemReferenceCandidates.ids(in: messages),
          conversationActions: messages.first?.conversationActions), thinking: false, effort: nil
    )
    try cancellation.check()
    guard let capacity = engine.contextPolicyJSON["configured_window"] as? Int else {
      throw SevraError("context_limit", "The configured context capacity is unavailable.")
    }
    return ContextMeasurement(
      promptTokens: tokens.count, capacity: capacity,
      templateIdentity: "slotstream-" + Self.revision + ";encodeChat;thinking=false;effort=nil")
  }
  package func summarize(
    messages: [InferenceMessage], allowedMessageIDs: [String], directory: URL,
    cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) async throws -> String {
    try require(leased && !active, "busy", "The local model needs an exclusive workbook run.")
    active = true
    defer { active = false }
    let engine = try await load(directory, cancellation: cancellation, progress: progress)
    let tokens = try engine.encodeChat(
      try Self.baselineMessages(messages), tools: [], thinking: false, effort: nil)
    if let problem = engine.contextError(
      promptTokens: tokens.count + ContextDigest.maximumOutputTokens)
    {
      throw SevraError("context_limit", problem)
    }
    var params = SampleParams()
    params.temperature = 0
    params.maxTokens = ContextDigest.maximumOutputTokens
    params.presencePenalty = 0
    params.seed = 42
    progress("Keeping conversation context")
    let result = engine.generate(
      promptIds: tokens, params: params,
      shouldContinue: { !cancellation.isCancelled && !cancellation.isExpired })
    try cancellation.check()
    if let failure = result.stats.requestFailure { throw failure }
    if let failure = result.stats.runtimeError { throw SevraError("inference", failure) }
    try require(
      result.ids.count < params.maxTokens, "context_digest",
      "Context maintenance did not finish. Original history is preserved.")
    _ = try ContextDigest.validate(result.text, allowedMessageIDs: Set(allowedMessageIDs))
    lastMetrics = .object([
      "phase": .string("context_summary"), "backend": .string("slotstream-baseline"),
      "promptTokens": .number(Double(tokens.count)),
      "generatedTokens": .number(Double(result.ids.count)),
      "requestSeconds": .number(result.stats.requestSeconds),
      "firstTokenSeconds": result.stats.firstTokenSeconds.map(Value.number) ?? .null,
      "peakMemoryGB": .number(result.stats.peakMemoryGB),
    ])
    return result.text
  }

  package func respond(
    messages: [InferenceMessage], directory: URL = LocalModel.defaultDirectory,
    cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void,
    toolScope: InferenceToolScope = .all, citationIDs: [String] = []
  ) async throws -> NativeReply {
    try require(!active, "busy", "The local model is already working.")
    active = true
    defer { active = false }
    let engine = try await load(directory, cancellation: cancellation, progress: progress)
    let available =
      try Self.baselineDefinitions(
        itemReferenceIDs: ItemReferenceCandidates.ids(in: messages),
        conversationActions: messages.first?.conversationActions, toolScope: toolScope
      )
      .filter { toolScope.allows($0.name) }
    let tokens = try engine.encodeChat(
      try Self.baselineMessages(messages), tools: available, thinking: false, effort: nil)
    // The engine window includes the reply. Keep this hard bound independent
    // of conversation maintenance, including when maintenance is disabled.
    if let problem = engine.contextError(promptTokens: tokens.count + 1800) {
      throw SevraError("context_limit", problem)
    }
    guard let capacity = engine.contextPolicyJSON["configured_window"] as? Int else {
      throw SevraError("context_limit", "The configured context capacity is unavailable.")
    }
    let measurement = ContextMeasurement(
      promptTokens: tokens.count, capacity: capacity,
      templateIdentity: "slotstream-" + Self.revision + ";encodeChat;thinking=false;effort=nil")
    var params = SampleParams()
    params.temperature = 0
    params.maxTokens = 1800
    params.presencePenalty = 0
    params.seed = 42
    progress("Thinking locally")
    let result = engine.generate(
      promptIds: tokens, params: params, shouldContinue: { !cancellation.isCancelled })
    try cancellation.check()
    if let failure = result.stats.requestFailure { throw failure }
    if let error = result.stats.runtimeError { throw SevraError("inference", error) }
    try require(
      result.ids.count < params.maxTokens, "truncated",
      "The model reached its response limit. Narrow the request and try again.")
    lastMetrics = .object([
      "toolScope": .string(toolScope.rawValue),
      "promptTokens": .number(Double(tokens.count)),
      "contextTokens": .number(Double(capacity)),
      "maintenanceThreshold": .number(Double(measurement.threshold)),
      "maintenanceRecommended": .bool(tokens.count >= measurement.threshold),
      "requestSeconds": .number(result.stats.requestSeconds),
      "firstTextSeconds": result.stats.firstTextSeconds.map(Value.number) ?? .null,
      "generatedTokens": .number(Double(result.ids.count)),
      "firstTokenSeconds": result.stats.firstTokenSeconds.map(Value.number) ?? .null,
      "decodeTokens": .number(Double(result.stats.decodeTokens)),
      "decodeSeconds": .number(result.stats.decodeSeconds),
      "decodeTokensPerSecond": .number(result.stats.decodeTPS),
      "prefillSeconds": .number(result.stats.prefillSeconds),
      "peakMemoryGB": .number(result.stats.peakMemoryGB),
      "speculativeMethod": result.stats.speculativeMethod.map(Value.string) ?? .null,
    ])
    let events = ToolCallSplitter.parseAll(
      result.text, tools: available.map(\.schema))
    var text = ""
    var calls: [ParsedToolCall] = []
    for event in events {
      switch event {
      case .text(let value): text += value
      case .toolCall(let call): calls.append(call)
      default: break
      }
    }
    return NativeReply(
      text: text,
      calls: calls.map {
        InferenceCall(id: $0.id, name: $0.name, inputJSON: $0.inputJSON)
      })
  }
}
