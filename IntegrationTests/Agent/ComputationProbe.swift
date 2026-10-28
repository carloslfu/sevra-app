import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

func runComputationProbe(modelsRoot: String, library: String, engine: String, output: String)
  async throws
{
  let root = URL(fileURLWithPath: output)
  try require(
    !FileManager.default.fileExists(atPath: root.path), "fixture", "Use a fresh output directory.")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  let model = NativeWorkbookModel(
    configuration: try nativeProbeConfiguration(
      library: library, engine: engine, modelsRoot: modelsRoot,
      budget: .init(profile: .evaluation32K),
      reasoning: .bounded512, modelLayout: .installed))
  let book = try Workbook.create(
    at: root.appendingPathComponent("Computation.sevra"), title: "Synthetic shop")
  let function = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("function"), "title": .string("Case units"),
      "description": .string("12items per case"),
      "parameters": .array([
        .object([
          "id": .string("cases"), "label": .string("Cases"), "type": .string("decimal"),
          "required": .bool(true), "unit": .string("cases"),
        ])
      ]),
      "payload": .object([
        "expression": .string("cases*12"), "calls": .array([]), "unit": .string("items"),
      ]),
    ]))
  let original = try book.addItem(
    category: "source", kind: "observation", title: "Synthetic counts",
    text: "Estimated counts: bolts2, nuts5.", meaning: "estimate")
  let table = try book.createDataset(
    title: "Counts",
    columns: [
      .init(id: "sku", title: "Item", type: "text"),
      .init(id: "quantity", title: "Quantity", type: "decimal", unit: "items"),
    ],
    rows: [
      ["sku": .string("bolts"), "quantity": .string("2")],
      ["sku": .string("nuts"), "quantity": .string("5")],
    ], sourceID: original.id)
  for row in try book.rows(table.id) {
    _ = try book.addItem(
      category: "record", kind: "row", title: row.title, data: row.data, meaning: "estimate",
      inputs: [row.id], supersedes: row.id)
  }
  let query = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("query"), "title": .string("Current quantities"),
      "description": .string("Current estimated counts"), "parameters": .array([]),
      "payload": .object([
        "dataMode": .string("live"),
        "query": .object([
          "sources": .array([
            .object([
              "datasetID": .string(table.id), "definitionID": .string(table.definitionID),
              "scope": .object(["meaning": .string("estimate")]),
            ])
          ]),
          "select": .array([
            .object([
              "id": .string("sku"),
              "column": .object(["source": .number(0), "column": .string("sku")]),
            ]),
            .object([
              "id": .string("quantity"),
              "column": .object(["source": .number(0), "column": .string("quantity")]),
            ]),
          ]),
          "limit": .number(10),
        ]),
      ]),
    ]))
  var results: [Value] = []
  func ask(_ name: String, _ prompt: String) async throws -> AgentResult {
    let started = Date()
    let value = try await WorkbookAgent.run(
      prompt, workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot), model: model,
      enableCompaction: false)
    results.append(
      .object([
        "name": .string(name), "answer": .string(value.answer), "state": .string(value.state),
        "steps": .number(Double(value.steps)),
        "seconds": .number(Date().timeIntervalSince(started)), "runs": .array(try book.agentRuns()),
      ]))
    try Data(Value.array(results).json().utf8).write(
      to: root.appendingPathComponent("results.json"), options: .atomic)
    try Data(encoded(book.messages()).json().utf8).write(
      to: root.appendingPathComponent("messages.json"), options: .atomic)
    return value
  }
  do {
    let first = try await ask(
      "two-native-spaces",
      "Use the saved Case units calculation for 3 cases. Create two spaces named Stock count and Case report, each showing it as a reusable native calculation component, with the same inputs and live definition binding. Do not create business proposals or static text substitutes."
    )
    try expectEqual(first.state, "complete")
    for name in ["Stock count", "Case report"] {
      let space = try expectValue(book.spaces().first { $0.title == name })
      let component = try expectValue(
        space.definition.components.first { $0.type == "calculation" })
      try expectEqual(component.definitionBinding?["logicalID"], .string(function.logicalID))
      try expectEqual(component.arguments, .object(["cases": .string("3")]))
      try expectEqual(try book.componentDefinitionResult(component)["result"], .string("36"))
    }
    print("PASS selected model reuses one calculation in two native spaces")
    let second = try await ask(
      "publish-query",
      "Use our saved Current quantities query and save its complete result as an estimate named Counts snapshot for my review. Use the saved query and its actual evaluation receipt; do not accept it."
    )
    try expectEqual(second.state, "needs_review")
    let published = try expectValue(
      book.items(kind: "calculation").first { $0.title == "Counts snapshot" })
    try expectEqual(published.status, "draft")
    try expectEqual(published.meaning, "estimate")
    try expectEqual(published.data["evaluation"]["definitionID"], .string(query.id))
    try expectEqual(published.data["evaluation"]["result"]["rows"].array.count, 2)
    try expectEqual(published.data["inputPopulation"].array[0]["rows"].array.count, 2)
    print("PASS selected model publishes exact complete query result as an estimate draft")
    _ = try await ask(
      "report",
      "Write a short report named Receiving outlook from the saved Counts snapshot result. Include both item quantities and clearly say these are estimates, leaving the report as a draft. Do not accept either result."
    )
    let report = try expectValue(
      book.items(kind: "document").first { $0.title == "Receiving outlook" })
    try expectEqual(report.status, "draft")
    try expectEqual(report.text.lowercased().contains("estimate"), true)
    try expectEqual(report.text.contains("2") && report.text.contains("5"), true)
    try expectEqual(
      try book.lineage(report.id).contains { $0["parent"] == .string(published.id) }, true)
    print("PASS selected model derives a report from the exact saved result without acceptance")
    let old = try book.rows(table.id).first { $0.data["sku"] == .string("bolts") }!
    _ = try book.addItem(
      category: "record", kind: "row", title: old.title,
      data: .object(["sku": .string("bolts"), "quantity": .string("8")]), meaning: "estimate",
      inputs: [old.id], supersedes: old.id)
    let changed = try await ask(
      "live-vs-saved",
      "Compare the live Current quantities query with the previously saved Counts snapshot. Tell me what changed for bolts, preserving the saved result and all draft statuses. Do not write anything."
    )
    try expectEqual(changed.answer.contains("8") && changed.answer.contains("2"), true)
    try expectEqual(try book.item(published.id).data, published.data)
    try expectEqual(try book.items(kind: "calculation").count, 1)
    try expectEqual(try book.verify()["ok"], .bool(true))
    print("PASS selected model distinguishes refreshed live rows from saved historical values")
    _ = await model.unload()
  } catch {
    try? Data(encoded(book.messages()).json().utf8).write(
      to: root.appendingPathComponent("messages-failure.json"), options: .atomic)
    _ = await model.unload()
    throw error
  }
}
