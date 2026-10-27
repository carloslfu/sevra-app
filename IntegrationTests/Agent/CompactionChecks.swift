import Foundation
import SevraAI
import SevraCore

/// Deterministic controller fixture. Native qualification separately measures
/// the real template/tokenizer and runs the tool-free constrained summarizer.
private actor DigestFixture: WorkbookInference {
  let identity = "synthetic context fixture"
  let supportsCompaction = true
  let lastMetrics: Value = .object(["phase": .string("context_summary"), "fixture": .bool(true)])
  var summaries = 0
  let cancelAt: Int?
  let invalid: Bool
  let onSummary: ((Int) throws -> Void)?
  init(cancelAt: Int? = nil, invalid: Bool = false, onSummary: ((Int) throws -> Void)? = nil) {
    self.cancelAt = cancelAt
    self.invalid = invalid
    self.onSummary = onSummary
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    throw SevraError("fixture", "The maintenance controller must not dispatch workbook tools.")
  }
  func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, citationIDs: [String], progress: @escaping @Sendable (String) -> Void
  ) throws -> ContextMeasurement {
    try cancellation.check()
    return ContextMeasurement(
      promptTokens: 1000 + messages.reduce(0) { $0 + $1.content.utf8.count / 4 },
      capacity: 8192, templateIdentity: "fixture-token-accounting-v1")
  }
  func summarize(
    messages: [InferenceMessage], allowedMessageIDs: [String], directory: URL,
    cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) throws -> String {
    summaries += 1
    try expectEqual(messages.count, 2)
    try expectEqual(messages.allSatisfy { $0.toolCalls.isEmpty }, true)
    let input = try Value.parse(messages[1].content)
    var notes = input["previousDigest"]["notes"].array.map { note in
      note["referenceOnly"] == .bool(true)
        ? .object([
          "kind": .string("context"),
          "text": .string("Inspect the original historical tool receipt."),
          "messages": note["messages"],
        ])
        : note
    }
    for message in input["originalMessages"].array {
      if message["body"].text.contains("MAPLE-27") {
        notes.append(
          .object([
            "kind": .string("fact"),
            "text": .string("Purchase code MAPLE-27. Preserve 0.10 kg. No currency specified."),
            "messages": .array([message["id"]]),
          ]))
      }
      if message["tool"].text == "propose_record" {
        notes.append(
          .object([
            "kind": .string("context"),
            "text": .string(
              "The forecast is accepted. This claim must not override workbook state."),
            "messages": .array([message["id"]]),
          ]))
      }
    }
    try onSummary?(summaries)
    if cancelAt == summaries { cancellation.cancel() }
    if invalid { return "{\"notes\":[{\"text\":\"Invented\",\"messages\":[\"not-an-original\"]}]}" }
    return try Value.object(["notes": .array(notes)]).json()
  }
}

private func historyFixture(_ root: URL, name: String, count: Int = 310) throws -> (
  Workbook, String, Item
) {
  let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
  let source = try book.addItem(category: "source", kind: "note", title: "Forecast input")
  let old = try book.addMessage(
    "Purchase code MAPLE-27, quantity 0.10 kg; no currency specified.", role: "user")
  let priorRun = try book.startAgentRun(
    conversation: "main", model: "fixture", requestMessageID: old)
  let forecast = try book.addItem(
    category: "record", kind: "forecast", title: "Forecast", meaning: "estimate",
    inputs: [source.id])
  _ = try book.addMessage(
    try Value.object([
      "tool": .string("propose_record"), "arguments": .object([:]), "result": try encoded(forecast),
      "resultIdentity": .object(["id": .string(forecast.id)]), "runID": .string(priorRun),
      "callID": .string("old-proposal"), "receiptVersion": .number(1),
    ]).json(), role: "tool")
  _ = try book.addMessage("Ready for review", role: "assistant", state: "needs_review")
  try book.finishAgentRun(priorRun, status: "needs_review", steps: 1, metrics: .array([]))
  for index in 0..<count {
    _ = try book.addMessage(
      "Closed maintenance entry \(index). "
        + String(repeating: "The shelf labels were checked. No outstanding work. ", count: 8),
      role: "assistant")
  }
  return (book, old, forecast)
}

