import Foundation

/// Debug timing for chat turns. It is off unless the environment has `SEVRA_CHAT_TIMING=1`, or
/// the app has the `SevraChatTiming` default (`defaults write com.sevra.workbooks SevraChatTiming
/// -bool true`, then reopen the app). Read once per process, so it costs one check when off.
///
/// When on, every chat turn appends one JSON line to `~/Library/Logs/Sevra/chat-timing.jsonl`:
/// each timed step from Send to the reply on screen, in seconds since Send, with token counts,
/// tool names and the model's per-call figures. Starting the engine ahead of a request writes a
/// line of its own. No message text, arguments or results are written, and nothing leaves the
/// Mac. `python3 scripts/chat_timing.py` prints the steps of each turn and compares the turns.
public enum ChatTiming {
  public static let enabled: Bool = {
    if let value = ProcessInfo.processInfo.environment["SEVRA_CHAT_TIMING"], !value.isEmpty {
      return value != "0"
    }
    return UserDefaults.standard.bool(forKey: "SevraChatTiming")
  }()
  public static var logFile: URL {
    if let path = ProcessInfo.processInfo.environment["SEVRA_CHAT_TIMING_LOG"], !path.isEmpty {
      return URL(fileURLWithPath: path)
    }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Logs/Sevra/chat-timing.jsonl")
  }
  public static var now: Double { ProcessInfo.processInfo.systemUptime }

  private final class Record {
    let kind: String
    let start: Double
    let wall = Date()
    var fields: [String: Value]
    var events: [Value] = []
    var totals: [String: (count: Int, seconds: Double)] = [:]
    /// A turn whose request has finished and that now waits for its reply on screen.
    var awaitingReply: String?
    init(kind: String, start: Double, fields: [String: Value]) {
      self.kind = kind
      self.start = start
      self.fields = fields
    }
  }
  private static let lock = NSLock()
  nonisolated(unsafe) private static var open: [Record] = []
  nonisolated(unsafe) private static var sendPressed: Double?
  nonisolated(unsafe) private static var sequence = 0

  private static func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  /// The composer's Send. The turn that starts right after measures from here.
  public static func pressedSend() {
    guard enabled else { return }
    let time = now
    withLock { sendPressed = time }
  }

  /// Starts a turn, unless one is already running: the app starts it at Send and the product
  /// layer starts one only for a caller without a screen, such as `sevra ask`. A turn still
  /// waiting for its reply on screen is written first.
  @discardableResult public static func beginTurn(origin: String, conversation: String) -> Bool {
    guard enabled else { return false }
    let time = now
    var finished: [Record] = []
    let began: Bool = withLock {
      if open.contains(where: { $0.kind == "turn" && $0.awaitingReply == nil }) { return false }
      finished = open.filter { $0.kind == "turn" }
      open.removeAll { $0.kind == "turn" }
      let pressed = sendPressed.flatMap { time - $0 < 2 ? $0 : nil }
      sendPressed = nil
      sequence += 1
      let record = Record(
        kind: "turn", start: pressed ?? time,
        fields: [
          "origin": .string(origin), "conversation": .string(conversation),
          "turnInProcess": .number(Double(sequence)),
        ])
      if pressed != nil { record.events.append(event("ui.send", at: 0)) }
      record.events.append(event("turn.begin", at: time - record.start))
      open.append(record)
      return true
    }
    for record in finished { write(record, outcome: "superseded") }
    if began && Thread.isMainThread { watchMainThread() }
    return began
  }

