import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

/// Inject only the observed invalid finish, then let the actual model recover.
/// This is a labeled fault-injection probe, not an autonomous success claim.
private actor MissingCitationFault: WorkbookInference {
  let identity = "Injected uncited finish followed by native model recovery"
  private let base: NativeWorkbookModel
  private var first = true
  private let basis: String
  private(set) var lastMetrics: Value = .null
  private(set) var recoveryScopes: [String] = []
  init(_ base: NativeWorkbookModel, basis: String) {
    self.base = base
    self.basis = basis
  }
  // The probe acquires the underlying lease before handing it to this wrapper.
  func beginRun() {}
  func endRun() async { await base.endRun() }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    if first {
      first = false
      try expectEqual(toolScope, .all)
      try expectEqual(citationIDs.isEmpty, true)
      lastMetrics = .object(["injectedMissingCitation": .bool(true)])
      return NativeReply(
        text: "",
        calls: [
          .init(
            id: "injected-uncited-finish", name: "finish",
            inputJSON: try Value.object([
              "answer": .string(
                basis == "evidence"
                  ? "The original quantity was 0.10 kg. No currency was specified."
                  : "The original quantity was 120."), "basis": .string(basis),
              "citations": .array([]),
            ]).json())
        ])
    }
    if recoveryScopes.isEmpty { try expectEqual(toolScope, .inspection) }
    recoveryScopes.append(toolScope.rawValue)
    let reply = try await base.respond(
      messages: messages, directory: directory, cancellation: cancellation,
      progress: progress, toolScope: toolScope, citationIDs: citationIDs)
    lastMetrics = await base.lastMetrics
    return reply
  }
}

func runInspectionRecoveryProbe(
  modelFolder: String, library: String, engine: String, modelsRoot: String
) async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-inspection-recovery-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  for reasoning in [NativeReasoning.off, .bounded512] {
    for basis in ["evidence", "current_request"] {
      let book = try Workbook.create(
        at: root.appendingPathComponent("Recovery-\(reasoning.rawValue)-\(basis).sevra"),
        title: "Recovery")
      let original = try book.addMessage(
        "Purchase code MAPLE-27. Original quantity is exactly 0.10 kg. No currency has been specified.",
        role: "user")
      _ = try book.addMessage("Recorded.", role: "assistant")
      let base = NativeWorkbookModel(
        configuration: try nativeProbeConfiguration(
          library: library, engine: engine, modelsRoot: modelsRoot,
          budget: .init(profile: .evaluation32K), reasoning: reasoning))
      let model = MissingCitationFault(base, basis: basis)
      try await base.beginRun()
      do {
        let result = try await WorkbookAgent.run(
          "What was the exact original quantity and unit? Did I choose a currency? Make no changes.",
          workbook: book, modelDirectory: URL(fileURLWithPath: modelFolder),
          progress: { fputs("Inspection recovery: \($0)\n", stderr) }, model: model)
        let scopes = await model.recoveryScopes
        print(
          try Value.object([
            "faultInjected": .bool(true), "injectedBasis": .string(basis),
            "reasoningBudget": .number(Double(reasoning.rawValue)),
            "answer": .string(result.answer),
            "citations": .array(result.citations.map(Value.string)),
            "steps": .number(Double(result.steps)),
            "actualModelScopes": .array(scopes.map(Value.string)),
            "runs": .array(try book.agentRuns()),
            "trace": try encoded(book.messages().filter { $0.role == "tool" }),
          ]).json())
        try expectEqual(result.state, "complete")
        try expectEqual(result.citations.contains("message:" + original), true)
        // Quantity and unit can be expressed in separate clauses. Keep the
        // decimal spelling check without requiring one exact sentence shape.
        try expectEqual(
          result.answer.range(of: #"(?<![0-9.])0\.10(?![0-9])"#, options: .regularExpression)
            != nil, true)
        try expectEqual(
          result.answer.range(of: #"\bkg\b"#, options: .regularExpression) != nil, true)
        try expectEqual(result.answer.contains(where: { "$€£".contains($0) }), false)
        try expectEqual(scopes.first, "inspection")
        try expectEqual(try book.items().filter { $0.category == "record" }.isEmpty, true)
        try expectEqual(try book.verify()["ok"], .bool(true))
        try expectEqual(await base.unload(), true)
      } catch {
        _ = await base.unload()
        throw error
      }
    }
  }
  print(
    "PASS real native recovery after injected uncited and fabricated current-request finishes, with and without reasoning"
  )
}
