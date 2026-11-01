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
    try expectEqual(messages[0].content.contains("share the same Sources, Records"), true)
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
    "If I change inventory in a side thread, is main unaffected? Explain without changing anything.",
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
    "Here are the key differences: main keeps the ongoing discussion; threads hold side discussions.",
    "The difference is one of focus. Both conversations share the workbook data.",
    "A difference between a Source and a Record is whether it is an input or a derivation.",
    "1. Main conversation.\n2. Side threads. Their difference is conversation scope.",
    "Key differences:\n\n1. **Structure**: the main conversation is the default root.\n2. **Shared data**: the same workbook.",
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
    "Here are the key differences: a thread has its own discussion history, while all threads share this workbook's data. Starting one does not create an inventory scenario."
  let model = InterfaceAnswerModel(answer)
  let result = try await WorkbookAgent.run(
    "Explain the difference between main and a thread. Do not create one.",
    workbook: book, model: model)
  try expectEqual(result.answer, answer)
  try expectEqual(result.steps, 1)
  try expectEqual(await model.responses, 1)
  try expectEqual(try book.messages().filter { $0.role == "tool" }.count, 0)
  try expectEqual(try book.conversations().count, 1)

  let unsupported = InterfaceAnswerModel("The price difference is 2.40.")
  do {
    _ = try await WorkbookAgent.run("Compare these prices.", workbook: book, model: unsupported)
    throw SevraError("fixture", "Unsupported numeric comparison was accepted")
  } catch let e as SevraError { try expectEqual(e.code, "answer_validation") }
  let rejected = try book.messages().filter { $0.role == "tool" }
  try expectEqual(rejected.count, 4)
  try expectEqual(rejected.allSatisfy { $0.body.contains("compare_rows or calculate") }, true)

  let parent = try book.addMessage("Explore stock separately.", role: "user")
  let thread = try book.startThread(parentMessage: parent)
  let observation = try book.addItem(
    category: "source", kind: "observation", title: "Stock check",
    text: "Opening stock 20; two units handed over.", status: "accepted")
  try book.setOpeningBalance(
    subject: "fittings", quantity: "20", effective: "2026-01-01", sourceID: observation.id)
  let mainTools = WorkbookTools(book)
  let threadTools = WorkbookTools(book, conversation: thread)
  let proposal = try threadTools.execute(
    "propose_movement",
    .object([
      "subject": .string("fittings"), "quantity": .string("-2"),
      "occurrence": .string("handover-1"),
      "effective": .string("2026-01-02"), "input": .string(observation.id),
    ]))
  let balance: Value = .object(["subject": .string("fittings")])
  try expectEqual(try mainTools.execute("balance", balance)["quantity"].text, "20")
  _ = try book.accept(proposal["id"].text)
  try expectEqual(try mainTools.execute("balance", balance)["quantity"].text, "18")
  try expectEqual(try threadTools.execute("balance", balance)["quantity"].text, "18")
  let sourceCount = try book.items().filter { $0.category == "source" }.count
  let calculation = try threadTools.execute("calculate", .object(["expression": .string("20-2")]))
  let analysis = try threadTools.execute(
    "propose_record",
    .object([
      "kind": .string("analysis"), "title": .string("Stock interpretation"),
      "text": .string("Calculated from the original stock observation."),
      "meaning": .string("estimate"), "inputs": .array([.string(observation.id)]),
      "data": .object(["quantity": calculation["result"]]),
    ]))
  try expectEqual(analysis["data"]["quantity"].text, "18")
  try expectEqual(analysis["category"].text, "record")
  try expectEqual(try book.items().filter { $0.category == "source" }.count, sourceCount)
  try expectEqual(try book.verify()["ok"], .bool(true))
  print(
    "PASS conceptual differences finish directly; numeric comparisons stay checked; threads share accepted workbook data"
  )
}
