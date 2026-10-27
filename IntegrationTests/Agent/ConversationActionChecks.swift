import Foundation
import SevraAI
import SevraBaseline
import SevraCore
import SevraNativeAI
import SevraSplashGrammar
import SevraSplashText

private actor ConversationActionModel: WorkbookInference {
  let identity = "synthetic conversation action fixture"
  let lastMetrics: Value = .object(["fixture": .bool(true)])
  let arguments: Value
  let cancelResponse: Bool
  var calls = 0
  var ends = 0
  init(_ arguments: Value, cancelResponse: Bool = false) {
    self.arguments = arguments
    self.cancelResponse = cancelResponse
  }
  func beginRun() {}
  func endRun() { ends += 1 }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    calls += 1
    if cancelResponse { cancellation.cancel() }
    if calls == 1 {
      let tool = WorkbookTools.conversationTools.first { $0.value == arguments["action"].text }!.key
      let fields = arguments.object.filter { $0.key != "action" }
      return .init(
        text: "This untrusted assistant claim must not be published.",
        calls: [
          .init(
            id: "interface-action", name: tool, inputJSON: try Value.object(fields).json())
        ])
    }
    try require(
      messages.last!.content.contains("error"), "fixture",
      "Unexpected extra model turn after action")
    return .init(
      text: "",
      calls: [
        .init(
          id: "clarify", name: "finish",
          inputJSON:
            "{\"answer\":\"Please choose an earlier exchange in this thread.\",\"basis\":\"general\",\"citations\":[]}"
        )
      ])
  }
}

