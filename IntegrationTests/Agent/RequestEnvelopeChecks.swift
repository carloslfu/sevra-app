import Foundation
import SevraAI
import SevraCore

private actor RequestEnvelopeModel: WorkbookInference {
  let identity = "synthetic request envelope"
  let lastMetrics: Value = .null
  let book: Workbook
  let prompt: String
  let context: String
  var responses = 0
  init(_ book: Workbook, prompt: String, context: String) {
    self.book = book
    self.prompt = prompt
    self.context = context
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
    try expectEqual(host["continuation"], .null)
    let arguments: Value = .object([
      "title": .string("Sales forecast"), "kind": .string("forecast"),
      "text": .string("Expected fittings: 30."), "meaning": .string("estimate"),
      "inputs": .array([]),
    ])
    return .init(
      text: "",
      calls: [
        try .init(id: identifier(), operation: "propose_record", arguments, scope: toolScope)
      ])
  }
}

func checkRequestEnvelopes() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-request-envelope-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  for visible in [false, true] {
    let book = try Workbook.create(
      at: root.appendingPathComponent("\(visible).sevra"), title: "Envelope")
    let prompt =
      visible
      ? "Prepare a forecast for 30 fittings. Leave it for review."
      : "Please prepare a forecast for 30 fittings.\nLabel: Cañón \\\"quoted\\\". Leave it for review."
    let context = visible ? "Selected Home" : ""
    let model = RequestEnvelopeModel(book, prompt: prompt, context: context)
    let result = try await WorkbookAgent.run(
      prompt, workbook: book, context: context, model: model, enableCompaction: false)
    try expectEqual(result.state, "needs_review")
    try expectEqual(result.steps, 1)
    let requests = try book.items(kind: "request")
    try expectEqual(requests.count, 1)
    try expectEqual(try book.item(requests[0].id).text, prompt)
    let forecast = try book.items(kind: "forecast").first!
    let conversation = book.startChat
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
    "PASS intact user request, separate host metadata and automatic request lineage without redundant reads"
  )
}
