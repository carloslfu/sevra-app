import Foundation
import SevraAI
import SevraCore

private actor SpaceActionModel: WorkbookInference {
  let identity = "synthetic space actions"
  let lastMetrics: Value = .object(["fixture": .bool(true)])
  let actions: [(String, Value)]
  var calls = 0
  init(_ actions: [(String, Value)]) { self.actions = actions }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    let index = calls
    calls += 1
    if index < actions.count {
      return .init(
        text: "",
        calls: [
          .init(
            id: "space-\(index)", name: actions[index].0, inputJSON: try actions[index].1.json())
        ])
    }
    let refused = messages.last?.content.contains("error") == true
    return .init(
      text: "",
      calls: [
        .init(
          id: "finish", name: "finish",
          inputJSON: try Value.object([
            "answer": .string(
              refused ? "No shortcut was changed." : "The requested actions are complete."),
            "basis": .string(refused ? "general" : "completed_action"), "citations": .array([]),
          ]).json())
      ])
  }
}

@MainActor func checkSpaceActions() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-space-actions-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root, title: "Space actions")
  let id = try book.saveSpace(title: "Purchasing", definition: .init(components: []))
  let definitions = try encoded(book.spaces())
  let target: Value = .object(["target": .string("Purchasing")])
  let pin: Value = .object(["target": .string("Purchasing"), "pinned": .bool(true)])
  let unpin: Value = .object(["target": .string("Purchasing"), "pinned": .bool(false)])
  var opened: [String] = []
  let model = SpaceActionModel([
    ("set_space_pinned", pin), ("open_space", target),
    ("calculate", .object(["expression": .string("9-2")])),
  ])
  _ = try await WorkbookAgent.run(
    "Pin Purchasing, open it and calculate 9 minus 2.", workbook: book, model: model,
    openSpace: { opened.append($0.id) })
  try expectEqual(opened, [id])
  try expectEqual(await model.calls, 4)
  try expectEqual(try book.workspaceSnapshot(conversation: "main")!.spaceNavigation.pinned, [id])
  try expectEqual(try encoded(book.spaces()), definitions)
  let ordered = try await WorkbookAgent.run(
    "Save a space called Overview, then open Purchasing.", workbook: book,
    model: SpaceActionModel([
      (
        "save_space",
        .object([
          "title": .string("Overview"),
          "definition": .object([
            "version": .number(1), "components": .array([]),
          ]),
        ])
      ), ("open_space", target),
    ]), openSpace: { opened.append($0.id) })
  try expectEqual(ordered.focus == nil, true)
  try expectEqual(opened.last, id)
  try expectEqual(try book.spaceTarget("Overview").title, "Overview")
  let receipts = try book.agentRuns()
  try expectEqual(receipts.last?["status"].text, "complete")
  _ = try await WorkbookAgent.run(
    "Unpin Purchasing.", workbook: book, model: SpaceActionModel([("set_space_pinned", unpin)]))
  try expectEqual(try book.workspaceSnapshot(conversation: "main")!.spaceNavigation.pinned, [])
  _ = try await WorkbookAgent.run(
    "Explain only.", workbook: book, model: SpaceActionModel([("set_space_pinned", pin)]))
  try expectEqual(try book.workspaceSnapshot(conversation: "main")!.spaceNavigation.pinned, [])

  for unavailable in [true, false] {
    let probe = SpaceActionModel([("open_space", target)])
    var opener: SpaceOpener?
    if !unavailable {
      opener = { _ in
        throw SevraError("workspace_changed", "You moved elsewhere. No space was opened.")
      }
    }
    let result = try await WorkbookAgent.run(
      "Take me to Purchasing.", workbook: book, model: probe, openSpace: opener)
    try expectEqual(await probe.calls, 1)
    try expectEqual(
      result.answer.contains("No space was opened") || result.answer.contains("No view was opened"),
      true)
    try expectEqual(result.focus == nil, true)
  }
  _ = try book.saveSpace(title: "Purchasing", definition: .init(components: []))
  let ambiguous = SpaceActionModel([("set_space_pinned", pin)])
  let clarification = try await WorkbookAgent.run(
    "Pin Purchasing.", workbook: book, model: ambiguous)
  try expectEqual(await ambiguous.calls, 1)
  try expectEqual(clarification.answer.contains("More than one space"), true)
  try expectEqual(try book.workspaceSnapshot(conversation: "main")!.spaceNavigation.pinned, [])
  try expectEqual(try book.spaceTarget(id).id, id)
  try expectThrows(try book.spaceTarget("Purch"))
  try expectEqual(
    try WorkbookTools(book).execute("open_space", .object(["target": .string(id)]))["status"].text,
    "resolved")
  try expectThrows(try WorkbookTools(book, readOnly: true).execute("open_space", target))
  try expectEqual(try book.verify()["ok"], .bool(true))
  print(
    "PASS scoped space opening, compound continuation, shortcut/snapshot separation, read-only denial and terminal ambiguity/window refusal"
  )
}
