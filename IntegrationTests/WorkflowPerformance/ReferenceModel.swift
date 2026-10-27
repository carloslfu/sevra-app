import Darwin
import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

final class Observations: @unchecked Sendable {
  private let lock = NSLock()
  private var rows: [Value] = []
  func append(_ row: Value) {
    lock.lock()
    rows.append(row)
    lock.unlock()
  }
  func reset() {
    lock.lock()
    rows = []
    lock.unlock()
  }
  func snapshot() -> [Value] {
    lock.lock()
    defer { lock.unlock() }
    return rows
  }
}

/// Evaluation only: the installed app never links this target or starts Python.
actor ReferenceModel: WorkbookInference {
  let identity = "Pinned Splash Python reference; shared workbook host; bounded512"
  private(set) var lastMetrics: Value = .null
  private let worker: ReferenceWorker
  private let observations: Observations
  private var lease: Int32 = -1
  private var leased = false
  init(config: Value, observations: Observations) {
    worker = ReferenceWorker(config: config)
    self.observations = observations
  }
  func beginRun() throws {
    try require(!leased, "busy", "Reference run already active")
    if lease < 0 {
      let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/Sevra")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let fd = Darwin.open(
        folder.appendingPathComponent("inference.lock").path,
        O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
      try require(fd >= 0, "model_lock", "Cannot open reference lease")
      guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        Darwin.close(fd)
        throw SevraError("model_busy", "Another process owns local inference")
      }
      lease = fd
    }
    leased = true
  }
  func endRun() { leased = false }
  func releaseResources() async -> Bool {
    guard !leased, await worker.close() else { return false }
    if lease >= 0 {
      flock(lease, LOCK_UN)
      Darwin.close(lease)
      lease = -1
    }
    return true
  }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    try require(leased, "busy", "Reference needs a run lease")
    let policy = try NativeCitationPolicy.make(citationIDs, toolScope: toolScope, thinking: true)
    let body: [String: Any] = [
      "messages": try messages.map(nativeTemplateMessage),
      "tools": try JSONSerialization.jsonObject(with: policy.toolsJSON),
      "tool_choice": "required", "parallel_tool_calls": false,
      "chat_template_kwargs": ["enable_thinking": true], "preserve_thinking": false,
      "thinking_token_budget": 512, "max_tokens": 1800,
      "priority": "foreground", "temperature": 0, "top_p": 1, "top_k": 0, "min_p": 0,
      "presence_penalty": 0, "frequency_penalty": 0, "repetition_penalty": 1, "seed": 42,
    ]
    let value = try Value.parse(
      String(
        decoding: JSONSerialization.data(
          withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self))
    let started = ProcessInfo.processInfo.systemUptime
    let row = try await worker.request(value, cancellation: cancellation)
    try require(
      row["finish"].int == 0 && row["bounded"] == .bool(false), "truncated",
      "Reference did not finish normally")
    let metrics: Value = .object([
      "backend": .string("splash-python-reference"), "toolScope": .string(toolScope.rawValue),
      "promptTokens": .number(Double(row["promptTokens"].array.count)),
      "matchedPromptTokens": row["matchedPromptTokens"],
      "contextTokens": .number(32768),
      "outputBudget": .number(1800), "reasoningBudget": .number(512),
      "requestSeconds": row["completeSeconds"], "firstTokenSeconds": row["firstTokenSeconds"],
      "prefillSeconds": row["prefillSeconds"], "decodeSeconds": row["decodeSeconds"],
      "bridgeWallSeconds": .number(ProcessInfo.processInfo.systemUptime - started),
      "generatedTokens": .number(Double(row["tokens"].array.count)),
    ])
    lastMetrics = metrics
    observations.append(
      .object([
        "promptTokens": row["promptTokens"], "generationTokens": row["generationTokens"],
        "tokens": row["tokens"], "requestFrame": row["requestFrame"], "metrics": metrics,
      ]))
    return NativeReply(
      text: row["text"].text,
      calls: try row["calls"].array.enumerated().map { index, call in
        InferenceCall(
          id: "reference_\(index)", name: call["name"].text, inputJSON: try call["arguments"].json()
        )
      }, reasoning: row["reasoning"].text)
  }
}

