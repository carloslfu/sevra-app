import Foundation

public struct SplashError: LocalizedError, CustomStringConvertible, Sendable {
  public let description: String
  /// An original that is missing or differs. Setup can repair that; it cannot repair anything else.
  public let repairable: Bool
  public var errorDescription: String? { description }
  public init(_ message: String, repairable: Bool = false) {
    description = message
    self.repairable = repairable
  }
}

func check(_ condition: Bool, _ message: String) throws {
  if !condition { throw SplashError(message) }
}

// Splash 1.4.1 protocol v11. Layout is pinned against upstream's byte fixtures.
// This frontend initially submits text only. Images remain an explicit unsupported input.
public enum SplashWire {
  public static let version: UInt16 = 11
  public static let maxTokens = 1 << 20
  public static let maxStatusBytes = 32 * 1024 * 1024
  public struct Sampling: Sendable, Equatable {
    public var temperature: Float = 0
    public var topP: Float = 1
    public var topK: UInt32 = 0
    public var presence: Float = 0
    public var frequency: Float = 0
    public var repetition: Float = 1
    public var minP: Float = 0
    public init() {}
    func validate() throws {
      try check(
        temperature == 0 || (temperature.isFinite && temperature >= Float.leastNormalMagnitude),
        "Invalid temperature")
      try check(topP > 0 && topP <= 1 && minP >= 0 && minP <= 1, "Invalid sampling probabilities")
      try check(
        abs(presence) <= 2 && abs(frequency) <= 2 && repetition.isFinite && repetition > 0,
        "Invalid penalties")
    }
  }
  public struct Thinking: Sendable {
    public let tokens: UInt32
    public let end: [UInt32]
    public let alsoEnds: UInt32
    public init(tokens: UInt32, end: [UInt32], alsoEnds: UInt32) {
      self.tokens = tokens
      self.end = end
      self.alsoEnds = alsoEnds
    }
  }
  public struct Request: Sendable {
    public var id: UInt64
    public var priority: UInt8 = 0
    public var absoluteDeadline: UInt64
    public var remainingDeadline: UInt64
    public var maxOutput: UInt32 = 1800
    public var prompt: [UInt32]
    public var sampling = Sampling()
    public var seed: UInt64 = 42
    public var tokenMask = false
    public var scores: [UInt32] = []
    public var generationTokens: UInt32 = 0
    public var flags: UInt32 = 0
    public var saltLow: UInt64 = 0
    public var saltHigh: UInt64 = 0
    public var thinking: Thinking?
    public init(id: UInt64, prompt: [UInt32], absoluteDeadline: UInt64, remainingDeadline: UInt64) {
      self.id = id
      self.prompt = prompt
      self.absoluteDeadline = absoluteDeadline
      self.remainingDeadline = remainingDeadline
    }
    public func encoded() throws -> Data {
      try check(id != 0 && priority <= 2, "Invalid request identity or priority")
      try check(absoluteDeadline > 0 && remainingDeadline > 0, "Invalid deadline")
      try check(
        !prompt.isEmpty && prompt.count <= maxTokens && generationTokens < prompt.count,
        "Invalid prompt size")
      try check(flags & ~3 == 0, "Unknown request flags")
      try sampling.validate()
      if scores.isEmpty {
        try check(maxOutput > 0 && maxOutput <= maxTokens, "Invalid output limit")
      } else {
        try check(
          scores.count >= 2 && scores.count <= 255 && Set(scores).count == scores.count,
          "Invalid score tokens")
        try check(
          maxOutput == 0 && sampling == Sampling() && !tokenMask && thinking == nil,
          "Invalid scoring configuration")
      }
      try check(
        flags & 1 == 0 || (!tokenMask && scores.isEmpty),
        "Ignore-EOS requires unconstrained generation")
      if let thinking {
        try check(
          thinking.tokens < UInt32.max && (1...64).contains(thinking.end.count),
          "Invalid thinking budget")
        try check(
          !thinking.end.dropLast().contains(thinking.end.last!)
            && !thinking.end.dropLast().contains(thinking.alsoEnds), "Ambiguous thinking terminator"
        )
      }
      var w = Writer()
      w.u64(id)
      w.u8(priority)
      w.u8(tokenMask ? 1 : 0)
      w.u64(absoluteDeadline)
      w.u64(remainingDeadline)
      w.u32(maxOutput)
      w.u32(UInt32(prompt.count))
      w.u32(0)  // No image spans.
      w.f32(sampling.temperature)
      w.f32(sampling.topP)
      w.u32(sampling.topK)
      w.f32(sampling.presence)
      w.f32(sampling.frequency)
      w.f32(sampling.repetition)
      w.f32(sampling.minP)
      w.u64(seed)
      w.u32(UInt32(scores.count))
      w.u32(generationTokens)
      w.u32(flags)
      w.u64(saltLow)
      w.u64(saltHigh)
      w.u32(thinking?.tokens ?? UInt32.max)
      w.u32(UInt32(thinking?.end.count ?? 0))
      w.u32(thinking?.alsoEnds ?? 0)
      for token in prompt { w.u32(token) }
      for token in scores { w.u32(token) }
      for token in thinking?.end ?? [] { w.u32(token) }
      return frame(1, w.data)
    }
  }
  public static func cancel(_ id: UInt64) throws -> Data {
    try check(id > 0, "Cancel needs a request id")
    var w = Writer()
    w.u64(id)
    return frame(2, w.data)
  }
  public static func mask(id: UInt64, maskID: UInt64, words: [UInt32]) throws -> Data {
    try check(
      id > 0 && maskID > 0 && !words.isEmpty && words.count <= maxTokens, "Invalid mask response")
    var w = Writer()
    w.u64(id)
    w.u64(maskID)
    w.u32(UInt32(words.count))
    for word in words { w.u32(word) }
    return frame(3, w.data)
  }
  public static func status(_ id: UInt64, release: Bool = false) -> Data {
    var w = Writer()
    w.u64(id)
    return frame(release ? 5 : 4, w.data)
  }
  static func frame(_ type: UInt16, _ payload: Data) -> Data {
    var w = Writer()
    w.data.append(contentsOf: [83, 80, 76, 72])
    w.u16(version)
    w.u16(type)
    w.u64(UInt64(payload.count))
    w.data.append(payload)
    return w.data
  }
  public enum Finish: UInt8, Sendable { case stop = 0, length = 1, cancelled = 2 }
  public struct Done: Sendable, Equatable {
    public let id: UInt64
    public let reason: Finish
    public let bounded: Bool
    public let prompt: UInt32
    public let completion: UInt32
    public let prefillMicros: UInt64
    public let decodeMicros: UInt64
    public let wallMicros: UInt64
    public let deduplicated: UInt32
    public let drafted: UInt32
    public let accepted: UInt32
    public let cycles: UInt32
    public let logits: [Float]
  }
  public struct Failure: LocalizedError, Sendable, Equatable, CustomStringConvertible {
    public let classification: UInt8
    public let retryable: Bool
    public let retryAfter: UInt32
    public let id: UInt64
    public let code: Data
    public let message: Data
    public var description: String {
      String(decoding: code, as: UTF8.self) + ": " + String(decoding: message, as: UTF8.self)
    }
    public var errorDescription: String? { description }
  }
  public enum Event: Sendable, Equatable {
    case ready(concurrent: UInt32, context: UInt32, vision: Bool)
    case start(id: UInt64, lane: UInt32, matched: UInt32)
    case progress(id: UInt64, processed: UInt32, micros: UInt64)
    case tokens(id: UInt64, offset: UInt32, tokens: [UInt32])
    case mask(id: UInt64, maskID: UInt64, words: UInt32, simulation: [UInt32])
    case done(Done)
    case error(Failure)
    case status(id: UInt64, json: Data)
  }

