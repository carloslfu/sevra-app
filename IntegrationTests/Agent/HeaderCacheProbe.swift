import CryptoKit
import Darwin
import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash
import SevraSplashText

/// Records the first decision an ordinary chat turn dispatches, then ends the turn there.
private actor HeaderCaptureFixture: WorkbookInference {
  let identity = "header capture fixture"
  let lastMetrics: Value = .null
  private(set) var first:
    (messages: [InferenceMessage], scope: InferenceToolScope, citations: [String])?
  func beginRun() {}
  func endRun() {}
  // The native model maintains context; keep the same message shape.
  var supportsCompaction: Bool { true }
  func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, toolScope: InferenceToolScope, citationIDs: [String],
    progress: @escaping @Sendable (String) -> Void
  ) throws -> ContextMeasurement {
    .init(promptTokens: 1000, capacity: 65536, templateIdentity: "header-capture")
  }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) throws -> NativeReply {
    if first == nil { first = (messages, toolScope, citationIDs) }
    throw SevraError("probe_captured", "The first chat decision was captured.")
  }
}

private func hex(_ digest: SHA256.Digest) -> String {
  digest.map { String(format: "%02x", $0) }.joined()
}

private func fileDigest(_ url: URL) throws -> String {
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

/// A plain read-and-write copy, as a file unpacked from a disk image arrives: a new file with
/// the same bytes, not a clone of the engine's own.
private func copyBytes(from source: URL, to target: URL) throws -> String {
  let input = try FileHandle(forReadingFrom: source)
  defer { try? input.close() }
  try require(
    FileManager.default.createFile(
      atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600]),
    "probe", "Cannot create " + target.lastPathComponent)
  let output = try FileHandle(forWritingTo: target)
  defer { try? output.close() }
  var hash = SHA256()
  while try autoreleasepool(invoking: { () throws -> Bool in
    guard let bytes = try input.read(upToCount: 1 << 20), !bytes.isEmpty else { return false }
    hash.update(data: bytes)
    try output.write(contentsOf: bytes)
    return true
  }) {}
  try output.synchronize()
  return hex(hash.finalize())
}

/// Each entry's name, mode, length and the bytes its blocks take on the volume.
private func listing(_ folder: URL) throws -> [Value] {
  try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted().map { name in
    var status = stat()
    try require(
      lstat(folder.appendingPathComponent(name).path, &status) == 0, "probe", "Cannot read " + name)
    return .object([
      "name": .string(name), "mode": .string(String(status.st_mode & 0o7777, radix: 8)),
      "bytes": .number(Double(status.st_size)),
      "allocatedBytes": .number(Double(status.st_blocks) * 512),
    ])
  }
}

