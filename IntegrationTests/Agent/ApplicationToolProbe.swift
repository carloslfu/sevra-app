import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

func runApplicationToolProbe(modelsRoot: String, library: String, engine: String, output: String)
  async throws
{
  let root = URL(fileURLWithPath: output)
  try require(
    !FileManager.default.fileExists(atPath: root.path), "fixture", "Use a new output directory.")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  let model = NativeWorkbookModel(
    configuration: try nativeProbeConfiguration(
      library: library, engine: engine, modelsRoot: modelsRoot,
      budget: .init(profile: .evaluation32K), reasoning: .bounded512, modelLayout: .installed))
  let book = try Workbook.create(
    at: root.appendingPathComponent("Applications.sevra"), title: "Synthetic shop")
  var results: [Value] = []
  func record(_ name: String, result: AgentResult, started: Date) throws {
    results.append(
      .object([
        "name": .string(name), "answer": .string(result.answer), "state": .string(result.state),
        "steps": .number(Double(result.steps)),
        "seconds": .number(Date().timeIntervalSince(started)),
        "runs": .array(try book.agentRuns()),
      ]))
    try Data(Value.array(results).json().utf8).write(
      to: root.appendingPathComponent("results.json"), options: .atomic)
    try Data(encoded(book.messages()).json().utf8).write(
      to: root.appendingPathComponent("messages.json"), options: .atomic)
  }
  do {
    var started = Date()
    let author = try await WorkbookAgent.run(
      "Create a reusable calculation called Case units. It takes a required decimal parameter called cases, in cases, and multiplies it by 12. Its output unit is items. Save this calculation for reuse; do not create a business proposal or run it yet.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("author-function", result: author, started: started)
    let functions = try book.searchApplicationDefinitions("Case units", kind: "function")["hits"]
      .array
    try expectEqual(functions.count, 1)
    let function = try book.applicationDefinition(functions[0]["id"].text)
    try expectEqual(
      try book.evaluateApplicationDefinition(
        function.id, arguments: .object(["cases": .string("3")]))["result"], .string("36"))
    print("PASS native application author-function")
    started = Date()
    let calculated = try await WorkbookAgent.run(
      "Use the saved Case units calculation for 3 cases. Tell me its result in items without changing business data.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("evaluate-function", result: calculated, started: started)
    try expectEqual(calculated.answer.contains("36"), true)
    let tools = try book.messages().filter { $0.role == "tool" }.map { try Value.parse($0.body) }
    try expectEqual(
      tools.contains {
        $0["tool"].text == "evaluate_definition" && $0["result"]["result"] == .string("36")
      }, true)
    print("PASS native application evaluate-function")
    let previousHome = try book.spaces().first { $0.id == "home" }!.definition.components
    started = Date()
    let formResult = try await WorkbookAgent.run(
      "Create a reusable receiving action and its native form, named Goods in, using the registered receiving starter. Add that saved form to our existing Home. Keep all existing Home sections. Do not prepare inventory proposals yet.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("author-home-form", result: formResult, started: started)
    let forms = try book.searchApplicationDefinitions("Goods in", kind: "form")["hits"].array
    try expectEqual(forms.count, 1)
    let form = try book.applicationDefinition(forms[0]["id"].text)
    let home = try book.spaces().first { $0.id == "home" }!
    let hasForm = home.definition.components.contains { component in
      component.type == "form"
        && (component.definitionBinding?["logicalID"].text == form.logicalID
          || component.definitionBinding?["versionID"].text == form.id)
    }
    try expectEqual(hasForm, true)
    for component in previousHome {
      try expectEqual(home.definition.components.first { $0.id == component.id }, component)
    }
    print("PASS native application author-home-form")
    _ = try book.addItem(
      category: "source", kind: "observation", title: "Receipt R-2026",
      text:
        "SYNTHETIC RECEIPT R-2026\nDate 2026-10-28\nWe received 3 bolts and 2 nuts into our stock.\nLine 1: bolts, 3 items\nLine 2: nuts, 2 items\nDelivery identity R-2026. No acceptance yet."
    )
    started = Date()
    let submitted = try await WorkbookAgent.run(
      "Use our saved Goods in form to prepare the inventory proposals from Receipt R-2026 for my review. Use its delivery identity, date and line numbers. Do not accept anything.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("submit-saved-form", result: submitted, started: started)
    try expectEqual(submitted.state, "needs_review")
    let movements = try book.items(kind: "movement")
    try expectEqual(movements.count, 2)
    try expectEqual(movements.allSatisfy { $0.status == "draft" && $0.meaning == "actual" }, true)
    try expectEqual(Set(movements.map { $0.data["subject"].text }), ["bolts", "nuts"])
    for movement in movements {
      try expectEqual(
        movement.data["quantity"], .string(movement.data["subject"].text == "bolts" ? "3" : "2"))
      try expectEqual(movement.data["effective"], .string("2026-10-28T00:00:00.000Z"))
    }
    try expectEqual(try book.items(kind: "application_invocation").count, 1)
    print("PASS native application submit-saved-form")
    _ = try book.addItem(
      category: "source", kind: "observation", title: "Receipt R-2027",
      text:
        "SYNTHETIC RECEIPT R-2027\nDate 2026-10-28\n4 washers handed over.\nLine 1: washers, 4 items\nDelivery identity R-2027. No sender or receiver identified."
    )
    started = Date()
    let unclear = try await WorkbookAgent.run(
      "Use Goods in to prepare Receipt R-2027 for review, using the receipt's date and line number. Do not accept anything.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("ambiguous-direction", result: unclear, started: started)
    try expectEqual(try book.items(kind: "movement").count, 2)
    try expectEqual(try book.items(kind: "application_invocation").count, 1)
    try expectEqual(unclear.state, "complete")
    let clarification = unclear.answer.lowercased()
    try expectEqual(
      ["receiv", "incoming", "outgoing", "into", "from", "direction", "stock"].contains {
        clarification.contains($0)
      }, true)
    print("PASS native application ambiguous-direction preserves original proposals")
    try expectEqual(try book.verify()["ok"], .bool(true))
    _ = await model.unload()
  } catch {
    try? Data(encoded(book.messages()).json().utf8).write(
      to: root.appendingPathComponent("messages-failure.json"), options: .atomic)
    _ = await model.unload()
    throw error
  }
}
