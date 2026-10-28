import Foundation
import SevraAI
import SevraCore

private actor RequestEnvelopeModel: WorkbookInference {
  let identity = "synthetic request envelope"
  let lastMetrics: Value = .null
  let book: Workbook
  let prompt: String
  let context: String
  let branch: Bool
  var responses = 0
  var originalSource: String?
  init(_ book: Workbook, prompt: String, context: String, branch: Bool) {
    self.book = book
    self.prompt = prompt
    self.context = context
    self.branch = branch
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    responses += 1
    let user = messages.last { $0.role == "user" }!
    try expectEqual(user.content, prompt + (context.isEmpty ? "" : "\nVisible context: " + context))
    let system = messages[0].content
    guard let start = system.range(of: "\nHost submission context: ") else {
      throw SevraError("fixture", "Missing host submission context")
    }
    let host = try Value.parse(String(system[start.upperBound...]))
    let source = try book.item(host["requestSourceID"].text)
    try expectEqual(source.text, prompt)
    try expectEqual(source.kind, "request")
    try expectEqual(citationIDs, [])
    if let originalSource { try expectEqual(source.id, originalSource) }
    originalSource = source.id
    if responses == 1 {
      try expectEqual(host["continuation"], .null)
    } else {
      try expectEqual(host["continuation"]["remainingTask"].text, "prepare a forecast")
      try expectEqual(messages[0].conversationActions, [])
      try expectEqual(toolScope, .propose_record)
      let completed = messages.last!
      try expectEqual(completed.role, "tool")
      try expectEqual(completed.toolName, "start_thread_and_continue")
      let result = try Value.parse(completed.content)
      try expectEqual(result["kind"].text, "created")
      try expectEqual(messages[messages.count - 2].toolCalls.first?.id, completed.toolCallId)
    }
    let name: String
    let arguments: Value
    if branch && responses == 1 {
      name = "start_thread_and_continue"
      arguments = .object([
        "task": .string("prepare a forecast"), "work": .string("propose_record"),
      ])
    } else {
      name = "propose_record"
      arguments = .object([
        "title": .string("Sales forecast"), "kind": .string("forecast"),
        "text": .string("Expected fittings: 30."), "meaning": .string("estimate"),
        "inputs": .array([]),
      ])
    }
    return .init(
      text: "", calls: [.init(id: identifier(), name: name, inputJSON: try arguments.json())])
  }
}

func checkRequestEnvelopes() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-request-envelope-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  for branch in [false, true] {
    let book = try Workbook.create(
      at: root.appendingPathComponent("\(branch).sevra"), title: "Envelope")
    let prompt =
      branch
      ? "Start a thread and prepare a forecast for 30 fittings. Leave it for review."
      : "Please prepare a forecast for 30 fittings.\nLabel: Cañón \\\"quoted\\\". Leave it for review."
    let context = branch ? "Selected Home" : ""
    let model = RequestEnvelopeModel(book, prompt: prompt, context: context, branch: branch)
    let result = try await WorkbookAgent.run(
      prompt, workbook: book, context: context, model: model, enableCompaction: false)
    try expectEqual(result.state, "needs_review")
    try expectEqual(result.steps, branch ? 2 : 1)
    let requests = try book.items(kind: "request")
    try expectEqual(requests.count, 1)
    try expectEqual(try book.item(requests[0].id).text, prompt)
    let forecast = try book.items(kind: "forecast").first!
    let conversation = result.conversationAction?.conversation ?? "main"
    let message = try book.messages(conversation: conversation).last { $0.state == "needs_review" }!
    let payload = try book.messagePayload(message.id, conversation: conversation)
    try expectEqual(payload["kind"].text, "proposal")
    try expectEqual(payload["itemID"].text, forecast.id)
    let review = try book.workspaceSnapshot(conversation: conversation)!.proposalReviews[message.id]
    try expectEqual(review?.proposalID, forecast.id)
    try expectEqual(review?.status, "draft")
    try expectEqual(forecast.status, "draft")
    try expectEqual(try book.item(forecast.id).meaning, "estimate")
    try expectEqual(try book.lineage(forecast.id).map { $0["parent"].text }, [requests[0].id])
    try expectEqual(try book.verify()["ok"], .bool(true))
  }
  print(
    "PASS intact user request, separate host metadata, scoped continuation and automatic request lineage without redundant reads"
  )
}
