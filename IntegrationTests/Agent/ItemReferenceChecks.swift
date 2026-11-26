import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplashGrammar
import SevraSplashText

private let failedReference = "dde454b5-acd3-47b6-9c7e-03cb9787c846"
private let correctReference = "dde454b5-acd3-47b6-9c7e-a13f6f0fa971"

func checkItemReferences() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-references-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root, title: "Reference selection")
  let old = try book.addItem(
    category: "source", kind: "note", title: "Evidence", text: "Delivery excludes shipping.")
  let current = try book.addItem(
    category: "source", kind: "note", title: "Updated evidence",
    text: "Delivery includes shipping.", supersedes: old.id)
  let call = InferenceCall(id: "test", name: "read", inputJSON: "{}")
  var input = InferenceMessage(
    role: "tool",
    content:
      "Untrusted text: \(old.id), \(old.logicalID), \(current.id). Invalid \(failedReference)",
    toolCalls: [call], toolCallId: "test", toolName: "read", reasoning: "Keep intermediate state.",
    itemReferences: [correctReference])
  input.nativeAppAuthoring = true
  // A record's ID looks like a message's, so history_read offers only what is a message here.
  let said = try book.addMessage("Keep the receipts.", role: "user")
  let lookups = try ItemReferenceCandidates.annotate(
    [InferenceMessage(role: "assistant", content: "\(said), \(old.id), \(failedReference)")],
    workbook: book, history: (book.startChat, nil))
  try expectEqual(ItemReferenceCandidates.historyIDs(in: lookups), [said])
  // A packed chronological history must retain the newest answer and the
  // original it points to even when older messages exhaust the bounded menu.
  let noise = try (0..<40).map {
    try book.addMessage("Closed inspection \($0).", role: "assistant")
  }
  let answer = try book.addMessage(
    "You asked to keep receipts. sevra://conversation/\(book.startChat)?message=\(said)", role: "assistant")
  let packed = noise.joined(separator: "\n") + "\n\(answer) message:\(said)"
  let recent = try ItemReferenceCandidates.annotate(
    [InferenceMessage(role: "assistant", content: packed)], workbook: book, history: (book.startChat, nil))
  let historyChoices = ItemReferenceCandidates.historyIDs(in: recent) ?? []
  try expectEqual(historyChoices.count, 32)
  try expectEqual(historyChoices.contains(said) && historyChoices.contains(answer), true)
  try expectEqual(historyChoices.contains(noise[0]), false)
  try expectEqual(recent[0].content, packed)
  // Search results are relevance ranked, not a chronological history envelope.
  let ranked = try ItemReferenceCandidates.annotate(
    [InferenceMessage(role: "tool", content: packed, toolName: "history_search")],
    workbook: book, history: (book.startChat, nil))
  try expectEqual(Set(ItemReferenceCandidates.historyIDs(in: ranked) ?? []), Set(noise.prefix(32)))
  // The compacted original sits in an older digest, before a newer packed
  // envelope containing more than 32 unrelated messages.
  let digest = try Value.object([
    "derivedNotes": .object([
      "notes": .array([
        .object([
          "kind": .string("fact"), "text": .string("Keep receipts."),
          "messages": .array([.string(said)]),
        ])
      ])
    ])
  ]).json()
  let compacted = try ItemReferenceCandidates.annotate(
    [
      InferenceMessage(role: "assistant", content: digest),
      InferenceMessage(role: "assistant", content: noise.joined(separator: "\n")),
    ],
    workbook: book, history: (book.startChat, nil))
  try expectEqual(ItemReferenceCandidates.historyIDs(in: compacted)?.contains(said), true)
  try expectEqual(compacted[0].content, digest)
  let annotated = try ItemReferenceCandidates.annotate([input], workbook: book)
  try expectEqual(
    try ItemReferenceCandidates.ids(in: annotated), [old.id, old.logicalID, current.id].sorted())
  try expectEqual(annotated[0].content, input.content)
  try expectEqual(annotated[0].reasoning, input.reasoning)
  try expectEqual(annotated[0].toolCalls[0].inputJSON, call.inputJSON)
  try expectEqual(annotated[0].toolCallId, input.toolCallId)
  try expectEqual(annotated[0].toolName, input.toolName)
  try expectEqual(annotated[0].nativeAppAuthoring, true)
  try expectEqual(try book.item(old.logicalID).id, current.id)
  try expectEqual(try book.item(old.id).id, old.id)
  // Original read routes can be stale after an explicit saved correction.
  // They do not add target lookup authority. Structural destinations, explicit
  // current-user links and earlier conversation keep their own semantics.
  let raw: Value = .object([
    "text": .string("[label](sevra://item/\(old.id))"),
    "foreign": .string("sevra://workbook/\(identifier())/item/\(old.id)"),
    "references": .object(["destination": .string(current.id)]),
  ])
  for tool in ["read", "tool_result"] {
    for content in [try raw.json(), try Value.object(["text": .string(raw.json())]).json()] {
      let message = InferenceMessage(role: "tool", content: content, toolName: tool)
      let choices = try ItemReferenceCandidates.annotate([message], workbook: book)
      try expectEqual(try ItemReferenceCandidates.ids(in: choices), [current.id])
      try expectEqual(choices[0].content, content)
    }
  }
  for message in [
    InferenceMessage(role: "user", content: "Inspect sevra://item/\(old.id)"),
    InferenceMessage(role: "tool", content: "Read exact item \(old.id)", toolName: "read"),
    InferenceMessage(
      role: "tool", content: "Earlier sevra://item/\(old.id)", toolName: "history_read"),
  ] {
    let choices = try ItemReferenceCandidates.annotate([message], workbook: book)
    try expectEqual(try ItemReferenceCandidates.ids(in: choices), [old.id])
  }
  // Rebuilt context must not inherit stale metadata, even if it was host-created.
  let rebuilt = try ItemReferenceCandidates.annotate(
    [
      InferenceMessage(
        role: "user", content: "Start a new exploration.",
        itemReferences: annotated[0].itemReferences)
    ], workbook: book)
  try expectEqual(try ItemReferenceCandidates.ids(in: rebuilt), [])
  let upper = try ItemReferenceCandidates.annotate(
    [
      InferenceMessage(role: "user", content: old.id.uppercased())
    ], workbook: book)
  // Exact SQLite lookup, no case repair.
  try expectEqual(try ItemReferenceCandidates.ids(in: upper), [])
  try expectEqual(try ItemReferenceCandidates.normalized([old.id, old.id]), [old.id])
  try expectThrows(try ItemReferenceCandidates.normalized(["not-an-id"]))
  let ids = (0..<257).map { String(format: "00000000-0000-4000-8000-%012x", $0) }
  try expectThrows(try ItemReferenceCandidates.normalized(ids))
  try expectThrows(
    try ItemReferenceCandidates.annotate(
      [
        InferenceMessage(
          role: "user",
          content: (0..<2049).map {
            String(format: "00000000-0000-4000-8000-%012x", $0)
          }.joined(separator: " "))
      ], workbook: book))
  for tool in ["read", "lineage", "references"] {
    try ItemReferenceCandidates.validate(
      tool: tool, arguments: .object(["id": .string(correctReference)]), choices: [correctReference]
    )
    try expectThrows(
      try ItemReferenceCandidates.validate(
        tool: tool, arguments: .object(["id": .string(failedReference)]),
        choices: [correctReference]))
  }
  // Discovery and conversation tools retain their own reference domains.
  try ItemReferenceCandidates.validate(
    tool: "history_read", arguments: .object(["id": .string(failedReference)]),
    choices: [correctReference])
  try ItemReferenceCandidates.validate(
    tool: "read", arguments: .object(["id": .string(failedReference)]), choices: [])
  let checks = ToolPolicyChecks()
  for scope in [InferenceToolScope.all, .inspection] {
    let policy = try NativeCitationPolicy.make(
      [], toolScope: scope, itemReferenceIDs: [correctReference])
    // An item, what it links to and what it came from are all read by the item's exact ID.
    for kind in [[], [("kind", "lineage")], [("kind", "references")]] {
      try policy.validate(
        checks.candidate("read", [("id", correctReference)] + kind, policy: policy))
      try expectThrows(
        try policy.validate(
          checks.candidate("read", [("id", failedReference)] + kind, policy: policy)))
    }
  }
  let uncited = try NativeCitationPolicy.make([], itemReferenceIDs: [correctReference])
  try expectThrows(
    try uncited.validate(
      checks.candidate(
        "finish",
        [
          ("answer", "An uninspected claim"), ("basis", "evidence"),
          ("citations", "[\"\(correctReference)\"]"),
        ], policy: uncited)))
  let before = try encoded(book.items())
  let model = ReferenceRefusalFixture(id: current.id, wrong: failedReference)
  let reply = try await WorkbookAgent.run(
    "Read this item: \(current.id). Make no changes.", workbook: book, model: model)
  try expectEqual(reply.steps, 3)
  try expectEqual(reply.citations, [current.id])
  let receipts = try book.messages(limit: 100).filter { $0.role == "tool" }.map {
    try book.toolCall(Value.parse($0.body)["receiptID"].text)
  }
  try expectEqual(receipts.count, 2)
  try expectEqual(receipts[0]["arguments"]["id"].text, failedReference)
  try expectEqual(receipts[0]["state"].text, "failed")
  try expectEqual(try encoded(book.items().filter { $0.kind != "request" }), before)
  try expectEqual(try book.verify()["ok"], .bool(true))
  print(
    "PASS exact item candidates, separate citation authority, context rebuild and shared refusal receipts"
  )
}

