import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

/// Replay the observed invalid raw-model answer through the real workbook host.
/// The comparison and first finish are injected; only recovery is autonomous.
private actor CurrencyFault: WorkbookInference {
  let identity = "Injected currency error followed by workbook validation and recovery"
  private let base: (any WorkbookInference)?
  private let datasetID: String
  private var responses = 0
  private var inputs: [String] = []
  private(set) var sawRejection = false
  private(set) var lastMetrics: Value = .null
  init(datasetID: String, base: (any WorkbookInference)? = nil) {
    self.datasetID = datasetID
    self.base = base
  }
  func beginRun() {}
  func endRun() async { await base?.endRun() }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    responses += 1
    if responses == 1 {
      return NativeReply(text: "", calls: [.init(
        id: "injected-comparison", name: "compare_rows",
        inputJSON: try Value.object([
          "datasetID": .string(datasetID), "labelColumn": .string("supplier"),
          "valueColumn": .string("total"),
        ]).json())])
    }
    if responses == 2 {
      let result = try Value.parse(messages.last!.content)
      inputs = result["inputs"].array.compactMap(\.string)
      try expectEqual(inputs.count, 2)
      try expectEqual(Set(inputs).isSubset(of: Set(citationIDs)), true)
      return try finish(
        "Oak Supply is $3.50 cheaper than Cedar Tools, representing a 12.73% savings relative to Cedar Tools' quote of 27.5.")
    }
    if responses == 3 {
      try expectEqual(messages.last!.toolName, "finish")
      try expectEqual(messages.last!.content.contains("Remove invented currency symbols"), true)
      sawRejection = true
    }
    if let base {
      let reply = try await base.respond(
        messages: messages, directory: directory, cancellation: cancellation,
        progress: progress, toolScope: toolScope, citationIDs: citationIDs)
      lastMetrics = await base.lastMetrics
      return reply
    }
    try expectEqual(responses, 3)
    return try finish("Oak Supply is 3.5 cheaper than Cedar Tools, or 12.73% relative to 27.5.")
  }
  private func finish(_ answer: String) throws -> NativeReply {
    NativeReply(text: "", calls: [.init(
      id: "currency-finish-\(responses)", name: "finish",
      inputJSON: try Value.object([
        "answer": .string(answer), "basis": .string("evidence"),
        "citations": .array(inputs.map(Value.string)),
      ]).json())])
  }
}

private func checkCurrencyResult(
  _ result: AgentResult, book: Workbook, before: [Item], expectedInputs: Set<String>,
  model: CurrencyFault
) async throws {
  try expectEqual(await model.sawRejection, true)
  try expectEqual(result.state, "complete")
  try expectEqual(result.answer.contains(where: { "$€£".contains($0) }), false)
  try expectEqual(result.answer.contains("3.5") && result.answer.contains("12.73"), true)
  try expectEqual(Set(result.citations), expectedInputs)
  let after = try book.items()
  let originalIDs = Set(before.map(\.id))
  try expectEqual(after.filter { originalIDs.contains($0.id) }, before)
  let added = after.filter { !originalIDs.contains($0.id) }
  // Read-only jobs still preserve the user's original request as a Source.
  try expectEqual(added.count, 1)
  try expectEqual(added[0].category, "source")
  try expectEqual(added[0].kind, "request")
  try expectEqual(added[0].text,
    "Compare supplier costs, report the difference and percentage. No currency was specified. Make no changes.")
  try expectEqual(try book.verify()["ok"], .bool(true))
  let messages = try book.messages()
  try expectEqual(messages.filter {
    $0.role == "assistant" && $0.body.contains("$3.50")
  }.isEmpty, true)
  try expectEqual(messages.filter {
    $0.role == "tool" && $0.body.contains("Remove invented currency symbols")
  }.count, 1)
}

func checkCurrencyRejection() async throws {
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-currency-check-" + identifier() + ".sevra")
  defer { try? FileManager.default.removeItem(at: path) }
  let demo = try Demo.create(at: path)
  let book = try Workbook(path)
  let before = try book.items()
  let table = demo["datasetID"].text
  let inputs = Set(try book.rows(table).map(\.id))
  let model = CurrencyFault(datasetID: table)
  let result = try await WorkbookAgent.run(
    "Compare supplier costs, report the difference and percentage. No currency was specified. Make no changes.",
    workbook: book, model: model)
  try await checkCurrencyResult(result, book: book, before: before, expectedInputs: inputs, model: model)
  try expectEqual(result.steps, 3)
  print("PASS invented currency is rejected before assistant publication; corrected answer retains exact citations and unchanged business data")
}

func runCurrencyRecoveryProbe(
  modelsRoot: String, library: String, engine: String
) async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-currency-recovery-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  for reasoning in [NativeReasoning.off, .bounded512] {
    for trial in 1...2 {
      let path = root.appendingPathComponent("Currency-\(reasoning.rawValue)-\(trial).sevra")
      let demo = try Demo.create(at: path)
      let book = try Workbook(path)
      let before = try book.items()
      let table = demo["datasetID"].text
      let inputs = Set(try book.rows(table).map(\.id))
      let original = try nativeProbeConfiguration(
        library: library, engine: engine, modelsRoot: modelsRoot,
        budget: .init(profile: .evaluation32K), reasoning: reasoning)
      let base = NativeWorkbookModel(configuration: .init(
        engine: original.engine, engineFiles: original.engineFiles,
        grammarLibrary: original.grammarLibrary, grammarSHA256: original.grammarSHA256,
        modelsRoot: original.modelsRoot, memoryBytes: original.memoryBytes,
        contextBudget: original.contextBudget, reasoning: reasoning, modelLayout: .installed,
        contextMaintenanceEnabled: false))
      let model = CurrencyFault(datasetID: table, base: base)
      try await base.beginRun()
      let began = Date()
      do {
        let result = try await WorkbookAgent.run(
          "Compare supplier costs, report the difference and percentage. No currency was specified. Make no changes.",
          workbook: book, modelDirectory: URL(fileURLWithPath: modelsRoot),
          progress: { fputs("Currency recovery: \($0)\n", stderr) }, model: model)
        print(try Value.object([
          "faultInjected": .bool(true), "reasoningBudget": .number(Double(reasoning.rawValue)),
          "trial": .number(Double(trial)), "elapsedSeconds": .number(Date().timeIntervalSince(began)),
          "answer": .string(result.answer), "steps": .number(Double(result.steps)),
          "citations": .array(result.citations.map(Value.string)),
          "trace": try encoded(book.messages().filter { $0.role == "tool" }),
          "runs": .array(try book.agentRuns()),
        ]).json())
        try await checkCurrencyResult(result, book: book, before: before, expectedInputs: inputs, model: model)
        try expectEqual(await base.unload(), true)
      } catch {
        print(try Value.object([
          "faultInjected": .bool(true), "reasoningBudget": .number(Double(reasoning.rawValue)),
          "trial": .number(Double(trial)), "error": .string(String(describing: error)),
          "trace": try encoded(book.messages().filter { $0.role == "tool" }),
        ]).json())
        _ = await base.unload()
        throw error
      }
    }
  }
  print("PASS four real-model recoveries from injected currency errors; off and bounded512, fresh helper per trial")
}
