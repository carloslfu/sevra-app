import Foundation
import SevraAI
import SevraCore

/// Asks chat to prepare a saved action, then finishes.
private actor SavedActionModel: WorkbookInference {
  let identity = "Synthetic saved action"
  let lastMetrics: Value = .null
  let actionID: String
  let arguments: Value
  let answer: Value
  var scopes: [InferenceToolScope] = []
  init(actionID: String, arguments: Value, answer: Value) {
    self.actionID = actionID
    self.arguments = arguments
    self.answer = answer
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
                "arguments": .object(["id": .string(actionID), "arguments": arguments]),
              ])
            ]).json())
        ])
    }
    return .init(
      text: "",
      calls: [
        .init(
          id: identifier(), name: "finish",
          inputJSON: try answer.json())
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
  let model = SavedActionModel(
    actionID: action.id,
    arguments: .object([
      "title": .string("Oak quote"), "body": .string("Oak Supply quotes 2.40 each."),
      "evidence": .string(evidence.id), "meaning": .string("actual"),
      "scenario": .string("actual"),
    ]),
    answer: .object([
      "answer": .string("I could not draft that note from chat."),
      "basis": .string("unresolved"), "citations": .array([]),
    ]))
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
  // A saved action on a saved tool runs from chat: the row is added at once, and the answer
  // offers the one Undo that takes it back.
  _ = try book.chatSaveTool(
    name: "add_quote", description: "Adds a supplier quote.",
    inputs: [("supplier", "text"), ("quantity", "decimal"), ("unit_cost", "decimal")],
    statements: [
      "INSERT INTO supplier_comparison (supplier, quantity, unit_cost) VALUES (:supplier, :quantity, :unit_cost)"
    ], source: nil, token: "save-add-quote", requestSourceID: nil)
  let tool = try book.applicationDefinition(
    try book.savedTools().first { $0.name == "add_quote" }!.definitionID)
  let adds = try book.saveApplicationDefinition(
    logicalID: identifier(), content: ActionRegistry.toolActionDefinition(tool: tool))
  let runner = SavedActionModel(
    actionID: adds.id,
    arguments: .object([
      "supplier": .string("Birch Parts"), "quantity": .string("10"),
      "unit_cost": .string("2.10"),
    ]),
    answer: .object([
      "answer": .string("Added the Birch Parts quote."), "basis": .string("completed_action"),
      "citations": .array([]),
    ]))
  _ = try await WorkbookAgent.run(
    "Add a quote from Birch Parts, 10 at 2.10, with the saved action.", workbook: book,
    model: runner)
  func suppliers() throws -> [String] {
    try book.chatSQL(
      statements: ["SELECT supplier FROM supplier_comparison ORDER BY supplier"], readOnly: true,
      token: identifier(), requestSourceID: nil
    )["results"].array[0]["rows"].array.map { $0.array[0].text }
  }
  try expectEqual(try suppliers(), ["Birch Parts", "Cedar Tools", "Oak Supply"])
  let answered = try book.messages().last { $0.role == "assistant" }!
  let undo = try book.conversationSQLReceipt(answered.id, conversation: book.startChat)
  try expectEqual(undo != nil, true)
  _ = try book.chatSQLUndo(undo!, actor: .human("synthetic person"))
  try expectEqual(try suppliers(), ["Cedar Tools", "Oak Supply"])
  try expectEqual(try book.verify()["ok"], .bool(true))
  print(
    "PASS chat cannot submit a saved document action and saves nothing, a saved tool action runs from chat with one Undo, and the supplier comparison runs through sql"
  )
  try checkOptionalToolInputs(book)
}

/// A tool saved from chat can mark an input optional with required: false. Left out, from
/// chat or from a view's button, it is NULL. The other inputs stay required.
private func checkOptionalToolInputs(_ book: Workbook) throws {
  _ = try book.chatSQL(
    statements: ["CREATE TABLE visits (customer TEXT, note TEXT)"], readOnly: false,
    token: identifier(), requestSourceID: nil)
  let save = GeneralTools.route(
    "save",
    .object([
      "tool": .object([
        "name": .string("log_visit"), "description": .string("Logs a customer visit."),
        "inputs": .array([
          .object(["name": .string("customer"), "type": .string("text")]),
          .object([
            "name": .string("note"), "type": .string("text"), "required": .bool(false),
          ]),
        ]),
        "statements": .array([
          .string("INSERT INTO visits (customer, note) VALUES (:customer, :note)")
        ]),
      ])
    ]))
  let saved = try WorkbookTools(book).execute(save.tool, save.arguments)
  try expectEqual(saved["inputs"], .array([.string("customer text"), .string("note text optional")]))
  try expectEqual(
    try book.chatSavedTools().contains("log_visit(customer TEXT, note TEXT optional)"), true)
  func visits() throws -> [[String]] {
    try book.chatSQL(
      statements: ["SELECT customer, coalesce(note, 'NULL') FROM visits ORDER BY customer"],
      readOnly: true, token: identifier(), requestSourceID: nil
    )["results"].array[0]["rows"].array.map { $0.array.map(\.text) }
  }
  _ = try book.chatRunTool(
    name: "log_visit", values: ["customer": .string("Ana")], readOnly: false,
    token: identifier(), requestSourceID: nil)
  _ = try book.chatRunTool(
    name: "log_visit", values: ["customer": .string("Bea"), "note": .string("Paid cash")],
    readOnly: false, token: identifier(), requestSourceID: nil)
  // The required input is still required.
  do {
    _ = try book.chatRunTool(
      name: "log_visit", values: ["note": .string("No customer")], readOnly: false,
      token: identifier(), requestSourceID: nil)
    throw SevraError("check", "A required input was left out.")
  } catch let error as SevraError where error.code == "tool_inputs" {}
  // A button leaves the optional input out too.
  let view = try WorkbookTools(book).execute(
    "save_space",
    .object([
      "title": .string("Visits"),
      "definition": .object([
        "version": .number(1),
        "components": .array([
          .object([
            "id": .string("log"), "type": .string("button"), "title": .string("Log a visit"),
            "definitionBinding": .object(["tool": .string("log_visit")]),
          ])
        ]),
      ]),
    ]))
  _ = try book.pressButton(
    spaceID: view["spaceID"].text, componentID: "log", values: ["customer": .string("Cy")])
  try expectEqual(
    try visits(), [["Ana", "NULL"], ["Bea", "Paid cash"], ["Cy", "NULL"]])
  // Without required: false, every input is required, as before.
  let strict = try WorkbookTools(book).execute(
    "save",
    .object([
      "kind": .string("tool"), "name": .string("log_strict"), "description": .string("Logs."),
      "inputs": .array([.object(["name": .string("note"), "type": .string("text")])]),
      "statements": .array([.string("INSERT INTO visits (customer, note) VALUES ('x', :note)")]),
    ]))
  try expectEqual(strict["inputs"], .array([.string("note text")]))
  print("PASS a tool saved from chat takes an optional input, NULL when chat or a button leaves it out")
}
