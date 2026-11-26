import Foundation
import SevraAI
import SevraCore

/// Asks chat to prepare a saved action, then finishes.
private actor SavedActionModel: WorkbookInference {
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
    if scopes.count == 1 {
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
                    "title": .string("Oak quote"), "body": .string("Oak Supply quotes 2.40 each."),
                    "evidence": .string(evidenceID), "meaning": .string("actual"),
                    "scenario": .string("actual"),
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
            "answer": .string("I could not draft that note from chat."),
            "basis": .string("unresolved"), "citations": .array([]),
          ]).json())
      ])
  }
}

/// No model. A saved document action prepared from chat is refused before anything is saved,
/// because document drafts go through their form or workflow. The README's supplier comparison
/// is reproduced with sql over the comparison table.
func checkSavedActions() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "saved-action-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let url = root.appendingPathComponent("Business.sevra")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  _ = try Demo.create(at: url)
  let book = try Workbook(url)
  let action = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: ActionRegistry.documentDefinition(
      title: "Draft a supplier note", description: "A note from a quote"))
  let evidence = try book.addItem(
    category: "source", kind: "observation", title: "Oak quote",
    text: "Oak Supply quotes 2.40 each.", status: "accepted")
  let model = SavedActionModel(actionID: action.id, evidenceID: evidence.id)
  let before = try book.items(kind: "document").count
  _ = try await WorkbookAgent.run(
    "Draft a note about the Oak quote with the saved action.", workbook: book, model: model)
  try expectEqual(try book.items(kind: "document").count, before)
  let receipts = try book.messages().filter { $0.role == "tool" }.map { try Value.parse($0.body) }
  try expectEqual(
    receipts.contains { $0["result"]["error"].text.contains("workspace_action form.submit") },
    true)
  let comparison = try book.chatSQL(
    statements: ["SELECT supplier, round(total, 2) FROM supplier_comparison ORDER BY total"],
    readOnly: true, token: identifier(), requestSourceID: nil)
  try expectEqual(
    comparison["results"].array.first?["rows"].array.map { $0.array.map(\.text) },
    [["Oak Supply", "24"], ["Cedar Tools", "27.5"]])
  try expectEqual(try book.verify()["ok"], .bool(true))
  print(
    "PASS chat cannot submit a saved document action and saves nothing, and the supplier comparison runs through sql"
  )
}
