import Foundation
import SevraAI
@testable import SevraCore

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
  var reviewOpenings = 0
  let reviews = SpaceActionModel([("open_reviews", .object([:]))])
  let shown = try await WorkbookAgent.run(
    "Show my pending drafts.", workbook: book, model: reviews,
    openReviews: { reviewOpenings += 1 })
  try expectEqual(reviewOpenings, 1)
  try expectEqual(shown.steps, 2)
  let unavailableReviews = SpaceActionModel([("open_reviews", .object([:]))])
  let refusedReviews = try await WorkbookAgent.run(
    "Show my pending drafts.", workbook: book,
    model: unavailableReviews)
  try expectEqual(await unavailableReviews.calls, 1)
  try expectEqual(refusedReviews.answer.contains("No view was opened"), true)
  try expectThrows(try WorkbookTools(book, readOnly: true).execute("open_reviews", .object([:])))

  // Asking for an automation reaches its native review. It enables nothing, and only an exact
  // name gets there.
  func automation(_ title: String) throws -> ApplicationDefinition {
    let function = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("function"), "title": .string(title + " rule"),
        "description": .string("Synthetic"), "parameters": .array([]),
        "payload": .object(["expression": .string("2*2"), "unit": .string("items")]),
      ]))
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(), content: book.workflowTemplate(function.id))
    return try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("automation"), "title": .string(title),
        "description": .string("Synthetic"), "parameters": .array([]),
        "payload": .object([
          "policy": .string("calendar-drafts-v1"),
          "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow.id)]),
          "arguments": .object([:]),
          "schedule": .object([
            "policy": .string("native-calendar-v1"), "timeZone": .string("America/Bogota"),
            "hour": .number(9), "minute": .number(0),
            "recurrence": .object(["kind": .string("weekly"), "weekdays": .array([.number(1)])]),
          ]),
        ]),
      ]))
  }
  let weekly = try automation("Weekly stock check")
  func opening(_ target: String, window: Bool = true) async throws -> AgentResult {
    try await WorkbookAgent.run(
      "Enable " + target, workbook: book,
      model: SpaceActionModel([("open_automation", .object(["target": .string(target)]))]),
      openSpace: window ? { _ in } : nil)
  }
  let reviewed = try await opening("weekly STOCK check")
  try expectEqual(reviewed.focus?.kind, "automation")
  try expectEqual(reviewed.focus?.id, weekly.id)
  try expectEqual(reviewed.steps, 1)
  try expectEqual(reviewed.answer.contains("Nothing was enabled"), true)
  _ = try automation("Stock [check](https://example.com)")
  let linked = try await opening("Stock [check](https://example.com)")
  try expectEqual(linked.answer.hasPrefix("Review “Stock \\[check\\](https://example.com)”"), true)
  let noWindow = try await opening("Weekly stock check", window: false)
  try expectEqual(noWindow.answer.contains("No view was opened"), true)
  try expectEqual(noWindow.focus == nil, true)
  let unknown = try await opening("Weekly stock")
  try expectEqual(unknown.answer.contains("No saved automation has that exact name"), true)
  try expectEqual(unknown.focus == nil, true)
  _ = try automation("Weekly stock check")
  let twoNamed = try await opening("Weekly stock check")
  try expectEqual(twoNamed.answer.contains("More than one automation"), true)
  try expectEqual(twoNamed.focus == nil, true)

  // A plain request for a draft gets one correction if the model only answers in chat.
  try expectEqual(DraftRequest.asks("Draft a brief summary of the report."), true)
  try expectEqual(DraftRequest.asks("Please write me a short draft of it."), true)
  try expectEqual(DraftRequest.asks("Redacta un borrador breve en español."), true)
  try expectEqual(DraftRequest.asks("What does the draft say?"), false)
  try expectEqual(DraftRequest.asks("Can you write a short draft of it?"), true)
  try expectEqual(DraftRequest.asks("Should I make a draft order for Brio or wait for tax terms?"), false)
  try expectEqual(DraftRequest.asks("Did you make a draft yet?"), false)
  try expectEqual(DraftRequest.asks("How do I create a draft?"), false)
  try expectEqual(DraftRequest.asks("¿Cómo hago un borrador?"), false)
  try expectEqual(DraftRequest.asks("Show my pending drafts."), false)
  let chatAnswer: Value = .object([
    "answer": .string("Here it is in chat."), "basis": .string("general"),
    "citations": .array([]),
  ])
  let corrected = SpaceActionModel([
    ("finish", chatAnswer),
    (
      "draft",
      .object(["title": .string("Note"), "text": .string("New words."), "inputs": .array([])])
    ),
  ])
  let drafting = try Workbook.create(
    at: FileManager.default.temporaryDirectory.appendingPathComponent(identifier() + ".sevra"),
    title: "Drafts")
  defer { try? FileManager.default.removeItem(at: drafting.url) }
  let saved = try await WorkbookAgent.run(
    "Draft a short note about delivery.", workbook: drafting, model: corrected)
  try expectEqual(saved.state, "complete")
  try expectEqual(await corrected.calls, 3)
  try expectEqual(try drafting.items(kind: "document").contains { $0.title == "Note" }, true)
  // A second answer ends the run, so a false alarm can never trap it.
  let answeredTwice = SpaceActionModel([("finish", chatAnswer), ("finish", chatAnswer)])
  let notDraft = try await WorkbookAgent.run(
    "Draft dates are in the report, right?", workbook: drafting, model: answeredTwice)
  try expectEqual(notDraft.state, "complete")
  try expectEqual(await answeredTwice.calls, 2)
  let readQueue = try WorkbookTools(book, readOnly: true).execute("review_queue", .object([:]))
  try expectEqual(readQueue["items"].array.isEmpty, true)
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
