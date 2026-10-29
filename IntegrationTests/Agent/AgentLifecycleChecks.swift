import Foundation
import SevraAI
import SevraBaseline
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
  let filteredSearches: Bool
  let balanceOnly: Bool
  let omitBalanceCitation: Bool
  let inlineBalanceReferences: Bool
  let initialBasis: String?
  var balanceIDs: [String] = []
  let violateReadOnly: Bool
  init(
    cancelAfterResponse: Bool = false, fail: Bool = false, searchesOnly: Bool = false,
    balanceOnly: Bool = false, violateReadOnly: Bool = false, filteredSearches: Bool = false,
    omitBalanceCitation: Bool = false, initialBasis: String? = nil,
    inlineBalanceReferences: Bool = false
  ) {
    self.cancelAfterResponse = cancelAfterResponse
    self.fail = fail
    self.searchesOnly = searchesOnly
    self.filteredSearches = filteredSearches
    self.balanceOnly = balanceOnly
    self.omitBalanceCitation = omitBalanceCitation
    self.inlineBalanceReferences = inlineBalanceReferences
    self.initialBasis = initialBasis
    self.violateReadOnly = violateReadOnly
  }
  func beginRun() throws { begins += 1 }
  func endRun() { ends += 1 }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    responses += 1
    if let initialBasis {
      if responses == 1 {
        return NativeReply(
          text: "",
          calls: [
            .init(
              id: "unsupported-finish", name: "finish",
              inputJSON: try Value.object([
                "answer": .string("Unsupported workbook claim."), "basis": .string(initialBasis),
                "citations": .array([]),
              ]).json())
          ])
      }
      if initialBasis == "evidence" && responses == 2 {
        try expectEqual(toolScope, .inspection)
        return NativeReply(
          text: "",
          calls: [
            .init(
              id: "inspect-before-finish", name: "history_search",
              inputJSON: "{\"query\":\"missing fixture\"}")
          ])
      }
      try expectEqual(responses, initialBasis == "evidence" ? 3 : 2)
      try expectEqual(toolScope, .answer)
      if initialBasis != "evidence" {
        try expectEqual(messages.last!.content.contains("error"), true)
      }
    }
    if fail { throw SevraError("fixture_failure", "Synthetic failure") }
    if cancelAfterResponse { cancellation.cancel() }
    if violateReadOnly {
      try expectEqual(toolScope, .answer)
      if responses == 1 {
        return NativeReply(
          text: "",
          calls: [
            .init(
              id: "unwanted-draft", name: "draft",
              inputJSON: "{\"title\":\"Unwanted\",\"text\":\"No\",\"inputs\":[]}")
          ])
      }
      try expectEqual(responses, 2)
      try expectEqual(messages.last!.content.contains("explicitly forbids changes"), true)
    }
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
      if responses == 2 {
        let balance = try Value.parse(messages.last!.content)
        balanceIDs = [balance["basis"].text] + balance["effects"].array.map { $0["item_id"].text }
        try expectEqual(balance["evidence"]["referenceType"].text, "item-version")
        try expectEqual(balance["evidence"]["citations"].array.compactMap(\.string), balanceIDs)
        try expectEqual(
          balance["evidence"]["notice"].text.contains("not conversation messages"), true)
      } else {
        try expectEqual(responses, 3)
        try expectEqual(omitBalanceCitation, true)
        try expectEqual(messages.last!.content.contains("every inspected input"), true)
        try expectEqual(messages.last!.content.contains("not conversation-message IDs"), true)
      }
      try expectEqual(balanceIDs.allSatisfy { citationIDs.contains($0) && !$0.isEmpty }, true)
      let ids = omitBalanceCitation && responses == 2 ? Array(balanceIDs.prefix(1)) : balanceIDs
      return NativeReply(
        text: "",
        calls: [
          InferenceCall(
            id: "balance-finish-\(responses)", name: "finish",
            inputJSON: try Value.object([
              "answer": .string(
                "The current stock is 18 brass bolts."
                  + (inlineBalanceReferences
                    ? " Source " + balanceIDs[0] + "; movement " + balanceIDs[1].uppercased() : "")),
              "basis": .string("evidence"),
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
            inputJSON: try Value.object(
              filteredSearches
                ? ["query": .string("missing evidence \(responses)"), "kind": .string("note")]
                : ["query": .string("missing evidence \(responses)")]
            ).json())
        ])
    }
    return NativeReply(
      text: "",
      calls: [
        InferenceCall(
          id: "fixture-call", name: "finish",
          inputJSON: "{\"basis\":\"general\",\"answer\":\"No changes requested.\",\"citations\":[]}"
        )
      ])
  }
}

