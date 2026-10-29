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
  package enum ModelLayout: Sendable { case localPack, installed }
  package struct Configuration: Sendable {
    package let engine: URL
    package let engineFiles: [String: String]
    package let grammarLibrary: URL
    package let grammarSHA256: String
    package let modelsRoot: URL
    package let memoryBytes: UInt64
    package let contextBudget: ContextBudget
    package let reasoning: NativeReasoning
    package let modelLayout: ModelLayout
    package let contextMaintenanceEnabled: Bool
    package let observeRequest: (@Sendable (Value) -> Void)?
    package let observeMask: (@Sendable ([UInt32], [UInt32], UInt32, [UInt32]) -> Void)?
    /// Qualification intervention only. Product callers retain shared caching.
    package let diagnosticRequestCacheIsolation: Bool
    package init(
      engine: URL, engineFiles: [String: String], grammarLibrary: URL,
      grammarSHA256: String, modelsRoot: URL, memoryBytes: UInt64,
      contextBudget: ContextBudget = .init(), reasoning: NativeReasoning = .off,
      modelLayout: ModelLayout = .localPack, contextMaintenanceEnabled: Bool = true,
      observeRequest: (@Sendable (Value) -> Void)? = nil,
      observeMask: (@Sendable ([UInt32], [UInt32], UInt32, [UInt32]) -> Void)? = nil,
      diagnosticRequestCacheIsolation: Bool = false
    ) {
      self.engine = engine
      self.engineFiles = engineFiles
      self.grammarLibrary = grammarLibrary
      self.grammarSHA256 = grammarSHA256
      self.modelsRoot = modelsRoot
      self.memoryBytes = memoryBytes
      self.contextBudget = contextBudget
      self.reasoning = reasoning
      self.modelLayout = modelLayout
      self.contextMaintenanceEnabled = contextMaintenanceEnabled
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
  package init(configuration: Configuration) {
    worker = NativeWorker(configuration)
    contextMaintenanceEnabled = configuration.contextMaintenanceEnabled
    identity =
      "Splash 1.4.1; 1744cfafee415fb463b289449cec59a864e768e9; Qwen3.6-35B-A3B-4bit + DFlash2; native Swift candidate"
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
    idleRelease?.cancel()
    idleRelease = nil
    leased = true
  }

  package func endRun() async {
    guard !active else { return }
    leased = false
    idleRelease?.cancel()
    idleRelease = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
      _ = await self?.unload()
    }
  }

  package func releaseResources() async -> Bool { await unload() }

  @discardableResult package func unload() async -> Bool {
    guard !active && !leased else { return false }
    active = true
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
    idleRelease?.cancel()
    // Release the lease only after the worker has reaped its helper, including
    // when an owner disappears without an explicit unload.
    worker.shutdown(releasing: processLock)
  }

  package var supportsCompaction: Bool { contextMaintenanceEnabled }
  package func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, citationIDs: [String], progress: @escaping @Sendable (String) -> Void
  ) async throws -> ContextMeasurement {
    try require(leased && !active, "busy", "The native model needs an exclusive workbook run.")
    active = true
    defer { active = false }
    return try await withTaskCancellationHandler {
      if Task.isCancelled { cancellation.cancel() }
      try cancellation.check()
      return try await worker.measureContext(
        messages: messages, directory: directory,
        cancellation: cancellation, summary: summary, citationIDs: citationIDs, progress: progress)
    } onCancel: {
      cancellation.cancel()
    }
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
        "request": request, "response": try Value.parse(call.inputJSON), "metrics": result.1,
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
    try require(leased && !active, "busy", "The native model needs an exclusive workbook run.")
    active = true
    lastMetrics = .null
    defer { active = false }
    return try await withTaskCancellationHandler {
      if Task.isCancelled { cancellation.cancel() }
      try cancellation.check()
      let result = try await worker.respond(
        messages: messages, directory: directory, cancellation: cancellation,
        progress: progress, toolScope: toolScope, citationIDs: citationIDs)
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
    let helper: SplashNativeProcess
    var requestID: UInt64 = 0
    init(
      directory: URL, configuration: NativeWorkbookModel.Configuration,
      cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
    ) throws {
      self.directory = directory
      try require(
        configuration.memoryBytes >= 4 * 1024 * 1024 * 1024,
        "model_setup", "Invalid candidate engine memory budget.")
      try require(
        Set(configuration.engineFiles.keys) == ["splash", "splash.metallib", "host-step.metallib"],
        "model_setup", "Native executable and Metal identities are required.")
      let folder = configuration.engine.deletingLastPathComponent()
      for (name, digest) in configuration.engineFiles {
        try Self.verify(folder.appendingPathComponent(name), digest, cancellation)
      }
      try require(
        configuration.engine.lastPathComponent == "splash", "model_setup",
        "Invalid native executable.")
      progress("Checking local model files")
      let pack = try SplashModelPack.selected()
      let assembly: URL
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
      try cancellation.check()
      frontend = try SplashTextFrontend(modelFolder: tokenizer)
      factory = try SplashGrammarFactory(
        frontend: frontend, library: configuration.grammarLibrary,
        librarySHA256: configuration.grammarSHA256)
      try cancellation.check()
      // A cold device/OS shader cache can compile for several minutes. Keep
      // startup cancellable and bounded, separately from generation deadlines.
      progress("Preparing local AI. First start may compile native components…")
      helper = try SplashNativeProcess(
        executable: configuration.engine,
        arguments: [
          "serve-native", assembly.path, String(configuration.contextBudget.contextTokens),
          String(configuration.memoryBytes),
          "--persistent-cache", "off", "--idle-sleep", "allow", "--verify-rows", "all",
        ],
        timeout: 360, cancelled: { cancellation.isCancelled || cancellation.isExpired })
    }
    deinit { helper.close() }
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

  func close() async -> Bool {
    await withCheckedContinuation { continuation in
      queue.async {
        guard self.session?.helper.close() != false else {
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
      guard self.session?.helper.close() != false else { return }
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
    citationIDs: [String], interpretation: Value? = nil
  ) async throws -> (NativeReply, Value) {
    try await perform(directory: directory, cancellation: cancellation, progress: progress) {
      session in
      try self.generate(
        messages, session, cancellation, progress, toolScope, citationIDs, interpretation)
    }
  }
  private func perform<T>(
    directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, action: @escaping (Session) throws -> T
  ) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
          try cancellation.check()
          let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
          if self.session?.directory != directory {
            try require(
              self.session?.helper.close() != false, "native_shutdown",
              "The previous native helper has not stopped. Retry unloading it.")
            self.session = nil
            self.session = try Session(
              directory: directory, configuration: self.configuration,
              cancellation: cancellation, progress: progress)
          }
          let result = try action(self.session!)
          try cancellation.check()
          continuation.resume(returning: result)
        } catch {
          if self.session?.helper.close() != false { self.session = nil }
          continuation.resume(throwing: error)
        }
      }
    }
  }
  func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, citationIDs: [String], progress: @escaping @Sendable (String) -> Void
  ) async throws -> ContextMeasurement {
    try await perform(directory: directory, cancellation: cancellation, progress: progress) {
      session in
      let thinking = !summary && self.configuration.reasoning.enabled
      let tools =
        summary
        ? nil
        : try NativeCitationPolicy.make(
          citationIDs, thinking: thinking,
          itemReferenceIDs: ItemReferenceCandidates.ids(in: messages),
          conversationActions: messages.first?.conversationActions,
          documentCopyIDs: DocumentCopyCandidates.ids(in: messages)
        ).promptTools()
      let prompt = try session.frontend.prepare(
        messages: messages.map(nativeTemplateMessage),
        tools: tools, thinking: thinking, contextLimit: SplashWire.maxTokens)
      return ContextMeasurement(
        promptTokens: prompt.tokens.count,
        capacity: self.configuration.contextBudget.contextTokens,
        templateIdentity: session.frontend.templateIdentity)
    }
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
      let prompt = try session.frontend.prepare(
        messages: messages.map(nativeTemplateMessage),
        contextLimit: self.configuration.contextBudget.contextTokens)
      try require(
        prompt.tokens.count + ContextDigest.maximumOutputTokens
          <= self.configuration.contextBudget.contextTokens,
        "context_limit", "The history batch exceeds its summary budget.")
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
      let generated = try session.helper.generate(
        request,
        cancelled: { cancellation.isCancelled || cancellation.isExpired },
        mask: { try constraint.masks(committed: $0, simulation: $1, words: $2) },
        event: { event in
          if case .tokens(_, _, let tokens) = event { _ = try output.append(tokens: tokens) }

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
          "phase": .string("context_summary"), "backend": .string("splash-native-candidate"),
          "promptTokens": .number(Double(prompt.tokens.count)),
          "contextTokens": .number(Double(self.configuration.contextBudget.contextTokens)),
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
    _ toolScope: InferenceToolScope, _ citationIDs: [String], _ interpretation: Value? = nil
  ) throws -> (NativeReply, Value) {
    let reasoning = configuration.reasoning
    let policy: SplashToolPolicy
    if let interpretation {
      let declaration: Value = .array([
        .object([
          "type": .string("function"),
          "function": .object([
            "name": .string("interpretation_result"),
            "description": .string(
              "Return only the requested interpretation. No execution or acceptance."),
            "parameters": interpretation["schema"],
          ]),
        ])
      ])
      policy = try SplashToolPolicy(
        toolsJSON: Data(declaration.json().utf8), thinking: reasoning.enabled)
    } else {
      policy = try NativeCitationPolicy.make(
        citationIDs, toolScope: toolScope, thinking: reasoning.enabled,
        itemReferenceIDs: ItemReferenceCandidates.ids(in: messages),
        conversationActions: messages.first?.conversationActions,
        documentCopyIDs: DocumentCopyCandidates.ids(in: messages))
    }
    let budget = configuration.contextBudget
    let prompt = try session.frontend.prepare(
      messages: messages.map(nativeTemplateMessage), tools: policy.promptTools(),
      thinking: reasoning.enabled, contextLimit: budget.contextTokens)
    let allowance = try budget.allowance(promptTokens: prompt.tokens.count)
    let outputBudget = min(
      allowance.outputTokens, interpretation?["maxOutputTokens"].int ?? allowance.outputTokens)
    let constraint = try session.factory.create(grammar: policy.grammar)
    let output = try SplashOutputStream(
      frontend: session.frontend, tools: policy.outputTools, thinking: reasoning.enabled)
    session.requestID += 1
    var request = SplashWire.Request(
      id: session.requestID, prompt: prompt.tokens,
      absoluteDeadline: UInt64((Date().timeIntervalSince1970 + 180) * 1e6),
      remainingDeadline: 180_000_000)
    request.maxOutput = UInt32(outputBudget)
    request.generationTokens = prompt.generationTokens
    request.tokenMask = true
    request.thinking = try reasoning.budget(outputTokens: outputBudget)
    if configuration.diagnosticRequestCacheIsolation {
      request.saltLow = session.requestID
      request.saltHigh = 0x5345_5652_4149_3200
    }
    try cancellation.check()
    progress("Thinking locally")
    var matchedPromptTokens = 0
    let generated = try session.helper.generate(
      request,
      cancelled: { cancellation.isCancelled || cancellation.isExpired },
      mask: { committed, simulation, words in
        let values = try constraint.masks(
          committed: committed, simulation: simulation, words: words)
        self.configuration.observeMask?(committed, simulation, words, values)
        return values
      },
      event: { event in
        if case .tokens(_, _, let tokens) = event { _ = try output.append(tokens: tokens) }
        if case .start(_, _, let matched) = event { matchedPromptTokens = Int(matched) }
      })
    try cancellation.check()
    try require(
      generated.done.reason == .stop && !generated.done.bounded,
      "truncated",
      "The model did not finish its response. No action from this response was applied.")
    try constraint.finish(committed: generated.tokens, requireComplete: true)
    let parsed = try output.finish(generated.done.reason).0
    let reasoningTokens = try reasoning.generatedTokens(generated.tokens)
    try require(parsed.calls.count == 1, "model_format", "Expected one complete native tool call.")
    let calls: [InferenceCall] = try parsed.calls.map { candidate in
      try policy.validate(candidate)
      return InferenceCall(
        id: "call_" + identifier(), name: candidate.name,
        inputJSON: String(decoding: candidate.arguments, as: UTF8.self))
    }
    try cancellation.check()
    let metrics: Value = .object([
      "backend": .string("splash-native-candidate"),
      "toolScope": .string(interpretation == nil ? toolScope.rawValue : "workflow_interpretation"),
      "requestSeconds": .number(generated.requestSeconds),
      "firstTokenSeconds": generated.firstTokenSeconds.map(Value.number) ?? .null,
      "promptTokens": .number(Double(prompt.tokens.count)),
      "matchedPromptTokens": .number(Double(matchedPromptTokens)),
      "deduplicatedKVTokens": .number(Double(generated.done.deduplicated)),
      "contextTokens": .number(Double(budget.contextTokens)),
      "maintenanceThreshold": .number(Double(budget.maintenanceThreshold)),
      "maintenanceRecommended": .bool(allowance.maintenanceRecommended),
      "nextToolResultReserve": .number(Double(budget.nextToolResultReserve)),
      "recoveryReserve": .number(Double(budget.recoveryReserve)),
      "outputBudget": .number(Double(outputBudget)),
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
    ])
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
    return (NativeReply(text: parsed.text, calls: calls, reasoning: parsed.reasoning), metrics)
  }

}

package func nativeTemplateMessage(_ message: InferenceMessage) throws -> [String: any Sendable] {
  var value: [String: any Sendable] = ["role": message.role, "content": message.content]
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