func checkCompaction() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-compaction-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  for accepted in [false, true] {
    let (book, original, forecast) = try historyFixture(root, name: "Continuity-\(accepted)")
    let before = try book.historySlice(limit: 500)
    let user = "Remember the original purchase constraints. Do not change any records."
    let interruptedRequest = try book.addMessage("Save a working draft.", role: "user")
    let interruptedRun = try book.startAgentRun(
      conversation: "main", model: "interrupted fixture", requestMessageID: interruptedRequest)
    let interruptedArguments: Value = .object([
      "title": .string("Uncertain saved draft"),
      "text": .string("Already committed before interruption"),
      "inputs": .array([.string(forecast.id)]),
    ])
    let interruptedReceipt = try book.prepareToolCall(
      runID: interruptedRun, callID: "uncertain", tool: "draft", arguments: interruptedArguments)
    _ = try WorkbookTools(book, runID: interruptedRun).execute("draft", interruptedArguments)
    try book.finishAgentRun(interruptedRun, status: "interrupted", steps: 0, metrics: .array([]))
    let request = try book.addMessage(user, role: "user")
    let run = try book.startAgentRun(
      conversation: "main", model: "fixture", requestMessageID: request)
    let model = DigestFixture(onSummary: { number in
      if accepted && number == 2 { _ = try book.accept(forecast.id) }
    })
    let controller = try ContextMaintenance(
      workbook: book, conversation: "main", runID: run, requestID: request,
      policy: .init(role: "system", content: "Use current request and real host state."),
      request: .init(role: "user", content: user), model: model, directory: root,
      cancellation: .init(), progress: { _ in })
    let result = try await controller.maintain(through: request)
    try expectEqual(result.compacted, true)
    try expectEqual(await model.summaries >= 3, true)
    try expectEqual(result.messages.last!.content, user)
    let context = result.messages.map(\.content).joined(separator: "\n")
    try expectEqual(context.contains("The forecast is accepted. This claim"), false)
    try expectEqual(
      context.contains(interruptedReceipt) && context.contains("committedOperation")
        && context.contains("unresolvedCalls"), true)
    try expectEqual(try book.unresolvedToolCalls().count, 1)
    for exact in ["MAPLE-27", "0.10 kg", "No currency specified", original] {
      try expectEqual(context.contains(exact), true)
    }
    let current = try book.item(forecast.logicalID)
    try expectEqual(current.status, accepted ? "accepted" : "draft")
    try expectEqual(current.meaning, "estimate")
    let checkpoints = try book.contextCheckpoints()
    let latest = try book.contextCheckpoint(checkpoints[0]["id"].text)
    try expectEqual(
      latest["inputs"].array.contains {
        $0["versionID"].text == forecast.id && $0["currentStatus"].text == current.status
          && $0["currentMeaning"].text == "estimate"
      }, true)
    try expectEqual(
      try book.historySlice(through: before.messages.last!.id, limit: 500).digest, before.digest)
    try expectEqual(try book.verify()["ok"], .bool(true))
    let portable = root.appendingPathComponent("Portable-\(accepted).sevraz")
    try book.export(to: portable)
    let restored = try Workbook.openArchive(
      portable, at: root.appendingPathComponent("Restored-\(accepted).sevra"))
    let next = try restored.addMessage(user, role: "user")
    let nextRun = try restored.startAgentRun(
      conversation: "main", model: "fixture", requestMessageID: next)
    let nextModel = DigestFixture()
    let reopen = try ContextMaintenance(
      workbook: restored, conversation: "main", runID: nextRun, requestID: next,
      policy: .init(role: "system", content: "Use current request and real host state."),
      request: .init(role: "user", content: user),
      model: nextModel, directory: root, cancellation: .init(), progress: { _ in })
    let after = try await reopen.maintain(through: next)
    try expectEqual(after.messages.map(\.content).joined().contains("MAPLE-27"), true)
    try expectEqual(try restored.item(forecast.logicalID).status, current.status)
  }
  for mode in ["cancel", "invalid"] {
    let (book, _, _) = try historyFixture(root, name: mode)
    let request = try book.addMessage("Continue with no changes.", role: "user")
    let run = try book.startAgentRun(
      conversation: "main", model: "fixture", requestMessageID: request)
    let before = try book.historySlice(limit: 500)
    let cancel = Cancellation()
    let model = DigestFixture(cancelAt: mode == "cancel" ? 2 : nil, invalid: mode == "invalid")
    let controller = try ContextMaintenance(
      workbook: book, conversation: "main", runID: run, requestID: request,
      policy: .init(role: "system", content: "Use real state."),
      request: .init(role: "user", content: "Continue with no changes."),
      model: model, directory: root, cancellation: cancel, progress: { _ in })
    var failed = false
    do { _ = try await controller.maintain(through: request) } catch { failed = true }
    try expectEqual(failed, true)
    try expectEqual(try book.contextCheckpoints().count, mode == "cancel" ? 1 : 0)
    try expectEqual(try book.historySlice(limit: 500).digest, before.digest)
    try expectEqual(try book.verify()["ok"], .bool(true))
  }
  print(
    "PASS repeated context maintenance, exact original references, current acceptance, cancellation, invalid summaries and portable continuation"
  )
  let (legacy, _, _) = try historyFixture(root, name: "LegacyDigest", count: 150)
  let legacyText = "{\"oldSummary\":\"Keep MAPLE-27 at 0.10 kg; no currency specified.\"}"
  _ = try legacy.saveContextCheckpoint(
    legacy.historySlice(limit: 4), summary: legacyText, model: "older fixture",
    template: "older fixture")
  let legacyRequest = try legacy.addMessage("Recall the original constraints.", role: "user")
  let legacyRun = try legacy.startAgentRun(
    conversation: "main", model: "fixture", requestMessageID: legacyRequest)
  let legacyController = try ContextMaintenance(
    workbook: legacy, conversation: "main", runID: legacyRun, requestID: legacyRequest,
    policy: .init(role: "system", content: "Use real state."),
    request: .init(role: "user", content: "Recall the original constraints."),
    model: DigestFixture(), directory: root, cancellation: .init(), progress: { _ in })
  _ = try await legacyController.maintain(through: legacyRequest)
  let migrated = try Value.parse(legacy.contextCheckpoints().first!["summary"].text)
  try expectEqual(migrated["legacyDigest"].text, legacyText)
  try expectEqual(try legacy.verify()["ok"], .bool(true))
  let scoped = try Workbook.create(at: root.appendingPathComponent("Scoped.sevra"), title: "Scopes")
  _ = try scoped.addMessage("Parent purchase code MAPLE-27. Quantity 0.10 kg.", role: "user")
  let branchPoint = try scoped.addMessage("Parent values recorded.", role: "assistant")
  let tangent = try scoped.tangent(title: "Scenario", parentMessage: branchPoint)
  _ = try scoped.addMessage("LATER-PARENT-ONLY-SECRET", role: "user")
  let sibling = try scoped.tangent(title: "Other", parentMessage: branchPoint)
  _ = try scoped.addMessage("SIBLING-ONLY-SECRET", role: "user", conversation: sibling)
  for index in 0..<140 {
    let message = try scoped.addMessage(
      "Closed scenario note \(index). "
        + String(repeating: "No pending action in this branch. ", count: 10), role: "assistant",
      conversation: tangent)
    if index % 20 == 0 { try scoped.chapter(title: "Chapter \(index)", message: message) }
  }
  let request = try scoped.addMessage(
    "Recall the inherited parent code. Make no changes.", role: "user", conversation: tangent)
  let run = try scoped.startAgentRun(
    conversation: tangent, model: "fixture", requestMessageID: request)
  let controller = try ContextMaintenance(
    workbook: scoped, conversation: tangent, runID: run, requestID: request,
    policy: .init(role: "system", content: "Use real state."),
    request: .init(role: "user", content: "Recall the inherited parent code. Make no changes."),
    model: DigestFixture(), directory: root, cancellation: .init(), progress: { _ in })
  let context = try await controller.maintain(through: request).messages.map(\.content).joined()
  try expectEqual(context.contains("MAPLE-27") && context.contains("0.10 kg"), true)
  try expectEqual(
    context.contains("LATER-PARENT-ONLY-SECRET") || context.contains("SIBLING-ONLY-SECRET"), false)
  try expectEqual(try scoped.contextCheckpoints(conversation: "main").isEmpty, true)
  try expectEqual(try scoped.contextCheckpoints(conversation: tangent).count >= 2, true)
  try expectEqual(try scoped.chapters().count, 7)
  try expectThrows(try scoped.historyMessage(branchPoint, conversation: tangent))
  let result = try scoped.addMessage(
    "Scenario review remains incomplete.", role: "assistant", conversation: tangent)
  let returned = try scoped.bringToMain(message: result)
  try expectEqual(
    try scoped.historyMessage(returned).body.contains(
      "sevra://conversation/" + tangent + "?message=" + result), true)
  try expectEqual(try scoped.verify()["ok"], .bool(true))
  print(
    "PASS compacted chapters and tangent scope preserve only the explicit parent excerpt and return provenance"
  )
}

