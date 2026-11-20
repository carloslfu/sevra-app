import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash

/// Records the first decision a chat turn dispatches, then ends the turn there.
private actor FirstDecision: WorkbookInference {
  let identity = "prompt header check"
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
    .init(promptTokens: 1000, capacity: 65536, templateIdentity: "prompt-header-check")
  }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    if first == nil { first = (messages, toolScope) }
    throw SevraError("check_captured", "The first decision was captured.")
  }
}

private func expectHeader(_ condition: Bool, _ message: String) throws {
  guard condition else { throw SevraError("prompt_header_check", message) }
}

/// No model. The prepared header is named by inputs worked out without the model, so those
/// inputs must be exactly what real chat turns put first. Also: where each executable looks
/// for a header, its three states, the restore into the engine's cache folder, and the check
/// of the engine's status after a start.
func checkPromptHeader() async throws {
  let files = FileManager.default
  let root = files.temporaryDirectory.appendingPathComponent("sevra-header-" + UUID().uuidString)
  try files.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? files.removeItem(at: root) }
  let book = root.appendingPathComponent("Business.sevra")
  _ = try Demo.create(at: book)

  // 1. Real first decisions of ordinary chat in the app, a read-only request and the CLI.
  let expected = try PromptHeader.inputs(reasoning: .bounded512)
  for (prompt, conversationInput) in [
    ("How many brass bolts do we have?", true),
    ("Without changing anything, list the tables.", true),
    ("How many brass bolts do we have?", false),
  ] {
    let fixture = FirstDecision()
    _ = try? await WorkbookAgent.run(
      prompt, workbook: try Workbook(book), context: "Space: Home\nActive space ID: home",
      model: fixture, conversationInput: conversationInput)
    guard let first = await fixture.first else {
      throw SevraError("prompt_header_check", "No decision was dispatched for: " + prompt)
    }
    let inputs = try NativePreparedRequest.headerInputs(
      messages: first.messages, configuredReasoning: .bounded512, toolScope: first.scope)
    try expectHeader(
      inputs == expected,
      "A chat turn's header differs from the prepared one: " + prompt
        + " (conversation input \(conversationInput))")
  }
  try expectHeader(
    try PromptHeader.inputsDigest(reasoning: .bounded512)
      != (try PromptHeader.inputsDigest(reasoning: .off)),
    "The thinking switch is not part of the header's name.")

  // 2. Inside an app every executable uses the outermost app's folder; outside, the setting.
  let app = URL(fileURLWithPath: "/Applications/Sevra.app")
  for executable in [
    "Contents/MacOS", "Contents/CLI", "Contents/Helpers/Sevra CLI.app/Contents/MacOS",
  ] {
    try expectHeader(
      PromptHeader.location(
        executable: app.appendingPathComponent(executable), environment: ["SEVRA_PROMPT_HEADER": "/x"])
        == app.appendingPathComponent("Contents/Resources/PromptHeader"),
      "An executable inside the app looks elsewhere: " + executable)
  }
  let tree = URL(fileURLWithPath: "/tmp/build/bin")
  try expectHeader(
    PromptHeader.location(executable: tree, environment: ["SEVRA_PROMPT_HEADER": "/x/h"])
      == URL(fileURLWithPath: "/x/h")
      && PromptHeader.location(executable: tree, environment: [:]) == nil,
    "An executable outside an app does not follow its explicit setting.")

  // 3. Absent, present and matching, mismatched.
  let identity = try PromptHeader.Identity(
    engineSHA256: String(repeating: "e", count: 64), activations: "bf16", reasoning: .bounded512)
  let headers = root.appendingPathComponent("headers")
  try expectHeader(
    PromptHeader.state(at: headers, identity: identity) == .absent
      && PromptHeader.state(at: nil, identity: identity) == .absent,
    "A missing header is not reported as absent.")
  let folder = headers.appendingPathComponent(identity.inputs)
  try files.createDirectory(at: folder, withIntermediateDirectories: true)
  var entries: [String: PromptHeader.File] = [:]
  for name in PromptHeader.dataFiles {
    let bytes = Data(repeating: UInt8(name.count), count: 100 + name.count)
    try bytes.write(to: folder.appendingPathComponent(name))
    entries[name] = .init(bytes: bytes.count, sha256: String(repeating: "0", count: 64))
  }
  func manifest(engine: PromptHeader.Engine = identity.engine) -> PromptHeader.Manifest {
    .init(
      inputs: identity.inputs, tokens: 2572, tokenSHA256: String(repeating: "1", count: 64),
      lastCompletePage: 2560, cacheName: String(repeating: "2", count: 32), engine: engine,
      engineOptions: identity.engineOptions, model: identity.model,
      assemblyKey: String(repeating: "3", count: 64),
      takenBack: .init(states: 1, kvBlocks: 80, bytes: 94_273_536), files: entries)
  }
  func write(_ value: PromptHeader.Manifest) throws {
    try JSONEncoder().encode(value).write(to: folder.appendingPathComponent("manifest.json"))
  }
  try write(manifest())
  guard case .present(let found, let read) = PromptHeader.state(at: headers, identity: identity),
    found.path == folder.path, read == manifest()
  else {
    throw SevraError(
      "prompt_header_check",
      "A matching header is not found: \(PromptHeader.state(at: headers, identity: identity))")
  }
  try write(manifest(engine: .init(release: "1.6.1", commit: "0", sha256: identity.engine.sha256)))
  try expectHeader(
    PromptHeader.state(at: headers, identity: identity) == .mismatched("the engine"),
    "A header for another engine is not refused.")
  try write(manifest())
  try Data([1]).write(to: folder.appendingPathComponent("kv.slots"))
  try expectHeader(
    PromptHeader.state(at: headers, identity: identity) == .mismatched("a damaged file, kv.slots"),
    "A data file cut short is not refused.")
  try Data(repeating: 8, count: 108).write(to: folder.appendingPathComponent("kv.slots"))
  let other = headers.appendingPathComponent(String(repeating: "9", count: 64))
  try files.moveItem(at: folder, to: other)
  try expectHeader(
    PromptHeader.state(at: headers, identity: identity) == .mismatched("the instructions or tools"),
    "A header for other instructions is reported as absent.")
  try files.moveItem(at: other, to: folder)

  // 4. A restore empties the cache directory and places owner-only copies under the cache name.
  let cache = root.appendingPathComponent("cache")
  try files.createDirectory(
    at: cache.appendingPathComponent("conversation"), withIntermediateDirectories: true)
  try PromptHeader.restore(folder, manifest(), into: cache)
  let named = cache.appendingPathComponent(manifest().cacheName)
  try expectHeader(
    try files.contentsOfDirectory(atPath: cache.path) == [manifest().cacheName]
      && Set(try files.contentsOfDirectory(atPath: named.path)) == Set(PromptHeader.dataFiles),
    "A restore kept earlier files or missed one.")
  for (url, mode) in [(cache, 0o700), (named, 0o700), (named.appendingPathComponent("kv.slots"), 0o600)] {
    let attributes = try files.attributesOfItem(atPath: url.path)
    try expectHeader(
      (attributes[.posixPermissions] as? NSNumber)?.intValue == mode,
      "A restored path is not owner-only: " + url.lastPathComponent)
  }
  try expectHeader(
    try Data(contentsOf: named.appendingPathComponent("state.slots"))
      == Data(contentsOf: folder.appendingPathComponent("state.slots")),
    "A restored file differs from the app's.")

  // 5. After a start: every point taken back, some missing, or no disk cache at all.
  func status(_ persistent: Bool, _ states: Int, _ blocks: Int, _ left: Int) -> Value {
    .object([
      "disk": .object([
        "persistent": .bool(persistent),
        "taken_back": .object([
          "states": .number(Double(states)), "kv_blocks": .number(Double(blocks)),
          "left_behind": .number(Double(left)),
        ]),
      ])
    ])
  }
  try expectHeader(
    PromptHeader.check(status: status(true, 1, 80, 0), manifest()) == .whole
      && PromptHeader.check(status: status(true, 1, 79, 0), manifest()) == .short
      && PromptHeader.check(status: status(true, 1, 80, 1), manifest()) == .short
      && PromptHeader.check(status: status(true, 0, 0, 0), manifest()) == .short
      && PromptHeader.check(status: status(false, 0, 0, 0), manifest()) == .notPersistent,
    "The start check misreads the engine's status.")
  try expectHeader(
    PromptHeader.missing().code == "model_header"
      && PromptHeader.noDisk(manifest()).message.contains("13 GB"),
    "The header errors are not the documented ones.")
  print(
    "PASS the prepared header matches real chat turns, is found inside and outside an app, is refused when absent, mismatched or damaged, restores owner-only, and its start check reads the engine status"
  )
}
