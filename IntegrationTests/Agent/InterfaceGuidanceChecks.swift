import Foundation
import SevraAI
import SevraCore

private actor InterfaceAnswerModel: WorkbookInference {
  let identity = "synthetic interface guidance fixture"
  let lastMetrics: Value = .object(["fixture": .bool(true)])
  let answer: String
  var responses = 0
  init(_ answer: String) { self.answer = answer }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    responses += 1
    try expectEqual(messages[0].content.contains(GeneralTools.instructions), true)
    return .init(
      text: "",
      calls: [
        .init(
          id: identifier(), name: "finish",
          inputJSON: try Value.object([
            "answer": .string(answer), "basis": .string("general"), "citations": .array([]),
          ]).json())
      ])
  }
}

func checkInterfaceGuidance() async throws {
  for prompt in [
    "Explain only; leave this workbook unchanged.",
    "If I change inventory in another chat, is this one unaffected? Explain without changing anything.",
    "Explain without making changes.",
    "Ask what you need before saving anything.", "Do not save anything.",
  ] { try expectEqual(RequestRestrictions.isExplicitlyReadOnly(prompt), true) }
  for prompt in [
    "What does 'explain only' mean?", "Create a note about the phrase explain only.",
    "Don't explain only; create the requested draft.",
    "Create a note about the phrase 'do not save anything'.",
    "What does 'ask what you need before saving anything' mean?",
  ] { try expectEqual(RequestRestrictions.isExplicitlyReadOnly(prompt), false) }
  for text in [
    "Here are the key differences: each chat keeps its own discussion; all chats share the workbook.",
    "The difference is one of focus. Both conversations share the workbook data.",
    "A difference between a Source and a Record is whether it is an input or a derivation.",
    "1. This chat.\n2. Another chat. Their difference is conversation scope.",
    "Key differences:\n\n1. **Structure**: each chat starts empty.\n2. **Shared data**: the same workbook.",
    "VAT on this invoice is 19%.",
  ] {
    try expectEqual(CalculationRequirement.hasComparisonClaim(text), false)
  }
  for text in [
    "The price difference is 2.40.", "The difference in totals equals 12.",
    "A difference of .25 units.", "Difference: −2", "It is cheaper.",
    "This is more expensive.", "A lower cost.", "A higher cost.",
  ] {
    try expectEqual(CalculationRequirement.hasComparisonClaim(text), true)
  }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-interface-guidance-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root, title: "Interface guidance")
  let answer =
    "Here are the key differences: a chat has its own discussion history, while all chats share this workbook's data. Starting one does not create an inventory scenario."
  let model = InterfaceAnswerModel(answer)
  let result = try await WorkbookAgent.run(
    "Explain the difference between two chats. Do not create one.",
    workbook: book, model: model)
  try expectEqual(result.answer, answer)
  try expectEqual(result.steps, 1)
  try expectEqual(await model.responses, 1)
  try expectEqual(try book.messages().filter { $0.role == "tool" }.count, 0)
  try expectEqual(try book.chats().count, 1)

  let unsupported = InterfaceAnswerModel("The price difference is 2.40.")
  do {
    _ = try await WorkbookAgent.run("Compare these prices.", workbook: book, model: unsupported)
    throw SevraError("fixture", "Unsupported numeric comparison was accepted")
  } catch let e as SevraError { try expectEqual(e.code, "answer_validation") }
  let rejected = try book.messages().filter { $0.role == "tool" }
  try expectEqual(rejected.count, 4)
  try expectEqual(rejected.allSatisfy { $0.body.contains("arithmetic with sql") }, true)

  _ = try book.addMessage("Explore stock separately.", role: "user")
  let other = try book.createChat()
  let observation = try book.addItem(
    category: "source", kind: "observation", title: "Stock check",
    text: "Opening stock 20; two units handed over.", status: "accepted")
  let table = try book.createDataset(
    title: "Fittings", columns: [.init(id: "count", title: "Count", type: "decimal")],
    rows: [["count": .string("20")]], sourceID: observation.id)
  let firstTools = WorkbookTools(book)
  let otherTools = WorkbookTools(book, conversation: other)
  func count(_ tools: WorkbookTools) throws -> String {
    let read = try tools.execute(
      "sql", .object(["statements": .array([.string("SELECT count FROM fittings")])]))
    return read["results"].array.first?["rows"].array.first?.array.first?.text ?? ""
  }
  let proposal = try book.proposeTableEdit(
    table.id, edits: [RowEdit(id: try book.rows(table.id)[0].id, values: ["count": .string("18")])])
  try expectEqual(try count(firstTools), "20")
  _ = try book.accept(proposal.id)
  try expectEqual(try count(firstTools), "18")
  try expectEqual(try count(otherTools), "18")
  let sourceCount = try book.items().filter { $0.category == "source" }.count
  let calculation = try otherTools.execute(
    "sql", .object(["statements": .array([.string("SELECT CAST(20 - 2 AS TEXT) AS quantity")])]))
  let analysis = try otherTools.execute(
    "propose_record",
    .object([
      "kind": .string("analysis"), "title": .string("Stock interpretation"),
      "text": .string("Calculated from the original stock observation."),
      "meaning": .string("estimate"), "inputs": .array([.string(observation.id)]),
      "data": .object([
        "quantity": calculation["results"].array.first?["rows"].array.first?.array.first ?? .null
      ]),
    ]))
  try expectEqual(analysis["data"]["quantity"].text, "18")
  try expectEqual(analysis["category"].text, "record")
  try expectEqual(try book.items().filter { $0.category == "source" }.count, sourceCount)
  try expectEqual(try book.verify()["ok"], .bool(true))
  print(
    "PASS conceptual differences finish directly; numeric comparisons stay checked; chats share accepted workbook data"
  )
}
