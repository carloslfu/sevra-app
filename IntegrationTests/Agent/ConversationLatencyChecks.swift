import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

private actor ConversationRoutingFixture: WorkbookInference {
  let identity = "conversation routing fixture"
  let lastMetrics: Value = .null
  private(set) var prompts: [String] = []
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    prompts.append(messages.last?.content ?? "")
    let arguments = try Value.object([
      "answer": .string("Model fixture response."),
      "basis": .string("general"),
      "citations": .array([]),
    ]).json()
    return NativeReply(
      text: "", calls: [.init(id: "routing-\(prompts.count)", name: "finish", inputJSON: arguments)])
  }
}

/// Try the same completed read, a distinct subject, then repeat that subject twice.
private actor RepeatingCalculationFixture: WorkbookInference {
  let identity = "calculation reuse fixture"
  let lastMetrics: Value = .null
  private var index = 0
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    let subjects = ["brass bolts", "brass bolts", "washers", "washers", "washers"]
    if index > 0 {
      let previous = try Value.parse(messages.last!.content)
      if [2, 4, 5].contains(index) {
        try require(previous["reusedReceiptID"].string != nil, "test", "Duplicate calculation executed")
      } else {
        try require(previous["openingQuantity"].text == (index == 1 ? "20" : "7"),
          "test", "Distinct calculation did not obtain its own opening basis")
      }
    }
    let final = index == subjects.count
    try require((toolScope == .finish) == final, "test", "Distinct inputs lost their tool access")
    let arguments: Value = final
      ? .object(["answer": .string("There are 18 brass bolts and 7 washers."),
        "basis": .string("evidence"), "citations": .array([])])
      : .object(["subject": .string(subjects[index])])
    index += 1
    return .init(text: "", calls: [.init(id: "lookup-\(index)",
      name: final ? "finish" : "balance", inputJSON: try arguments.json())])
  }
}

func checkConversationLatency() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(
    at: root.appendingPathComponent("Conversation.sevra"), title: "Conversation")
  let model = ConversationRoutingFixture()
  let prompts = ["hey", "what can you do for me?", "tell me more", "tldr", "hola"]
  for prompt in prompts {
    let result = try await WorkbookAgent.run(
      prompt, workbook: book, model: model, conversationInput: true)
    try require(
      result.steps == 1 && result.state == "complete" && result.answer == "Model fixture response.",
      "test", "The conversation bypassed its model for: " + prompt)
  }
  let seen = await model.prompts
  try require(seen == prompts, "test", "The model did not receive the submitted conversation")
  let cancelled = Cancellation()
  cancelled.cancel()
  let messagesBeforeCancel = try book.messages().count
  do {
    _ = try await WorkbookAgent.run("hello", workbook: book, cancellation: cancelled, model: model)
    throw SevraError("test", "Cancelled conversation completed")
  } catch let error as SevraError {
    try require(error.code == "cancelled", "test", "Unexpected cancellation result")
  }
  try require(
    try book.messages().count == messagesBeforeCancel + 2, "test",
    "Cancelled submission lost its diagnostic")
  try require(try book.verify()["ok"] == .bool(true), "test", "Conversation damaged the workbook")

  let example = root.appendingPathComponent("Calculation.sevra")
  _ = try Demo.create(at: example)
  let stock = try Workbook(example)
  let basis = try stock.balance(subject: "brass bolts")["basis"].text
  try stock.setOpeningBalance(subject: "washers", quantity: "7", effective: "2026-01-01", sourceID: basis)
  let both = try await WorkbookAgent.run(
    "How many brass bolts and washers are there? Do not change the workbook.",
    workbook: stock, model: RepeatingCalculationFixture(), conversationInput: true)
  try require(both.steps == 6 && both.state == "complete" && both.citations.contains(basis),
    "test", "Repeated-read recovery lost the verified evidence")
  // The visible vocabulary stays generic, but a calculation input is never a count receipt.
  let countID = identifier()
  func finishCount(_ id: String, policy: SplashToolPolicy) throws -> SplashToolCandidate {
    try ToolPolicyChecks().candidate("finish", [
      ("answer", "Counted."), ("basis", "evidence"), ("citations", "[]"),
      ("counts", try Value.array([.string(id)]).json()),
    ], policy: policy)
  }
  let available = try NativeCitationPolicy.make([], countReceiptIDs: [countID])
  try available.validate(finishCount(countID, policy: available))
  for policy in [available, try NativeCitationPolicy.make([], countReceiptIDs: [])] {
    do {
      try policy.validate(finishCount("2 calculation inputs", policy: policy))
      throw SevraError("test", "A fabricated count receipt was admitted")
    } catch is SplashError { }
  }
  let sourceID = identifier()
  let link = "[Original quote](sevra://item/" + sourceID + ")"
  let assistantID = try book.addMessage("Known cost. " + link, role: "assistant")
  let assistant = try book.historyMessage(assistantID)
  let presented = WorkbookAgent.historyPresentation(assistant)
  try require(
    presented.text == "Known cost. Original quote" && presented.ids == [sourceID],
    "test", "History copied presentation URLs or lost lookup identity")
  let userID = try book.addMessage(link, role: "user")
  let user = try book.historyMessage(userID)
  try require(WorkbookAgent.historyPresentation(user).text == link, "test", "User original changed")
  let saved = try book.addMessage(assistant.body, role: "assistant")
  _ = try WorkbookAgent.conversationHistory(book, conversation: "main")
  try require(
    try book.historyMessage(saved).body == assistant.body, "test", "Saved original changed")

  // Different exact choices produce identical prompt declarations, but the
  // original constrained schemas still reject invented or out-of-scope IDs.
  func policy(_ id: String) throws -> SplashToolPolicy {
    try NativeCitationPolicy.make([id], itemReferenceIDs: [id], historyReferenceIDs: [id])
  }
  let first = identifier()
  let second = identifier()
  let a = try policy(first)
  let b = try policy(second)
  let aJSON = try JSONSerialization.data(withJSONObject: a.promptTools(), options: [.sortedKeys])
  let bJSON = try JSONSerialization.data(withJSONObject: b.promptTools(), options: [.sortedKeys])
  try require(aJSON == bJSON, "test", "Dynamic IDs changed the prompt prefix")
  try a.validate(ToolPolicyChecks().candidate("read", [("id", first)], policy: a))
  do {
    try a.validate(ToolPolicyChecks().candidate("read", [("id", second)], policy: a))
    throw SevraError("test", "Prompt projection weakened ID validation")
  } catch is SevraError {
    throw SevraError("test", "ID validation accepted a different choice")
  } catch { /* Expected schema refusal. */  }
  print(
    "PASS model-backed conversation and follow-ups, cancellation, and stable prompt/strict ID validation"
  )
}

