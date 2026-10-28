import Foundation
import SevraAI
import SevraBaseline
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
  let input = InferenceMessage(
    role: "tool",
    content:
      "Untrusted text: \(old.id), \(old.logicalID), \(current.id). Invalid \(failedReference)",
    toolCalls: [call], toolCallId: "test", toolName: "read", reasoning: "Keep intermediate state.",
    itemReferences: [correctReference])
  let annotated = try ItemReferenceCandidates.annotate([input], workbook: book)
  try expectEqual(
    try ItemReferenceCandidates.ids(in: annotated), [old.id, old.logicalID, current.id].sorted())
  try expectEqual(annotated[0].content, input.content)
  try expectEqual(annotated[0].reasoning, input.reasoning)
  try expectEqual(annotated[0].toolCalls[0].inputJSON, call.inputJSON)
  try expectEqual(annotated[0].toolCallId, input.toolCallId)
  try expectEqual(annotated[0].toolName, input.toolName)
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
    for tool in ["read", "lineage", "references"] {
      try policy.validate(checks.candidate(tool, [("id", correctReference)], policy: policy))
      try expectThrows(
        try policy.validate(checks.candidate(tool, [("id", failedReference)], policy: policy)))
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
  let baseline = try LocalModel.baselineDefinitions(itemReferenceIDs: [correctReference])
  let native = try NativeTools.referenceDefinitions(itemReferenceIDs: [correctReference])
  try expectEqual(baseline.count, native.count)
  for name in ["read", "lineage", "references"] {
    let parameters = try Value.parse(baseline.first { $0.name == name }!.parameters.jsonText)
    try expectEqual(parameters, native.first { $0.name == name }!.parameters)
  }
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
    "PASS exact item candidates, separate citation authority, context rebuild, shared refusal receipts and baseline/native schema parity"
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
        .init(id: identifier(), name: step == 3 ? "finish" : "read", inputJSON: try args.json())
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
    definitions.first { $0.name == "read" }!.parameters["properties"]["id"]["enum"].array.count, 256
  )
  for thinking in [false, true] {
    let policy = try NativeCitationPolicy.make(
      [], thinking: thinking, itemReferenceIDs: [correctReference])
    let base = try frontend.prepare(
      messages: [["role": "user", "content": "Inspect the item."]],
      tools: NativeCitationPolicy.make([], thinking: thinking).promptTools(), thinking: thinking)
    let bounded = try frontend.prepare(
      messages: [["role": "user", "content": "Inspect the item."]],
      tools: policy.promptTools(), thinking: thinking)
    try expectEqual(bounded.tokens.count > base.tokens.count, true)
    for tool in ["read", "lineage", "references"] {
      func output(_ id: String) -> String {
        (thinking ? "Inspect the known reference.</think>\n" : "")
          + "<tool_call>\n<function=\(tool)>\n<parameter=id>\n\(id)\n</parameter>\n</function>\n</tool_call>"
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
    "PASS actual item-reference grammar rejects the recorded wrong suffix, with reasoning on/off and measured schema overhead"
  )
}
