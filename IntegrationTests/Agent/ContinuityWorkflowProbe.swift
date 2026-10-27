import Foundation
import SevraAI
import SevraCore
import SevraNativeAI

/// Actual native inference with a controlled human edit after summary input was
/// captured. The wrapper never supplies a model response, tool or citation.
private actor ContinuityWorkflowModel: WorkbookInference {
  let native: NativeWorkbookModel
  var pendingEdit: (path: URL, id: String, accept: Bool)?
  var edits: [Value] = []
  var summaries = 0
  let identity: String
  var lastMetrics: Value = .null
  init(_ native: NativeWorkbookModel) async {
    self.native = native
    identity = await native.identity
  }
  let supportsCompaction = true
  func beginRun() async throws { try await native.beginRun() }
  func endRun() async { await native.endRun() }
  func releaseResources() async -> Bool { await native.releaseResources() }
  func arm(path: URL, id: String, accept: Bool) {
    pendingEdit = (path, id, accept)
  }
  func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, citationIDs: [String], progress: @escaping @Sendable (String) -> Void
  ) async throws -> ContextMeasurement {
    try await native.measureContext(
      messages: messages, directory: directory, cancellation: cancellation,
      summary: summary, citationIDs: citationIDs, progress: progress)
  }
  func summarize(
    messages: [InferenceMessage], allowedMessageIDs: [String], directory: URL,
    cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) async throws -> String {
    summaries += 1
    if let edit = pendingEdit {
      let workbook = try Workbook(edit.path)
      let changed = try edit.accept ? workbook.accept(edit.id) : workbook.undoItem(edit.id)
      edits.append(
        .object([
          "summary": .number(Double(summaries)), "before": .string(edit.id),
          "after": .string(changed.id), "status": .string(changed.status),
          "meaning": .string(changed.meaning),
        ]))
      pendingEdit = nil
    }
    let result = try await native.summarize(
      messages: messages, allowedMessageIDs: allowedMessageIDs,
      directory: directory, cancellation: cancellation, progress: progress)
    lastMetrics = await native.lastMetrics
    return result
  }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    let result = try await native.respond(
      messages: messages, directory: directory, cancellation: cancellation,
      progress: progress, toolScope: toolScope, citationIDs: citationIDs)
    lastMetrics = await native.lastMetrics
    return result
  }
}

