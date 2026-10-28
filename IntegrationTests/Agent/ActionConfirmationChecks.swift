import Foundation
import SevraAI
import SevraCore

private actor ConfirmationModel: WorkbookInference {
  let identity = "synthetic saved-artifact confirmation"
  let lastMetrics: Value = .null
  let source: Item
  let factual: Bool
  let invalidDraft: Bool
  let retryDraft: Bool
  let differentTitle: Bool
  var step = 0
  init(
    _ source: Item, factual: Bool, invalidDraft: Bool, retryDraft: Bool = false,
    differentTitle: Bool = false
  ) {
    self.source = source
    self.factual = factual
    self.invalidDraft = invalidDraft
    self.retryDraft = retryDraft
    self.differentTitle = differentTitle
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    step += 1
    let tool: String
    let args: Value
    if step == 1 {
      tool = "read"
      args = .object(["id": .string(source.id)])
    } else if [2, 3].contains(step) {
      tool = "save_space"
      args = .object([
        "title": .string("Overview"),
        "definition": .object(["version": .number(1), "components": .array([])]),
      ])
    } else if step == 4 || (step == 5 && retryDraft) {
      tool = "draft"
      args = .object([
        "title": .string(differentTitle && step == 5 ? "Other memo" : "Memo [A]"),
        "text": .string("Renamed the identifier to Alpha."),
        "inputs": .array([.string(invalidDraft && step == 4 ? "not-a-source" : source.id)]),
      ])
    } else {
      tool = "finish"
      args = .object([
        "answer": .string(
          factual
            ? "The source records ALPHA-CHECK."
            : "All requested identifiers were preserved exactly; every condition was verified. 123e4567-e89b-12d3-a456-426614174000 cost $1000."
        ),
        "basis": .string(factual ? "evidence" : "completed_action"),
        "citations": .array(factual ? [.string(source.id)] : []),
      ])
    }
    return .init(text: "", calls: [.init(id: identifier(), name: tool, inputJSON: try args.json())])
  }
}

func checkActionConfirmations() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "confirmation-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  for mode in ["saved", "evidence", "failed-draft", "retry", "different"] {
    let book = try Workbook.create(at: root.appendingPathComponent(mode + ".sevra"), title: mode)
    let source = try book.addItem(
      category: "source", kind: "note", title: "Input", text: "ALPHA-CHECK")
    let invalid = mode == "failed-draft"
    let retry = mode == "retry" || mode == "different"
    let result = try await WorkbookAgent.run(
      "Save Overview and a memo using the input.", workbook: book,
      context: "Input: \(source.id)",
      model: ConfirmationModel(
        source, factual: mode == "evidence", invalidDraft: invalid || retry, retryDraft: retry,
        differentTitle: mode == "different"))
    try expectEqual(result.state, "complete")
    let last = try expectValue(book.messages().last { $0.role == "assistant" })
    let payload = try book.messagePayload(last.id)
    try expectEqual(try book.spaces().filter { $0.title == "Overview" }.count, 1)
    try expectEqual(result.answer.contains("every condition was verified"), false)
    try expectEqual(result.answer.contains("All requested identifiers"), false)
    try expectEqual(result.answer.contains("123e4567"), false)
    try expectEqual(result.answer.contains("$1000"), false)
    if mode == "evidence" {
      try expectEqual(result.answer.hasPrefix("The source records ALPHA-CHECK."), true)
      try expectEqual(payload["presentation"].text, "answer")
    } else {
      try expectEqual(result.answer.components(separatedBy: "Saved space").count, 2)
      try expectEqual(result.answer.contains("Saved draft"), !invalid)
      try expectEqual(payload["presentation"].text, "host_actions")
      try expectEqual(payload["actionConfirmations"].array.count, retry ? 4 : 3)
      try expectEqual(
        result.answer.contains("Couldn’t finish saving the draft."), invalid || mode == "different")
      try expectEqual(
        payload["arguments"]["answer"].text.contains("every condition was verified"), true)
    }
    if !invalid {
      let draft = try expectValue(book.items(kind: "document").first)
      try expectEqual(draft.text, "Renamed the identifier to Alpha.")
      try expectEqual(draft.status, "draft")
      if mode == "saved" { try expectEqual(result.answer.contains(draft.id), true) }
    }
    try expectEqual(try book.verify()["ok"], .bool(true))
  }
  print(
    "PASS receipt-based saved-artifact confirmations, idempotent rendering, failed-write exclusion and intact cited answers"
  )
}
