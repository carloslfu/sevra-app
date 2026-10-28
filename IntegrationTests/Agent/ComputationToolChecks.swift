import Foundation
import SevraAI
import SevraCore

private actor ComputationReceiptModel: WorkbookInference {
  let identity = "synthetic result receipt consumer"
  let lastMetrics: Value = .null
  let definitionID: String
  private var step = 0
  init(_ id: String) { definitionID = id }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    step += 1
    let tool: String
    let arguments: Value
    if step == 1 {
      tool = "read_definition"
      arguments = .object(["id": .string(definitionID)])
    } else if step == 2 {
      tool = "evaluate_definition"
      arguments = .object(["id": .string(definitionID), "arguments": .object([:])])
    } else {
      try expectEqual(step, 3)
      let message = try expectValue(messages.last { $0.role == "tool" })
      let evaluation = try Value.parse(message.content)
      let receipt = try expectValue(evaluation["receiptID"].string)
      try expectEqual(receipt == evaluation["snapshot"].text, false)
      tool = "publish_result"
      arguments = .object([
        "evaluationReceiptID": .string(receipt), "title": .string("Expected units"),
        "meaning": .string("estimate"),
      ])
    }
    return .init(
      text: "", calls: [.init(id: identifier(), name: tool, inputJSON: try arguments.json())])
  }
}

func checkComputationTools() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "computation-tool-" + identifier() + ".sevra")
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root, title: "Synthetic results")
  let function = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("function"), "title": .string("Expected units"),
      "description": .string("Synthetic"), "parameters": .array([]),
      "payload": .object(["expression": .string("3*12"), "calls": .array([])]),
    ]))
  let result = try await WorkbookAgent.run(
    "Save this calculation as an estimate draft. Do not accept it.", workbook: book,
    model: ComputationReceiptModel(function.id))
  try expectEqual(result.state, "needs_review")
  try expectEqual(result.answer.contains("estimate draft"), true)
  try expectEqual(result.answer.contains("Accept this proposal to continue"), false)
  let saved = try expectValue(book.items(kind: "calculation").first)
  try expectEqual(saved.status, "draft")
  try expectEqual(saved.meaning, "estimate")
  try expectEqual(saved.data["evaluation"]["result"], .string("36"))
  try expectEqual(saved.data["evaluation"]["receiptID"], .null)
  try expectEqual(try book.verify()["ok"], .bool(true))
  print("PASS model-visible evaluation receipts publish exact estimate drafts with optional review")
}
