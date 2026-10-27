import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash

/// Autonomous cases: no supplied tool choice or injected finish. The hidden
/// movement's title/body deliberately omit the word used by a lexical query.
func runCoverageProbe(modelFolder: String, library: String, engine: String, modelsRoot: String)
  async throws
{
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-coverage-live-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  var passed = 0
  for reasoning in [NativeReasoning.off, .bounded512] {
    for name in ["accepted", "hidden", "empty"] {
      let book = try Workbook.openArchive(
        URL(fileURLWithPath: "integration/fixtures/reasoning/accepted.sevraz"),
        at: root.appendingPathComponent(name + "-" + String(reasoning.rawValue) + ".sevra"))
      if name == "hidden" {
        let source = try book.addItem(
          category: "source", kind: "note", title: "Handover", text: "Two units handed over.")
        _ = try book.addItem(
          category: "record", kind: "movement", title: "Dispatch", text: "Two units handed over.",
          status: "accepted", inputs: [source.id])
      }
      if name == "empty" {
        let file = root.appendingPathComponent("Unreadable.fixture")
        try Data([0, 1, 2]).write(to: file)
        _ = try book.importFile(file)
      }
      let prompt =
        name == "accepted"
        ? "I accepted the October forecast through the workbook. Inspect its current status and tell me whether it became an actual. Make no changes."
        : "How many current Records classified as movement does this workbook contain, across all statuses, meanings and scenarios? Report the exact scoped count and its limits. Make no changes."
      let before = try encoded(book.items().filter { $0.kind != "request" })
      let previousRuns = Set(try book.agentRuns().map { $0["id"].text })
      let model = NativeWorkbookModel(
        configuration: try nativeProbeConfiguration(
          library: library, engine: engine, modelsRoot: modelsRoot,
          budget: .init(profile: .evaluation32K), reasoning: reasoning))
      let start = Date()
      var outcome: [String: Value] = [
        "case": .string(name), "reasoning": .number(Double(reasoning.rawValue)),
        "prompt": .string(prompt),
      ]
      var good = false
      do {
        let result = try await WorkbookAgent.run(
          prompt, workbook: book, modelDirectory: URL(fileURLWithPath: modelFolder),
          progress: { fputs("Coverage \(name)/\(reasoning.rawValue): \($0)\n", stderr) },
          model: model)
        outcome["answer"] = .string(result.answer)
        outcome["steps"] = .number(Double(result.steps))
        let count = name == "hidden" ? "1" : "0"
        let semantic =
          name == "accepted"
          ? result.answer.localizedCaseInsensitiveContains("accepted")
            && result.answer.localizedCaseInsensitiveContains("estimate")
            && result.citations.contains("97ec6562-c4e4-4f4b-87bb-67e2ed0e92e8")
          : result.answer.contains(
            "Current workbook Records: " + count
              + " (kind: movement, status: any, meaning: any, scenario: any)")
            && result.answer.contains("documents may describe additional events")
        good = result.state == "complete" && semantic && !SearchCoverage.overstates(result.answer)
      } catch { outcome["error"] = .string(String(describing: error)) }
      let unchanged = try before == encoded(book.items().filter { $0.kind != "request" })
      let integrity = try book.verify()["ok"] == .bool(true)
      let unloaded = await model.unload()
      good = good && unchanged && integrity && unloaded
      if good { passed += 1 }
      outcome["passed"] = .bool(good)
      outcome["unchanged"] = .bool(unchanged)
      outcome["integrity"] = .bool(integrity)
      outcome["unloaded"] = .bool(unloaded)
      outcome["seconds"] = .number(Date().timeIntervalSince(start))
      let runID = try book.agentRuns().first { !previousRuns.contains($0["id"].text) }?["id"].text
      outcome["receipts"] = .array(
        try book.messages(limit: 100).compactMap { message in
          guard message.role == "tool", let receipt = try? Value.parse(message.body),
            runID != nil, receipt["runID"].text == runID
          else { return nil }
          return receipt
        })
      print(try Value.object(outcome).json())
      fflush(stdout)
    }
  }
  print("COVERAGE \(passed)/6")
  try expectEqual(passed, 6)
}