  /// While an app turn is open, how late the main thread runs a block due every 50 ms. Lateness
  /// above 20 ms is added up, and a stall over 250 ms is listed with its length.
  private static func watchMainThread() {
    let due = now + 0.05
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      let late = now - due
      if late > 0.02 { add("ui.main_thread_late", seconds: late) }
      if late > 0.25 { mark("ui.main_thread_stall", ["seconds": .number(rounded(late))]) }
      if turnOpen { watchMainThread() }
    }
  }

  /// A record of its own for work no request waits for yet, such as starting the engine when a
  /// workbook opens. Events while it is open go to it and to any turn that is open.
  public static func beginBackground(_ kind: String) {
    guard enabled else { return }
    let time = now
    withLock { open.append(Record(kind: kind, start: time, fields: [:])) }
  }
  public static func endBackground(_ kind: String, outcome: String) {
    guard enabled else { return }
    let records: [Record] = withLock {
      let ended = open.filter { $0.kind == kind }
      open.removeAll { $0.kind == kind }
      return ended
    }
    for record in records { write(record, outcome: outcome) }
  }

  private static func event(_ name: String, at: Double, seconds: Double? = nil, fields: [String: Value] = [:]) -> Value {
    var object = fields
    object["name"] = .string(name)
    object["at"] = .number(rounded(at))
    if let seconds { object["seconds"] = .number(rounded(seconds)) }
    return .object(object)
  }
  private static func rounded(_ value: Double) -> Double { (value * 1_000_000).rounded() / 1_000_000 }

  private static func append(_ name: String, started: Double, ended: Double?, fields: [String: Value]) {
    withLock {
      for record in open {
        record.events.append(
          event(
            name, at: started - record.start, seconds: ended.map { $0 - started }, fields: fields))
      }
    }
  }

  /// A moment, such as the first answer text reaching the screen.
  public static func mark(_ name: String, _ fields: [String: Value] = [:]) {
    guard enabled else { return }
    append(name, started: now, ended: nil, fields: fields)
  }
  /// A step that already ran, from its start time.
  public static func record(_ name: String, since start: Double, _ fields: [String: Value] = [:]) {
    guard enabled else { return }
    append(name, started: start, ended: now, fields: fields)
  }
  /// A step measured by its caller.
  public static func record(
    _ name: String, from start: Double, to end: Double, _ fields: [String: Value] = [:]
  ) {
    guard enabled else { return }
    append(name, started: start, ended: end, fields: fields)
  }
  public static func span<T>(
    _ name: String, _ fields: [String: Value] = [:], _ body: () throws -> T
  ) rethrows -> T {
    guard enabled else { return try body() }
    let start = now
    do {
      let result = try body()
      append(name, started: start, ended: now, fields: fields)
      return result
    } catch {
      var failed = fields
      failed["failed"] = .bool(true)
      append(name, started: start, ended: now, fields: failed)
      throw error
    }
  }
  public static func asyncSpan<T>(
    _ name: String, _ fields: [String: Value] = [:], _ body: () async throws -> T
  ) async rethrows -> T {
    guard enabled else { return try await body() }
    let start = now
    do {
      let result = try await body()
      append(name, started: start, ended: now, fields: fields)
      return result
    } catch {
      var failed = fields
      failed["failed"] = .bool(true)
      append(name, started: start, ended: now, fields: failed)
      throw error
    }
  }
  /// A running total for something too frequent to list one by one, such as waits for the
  /// workbook lock.
  public static func add(_ name: String, seconds: Double) {
    guard enabled else { return }
    withLock {
      for record in open {
        let total = record.totals[name] ?? (0, 0)
        record.totals[name] = (total.count + 1, total.seconds + seconds)
      }
    }
  }
  /// A value for the open turn as a whole.
  public static func set(_ key: String, _ value: Value) {
    guard enabled else { return }
    withLock {
      for record in open where record.kind == "turn" { record.fields[key] = value }
    }
  }
  public static var turnOpen: Bool {
    guard enabled else { return false }
    return withLock { open.contains { $0.kind == "turn" } }
  }

  /// The request finished. With a reply to show, the turn stays open until the chat on screen
  /// shows it, or for at most 15 seconds; a failed or stopped request ends the turn now.
  public static func requestFinished(awaitingReplyTo request: String?, outcome: String) {
    guard enabled else { return }
    mark("turn.request_finished", ["outcome": .string(outcome)])
    guard let request, !["failed", "cancelled"].contains(outcome) else {
      endTurn(outcome: outcome)
      return
    }
    withLock {
      for record in open where record.kind == "turn" { record.awaitingReply = request }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
      if awaitingReply == request { endTurn(outcome: "reply_not_seen") }
    }
  }
  /// The request whose reply the open turn is waiting to see, if any.
  public static var awaitingReply: String? {
    guard enabled else { return nil }
    return withLock { open.first { $0.kind == "turn" }?.awaitingReply.flatMap { $0.isEmpty ? nil : $0 } }
  }
  /// Call on the main thread when the chat on screen first has the reply. The turn ends after the
  /// next pass of the main run loop, once SwiftUI has laid out and drawn that change.
  public static func replyInView(_ request: String) {
    guard enabled else { return }
    let first: Bool = withLock {
      guard let record = open.first(where: { $0.kind == "turn" }), record.awaitingReply == request
      else { return false }
      record.awaitingReply = ""
      return true
    }
    guard first else { return }
    mark("ui.reply_in_view")
    DispatchQueue.main.async {
      mark("ui.reply_drawn")
      endTurn(outcome: "complete")
    }
  }
  /// Ends the open turn, even one still running. A product-layer turn ends here too.
  public static func endTurn(outcome: String) {
    guard enabled else { return }
    let records: [Record] = withLock {
      let ended = open.filter { $0.kind == "turn" }
      open.removeAll { $0.kind == "turn" }
      return ended
    }
    for record in records { write(record, outcome: outcome) }
  }

  private static func write(_ record: Record, outcome: String) {
    let end = now
    var line = record.fields
    line["kind"] = .string(record.kind)
    line["outcome"] = .string(outcome)
    line["startedAt"] = .string(ISO8601DateFormatter().string(from: record.wall))
    line["seconds"] = .number(rounded(end - record.start))
    line["process"] = .string(ProcessInfo.processInfo.processName)
    line["events"] = .array(record.events)
    line["totals"] = .object(
      record.totals.mapValues {
        .object(["count": .number(Double($0.count)), "seconds": .number(rounded($0.seconds))])
      })
    guard let text = try? Value.object(line).json() else { return }
    let file = logFile
    try? FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: file.path) {
      FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
    }
    guard let handle = try? FileHandle(forWritingTo: file) else { return }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: Data((text + "\n").utf8))
  }
}
