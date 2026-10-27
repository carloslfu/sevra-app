import Foundation
import SevraAI
import SevraCore

private actor ParentHistoryInference: WorkbookInference {
  let identity = "explicit inherited history fixture"
  let lastMetrics: Value = .null
  let original: String
  var step = 0
  init(original: String) { self.original = original }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    step += 1
    if step == 1 {
      try expectEqual(citationIDs.contains("message:" + original), false)
      return .init(
        text: "",
        calls: [
          .init(
            id: "inherited-read", name: "history_read",
            inputJSON: try Value.object(["id": .string(original)]).json())
        ])
    }
    try expectEqual(step, 2)
    try expectEqual(citationIDs.contains("message:" + original), true)
    return .init(
      text: "",
      calls: [
        .init(
          id: "inherited-finish", name: "finish",
          inputJSON: try Value.object([
            "answer": .string("The inherited packing sample is exactly 0.10 kg."),
            "basis": .string("evidence"), "citations": .array([.string("message:" + original)]),
          ]).json())
      ])
  }
}

func checkParentHistory() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-parent-history-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root, title: "Inherited evidence")
  let excluded = try book.addMessage("Unshared earlier parent information.", role: "user")
  for index in 0..<6 {
    _ = try book.addMessage("Closed parent note \(index).", role: "assistant")
  }
  let original = try book.addMessage("Packing sample exactly 0.10 kg.", role: "user")
  let tangent = try book.tangent(title: "Packing", parentMessage: original)
  let excerpt = try book.parentContext(conversation: tangent)
  let later = try book.addMessage("New parent information after branching.", role: "user")
  let sibling = try book.tangent(title: "Other work", parentMessage: later)
  let siblingMessage = try book.addMessage(
    "Sibling private context.", role: "user", conversation: sibling)
  let local = try book.addMessage("Tangent-only note.", role: "user", conversation: tangent)
  let request = try book.addMessage(
    "Read the inherited packing quantity.", role: "user", conversation: tangent)
  let run = try book.startAgentRun(
    conversation: tangent, model: "fixture", requestMessageID: request)
  let future = try book.addMessage(
    "Later in the tangent.", role: "assistant", conversation: tangent)
  let tools = WorkbookTools(book, runID: run, conversation: tangent)
  let inherited = try tools.execute("history_read", .object(["id": .string(original)]))
  try expectEqual(inherited["citation"], .string("message:" + original))
  try expectEqual(inherited["conversation"], .string("main"))
  try expectEqual(inherited["inherited"], .bool(true))
  try expectEqual(inherited["message"]["body"].text, "Packing sample exactly 0.10 kg.")
  for id in [excluded, later, siblingMessage] {
    do {
      _ = try tools.execute("history_read", .object(["id": .string(id)]))
      throw SevraError("fixture_assertion", "History escaped the explicit parent excerpt.")
    } catch let error as SevraError { try expectEqual(error.code, "history_scope") }
  }
  try expectThrows(try book.historyMessage(original, conversation: tangent))
  try expectThrows(
    try book.readHistoryEvidence(original, conversation: tangent, beforeMessage: later))
  try expectEqual(try encoded(book.parentContext(conversation: tangent)), encoded(excerpt))
  let localRead = try tools.execute("history_read", .object(["id": .string(local)]))
  try expectEqual(localRead["inherited"], .bool(false))
  try expectEqual(localRead["conversation"], .string(tangent))
  try expectEqual(localRead["citation"], .string("message:" + local))
  for id in [request, future] {
    try expectEqual(
      try tools.execute("history_read", .object(["id": .string(id)]))["citation"], .null)
  }
  try expectEqual(
    try tools.execute("history_search", .object(["query": .string("packing sample")]))["hits"].array
      .isEmpty, true)
  try book.finishAgentRun(run, status: "complete", steps: 0, metrics: .array([]))
  let answer = try await WorkbookAgent.run(
    "What packing sample quantity was inherited? Make no changes.", workbook: book,
    conversation: tangent, model: ParentHistoryInference(original: original))
  try expectEqual(answer.citations, ["message:" + original])
  try expectEqual(answer.answer.contains("sevra://conversation/main?message=" + original), true)
  try expectEqual(
    answer.answer.contains("sevra://conversation/" + tangent + "?message=" + original), false)

  let tangentFact = try book.addMessage(
    "Packing sample exactly 0.10 kg.", role: "user", conversation: tangent)
  let nested = try book.tangent(title: "Nested packing", parentMessage: tangentFact)
  let nestedTools = WorkbookTools(book, conversation: nested)
  try expectThrows(try nestedTools.execute("history_read", .object(["id": .string(original)])))
  let nestedAnswer = try await WorkbookAgent.run(
    "What packing sample quantity was inherited? Make no changes.", workbook: book,
    conversation: nested, model: ParentHistoryInference(original: tangentFact))
  try expectEqual(
    nestedAnswer.answer.contains("sevra://conversation/" + tangent + "?message=" + tangentFact),
    true)
  try expectEqual(try book.items().filter { $0.category == "record" }.isEmpty, true)
  try expectEqual(try book.verify()["ok"], .bool(true))
  print(
    "PASS inherited parent evidence is readable and correctly linked without widening history search or branch scope"
  )
}
