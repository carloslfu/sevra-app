import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

func runMovementDirectionProbe(modelsRoot: String, library: String, engine: String, output: String)
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
  let b = try Workbook.create(
    at: root.appendingPathComponent("Direction.sevra"), title: "Vega delivery")
  let source = try b.addItem(
    category: "source", kind: "observation", title: "Receipt Vega 2043",
    text:
      "SYNTHETIC RECEIPT VEGA 2043\n2 brass bolts handed over\nFulfillment evidence only\nNo automatic inventory acceptance"
  )
  let cases: [(String, String, String, Bool)] = [
    (
      "ambiguous",
      "The Vega receipt records two brass bolts handed over. Prepare the stock adjustment for that delivery on 2 January 2026, but leave it for my review.",
      "2", false
    ),
    (
      "outgoing",
      "These two bolts left our stock and went to the customer. Correct this movement and leave the change for my review.",
      "-2", true
    ),
    (
      "incoming",
      "We received two brass bolts into our stock from Vega on 2 January 2026. Prepare the movement for review.",
      "2", true
    ),
    ("wrong-sign", "These two bolts left our stock and went to the customer.", "2", false),
    (
      "spanish",
      "Entregamos dos tornillos de nuestro inventario al cliente. Prepara el movimiento para revisar.",
      "-2", true
    ),
  ]
  var rows: [Value] = []
  do {
    try await model.beginRun()
    for (name, request, quantity, expected) in cases {
      let started = Date()
      let result = try await MovementDirectionReview.check(
        request: request, evidence: source,
        chunks: b.readChunks(source.id), subject: "brass bolts", quantity: quantity,
        model: model, directory: URL(fileURLWithPath: modelsRoot), cancellation: .init(),
        progress: { _ in })
      rows.append(
        .object([
          "name": .string(name), "expected": .bool(expected),
          "matches": .bool(result.matches), "review": result.receipt,
          "seconds": .number(Date().timeIntervalSince(started)), "metrics": await model.lastMetrics,
        ]))
      try Data(Value.array(rows).json().utf8).write(
        to: root.appendingPathComponent("reviews.json"), options: .atomic)
      try expectEqual(result.matches, expected)
      print("PASS native direction \(name)")
    }
    await model.endRun()
    _ = try b.addMessage("Earlier interpretation: add two bolts to inventory.", role: "assistant")
    let result = try await WorkbookAgent.run(
      cases[0].1, workbook: b,
      modelDirectory: URL(fileURLWithPath: modelsRoot), model: model, enableCompaction: false)
    let outcome: Value = .object([
      "answer": .string(result.answer), "state": .string(result.state),
      "movements": .array(try b.items(kind: "movement").map { try encoded($0) }),
      "messages": .array(try b.messages().map { try encoded($0) }),
      "runs": .array(try b.agentRuns()),
    ])
    try Data(outcome.json().utf8).write(to: root.appendingPathComponent("agent.json"))
    try expectEqual(try b.items(kind: "movement").isEmpty, true)
    try expectEqual(try b.verify()["ok"], .bool(true))
    print(
      "PASS native ambiguous request with misleading earlier assistant history creates no movement")
    _ = await model.unload()
  } catch {
    await model.endRun()
    _ = await model.unload()
    throw error
  }
}