private final class ReferenceWorker: @unchecked Sendable {
  private let queue = DispatchQueue(label: "sevra.workflow-reference")
  private let config: Value
  private var process: Process?
  private var input: FileHandle?
  private var output: FileHandle?
  private var pending = Data()
  private var helper: Int32?
  private var sequence = 0
  init(config: Value) { self.config = config }
  private func line(_ token: Cancellation, timeout: Double = 200) throws -> Value {
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    while true {
      try token.check()
      if let end = pending.firstIndex(of: 10) {
        let bytes = pending.prefix(upTo: end)
        pending.removeSubrange(...end)
        let row = try Value.parse(String(decoding: bytes, as: UTF8.self))
        if let error = row["error"].string { throw SevraError("reference", error) }
        return row
      }
      try require(
        ProcessInfo.processInfo.systemUptime < deadline, "reference_timeout",
        "Reference response deadline expired")
      guard let output else { throw SevraError("reference", "Reference pipe is closed") }
      var descriptor = pollfd(
        fd: output.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
      let result = poll(&descriptor, 1, 100)
      if result < 0 && errno == EINTR { continue }
      try require(result >= 0, "reference", "Reference poll failed")
      if result == 0 { continue }
      var bytes = [UInt8](repeating: 0, count: 65536)
      let count = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
      if count < 0 && errno == EINTR { continue }
      try require(count > 0, "reference", "Reference exited before response")
      pending.append(contentsOf: bytes.prefix(count))
      try require(
        pending.count <= 16 * 1024 * 1024, "reference",
        "Reference response exceeds qualification bound")
    }
  }
  private func send(_ value: Value) throws {
    guard let input else { throw SevraError("reference", "Reference input is closed") }
    try input.write(contentsOf: Data((try value.json() + "\n").utf8))
  }
  private func start(_ token: Cancellation) throws {
    if process != nil { return }
    let child = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    child.executableURL = URL(fileURLWithPath: config["python"].text)
    child.arguments = [config["referenceScript"].text, config["configPath"].text]
    child.environment = ProcessInfo.processInfo.environment.merging(
      ["HF_HUB_OFFLINE": "1", "TOKENIZERS_PARALLELISM": "false"], uniquingKeysWith: { _, b in b })
    child.standardInput = stdin
    child.standardOutput = stdout
    child.standardError = FileHandle.standardError
    try child.run()
    process = child
    input = stdin.fileHandleForWriting
    output = stdout.fileHandleForReading
    let ready = try line(token)
    try require(ready["ready"] == .bool(true), "reference", "Reference did not become ready")
    helper = ready["helperPID"].int.map(Int32.init)
  }
  func request(_ body: Value, cancellation: Cancellation) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
          try self.start(cancellation)
          self.sequence += 1
          try self.send(
            .object([
              "op": .string("workflow"), "id": .string("step-\(self.sequence)"), "body": body,
            ]))
          continuation.resume(returning: try self.line(cancellation))
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
  func close() async -> Bool {
    await withCheckedContinuation { continuation in
      queue.async {
        guard let process = self.process else {
          continuation.resume(returning: true)
          return
        }
        var graceful = false
        do {
          try self.send(.object(["op": .string("close")]))
          graceful = try self.line(Cancellation(), timeout: 20)["closed"] == .bool(true)
        } catch {}
        self.input?.closeFile()
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
          Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
          process.terminate()
          Thread.sleep(forTimeInterval: 0.2)
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        self.output?.closeFile()
        let helperGone = self.helper.map { kill($0, 0) == -1 && errno == ESRCH } ?? true
        self.process = nil
        self.input = nil
        self.output = nil
        self.pending = Data()
        continuation.resume(returning: graceful && helperGone && process.terminationStatus == 0)
      }
    }
  }
}
