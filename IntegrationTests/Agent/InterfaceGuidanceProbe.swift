import CryptoKit
import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

func runInterfaceGuidanceProbe(modelsRoot: String, library: String, engine: String, output: String)
  async throws
{
  let root = URL(fileURLWithPath: output)
  try require(
    !FileManager.default.fileExists(atPath: root.path), "fixture", "Use a new output folder.")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  let cases: [(String, String, Int)] = [
    (
      "thread-difference",
      "How would starting a thread differ from staying in our main conversation? Explain only; do not create one.",
      1
    ),
    (
      "source-record",
      "What is the difference between a Source and a Record? Explain only; leave this workbook unchanged.",
      1
    ),
    (
      "shared-data",
      "If I open a side thread and change inventory there, is the main workbook unaffected? Explain without changing anything.",
      1
    ),
    (
      "supplied-prices",
      "A quote is 12.40 and another is 14.80. Calculate their price difference. Do not create records or tables.",
      3
    ),
    (
      "stored-prices",
      "Which of the Birch and Cedar quotes in this workbook has the lower unit cost, and by how much? Read both quote sources. Do not change anything.",
      12
    ),
  ]
  let spec = Value.object([
    "version": .number(1),
    "scope": .string(
      "Interface explanations without irrelevant tools; shared workbook scope; retained deterministic arithmetic and source retrieval."
    ),
    "cases": .array(
      cases.map {
        .object([
          "name": .string($0.0), "prompt": .string($0.1), "maximumSteps": .number(Double($0.2)),
        ])
      }),
    "checks": .string(
      "First three: finish only, one step, no tool receipts. Supplied prices: calculate then finish, result 2.4, no unrelated tools. Stored prices: read both quote versions, deterministic comparison, cited originals and 2.4 difference. Every case preserves original items/conversations and verifies integrity. Shared-data wording also requires human/agent semantic review."
    ),
  ])
  try Data(spec.json().utf8).write(to: root.appendingPathComponent("protocol.json"))
  func hash(_ path: String) throws -> Value {
    .string(
      SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path))).map {
        String(format: "%02x", $0)
      }.joined())
  }
  let execution = try Value.object([
    "binarySHA256": hash(CommandLine.arguments[0]), "engineSHA256": hash(engine),
    "grammarLibrarySHA256": hash(library),
    "model": .string("Qwen3.6-35B installed, native 32K, bounded512"),
  ])
  try Data(execution.json().utf8).write(to: root.appendingPathComponent("execution.json"))
  let model = NativeWorkbookModel(
    configuration: try nativeProbeConfiguration(
      library: library, engine: engine, modelsRoot: modelsRoot,
      budget: .init(profile: .evaluation32K), reasoning: .bounded512, modelLayout: .installed))
  var results: [Value] = []
  var failures = 0
  for (name, prompt, maximum) in cases {
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    let birch = try book.addItem(
      category: "source", kind: "quote", title: "Birch quote",
      text: "Birch quoted a unit cost of 14.80 for a brass fitting. No currency was specified.")
    let cedar = try book.addItem(
      category: "source", kind: "quote", title: "Cedar quote",
      text:
        "Cedar quoted a unit cost of 12.40 for the same brass fitting. No currency was specified.")
    let original = try encoded(book.items())
    var record: [String: Value] = ["name": .string(name), "prompt": .string(prompt)]
    do {
      let result = try await WorkbookAgent.run(
        prompt, workbook: book,
        modelDirectory: URL(fileURLWithPath: modelsRoot),
        cancellation: .init(deadlineAfterSeconds: 240),
        model: model, enableCompaction: false)
      record["answer"] = .string(result.answer)
      record["steps"] = .number(Double(result.steps))
      record["citations"] = .array(result.citations.map(Value.string))
      let receipts = try book.messages(limit: 100).filter { $0.role == "tool" }.map {
        try Value.parse($0.body)
      }
      record["receipts"] = .array(receipts)
      try require(result.steps <= maximum, "guidance", "Exceeded the preregistered step limit.")
      try require(
        result.conversationAction == nil && book.conversations().count == 1, "guidance",
        "Unexpected conversation action.")
      if maximum == 1 {
        try require(
          receipts.isEmpty && result.citations.isEmpty, "guidance",
          "An explanation used evidence or action tools.")
      } else {
        let calls = receipts.filter { $0["tool"] != .string("finish") }
        try require(
          calls.contains { ["calculate", "compare_rows"].contains($0["tool"].text) }, "guidance",
          "Missing deterministic calculation.")
        try require(result.answer.contains("2.4"), "guidance", "Missing correct price difference.")
        if name == "supplied-prices" {
          try require(
            calls.allSatisfy { $0["tool"] == .string("calculate") }, "guidance",
            "Unrelated tool for supplied arithmetic.")
        } else {
          try require(
            Set([birch.id, cedar.id]).isSubset(of: Set(result.citations)), "guidance",
            "Missing inspected quote citations.")
          try require(result.answer.lowercased().contains("cedar"), "guidance", "Wrong supplier.")
        }
      }
      try require(
        try encoded(book.items().filter { $0.kind != "request" }) == original, "guidance",
        "Original data changed.")
      try require(try book.verify()["ok"] == .bool(true), "guidance", "Workbook integrity failed.")
      record["passed"] = .bool(true)
    } catch {
      failures += 1
      record["passed"] = .bool(false)
      record["error"] = .string(error.localizedDescription)
    }
    record["runs"] = .array(try book.agentRuns())
    results.append(.object(record))
    try Data(Value.array(results).json().utf8).write(
      to: root.appendingPathComponent("results.json"), options: .atomic)
    print("\(record["passed"] == .bool(true) ? "PASS" : "FAIL") interface guidance \(name)")
    fflush(stdout)
  }
  let released = await model.releaseResources()
  try require(released, "guidance", "Model resources did not release.")
  try require(failures == 0, "guidance", "\(failures) cases failed; preserve the evidence.")
}
