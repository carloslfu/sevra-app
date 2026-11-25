import CryptoKit
import Darwin
import Foundation
import SevraAI
import SevraCore
import SevraSplash
import SevraSplashText

/// The ordinary chat header: the instructions and tool declarations every ordinary chat turn
/// starts with. `sevra header make` reads it once into the engine's disk cache, and the app
/// restores those files before every engine start. The app never computes it (P6).
package enum PromptHeader {
  package static let dataFiles = ["kv.records", "kv.slots", "state.records", "state.slots"]
  /// The engine's disk quota: the header and a conversation that fills the context, which left
  /// 1.76 GB of files at 61K tokens (phase H1).
  package static let quotaBytes: UInt64 = 8 << 30
  /// The engine keeps 10 GiB of its volume free. The header and a conversation go above that.
  package static func requiredFreeBytes(_ manifest: Manifest) -> UInt64 {
    (12 << 30) + UInt64(manifest.dataBytes)
  }
  package static let release = "1.7.2"
  package static let commit = "2afc7337aacc044722fa95e4cb3da75c281a19a8"

  /// The launch options the app starts the engine with. The context, memory and quota are not
  /// among them: a header made at 64K is taken back at 32K (phase H1).
  /// The app runs one request at a time, so it asks for one lane: Splash 1.7.2 gives every
  /// lane a 16-row verify arena, and one lane leaves the expert store more of the budget.
  package static func engineOptions(activations: String) -> [String] {
    [
      "--idle-sleep", "allow", "--verify-rows", "all", "--kv-format", "int8",
      "--state-format", "fp32", "--ane", "on", "--activations", activations,
      "--max-concurrent-requests", "1",
    ]
  }

  /// Options that change neither what a restore point holds nor the numbers it was computed
  /// with: how many rows a decode cycle verifies, how many lanes serve, and whether an idle
  /// engine sleeps. Splash 1.7.2's cache namespace leaves them out too, so a header made under
  /// other values of them is taken back whole.
  package static let restoreNeutralOptions: Set<String> = [
    "--verify-rows", "--max-concurrent-requests", "--idle-sleep",
  ]
  /// `options` without the restore-neutral ones and their values: what a header depends on.
  package static func restoreOptions(_ options: [String]) -> [String] {
    var kept: [String] = []
    var index = options.startIndex
    while index < options.endIndex {
      if restoreNeutralOptions.contains(options[index]) {
        index += 2
      } else {
        kept.append(options[index])
        index += 1
      }
    }
    return kept
  }

  /// The first decision of an ordinary chat turn, reduced to what its header depends on.
  /// `PromptHeaderChecks` compares it with real turns of every chat scope.
  package static var ordinaryMessages: [InferenceMessage] {
    var system = InferenceMessage(
      role: "system", content: GeneralTools.instructions)
    system.cacheablePolicy = system.content
    system.initialChatDecision = true
    system.conversationInput = true
    return [system, InferenceMessage(role: "user", content: "Hello")]
  }
  /// The header's inputs as canonical JSON: worked out without the model.
  package static func inputs(reasoning: NativeReasoning) throws -> Data {
    guard
      let inputs = try NativePreparedRequest.headerInputs(
        messages: ordinaryMessages, configuredReasoning: reasoning, toolScope: .all)
    else { throw SevraError("model_header", "An ordinary chat turn has no shared header.") }
    return inputs
  }
  /// Names the header's folder.
  package static func inputsDigest(reasoning: NativeReasoning) throws -> String {
    hex(SHA256.hash(data: try inputs(reasoning: reasoning)))
  }
  /// The header's tokens, from the model's own tokenizer and chat template.
  package static func tokens(frontend: SplashTextFrontend, reasoning: NativeReasoning) throws
    -> [UInt32]
  {
    let prepared = try NativePreparedRequest(
      messages: ordinaryMessages, frontend: frontend, configuredReasoning: reasoning,
      toolScope: .all, citationIDs: [])
    try require(
      prepared.stablePrefixCount >= 64, "model_header", "An ordinary chat turn has no shared header.")
    return Array(prepared.prompt.tokens.prefix(prepared.stablePrefixCount))
  }
  /// The engine keeps a restore point on the last complete 32-token page of a prompt start.
  package static func lastCompletePage(_ tokens: Int) -> Int { (tokens - 1) / 32 * 32 }
  package static func tokenDigest(_ tokens: [UInt32]) -> String {
    hex(SHA256.hash(data: tokens.withUnsafeBufferPointer { Data(buffer: $0) }))
  }

  package struct Engine: Codable, Equatable, Sendable {
    package let release: String
    package let commit: String
    package let sha256: String
    package init(release: String, commit: String, sha256: String) {
      self.release = release
      self.commit = commit
      self.sha256 = sha256
    }
  }
  package struct Model: Codable, Equatable, Sendable {
    package let pack: String
    package let target: String
    package let draft: String
    package init(_ pack: SplashModelPack) {
      self.pack = pack.name
      target = pack.target.repository + "@" + pack.target.revision
      draft = pack.draft.repository + "@" + pack.draft.revision
    }
  }
  package struct File: Codable, Equatable, Sendable {
    package let bytes: Int
    package let sha256: String
    package init(bytes: Int, sha256: String) {
      self.bytes = bytes
      self.sha256 = sha256
    }
  }
  package struct TakenBack: Codable, Equatable, Sendable {
    package let states: Int
    package let kvBlocks: Int
    package let bytes: Int
    package init(states: Int, kvBlocks: Int, bytes: Int) {
      self.states = states
      self.kvBlocks = kvBlocks
      self.bytes = bytes
    }
  }
  /// What a build needs a header to be: everything known without the model.
  package struct Identity: Equatable, Sendable {
    package let inputs: String
    package let engine: Engine
    package let engineOptions: [String]
    package let model: Model
    package init(engineSHA256: String, activations: String, reasoning: NativeReasoning) throws {
      inputs = try PromptHeader.inputsDigest(reasoning: reasoning)
      engine = .init(release: PromptHeader.release, commit: PromptHeader.commit, sha256: engineSHA256)
      engineOptions = PromptHeader.engineOptions(activations: activations)
      model = .init(try SplashModelPack.selected())
    }
  }
  package struct Manifest: Codable, Equatable, Sendable {
    package var version = 1
    package let inputs: String
    package let tokens: Int
    package let tokenSHA256: String
    package let lastCompletePage: Int
    package let cacheName: String
    package let engine: Engine
    package let engineOptions: [String]
    package let model: Model
    package let assemblyKey: String
    package let takenBack: TakenBack
    package let files: [String: File]
    package init(
      inputs: String, tokens: Int, tokenSHA256: String, lastCompletePage: Int, cacheName: String,
      engine: Engine, engineOptions: [String], model: Model, assemblyKey: String,
      takenBack: TakenBack, files: [String: File]
    ) {
      self.inputs = inputs
      self.tokens = tokens
      self.tokenSHA256 = tokenSHA256
      self.lastCompletePage = lastCompletePage
      self.cacheName = cacheName
      self.engine = engine
      self.engineOptions = engineOptions
      self.model = model
      self.assemblyKey = assemblyKey
      self.takenBack = takenBack
      self.files = files
    }
    package var dataBytes: Int { files.values.reduce(0) { $0 + $1.bytes } }
    /// Why this header does not fit the build, or nil when it does.
    package func mismatch(_ identity: Identity) -> String? {
      if version != 1 { return "its format" }
      if inputs != identity.inputs { return "the instructions or tools" }
      // A release signs the engine again, which changes its file digest but not its code.
      // The release and commit name the code; the build verifies its files against them.
      if engine.release != identity.engine.release || engine.commit != identity.engine.commit {
        return "the engine"
      }
      if PromptHeader.restoreOptions(engineOptions)
        != PromptHeader.restoreOptions(identity.engineOptions)
      {
        return "the engine settings"
      }
      if model != identity.model { return "the model" }
      return nil
    }
  }

  /// Where this executable finds headers. Every executable inside an app, the command line
  /// tool in `Contents/CLI` or in a helper app included, uses the outermost app's
  /// `Contents/Resources/PromptHeader`. Anything else uses `SEVRA_PROMPT_HEADER`, or has none.
  package static func location(
    executable: URL = SplashRuntimeResources.executableDirectory,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> URL? {
    var url = executable.standardizedFileURL
    var app: URL?
    while url.pathComponents.count > 1 {
      if url.pathExtension == "app" { app = url }
      url.deleteLastPathComponent()
    }
    if let app { return app.appendingPathComponent("Contents/Resources/PromptHeader") }
    return environment["SEVRA_PROMPT_HEADER"].flatMap {
      $0.isEmpty ? nil : URL(fileURLWithPath: $0)
    }
  }

  package enum State: Equatable, Sendable {
    case present(URL, Manifest)
    case absent
    case mismatched(String)
    package var report: Value {
      switch self {
      case .present(_, let manifest):
        return .object([
          "state": .string("present"), "inputs": .string(manifest.inputs),
          "tokens": .number(Double(manifest.tokens)),
          "bytes": .number(Double(manifest.dataBytes)),
        ])
      case .absent: return .object(["state": .string("absent")])
      case .mismatched(let reason):
        return .object(["state": .string("mismatched"), "reason": .string(reason)])
      }
    }
  }
  /// Present and matching, absent, or mismatched, without the model.
  package static func state(at location: URL?, identity: Identity) -> State {
    guard let location else { return .absent }
    let folder = location.appendingPathComponent(identity.inputs)
    guard
      let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
      let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
    else {
      let others = (try? FileManager.default.contentsOfDirectory(atPath: location.path)) ?? []
      return others.contains { $0.count == 64 } ? .mismatched("the instructions or tools") : .absent
    }
    if let reason = manifest.mismatch(identity) { return .mismatched(reason) }
    for name in dataFiles {
      var status = stat()
      guard lstat(folder.appendingPathComponent(name).path, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFREG,
        Int(status.st_size) == manifest.files[name]?.bytes
      else { return .mismatched("a damaged file, " + name) }
    }
    return .present(folder, manifest)
  }

  package static func missing(_ reason: String? = nil) -> SevraError {
    SevraError(
      "model_header",
      "This copy of Sevra has no prepared prompt for the local AI"
        + (reason.map { " that matches " + $0 } ?? "")
        + ". Install Sevra again. In a source build, run bash scripts/install.sh again once the model is downloaded, or run sevra header make."
    )
  }
  package static func damaged() -> SevraError {
    SevraError(
      "model_header",
      "The prepared prompt in this copy of Sevra did not load, so the local AI is unavailable. Install Sevra again."
    )
  }
  package static func noDisk(_ manifest: Manifest) -> SevraError {
    let gigabytes = Int((Double(requiredFreeBytes(manifest)) / 1e9).rounded(.up))
    return SevraError(
      "model_disk",
      "The local AI needs about \(gigabytes) GB free on this Mac's startup disk for its prompt cache. Free some space, then try again."
    )
  }

  /// Free space on the volume that holds `folder`, as the engine counts it: without purgeable
  /// space.
  package static func freeBytes(_ folder: URL) -> UInt64 {
    var info = statfs()
    var url = folder
    while statfs(url.path, &info) != 0 && url.pathComponents.count > 1 { url.deleteLastPathComponent() }
    return UInt64(info.f_bavail) * UInt64(info.f_bsize)
  }

  /// Empties the cache directory and puts the header's four files in the folder the engine
  /// names its cache, as copy-on-write clones where the volume allows.
  package static func restore(_ header: URL, _ manifest: Manifest, into cache: URL) throws {
    let files = FileManager.default
    if files.fileExists(atPath: cache.path) { try files.removeItem(at: cache) }
    let ownerOnly: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
    try files.createDirectory(
      at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
    try files.createDirectory(at: cache, withIntermediateDirectories: false, attributes: ownerOnly)
    let folder = cache.appendingPathComponent(manifest.cacheName)
    try files.createDirectory(at: folder, withIntermediateDirectories: false, attributes: ownerOnly)
    for name in dataFiles {
      let source = header.appendingPathComponent(name)
      let target = folder.appendingPathComponent(name)
      if clonefile(source.path, target.path, 0) != 0 {
        try files.copyItem(at: source, to: target)
      }
      chmod(target.path, 0o600)
    }
  }

  package enum Restored: Equatable { case whole, short, notPersistent }
  /// After Ready: the engine took back every restore point the header holds, from its own disk.
  package static func check(status: Value, _ manifest: Manifest) -> Restored {
    let disk = status["disk"]
    guard disk["persistent"] == .bool(true) else { return .notPersistent }
    let taken = disk["taken_back"]
    return (taken["states"].int ?? 0) >= manifest.takenBack.states
      && (taken["kv_blocks"].int ?? 0) >= manifest.takenBack.kvBlocks
      && taken["left_behind"].int == 0 ? .whole : .short
  }

  /// The launch arguments of every engine start that uses the header.
  package static func arguments(
    assembly: URL, contextTokens: Int, memoryBytes: UInt64, cache: URL, activations: String
  ) -> [String] {
    [
      "serve-native", assembly.path, String(contextTokens), String(memoryBytes),
      String(quotaBytes), "--persistent-cache", "on", "--cache-dir", cache.path,
    ] + engineOptions(activations: activations)
  }

  /// One model process on this Mac: no other engine helper, and enough reclaimable memory.
  package static func admitModelLoad(minimumBytes: Double = 16 * 1_073_741_824) throws {
    func run(_ tool: String, _ arguments: [String]) throws -> String {
      let process = Process()
      let pipe = Pipe()
      process.executableURL = URL(fileURLWithPath: tool)
      process.arguments = arguments
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      try process.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      return String(decoding: data, as: UTF8.self)
    }
    try require(
      try run("/usr/bin/pgrep", ["-x", "splash"]).trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty, "model_busy",
      "Another local AI engine is running. Quit Sevra or wait for it to finish, then try again.")
    let report = try run("/usr/bin/vm_stat", [])
    func figure(_ label: String) -> Double {
      guard let range = report.range(of: label) else { return 0 }
      return Double(report[range.upperBound...].drop { !$0.isNumber }.prefix { $0.isNumber }) ?? 0
    }
    let reclaimable =
      (figure("Pages free:") + figure("Pages purgeable:") + figure("File-backed pages:"))
      * figure("page size of")
    try require(
      reclaimable >= minimumBytes, "memory",
      String(
        format: "Reclaimable memory is %.1f GB, under the %.0f GB a model load needs. Close other apps, then try again.",
        reclaimable / 1e9, minimumBytes / 1e9))
  }

  /// SIGTERM and the engine's own exit, so a clean stop writes its waiting restore points.
  package static func stopCleanly(_ helper: SplashNativeProcess) throws {
    let started = ProcessInfo.processInfo.systemUptime
    try require(Darwin.kill(helper.processID, SIGTERM) == 0, "model_header", "Cannot stop the engine.")
    while helper.isOpen {
      try require(
        ProcessInfo.processInfo.systemUptime - started < 120, "model_header",
        "The engine did not stop within 120 seconds.")
      usleep(50_000)
    }
    helper.close()
  }

  package static func hex(_ digest: SHA256.Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
  }
  package static func fileDigest(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while try autoreleasepool(invoking: { () throws -> Bool in
      guard let bytes = try handle.read(upToCount: 1 << 20), !bytes.isEmpty else { return false }
      hash.update(data: bytes)
      return true
    }) {}
    return hex(hash.finalize())
  }

  /// Makes the header for this build into `output/<inputs digest>/`, or finds it there.
  ///
  /// Starts the engine with the app's own launch arguments in a fresh cache directory, sends
  /// the header as a request of one token and waits for the engine's own exit, so the restore
  /// point is written. Then restores the files into a new directory, starts again and requires
  /// the engine to take the point back and a request to resume the header. Only then does it
  /// write the four files and the manifest.
  package static func make(
    identity: Identity, output: URL, engine: URL, assembly: URL, frontend: SplashTextFrontend,
    reasoning: NativeReasoning, activations: String, contextTokens: Int, memoryBytes: UInt64,
    progress: (String) -> Void = { _ in }
  ) throws -> (URL, Manifest) {
    let files = FileManager.default
    if case .present(let folder, let manifest) = state(at: output, identity: identity),
      manifest.assemblyKey == assemblyKey(assembly)
    {
      return (folder, manifest)
    }
    let header = try tokens(frontend: frontend, reasoning: reasoning)
    let page = lastCompletePage(header.count)
    try files.createDirectory(at: output, withIntermediateDirectories: true)
    let work = output.appendingPathComponent(".make-" + UUID().uuidString)
    let ownerOnly: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
    try files.createDirectory(at: work, withIntermediateDirectories: false, attributes: ownerOnly)
    defer { try? files.removeItem(at: work) }
    let cache = work.appendingPathComponent("cache")
    try files.createDirectory(at: cache, withIntermediateDirectories: false, attributes: ownerOnly)
    let arguments = Self.arguments(
      assembly: assembly, contextTokens: contextTokens, memoryBytes: memoryBytes, cache: cache,
      activations: activations)
    var requestID: UInt64 = 0
    func send(_ helper: SplashNativeProcess) throws -> Int {
      requestID += 1
      var request = SplashWire.Request(
        id: requestID, prompt: header,
        absoluteDeadline: UInt64((Date().timeIntervalSince1970 + 300) * 1e6),
        remainingDeadline: 300_000_000)
      request.maxOutput = 1
      var matched = 0
      _ = try helper.generate(
        request, timeout: 300,
        event: { if case .start(let start) = $0 { matched = Int(start.matched) } })
      return matched
    }
    func start() throws -> SplashNativeProcess {
      try admitModelLoad()
      return try SplashNativeProcess(executable: engine, arguments: arguments, timeout: 360)
    }

    progress("Reading the prompt header, \(header.count) tokens")
    let first = try start()
    defer { first.close() }
    _ = try send(first)
    try stopCleanly(first)
    let names = try files.contentsOfDirectory(atPath: cache.path).filter {
      $0.count == 32 && $0.allSatisfy(\.isHexDigit)
    }
    try require(names.count == 1, "model_header", "The engine left no single cache folder.")
    let written = work.appendingPathComponent("files")
    try files.createDirectory(at: written, withIntermediateDirectories: false, attributes: ownerOnly)
    var entries: [String: File] = [:]
    for name in dataFiles {
      let source = cache.appendingPathComponent(names[0]).appendingPathComponent(name)
      try files.copyItem(at: source, to: written.appendingPathComponent(name))
      chmod(written.appendingPathComponent(name).path, 0o600)
      let size = (try files.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.intValue ?? 0
      entries[name] = .init(bytes: size, sha256: try fileDigest(written.appendingPathComponent(name)))
    }

    progress("Checking that the engine takes the header back")
    var manifest = Manifest(
      inputs: identity.inputs, tokens: header.count, tokenSHA256: tokenDigest(header),
      lastCompletePage: page, cacheName: names[0], engine: identity.engine,
      engineOptions: identity.engineOptions, model: identity.model,
      assemblyKey: assemblyKey(assembly), takenBack: .init(states: 1, kvBlocks: 1, bytes: 0),
      files: entries)
    try restore(written, manifest, into: cache)
    let second = try start()
    defer { second.close() }
    let status = try Value.parse(String(decoding: second.status(id: UInt64.max), as: UTF8.self))
    try require(
      check(status: status, manifest) == .whole, "model_header",
      "The engine did not take the header back from its files.")
    let taken = status["disk"]["taken_back"]
    manifest = Manifest(
      inputs: manifest.inputs, tokens: manifest.tokens, tokenSHA256: manifest.tokenSHA256,
      lastCompletePage: page, cacheName: manifest.cacheName, engine: manifest.engine,
      engineOptions: manifest.engineOptions, model: manifest.model,
      assemblyKey: manifest.assemblyKey,
      takenBack: .init(
        states: taken["states"].int ?? 0, kvBlocks: taken["kv_blocks"].int ?? 0,
        bytes: taken["bytes"].int ?? 0), files: entries)
    let matched = try send(second)
    try require(
      matched >= page, "model_header",
      "The engine read the header again instead of resuming it (\(matched) of \(page) tokens).")
    second.close()

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(to: written.appendingPathComponent("manifest.json"))
    let folder = output.appendingPathComponent(identity.inputs)
    if files.fileExists(atPath: folder.path) { try files.removeItem(at: folder) }
    try files.moveItem(at: written, to: folder)
    return (folder, manifest)
  }

  /// The digest of the assembly's model.json, the first part of its folder name.
  package static func assemblyKey(_ assembly: URL) -> String {
    String(assembly.lastPathComponent.prefix(64))
  }
}
