import Foundation
import SevraSplash

/// ByteLevel streaming for the pinned Qwen tokenizer. Verified against Splash's
/// CallbackStreamer and tokenizers DecodeStream. No whole-response redecoding.
/// A worker owns one instance per request; terminal/error state cannot be reused.
public final class SplashTextStream {
  private let vocabulary: SplashTextFrontend.ByteVocabulary
  private let offsets: [Int]
  private let special: Set<UInt32>
  private let added: Set<UInt32>
  private let stops: [Data]
  private var partial: [UInt8] = []
  private var held = ""
  private var stopPending = Data()
  private var terminal = false
  private var tokenCount = 0
  private var byteCount = 0
  public private(set) var matchedStop: String?
  public static let maximumBytes = 2 * 1024 * 1024

  init(
    vocabulary: SplashTextFrontend.ByteVocabulary, special: Set<UInt32>,
    added: Set<UInt32>, stopSequences: [String]
  ) throws {
    guard stopSequences.count <= 16,
      stopSequences.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 })
    else {
      throw SplashError("Invalid output stop sequences")
    }
    self.vocabulary = vocabulary
    self.special = special
    self.added = added
    stops = stopSequences.map { Data($0.utf8) }
    offsets = vocabulary.offsets
  }

  /// Returns new visible text only. The transport still owns cancellation and
  /// draining the terminal event when a caller observes matchedStop.
  public func append(_ token: UInt32) throws -> String {
    guard !terminal else { throw SplashError("Text stream has already ended") }
    do {
      guard token < SplashTextFrontend.vocabularySize,
        tokenCount < SplashWire.maxTokens
      else { throw SplashError("Invalid output token") }
      tokenCount += 1
      if matchedStop != nil || special.contains(token) { return "" }
      var start = offsets[Int(token)]
      let end = offsets[Int(token) + 1]
      if added.contains(token) && vocabulary.bytes[start] == 0xff {
        // 0xff is a grammar sentinel only for added/padded entries. It can
        // also be an ordinary byte token, which must decode to U+FFFD.
        start += 1
      }
      byteCount += end - start
      guard byteCount <= Self.maximumBytes else {
        throw SplashError("Output text exceeds its limit")
      }
      var bytes = partial
      bytes.append(contentsOf: vocabulary.bytes[start..<end])
      let retained = Self.incompleteSuffix(bytes)
      partial = Array(bytes.suffix(retained))
      held += String(decoding: bytes.dropLast(retained), as: UTF8.self)
      // The reference holds the complete delta until it no longer ends in a
      // replacement character. This includes a literal U+FFFD at the end.
      guard partial.isEmpty, held.unicodeScalars.last?.value != 0xfffd else { return "" }
      let ready = held
      held = ""
      return emit(ready)
    } catch {
      terminal = true
      throw error
    }
  }

  public func finish() throws -> String {
    guard !terminal else { throw SplashError("Text stream has already ended") }
    terminal = true
    if matchedStop != nil { return "" }
    // Splash drops an unfinished character and trailing replacement characters.
    while held.unicodeScalars.last?.value == 0xfffd { held.unicodeScalars.removeLast() }
    var result = emit(held)
    held = ""
    partial = []
    if matchedStop == nil {
      result += String(decoding: stopPending, as: UTF8.self)
      stopPending = Data()
    }
    return result
  }

  private func emit(_ text: String) -> String {
    guard !text.isEmpty, matchedStop == nil else { return "" }
    if stops.isEmpty { return text }
    stopPending.append(contentsOf: text.utf8)
    var first: (Range<Data.Index>, Int)?
    for (index, stop) in stops.enumerated() {
      if let range = stopPending.range(of: stop),
        first == nil || range.lowerBound < first!.0.lowerBound
      {
        first = (range, index)
      }
    }
    if let first {
      let ready = String(decoding: stopPending[..<first.0.lowerBound], as: UTF8.self)
      matchedStop = String(decoding: stops[first.1], as: UTF8.self)
      stopPending = Data()
      return ready
    }
    let keep = heldMarkerBytes(stopPending, markers: stops)
    let ready = String(decoding: stopPending.dropLast(keep), as: UTF8.self)
    stopPending = Data(stopPending.suffix(keep))
    return ready
  }

  /// A valid but unfinished UTF-8 sequence has at most three bytes. Invalid
  /// sequences decode immediately with the same maximal-subpart replacement.
  private static func incompleteSuffix(_ bytes: [UInt8]) -> Int {
    guard !bytes.isEmpty else { return 0 }
    var start = bytes.count - 1
    while start > 0 && (0x80...0xbf).contains(bytes[start]) && bytes.count - start < 4 {
      start -= 1
    }
    let lead = bytes[start]
    let length =
      (0xc2...0xdf).contains(lead)
      ? 2 : (0xe0...0xef).contains(lead) ? 3 : (0xf0...0xf4).contains(lead) ? 4 : 0
    let count = bytes.count - start
    guard length > count else { return 0 }
    for position in 1..<count {
      let byte = bytes[start + position]
      guard (0x80...0xbf).contains(byte) else { return 0 }
      if position == 1
        && ((lead == 0xe0 && byte < 0xa0) || (lead == 0xed && byte > 0x9f)
          || (lead == 0xf0 && byte < 0x90) || (lead == 0xf4 && byte > 0x8f))
      {
        return 0
      }
    }
    return count
  }
}

/// Exact UTF-8 matching avoids Swift's canonical-equivalence String comparison
/// when the protocol needs to distinguish bytes and split marker prefixes.
func heldMarkerBytes(_ data: Data, markers: [Data]) -> Int {
  let maximum = min(data.count, (markers.map(\.count).max() ?? 1) - 1)
  guard maximum > 0 else { return 0 }
  for length in stride(from: maximum, through: 1, by: -1) {
    if markers.contains(where: {
      length < $0.count && data.suffix(length).elementsEqual($0.prefix(length))
    }) {
      return length
    }
  }
  return 0
}
