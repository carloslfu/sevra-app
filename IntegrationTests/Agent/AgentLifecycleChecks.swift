import Foundation
import SevraAI
import SevraCore
import SevraSplash

private actor ScriptedInference: WorkbookInference {
  let identity = "synthetic inference fixture"
  let lastMetrics: Value = .object(["fixture": .bool(true)])
  var begins = 0
  var ends = 0
  var responses = 0
  let cancelAfterResponse: Bool
  let fail: Bool
  let searchesOnly: Bool
  let balanceOnly: Bool
  init(
    cancelAfterResponse: Bool = false, fail: Bool = false, searchesOnly: Bool = false,
    balanceOnly: Bool = false
  ) {
    self.cancelAfterResponse = cancelAfterResponse
    self.fail = fail
    self.searchesOnly = searchesOnly
    self.balanceOnly = balanceOnly
  }
  func beginRun() throws { begins += 1 }
  func endRun() { ends += 1 }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, finishOnly: Bool, citationIDs: [String]
  ) async throws -> NativeReply {
    responses += 1
    if fail { throw SevraError("fixture_failure", "Synthetic failure") }
    if cancelAfterResponse { cancellation.cancel() }
    if balanceOnly {
      if responses == 1 {
        return NativeReply(
          text: "",
          calls: [
            InferenceCall(
              id: "balance-call", name: "balance",
              inputJSON: "{\"subject\":\"brass bolts\"}")
          ])
      }
      try expectEqual(responses, 2)
      let balance = try Value.parse(messages.last!.content)
      let ids = [balance["basis"].text] + balance["effects"].array.map { $0["item_id"].text }
      try expectEqual(ids.allSatisfy { citationIDs.contains($0) && !$0.isEmpty }, true)
      return NativeReply(
        text: "",
        calls: [
          InferenceCall(
            id: "balance-finish", name: "finish",
            inputJSON: try Value.object([
              "answer": .string("The current stock is 18 brass bolts."),
              "citations": .array(ids.map(Value.string)),
            ]).json())
        ])
    }
    if searchesOnly {
      try expectEqual(responses <= 3, true)
      return NativeReply(
        text: "",
        calls: [
          InferenceCall(
            id: "search-\(responses)", name: "search",
            inputJSON: "{\"query\":\"missing evidence \(responses)\"}")
        ])
    }
    return NativeReply(
      text: "",
      calls: [
        InferenceCall(
          id: "fixture-call", name: "finish",
          inputJSON: "{\"answer\":\"No changes requested.\",\"citations\":[]}")
      ])
  }
}

