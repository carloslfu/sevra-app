import Foundation
import SevraAI
import SevraCore

/// Prepares the sample workbook's saved movement action, then answers its direction review.
private actor SavedMovementModel: WorkbookInference {
  let identity = "Synthetic saved action"
  let lastMetrics: Value = .null
  let actionID: String
  let evidenceID: String
  var scopes: [InferenceToolScope] = []
  init(actionID: String, evidenceID: String) {
    self.actionID = actionID
    self.evidenceID = evidenceID
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    scopes.append(toolScope)
    if toolScope == .actionDirection {
      return .init(
        text: "",
        calls: [
          .init(
            id: identifier(), name: "review_action_directions",
            inputJSON: try Value.object([
              "directions": .array([
                .object([
                  "index": .number(0), "direction": .string("outgoing"),
                  "basis": .string("request"), "quote": .string("Two brass bolts left our stock"),
                ])
              ])
            ]).json())
        ])
    }
    if scopes.filter({ $0 != .actionDirection }).count == 1 {
      return .init(
        text: "",
        calls: [
          .init(
            id: identifier(), name: "run",
            inputJSON: try Value.object([
              "action": .object([
                "name": .string("action.prepare"),
                "arguments": .object([
                  "id": .string(actionID),
                  "arguments": .object([
                    "subject": .string("brass bolts"), "quantity": .string("-2"),
                    "occurrence": .string("sale-7"), "effective": .string("2026-01-03"),
                    "evidence": .string(evidenceID), "meaning": .string("actual"),
                  ]),
                ]),
              ])
            ]).json())
        ])
    }
    return .init(
      text: "",
      calls: [
        .init(
          id: identifier(), name: "finish",
          inputJSON: try Value.object([
            "answer": .string("The movement is drafted for your review."),
            "basis": .string("completed_action"), "citations": .array([]),
          ]).json())
      ])
  }
}

/// No model. Phase 5's stock exit: a movement made through the sample workbook's saved action
/// goes through the same direction review as one proposed directly, saves a draft only, and the
/// stock read through sql agrees with the core's balance. The README's supplier comparison is
/// reproduced with sql over the comparison table.
func checkSavedMovementAction() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "saved-action-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let url = root.appendingPathComponent("Business.sevra")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  _ = try Demo.create(at: url)
  let book = try Workbook(url)
  let action = try book.searchApplicationDefinitions("stock movement", kind: "action")["hits"]
    .array.first
  let actionID = try expectValue(action?["id"].string)
  let evidence = try book.addItem(
    category: "source", kind: "observation", title: "Counter sale",
    text: "Two brass bolts left our stock for a counter sale.", status: "accepted")
  let model = SavedMovementModel(actionID: actionID, evidenceID: evidence.id)
  let result = try await WorkbookAgent.run(
    "Two brass bolts left our stock in a counter sale on January 3. Record it with the saved action.",
    workbook: book, model: model)
  try expectEqual(await model.scopes.contains(.actionDirection), true)
  try expectEqual(result.state, "needs_review")
  let movements = try book.items(kind: "movement").filter { $0.status == "draft" }
  try expectEqual(movements.count, 1)
  try expectEqual(movements[0].data["quantity"].text, "-2")
  let receipts = try book.messages().filter { $0.role == "tool" }.map { try Value.parse($0.body) }
  try expectEqual(
    receipts.contains { $0["result"]["directionReview"]["matches"] == .bool(true) }, true)
  // The draft does not count until it is accepted; sql's stock and the core agree before and after.
  func sqlStock() throws -> String {
    let read = try book.chatSQL(
      statements: ["SELECT quantity FROM stock WHERE subject = 'brass bolts'"], readOnly: true,
      token: identifier(), requestSourceID: nil)
    guard let cell = read["results"].array.first?["rows"].array.first?.array.first else {
      return ""
    }
    return Numbers.string(try Numbers.decimal(cell.text))
  }
  try expectEqual(try sqlStock(), "18")
  try expectEqual(try book.balance(subject: "brass bolts")["quantity"].text, "18")
  _ = try book.accept(movements[0].id)
  try expectEqual(try sqlStock(), try book.balance(subject: "brass bolts")["quantity"].text)
  try expectEqual(try sqlStock(), "16")
  let comparison = try book.chatSQL(
    statements: ["SELECT supplier, round(total, 2) FROM supplier_comparison ORDER BY total"],
    readOnly: true, token: identifier(), requestSourceID: nil)
  try expectEqual(
    comparison["results"].array.first?["rows"].array.map { $0.array.map(\.text) },
    [["Oak Supply", "24"], ["Cedar Tools", "27.5"]])
  try expectEqual(try book.verify()["ok"], .bool(true))
  print(
    "PASS a stock movement through the sample's saved action: direction review, draft only, sql stock equal to the core balance, and the supplier comparison through sql"
  )
}
