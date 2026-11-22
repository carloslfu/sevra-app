import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraProduct
import SevraSplash
import SevraSplashText

/// A diagnostic with the real model, not a check: the app's first request, timed. The product's
/// model configuration is built from a packaged build, the engine starts ahead of the request as
/// the app starts it when a workbook opens, and then "hi" and a follow-up, or the given prompts,
/// are sent as composer input in a new chat of a copy of a workbook, with the context the app
/// sends from Home. SEVRA_TRACE_PAUSE waits that many seconds after opening and between turns,
/// as a person reads and types. Run with SEVRA_PROMPT_HEADER set to the build's header folder,
/// and SEVRA_CHAT_TIMING=1 to log every step (scripts/chat_timing.py reads it).
func firstRequestTrace(
  modelsRoot: String, packagedBin: String, workbook: String, prompts: [String] = ["hi", "ho"]
) async throws {
  try SplashModelSetup.checkHardware()
  let resources = URL(fileURLWithPath: packagedBin).standardizedFileURL
  let manifest = try Value.parse(
    String(contentsOf: resources.appendingPathComponent("native-runtime.json")))
  let models = URL(fileURLWithPath: modelsRoot)
  let model = NativeWorkbookModel(
    configuration: .init(
      engine: resources.appendingPathComponent("NativeRuntime/engine/splash"),
      engineFiles: manifest["engineFiles"].object.mapValues(\.text),
      grammarLibrary: resources.appendingPathComponent("NativeRuntime/libllguidance.dylib"),
      grammarSHA256: manifest["grammarSHA256"].text,
      modelsRoot: models, memoryBytes: 12 * 1024 * 1024 * 1024,
      contextBudget: .init(profile: .evaluation64K), reasoning: .bounded512,
      modelLayout: .installed, contextMaintenanceEnabled: true))
  let service = ProductAI(qualifying: model)
  let book = try Workbook(URL(fileURLWithPath: workbook))
  let start = ProcessInfo.processInfo.systemUptime
  func mark(_ text: String) {
    print(String(format: "%7.3f  %@", ProcessInfo.processInfo.systemUptime - start, text))
  }
  // A new chat, as the person starts one.
  let chat = try book.createChat()
  mark("workbook open, new chat " + chat.prefix(8))

  // As the app does when a workbook opens. A request sent before it finishes waits for it.
  await service.prewarm(modelDirectory: models)
  mark("engine start begun ahead of the request")
  let pause = Double(ProcessInfo.processInfo.environment["SEVRA_TRACE_PAUSE"] ?? "") ?? 0
  for prompt in prompts {
    if pause > 0 { try await Task.sleep(nanoseconds: UInt64(pause * 1e9)) }
    let sent = ProcessInfo.processInfo.systemUptime
    mark("send " + prompt)
    let result = try await service.run(
      prompt, workbook: book, conversation: chat, context: "Space: Home\nActive space ID: home",
      modelDirectory: models, progress: { mark("  progress " + $0) }, conversationInput: true)
    mark(
      String(
        format: "answer after %.2f s, %d steps: %@", ProcessInfo.processInfo.systemUptime - sent,
        result.steps, result.answer))
  }
  _ = await service.unload()
  mark("unloaded")
}

/// Records the first decision a turn dispatches, then stops the turn there.
private actor CapturedDecision: WorkbookInference {
  let identity = "prompt capture"
  let lastMetrics: Value = .null
  private(set) var first: (messages: [InferenceMessage], scope: InferenceToolScope)?
  func beginRun() {}
  func endRun() {}
  var supportsCompaction: Bool { true }
  func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, toolScope: InferenceToolScope, citationIDs: [String],
    progress: @escaping @Sendable (String) -> Void
  ) throws -> ContextMeasurement {
    .init(promptTokens: 1000, capacity: 65536, templateIdentity: "prompt-capture")
  }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    if first == nil { first = (messages, toolScope) }
    throw SevraError("captured", "The first decision was captured.")
  }
}

/// No model: prints what a composer turn's first decision reads after the prepared header.
func firstRequestPrompt(tokenizer: String, workbook: String) async throws {
  let frontend = try SplashTextFrontend(modelFolder: URL(fileURLWithPath: tokenizer))
  let book = try Workbook(URL(fileURLWithPath: workbook))
  let capture = CapturedDecision()
  _ = try? await WorkbookAgent.run(
    "hi", workbook: book, context: "", model: capture, conversationInput: true)
  guard let first = await capture.first else { throw SevraError("trace", "Nothing dispatched.") }
  let prepared = try NativePreparedRequest(
    messages: first.messages, frontend: frontend, configuredReasoning: .bounded512,
    toolScope: first.scope, citationIDs: [])
  let rest = Array(prepared.prompt.tokens.dropFirst(prepared.stablePrefixCount))
  print("header \(prepared.stablePrefixCount) tokens, then \(rest.count):")
  print(frontend.decode(rest))
}
