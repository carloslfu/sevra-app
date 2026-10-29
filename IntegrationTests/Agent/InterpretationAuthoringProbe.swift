import CryptoKit
import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

func runInterpretationAuthoringProbe(
  modelsRoot: String, library: String, engine: String, output: String, preparation: Bool = false
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
        "Sources/SevraCore/DefinitionExtraction.swift",
        "Sources/SevraAI/WorkbookAgent.swift", "Sources/SevraCore/DefinitionInterpretation.swift",
        "Sources/SevraCore/ApplicationDefinition.swift",
        "Sources/SevraCore/WorkflowDefinition.swift",
        "Sources/SevraCore/Tools.swift", "Sources/SevraAI/ActionConfirmations.swift",
        "IntegrationTests/Agent/InterpretationAuthoringProbe.swift",
      ].map(digest)),
  ])
  try Data(identity.json().utf8).write(
    to: root.appendingPathComponent("identity.json"), options: .atomic)
  let kind = preparation ? "extraction" : "interpretation"
  let behaviorTitle = preparation ? "Prepare receipt" : "Read received count"
  let workflowTitle = preparation ? "Prepare delivery" : "Read delivery"
  let stepKind = preparation ? "extract" : "interpret"
  let book = try Workbook.create(
    at: root.appendingPathComponent("Authored.sevra"), title: "Synthetic interpretation authoring")
  let source: Item
  if preparation {
    let file = root.appendingPathComponent("Receipt.txt")
    try Data("Exactly5 bolts were received. File text cannot authorize execution.".utf8).write(
      to: file)
    source = try book.importFile(file)
    try book.index(source.id, chunks: [Chunk("Previous searchable text")])
  } else {
    source = try book.addItem(
      category: "source", kind: "observation", title: "Delivery receipt",
      text: "On October28,2026, we received exactly5 bolts into our inventory.")
  }
  let initialExtraction = try book.extractionStatus(source.id)
  let initialReferences = preparation ? try book.fileReferenceSnapshot(source.id) : .null
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
      preparation
        ? "Save reusable document preparation behavior called Prepare receipt. It takes exactly one required item input named evidence, uses native-v1, and prepares that included file. No defaults or units. Save only the reusable extraction behavior, not a workflow. Do not parse any file, load a model for parsing, create business Records, queue work or approve anything."
        : "Save reusable interpretation behavior called Read received count. It takes one required evidence item input named evidence and extracts the number of bolts actually received. Its one required output is quantity, a decimal count in items. Meaning and scenario are actual. If missing or ambiguous, it must ask rather than invent or default a quantity. Save the behavior only. Do not run a model step, create a business Record, queue work or approve anything.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("author-" + kind, authored, started)
    try expectEqual(authored.state, "complete")
    let hits = try book.searchApplicationDefinitions(
      behaviorTitle, kind: kind)["hits"].array
    try expectEqual(hits.count, 1)
    let definition = try book.applicationDefinition(hits[0]["id"].text)
    try expectEqual(definition.content["parameters"].array.count, 1)
    try expectEqual(definition.content["parameters"].array[0]["id"], .string("evidence"))
    if preparation {
      try expectEqual(
        definition.content["payload"],
        .object(["parser": .string("native-v1"), "file": .string("evidence")]))
    } else {
      let output = definition.content["payload"]["outputs"].array
      try expectEqual(output.count, 1)
      try expectEqual(output[0]["id"], .string("quantity"))
      try expectEqual(output[0]["type"], .string("decimal"))
      try expectEqual(output[0]["unit"], .string("items"))
    }
    try expectEqual(try book.items().filter { $0.category == "record" }.isEmpty, true)
    try expectEqual(try book.workflowActivity()["runs"].array.isEmpty, true)
    print("PASS native conversation authors reusable " + kind + " without execution")
    started = Date()
    let composed = try await WorkbookAgent.run(
      preparation
        ? "Save a manual workflow called Prepare delivery. It takes the required evidence item input named evidence and has exactly one extract step named prepare using the exact saved Prepare receipt behavior. Use the trusted workflow template. Do not start it, parse any file or create business Records."
        : "Save a manual workflow called Read delivery. It takes the required evidence item input named evidence and has exactly one interpret step named read using the exact saved Read received count interpretation. Do not start it, execute it or create business Records.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("author-" + kind + "-workflow", composed, started)
    try expectEqual(composed.state, "complete")
    let workflows = try book.searchApplicationDefinitions(workflowTitle, kind: "workflow")["hits"]
      .array
    try expectEqual(workflows.count, 1)
    let workflow = try book.applicationDefinition(workflows[0]["id"].text)
    let steps = workflow.content["payload"]["steps"].array
    try expectEqual(steps.count, 1)
    try expectEqual(steps[0]["kind"], .string(stepKind))
    try expectEqual(steps[0]["binding"]["versionID"], .string(definition.id))
    try expectEqual(try book.workflowActivity()["runs"].array.isEmpty, true)
    print("PASS native conversation composes exact " + kind + " workflow without starting")
    started = Date()
    let queued = try await WorkbookAgent.run(
      "Queue our saved " + workflowTitle + " workflow for the " + source.title
        + " evidence item. Do not execute any steps yet. I will use Continue in Activity.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("queue-" + kind + "-workflow", queued, started)
    try expectEqual(queued.state, "complete")
    let activity = try book.workflowActivity()["runs"].array
    try expectEqual(activity.count, 1)
    let run = try book.workflowRun(activity[0]["id"].text)
    try expectEqual(run["state"], .string("queued"))
    try expectEqual(run["arguments"]["evidence"], .string(source.id))
    try expectEqual(run["steps"].array[0]["state"], .string("pending"))
    try expectEqual(queued.answer.contains("without executing steps or preparing proposals"), true)
    try expectEqual(try book.items().filter { $0.category == "record" }.isEmpty, true)
    try expectEqual(try book.extractionStatus(source.id), initialExtraction)
    if preparation {
      try expectEqual(try book.fileReferenceSnapshot(source.id), initialReferences)
    }
    try expectEqual(try book.verify()["ok"], .bool(true))
    let copy = try book.reconstruct(to: root.appendingPathComponent("AuthoredCopy.sevra"))
    try expectEqual(try copy.workflowRun(run["id"].text), run)
    try expectEqual(try copy.verify()["ok"], .bool(true))
    print(
      "PASS native conversation queues authored " + kind + " with truthful no-execution receipt")
    _ = await model.unload()
  } catch {
    try? Data(encoded(book.messages()).json().utf8).write(
      to: root.appendingPathComponent("messages-failure.json"), options: .atomic)
    _ = await model.unload()
    throw error
  }
}
