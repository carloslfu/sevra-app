import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

func runWorkflowToolProbe(modelsRoot: String, library: String, engine: String, output: String)
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
    at: root.appendingPathComponent("Workflows.sevra"), title: "Synthetic workflows")
  let pure = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("function"), "title": .string("Count pairs"),
      "description": .string("Synthetic"),
      "parameters": .array([]), "payload": .object(["expression": .string("2")]),
    ]))
  var results: [Value] = []
  func record(_ name: String, _ result: AgentResult, _ started: Date) throws {
    results.append(
      .object([
        "name": .string(name), "answer": .string(result.answer), "state": .string(result.state),
        "steps": .number(Double(result.steps)),
        "seconds": .number(Date().timeIntervalSince(started)),
        "runs": .array(try book.agentRuns()), "activity": try book.workflowActivity(),
      ]))
    try Data(Value.array(results).json().utf8).write(
      to: root.appendingPathComponent("results.json"), options: .atomic)
    try Data(encoded(book.messages()).json().utf8).write(
      to: root.appendingPathComponent("messages.json"), options: .atomic)
  }
  do {
    var started = Date()
    let authored = try await WorkbookAgent.run(
      "Save a reusable manual workflow called Daily count. It has no parameters and exactly one evaluate step named count, calling our existing Count pairs function with no arguments. Bind its exact saved version. Do not start or execute it, and do not create business records.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("author-workflow", authored, started)
    let hits = try book.searchApplicationDefinitions("Daily count", kind: "workflow")["hits"].array
    try expectEqual(hits.count, 1)
    let workflow = try book.applicationDefinition(hits[0]["id"].text)
    let steps = workflow.content["payload"]["steps"].array
    try expectEqual(steps.count, 1)
    try expectEqual(steps[0]["binding"]["versionID"], .string(pure.id))
    try expectEqual(try book.workflowActivity()["runs"].array.isEmpty, true)
    print("PASS native workflow author exact reusable definition without execution")
    let originalHome = try book.spaces().first { $0.id == "home" }!
    started = Date()
    let form = try await WorkbookAgent.run(
      "Create a native form called Run count for our saved Daily count workflow, using its form template. Add it to existing Home, preserving every existing section. Do not start or execute anything.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("author-home-workflow-form", form, started)
    let forms = try book.searchApplicationDefinitions("Run count", kind: "form")["hits"].array
    try expectEqual(forms.count, 1)
    let savedForm = try book.applicationDefinition(forms[0]["id"].text)
    try expectEqual(
      savedForm.content["payload"]["workflow"]["logicalID"], .string(workflow.logicalID))
    let home = try book.spaces().first { $0.id == "home" }!
    for component in originalHome.definition.components {
      try expectEqual(
        try encoded(home.definition.components.first { $0.id == component.id }),
        try encoded(Optional(component)))
    }
    try expectEqual(
      home.definition.components.contains {
        $0.type == "form" && $0.definitionBinding?["logicalID"].text == savedForm.logicalID
      }, true)
    try expectEqual(try book.workflowActivity()["runs"].array.isEmpty, true)
    print("PASS native workflow form authoring on existing Home without starting")
    started = Date()
    let queued = try await WorkbookAgent.run(
      "Queue our saved Daily count workflow with no arguments. Do not execute any steps yet; I will use Continue in Activity.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("queue-workflow", queued, started)
    let runs = try book.workflowActivity()["runs"].array
    try expectEqual(runs.count, 1)
    try expectEqual(runs[0]["state"], .string("queued"))
    try expectEqual(queued.focus?.kind, "workflow")
    try expectEqual(queued.answer.contains("without executing steps or preparing proposals"), true)
    try expectEqual(
      try book.workflowRun(runs[0]["id"].text)["steps"].array.allSatisfy {
        $0["state"] == .string("pending")
      }, true)
    try expectEqual(try book.items().filter { $0.category == "record" }.isEmpty, true)
    try expectEqual(try book.verify()["ok"], .bool(true))
    print("PASS native workflow queue with truthful host-owned outcome and no execution")
    _ = await model.unload()
  } catch {
    try? Data(encoded(book.messages()).json().utf8).write(
      to: root.appendingPathComponent("messages-failure.json"), options: .atomic)
    _ = await model.unload()
    throw error
  }
}
