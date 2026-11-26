import AppKit
import SevraAI
import SevraCore
import SevraVoice

final class CatalogOpenPanel: NSOpenPanel {
  var selection: URL?
  override var url: URL? { selection }
  override var urls: [URL] { selection.map { [$0] } ?? [] }
  override func runModal() -> NSApplication.ModalResponse {
    selection == nil ? .cancel : .OK
  }
}
final class CatalogSavePanel: NSSavePanel {
  override var url: URL? {
    AppHost.root.appendingPathComponent("Exports", isDirectory: true).appendingPathComponent(
      nameFieldStringValue.isEmpty
        ? "Export" : URL(fileURLWithPath: nameFieldStringValue).lastPathComponent)
  }
  override func runModal() -> NSApplication.ModalResponse {
    try? FileManager.default.createDirectory(
      at: AppHost.root.appendingPathComponent("Exports"), withIntermediateDirectories: true)
    return .OK
  }
}
@MainActor final class CatalogDictation: DictationDriver {
  let mode: String
  init(mode: String = "Default") { self.mode = mode }
  func requestSpeechPermission(_ completion: @escaping @MainActor (Bool) -> Void) {
    completion(mode != "Denied")
  }
  func requestMicrophonePermission(_ completion: @escaping @MainActor (Bool) -> Void) {
    completion(mode != "Denied")
  }
  func begin(
    result: @escaping @MainActor (String, Bool) -> Void,
    failure: @escaping @MainActor (String) -> Void
  ) throws { result("um compare the supplier quotes compare the supplier quotes", mode != "Recording") }
  func stop() {}
}
/// Stands in for the on-device cleanup: drops "um" and a phrase said twice, and adds the
/// capital and full stop, so the catalog shows a cleanup without a model.
struct CatalogDictationCleaner: DictationCleaner {
  func clean(_ transcript: String) async throws -> String {
    var words = transcript.split(separator: " ").map(String.init).filter { $0 != "um" }
    let half = words.count / 2
    if words.count % 2 == 0, Array(words[..<half]) == Array(words[half...]) {
      words = Array(words[..<half])
    }
    let text = words.joined(separator: " ")
    return text.prefix(1).uppercased() + text.dropFirst() + "."
  }
}
/// Scripted tool calls still run through the production agent and workbook transaction paths.
actor CatalogInference: WorkbookInference {
  let identity = "Catalog scripted inference"
  /// Scripted figures in the engine's shape, different for each call, so a finished activity
  /// shows its writing speed. Sample numbers, not a measurement.
  private(set) var lastMetrics = Value.null
  private var answered = 0
  var calls: [(String, Value)]
  /// Scripted reasoning for each call in turn, shown as the model's thoughts.
  var thoughts: [String]
  let attachVisual: Bool
  init(_ calls: [(String, Value)] = [], thoughts: [String] = [], attachVisual: Bool = false) {
    self.calls = calls
    self.thoughts = thoughts
    self.attachVisual = attachVisual
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    try cancellation.check()
    answered += 1
    lastMetrics = .object([
      "backend": .string("splash"), "decodeTokens": .number(Double(30 + answered * 12)),
      "decodeSeconds": .number(0.8 + Double(answered) * 0.2),
      "requestSeconds": .number(1.5 + Double(answered) * 0.3),
    ])
    let next =
      calls.isEmpty
      ? (
        "finish",
        Value.object([
          "answer": .string(
            "This catalog uses scripted inference. This request has no model script; explore the native controls or advance the documented flow."
          ), "basis": .string("general"), "citations": .array([]),
        ])
      ) : calls.removeFirst()
    var arguments = next.1
    if attachVisual, next.0 == "finish" {
      var fields = arguments.object
      fields["visuals"] = .array(messages.first?.visualCaptureIDs.prefix(6).map(Value.string) ?? [])
      arguments = .object(fields)
    }
    return NativeReply(
      text: "", calls: [.init(id: UUID().uuidString, name: next.0, inputJSON: try arguments.json())],
      reasoning: thoughts.isEmpty ? "" : thoughts.removeFirst())
  }
}

/// Explicit failure/cancellation gate, released on teardown. Reset starts a fresh transport.
actor CatalogTransportGate {
  private var waiter: CheckedContinuation<Data, Error>?
  private var finished = false
  func wait() async throws -> Data {
    if finished {
      throw SevraError("catalog_transport", "Synthetic transport stopped. Reset to start again.")
    }
    return try await withCheckedThrowingContinuation { waiter = $0 }
  }
  func finish() {
    finished = true
    waiter?.resume(
      throwing: SevraError(
        "catalog_transport", "Synthetic transport interrupted. Restart or reset."))
    waiter = nil
  }
}
