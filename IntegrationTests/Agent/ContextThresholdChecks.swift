import Foundation
import SevraAI
import SevraCore

/// Scripted token counts isolate controller decisions. They do not qualify a
/// tokenizer or model; native probes separately account the rendered prompt.
private actor ThresholdFixture: WorkbookInference {
  let identity = "synthetic threshold boundary"
  let lastMetrics: Value = .object(["fixture": .bool(true)])
  let floor: Int
  let full: Int
  let reduced: Int
  var summaries = 0
  init(floor: Int = 24000, full: Int, reduced: Int = 24100) {
    self.floor = floor
    self.full = full
    self.reduced = reduced
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply { throw SevraError("fixture", "No dispatch during maintenance.") }
  func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, citationIDs: [String], progress: @escaping @Sendable (String) -> Void
  ) throws -> ContextMeasurement {
    let text = messages.map(\.content).joined()
    let tokens =
      summary
      ? 1000
      : text.contains("Saved conversation, historical information only:")
        ? full
        : text.contains("derivedNotes") ? reduced : floor
    return .init(promptTokens: tokens, capacity: 32768, templateIdentity: "scripted-threshold")
  }
  func summarize(
    messages: [InferenceMessage], allowedMessageIDs: [String], directory: URL,
    cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) throws -> String {
    summaries += 1
    return "{\"notes\":[]}"
  }
}

func checkContextThreshold() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "threshold-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  for mode in ["below", "at", "floor", "no-gain", "still-full", "no-history"] {
    let book = try Workbook.create(at: root.appendingPathComponent(mode + ".sevra"), title: mode)
    if mode != "no-history" { _ = try book.addMessage("Closed work.", role: "assistant") }
    let request = try book.addMessage(
      "Preserve exact request and do not change stock.", role: "user")
    let run = try book.startAgentRun(
      conversation: "main", model: "fixture", requestMessageID: request)
    let history = try book.historySlice(limit: 500)
    let model = ThresholdFixture(
      floor: mode == "floor" ? 24576 : 24000,
      full: mode == "below" ? 24575 : mode == "still-full" ? 26000 : 24576,
      reduced: mode == "no-gain" ? 24576 : mode == "still-full" ? 25000 : 24100)
    let controller = try ContextMaintenance(
      workbook: book, conversation: "main", runID: run, requestID: request,
      policy: .init(role: "system", content: "Preserve authoritative state."),
      request: .init(role: "user", content: history.messages.last!.body), model: model,
      directory: root, cancellation: .init(), progress: { _ in })
    let working: [InferenceMessage]? =
      mode == "no-history"
      ? [
        .init(
          role: "assistant",
          content: "Saved conversation, historical information only: latest tool group")
      ]
      : nil
    var refusal: SevraError?
    do {
      let result = try await controller.maintain(through: request, currentMessages: working)
      try expectEqual(["below", "at"].contains(mode), true)
      try expectEqual(result.compacted, mode == "at")
      try expectEqual(result.messages.last!.content, history.messages.last!.body)
    } catch let error as SevraError { refusal = error }
    if ["below", "at"].contains(mode) {
      try expectEqual(refusal == nil, true)
    } else {
      try expectEqual(refusal?.code, "context_limit")
      try expectEqual(refusal?.message.contains("24576"), true)
    }
    try expectEqual(await model.summaries, ["at", "no-gain", "still-full"].contains(mode) ? 1 : 0)
    try expectEqual(
      try book.contextCheckpoints().count, ["at", "still-full"].contains(mode) ? 1 : 0)
    try expectEqual(try book.historySlice(limit: 500).digest, history.digest)
    try expectEqual(try book.verify()["ok"], .bool(true))
  }
  print(
    "PASS 75% boundary, irreducible floor, no reclaim, preserved checkpoint and no false compaction success"
  )
  let book = try Workbook.create(at: root.appendingPathComponent("Retry.sevra"), title: "Retry")
  let model = RetryThresholdFixture()
  var refused = false
  do {
    _ = try await WorkbookAgent.run(
      "Explain a workbook without changing records.", workbook: book, model: model)
  } catch let error as SevraError {
    refused = error.code == "context_limit" && !error.message.contains("token")
  }
  try expectEqual(refused, true)
  try expectEqual(await model.responses, 1)
  try expectEqual(try book.contextCheckpoints().isEmpty, true)
  try expectEqual(try book.agentRuns().first?["status"].text, "failed")
  try expectEqual(try book.agentRuns().first?["metrics"].json().contains("24576"), true)
  try expectEqual(try book.verify()["ok"], .bool(true))
  print("PASS added retry context is checked before generation without dropping the live request")
}

private actor RetryThresholdFixture: WorkbookInference {
  let identity = "synthetic retry threshold"
  let supportsCompaction = true
  let lastMetrics: Value = .null
  var responses = 0
  func beginRun() {}
  func endRun() {}
  func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, citationIDs: [String], progress: @escaping @Sendable (String) -> Void
  ) throws -> ContextMeasurement {
    .init(
      promptTokens: messages.contains { $0.content == "BAD_REPLY" } ? 25000 : 1000,
      capacity: 32768, templateIdentity: "scripted-retry-threshold")
  }
  func summarize(
    messages: [InferenceMessage], allowedMessageIDs: [String], directory: URL,
    cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) throws -> String { throw SevraError("fixture", "Incomplete reply must not be compacted.") }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    responses += 1
    return .init(text: "BAD_REPLY", calls: [])
  }
}