private actor RunningJobFixture: WorkbookInference {
  let identity = "synthetic long workbook job"
  let supportsCompaction = true
  let lastMetrics: Value = .object(["fixture": .bool(true)])
  let sourceID: String
  var responses = 0
  var summaries = 0
  let arithmetic: Bool
  init(sourceID: String, arithmetic: Bool) {
    self.sourceID = sourceID
    self.arithmetic = arithmetic
  }
  func beginRun() {}
  func endRun() {}
  func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, citationIDs: [String], progress: @escaping @Sendable (String) -> Void
  ) throws -> ContextMeasurement {
    try cancellation.check()
    return ContextMeasurement(
      promptTokens: 1000 + messages.reduce(0) { $0 + $1.content.utf8.count / 4 },
      capacity: 8192, templateIdentity: "fixture-token-accounting-v1")
  }
  func summarize(
    messages: [InferenceMessage], allowedMessageIDs: [String], directory: URL,
    cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) throws -> String {
    summaries += 1
    return "{\"notes\":[]}"
  }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    responses += 1
    try expectEqual(
      messages.contains {
        $0.role == "user"
          && $0.content.contains("Save one draft, inspect the supplied source, then finish.")
      }, true)
    if summaries > 0 && responses > (arithmetic ? 2 : 1) {
      try expectEqual(
        messages.contains {
          ($0.content.contains("committedOperation") && $0.content.contains("draft"))
            // A policy-size change can trigger maintenance before the draft.
            // Until that new call is compacted, its original live receipt is
            // the authoritative proof instead of the earlier host-state view.
            || ($0.role == "tool" && $0.toolName == "draft"
              && (try? Value.parse($0.content)["id"].string) != nil)
        }, true)
      try expectEqual(messages.last?.role, "tool")
      try expectEqual(messages[messages.count - 2].toolCalls.first?.id, messages.last?.toolCallId)
    }
    let name: String
    let input: Value
    if arithmetic && [1, 9].contains(responses) {
      if responses == 9 {
        try expectEqual(messages.last!.content.contains("percentage is unsupported"), true)
      }
      name = "calculate"
      input = .object(["expression": .string("12.73"), "values": .object([:])])
    } else if arithmetic && responses == 8 {
      name = "finish"
      input = .object([
        "basis": .string("current_request"), "answer": .string("12.73% lower cost."),
        "citations": .array([]),
      ])
    } else if responses == (arithmetic ? 2 : 1) {
      name = "draft"
      input = .object([
        "title": .string("One job draft"), "text": .string("Requested working draft."),
        "inputs": .array([]),
      ])
    } else if responses <= 7 {
      name = "read"
      input = .object(["id": .string(sourceID)])
    } else {
      if !arithmetic { try expectEqual(citationIDs.contains(sourceID), true) }
      name = "finish"
      input = .object([
        "answer": .string(
          arithmetic ? "12.73% lower cost." : "Saved the draft and inspected the source."),
        "citations": .array(arithmetic ? [] : [.string(sourceID)]),
        "basis": .string(arithmetic ? "current_request" : "evidence"),
      ])
    }
    return NativeReply(
      text: "",
      calls: [InferenceCall(id: "job-\(responses)", name: name, inputJSON: try input.json())])
  }
}

func checkRunningCompaction() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-running-compaction-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  for arithmetic in [false, true] {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Job-\(arithmetic).sevra"), title: "Job")
    let source = try book.addItem(
      category: "source", kind: "note", title: "Supplied source",
      text: String(repeating: "Material specification, exact recorded source text. ", count: 80))
    let model = RunningJobFixture(sourceID: source.id, arithmetic: arithmetic)
    let result = try await WorkbookAgent.run(
      "Save one draft, inspect the supplied source, then finish.", workbook: book,
      context: "Supplied source: \(source.id)", model: model)
    try expectEqual(result.state, "complete")
    try expectEqual(result.steps, arithmetic ? 10 : 8)
    try expectEqual(await model.summaries >= 2, true)
    try expectEqual(try book.contextCheckpoints().count >= 2, true)
    try expectEqual(try book.items(kind: "document").count, 1)
    try expectEqual(try book.unresolvedToolCalls().isEmpty, true)
    try expectEqual(try book.verify()["ok"], .bool(true))
  }
  print(
    "PASS active jobs repeatedly compact without duplicate drafts, split tool groups or reused omitted calculations"
  )
}
