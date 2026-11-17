import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

/// A fresh model handles the same small question and exact chart at both context capacities.
@MainActor func runVisualJourneyProbe(
  modelsRoot: String, library: String, engine: String, output: String, large: Bool
) async throws {
  let directory = URL(fileURLWithPath: output)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  let book = try Workbook.create(
    at: directory.appendingPathComponent("Visual proof.sevra"),
    title: "Visual proof")
  let source = try book.addItem(category: "source", kind: "note", title: "Test sales")
  _ = try book.createDataset(
    title: "Sales",
    columns: [
      .init(id: "branch", title: "Branch"),
      .init(id: "sales", title: "Sales", type: "decimal", unit: "USD"),
    ],
    rows: [
      ["branch": .string("North"), "sales": .string("12.25")],
      ["branch": .string("South"), "sales": .string("8.50")],
      ["branch": .string("North"), "sales": .string("6.00")],
    ], sourceID: source.id)
  let model = NativeWorkbookModel(
    configuration: try nativeProbeConfiguration(
      library: library, engine: engine, modelsRoot: modelsRoot,
      budget: .init(profile: large ? .evaluation64K : .evaluation32K),
      reasoning: .bounded512, modelLayout: .installed))
  let began = Date()
  var results: [Value] = []
  func attempt(_ label: String, _ body: () async throws -> Void) async {
    do {
      try await body()
      results.append(.object(["case": .string(label), "passed": .bool(true)]))
      print("PASS " + label)
    } catch {
      results.append(
        .object([
          "case": .string(label), "passed": .bool(false),
          "error": .string(error.localizedDescription),
        ]))
      print("FAIL " + label + ": " + error.localizedDescription)
    }
  }
  func ask(_ prompt: String, answer: String? = nil) async throws {
    _ = try await WorkbookAgent.run(
      prompt, workbook: book,
      modelDirectory: URL(fileURLWithPath: modelsRoot),
      cancellation: .init(deadlineAfterSeconds: 140), model: model,
      enableCompaction: true, conversationInput: true, inputAnswerID: answer)
  }
  await attempt("Question and typed continuation") {
    try await ask(
      "In this chat, ask me whether to include shipping in the example margin. Put the choice in the chat. Wait for my answer before explaining the formula."
    )
    guard let question = try book.pendingConversationInput(conversation: "main"),
      let answer = try book.submitConversationInput(
        question, response: .text("Yes, include shipping."))
    else { throw SevraError("live_visual", "No actionable question or accepted answer was saved.") }
    try await ask("", answer: answer)
    try require(
      try book.pendingConversationInput(conversation: "main") == nil,
      "live_visual", "The answered question did not close.")
  }
  await attempt("Exact captured sales chart") {
    try await ask(
      "Show a bar chart right here in the answer of total sales in USD by branch from the Sales table. Keep the workbook data and Home layout unchanged."
    )
    let messages = try book.messages()
    var capture: VisualChartData?
    for message in messages.reversed() where message.role == "assistant" {
      if let visual = try? book.conversationVisual(message.id, index: 0, conversation: "main"),
        let data = visual.chartData
      {
        capture = data
        break
      }
    }
    try require(
      capture?.unit == "USD" && capture?.manifestID != nil
        && Dictionary(uniqueKeysWithValues: (capture?.points ?? []).map { ($0.label, $0.amount) })
          == ["North": "18.25", "South": "8.5"],
      "live_visual",
      "No saved chart with the exact independent totals and complete source manifest.")
  }
  let report: Value = .object([
    "context": .number(large ? 65536 : 32768), "results": .array(results),
    "seconds": .number(Date().timeIntervalSince(began)), "agentRuns": .array(try book.agentRuns()),
  ])
  try Data(report.json().utf8).write(to: directory.appendingPathComponent("results.json"))
  try require(
    results.allSatisfy { $0["passed"] == .bool(true) },
    "live_visual", "A live visual case failed. Inspect the retained workbook and report.")
}
