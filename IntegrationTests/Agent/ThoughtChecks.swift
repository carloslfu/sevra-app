import Foundation
import SevraAI
import SevraCore

/// Thinks before every call and keeps each prompt it was given.
private actor ThinkingModel: WorkbookInference {
  let identity = "synthetic thinking model"
  let lastMetrics: Value = .null
  private var steps: [(thought: String, tool: String, arguments: Value)]
  private(set) var prompts: [[InferenceMessage]] = []
  init(_ steps: [(thought: String, tool: String, arguments: Value)]) { self.steps = steps }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    prompts.append(messages)
    guard !steps.isEmpty else { throw SevraError("fixture", "The thinking script ran out.") }
    let step = steps.removeFirst()
    if step.tool == "none" { return .init(text: "", calls: [], reasoning: step.thought) }
    return .init(
      text: "",
      calls: [try .init(id: identifier(), operation: step.tool, step.arguments, scope: toolScope)],
      reasoning: step.thought)
  }
}

private final class PreviewLog: @unchecked Sendable {
  private let lock = NSLock()
  private var updates: [AnswerPreview] = []
  func add(_ update: AnswerPreview) { lock.withLock { updates.append(update) } }
  var last: AnswerPreview? { lock.withLock { updates.last } }
}

/// The model's thoughts are saved with each run for the person to read, in the order the
/// calls ran, with the calls Sevra sent back. No later request shows them to the model.
func checkVisibleThoughts() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-thoughts-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root.appendingPathComponent("Thoughts.sevra"), title: "T")
  let chat = book.startChat
  let marks = ["MARK-SEARCH", "MARK-NOCALL", "MARK-DOLLAR", "MARK-ANSWER"]
  let model = ThinkingModel([
    (marks[0] + " I should search first.", "search", .object(["query": .string("greeting")])),
    (marks[1] + " I forgot to call a tool.", "none", .null),
    (
      marks[2] + " Answer with a price.", "finish",
      .object([
        "answer": .string("Hello for $5."), "basis": .string("general"),
        "citations": .array([]),
      ])
    ),
    (
      marks[3] + " Answer without a currency.", "finish",
      .object([
        "answer": .string("Hello."), "basis": .string("general"), "citations": .array([]),
      ])
    ),
  ])
  let previews = PreviewLog()
  let first = try await WorkbookAgent.run(
    "Say hello.", workbook: book, conversation: chat,
    answerPreview: { previews.add($0) }, model: model, conversationInput: true)
  try expectEqual(first.state, "complete")
  let request = try book.messages(conversation: chat).first { $0.role == "user" }!
  let activity = try book.requestActivities(messageIDs: [request.id], conversation: chat)[0]
  let thoughts = try book.runThoughts(activity.id, conversation: chat)
  try expectEqual(thoughts.map(\.step), [1, 2, 3, 4])
  try expectEqual(thoughts.map { $0.text.components(separatedBy: " ")[0] }, marks)
  try expectEqual(thoughts.map(\.outcome), [nil, "unusable", "answer_refused", nil])
  try expectEqual(thoughts[2].draft, "Hello for $5.")
  try expectEqual(thoughts[2].note?.contains("currency"), true)
  try expectEqual(thoughts[1].note?.contains("Use exactly one"), true)
  // Each thought comes before the step it led to; the unmatched ones keep their place.
  let order = RequestActivity.timeline(steps: activity.steps, thoughts: thoughts).map(\.id)
  try expectEqual(order.count, 5)
  try expectEqual(order[0], "thought-1")
  try expectEqual(order[1], "step-" + activity.steps[0].id)
  try expectEqual(Array(order[2...]), ["thought-2", "thought-3", "thought-4"])
  // The window received the same thoughts while the run lasted.
  try expectEqual(previews.last?.thoughts.map(\.step), [1, 2, 3, 4])
  try expectEqual(previews.last?.reasoning, nil)
  // A step the host took on its own stays ahead of the next thought.
  let host = ToolActivityProbe.step(callID: "host-made")
  let withHost = RequestActivity.timeline(
    steps: [activity.steps[0], host], thoughts: [thoughts[0], thoughts[3]]
  ).map(\.id)
  try expectEqual(
    withHost, ["thought-1", "step-" + activity.steps[0].id, "step-" + host.id, "thought-4"])
  // A call without reasoning shows only its step, still ahead of a later sent-back answer.
  let quiet = ToolActivityProbe.step(callID: "quiet")
  let marker = ActivityThought(step: 1, callID: "quiet", tool: "search", text: "")
  let refused = ActivityThought(step: 2, text: "", outcome: "answer_refused", note: "No.")
  try expectEqual(
    RequestActivity.timeline(steps: [quiet], thoughts: [refused, marker]).map(\.id),
    ["step-" + quiet.id, "thought-2"])

  // The counterexample: a follow-up never shows the model an earlier thought.
  let followUp = ThinkingModel([
    (
      "Plain answer.", "finish",
      .object([
        "answer": .string("Hello again."), "basis": .string("general"),
        "citations": .array([]),
      ])
    )
  ])
  _ = try await WorkbookAgent.run(
    "Say it again.", workbook: book, conversation: chat, model: followUp,
    conversationInput: true)
  let seen = await followUp.prompts.flatMap { $0 }.map { $0.content + $0.reasoning }
    .joined(separator: "\n")
  for mark in marks where seen.contains(mark) {
    throw SevraError("thought_check", "A saved thought reached the model: " + mark)
  }
  print("PASS visible thoughts: saved in order, sent-back calls, live delivery, never re-read")
}

/// A completed step that no thought names, as the host makes on its own.
enum ToolActivityProbe {
  static func step(callID: String) -> ToolActivity {
    ToolActivity(
      id: "host-" + callID, callID: callID, tool: "search", state: "completed",
      arguments: .object([:]), result: nil)
  }
}