func checkAgentLifecycle() async throws {
  let reference = "97ec6562-c4e4-4f4b-87bb-67e2ed0e92e8"
  for prose in ["Current version " + reference, "Current version 97ec6562", "Message:97EC6562"] {
    try expectEqual(WorkbookAgent.containsOpaqueReference(prose, inspected: [reference]), true)
  }
  try expectEqual(
    WorkbookAgent.containsOpaqueReference(
      "Batch WILLOW-12, quantity 0.20 kg", inspected: [reference]), false)
  let unknown = "10000000-1000-4000-8000-100000000001"
  let mixed = "Source: (" + reference + ") row " + unknown + " Message:97EC6562"
  try expectEqual(
    WorkbookAgent.opaqueReferences(mixed, inspected: ["message:" + reference]),
    [unknown, "97EC6562", reference].sorted())
  let feedback = WorkbookAgent.opaqueReferenceFeedback(mixed, inspected: [reference])!
  for literal in [reference, unknown, "97EC6562", "source IDs in parentheses", "citations array"] {
    try expectEqual(feedback.contains(literal), true)
  }
  try expectEqual(
    WorkbookAgent.opaqueReferenceFeedback("Batch WILLOW-12, 0.20 kg", inspected: [reference]), nil)
  let prose = "Résumé " + reference.uppercased() + "; source " + reference + "; " + unknown
  let aliases = WorkbookAgent.renderableReferences(
    prose, citations: [reference], inspected: [reference])
  try expectEqual(aliases.count, 2)
  let rendered = WorkbookAgent.renderReferenceLinks(prose, references: aliases) { id in
    "[Source](sevra://item/" + id + ")"
  }
  try expectEqual(
    rendered,
    "Résumé [Source](sevra://item/" + reference
      + "); source [Source](sevra://item/" + reference + "); " + unknown)
  for text in [
    "`" + reference + "`", "[Source](sevra://item/" + reference + ")",
    "message:" + reference, String(reference.prefix(8)),
    "~~~\n" + reference + "\n~~~", "    " + reference, "\t" + reference,
    "[label][" + reference + "]", "<span>" + reference + "</span>",
  ] {
    try expectEqual(
      WorkbookAgent.renderableReferences(text, citations: [reference], inspected: [reference])
        .isEmpty, true)
  }
  try expectEqual(
    WorkbookAgent.renderableReferences(reference, citations: [], inspected: [reference]).isEmpty,
    true)
  try expectEqual(
    WorkbookAgent.renderableReferences(reference, citations: [reference], inspected: []).isEmpty,
    true)
  try expectEqual(WorkbookAgent.citationLabel("[A]*`\\\nB"), "\\[A\\]\\*\\`\\\\ B")
  let hostileTitle = "[untrusted](https://example.invalid) *name*\n<source>"
  let safeLink =
    "[" + WorkbookAgent.citationLabel(hostileTitle) + "](sevra://item/" + reference + ")"
  let attributed = try AttributedString(markdown: safeLink)
  try expectEqual(
    String(attributed.characters), hostileTitle.replacingOccurrences(of: "\n", with: " "))
  try expectEqual(
    Set(attributed.runs.compactMap { $0.link?.absoluteString }), ["sevra://item/" + reference])
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-agent-lifecycle-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let readOnlyBook = try Workbook.create(
    at: root.appendingPathComponent("ReadOnly.sevra"), title: "Read only")
  for basis in ["evidence", "completed_action", "unsupported"] {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Basis-\(basis).sevra"), title: "Answer basis")
    let result = try await WorkbookAgent.run(
      "Just acknowledge. Make no changes.", workbook: book,
      model: ScriptedInference(initialBasis: basis))
    try expectEqual(result.steps, basis == "evidence" ? 3 : 2)
    try expectEqual(result.answer, "No changes requested.")
    try expectEqual(
      try book.messages().filter {
        $0.role == "assistant" && $0.body.contains("Unsupported workbook claim")
      }.isEmpty, true)
  }
  let readOnlyTools = WorkbookTools(readOnlyBook, readOnly: true)
  for tool in NativeTools.definitions
  where tool.name != "finish" && !WorkbookTools.readOnlyTools.contains(tool.name) {
    do {
      _ = try readOnlyTools.execute(tool.name, .object([:]))
      throw SplashError("Mutating tool was allowed")
    } catch let error as SevraError { try expectEqual(error.code, "read_only_request") }
  }
  for prompt in [
    "What is the value? Make no changes.", "Do not change anything.", "Don't change the workbook!",
    "No hagas cambios.",
  ] {
    try expectEqual(RequestRestrictions.isExplicitlyReadOnly(prompt), true)
  }
  try expectEqual(
    RequestRestrictions.isExplicitlyReadOnly("Create a draft about change control."), false)
  let readOnlyAnswer = try await WorkbookAgent.run(
    "Explain the workbook. Make no changes.", workbook: readOnlyBook,
    model: ScriptedInference(violateReadOnly: true))
  try expectEqual(readOnlyAnswer.state, "complete")
  try expectEqual(try readOnlyBook.items(kind: "document").isEmpty, true)
  try expectEqual(try readOnlyBook.unresolvedToolCalls().isEmpty, true)
  try expectEqual(try readOnlyBook.verify()["ok"], .bool(true))
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
      try expectEqual(history.count, 1)
      try expectEqual(history.allSatisfy { $0.role == "assistant" }, true)
      try expectEqual(history.last!.content.contains("status " + expected), true)
      try expectEqual(history.last!.content.contains("It is not pending"), true)
      try expectEqual(history.last!.content.contains("Just acknowledge. Make no changes."), false)
      try expectEqual(
        try book.historyMessage(request.id, conversation: "main").body,
        "Just acknowledge. Make no changes.")
      try expectEqual(try book.requestRunStatus(request.id), expected)
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
  try expectEqual(draftHistory.count, 1)
  try expectEqual(draftHistory[0].role, "assistant")
  try expectEqual(draftHistory[0].content.contains("historical information only"), true)
  let saved = try Value.parse(
    String(draftHistory[0].content.split(separator: "\n", maxSplits: 1)[1]))
  try expectEqual(saved.array.map { $0["role"].text }, ["user", "assistant"])
  try expectEqual(saved.array[0]["text"].text, "Estimate five units")
  try expectEqual(saved.array[0]["id"].text.isEmpty, false)
  try expectEqual(draftHistory.last!.content.contains("\"status\":\"draft\""), true)
  let accepted = try reviewBook.accept(proposal.id)
  let historicalRead = try WorkbookTools(reviewBook, readOnly: true).execute(
    "read", .object(["id": .string(proposal.id)]))
  try expectEqual(historicalRead["item"]["status"].text, "draft")
  try expectEqual(historicalRead["isCurrentVersion"], .bool(false))
  try expectEqual(historicalRead["currentVersion"]["id"].text, accepted.id)
  try expectEqual(historicalRead["currentVersion"]["status"].text, "accepted")
  try expectEqual(historicalRead["currentVersion"]["meaning"].text, "estimate")
  try expectEqual(
    WorkbookAgent.visibleEvidence(tool: "read", result: historicalRead).map(\.0), [proposal.id])
  let acceptedHistory = try WorkbookAgent.conversationHistory(reviewBook, conversation: "main")
  try expectEqual(acceptedHistory.last!.content.contains("\"status\":\"accepted\""), true)
  try expectEqual(acceptedHistory.last!.content.contains("\"meaning\":\"estimate\""), true)
  try expectEqual(acceptedHistory.last!.content.contains(accepted.data["datasetID"].text), true)
  _ = try reviewBook.undoItem(accepted.id)
  let withdrawnHistory = try WorkbookAgent.conversationHistory(reviewBook, conversation: "main")
  try expectEqual(withdrawnHistory.last!.content.contains("\"status\":\"rejected\""), true)
  for (incomplete, filtered) in [(false, false), (true, false), (false, true), (true, true)] {
    let missing = try Workbook.create(
      at: root.appendingPathComponent("Missing-\(incomplete)-\(filtered).sevra"), title: "Missing")
    if incomplete {
      let file = root.appendingPathComponent("Unreadable.fixture")
      try Data([0, 1, 2, 3]).write(to: file)
      _ = try missing.importFile(file)
    }
    let model = ScriptedInference(searchesOnly: true, filteredSearches: filtered)
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
    try expectEqual(result.answer.contains("also searched earlier messages"), !filtered)
    try expectEqual(result.answer.contains("queries were limited to business evidence"), filtered)
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
  let corrected = try await WorkbookAgent.run(
    "What is the brass bolt stock? Cite the basis and movements. Make no changes.",
    workbook: inventory, model: ScriptedInference(balanceOnly: true, omitBalanceCitation: true))
  try expectEqual(corrected.state, "complete")
  try expectEqual(corrected.steps, 3)
  try expectEqual(Set(corrected.citations), Set(balanceAnswer.citations))
  let validations = try inventory.messages(limit: 100).filter {
    $0.role == "tool" && $0.body.contains("every inspected input")
  }
  try expectEqual(validations.count, 1)
  let linked = try await WorkbookAgent.run(
    "What is the brass bolt stock? Cite the basis and movements. Make no changes.",
    workbook: inventory, model: ScriptedInference(balanceOnly: true, inlineBalanceReferences: true))
  try expectEqual(linked.steps, 2)
  try expectEqual(Set(linked.citations), Set(balanceAnswer.citations))
  try expectEqual(linked.answer.contains("[Workshop inventory](sevra://item/"), true)
  try expectEqual(linked.answer.components(separatedBy: "sevra://item/").count, 3)
  let savedLinked = try inventory.messages(limit: 100).last!
  let savedPayload = try inventory.messagePayload(savedLinked.id)
  try expectEqual(savedPayload["renderedReferences"].object.count, 2)
  try expectEqual(savedPayload["arguments"]["answer"].text.contains("sevra://"), false)
  try expectEqual(try inventory.balance(subject: "brass bolts")["quantity"].text, "18")
  print(
    "PASS full inspected and cited item IDs render as safe native links without another model turn; unknown and ambiguous references remain refused"
  )
  print(
    "PASS workbook actor lifecycle, history types, proposal states and deterministic search/index coverage limit"
  )
}