func checkConversationActions() async throws {
  let checks = ToolPolicyChecks()
  let mainPolicy = try NativeCitationPolicy.make([], conversationActions: ["start_thread"])
  try mainPolicy.validate(
    checks.candidate("start_thread", [], policy: mainPolicy))
  try expectThrows(
    try mainPolicy.validate(
      checks.candidate(
        "rename_current_thread", [("title", "Other")], policy: mainPolicy
      )))
  let restrictedTools = try NativeTools.referenceDefinitions(conversationActions: [])
  try expectEqual(
    restrictedTools.contains { WorkbookTools.conversationTools[$0.name] != nil }, false)
  let baseline = try LocalModel.baselineDefinitions(conversationActions: ["start_thread"])
  let native = try NativeTools.referenceDefinitions(conversationActions: ["start_thread"])
  try expectEqual(
    try Value.parse(baseline.first { $0.name == "start_thread" }!.parameters.jsonText),
    native.first { $0.name == "start_thread" }!.parameters)
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-conversation-actions-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let b = try Workbook.create(at: root, title: "Synthetic conversation actions")
  let parent = try b.addMessage("Compare delivery dates for these suppliers.", role: "user")
  let source = try b.addMessage(
    "Delivery is estimated for Friday; no order has been placed.", role: "assistant")
  let create = ConversationActionModel(
    .object(["action": .string("start_thread"), "title": .string("Delivery")]))
  let created = try await WorkbookAgent.run(
    "Explore this in a separate discussion.", workbook: b, model: create)
  try expectEqual(created.conversationAction?.kind, .created)
  try expectEqual(await create.calls, 1)
  try expectEqual(await create.ends, 1)
  try expectEqual(created.answer, "Created a thread.")
  let thread = created.conversationAction!.conversation
  try expectEqual(created.conversationAction?.message, source)
  try expectEqual(try b.messages(conversation: thread).count, 0)
  _ = try b.addMessage("Keep inventory unchanged.", role: "user", conversation: thread)
  let finding = try b.addMessage(
    "Friday delivery is an estimate, not a commitment.", role: "assistant", conversation: thread)
  let mainBefore = try b.messages().map(\.id)
  let share = ConversationActionModel(
    .object([
      "action": .string("review_summary"),
      "summary": .string("Friday delivery remains an estimate."),
    ]))
  let review = try await WorkbookAgent.run(
    "Bring the selected findings back for review.", workbook: b, conversation: thread, model: share)
  try expectEqual(review.conversationAction?.kind, .reviewSummary)
  try expectEqual(review.conversationAction?.message, finding)
  try expectEqual(try b.messages().map(\.id), mainBefore)
  try expectEqual(try b.latestShareableAnswer(conversation: thread)?.id, finding)
  try expectEqual(review.answer.contains("Nothing has been shared"), true)
  let rename = ConversationActionModel(
    .object(["action": .string("rename_thread"), "title": .string("Entregas")]))
  let renamed = try await WorkbookAgent.run(
    "Cambia el nombre de este hilo a Entregas.", workbook: b, conversation: thread, model: rename)
  try expectEqual(renamed.conversationAction?.kind, .renamed)
  try expectEqual(try b.conversationIdentity(thread)["title"].text, "Entregas")
  let back = ConversationActionModel(.object(["action": .string("return_to_main")]))
  let returned = try await WorkbookAgent.run(
    "Let's return to our main discussion.", workbook: b, conversation: thread, model: back)
  try expectEqual(returned.conversationAction?.conversation, "main")
  try expectEqual(try b.messages().map(\.id), mainBefore)
  let forged = ConversationActionModel(
    .object(["action": .string("review_summary"), "message": .string(parent)]))
  let refused = try await WorkbookAgent.run(
    "Review the earlier finding.", workbook: b, conversation: thread, model: forged)
  try expectEqual(refused.conversationAction, nil)
  try expectEqual(await forged.calls, 2)
  let readonly = ConversationActionModel(.object(["action": .string("start_thread")]))
  let count = try b.conversations().count
  let restricted = try await WorkbookAgent.run(
    "Do not make any changes.", workbook: b, model: readonly)
  try expectEqual(restricted.conversationAction, nil)
  try expectEqual(try b.conversations().count, count)
  let cancelled = ConversationActionModel(
    .object(["action": .string("start_thread")]), cancelResponse: true)
  do {
    _ = try await WorkbookAgent.run("Branch this discussion.", workbook: b, model: cancelled)
    throw SevraError("fixture", "Cancelled response executed an action")
  } catch let e as SevraError { try expectEqual(e.code, "cancelled") }
  try expectEqual(try b.conversations().count, count)
  try expectEqual(await cancelled.ends, 1)
  try expectEqual(try b.verify()["ok"], .bool(true))
  print(
    "PASS terminal conversation actions, exact parent, rename, review without sharing, scope/refusal and cancellation"
  )
}

func checkConversationActionGrammar(
  frontend: SplashTextFrontend, factory: SplashGrammarFactory
) throws {
  for thinking in [false, true] {
    let main = try NativeCitationPolicy.make(
      [], thinking: thinking, conversationActions: ["start_thread"])
    let thread = try NativeCitationPolicy.make(
      [], thinking: thinking,
      conversationActions: ["start_thread", "rename_thread", "return_to_main", "review_summary"])
    let restricted = try NativeCitationPolicy.make(
      [], thinking: thinking, conversationActions: [])
    func output(_ action: String) -> [UInt32] {
      let tool = WorkbookTools.conversationTools.first { $0.value == action }!.key
      return frontend.encode(
        (thinking ? "Use the available interface action.</think>\n" : "")
          + "<tool_call>\n<function=" + tool + ">\n</function>\n</tool_call>")
    }
    let create = try factory.create(grammar: main.grammar)
    try create.finish(committed: output("start_thread"), requireComplete: true)
    let review = try factory.create(grammar: thread.grammar)
    try review.finish(committed: output("review_summary"), requireComplete: true)
    let wrongScope = try factory.create(grammar: main.grammar)
    try expectThrows(
      try wrongScope.finish(committed: output("review_summary"), requireComplete: true))
    let readOnly = try factory.create(grammar: restricted.grammar)
    try expectThrows(
      try readOnly.finish(committed: output("start_thread"), requireComplete: true))
  }
  print("PASS native conversation capability masks change with scope and read-only state")
}
