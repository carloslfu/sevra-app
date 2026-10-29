import Darwin
import Foundation
import SevraSplash

let fixtureURL = Bundle.module.url(forResource: "protocol_golden", withExtension: "txt")!
let golden = try String(contentsOf: fixtureURL, encoding: .utf8).split(separator: "\n").reduce(
  into: [String: Data]()
) { out, line in
  if line.hasPrefix("#") { return }
  let parts = line.split(separator: " ")
  guard parts.count == 2 else { return }
  let hex = Array(parts[1])
  var bytes: [UInt8] = []
  for i in stride(from: 0, to: hex.count, by: 2) {
    bytes.append(UInt8(String(hex[i...i + 1]), radix: 16)!)
  }
  out[String(parts[0])] = Data(bytes)
}
func set(_ data: inout Data, _ offset: Int, _ value: UInt64, width: Int = 4) {
  for i in 0..<width { data[offset + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
}
func get(_ data: Data, _ offset: Int, width: Int = 4) -> UInt64 {
  (0..<width).reduce(0) { $0 | UInt64(data[offset + $1]) << ($1 * 8) }
}
func decode(_ data: Data) throws -> SplashWire.Event {
  var d = SplashWire.Decoder()
  let result = try d.consume(data)
  try d.finish()
  guard result.count == 1 else { throw SplashError("Fixture did not produce one event") }
  return result[0]
}
func readExactly(_ count: Int) throws -> Data? {
  var data = Data()
  while data.count < count {
    guard let part = try FileHandle.standardInput.read(upToCount: count - data.count), !part.isEmpty
    else { return nil }
    data.append(part)
  }
  return data
}
func emit(_ data: Data) throws { try FileHandle.standardOutput.write(contentsOf: data) }
func peer(_ mode: String) throws {
  if mode == "ignore-terminate" { signal(SIGTERM, SIG_IGN) }
  if mode == "startup-cancel" {
    signal(SIGTERM, SIG_IGN)
    try Data(String(getpid()).utf8).write(
      to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
    sleep(10)
    return
  }
  if mode == "startup-stall" {
    sleep(10)
    return
  }
  if mode == "partial" {
    try emit(Data(golden["ready"]!.prefix(8)))
    return
  }
  if mode == "startup-fail" {
    try emit(golden["error_engine"]!)
    return
  }
  if mode == "stderr" {
    try FileHandle.standardError.write(contentsOf: Data(repeating: 120, count: 262144))
  }
  for byte in golden["ready"]! { try emit(Data([byte])) }
  if mode == "ignore-terminate" { while true { pause() } }
  if mode == "crash" { return }
  while let header = try readExactly(16) {
    let type = get(header, 6, width: 2)
    let size = get(header, 8, width: 8)
    guard size < 8 * 1024 * 1024, let payload = try readExactly(Int(size)) else { return }
    let id = get(payload, 0, width: 8)
    if type == 4 || type == 5 {
      var status = golden["status_json"]!
      set(&status, 16, id, width: 8)
      try emit(status)
      continue
    }
    if type != 1 { return }
    let prompt = get(payload, 30)
    if mode == "stall" {
      sleep(10)
      return
    }
    if mode == "refusal" && id == 91 {
      var error = golden["error_request"]!
      set(&error, 22, id, width: 8)
      try emit(error)
      continue
    }
    var done = golden["done_bounded"]!
    set(&done, 16, id, width: 8)
    done[24] = 0
    done[25] = 0
    set(&done, 26, prompt)
    set(&done, 30, 3)
    if mode == "cancel" && id == 91 {
      guard let cancelHeader = try readExactly(16), get(cancelHeader, 6, width: 2) == 2,
        let cancel = try readExactly(8), get(cancel, 0, width: 8) == id
      else { return }
      done[24] = 2
      set(&done, 30, 0)
      try emit(done)
      continue
    }
    var start = golden["start"]!
    set(&start, 16, id, width: 8)
    set(&start, 24, 0)
    set(&start, 28, 0)
    var tokens = golden["tokens"]!
    set(&tokens, 16, id, width: 8)
    set(&tokens, 24, mode == "gap" ? 1 : 0)
    var bytes = start + tokens + done
    if mode == "duplicate" { bytes.append(done) }
    try emit(bytes)
  }
}
if CommandLine.arguments.count >= 3 && CommandLine.arguments[1] == "--peer" {
  guard CommandLine.arguments.count == (CommandLine.arguments[2] == "startup-cancel" ? 4 : 3)
  else { exit(2) }
  do {
    try peer(CommandLine.arguments[2])
    exit(0)
  } catch { exit(70) }
}

do {
  if try nativeProbe(Array(CommandLine.arguments.dropFirst())) { exit(0) }
} catch {
  fputs("Native probe failed: \(error)\n", stderr)
  exit(1)
}

var passed = 0
var failed = 0
func expect(_ value: Bool, _ label: String = "Expectation failed") throws {
  if !value { throw SplashError(label) }
}
func rejects(_ action: () throws -> Void) throws {
  do { try action() } catch { return }
  throw SplashError("Invalid input was accepted")
}
func test(_ name: String, _ body: () throws -> Void) {
  do {
    try body()
    passed += 1
    print("PASS \(name)")
  } catch {
    failed += 1
    print("FAIL \(name): \(error)")
  }
}
func example() -> SplashWire.Request {
  var r = SplashWire.Request(
    id: 0x0123_4567_89AB_CDEF, prompt: [0, 1, 42, 0x8000_0000, .max],
    absoluteDeadline: 1_800_000_000_000_000, remainingDeadline: 45_000_000)
  r.maxOutput = 32768
  r.seed = 0xFEDC_BA98_7654_3210
  r.tokenMask = true
  r.generationTokens = 2
  r.sampling.temperature = 0.8
  r.sampling.topP = 0.95
  r.sampling.topK = 32
  r.sampling.presence = 1.5
  r.sampling.frequency = -0.25
  r.sampling.repetition = 1.1
  r.sampling.minP = 0.05
  r.saltLow = 0x8899_AABB_CCDD_EEFF
  r.saltHigh = 0x0011_2233_4455_6677
  r.thinking = .init(tokens: 4096, end: [198, 248069], alsoEnds: 248058)
  return r
}
func request(_ id: UInt64 = 91) -> SplashWire.Request {
  SplashWire.Request(
    id: id, prompt: [1, 2, 3, 4],
    absoluteDeadline: UInt64(Date().timeIntervalSince1970 * 1e6) + 30_000_000,
    remainingDeadline: 30_000_000)
}
func process(_ mode: String = "normal", timeout: Double = 5) throws -> SplashNativeProcess {
  try SplashNativeProcess(
    executable: URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL,
    arguments: ["--peer", mode], timeout: timeout)
}

test("upstream text request byte parity") {
  try expect(try example().encoded() == golden["request"])
}
test("upstream request variants and control frames") {
  var r = example()
  r.flags = 2
  try expect(try r.encoded() == golden["request_progress"])
  r.flags = 1
  r.tokenMask = false
  try expect(try r.encoded() == golden["request_ignore_eos"])
  r = example()
  r.maxOutput = 0
  r.prompt = [5, 6, 7]
  r.sampling = .init()
  r.tokenMask = false
  r.scores = [101, 202, 303]
  r.thinking = nil
  try expect(try r.encoded() == golden["request_score"])
  try expect(try SplashWire.cancel(91) == golden["cancel"])
  try expect(
    try SplashWire.mask(id: 91, maskID: 7, words: [.max, 0, 0xA5A5_A5A5]) == golden["mask_response"]
  )
  try expect(SplashWire.status(808) == golden["status_request"])
  try expect(SplashWire.status(808, release: true) == golden["release_request"])
}
test("every upstream engine golden, fragmented at every byte") {
  let engineNames = golden.keys.filter {
    !["request", "cancel", "mask_response", "status_request", "release_request"].contains($0)
      && !$0.hasPrefix("request_")
  }.sorted()
  try expect(engineNames.count == 15)
  for name in engineNames {
    let bytes = golden[name]!
    let expected = try decode(bytes)
    var decoder = SplashWire.Decoder()
    var events: [SplashWire.Event] = []
    for byte in bytes { events += try decoder.consume(Data([byte])) }
    try decoder.finish()
    try expect(events == [expected], name)
  }
  try expect(try decode(golden["ready"]!) == .ready(concurrent: 4, context: 524288, vision: false))
  try expect(try decode(golden["tokens"]!) == .tokens(id: 91, offset: 17, tokens: [10, 11, 12]))
  if case .done(let d) = try decode(golden["done"]!) {
    try expect(
      d.prompt == 4096 && d.completion == 512 && d.prefillMicros == 1000 && d.decodeMicros == 2000
        && d.wallMicros == 3500)
    try expect(d.deduplicated == 64 && d.drafted == 350 && d.accepted == 280 && d.cycles == 50)
  } else {
    throw SplashError("Not a done event")
  }
  if case .done(let d) = try decode(golden["done_scored"]!) {
    try expect(d.logits == [1.5, -2.25, 0.5])
  } else {
    throw SplashError("Not a scored event")
  }
}
test("bad header rejects before allocating a payload and remains failed") {
  for (offset, value, width) in [(0, UInt64(0), 1), (4, 10, 2), (6, 1, 2), (8, .max, 8)] {
    var bytes = golden["ready"]!
    set(&bytes, offset, value, width: width)
    var decoder = SplashWire.Decoder()
    try rejects { _ = try decoder.consume(Data(bytes.prefix(16))) }
    try rejects { _ = try decoder.consume(golden["ready"]!) }
  }
}
test("partial EOF and malformed event bodies are refused") {
  for n in 1..<golden["ready"]!.count {
    var decoder = SplashWire.Decoder()
    _ = try decoder.consume(Data(golden["ready"]!.prefix(n)))
    try rejects { try decoder.finish() }
  }
  for (name, offset, value, width) in [
    ("ready", 24, UInt64(2), 1), ("start", 16, 0, 8), ("tokens", 28, 4000, 4), ("done", 24, 8, 1),
    ("done", 25, 1, 1), ("error_request", 16, 2, 1),
    ("mask_request_initial", 32, UInt64(UInt32.max), 4),
  ] {
    var bytes = golden[name]!
    set(&bytes, offset, value, width: width)
    try rejects { _ = try decode(bytes) }
  }
}
test("invalid client configuration is rejected") {
  var r = request()
  r.sampling.temperature = .nan
  try rejects { _ = try r.encoded() }
  r = request()
  r.flags = 8
  try rejects { _ = try r.encoded() }
  r = request()
  r.prompt = []
  try rejects { _ = try r.encoded() }
  r = request()
  r.generationTokens = 4
  try rejects { _ = try r.encoded() }
  r = request()
  r.id = 0
  try rejects { _ = try r.encoded() }
  r = request()
  r.thinking = .init(tokens: 4, end: [1, 2, 1], alsoEnds: 8)
  try rejects { _ = try r.encoded() }
}
test("request state refuses gap, duplicate, wrong id and progress after tokens") {
  for bad in [
    SplashWire.Event.tokens(id: 91, offset: 1, tokens: [2]),
    .tokens(id: 92, offset: 0, tokens: [2]), .start(id: 91, lane: 0, matched: 0),
  ] {
    var state = SplashStreamState(request())
    try state.accept(.start(id: 91, lane: 0, matched: 0))
    try rejects { _ = try state.accept(bad) }
  }
  var r = request()
  r.flags = 2
  var state = SplashStreamState(r)
  try state.accept(.start(id: 91, lane: 0, matched: 0))
  try state.accept(.tokens(id: 91, offset: 0, tokens: [2]))
  try rejects { _ = try state.accept(.tokens(id: 91, offset: 0, tokens: [2])) }
  try rejects { _ = try state.accept(.progress(id: 91, processed: 1, micros: 4)) }
}
test("native pipes run multiple requests, status and idle release") {
  let p = try process()
  defer { p.close() }
  try expect(p.ready?.context == 524288)
  for id: UInt64 in [91, 92] {
    let r = try p.generate(request(id))
    try expect(r.tokens == [10, 11, 12] && r.done.reason == .stop)
    try expect(r.firstTokenSeconds != nil && r.requestSeconds > 0)
  }
  try expect(try JSONSerialization.jsonObject(with: p.status(id: 808)) is [String: Any])
  try expect(
    try JSONSerialization.jsonObject(with: p.status(id: 809, release: true)) is [String: Any])
  try rejects { _ = try p.generate(request(91)) }
}
test("request refusal preserves the helper for a succeeding request") {
  let p = try process("refusal")
  defer { p.close() }
  do {
    _ = try p.generate(request())
    throw SplashError("Expected native refusal")
  } catch let error as SplashWire.Failure {
    try expect(error.classification == 1 && error.retryable)
  }
  try expect(try p.generate(request(92)).tokens.count == 3)
}
test("cancellation without start then recovery") {
  let p = try process("cancel")
  defer { p.close() }
  let r = try p.generate(request(), cancelled: { true })
  try expect(r.done.reason == .cancelled && r.tokens.isEmpty)
  try expect(try p.generate(request(92)).tokens.count == 3)
}
test("native timeout kills and reaps only the owned helper") {
  let p = try process("stall")
  let pid = p.processID
  let before = ProcessInfo.processInfo.systemUptime
  try rejects { _ = try p.generate(request(), timeout: 0.1) }
  try expect(ProcessInfo.processInfo.systemUptime - before < 3)
  try expect(kill(pid, 0) == -1 && errno == ESRCH)
}
test("serial worker teardown is bounded, repeatable and reaps a stubborn helper") {
  let worker = DispatchQueue(label: "sevra-test-native-close")
  try worker.sync {
    for mode in Array(repeating: "normal", count: 32) + ["ignore-terminate"] {
      let p = try process(mode)
      let pid = p.processID
      let before = ProcessInfo.processInfo.systemUptime
      try expect(p.close())
      try expect(p.close())
      try expect(ProcessInfo.processInfo.systemUptime - before < 5)
      try expect(kill(pid, 0) == -1 && errno == ESRCH)
    }
  }
}
test("malformed stream, duplicate completion and child exit fail closed") {
  for mode in ["gap", "duplicate", "crash"] {
    let p = try process(mode)
    let pid = p.processID
    try rejects { _ = try p.generate(request()) }
    try expect(kill(pid, 0) == -1 && errno == ESRCH)
    try rejects { _ = try p.generate(request(92)) }
  }
}
test("startup failure, partial frame and timeout clean up") {
  for mode in ["startup-fail", "partial", "startup-stall"] {
    try rejects { _ = try process(mode, timeout: 0.15) }
  }
  try rejects {
    _ = try SplashNativeProcess(
      executable: URL(fileURLWithPath: "/missing-sevra-test-helper"), arguments: [])
  }
}
test("cancelling a long cold start promptly reaps its unresponsive helper") {
  let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: pidFile) }
  let before = ProcessInfo.processInfo.systemUptime
  do {
    _ = try SplashNativeProcess(
      executable: URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL,
      arguments: ["--peer", "startup-cancel", pidFile.path], timeout: 360,
      cancelled: { FileManager.default.fileExists(atPath: pidFile.path) })
    throw SplashError("Expected startup cancellation")
  } catch let error as SplashError {
    try expect(error.localizedDescription.contains("cancelled"))
  }
  try expect(ProcessInfo.processInfo.systemUptime - before < 5)
  let pid = try String(contentsOf: pidFile, encoding: .utf8)
  try expect(kill(Int32(pid)!, 0) == -1 && errno == ESRCH)
}
test("stderr is continuously drained with a bounded diagnostic tail") {
  let p = try process("stderr")
  defer { p.close() }
  try expect(p.diagnosticTail.utf8.count == 65536)
  try expect(try p.generate(request()).tokens.count == 3)
}
checkModelPreparation()
checkNativeSetup()
print("\(passed) Splash checks passed; \(failed) failed")
exit(failed == 0 ? 0 : 1)
