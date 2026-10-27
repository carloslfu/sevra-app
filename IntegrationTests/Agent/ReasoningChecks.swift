import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

func checkReasoningBudget() throws {
  try expectEqual(
    WorkbookAgent.numericValues(
      "1. Quantity 0.10 kg\n2. Stock 1,200 and movement −2; .25 per item."),
    Set(["0.1", "1200", "-2", "0.25"]))
  try expectEqual(WorkbookAgent.numericValues("What was the exact batch code and quantity?"), [])
  try expectEqual(WorkbookAgent.numericValues("Quantity 120."), ["120"])
  try expectEqual(try NativeReasoning.off.budget(outputTokens: 256) == nil, true)
  let budget = try expectValue(NativeReasoning.bounded512.budget(outputTokens: 1800))
  try expectEqual(budget.tokens, 512)
  try expectEqual(budget.end, [248069])
  try expectEqual(budget.alsoEnds, 248058)
  try expectThrows(try NativeReasoning.bounded512.budget(outputTokens: 771))
  _ = try NativeReasoning.bounded512.budget(outputTokens: 772)
  try expectEqual(try NativeReasoning.bounded512.generatedTokens([12, 34, 248069, 248058]), 2)
  try expectThrows(try NativeReasoning.bounded512.generatedTokens([12, 34]))
  try expectThrows(
    try ContextBudget.validateEnvelope([
      InferenceMessage(
        role: "assistant", content: "",
        reasoning: String(repeating: "r", count: ContextBudget.maximumMessageBytes))
    ]))
  print(
    "PASS bounded reasoning preserves a tool-output reserve and requires a closed thinking block")
}

func checkReasoningGrammar(frontend: SplashTextFrontend, factory: SplashGrammarFactory) throws {
  let policy = try NativeCitationPolicy.make(
    ["message:original"], toolScope: .finish, thinking: true)
  let text =
    "Inspect the original. </think>\n<tool_call>\n<function=finish>\n<parameter=answer>\nThe code was recorded.\n</parameter>\n<parameter=basis>\nevidence\n</parameter>\n<parameter=citations>\n[\"message:original\"]\n</parameter>\n</function>\n</tool_call>"
  let tokens = frontend.encode(text)
  let constraint = try factory.create(grammar: policy.grammar)
  _ = try constraint.masks(
    committed: [], simulation: [], words: (SplashTextFrontend.vocabularySize + 31) / 32)
  try constraint.finish(committed: tokens, requireComplete: true)
  let stream = try SplashOutputStream(frontend: frontend, tools: policy.outputTools, thinking: true)
  _ = try stream.append(tokens: tokens)
  let parsed = try stream.finish(.stop).0
  try expectEqual(parsed.reasoning.contains("Inspect the original."), true)
  try expectEqual(parsed.text.contains("Inspect the original."), false)
  try expectEqual(parsed.calls.count, 1)
  try policy.validate(parsed.calls[0])
  let forced = try factory.create(grammar: forcedReasoningPrefixGrammar(policy, "𠀋"))
  try forced.finish(committed: frontend.encode("𠀋" + text), requireComplete: true)
  let messages: [[String: any Sendable]] = [["role": "user", "content": "Recall the code."]]
  let enabled = try frontend.prepare(
    messages: messages, tools: policy.promptTools(), thinking: true)
  let disabled = try frontend.prepare(
    messages: messages, tools: policy.promptTools(), thinking: false)
  try expectEqual(enabled.tokens == disabled.tokens, false)
  let retained = InferenceMessage(
    role: "assistant", content: "",
    toolCalls: [
      .init(id: "lookup", name: "history_read", inputJSON: "{\"id\":\"original\"}")
    ], reasoning: "Synthetic intermediate plan.")
  let tool = InferenceMessage(
    role: "tool", content: "Original evidence", toolCallId: "lookup", toolName: "history_read")
  let current = try frontend.prepare(
    messages: messages + [try nativeTemplateMessage(retained), try nativeTemplateMessage(tool)],
    tools: policy.promptTools(), thinking: true)
  try expectEqual(frontend.decode(current.tokens).contains("Synthetic intermediate plan."), true)
  let later = try frontend.prepare(
    messages: messages + [
      try nativeTemplateMessage(retained), try nativeTemplateMessage(tool),
      ["role": "user", "content": "Next task"],
    ],
    tools: policy.promptTools(), thinking: true)
  try expectEqual(frontend.decode(later.tokens).contains("Synthetic intermediate plan."), false)
  let broken = try SplashOutputStream(frontend: frontend, tools: policy.outputTools, thinking: true)
  _ = try broken.append(tokens: frontend.encode("Still reasoning"))
  try expectEqual(try broken.finish(.length).0.calls.isEmpty, true)
  for thinking in [false, true] {
    let inspection = try NativeCitationPolicy.make([], toolScope: .inspection, thinking: thinking)
    try expectEqual(Set(inspection.outputTools.map(\.name)), WorkbookTools.readOnlyTools)
    let grammar = try factory.create(grammar: inspection.grammar)
    let prefix = thinking ? "Inspect the original. </think>\n" : ""
    let read =
      prefix
      + "<tool_call>\n<function=history_read>\n<parameter=id>\noriginal\n</parameter>\n</function>\n</tool_call>"
    try grammar.finish(committed: frontend.encode(read), requireComplete: true)
    let excluded = try factory.create(grammar: inspection.grammar)
    let finish = thinking ? text : String(text.split(separator: "</think>", maxSplits: 1)[1])
    try expectThrows(try excluded.finish(committed: frontend.encode(finish), requireComplete: true))
  }
  print(
    "PASS reasoning prompt, dynamic citation grammar and stream projection agree; unfinished reasoning cannot dispatch"
  )
}

