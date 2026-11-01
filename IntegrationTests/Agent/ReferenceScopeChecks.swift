import Foundation
import SevraAI
import SevraCore

private actor HiddenRequestInference: WorkbookInference {
  let identity = "scripted conversation bypass refusal"
  let lastMetrics: Value = .null
  let overview: String
  let hidden: String
  let message: String
  var step = 0
  init(overview: String, hidden: String, message: String) {
    self.overview = overview
    self.hidden = hidden
    self.message = message
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    step += 1
    try expectEqual(citationIDs.contains(hidden), false)
    var tool: String
    var args: Value
    switch step {
    case 1:
      tool = "read"
      args = .object(["id": .string(overview)])
    case 2:
      tool = "references"
      args = .object(["id": .string(overview)])
    case 3:
      let result = try Value.parse(messages.last!.content)
      try expectEqual(result["hits"].array.isEmpty, true)
      try expectEqual(result.json().contains(hidden), false)
      tool = "read"
      args = .object(["id": .string(hidden)])
    case 4:
      try expectEqual(messages.last!.content.contains("business-evidence read scope"), true)
      tool = "history_read"
      args = .object(["id": .string(message)])
    default:
      try expectEqual(step, 5)
      try expectEqual(messages.last!.content.contains("inherited parent excerpt"), true)
      tool = "finish"
      args = .object([
        "answer": .string("Use history within its permitted conversation scope."),
        "basis": .string("general"), "citations": .array([]),
      ])
    }
    return .init(text: "", calls: [.init(id: identifier(), name: tool, inputJSON: try args.json())])
  }
}

private actor RequestCeilingInference: WorkbookInference {
  let identity = "scripted immutable request ceiling"
  let lastMetrics: Value = .null
  let book: Workbook
  var step = 0
  var original: String?
  init(_ book: Workbook) { self.book = book }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    step += 1
    if step == 1 {
      let source = try book.items(kind: "request").first!
      original = source.id
      // Simulate a separate owner writing after this run's captured request.
      _ = try book.addItem(
        category: "source", kind: "request", title: "FUTURE-SECRET-TITLE",
        text: "FUTURE-SECRET-CONTENT", meaning: "plan", supersedes: source.id)
      return .init(
        text: "",
        calls: [
          .init(
            id: identifier(), name: "read",
            inputJSON: try Value.object(["id": .string(source.id)]).json())
        ])
    }
    try expectEqual(step, 2)
    let result = try Value.parse(messages.last!.content)
    try expectEqual(result["currentVersion"], .null)
    try expectEqual(result.json().contains("FUTURE-SECRET"), false)
    return .init(
      text: "",
      calls: [
        .init(
          id: identifier(), name: "finish",
          inputJSON: try Value.object([
            "answer": .string("Your supplied label is MAPLE."), "basis": .string("current_request"),
            "citations": .array([.string(original!)]),
          ]).json())
      ])
  }
}

func checkReferenceScope() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-reference-scope-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root.appendingPathComponent("Hidden.sevra"), title: "Hidden")
  let parent = try book.addMessage("Parent context", role: "user")
  let sibling = try book.tangent(title: "Private side discussion", parentMessage: parent)
  let message = try book.addMessage("SIBLING-SECRET-CONTENT", role: "user", conversation: sibling)
  let hidden = try book.addItem(
    category: "source", kind: "request", title: "SIBLING-SECRET-TITLE",
    text: "SIBLING-SECRET-CONTENT",
    data: .object(["conversationID": .string(sibling), "messageID": .string(message)]))
  let overview = try book.addItem(
    category: "source", kind: "document", title: "Overview",
    text:
      "[Earlier request](sevra://item/\(hidden.id)). Source pointer: \(hidden.id). History message pointer: \(message)."
  )
  let result = try await WorkbookAgent.run(
    "Explore the saved link from \(overview.id). Make no changes.", workbook: book,
    model: HiddenRequestInference(overview: overview.id, hidden: hidden.id, message: message))
  try expectEqual(result.steps, 5)
  let visible = try book.messages(limit: 100).map(\.body).joined(separator: "\n")
  try expectEqual(visible.contains("SIBLING-SECRET"), false)
  let receipts = try book.messages(limit: 100).filter { $0.role == "tool" }.map {
    try Value.parse($0.body)
  }
  try expectEqual(
    receipts.filter {
      $0["tool"].text == "read"
        && $0["result"]["error"].text.contains("business-evidence read scope")
    }
    .count, 1)
  try expectEqual(try book.verify()["ok"], .bool(true))
  let ceiling = try Workbook.create(
    at: root.appendingPathComponent("Ceiling.sevra"), title: "Ceiling")
  let supplied = try await WorkbookAgent.run(
    "My supplied label is MAPLE. Repeat it. Make no changes.",
    workbook: ceiling, model: RequestCeilingInference(ceiling))
  try expectEqual(supplied.steps, 2)
  try expectEqual(supplied.answer.contains("MAPLE"), true)
  try expectEqual(
    try ceiling.messages(limit: 100).map(\.body).joined(separator: "\n").contains("FUTURE-SECRET"),
    false)
  try expectEqual(try ceiling.verify()["ok"], .bool(true))
  print(
    "PASS reference/direct-read/history bypass refusal and immutable current-request ceiling without private head disclosure"
  )
}