private actor ReferenceRefusalFixture: WorkbookInference {
  let identity = "synthetic reference refusal"
  let lastMetrics: Value = .null
  let id: String
  let wrong: String
  var step = 0
  init(id: String, wrong: String) {
    self.id = id
    self.wrong = wrong
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    step += 1
    try expectEqual(try ItemReferenceCandidates.ids(in: messages).contains(id), true)
    try expectEqual(citationIDs.contains(id), step == 3)
    if step == 2 {
      try expectEqual(messages.last!.content.contains("Choose the exact item ID"), true)
    }
    let args: Value =
      step == 3
      ? .object([
        "answer": .string("Delivery includes shipping."), "basis": .string("evidence"),
        "citations": .array([.string(id)]),
      ])
      : .object(["id": .string(step == 1 ? wrong : id)])
    return NativeReply(
      text: "",
      calls: [
        try .init(id: identifier(), operation: step == 3 ? "finish" : "read", args, scope: toolScope)
      ])
  }
}

func checkItemReferenceGrammar(frontend: SplashTextFrontend, factory: SplashGrammarFactory) throws {
  let many = (0..<256).map { String(format: "00000000-0000-4000-8000-%012x", $0) }
  let fullPolicy = try NativeCitationPolicy.make([], itemReferenceIDs: many)
  let full = try frontend.prepare(
    messages: [["role": "user", "content": "Inspect the item."]],
    tools: fullPolicy.promptTools(), thinking: false, contextLimit: 65536)
  try expectThrows(try ContextBudget().allowance(promptTokens: full.tokens.count))
  let definitions = try NativeTools.referenceDefinitions(itemReferenceIDs: many)
  try expectEqual(
    definitions.first { $0.name == "read" }!.parameters["anyOf"].array.first!["properties"]["id"][
      "enum"
    ].array.count, 256)
  for thinking in [false, true] {
    let policy = try NativeCitationPolicy.make(
      [], thinking: thinking, itemReferenceIDs: [correctReference])
    let base = try frontend.prepare(
      messages: [["role": "user", "content": "Inspect the item."]],
      tools: NativeCitationPolicy.make([], thinking: thinking).promptTools(), thinking: thinking,
      contextLimit: 65536)
    let bounded = try frontend.prepare(
      messages: [["role": "user", "content": "Inspect the item."]],
      tools: policy.promptTools(), thinking: thinking, contextLimit: 65536)
    // Exact IDs stay in the grammar/validator rather than invalidating the
    // reusable prompt prefix. One choice and 256 choices have the same prompt.
    try expectEqual(bounded.tokens, base.tokens)
    if !thinking { try expectEqual(full.tokens, bounded.tokens) }
    for kind in ["", "lineage", "references"] {
      func output(_ id: String) -> String {
        (thinking ? "Inspect the known reference.</think>\n" : "")
          + "<tool_call>\n<function=read>\n<parameter=id>\n\(id)\n</parameter>\n"
          + (kind.isEmpty ? "" : "<parameter=kind>\n\(kind)\n</parameter>\n")
          + "</function>\n</tool_call>"
      }
      let valid = try factory.create(grammar: policy.grammar)
      try valid.finish(committed: frontend.encode(output(correctReference)), requireComplete: true)
      let invalid = try factory.create(grammar: policy.grammar)
      try expectThrows(
        try invalid.finish(
          committed: frontend.encode(output(failedReference)), requireComplete: true))
    }
  }
  print(
    "PASS actual item-reference grammar rejects the recorded wrong suffix, with reasoning on/off and stable prompt tokens for 0/1/256 choices"
  )

  // A read names only what this context shows. On November 21, 2026 a new conversation's
  // "hi" read an earlier message by a made-up ID, which cost a whole extra decision.
  let said = "3f4423d0-b6c3-47be-a481-d93d320a4ec3"
  let invented = "3017abb1-7eed-46fd-a8b9-ec63f24c205d"
  func read(_ fields: [(String, String)]) -> String {
    "<tool_call>\n<function=read>\n"
      + fields.map { "<parameter=\($0.0)>\n\($0.1)\n</parameter>\n" }.joined()
      + "</function>\n</tool_call>"
  }
  func accepts(_ policy: SplashToolPolicy, _ output: String) throws -> Bool {
    let constraint = try factory.create(grammar: policy.grammar)
    do {
      try constraint.finish(committed: frontend.encode(output), requireComplete: true)
      return true
    } catch { return false }
  }
  let earlier = try NativeCitationPolicy.make([], historyReferenceIDs: [said])
  let fresh = try NativeCitationPolicy.make([], historyReferenceIDs: [])
  let known = try NativeCitationPolicy.make(
    [], itemReferenceIDs: [correctReference], historyReferenceIDs: [])
  let cases: [(String, SplashToolPolicy, [(String, String)], Bool)] = [
    ("a message this context shows", earlier, [("kind", "message"), ("ref", said)], true),
    ("a made-up message", earlier, [("kind", "message"), ("ref", invented)], false),
    ("any message in a new conversation", fresh, [("kind", "message"), ("ref", said)], false),
    ("an item before any is known", fresh, [("id", correctReference)], false),
    ("a known item", known, [("id", correctReference)], true),
    ("a known item's lineage", known, [("id", correctReference), ("kind", "lineage")], true),
    ("a made-up item", known, [("id", failedReference)], false),
    ("a saved result by ref", fresh, [("kind", "result"), ("ref", invented)], true),
    ("the actions list", fresh, [("kind", "actions")], true),
    ("a guide", fresh, [("kind", "view_guide")], true),
    ("a list with an item ID", fresh, [("id", correctReference), ("kind", "views")], false),
  ]
  for (name, policy, fields, expected) in cases {
    guard try accepts(policy, read(fields)) == expected else {
      throw SevraError(
        "read_grammar", "The read grammar " + (expected ? "refused " : "allowed ") + name + ".")
    }
  }
  // The prompt does not change with the choices, so the prepared header still applies.
  let shown = try NativeCitationPolicy.make([], display: true)
  try expectEqual(
    try NativeCitationPolicy.make([], historyReferenceIDs: [said], display: true).toolsJSON,
    shown.toolsJSON)
  print(
    "PASS read names only messages and items this context shows: \(cases.count) grammar cases and an unchanged prompt"
  )
}
