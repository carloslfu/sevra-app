import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash
import SevraSplashText

private final class FollowupRequestLog: @unchecked Sendable {
  private let lock = NSLock()
  private var rows: [Value] = []
  func append(_ value: Value) {
    lock.lock()
    rows.append(value)
    lock.unlock()
  }
  var all: [Value] {
    lock.lock()
    defer { lock.unlock() }
    return rows
  }
}

private final class FollowupPreviews: @unchecked Sendable {
  private let lock = NSLock()
  private let started: Double
  private var first: Double?
  private var events: [Value] = []
  init(started: Double) { self.started = started }
  func progress(_ text: String) {
    lock.lock()
    defer { lock.unlock() }
    events.append(.object([
      "seconds": .number(ProcessInfo.processInfo.systemUptime - started), "status": .string(text),
    ]))
  }
  func receive(_ value: AnswerPreview) {
    lock.lock()
    defer { lock.unlock() }
    if value.text?.isEmpty == false && first == nil {
      first = ProcessInfo.processInfo.systemUptime - started
    }
  }
  var firstSeconds: Value {
    lock.lock()
    defer { lock.unlock() }
    return first.map(Value.number) ?? .null
  }
  var progressEvents: [Value] {
    lock.lock()
    defer { lock.unlock() }
    return events
  }
}

/// Opt-in, actual model. One cold model instance and a fresh synthetic demo workbook, then
/// each prompt in order as one conversation, 15 seconds apart. Records each dispatched
/// prompt's exact tokens, the longest prefix any earlier prompt and output shared with it,
/// and where they diverged, so resumed versus recomputed tokens can be checked per call.
func runFollowupCacheTrace(
  modelsRoot: String, library: String, engine: String, output: String, prompts: [String]
) async throws {
  let root = URL(fileURLWithPath: output)
  try require(
    !FileManager.default.fileExists(atPath: output), "fixture", "Use a new output directory")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let base = try nativeProbeConfiguration(
    library: library, engine: engine, modelsRoot: modelsRoot,
    budget: .init(profile: .evaluation64K), reasoning: .bounded512, modelLayout: .installed)
  let log = FollowupRequestLog()
  let configuration = NativeWorkbookModel.Configuration(
    engine: base.engine, engineFiles: base.engineFiles, grammarLibrary: base.grammarLibrary,
    grammarSHA256: base.grammarSHA256, modelsRoot: base.modelsRoot,
    memoryBytes: base.memoryBytes, contextBudget: base.contextBudget, reasoning: base.reasoning,
    modelLayout: base.modelLayout, contextMaintenanceEnabled: true,
    observeRequest: { log.append($0) }, toolProfile: base.toolProfile)
  let model = NativeWorkbookModel(configuration: configuration)
  let bookURL = root.appendingPathComponent("Business.sevra")
  _ = try Demo.create(at: bookURL)
  let book = try Workbook(bookURL)
  var turns: [Value] = []
  for (index, prompt) in prompts.enumerated() {
    if index > 0 { try await Task.sleep(nanoseconds: 15_000_000_000) }
    let firstRequest = log.all.count
    let started = ProcessInfo.processInfo.systemUptime
    let previews = FollowupPreviews(started: started)
    let result = try await WorkbookAgent.run(
      prompt, workbook: book, context: "Space: Home\nActive space ID: home",
      modelDirectory: URL(fileURLWithPath: modelsRoot),
      cancellation: .init(deadlineAfterSeconds: 300),
      progress: { previews.progress($0) }, answerPreview: { previews.receive($0) },
      model: model, conversationInput: true)
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    let runMetrics = try book.agentRuns().first?["metrics"] ?? .null
    let turn: Value = .object([
      "turn": .number(Double(index + 1)), "prompt": .string(prompt),
      "wallSeconds": .number(elapsed), "firstVisibleSeconds": previews.firstSeconds,
      "answer": .string(result.answer), "citations": .array(result.citations.map(Value.string)),
      "steps": .number(Double(result.steps)), "state": .string(result.state),
      "requestIndexes": .array(
        (firstRequest..<log.all.count).map { .number(Double($0)) }),
      "runMetrics": runMetrics, "progress": .array(previews.progressEvents),
    ])
    turns.append(turn)
    print(try turn.json())
    try Data(Value.array(turns).json().utf8).write(
      to: root.appendingPathComponent("turns.json"), options: .atomic)
  }
  _ = await model.unload()

  // Analysis after the helper is gone: tokenizer only.
  let assembly = try SplashModelPreparation.installed(
    pack: SplashModelPack.selected(), modelsRoot: URL(fileURLWithPath: modelsRoot))
  let frontend = try SplashTextFrontend(modelFolder: assembly.appendingPathComponent("tokenizer"))
  func tokens(_ value: Value) -> [UInt32] { value.array.map { UInt32($0.int ?? 0) } }
  func common(_ a: [UInt32], _ b: [UInt32]) -> Int {
    var i = 0
    while i < a.count && i < b.count && a[i] == b[i] { i += 1 }
    return i
  }
  var sequences: [[UInt32]] = []
  var analysis: [Value] = []
  for (k, request) in log.all.enumerated() {
    let prompt = tokens(request["promptTokens"])
    let generated = tokens(request["tokens"])
    try Data(frontend.decode(prompt).utf8).write(
      to: root.appendingPathComponent("request-\(k)-prompt.txt"))
    try Data(frontend.decode(generated).utf8).write(
      to: root.appendingPathComponent("request-\(k)-generated.txt"))
    var bestIndex = -1
    var best = 0
    for (j, sequence) in sequences.enumerated() {
      let shared = common(prompt, sequence)
      if shared >= best { best = shared; bestIndex = j }
    }
    var divergence: Value = .null
    if bestIndex >= 0 {
      let other = sequences[bestIndex]
      let from = max(0, best - 40)
      divergence = .object([
        "sharedTail": .string(frontend.decode(Array(prompt[from..<best]))),
        "thisPromptContinues": .string(
          frontend.decode(Array(prompt[best..<min(prompt.count, best + 160)]))),
        "earlierSequenceContinued": .string(
          frontend.decode(Array(other[best..<min(other.count, best + 160)]))),
      ])
    }
    let previous = sequences.last
    analysis.append(.object([
      "request": .number(Double(k)),
      "promptTokens": .number(Double(prompt.count)),
      "generatedTokens": .number(Double(generated.count)),
      "longestSharedWithEarlierSequence": .number(Double(best)),
      "earlierRequest": .number(Double(bestIndex)),
      "sharedWithPreviousPrompt": previous.map {
        .number(Double(common(prompt, Array($0.prefix(prompt.count)))))
      } ?? .null,
      "previousPromptTokens": k > 0
        ? .number(Double(tokens(log.all[k - 1]["promptTokens"]).count)) : .null,
      "divergence": divergence,
      "metrics": request["metrics"],
    ]))
    sequences.append(prompt + generated)
  }
  try Data(Value.object(["turns": .array(turns), "requests": .array(analysis)]).json().utf8)
    .write(to: root.appendingPathComponent("trace.json"), options: .atomic)
  print("TRACE COMPLETE " + root.path)
}