  static func header(_ data: Data) throws -> (UInt16, Int) {
    var r = Reader(data)
    try check(try r.bytes(4) == Data([83, 80, 76, 72]), "Bad Splash magic")
    try check(try r.u16() == version, "Unsupported Splash protocol version")
    let type = try r.u16()
    let length = try r.u64()
    let bounds: ClosedRange<UInt64>
    switch type {
    case 0x100: bounds = 9...9
    case 0x101: bounds = 16...16
    case 0x108: bounds = 20...20
    case 0x102: bounds = 16...(16 + 4096 * 4)
    case 0x103: bounds = 24...(24 + 32 * 4)
    case 0x104: bounds = 62...(62 + 255 * 4)
    case 0x105: bounds = 22...(22 + 2 * 1024 * 1024)
    case 0x107: bounds = 8...UInt64(8 + maxStatusBytes)
    default: throw SplashError("Unknown native event type")
    }
    try check(bounds.contains(length), "Invalid native frame length")
    return (type, Int(length))
  }
  static func event(type: UInt16, data: Data) throws -> Event {
    var r = Reader(data)
    let event: Event
    switch type {
    case 0x100:
      let lanes = try r.u32()
      let context = try r.u32()
      let vision = try r.u8()
      try check(lanes > 0 && context > 0 && vision <= 1, "Invalid native capacities")
      event = .ready(concurrent: lanes, context: context, vision: vision == 1)
    case 0x101:
      event = .start(id: try r.id(), lane: try r.u32(), matched: try r.u32())
    case 0x108:
      let id = try r.id()
      let n = try r.u32()
      let elapsed = try r.u64()
      try check(n <= maxTokens, "Invalid prefill count")
      event = .progress(id: id, processed: n, micros: elapsed)
    case 0x102:
      let id = try r.id()
      let offset = try r.u32()
      let count = try r.u32()
      try check(
        count > 0 && count <= 4096 && UInt64(offset) + UInt64(count) <= UInt32.max,
        "Invalid token range")
      event = .tokens(id: id, offset: offset, tokens: try r.words(count))
    case 0x103:
      let id = try r.id()
      let maskID = try r.id()
      let words = try r.u32()
      let count = try r.u32()
      try check(
        words > 0 && count <= 32 && UInt64(words) * (UInt64(count) + 1) <= maxTokens,
        "Invalid mask dimensions")
      event = .mask(id: id, maskID: maskID, words: words, simulation: try r.words(count))
    case 0x104:
      let id = try r.id()
      let rawReason = try r.u8()
      let bounded = try r.u8()
      guard let reason = Finish(rawValue: rawReason) else {
        throw SplashError("Invalid finish reason")
      }
      try check(bounded <= 1 && (bounded == 0 || reason == .length), "Invalid bounded completion")
      let prompt = try r.u32()
      let completion = try r.u32()
      let prefill = try r.u64()
      let decode = try r.u64()
      let wall = try r.u64()
      let dedup = try r.u32()
      let drafted = try r.u32()
      let accepted = try r.u32()
      let cycles = try r.u32()
      let count = try r.u32()
      try check(
        count <= 255 && accepted <= drafted && cycles <= drafted && (drafted == 0 || cycles > 0),
        "Invalid completion statistics")
      let logits = try r.words(count).map { Float(bitPattern: $0) }
      try check(
        logits.isEmpty
          || (logits.count >= 2 && logits.allSatisfy(\.isFinite) && reason == .stop
            && completion == 0 && decode == 0 && drafted == 0),
        "Invalid score completion")
      event = .done(
        Done(
          id: id, reason: reason, bounded: bounded == 1, prompt: prompt, completion: completion,
          prefillMicros: prefill, decodeMicros: decode, wallMicros: wall, deduplicated: dedup,
          drafted: drafted, accepted: accepted, cycles: cycles, logits: logits))
    case 0x105:
      let kind = try r.u8()
      let retryable = try r.u8()
      let retryAfter = try r.u32()
      let id = try r.u64()
      let codeCount = try r.u32()
      let messageCount = try r.u32()
      try check(
        (1...3).contains(kind) && retryable <= 1 && ((kind == 1) == (id > 0)),
        "Invalid error classification")
      try check(retryAfter == 0 || retryable == 1, "Invalid retry delay")
      try check(
        codeCount > 0 && codeCount <= 1 << 20 && messageCount <= 1 << 20, "Invalid error strings")
      event = .error(
        Failure(
          classification: kind, retryable: retryable == 1, retryAfter: retryAfter, id: id,
          code: try r.bytes(Int(codeCount)), message: try r.bytes(Int(messageCount))))
    case 0x107:
      let id = try r.u64()
      try check(r.remaining > 0, "Empty status JSON")
      event = .status(id: id, json: try r.bytes(r.remaining))
    default: throw SplashError("Unknown event")
    }
    try check(r.remaining == 0, "Unexpected trailing event bytes")
    return event
  }