func forcedReasoningPrefixGrammar(_ policy: SplashToolPolicy, _ prefix: String) throws -> String {
  var wrapper = try Value.parse(policy.grammar).object
  var grammars = wrapper["grammars"]!.array
  var main = grammars[0].object
  main["lark_grammar"] = .string(
    main["lark_grammar"]!.text.replacingOccurrences(
      of: "think: TEXT", with: "think: " + (try Value.string(prefix).json()) + " TEXT"))
  grammars[0] = .object(main)
  wrapper["grammars"] = .array(grammars)
  return try Value.object(wrapper).json()
}

private actor ReasoningHistoryFixture: WorkbookInference {
  let identity = "synthetic reasoning continuity"
  let lastMetrics: Value = .null
  var step = 0
  func beginRun() { step = 0 }
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    step += 1
    if step == 1 {
      try expectEqual(messages.allSatisfy { $0.reasoning.isEmpty }, true)
      return NativeReply(
        text: "",
        calls: [
          .init(
            id: identifier(), name: "calculate",
            inputJSON: "{\"expression\":\"2 + 2\",\"values\":{}}")
        ], reasoning: "Private synthetic intermediate state.")
    }
    try expectEqual(step, 2)
    try expectEqual(messages[messages.count - 2].reasoning, "Private synthetic intermediate state.")
    return NativeReply(
      text: "",
      calls: [
        .init(
          id: identifier(), name: "finish",
          inputJSON: "{\"basis\":\"current_request\",\"answer\":\"4\",\"citations\":[]}")
      ], reasoning: "Private synthetic final state.")
  }
}

func checkReasoningHistory() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-reasoning-history-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root, title: "Reasoning privacy")
  let model = ReasoningHistoryFixture()
  for _ in 0..<2 {
    let reply = try await WorkbookAgent.run(
      "What is two plus two? Make no changes.", workbook: book, model: model)
    try expectEqual(reply.answer, "4")
  }
  let history = try encoded(book.messages(limit: 100)).json()
  let receipts = try Value.array(book.agentRuns()).json()
  let payloads = try book.historySlice().payloads
  try expectEqual(history.contains("Private synthetic"), false)
  try expectEqual(receipts.contains("Private synthetic"), false)
  try expectEqual(try Value.object(payloads).json().contains("Private synthetic"), false)
  let finishes = payloads.values.filter { $0["tool"].text == "finish" }
  try expectEqual(finishes.count, 2)
  try expectEqual(
    finishes.allSatisfy { $0["arguments"]["basis"].text == "current_request" }, true)
  try expectEqual(try book.verify()["ok"], .bool(true))
  print(
    "PASS reasoning survives tool steps, counts toward context, and is absent from saved history and later requests"
  )
}