func checkAgentLifecycle() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-agent-lifecycle-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  for (name, cancel, fail) in [
    ("success", false, false), ("cancelled", true, false), ("failed", false, true),
  ] {
    let model = ScriptedInference(cancelAfterResponse: cancel, fail: fail)
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    do {
      let result = try await WorkbookAgent.run(
        "Just acknowledge. Make no changes.", workbook: book, model: model)
      try expectEqual(result.state, "complete")
      try expectEqual(name, "success")
    } catch {
      if name == "success" { throw error }
    }
    try expectEqual(await model.begins, 1)
    try expectEqual(await model.ends, 1)
    try expectEqual(await model.responses, 1)
    let expected = name == "success" ? "complete" : name
    let run = try expectValue(book.agentRuns().first)
    try expectEqual(run["status"].text, expected)
    try expectEqual(run["model"].text, model.identity)
    let request = try expectValue(book.messages().first { $0.role == "user" })
    try expectEqual(run["request_message_id"].text, request.id)
    let assistant = try book.messages().filter { $0.role == "assistant" }
    try expectEqual(assistant.count, 1)
    try expectEqual(assistant[0].state, expected)
    if name == "success" {
      let payload = try book.messagePayload(assistant[0].id)
      try expectEqual(payload["tool"].text, "finish")
      try expectEqual(payload["runID"].text, run["id"].text)
      try expectEqual(payload["arguments"]["answer"].text, assistant[0].body)
      try expectEqual(payload["receiptVersion"].int, 1)
    }
    if cancel { try expectEqual(assistant[0].body.contains("No changes requested"), false) }
    if cancel || fail {
      let history = try WorkbookAgent.conversationHistory(book, conversation: "main")
      try expectEqual(history.count, 2)
      try expectEqual(history.last!.content.contains("status " + expected), true)
      try expectEqual(history.last!.content.contains("It is not pending"), true)
    }
  }

  // The preserved backend must retain JSON types and exact Int64 values in
  // history while the application conversation stops depending on its types.
  let json =
    "{\"integer\":9007199254740993,\"fraction\":1.25,\"flag\":true,\"none\":null,\"text\":\"café\",\"array\":[false,2]}"
  let messages = try LocalModel.baselineMessages([
    InferenceMessage(
      role: "assistant", content: "",
      toolCalls: [
        InferenceCall(id: "call-one", name: "fixture", inputJSON: json)
      ]),
    InferenceMessage(
      role: "tool", content: "{\"result\":null}", toolCallId: "call-one", toolName: "fixture"),
  ])
  let original = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! NSDictionary
  let converted =
    try JSONSerialization.jsonObject(with: Data(messages[0].toolCalls[0].inputJSON.utf8))
    as! NSDictionary
  try expectEqual(original, converted)
  try expectEqual(messages[1].toolCallId, "call-one")
  try expectEqual(messages[1].toolName, "fixture")
  let reviewBook = try Workbook.create(
    at: root.appendingPathComponent("Review.sevra"), title: "Review")
  let source = try reviewBook.addItem(
    category: "source", kind: "request", title: "Forecast request", text: "Estimate five units")
  let proposal = try reviewBook.proposeTable(
    title: "Forecast", columns: [.init(id: "units", title: "Units", type: "decimal")],
    rows: [["units": .string("5")]], meaning: "estimate", inputs: [source.id])
  _ = try reviewBook.addMessage("Estimate five units", role: "user")
  _ = try reviewBook.addMessage(
    try Value.object([
      "tool": .string("propose_table"),
      "result": try encoded(proposal),
    ]).json(), role: "tool")
  _ = try reviewBook.addMessage("Ready to review", role: "assistant", state: "needs_review")
  let draftHistory = try WorkbookAgent.conversationHistory(reviewBook, conversation: "main")
  try expectEqual(draftHistory.count, 2)
  try expectEqual(draftHistory.last!.content.contains("\"status\":\"draft\""), true)
  let accepted = try reviewBook.accept(proposal.id)
  let acceptedHistory = try WorkbookAgent.conversationHistory(reviewBook, conversation: "main")
  try expectEqual(acceptedHistory.last!.content.contains("\"status\":\"accepted\""), true)
  try expectEqual(acceptedHistory.last!.content.contains("\"meaning\":\"estimate\""), true)
  try expectEqual(acceptedHistory.last!.content.contains(accepted.data["datasetID"].text), true)
  _ = try reviewBook.undoItem(accepted.id)
  let withdrawnHistory = try WorkbookAgent.conversationHistory(reviewBook, conversation: "main")
  try expectEqual(withdrawnHistory.last!.content.contains("\"status\":\"rejected\""), true)
  for incomplete in [false, true] {
    let missing = try Workbook.create(
      at: root.appendingPathComponent("Missing-\(incomplete).sevra"), title: "Missing")
    if incomplete {
      let file = root.appendingPathComponent("Unreadable.fixture")
      try Data([0, 1, 2, 3]).write(to: file)
      _ = try missing.importFile(file)
    }
    let model = ScriptedInference(searchesOnly: true)
    let result = try await WorkbookAgent.run(
      "Find the missing contract", workbook: missing, model: model)
    try expectEqual(result.state, "complete")
    try expectEqual(result.steps, 3)
    try expectEqual(await model.responses, 3)
    try expectEqual(await model.ends, 1)
    try expectEqual(result.citations.count, 0)
    try expectEqual(
      result.answer.contains(incomplete ? "1 incomplete source" : "no incomplete sources"), true)
    try expectEqual(result.answer.contains("missing evidence 3"), true)
  }
  let inventoryPath = root.appendingPathComponent("Inventory.sevra")
  _ = try Demo.create(at: inventoryPath)
  let inventory = try Workbook(inventoryPath)
  let balanceModel = ScriptedInference(balanceOnly: true)
  let balanceAnswer = try await WorkbookAgent.run(
    "What is the brass bolt stock? Cite the basis and movements.",
    workbook: inventory, context: String(repeating: "Closed archive note. ", count: 5000),
    model: balanceModel)
  try expectEqual(balanceAnswer.state, "complete")
  try expectEqual(balanceAnswer.steps, 2)
  try expectEqual(balanceAnswer.citations.count, 2)
  try expectEqual(await balanceModel.ends, 1)
  print(
    "PASS workbook actor lifecycle, history types, proposal states and deterministic search/index coverage limit"
  )
}