/// Opt-in C12 subset. Keep the original workbook and all failed results in a new
/// output directory. This is functional evidence, not context/performance adoption.
func runContinuityWorkflowProbe(
  modelsRoot: String, library: String, engine: String, output: String
) async throws {
  let root = URL(fileURLWithPath: output).standardizedFileURL
  try require(
    !FileManager.default.fileExists(atPath: root.path), "fixture",
    "The continuity output directory must not exist.")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  let path = root.appendingPathComponent("Workflow.sevra")
  _ = try Demo.create(at: path)
  let book = try Workbook(path)
  let baselineBalance = try book.balance(subject: "brass bolts")
  let baselineSources = try book.items().filter { $0.category == "source" }
  let originalText =
    "Purchase code MAPLE-27. Original packing sample is exactly 0.10 kg. No currency has been specified. Keep all inventory unchanged."
  let original = try book.addMessage(originalText, role: "user")
  _ = try book.addMessage("Recorded as supplied information.", role: "assistant")
  let assumption = try book.addItem(
    category: "source", kind: "assumption", title: "November demand assumption",
    text: "Estimated demand for November is 4 units.")
  let forecast = try book.addItem(
    category: "record", kind: "forecast", title: "November forecast",
    text: "Estimated demand for November is 4 units.", meaning: "estimate",
    inputs: [assumption.id])
  let native = NativeWorkbookModel(
    configuration: try nativeProbeConfiguration(
      library: library, engine: engine, modelsRoot: modelsRoot,
      budget: .init(profile: .evaluation32K), reasoning: .bounded512, modelLayout: .installed))
  let model = await ContinuityWorkflowModel(native)
  let directory = URL(fileURLWithPath: modelsRoot)
  var stages: [Value] = []
  var activeStage = "setup"
  var restored: Workbook?

  func closedHistory(_ round: Int) throws {
    for index in 0..<150 {
      let message = try book.addMessage(
        "Closed shelf-label inspection \(round)-\(index). "
          + String(repeating: "Labels checked; no inventory movement or pending action. ", count: 3),
        role: "assistant")
      if index % 25 == 0 {
        try book.chapter(title: "Inspection \(round)-\(index)", message: message)
      }
    }
  }
  func ask(
    _ stage: String, _ prompt: String, workbook: Workbook, conversation: String = "main"
  ) async throws -> AgentResult {
    activeStage = stage
    let started = Date()
    let before = try workbook.contextCheckpoints(conversation: conversation, limit: 100).count
    let result = try await WorkbookAgent.run(
      prompt, workbook: workbook, conversation: conversation, modelDirectory: directory,
      progress: { fputs("Continuity workflow: \($0)\n", stderr) }, model: model)
    let row: Value = .object([
      "stage": .string(stage), "conversation": .string(conversation),
      "prompt": .string(prompt), "answer": .string(result.answer),
      "state": .string(result.state), "steps": .number(Double(result.steps)),
      "citations": .array(result.citations.map(Value.string)),
      "jobSeconds": .number(Date().timeIntervalSince(started)),
      "checkpointsBefore": .number(Double(before)),
      "checkpointsAfter": .number(
        Double(try workbook.contextCheckpoints(conversation: conversation, limit: 100).count)),
    ])
    stages.append(row)
    print(try row.json())
    fflush(stdout)
    try expectEqual(result.state, "complete")
    try expectEqual(try workbook.balance(subject: "brass bolts"), baselineBalance)
    try expectEqual(try workbook.verify()["ok"], .bool(true))
    return result
  }
  func originalHistory(_ workbook: Workbook, conversation: String = "main") throws -> [Value] {
    var result: [Value] = []
    var after: String?
    while true {
      let page = try workbook.historySlice(conversation: conversation, after: after, limit: 500)
      result += try page.messages.map { try encoded($0) }
      if !page.hasMore { return result }
      after = page.messages.last!.id
    }
  }
  func save(_ error: Error?, unloaded: Bool) async throws {
    var value: [String: Value] = [
      "probe": .string("native-continuity-workflow-v2"), "ok": .bool(error == nil),
      "activeStage": .string(activeStage), "contextTokens": .number(32768),
      "reasoningTokens": .number(512), "stages": .array(stages),
      "summaries": .number(Double(await model.summaries)), "edits": .array(await model.edits),
      "unloaded": .bool(unloaded), "runs": .array(try book.agentRuns()),
      "checkpoints": .array(try book.contextCheckpoints(limit: 100)),
      "history": .array(try originalHistory(book)),
      "integrity": try book.verify(), "balance": try book.balance(subject: "brass bolts"),
      "forecast": try encoded(book.item(forecast.logicalID)),
    ]
    if let error { value["error"] = .string(error.localizedDescription) }
    if let restored {
      value["reopenedRuns"] = .array(try restored.agentRuns())
      value["reopenedHistory"] = .array(try originalHistory(restored))
      value["reopenedIntegrity"] = try restored.verify()
      value["reopenedConversations"] = .array(try restored.conversations())
      value["tangentHistory"] = .array(
        try restored.conversations().filter { $0["id"].text != "main" }.map {
          .object([
            "conversation": $0,
            "messages": .array(try originalHistory(restored, conversation: $0["id"].text)),
          ])
        })
    }
    try Data(Value.object(value).json().utf8).write(
      to: root.appendingPathComponent("result.json"), options: .atomic)
  }

  do {
    try closedHistory(1)
    let recall = try await ask(
      "original",
      "What purchase code and original packing sample quantity and unit did I supply earlier? Preserve its decimal spelling. Did I specify a currency? Make no changes.",
      workbook: book)
    for token in ["MAPLE-27", "0.10", "kg"] { try expectEqual(recall.answer.contains(token), true) }
    try expectEqual(recall.citations.contains("message:" + original), true)
    try expectEqual(recall.answer.contains(where: { "$€£".contains($0) }), false)
    try expectEqual(try book.contextCheckpoints(limit: 100).count >= 1, true)

    try closedHistory(2)
    await model.arm(path: path, id: forecast.id, accept: true)
    let acceptedAnswer = try await ask(
      "accepted",
      "Inspect the current November forecast. Is it accepted, and does it represent an actual or an estimate? Make no changes.",
      workbook: book)
    let accepted = try book.item(forecast.logicalID)
    try expectEqual(accepted.status, "accepted")
    try expectEqual(accepted.meaning, "estimate")
    try expectEqual(acceptedAnswer.citations.contains(accepted.id), true)
    try expectEqual(acceptedAnswer.answer.lowercased().contains("estimate"), true)
    try expectEqual(acceptedAnswer.answer.lowercased().contains("accepted"), true)

    let latestText =
      "Correction for future packing: use exactly 0.25 kg per sample. The original sample was 0.10 kg. Keep purchase code MAPLE-27. Currency is still unspecified."
    let latest = try book.addMessage(latestText, role: "user")
    _ = try book.addMessage("Recorded the revised packing quantity.", role: "assistant")
    try closedHistory(3)
    await model.arm(path: path, id: accepted.id, accept: false)
    let withdrawnAnswer = try await ask(
      "withdrawn",
      "Inspect the current November forecast. Is it currently accepted or withdrawn? Does it represent an actual or an estimate? Make no changes.",
      workbook: book)
    let withdrawn = try book.item(forecast.logicalID)
    try expectEqual(withdrawn.status, "rejected")
    try expectEqual(withdrawn.meaning, "estimate")
    try expectEqual(withdrawnAnswer.citations.contains(withdrawn.id), true)
    try expectEqual(withdrawnAnswer.answer.lowercased().contains("estimate"), true)
    try expectEqual(
      withdrawnAnswer.answer.lowercased().contains("withdrawn")
        || withdrawnAnswer.answer.lowercased().contains("rejected"), true)

    let quantities = try await ask(
      "correction",
      "What packing sample quantity should I use now, and what was the original quantity? Include both units and preserve the decimal spellings. What is my purchase code, and did I choose a currency? Read the original messages. Make no changes.",
      workbook: book)
    for token in ["MAPLE-27", "0.10", "0.25", "kg"] {
      try expectEqual(quantities.answer.contains(token), true)
    }
    try expectEqual(quantities.citations.contains("message:" + latest), true)
    try expectEqual(quantities.answer.contains(where: { "$€£".contains($0) }), false)
    try expectEqual(try book.historyMessage(original).body, originalText)
    try expectEqual(try book.historyMessage(latest).body, latestText)
    for source in baselineSources {
      try expectEqual(try encoded(book.item(source.id)), encoded(source))
    }
    try expectEqual(try book.chapters().count, 18)
    try expectEqual(await model.edits.count, 2)
    try expectEqual(await model.summaries >= 3, true)
    try expectEqual(try book.contextCheckpoints(limit: 100).count >= 3, true)

    let archive = root.appendingPathComponent("Workflow.sevraz")
    try book.export(to: archive)
    let reopened = try Workbook.openArchive(
      archive, at: root.appendingPathComponent("Reopened.sevra"))
    restored = reopened
    try expectEqual(await model.releaseResources(), true)
    let inventory = try await ask(
      "reopened",
      "What is the current stock of brass bolts? Cite the opening balance and accepted movements. Make no changes.",
      workbook: reopened)
    try expectEqual(inventory.answer.contains("18"), true)
    let expected = Set(
      [baselineBalance["basis"].text] + baselineBalance["effects"].array.map { $0["item_id"].text })
    try expectEqual(Set(inventory.citations), expected)
    try expectEqual(try reopened.item(forecast.logicalID).id, withdrawn.id)
    try expectEqual(try reopened.historyMessage(original).body, originalText)
    try expectEqual(try reopened.historyMessage(latest).body, latestText)
    try expectEqual(try reopened.chapters().count, 18)
    let tangent = try reopened.tangent(title: "Packing follow-up", parentMessage: latest)
    let inherited = try await ask(
      "tangent",
      "From the parent information inherited by this tangent, what packing sample quantity should I use now, and what was the original quantity? Preserve both decimal spellings and units, and cite the original message. Make no changes.",
      workbook: reopened, conversation: tangent)
    for token in ["0.10", "0.25", "kg"] { try expectEqual(inherited.answer.contains(token), true) }
    try expectEqual(inherited.citations.contains("message:" + latest), true)
    try expectEqual(inherited.answer.contains("sevra://conversation/main?message=" + latest), true)
    let tangentReply = try expectValue(
      try reopened.messages(conversation: tangent).last {
        $0.role == "assistant" && $0.state == "complete"
      })
    let brought = try reopened.bringToMain(message: tangentReply.id)
    let broughtMessage = try reopened.historyMessage(brought)
    try expectEqual(broughtMessage.body.contains(tangentReply.body), true)
    try expectEqual(
      broughtMessage.body.contains(
        "sevra://conversation/" + tangent + "?message=" + tangentReply.id), true)
    try expectEqual(try reopened.balance(subject: "brass bolts"), baselineBalance)
    try expectEqual(try reopened.verify()["ok"], .bool(true))
    let unloaded = await model.releaseResources()
    try expectEqual(unloaded, true)
    try await save(nil, unloaded: unloaded)
    print(
      "PASS native repeated maintenance, concurrent forecast decisions, corrected quantities, portable stock and inherited tangent evidence"
    )
  } catch {
    let unloaded = await model.releaseResources()
    try await save(error, unloaded: unloaded)
    throw error
  }
}