  public struct Decoder {
    private var buffer = Data()
    private var failed = false
    public init() {}
    public mutating func consume(_ bytes: Data) throws -> [Event] {
      do {
        try check(!failed, "Decoder already failed")
        try check(bytes.count <= 65536, "Input chunk exceeds the bounded reader size")
        buffer.append(bytes)
        var result: [Event] = []
        var offset = 0
        while buffer.count - offset >= 16 {
          let (type, size) = try header(buffer.subdata(in: offset..<offset + 16))
          if buffer.count - offset < size + 16 { break }
          result.append(
            try event(type: type, data: buffer.subdata(in: offset + 16..<offset + 16 + size)))
          offset += 16 + size
        }
        if offset > 0 { buffer = buffer.subdata(in: offset..<buffer.count) }
        return result
      } catch {
        failed = true
        buffer.removeAll()
        throw error
      }
    }
    public mutating func finish() throws {
      if failed || !buffer.isEmpty {
        failed = true
        buffer.removeAll()
        throw SplashError("Truncated or failed native stream")
      }
    }
  }
}

private struct Writer {
  var data = Data()
  mutating func u8(_ n: UInt8) { data.append(n) }
  mutating func u16(_ n: UInt16) {
    var n = n.littleEndian
    withUnsafeBytes(of: &n) { data.append(contentsOf: $0) }
  }
  mutating func u32(_ n: UInt32) {
    var n = n.littleEndian
    withUnsafeBytes(of: &n) { data.append(contentsOf: $0) }
  }
  mutating func u64(_ n: UInt64) {
    var n = n.littleEndian
    withUnsafeBytes(of: &n) { data.append(contentsOf: $0) }
  }
  mutating func f32(_ n: Float) { u32(n.bitPattern) }
}
private struct Reader {
  let data: Data
  var offset = 0
  init(_ data: Data) { self.data = data }
  var remaining: Int { data.count - offset }
  mutating func bytes(_ n: Int) throws -> Data {
    try check(n >= 0 && n <= remaining, "Truncated native payload")
    defer { offset += n }
    return data.subdata(in: offset..<offset + n)
  }
  mutating func integer(_ n: Int) throws -> UInt64 {
    try check(n <= remaining, "Truncated native integer")
    var value: UInt64 = 0
    for i in 0..<n { value |= UInt64(data[data.startIndex + offset + i]) << (8 * i) }
    offset += n
    return value
  }
  mutating func u8() throws -> UInt8 { UInt8(try integer(1)) }
  mutating func u16() throws -> UInt16 { UInt16(try integer(2)) }
  mutating func u32() throws -> UInt32 { UInt32(try integer(4)) }
  mutating func u64() throws -> UInt64 { try integer(8) }
  mutating func id() throws -> UInt64 {
    let id = try u64()
    try check(id > 0, "Missing request id")
    return id
  }
  mutating func words(_ n: UInt32) throws -> [UInt32] {
    try check(Int(n) * 4 == remaining, "Native array count does not match payload")
    var words: [UInt32] = []
    words.reserveCapacity(Int(n))
    for _ in 0..<n { words.append(try u32()) }
    return words
  }
}
