import CryptoKit
import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

func runInterpretationAuthoringProbe(
  modelsRoot: String, library: String, engine: String, output: String
) async throws {
  let root = URL(fileURLWithPath: output)
  try require(
    !FileManager.default.fileExists(atPath: root.path), "fixture", "Use a new output directory.")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  let trace = InterpretationProbeTrace(root)
  let base = try nativeProbeConfiguration(
    library: library, engine: engine, modelsRoot: modelsRoot,
    budget: .init(profile: .evaluation32K), reasoning: .bounded512, modelLayout: .installed)
  let model = NativeWorkbookModel(
    configuration: .init(
      engine: base.engine, engineFiles: base.engineFiles, grammarLibrary: base.grammarLibrary,
      grammarSHA256: base.grammarSHA256, modelsRoot: base.modelsRoot, memoryBytes: base.memoryBytes,
      contextBudget: base.contextBudget, reasoning: base.reasoning, modelLayout: base.modelLayout,
      observeRequest: { trace.write($0) }))
  func digest(_ path: String) throws -> Value {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return .object([
      "path": .string(path), "bytes": .number(Double(data.count)),
      "sha256": .string(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()),
    ])
  }
  let identity: Value = .object([
    "model": .string(await model.identity), "runner": try digest(CommandLine.arguments[0]),
    "recordedUTC": .string(ISO8601DateFormatter().string(from: Date())),
    "sources": .array(
      try [
        "Sources/SevraCore/DefinitionTools.swift", "Sources/SevraAI/NativeApplicationTools.swift",
        "Sources/SevraAI/WorkbookAgent.swift", "Sources/SevraCore/DefinitionInterpretation.swift",
        "Sources/SevraCore/ApplicationDefinition.swift",
        "Sources/SevraCore/WorkflowDefinition.swift",
        "Sources/SevraCore/Tools.swift", "Sources/SevraAI/ActionConfirmations.swift",
        "IntegrationTests/Agent/InterpretationAuthoringProbe.swift",
      ].map(digest)),
  ])
  try Data(identity.json().utf8).write(
    to: root.appendingPathComponent("identity.json"), options: .atomic)
  let book = try Workbook.create(
    at: root.appendingPathComponent("Authored.sevra"), title: "Synthetic interpretation authoring")
  let source = try book.addItem(
    category: "source", kind: "observation", title: "Delivery receipt",
    text: "On October28,2026, we received exactly5 bolts into our inventory.")
  var results: [Value] = []
  func record(_ name: String, _ result: AgentResult, _ started: Date) throws {
    results.append(
      .object([
        "name": .string(name), "answer": .string(result.answer), "state": .string(result.state),
        "steps": .number(Double(result.steps)),
        "seconds": .number(Date().timeIntervalSince(started)), "runs": .array(try book.agentRuns()),
        "activity": try book.workflowActivity(),
      ]))
    try Data(Value.array(results).json().utf8).write(
      to: root.appendingPathComponent("results.json"), options: .atomic)
    try Data(encoded(book.messages()).json().utf8).write(
      to: root.appendingPathComponent("messages.json"), options: .atomic)
  }
  do {
    var started = Date()
    let authored = try await WorkbookAgent.run(
      "Save reusable interpretation behavior called Read received count. It takes one required evidence item input named evidence and extracts the number of bolts actually received. Its one required output is quantity, a decimal count in items. Meaning and scenario are actual. If missing or ambiguous, it must ask rather than invent or default a quantity. Save the behavior only. Do not run a model step, create a business Record, queue work or approve anything.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("author-interpretation", authored, started)
    try expectEqual(authored.state, "complete")
    let hits = try book.searchApplicationDefinitions(
      "Read received count", kind: "interpretation")["hits"].array
    try expectEqual(hits.count, 1)
    let definition = try book.applicationDefinition(hits[0]["id"].text)
    try expectEqual(definition.content["parameters"].array.count, 1)
    try expectEqual(definition.content["parameters"].array[0]["id"], .string("evidence"))
    let output = definition.content["payload"]["outputs"].array
    try expectEqual(output.count, 1)
    try expectEqual(output[0]["id"], .string("quantity"))
    try expectEqual(output[0]["type"], .string("decimal"))
    try expectEqual(output[0]["unit"], .string("items"))
    try expectEqual(try book.items().filter { $0.category == "record" }.isEmpty, true)
    try expectEqual(try book.workflowActivity()["runs"].array.isEmpty, true)
    print("PASS native conversation authors reusable interpretation without execution")
    started = Date()
    let composed = try await WorkbookAgent.run(
      "Save a manual workflow called Read delivery. It takes the required evidence item input named evidence and has exactly one interpret step named read using the exact saved Read received count interpretation. Do not start it, execute it or create business Records.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("author-interpretation-workflow", composed, started)
    try expectEqual(composed.state, "complete")
    let workflows = try book.searchApplicationDefinitions("Read delivery", kind: "workflow")["hits"]
      .array
    try expectEqual(workflows.count, 1)
    let workflow = try book.applicationDefinition(workflows[0]["id"].text)
    let steps = workflow.content["payload"]["steps"].array
    try expectEqual(steps.count, 1)
    try expectEqual(steps[0]["kind"], .string("interpret"))
    try expectEqual(steps[0]["binding"]["versionID"], .string(definition.id))
    try expectEqual(try book.workflowActivity()["runs"].array.isEmpty, true)
    print("PASS native conversation composes exact interpretation workflow without starting")
    started = Date()
    let queued = try await WorkbookAgent.run(
      "Queue our saved Read delivery workflow for the Delivery receipt evidence item. Do not execute any steps yet. I will use Continue in Activity.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("queue-interpretation-workflow", queued, started)
    try expectEqual(queued.state, "complete")
    let activity = try book.workflowActivity()["runs"].array
    try expectEqual(activity.count, 1)
    let run = try book.workflowRun(activity[0]["id"].text)
    try expectEqual(run["state"], .string("queued"))
    try expectEqual(run["arguments"]["evidence"], .string(source.id))
    try expectEqual(run["steps"].array[0]["state"], .string("pending"))
    try expectEqual(queued.answer.contains("without executing steps or preparing proposals"), true)
    try expectEqual(try book.items().filter { $0.category == "record" }.isEmpty, true)
    try expectEqual(try book.verify()["ok"], .bool(true))
    let copy = try book.reconstruct(to: root.appendingPathComponent("AuthoredCopy.sevra"))
    try expectEqual(try copy.workflowRun(run["id"].text), run)
    try expectEqual(try copy.verify()["ok"], .bool(true))
    print(
      "PASS native conversation queues authored interpretation with truthful no-execution receipt")
    _ = await model.unload()
  } catch {
    try? Data(encoded(book.messages()).json().utf8).write(
      to: root.appendingPathComponent("messages-failure.json"), options: .atomic)
    _ = await model.unload()
    throw error
  }
}