/// Runs the ordinary agent with the real native model on disposable workbooks.
func runConversationLatencyProbe(
  modelsRoot: String, library: String, engine: String, output: String, stockOnly: Bool = false,
  cacheTrace: Bool = false, desktopContext: Bool = false
)
  async throws
{
  let root = URL(fileURLWithPath: output)
  try require(
    !FileManager.default.fileExists(atPath: output), "fixture", "Use a new output directory")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let model = NativeWorkbookModel(
    configuration: try nativeProbeConfiguration(
      library: library, engine: engine, modelsRoot: modelsRoot,
      budget: .init(profile: .evaluation64K), reasoning: .bounded512, modelLayout: .installed))
  let book = try Workbook.create(
    at: root.appendingPathComponent("Conversation.sevra"), title: "Conversation")
  var rows: [Value] = []
  let introductoryPrompts = [
    "hey", "what can you do for me?", "tell me more", "tldr",
    "Could you explain what a reorder point is in plain English?",
    "Give me one sentence that explains the difference between a quote and an invoice.",
    "¿Para qué serviría este cuaderno en una panadería?",
  ]
  for prompt in stockOnly || cacheTrace || desktopContext ? [] : introductoryPrompts {
    let started = ProcessInfo.processInfo.systemUptime
    let previews = ProbePreviews(started: started)
    let result = try await WorkbookAgent.run(
      prompt, workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot),
      cancellation: .init(deadlineAfterSeconds: 180), answerPreview: { previews.receive($0) },
      model: model, conversationInput: true)
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    let metrics = try book.agentRuns().first?["metrics"] ?? .null
    let words = result.answer.split(whereSeparator: \.isWhitespace).count
    let row: Value = .object([
      "prompt": .string(prompt), "wallSeconds": .number(elapsed),
      "answer": .string(result.answer), "words": .number(Double(words)),
      "steps": .number(Double(result.steps)), "state": .string(result.state),
      "runMetrics": metrics,
      "preview": previews.snapshot(),
    ])
    rows.append(row)
    print(try row.json())
    try Data(Value.array(rows).json().utf8).write(
      to: root.appendingPathComponent("results.json"), options: .atomic)
    try require(previews.hasCleared, "quality", "Provisional text survived completion")
  }
  try require(try book.verify()["ok"] == .bool(true), "quality", "Integrity failed")
  let businessURL = root.appendingPathComponent("Business.sevra")
  _ = try Demo.create(at: businessURL)
  let business = try Workbook(businessURL)
  let originals = try business.items()
  var businessRows: [Value] = []
  let businessPrompts = [
    "What is the current stock of brass bolts? Use the balance tool and cite the evidence. Do not change the workbook.",
    "How many brass bolts are currently in stock? Use the balance tool and cite the evidence. Do not change the workbook.",
  ]
  var sequence = stockOnly ? Array(businessPrompts.prefix(1)) : businessPrompts
  if desktopContext { sequence = Array(businessPrompts.prefix(1)) }
  if cacheTrace { sequence += ["hey", "hey", businessPrompts[0]] }
  for (index, prompt) in sequence.enumerated() {
    if cacheTrace && index == 4 { try await Task.sleep(nanoseconds: 125_000_000_000) }
    let started = ProcessInfo.processInfo.systemUptime
    let previews = ProbePreviews(started: started)
    let result = try await WorkbookAgent.run(
      prompt, workbook: business, context: desktopContext ? "Space: Home\nActive space ID: home" : "", modelDirectory: URL(fileURLWithPath: modelsRoot),
      cancellation: .init(deadlineAfterSeconds: 180),
      progress: { previews.recordProgress($0) }, answerPreview: { previews.receive($0) },
      model: model, conversationInput: true)
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    let balance = try business.balance(subject: "brass bolts", asOf: "2099-12-31")
    let citations = Set(
      [balance["basis"].text] + balance["effects"].array.map { $0["item_id"].text })
    let originalIDs = Set(originals.map(\.id))
    let currentItems = try business.items()
    let integrity = try business.verify()
    let greeting = cacheTrace && (index == 2 || index == 3)
    let correctAnswer = greeting
      ? result.steps == 1 && !result.answer.isEmpty && result.citations.isEmpty
      : result.answer.contains("18") && Set(result.citations).isSuperset(of: citations)
    let passed = correctAnswer
      && currentItems.filter { originalIDs.contains($0.id) } == originals
      && integrity["ok"] == .bool(true) && previews.hasCleared
    let metrics = try business.agentRuns().first?["metrics"] ?? .null
    if cacheTrace, index > 0 {
      let measurements = try metrics.string.map(Value.parse) ?? metrics
      let call = measurements.array.first { $0["matchedPromptTokens"].int != nil }
      try require((call?["matchedPromptTokens"].int ?? 0) >= 2048, "quality",
        "The real helper did not resume a shared workbook prefix.")
      // Turns 2 and 4 repeat the previous turn's scope, so they resume its saved
      // conversation instead of computing the earlier turns again after the header.
      if [1, 3].contains(index) {
        let header = max(call?["stablePrefixTokens"].int ?? 0, call?["scopePrefixTokens"].int ?? 0)
        try require((call?["matchedPromptTokens"].int ?? 0) > header, "quality",
          "A same-scope follow-up resumed only the shared header, not the previous turn.")
      }
    }
    let row: Value = .object([
      "prompt": .string(prompt),
      "wallSeconds": .number(elapsed),
      "answer": .string(result.answer), "steps": .number(Double(result.steps)),
      "runMetrics": metrics, "preview": previews.snapshot(), "passed": .bool(passed),
      "progress": .array(previews.progressEvents),
    ])
    businessRows.append(row)
    print(try row.json())
    try Data(Value.array(businessRows).json().utf8).write(
      to: root.appendingPathComponent("business-results.json"), options: .atomic)
    try require(passed, "quality", "Business evidence or integrity regression")
  }
  _ = await model.unload()
}

private final class ProbePreviews: @unchecked Sendable {
  private let lock = NSLock()
  private let started: Double
  private var first: Double?
  private var updates = 0
  private var last: AnswerPreview?
  private var events: [Value] = []
  init(started: Double) { self.started = started }
  func recordProgress(_ text: String) {
    lock.lock()
    defer { lock.unlock() }
    events.append(.object([
      "seconds": .number(ProcessInfo.processInfo.systemUptime - started),
      "status": .string(text),
    ]))
  }
  var progressEvents: [Value] {
    lock.lock()
    defer { lock.unlock() }
    return events
  }
  func receive(_ value: AnswerPreview) {
    lock.lock()
    defer { lock.unlock() }
    if value.text?.isEmpty == false {
      if first == nil { first = ProcessInfo.processInfo.systemUptime - started }
      updates += 1
    }
    last = value
  }
  var hasCleared: Bool {
    lock.lock()
    defer { lock.unlock() }
    return last?.text == nil
  }
  func snapshot() -> Value {
    lock.lock()
    defer { lock.unlock() }
    return .object([
      "firstSeconds": first.map(Value.number) ?? .null,
      "updates": .number(Double(updates)), "cleared": .bool(last?.text == nil),
    ])
  }
}
