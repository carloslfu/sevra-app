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
  ) throws { result("Compare the supplier quotes", mode != "Recording") }
  func stop() {}
}
/// Scripted tool calls still run through the production agent and workbook transaction paths.
actor CatalogInference: WorkbookInference {
  let identity = "Catalog scripted inference"
  let lastMetrics = Value.null
  var calls: [(String, Value)]
  let attachVisual: Bool
  init(_ calls: [(String, Value)] = [], attachVisual: Bool = false) {
    self.calls = calls
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
      text: "", calls: [.init(id: UUID().uuidString, name: next.0, inputJSON: try arguments.json())]
    )
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