private func output(of tool: String, _ arguments: [String]) throws -> String {
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

/// One model process on this Mac. Waits while any engine helper runs, then requires 16 GiB of
/// reclaimable memory (free, purgeable and file-backed pages) before a start.
private func admitEngineStart() throws -> Value {
  var waited = 0
  while !(try output(of: "/usr/bin/pgrep", ["-fl", "splash serve"]))
    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  {
    try require(waited < 600, "model_busy", "Another engine helper is still running.")
    sleep(10)
    waited += 10
  }
  let report = try output(of: "/usr/bin/vm_stat", [])
  func figure(after label: String) -> Double {
    guard let range = report.range(of: label) else { return 0 }
    return Double(report[range.upperBound...].drop { !$0.isNumber }.prefix { $0.isNumber }) ?? 0
  }
  let reclaimable =
    (figure(after: "Pages free:") + figure(after: "Pages purgeable:")
      + figure(after: "File-backed pages:")) * figure(after: "page size of")
  try require(
    reclaimable >= 16 * 1_073_741_824, "memory",
    "Reclaimable memory is under 16 GiB. The engine was not started.")
  return .object([
    "otherHelpersRunning": .number(0), "waitedSeconds": .number(Double(waited)),
    "reclaimableGiB": .number((reclaimable / 1_073_741_824 * 10).rounded() / 10),
  ])
}

/// SIGTERM, then the helper's own exit. A clean stop gets the engine's own time to write the
/// waiting restore points; the app's stop kills it one second after the signal.
private func stopCleanly(_ helper: SplashNativeProcess) throws -> Double {
  let started = ProcessInfo.processInfo.systemUptime
  try require(Darwin.kill(helper.processID, SIGTERM) == 0, "probe", "Cannot signal the helper.")
  while helper.isOpen {
    try require(
      ProcessInfo.processInfo.systemUptime - started < 120, "probe",
      "The helper did not exit within 120 seconds of SIGTERM.")
    usleep(50_000)
  }
  let seconds = ProcessInfo.processInfo.systemUptime - started
  helper.close()
  return seconds
}

/// What both header probes start from: the pinned engine, the installed model and the header
/// the app's own prompt code puts first in an ordinary chat turn.
private struct HeaderProbeSetup {
  let engineURL: URL
  let assembly: URL
  let pin: Value
  let frontend: SplashTextFrontend
  let prepared: NativePreparedRequest
  let first: (messages: [InferenceMessage], scope: InferenceToolScope, citations: [String])
  let header: [UInt32]
  /// Splash 1.7.3 keeps a restore point on the last complete 32-token page (observeResume).
  var lastCompletePage: Int { (header.count - 1) / 32 * 32 }
}

private func prepareHeaderProbe(modelsRoot: String, engine: String, root: URL) async throws
  -> HeaderProbeSetup
{
  // The pinned engine, as the app verifies it before a start.
  let pin = try Value.parse(String(contentsOfFile: "integration/splash.json", encoding: .utf8))
  let engineURL = URL(fileURLWithPath: engine)
  for (name, digest) in pin["runtime"]["files"].object where name.hasPrefix("engine/") {
    let file = engineURL.deletingLastPathComponent().appendingPathComponent(
      String(name.dropFirst(7)))
    try require(
      try fileDigest(file) == digest.text, "model_setup", "The engine differs from the pin: " + name)
  }
  let assembly = try SplashModelPreparation.installed(
    pack: SplashModelPack.selected(), modelsRoot: URL(fileURLWithPath: modelsRoot))
  let frontend = try SplashTextFrontend(modelFolder: assembly.appendingPathComponent("tokenizer"))

  // The header is what the app's own prompt code puts first in an ordinary chat turn.
  let fixture = HeaderCaptureFixture()
  let bookURL = root.appendingPathComponent("Business.sevra")
  _ = try Demo.create(at: bookURL)
  _ = try? await WorkbookAgent.run(
    "Which supplier is cheaper?", workbook: try Workbook(bookURL),
    context: "Space: Home\nActive space ID: home", model: fixture, conversationInput: true)
  guard let first = await fixture.first else {
    throw SevraError("probe", "The chat turn dispatched no decision.")
  }
  let prepared = try NativePreparedRequest(
    messages: first.messages, frontend: frontend, configuredReasoning: .bounded512,
    toolScope: first.scope, citationIDs: first.citations)
  let header = Array(prepared.prompt.tokens.prefix(prepared.stablePrefixCount))
  try require(
    header.count >= 2048 && prepared.prompt.tokens.count > header.count, "probe",
    "The first chat decision has no header the app would prime.")
  return .init(
    engineURL: engineURL, assembly: assembly, pin: pin, frontend: frontend, prepared: prepared,
    first: first, header: header)
}

/// Opt-in, actual model. Phase H1, steps 1 and 2, of the general chat tools plan: does a
/// restore point the engine wrote for the ordinary chat header survive being copied out of
/// its cache directory and back into a new one?
///
/// Starts the engine helper directly with the app's launch arguments, the persistent cache
/// on, a new cache directory and an explicit disk quota. Prints one JSON document. It holds
/// no absolute path, so it can be kept as evidence.
func runHeaderCacheProbe(modelsRoot: String, engine: String, work: String) async throws {
  let files = FileManager.default
  let root = URL(fileURLWithPath: work)
  try require(!files.fileExists(atPath: root.path), "fixture", "Use a new work directory")
  let ownerOnly: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
  try files.createDirectory(at: root, withIntermediateDirectories: true, attributes: ownerOnly)
  defer { try? files.removeItem(at: root) }
  let cacheRoot = root.appendingPathComponent("cache")
  let aside = root.appendingPathComponent("aside")
  let dataFiles = ["kv.records", "kv.slots", "state.records", "state.slots"]
  let quotaBytes: UInt64 = 8 << 30

  let setup = try await prepareHeaderProbe(modelsRoot: modelsRoot, engine: engine, root: root)
  let engineURL = setup.engineURL, assembly = setup.assembly, pin = setup.pin
  let prepared = setup.prepared, first = setup.first
  let prompt = prepared.prompt
  let header = setup.header
  let lastCompletePage = setup.lastCompletePage

  // The product's launch values (NativeProductResources and NativeWorkbookModel), with the
  // quota, the persistent cache and its directory as the only differences.
  let contextTokens =
    ProcessInfo.processInfo.physicalMemory >= 48 * 1024 * 1024 * 1024 ? 65536 : 32768
  let memoryBytes: UInt64 = 12 * 1024 * 1024 * 1024
  let arguments = [
    "serve-native", assembly.path, String(contextTokens), String(memoryBytes), String(quotaBytes),
    "--persistent-cache", "on", "--cache-dir", cacheRoot.path,
    "--idle-sleep", "allow", "--verify-rows", "all",
    "--kv-format", "int8", "--state-format", "fp32", "--ane", "on", "--activations", "bf16",
    "--max-concurrent-requests", "1",
  ]
  func scrub(_ text: String) -> String {
    var text = text
    for (path, name) in [
      (cacheRoot.path, "<cache-dir>"), (root.path, "<work>"), (assembly.path, "<model>"),
      (NSHomeDirectory(), "~"),
    ] { text = text.replacingOccurrences(of: path, with: name) }
    let local = ["/Users/", "/private/", "/var/", "/tmp/", "/Volumes/", NSUserName()]
    return local.contains { text.contains($0) } ? "<withheld: names a local path>" : text
  }
  var document: [String: Value] = [
    "probe": .string("header-cache-probe"),
    "engine": .object([
      "release": pin["release"], "commit": pin["commit"],
      "sha256": pin["runtime"]["files"]["engine/splash"],
      "arguments": .array(arguments.map { .string(scrub($0)) }),
    ]),
    "quotaBytes": .number(Double(quotaBytes)),
    "header": .object([
      "tokens": .number(Double(header.count)),
      "tokenSHA256": .string(
        hex(SHA256.hash(data: header.withUnsafeBufferPointer { Data(buffer: $0) }))),
      "lastCompletePage": .number(Double(lastCompletePage)),
      "toolScope": .string(first.scope.rawValue),
      "scopePrefixTokens": .number(Double(prepared.scopePrefixCount)),
      "firstPromptTokens": .number(Double(prompt.tokens.count)),
    ]),
  ]

  // The app's own lock: no other Sevra process loads a model while this one holds it.
  let support = files.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Application Support/Sevra")
  try files.createDirectory(at: support, withIntermediateDirectories: true)
  let lock = Darwin.open(
    support.appendingPathComponent("inference.lock").path,
    O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
  try require(lock >= 0, "model_lock", "Cannot open local inference lock.")
  defer { Darwin.close(lock) }
  try require(
    flock(lock, LOCK_EX | LOCK_NB) == 0, "model_busy",
    "Another Sevra process has the model loaded.")

  var helper: SplashNativeProcess?
  defer { helper?.close() }
  var statusID = UInt64.max
  func disk(_ helper: SplashNativeProcess) throws -> Value {
    let status = try Value.parse(String(decoding: helper.status(id: statusID), as: UTF8.self))
    statusID -= 1
    var disk = status["disk"].object
    disk["volume_available_bytes"] = nil
    return .object([
      "disk": .object(disk), "cache": status["cache"],
      "state": .object(
        status["state"].object.filter {
          ["disk_hits", "disk_promotions", "disk_bytes", "publications"].contains($0.key)
        }),
    ])
  }
  func send(_ helper: SplashNativeProcess, _ tokens: [UInt32], generation: UInt32 = 0) throws
    -> Value
  {
    var request = SplashWire.Request(
      id: 1, prompt: tokens,
      absoluteDeadline: UInt64((Date().timeIntervalSince1970 + 180) * 1e6),
      remainingDeadline: 180_000_000)
    request.maxOutput = 1
    request.generationTokens = generation
    var matched = 0
    let result = try helper.generate(
      request, event: { if case .start(let start) = $0 { matched = Int(start.matched) } })
    return .object([
      "promptTokens": .number(Double(tokens.count)),
      "matchedPromptTokens": .number(Double(matched)),
      "generatedTokens": .number(Double(result.tokens.count)),
      "deduplicatedKVTokens": .number(Double(result.done.deduplicated)),
      "prefillSeconds": .number(Double(result.done.prefillMicros) / 1e6),
      "requestSeconds": .number(result.requestSeconds),
    ])
  }
  func cacheLog(_ helper: SplashNativeProcess) -> Value {
    .array(
      helper.diagnosticTail.split(whereSeparator: \.isNewline)
        .filter { $0.lowercased().contains("cache") }.map { .string(scrub(String($0))) })
  }
  /// One engine run: start, status, one request of one output token, status, clean stop.
  func engineRun(_ tokens: [UInt32], generation: UInt32 = 0) throws -> [String: Value] {
    var run: [String: Value] = ["admission": try admitEngineStart()]
    let began = ProcessInfo.processInfo.systemUptime
    let started = try SplashNativeProcess(executable: engineURL, arguments: arguments, timeout: 360)
    helper = started
    run["startSeconds"] = .number(ProcessInfo.processInfo.systemUptime - began)
    run["servedContextTokens"] = .number(Double(started.ready?.context ?? 0))
    run["atReady"] = try disk(started)
    run["request"] = try send(started, tokens, generation: generation)
    run["afterRequest"] = try disk(started)
    run["cacheLog"] = cacheLog(started)
    run["stopSeconds"] = .number(try stopCleanly(started))
    helper = nil
    return run
  }
  func namespaces() throws -> [String] {
    try files.contentsOfDirectory(atPath: cacheRoot.path).filter { name in
      name.count == 32 && name.allSatisfy { $0.isHexDigit }
    }
  }

  do {
    // Step 1. Make the restore point: the header as a request of one output token.
    fputs("header-cache-probe: making the header, \(header.count) tokens\n", stderr)
    try files.createDirectory(at: cacheRoot, withIntermediateDirectories: false, attributes: ownerOnly)
    document["make"] = .object(try engineRun(header))
    let names = try namespaces()
    document["cacheNamesAfterMake"] = .array(names.map(Value.string))
    try require(names.count == 1, "probe", "The engine left no single cache folder.")
    let folder = cacheRoot.appendingPathComponent(names[0])
    var written = try listing(folder)
    for (index, entry) in written.enumerated() where dataFiles.contains(entry["name"].text) {
      var entry = entry.object
      entry["sha256"] = .string(try fileDigest(folder.appendingPathComponent(entry["name"]!.text)))
      written[index] = .object(entry)
    }
    func total(_ key: String, _ only: (String) -> Bool) -> Double {
      written.filter { only($0["name"].text) }.reduce(0) { $0 + Double($1[key].int ?? 0) }
    }
    let slotBytes = total("bytes") { $0.hasSuffix(".slots") }
    var folderStatus = stat()
    _ = lstat(folder.path, &folderStatus)
    document["cache"] = .object([
      "name": .string(names[0]),
      "folderMode": .string(String(folderStatus.st_mode & 0o7777, radix: 8)),
      "files": .array(written),
      "dataBytes": .number(total("bytes") { dataFiles.contains($0) }),
      "dataAllocatedBytes": .number(total("allocatedBytes") { dataFiles.contains($0) }),
      "slotBytes": .number(slotBytes),
      "slotAllocatedBytes": .number(total("allocatedBytes") { $0.hasSuffix(".slots") }),
      "slotFilesAtQuota": .bool(slotBytes >= Double(quotaBytes) / 2),
    ])
    try require(
      Set(dataFiles).isSubset(of: Set(written.map { $0["name"].text })), "probe",
      "The engine did not write its four data files.")
    try require(
      total("bytes") { dataFiles.contains($0) } <= 4 * 1_073_741_824, "probe",
      "The data files are too large to copy byte for byte.")

    // Step 2. Copy the four data files aside, delete the cache directory, make the named
    // folder again, copy the files back, and start again.
    fputs("header-cache-probe: copying aside and restoring into a new directory\n", stderr)
    let copyBegan = ProcessInfo.processInfo.systemUptime
    try files.createDirectory(at: aside, withIntermediateDirectories: false, attributes: ownerOnly)
    for name in dataFiles {
      _ = try copyBytes(
        from: folder.appendingPathComponent(name), to: aside.appendingPathComponent(name))
    }
    try files.removeItem(at: cacheRoot)
    try require(!files.fileExists(atPath: cacheRoot.path), "probe", "The cache directory remains.")
    try files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: ownerOnly)
    var identical = true
    for name in dataFiles {
      let digest = try copyBytes(
        from: aside.appendingPathComponent(name), to: folder.appendingPathComponent(name))
      identical =
        identical && written.contains { $0["name"].text == name && $0["sha256"].text == digest }
    }
    document["restore"] = .object([
      "copy": .string("read and write, twice; no clone"), "bytesIdentical": .bool(identical),
      "copySeconds": .number(ProcessInfo.processInfo.systemUptime - copyBegan),
      "folderBeforeStart": .array(try listing(folder)),
    ])

    fputs("header-cache-probe: starting on the restored files\n", stderr)
    let restored = try engineRun(prompt.tokens, generation: prompt.generationTokens)
    document["restored"] = .object(restored)
    document["cacheNamesAfterRestore"] = .array(try namespaces().map(Value.string))
    let taken = restored["atReady"]?["disk"]["taken_back"] ?? .null
    let matched = restored["request"]?["matchedPromptTokens"].int ?? 0
    document["answer"] = .object([
      "diskPersistent": restored["atReady"]?["disk"]["persistent"] ?? .null,
      "takenBackStates": taken["states"], "takenBackKVBlocks": taken["kv_blocks"],
      "takenBackBytes": taken["bytes"], "leftBehind": taken["left_behind"],
      "headerTokens": .number(Double(header.count)),
      "lastCompletePage": .number(Double(lastCompletePage)),
      "matchedPromptTokensFirstRequest": .number(Double(matched)),
      "headerResumed": .bool(matched >= lastCompletePage),
    ])
  } catch {
    document["error"] = .string(scrub("\(error)"))
    print(try Value.object(document).json())
    throw error
  }
  print(try Value.object(document).json())
}

/// Opt-in, actual model. Phase H1, steps 4 to 6, of the general chat tools plan: a header made
/// under a small quota and restored under the app's, a header made at the 64K context and
/// restored at 32K, and a conversation that fills the context after a restore. Prints one JSON
/// document with no absolute path.
func runHeaderCacheLimitsProbe(modelsRoot: String, engine: String, work: String) async throws {
  let files = FileManager.default
  let root = URL(fileURLWithPath: work)
  try require(!files.fileExists(atPath: root.path), "fixture", "Use a new work directory")
  let ownerOnly: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
  try files.createDirectory(at: root, withIntermediateDirectories: true, attributes: ownerOnly)
  defer { try? files.removeItem(at: root) }
  let dataFiles = ["kv.records", "kv.slots", "state.records", "state.slots"]
  let smallQuota: UInt64 = 1 << 30
  let appQuota: UInt64 = 8 << 30
  let setup = try await prepareHeaderProbe(modelsRoot: modelsRoot, engine: engine, root: root)
  let header = setup.header, prompt = setup.prepared.prompt
  let memoryBytes: UInt64 = 12 * 1024 * 1024 * 1024

  func arguments(context: Int, quota: UInt64, cache: URL) -> [String] {
    [
      "serve-native", setup.assembly.path, String(context), String(memoryBytes), String(quota),
      "--persistent-cache", "on", "--cache-dir", cache.path,
      "--idle-sleep", "allow", "--verify-rows", "all",
      "--kv-format", "int8", "--state-format", "fp32", "--ane", "on", "--activations", "bf16",
      "--max-concurrent-requests", "1",
    ]
  }
  func scrub(_ text: String) -> String {
    var text = text
    for (path, name) in [
      (root.path, "<work>"), (setup.assembly.path, "<model>"), (NSHomeDirectory(), "~"),
    ] { text = text.replacingOccurrences(of: path, with: name) }
    let local = ["/Users/", "/private/", "/var/", "/tmp/", "/Volumes/", NSUserName()]
    return local.contains { text.contains($0) } ? "<withheld: names a local path>" : text
  }
  // Tokens the engine reads as any other: a fixed pseudo-random run inside the vocabulary.
  func filler(_ count: Int, seed: UInt64) -> [UInt32] {
    var state = seed
    return (0..<count).map { _ in
      state = state &* 6364136223846793005 &+ 1442695040888963407
      return UInt32(1000 + (state >> 33) % 100_000)
    }
  }

  let support = files.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Application Support/Sevra")
  try files.createDirectory(at: support, withIntermediateDirectories: true)
  let lock = Darwin.open(
    support.appendingPathComponent("inference.lock").path,
    O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
  try require(lock >= 0, "model_lock", "Cannot open local inference lock.")
  defer { Darwin.close(lock) }
  try require(
    flock(lock, LOCK_EX | LOCK_NB) == 0, "model_busy",
    "Another Sevra process has the model loaded.")

  var helper: SplashNativeProcess?
  defer { helper?.close() }
  var statusID = UInt64.max
  func disk(_ helper: SplashNativeProcess) throws -> Value {
    let status = try Value.parse(String(decoding: helper.status(id: statusID), as: UTF8.self))
    statusID -= 1
    var disk = status["disk"].object
    disk["volume_available_bytes"] = nil
    return .object(disk)
  }
  var requestID: UInt64 = 0
  func send(_ helper: SplashNativeProcess, _ tokens: [UInt32]) throws -> Value {
    requestID += 1
    var request = SplashWire.Request(
      id: requestID, prompt: tokens,
      absoluteDeadline: UInt64((Date().timeIntervalSince1970 + 300) * 1e6),
      remainingDeadline: 300_000_000)
    request.maxOutput = 1
    var matched = 0
    let result = try helper.generate(
      request, event: { if case .start(let start) = $0 { matched = Int(start.matched) } })
    return .object([
      "promptTokens": .number(Double(tokens.count)),
      "matchedPromptTokens": .number(Double(matched)),
      "prefillSeconds": .number(Double(result.done.prefillMicros) / 1e6),
    ])
  }
  func start(_ arguments: [String]) throws -> (SplashNativeProcess, [String: Value]) {
    var run: [String: Value] = ["admission": try admitEngineStart()]
    let began = ProcessInfo.processInfo.systemUptime
    let started = try SplashNativeProcess(
      executable: setup.engineURL, arguments: arguments, timeout: 360)
    helper = started
    run["startSeconds"] = .number(ProcessInfo.processInfo.systemUptime - began)
    run["servedContextTokens"] = .number(Double(started.ready?.context ?? 0))
    run["diskAtReady"] = try disk(started)
    return (started, run)
  }
  func stop(_ started: SplashNativeProcess, _ run: inout [String: Value]) throws {
    run["cacheLog"] = .array(
      started.diagnosticTail.split(whereSeparator: \.isNewline)
        .filter { $0.lowercased().contains("cache") }.map { .string(scrub(String($0))) })
    run["stopSeconds"] = .number(try stopCleanly(started))
    helper = nil
  }
  func namespaces(_ cache: URL) throws -> [String] {
    try files.contentsOfDirectory(atPath: cache.path).filter { name in
      name.count == 32 && name.allSatisfy { $0.isHexDigit }
    }
  }
  func restore(_ aside: URL, into cache: URL, name: String) throws {
    let folder = cache.appendingPathComponent(name)
    try files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: ownerOnly)
    for file in dataFiles {
      _ = try copyBytes(from: aside.appendingPathComponent(file), to: folder.appendingPathComponent(file))
    }
  }
  func resumed(_ request: Value) -> Bool {
    (request["matchedPromptTokens"].int ?? 0) >= setup.lastCompletePage
  }

  var document: [String: Value] = [
    "probe": .string("header-cache-limits-probe"),
    "engine": .object([
      "release": setup.pin["release"], "commit": setup.pin["commit"],
      "arguments": .array(
        arguments(context: 65536, quota: appQuota, cache: root).map { .string(scrub($0)) }),
    ]),
    "header": .object([
      "tokens": .number(Double(header.count)),
      "lastCompletePage": .number(Double(setup.lastCompletePage)),
      "firstPromptTokens": .number(Double(prompt.tokens.count)),
    ]),
    "smallQuotaBytes": .number(Double(smallQuota)), "appQuotaBytes": .number(Double(appQuota)),
  ]
  do {
    // Step 4, first half: the header made at 64K under a small quota.
    fputs("header-cache-limits-probe: making the header under a small quota\n", stderr)
    let made = root.appendingPathComponent("made")
    try files.createDirectory(at: made, withIntermediateDirectories: false, attributes: ownerOnly)
    var (helperMade, makeRun) = try start(arguments(context: 65536, quota: smallQuota, cache: made))
    makeRun["request"] = try send(helperMade, header)
    try stop(helperMade, &makeRun)
    document["make"] = .object(makeRun)
    let madeNames = try namespaces(made)
    try require(madeNames.count == 1, "probe", "The engine left no single cache folder.")
    let name = madeNames[0]
    let aside = root.appendingPathComponent("aside")
    try files.createDirectory(at: aside, withIntermediateDirectories: false, attributes: ownerOnly)
    for file in dataFiles {
      _ = try copyBytes(
        from: made.appendingPathComponent(name).appendingPathComponent(file),
        to: aside.appendingPathComponent(file))
    }
    document["madeFiles"] = .array(try listing(aside))

    // Step 4, second half, and step 6: restored under the app's quota at 64K, then a
    // conversation that fills the context, then a new conversation.
    fputs("header-cache-limits-probe: restoring under the app quota and filling the context\n", stderr)
    let full = root.appendingPathComponent("full")
    try restore(aside, into: full, name: name)
    var (helperFull, fullRun) = try start(arguments(context: 65536, quota: appQuota, cache: full))
    let firstRequest = try send(helperFull, prompt.tokens)
    fullRun["firstRequest"] = firstRequest
    var conversation = prompt.tokens
    var turns: [Value] = []
    for turn in 0..<8 {
      conversation += filler(7000, seed: UInt64(turn + 1))
      turns.append(try send(helperFull, conversation))
    }
    fullRun["turns"] = .array(turns)
    fullRun["diskAfterConversation"] = try disk(helperFull)
    let newConversation = try send(helperFull, header + filler(3000, seed: 99))
    fullRun["newConversation"] = newConversation
    try stop(helperFull, &fullRun)
    fullRun["filesAfterStop"] = .array(try listing(full.appendingPathComponent(name)))
    fullRun["namesAfterStop"] = .array(try namespaces(full).map(Value.string))
    document["full"] = .object(fullRun)

    // Step 5: the 64K header restored at the 32K context.
    fputs("header-cache-limits-probe: restoring the 64K header at 32K\n", stderr)
    let small = root.appendingPathComponent("small")
    try restore(aside, into: small, name: name)
    var (helperSmall, smallRun) = try start(arguments(context: 32768, quota: appQuota, cache: small))
    let smallRequest = try send(helperSmall, prompt.tokens)
    smallRun["request"] = smallRequest
    try stop(helperSmall, &smallRun)
    smallRun["namesAfterStop"] = .array(try namespaces(small).map(Value.string))
    document["context32K"] = .object(smallRun)

    let fullDisk = fullRun["diskAfterConversation"] ?? .null
    document["answer"] = .object([
      "cacheName64K": .string(name),
      "smallQuotaHeaderTakenBack": fullRun["diskAtReady"]?["taken_back"] ?? .null,
      "smallQuotaHeaderResumed": .bool(resumed(firstRequest)),
      "conversationTokens": .number(Double(conversation.count)),
      "conversationWrittenBytes": fullDisk["written_bytes"],
      "conversationUsedBytes": fullDisk["used_bytes"],
      "conversationWriteBehind": fullDisk["write_behind"],
      "newConversationResumedHeader": .bool(resumed(newConversation)),
      "context32KServed": smallRun["servedContextTokens"] ?? .null,
      "context32KCacheNames": smallRun["namesAfterStop"] ?? .null,
      "context32KTakenBack": smallRun["diskAtReady"]?["taken_back"] ?? .null,
      "context32KResumed": .bool(resumed(smallRequest)),
    ])
  } catch {
    document["error"] = .string(scrub("\(error)"))
    print(try Value.object(document).json())
    throw error
  }
  print(try Value.object(document).json())
}
