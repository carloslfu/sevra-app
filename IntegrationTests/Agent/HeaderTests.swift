import Darwin
import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash

private final class HeaderRequestLog: @unchecked Sendable {
  private let lock = NSLock()
  private var rows: [Value] = []
  private(set) var admissions = 0
  func append(_ value: Value) {
    lock.lock()
    rows.append(value)
    lock.unlock()
  }
  func admitted() {
    lock.lock()
    admissions += 1
    lock.unlock()
  }
  var all: [Value] {
    lock.lock()
    defer { lock.unlock() }
    return rows
  }
}

/// Opt-in, actual model. The prepared header's tests on a packaged development build, phase
/// H3 of the general chat tools plan. One run each, in English:
///
/// - resumed, not computed: a cold first turn resumes the restored header and asks for none of it as a head;
/// - faster: the same turn is faster than with the comparison setting, which computes it;
/// - same answers: both settings generate the same tokens for the same requests;
/// - recovers without computing: a seam reports one missed resume; the request restarts and
///   resumes, and nothing is computed;
/// - fails loudly: with no header, a mismatched manifest or a damaged file the local AI is
///   unavailable with the message, and only the damaged file starts the engine, twice;
/// - nothing kept: after a stop the cache directory is gone; after a forced kill the next start
///   holds the header only;
/// - another folder: a model prepared from other folders on this Mac has the same assembly key
///   and takes the same header back.
///
/// The survival of a full conversation and the 32K tier are phase H1's evidence. Prints one JSON
/// document with no absolute path.
func runHeaderTests(
  modelsRoot: String, library: String, engine: String, headers: String, work: String
) async throws {
  let files = FileManager.default
  let root = URL(fileURLWithPath: work)
  try require(!files.fileExists(atPath: root.path), "fixture", "Use a new work directory")
  try files.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? files.removeItem(at: root) }
  let headerRoot = URL(fileURLWithPath: headers)
  let cache = root.appendingPathComponent("cache")
  let base = try nativeProbeConfiguration(
    library: library, engine: engine, modelsRoot: modelsRoot,
    budget: .init(profile: .evaluation64K), reasoning: .bounded512, modelLayout: .installed)
  func configuration(
    _ header: NativeWorkbookModel.Configuration.Header, models: URL? = nil,
    seam: Bool = false, log: HeaderRequestLog
  ) -> NativeWorkbookModel.Configuration {
    .init(
      engine: base.engine, engineFiles: base.engineFiles, grammarLibrary: base.grammarLibrary,
      grammarSHA256: base.grammarSHA256, modelsRoot: models ?? base.modelsRoot,
      memoryBytes: base.memoryBytes, contextBudget: base.contextBudget, reasoning: base.reasoning,
      modelLayout: .installed, contextMaintenanceEnabled: true,
      observeRequest: { log.append($0) }, observeAdmission: { _ in log.admitted() },
      header: header, cacheDirectory: cache, diagnosticMissedResume: seam)
  }
  func helpers() -> Int {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-x", "splash"]
    process.standardOutput = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).count
  }
  func ready() throws {
    // A stopped or killed engine's memory returns to the system a moment after its process
    // exits, more slowly after a forced kill. Wait for it, bounded, instead of refusing the
    // next start; the product's own guard is unchanged.
    var waited = 0.0
    while true {
      do {
        try PromptHeader.admitModelLoad()
        return
      } catch let error as SevraError where error.code == "memory" && waited < 30 {
        usleep(500_000)
        waited += 0.5
      }
    }
  }
  struct Turn {
    var seconds: Double
    var answer: String
    var requests: [Value]
    var error: String?
  }
  func turn(
    _ prompt: String, _ configuration: NativeWorkbookModel.Configuration, log: HeaderRequestLog,
    model existing: NativeWorkbookModel? = nil, unload: Bool = true, from source: URL? = nil
  ) async throws -> (Turn, NativeWorkbookModel) {
    try ready()
    let model = existing ?? NativeWorkbookModel(configuration: configuration)
    let bookURL = root.appendingPathComponent("Business-\(UUID().uuidString).sevra")
    if let source { try files.copyItem(at: source, to: bookURL) } else { _ = try Demo.create(at: bookURL) }
    let first = log.all.count
    let started = ProcessInfo.processInfo.systemUptime
    var answer = ""
    var failure: String?
    do {
      let result = try await WorkbookAgent.run(
        prompt, workbook: try Workbook(bookURL), context: "Space: Home\nActive space ID: home",
        modelDirectory: URL(fileURLWithPath: modelsRoot),
        cancellation: .init(deadlineAfterSeconds: 300), model: model, conversationInput: true)
      answer = result.answer
      if result.state == "failed" { failure = result.answer }
    } catch {
      failure = "\(error)"
    }
    let seconds = ProcessInfo.processInfo.systemUptime - started
    if unload { _ = await model.unload() }
    let runs = try Workbook(bookURL).agentRuns()
    if failure == nil, let run = runs.first, run["status"].text == "failed" {
      failure = (try? run["error"].json()) ?? "failed"
    }
    return (
      Turn(
        seconds: seconds, answer: answer, requests: Array(log.all.dropFirst(first)),
        error: failure), model
    )
  }
  func metrics(_ turn: Turn) -> [Value] { turn.requests.map { $0["metrics"] } }
  func generated(_ turn: Turn) -> [Value] { turn.requests.map { $0["tokens"] } }

  let identity = try PromptHeader.Identity(
    engineSHA256: base.engineFiles["splash"] ?? "", activations: base.activations.rawValue,
    reasoning: base.reasoning)
  guard case .present(let headerFolder, let manifest) = PromptHeader.state(
    at: headerRoot, identity: identity)
  else { throw SevraError("header_tests", "Make the header first: sevra header make " + headers) }
  var document: [String: Value] = [
    "tests": .string("header-tests"),
    "header": .object([
      "inputs": .string(manifest.inputs), "tokens": .number(Double(manifest.tokens)),
      "lastCompletePage": .number(Double(manifest.lastCompletePage)),
      "bytes": .number(Double(manifest.dataBytes)), "cacheName": .string(manifest.cacheName),
    ]),
  ]
  var results: [String: Value] = [:]
  func record(_ name: String, _ passed: Bool, _ detail: [String: Value]) {
    var detail = detail
    detail["passed"] = .bool(passed)
    results[name] = .object(detail)
    fputs("header-tests: \(name) \(passed ? "passed" : "FAILED")\n", stderr)
    // A later step that throws must not lose why this one failed.
    if !passed, let text = try? Value.object(detail).json() {
      fputs("header-tests: \(name) detail \(text)\n", stderr)
    }
  }

  // Restored against computed: resumed, faster, same answers.
  let prompts = ["How many brass bolts do we have?", "Hi"]
  var restoredTurns: [Turn] = []
  var computedTurns: [Turn] = []
  for prompt in prompts {
    // One workbook for both settings, so the prompts are the same token for token.
    let source = root.appendingPathComponent("Source-\(UUID().uuidString).sevra")
    _ = try Demo.create(at: source)
    let restoredLog = HeaderRequestLog()
    restoredTurns.append(
      try await turn(
        prompt, configuration(.restore(headerRoot), log: restoredLog), log: restoredLog,
        from: source
      ).0)
    let computedLog = HeaderRequestLog()
    computedTurns.append(
      try await turn(
        prompt, configuration(.compute, log: computedLog), log: computedLog, from: source
      ).0)
  }
  let first = metrics(restoredTurns[0]).first ?? .null
  record(
    "resumedNotComputed",
    restoredTurns[0].error == nil && first["headerResumed"] == .bool(true)
      && (first["headTokens"].int ?? 0) != manifest.tokens
      && (first["matchedPromptTokens"].int ?? 0) >= manifest.lastCompletePage,
    [
      "matchedPromptTokens": first["matchedPromptTokens"],
      "headTokens": first["headTokens"], "headerResumed": first["headerResumed"],
    ])
  let computedFirst = metrics(computedTurns[0]).first ?? .null
  // The header's share of the first decision: the request's own prefill, which computes the
  // header when it is not restored. A whole turn's wall time is mostly the model load.
  func seconds(_ value: Value) -> Double {
    if case .number(let number) = value { return number }
    return 0
  }
  func headerWork(_ value: Value) -> Double {
    seconds(value["prefillSeconds"])
  }
  record(
    "faster",
    headerWork(first) < headerWork(computedFirst),
    [
      "restoredFirstDecisionSeconds": .number(headerWork(first)),
      "computedFirstDecisionSeconds": .number(headerWork(computedFirst)),
      "computedHeadTokens": computedFirst["headTokens"],
      "restoredTurnSeconds": .number(restoredTurns[0].seconds),
      "computedTurnSeconds": .number(computedTurns[0].seconds),
    ])
  // The engine is not repeatable token for token across processes: two computed runs of these
  // requests diverged at tokens 105 and 2 and worded the greeting differently. So the same
  // answers are the same decisions and the same factual answer, as the plan states them.
  record(
    "sameAnswers",
    zip(restoredTurns, computedTurns).allSatisfy {
      $0.error == nil && $1.error == nil && $0.requests.count == $1.requests.count
    } && restoredTurns[0].answer == computedTurns[0].answer,
    [
      "requests": .array(prompts.map(Value.string)),
      "restoredAnswers": .array(restoredTurns.map { .string($0.answer) }),
      "computedAnswers": .array(computedTurns.map { .string($0.answer) }),
      "restoredDecisions": .array(restoredTurns.map { .number(Double($0.requests.count)) }),
      "computedDecisions": .array(computedTurns.map { .number(Double($0.requests.count)) }),
      "firstDifferentToken": .array(
        zip(restoredTurns, computedTurns).map { pair in
          let a = generated(pair.0).first?.array ?? [], b = generated(pair.1).first?.array ?? []
          return .number(Double(zip(a, b).prefix { $0 == $1 }.count))
        }),
    ])

  record(
    "nothingKeptAfterStop", !files.fileExists(atPath: cache.path),
    ["cacheDirectoryAfterStop": .bool(files.fileExists(atPath: cache.path))])

  // A missed resume restarts from the app's files and computes nothing.
  let seamLog = HeaderRequestLog()
  let (seamTurn, _) = try await turn(
    "Hi", configuration(.restore(headerRoot), seam: true, log: seamLog), log: seamLog)
  let seamFirst = metrics(seamTurn).first ?? .null
  record(
    "recoversWithoutComputing",
    seamTurn.error == nil && seamFirst["headerRestarts"].int == 1
      && seamFirst["headerResumed"] == .bool(true)
      && (seamFirst["headTokens"].int ?? 0) != manifest.tokens
      && seamLog.admissions == 2,
    [
      "headerRestarts": seamFirst["headerRestarts"], "engineStarts": .number(Double(seamLog.admissions)),
      "answer": .string(seamTurn.answer),
    ])

  // Fails loudly: no header, a mismatched manifest, a damaged file.
  func copyHeader(_ name: String) throws -> URL {
    let folder = root.appendingPathComponent(name)
    try files.createDirectory(at: folder, withIntermediateDirectories: true)
    try files.copyItem(at: headerFolder, to: folder.appendingPathComponent(headerFolder.lastPathComponent))
    return folder
  }
  var loud: [String: Value] = [:]
  var loudPassed = true
  let empty = root.appendingPathComponent("no-header")
  try files.createDirectory(at: empty, withIntermediateDirectories: true)
  let mismatched = try copyHeader("mismatched")
  let manifestURL = mismatched.appendingPathComponent(manifest.inputs + "/manifest.json")
  var edited = try Value.parse(String(contentsOf: manifestURL, encoding: .utf8)).object
  var engineField = edited["engine"]?.object ?? [:]
  engineField["commit"] = .string(String(repeating: "0", count: 40))
  edited["engine"] = .object(engineField)
  try Data(Value.object(edited).json().utf8).write(to: manifestURL)
  let damaged = try copyHeader("damaged")
  let records = damaged.appendingPathComponent(manifest.inputs + "/kv.records")
  let size = (try files.attributesOfItem(atPath: records.path)[.size] as? NSNumber)?.intValue ?? 0
  try Data(count: size).write(to: records)
  for (name, folder, starts) in [
    ("absent", empty, 0), ("mismatched", mismatched, 0), ("damagedFile", damaged, 2),
  ] {
    let log = HeaderRequestLog()
    let (failed, _) = try await turn("Hi", configuration(.restore(folder), log: log), log: log)
    let message = failed.error ?? ""
    let passed =
      message.contains("model_header") && log.admissions == starts && log.all.isEmpty
      && helpers() == 0
    loudPassed = loudPassed && passed
    loud[name] = .object([
      "passed": .bool(passed), "engineStarts": .number(Double(log.admissions)),
      "decisions": .number(Double(log.all.count)),
      "message": .string(message.contains("Install Sevra again") ? "names the fix" : message),
    ])
  }
  record("failsLoudly", loudPassed, loud)

  // A forced kill, then the next start: the directory holds the header only.
  let killLog = HeaderRequestLog()
  let (_, live) = try await turn(
    "Hi", configuration(.restore(headerRoot), log: killLog), log: killLog, unload: false)
  let helper = Process()
  helper.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
  helper.arguments = ["-KILL", "-x", "splash"]
  try helper.run()
  helper.waitUntilExit()
  while helpers() > 0 { usleep(100_000) }
  var afterKill: [String] = []
  let killedLog = HeaderRequestLog()
  let (again, _) = try await turn(
    "Hi", configuration(.restore(headerRoot), log: killedLog), log: killLog, model: live,
    unload: false)
  if let names = try? files.contentsOfDirectory(atPath: cache.path) { afterKill = names }
  let againFirst = metrics(again).first ?? .null
  _ = await live.unload()
  record(
    "headerOnlyAfterKill",
    again.error == nil && againFirst["headerResumed"] == .bool(true)
      && afterKill == [manifest.cacheName],
    ["cacheFolders": .array(afterKill.map(Value.string)), "headerResumed": againFirst["headerResumed"]])

  // Another folder: the same model from hard links in other folders.
  let assembly = try SplashModelPreparation.installed(
    pack: SplashModelPack.selected(), modelsRoot: URL(fileURLWithPath: modelsRoot))
  let sidecar = try Value.parse(
    String(
      contentsOf: assembly.deletingLastPathComponent().appendingPathComponent(
        assembly.lastPathComponent + ".json"), encoding: .utf8))
  let pack = try SplashModelPack.selected()
  let elsewhere = root.appendingPathComponent("elsewhere")
  var folders: [String: URL] = [:]
  for (role, source) in [("target", pack.target), ("draft", pack.draft)] {
    let folder = elsewhere.appendingPathComponent(role)
    try files.createDirectory(at: folder, withIntermediateDirectories: true)
    folders[role] = folder
    for file in source.files where !file.destinations.isEmpty {
      let original = sidecar["files"][file.destinations[0]]["path"].text
      try files.linkItem(
        at: URL(fileURLWithPath: original), to: folder.appendingPathComponent(file.path))
    }
  }
  let otherModels = root.appendingPathComponent("other-models")
  let other = try SplashModelPreparation.prepare(
    pack: pack, target: folders["target"]!, draft: folders["draft"]!, modelsRoot: otherModels,
    pinnedSources: true)
  let otherLog = HeaderRequestLog()
  let (otherTurn, _) = try await turn(
    "Hi", configuration(.restore(headerRoot), models: otherModels, log: otherLog), log: otherLog)
  let otherFirst = metrics(otherTurn).first ?? .null
  record(
    "anotherFolder",
    PromptHeader.assemblyKey(other) == manifest.assemblyKey
      && other.path != assembly.path && otherTurn.error == nil
      && otherFirst["headerResumed"] == .bool(true),
    [
      "sameAssemblyKey": .bool(PromptHeader.assemblyKey(other) == manifest.assemblyKey),
      "headerResumed": otherFirst["headerResumed"],
    ])

  document["results"] = .object(results)
  document["passed"] = .bool(results.values.allSatisfy { $0["passed"] == .bool(true) })
  print(try Value.object(document).json())
  try require(document["passed"] == .bool(true), "header_tests", "A header test failed.")
}
