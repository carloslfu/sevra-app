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
  package struct Configuration: Sendable {
    package let engine: URL
    package let engineFiles: [String: String]
    package let grammarLibrary: URL
    package let grammarSHA256: String
    package let modelsRoot: URL
    package let memoryBytes: UInt64
    package init(
      engine: URL, engineFiles: [String: String], grammarLibrary: URL,
      grammarSHA256: String, modelsRoot: URL, memoryBytes: UInt64
    ) {
      self.engine = engine
      self.engineFiles = engineFiles
      self.grammarLibrary = grammarLibrary
      self.grammarSHA256 = grammarSHA256
      self.modelsRoot = modelsRoot
      self.memoryBytes = memoryBytes
    }
  }
  package let identity =
    "Splash 1.4.1; 1744cfafee415fb463b289449cec59a864e768e9; Qwen3.6-35B-A3B-4bit + DFlash2; native Swift candidate"
  package private(set) var lastMetrics: Value = .null
  private let worker: NativeWorker
  private var leased = false
  private var active = false
  private var processLock: Int32 = -1
  private var idleRelease: Task<Void, Never>?
  package init(configuration: Configuration) { worker = NativeWorker(configuration) }

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

  @discardableResult package func unload() async -> Bool {
    guard !active && !leased else { return false }
    active = true
    idleRelease?.cancel()
    idleRelease = nil
    await worker.close()
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

  package func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, finishOnly: Bool, citationIDs: [String]
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
        progress: progress, finishOnly: finishOnly, citationIDs: citationIDs)
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
      let assembly = try SplashModelPreparation.prepare(
        pack: pack, target: directory, draft: directory.appendingPathComponent("dflash"),
        modelsRoot: configuration.modelsRoot,
        cancelled: { cancellation.isCancelled || cancellation.isExpired })
      try cancellation.check()
      frontend = try SplashTextFrontend(modelFolder: directory)
      factory = try SplashGrammarFactory(
        frontend: frontend, library: configuration.grammarLibrary,
        librarySHA256: configuration.grammarSHA256)
      try cancellation.check()
      progress("Loading local AI")
      helper = try SplashNativeProcess(
        executable: configuration.engine,
        arguments: [
          "serve-native", assembly.path, "8192", String(configuration.memoryBytes),
          "--persistent-cache", "off", "--idle-sleep", "allow", "--verify-rows", "all",
        ],
        timeout: 180, cancelled: { cancellation.isCancelled || cancellation.isExpired })
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

  func close() async {
    await withCheckedContinuation { continuation in
      queue.async {
        self.session = nil
        continuation.resume()
      }
    }
  }

  func shutdown(releasing descriptor: Int32) {
    queue.async {
      self.session = nil
      if descriptor >= 0 {
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
      }
    }
  }

  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, finishOnly: Bool, citationIDs: [String]
  ) async throws -> (NativeReply, Value) {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
          try cancellation.check()
          let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
          if self.session?.directory != directory {
            self.session = nil
            self.session = try Session(
              directory: directory, configuration: self.configuration,
              cancellation: cancellation, progress: progress)
          }
          let result = try self.generate(
            messages, self.session!, cancellation, progress, finishOnly, citationIDs)
          continuation.resume(returning: result)
        } catch {
          // A failed stream cannot leave hidden engine/grammar state for another
          // job. The next explicit request starts a new verified helper.
          self.session = nil
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func generate(
    _ messages: [InferenceMessage], _ session: Session,
    _ cancellation: Cancellation, _ progress: @escaping @Sendable (String) -> Void,
    _ finishOnly: Bool, _ citationIDs: [String]
  ) throws -> (NativeReply, Value) {
    let policy = try NativeCitationPolicy.make(citationIDs, finishOnly: finishOnly)
    let prompt = try session.frontend.prepare(
      messages: messages.map(Self.templateMessage), tools: policy.promptTools())
    let outputBudget = min(1800, 8192 - prompt.tokens.count)
    try require(
      outputBudget >= 256, "context_limit",
      "This exploration reached its context budget. Continue with a narrower question; completed changes are saved."
    )
    let constraint = try session.factory.create(grammar: policy.grammar)
    let output = try SplashOutputStream(frontend: session.frontend, tools: policy.outputTools)
    session.requestID += 1
    var request = SplashWire.Request(
      id: session.requestID, prompt: prompt.tokens,
      absoluteDeadline: UInt64((Date().timeIntervalSince1970 + 180) * 1e6),
      remainingDeadline: 180_000_000)
    request.maxOutput = UInt32(outputBudget)
    request.generationTokens = prompt.generationTokens
    request.tokenMask = true
    try cancellation.check()
    progress("Thinking locally")
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
      "truncated",
      "The model did not finish its response. No action from this response was applied.")
    try constraint.finish(committed: generated.tokens, requireComplete: true)
    let parsed = try output.finish(generated.done.reason).0
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
      "requestSeconds": .number(generated.requestSeconds),
      "firstTokenSeconds": generated.firstTokenSeconds.map(Value.number) ?? .null,
      "promptTokens": .number(Double(prompt.tokens.count)),
      "outputBudget": .number(Double(outputBudget)),
      "generatedTokens": .number(Double(generated.tokens.count)),
      "prefillSeconds": .number(Double(generated.done.prefillMicros) / 1e6),
      "decodeSeconds": .number(Double(generated.done.decodeMicros) / 1e6),
      "draftedTokens": .number(Double(generated.done.drafted)),
      "acceptedDraftTokens": .number(Double(generated.done.accepted)),
      "speculativeMethod": .string("DFlash2"),
    ])
    return (NativeReply(text: parsed.text, calls: calls), metrics)
  }

  private static func templateMessage(_ message: InferenceMessage) throws -> [String: any Sendable]
  {
    var value: [String: any Sendable] = ["role": message.role, "content": message.content]
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
}
