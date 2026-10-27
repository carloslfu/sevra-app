import Foundation
import SevraAI
import SevraCore

private actor EvidenceHandoffModel: WorkbookInference {
  let identity = "synthetic handoff evidence"
  let lastMetrics: Value = .null
  let book: Workbook
  let originals: [Item]
  let historyID: String
  let stale: Bool
  var calls = 0
  func beginRun() {}
  func endRun() {}
  init(book: Workbook, originals: [Item], historyID: String, stale: Bool) {
    self.book = book
    self.originals = originals
    self.historyID = historyID
    self.stale = stale
  }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    calls += 1
    let tool: String
    let arguments: Value
    switch calls {
    case 1:
      tool = "history_read"
      arguments = .object(["id": .string(historyID)])
    case 2, 3:
      tool = "read"
      arguments = .object(["id": .string(originals[calls - 2].id)])
    case 4:
      tool = "calculate"
      arguments = .object(["expression": .string("14.80 - 12.40")])
    case 5:
      if stale {
        _ = try book.addItem(
          category: "source", kind: "quote", title: "Cedar revised",
          text: "The new unit cost is 11.00.",
          supersedes: originals[1].id)
      }
      tool = "start_thread_and_continue"
      arguments = .object([
        "task": .string("compare the original quotes"), "work": .string("answer"),
        "title": .string("Quotes"),
      ])
    default:
      try expectEqual(calls, 6)
      try expectEqual(
        Set(citationIDs), Set((stale ? Array(originals.prefix(1)) : originals).map(\.id)))
      try expectEqual(messages.map(\.reasoning).joined(), "")
      try expectEqual(messages.map(\.content).joined().contains("Outside selected excerpt"), false)
      try expectEqual(messages.map(\.content).joined().contains("Untrusted assistant prose"), false)
      let carried = messages.flatMap(\.toolCalls).map(\.name)
      try expectEqual(carried, stale ? ["read"] : ["read", "read", "calculate"])
      try expectEqual(messages[0].conversationActions, [])
      try expectEqual(toolScope, .answer)
      tool = "finish"
      arguments = .object([
        "answer": .string(
          stale
            ? "An original needs another read before I can answer." : "Cedar is 2.4 lower per unit."
        ),
        "basis": .string(stale ? "unresolved" : "evidence"),
        "citations": .array(stale ? [] : originals.map { .string($0.id) }),
      ])
    }
    return .init(
      text: "Untrusted assistant prose",
      calls: [.init(id: identifier(), name: tool, inputJSON: try arguments.json())],
      reasoning: "Private ephemeral reasoning")
  }
}

func checkHandoffEvidence() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-carry-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  for stale in [false, true] {
    let book = try Workbook.create(
      at: root.appendingPathComponent("live-\(stale).sevra"), title: "Quotes")
    let old = try book.addMessage("Outside selected excerpt", role: "user")
    for index in 0..<10 { _ = try book.addMessage("Closed note \(index)", role: "assistant") }
    _ = try book.addMessage("We can examine quotes.", role: "user")
    _ = try book.addMessage("Both quotes are available.", role: "assistant")
    let originals = try [
      book.addItem(category: "source", kind: "quote", title: "Birch", text: "Unit cost 14.80."),
      book.addItem(category: "source", kind: "quote", title: "Cedar", text: "Unit cost 12.40."),
    ]
    let model = EvidenceHandoffModel(book: book, originals: originals, historyID: old, stale: stale)
    let result = try await WorkbookAgent.run(
      "Start a thread and compare the original quotes.", workbook: book,
      context: originals.map(\.id).joined(separator: " "), model: model, enableCompaction: false)
    try expectEqual(result.steps, 6)
    try expectEqual(result.state, "complete")
    let child = result.conversationAction!.conversation
    try expectEqual(try book.messages(conversation: child).filter { $0.role == "tool" }.count, 0)
    // An exact result was transferred, not executed again or made into a new Source.
    try expectEqual(try book.items().filter { $0.kind == "request" }.count, 1)
    let future = try WorkbookAgent.conversationHistory(book, conversation: child)
    try expectEqual(future.flatMap(\.toolCalls).count, 0)
    try expectEqual(future.map(\.content).joined().contains("resultHash"), false)
    try expectEqual(try Workbook(book.url).verify()["ok"], .bool(true))
  }
  // Bound allocation and prove projected/unobserved results never establish proof.
  for mode in ["bytes", "count", "projection", "failed"] {
    let book = try Workbook.create(at: root.appendingPathComponent(mode + ".sevra"), title: mode)
    let prompt = "Start a thread and compare the original quotes."
    let run = try book.startAgentRequest(prompt, conversation: "main", model: "fixture")
    let source = try book.addItem(
      category: "source", kind: "request", title: "Request", text: prompt,
      data: .object(["messageID": .string(run.messageID), "conversationID": .string("main")]))
    let tools = WorkbookTools(
      book, runID: run.runID, requestSourceID: source.id, conversationTitle: "Main conversation")
    func execute(_ tool: String, _ arguments: Value, failed: Bool = false) throws -> String {
      let receipt = try book.prepareToolCall(
        runID: run.runID, callID: identifier(), tool: tool, arguments: arguments, assistantText: "")
      let value =
        failed
        ? Value.object(["error": .string("Fixture failure")]) : try tools.execute(tool, arguments)
      _ = try book.completeToolCall(receipt, result: value, failed: failed)
      return receipt
    }
    for index in 0..<(mode == "count" ? 9 : mode == "bytes" ? 5 : 1) {
      let item = try book.addItem(
        category: "source", kind: "quote", title: "Quote \(index)",
        text: mode == "projection"
          ? String(repeating: "Wide source text ", count: 1000) : "Unit cost 12.40.",
        data: mode == "bytes" || mode == "projection"
          ? .object(["padding": .string(String(repeating: "x", count: 11000))]) : .object([:]))
      _ = try execute("read", .object(["id": .string(item.id)]), failed: mode == "failed")
    }
    _ = try execute("calculate", .object(["expression": .string("14.8-12.4")]))
    let receipt = try execute(
      "start_thread_and_continue",
      .object(["task": .string("compare the original quotes"), "work": .string("answer")]))
    let handed = try book.handoffAgentRequest(
      runID: run.runID, receiptID: receipt, sourceID: source.id, steps: 11, metrics: .array([]))
    let entries = handed.evidence["entries"].array
    try expectEqual(entries.allSatisfy { $0["tool"].text == "read" }, true)
    try expectEqual(entries.count <= 8, true)
    try expectEqual(try Value.array(entries).json().utf8.count <= 32_000, true)
    try expectEqual(handed.evidence["omitted"].int! > 0, true)
    if mode == "count" { try expectEqual(entries.count, 8) }
    if mode == "bytes" { try expectEqual(entries.count > 0 && entries.count < 5, true) }
    if ["projection", "failed"].contains(mode) { try expectEqual(entries.count, 0) }
    let replay = try book.handoffAgentRequest(
      runID: run.runID, receiptID: receipt, sourceID: source.id, steps: 11, metrics: .array([]))
    try expectEqual(replay.evidence, handed.evidence)
    try expectEqual(try book.verify()["ok"], .bool(true))
  }
  print(
    "PASS handoff evidence: exact same-request reads/calculation, scoped history, changed heads, projection/failure refusal, byte/count bounds and replay"
  )
}
