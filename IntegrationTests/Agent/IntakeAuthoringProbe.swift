import CryptoKit
import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

func runIntakeAuthoringProbe(modelsRoot: String, library: String, engine: String, output: String)
  async throws
{
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
  let paths = [
    CommandLine.arguments[0], "Sources/SevraCore/DefinitionTools.swift",
    "Sources/SevraCore/WorkflowDefinition.swift", "Sources/SevraCore/DefinitionIntake.swift",
    "Sources/SevraAI/NativeApplicationTools.swift", "Sources/SevraAI/WorkbookAgent.swift",
    "Sources/SevraAI/RequestRestrictions.swift",
    "Sources/SevraAI/ActionConfirmations.swift", "IntegrationTests/Agent/workbook-tools.json",
    "IntegrationTests/Agent/IntakeAuthoringProbe.swift",
  ]
  let identity: Value = .object([
    "recordedUTC": .string(ISO8601DateFormatter().string(from: Date())),
    "model": .string(await model.identity),
    "files": .array(
      try paths.map { path in
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return .object([
          "path": .string(path), "bytes": .number(Double(data.count)),
          "sha256": .string(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()),
        ])
      }),
  ])
  try Data(identity.json().utf8).write(
    to: root.appendingPathComponent("identity.json"), options: .atomic)
  func fixture(_ name: String) throws -> (Workbook, Dataset) {
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    let source = try book.addItem(category: "source", kind: "observation", title: "Starting values")
    let table = try book.createDataset(
      title: "Parts",
      columns: [.init(id: "sku", title: "SKU"), .init(id: "qty", title: "Quantity")],
      rows: [["sku": .string("0012"), "qty": .string("4")]], sourceID: source.id)
    try book.setOpeningBalance(
      subject: "stock", quantity: "20", effective: "2026-10-01", sourceID: source.id)
    return (book, table)
  }
  let (book, table) = try fixture("Authored")
  let initial = try encoded(book.rows(table.id))
  let initialRecords = try encoded(book.items().filter { $0.category == "record" })
  let file = root.appendingPathComponent("Incoming.csv")
  try Data("code,amount\n0012,7\n".utf8).write(to: file)
  let source = try book.importFile(file)
  let extraction = try book.extractionStatus(source.id)
  var results: [Value] = []
  var activeBook = book
  func record(_ name: String, _ result: AgentResult, _ current: Workbook, _ started: Date) throws {
    results.append(
      .object([
        "name": .string(name), "state": .string(result.state), "answer": .string(result.answer),
        "steps": .number(Double(result.steps)),
        "seconds": .number(Date().timeIntervalSince(started)),
        "runs": .array(try current.agentRuns()), "activity": try current.workflowActivity(),
      ]))
    try Data(Value.array(results).json().utf8).write(
      to: root.appendingPathComponent("results.json"), options: .atomic)
    try Data(encoded(current.messages()).json().utf8).write(
      to: root.appendingPathComponent(name + "-messages.json"), options: .atomic)
  }
  do {
    var started = Date()
    let authored = try await WorkbookAgent.run(
      "Save reusable intake behavior named Update parts for my existing Parts table. Incoming CSV or TSV has its header in row1. Map incoming column1 to sku and column2 to qty. Use merge keyed by sku. New rows are estimates in the actual scenario. Take exactly one required item input named file, with no default/unit. Save only the intake behavior. Do not parse/apply a file, queue work, accept anything or change existing rows.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("author", authored, book, started)
    try expectEqual(authored.state, "complete")
    let hits = try book.searchApplicationDefinitions("Update parts", kind: "intake")["hits"].array
    try expectEqual(hits.count, 1)
    let intake = try book.applicationDefinition(hits[0]["id"].text)
    let payload = intake.content["payload"]
    try expectEqual(payload["datasetID"], .string(table.id))
    try expectEqual(payload["definitionID"], .string(table.definitionID))
    try expectEqual(payload["file"], .string("file"))
    try expectEqual(payload["mode"], .string("merge"))
    try expectEqual(payload["headerRow"], .number(1))
    try expectEqual(payload["keys"], .array([.string("sku")]))
    try expectEqual(payload["newRowMeaning"], .string("estimate"))
    try expectEqual(payload["newRowScenario"], .string("actual"))
    try expectEqual(
      payload["mapping"],
      .array([
        .object(["position": .number(0), "target": .string("sku")]),
        .object(["position": .number(1), "target": .string("qty")]),
      ]))
    try expectEqual(try encoded(book.items().filter { $0.category == "record" }), initialRecords)
    try expectEqual(try book.workflowActivity()["runs"].array.isEmpty, true)
    started = Date()
    let composed = try await WorkbookAgent.run(
      "Create a manual workflow named Review parts using the trusted workflow template for my exact saved Update parts intake. Use an intake step named import_rows and its required review step. Save only; do not queue or execute anything.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("compose", composed, book, started)
    try expectEqual(composed.state, "complete")
    let workflows = try book.searchApplicationDefinitions("Review parts", kind: "workflow")["hits"]
      .array
    try expectEqual(workflows.count, 1)
    let workflow = try book.applicationDefinition(workflows[0]["id"].text)
    let steps = workflow.content["payload"]["steps"].array
    try expectEqual(steps.count, 2)
    try expectEqual(steps[0]["kind"], .string("intake"))
    try expectEqual(steps[0]["id"], .string("import_rows"))
    try expectEqual(steps[0]["binding"]["versionID"], .string(intake.id))
    try expectEqual(steps[1]["review"], steps[0]["id"])
    try expectEqual(try encoded(book.items().filter { $0.category == "record" }), initialRecords)
    try expectEqual(try book.workflowActivity()["runs"].array.isEmpty, true)
    started = Date()
    let queued = try await WorkbookAgent.run(
      "Queue my saved Review parts workflow for the included Incoming.csv as its file input. Do not execute it or prepare proposals. I will use Continue in Activity.",
      workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("queue", queued, book, started)
    try expectEqual(queued.state, "complete")
    let runs = try book.workflowActivity()["runs"].array
    try expectEqual(runs.count, 1)
    let run = try book.workflowRun(runs[0]["id"].text)
    try expectEqual(run["state"], .string("queued"))
    try expectEqual(run["arguments"]["file"], .string(source.id))
    try expectEqual(run["steps"].array.allSatisfy { $0["state"] == .string("pending") }, true)
    try expectEqual(queued.answer.contains("without executing steps or preparing proposals"), true)
    try expectEqual(try encoded(book.rows(table.id)), initial)
    try expectEqual(try encoded(book.items().filter { $0.category == "record" }), initialRecords)
    try expectEqual(try book.balance(subject: "stock")["quantity"], .string("20"))
    try expectEqual(try book.extractionStatus(source.id), extraction)
    try expectEqual(try book.items().filter { $0.kind == "table-intake-update" }.isEmpty, true)
    let copy = try book.reconstruct(to: root.appendingPathComponent("AuthoredCopy.sevra"))
    try expectEqual(try copy.workflowRun(run["id"].text), run)
    try expectEqual(try encoded(copy.rows(table.id)), initial)
    try expectEqual(try copy.verify()["ok"], .bool(true))
    try expectEqual(try book.verify()["ok"], .bool(true))
    let (ambiguous, other) = try fixture("Ambiguous")
    activeBook = ambiguous
    let before = try encoded(ambiguous.rows(other.id))
    started = Date()
    let clarification = try await WorkbookAgent.run(
      "I want reusable intake for my Parts table, but I have not chosen append, replace or merge, a column mapping or the meaning of incoming rows. Do not choose defaults for me. Ask what you need before saving anything.",
      workbook: ambiguous, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    try record("ambiguous", clarification, ambiguous, started)
    try expectEqual(clarification.state, "complete")
    try expectEqual(try ambiguous.searchApplicationDefinitions("")["hits"].array.isEmpty, true)
    try expectEqual(try encoded(ambiguous.rows(other.id)), before)
    try expectEqual(try ambiguous.workflowActivity()["runs"].array.isEmpty, true)
    for message in try ambiguous.messages() where message.role == "tool" {
      let tool = try Value.parse(message.body)["tool"].text
      try expectEqual(WorkbookTools.readOnlyTools.contains(tool), true)
    }
    try expectEqual(
      try ambiguous.items().filter { $0.category == "record" && $0.kind != "row" }.isEmpty, true)
    try expectEqual(try ambiguous.verify()["ok"], .bool(true))
    print(
      "PASS actual native intake authoring, exact reviewed template, inert queued run and missing-intent clarification"
    )
    _ = await model.unload()
  } catch {
    try? Data(encoded(activeBook.messages()).json().utf8).write(
      to: root.appendingPathComponent("failure-messages.json"), options: .atomic)
    _ = await model.unload()
    throw error
  }
}
