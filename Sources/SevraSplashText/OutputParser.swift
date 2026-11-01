import CoreFoundation
import Foundation
import SevraSplash

/// The workbook supplies its own fixed tool names and parameter types. This is
/// projection metadata, not permission to execute or a complete JSON schema.
public struct SplashOutputTool: Sendable {
  public let name: String
  public let parameters: [String: Set<String>]
  public init(name: String, parameters: [String: Set<String>]) {
    self.name = name
    self.parameters = parameters
  }
}

public enum SplashOutputDelta: Sendable, Equatable {
  case text(String)
  case reasoning(String)
}

/// A complete syntactic candidate. The workbook agent must still validate its
/// complete schema, evidence references and authority before dispatching it.
public struct SplashToolCandidate: Sendable {
  public let name: String
  public let arguments: Data
}

public struct SplashParsedOutput: Sendable {
  public let text: String
  public let reasoning: String
  public let calls: [SplashToolCandidate]
  public let finish: SplashWire.Finish
}

/// Selected Qwen XML and reasoning projection. Behavior follows Splash 1.4.1
/// server/output.py; attribution/license: integration/licenses/Splash-Apache-2.0.txt.
/// Sevra deliberately refuses ambiguous/unfinished calls, unknown names and
/// duplicate fields. Upstream's permissive repair is not action authority.
public final class SplashOutputParser {
  private enum State { case output, json, content, name, arguments, parameter, value, closing }
  private static let call = Data("<tool_call>\n<function=".utf8)
  private static let thinkEnd = Data("</think>".utf8)
  private static let callEnd = Data("</tool_call>".utf8)
  private static let functionEnd = Data("</function>".utf8)
  private static let key = Data("<parameter=".utf8)
  private static let valueEnd = Data("\n</parameter>\n".utf8)
  private static let greater = Data(">".utf8)
  private static let argumentTags = [key, functionEnd, callEnd]
  private static let valueEnds = argumentTags.map { valueEnd + $0 }
  private let tools: [String: SplashOutputTool]
  private let textTags: [Data]
  private let reasoningEnds: [Data]
  private var state: State
  public var isReasoning: Bool { reasoningOpen }
  private var reasoningOpen: Bool
  private var reasoningPending = Data()
  private var separator = false
  private var pending = Data()
  private var terminal = false
  private var bytes = 0
  private var text = ""
  private var reasoning = ""
  private var heldWhitespace = ""
  private var visible: Bool
  private var name: String?
  private var parameter: String?
  private var value = ""
  private var valueStarted = false
  private var arguments: [String: Any] = [:]
  private var calls: [SplashToolCandidate] = []

  public init(tools: [SplashOutputTool] = [], thinking: Bool = false, structured: Bool = false)
    throws
  {
    let validTypes: Set<String> = [
      "string", "number", "integer", "boolean", "null", "object", "array",
    ]
    func validName(_ name: String) -> Bool {
      !name.isEmpty && name.utf8.count <= 256
        && name.utf8.allSatisfy {
          (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
            || [45, 46, 95].contains($0)
        }
    }
    guard tools.count <= 128, Set(tools.map(\.name)).count == tools.count,
      tools.allSatisfy({
        validName($0.name) && $0.parameters.count <= 128
          && $0.parameters.allSatisfy({
            validName($0.key) && !$0.value.isEmpty && $0.value.isSubset(of: validTypes)
          })
      })
    else {
      throw SplashError("Unsupported workbook tool projection")
    }
    self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    textTags = tools.isEmpty ? [Self.thinkEnd] : [Self.call, Self.thinkEnd]
    reasoningEnds = textTags
    reasoningOpen = thinking
    state = structured ? .output : .content
    visible = tools.isEmpty
  }

  /// Streams visible text/reasoning only. No tool can escape before finish.
  public func append(_ fragment: String) throws -> [SplashOutputDelta] {
    guard !terminal else { throw SplashError("Output parser has already ended") }
    do {
      bytes += fragment.utf8.count
      guard bytes <= SplashTextStream.maximumBytes else {
        throw SplashError("Model output exceeds its limit")
      }
      var events: [SplashOutputDelta] = []
      if reasoningOpen {
        reasoningPending.append(contentsOf: fragment.utf8)
        if let (range, marker) = next(in: reasoningPending, tags: reasoningEnds) {
          let part = String(decoding: reasoningPending[..<range.lowerBound], as: UTF8.self)
          emitReasoning(part, into: &events)
          let isThinkEnd = marker == Self.thinkEnd
          let rest = Data(reasoningPending[(isThinkEnd ? range.upperBound : range.lowerBound)...])
          reasoningPending = Data()
          reasoningOpen = false
          separator = isThinkEnd
          try content(rest, into: &events)
        } else {
          let keep = heldMarkerBytes(reasoningPending, markers: reasoningEnds)
          emitReasoning(
            String(decoding: reasoningPending.dropLast(keep), as: UTF8.self), into: &events)
          reasoningPending = Data(reasoningPending.suffix(keep))
        }
      } else {
        try content(Data(fragment.utf8), into: &events)
      }
      return events
    } catch {
      terminal = true
      throw error
    }
  }

  /// Only a successful native terminal may return calls. Truncated/cancelled
  /// results preserve display text but discard even previously closed calls.
  public func finish(_ reason: SplashWire.Finish) throws -> (
    SplashParsedOutput, [SplashOutputDelta]
  ) {
    guard !terminal else { throw SplashError("Output parser has already ended") }
    terminal = true
    var events: [SplashOutputDelta] = []
    if reasoningOpen {
      emitReasoning(String(decoding: reasoningPending, as: UTF8.self), into: &events)
      reasoningPending = Data()
    }
    if reason == .stop {
      guard ![State.name, .arguments, .parameter, .value].contains(state) else {
        throw SplashError("Model ended inside a tool call")
      }
      if state == .closing && !trimASCII(pending).isEmpty {
        throw SplashError("Model ended inside a tool closing marker")
      }
    }
    if [.content, .json, .output].contains(state), !pending.isEmpty {
      let partial = reason != .stop && textTags.contains { $0.starts(with: pending) }
      if !partial { emitText(String(decoding: pending, as: UTF8.self), into: &events) }
    }
    if calls.isEmpty && !heldWhitespace.isEmpty {
      text += heldWhitespace
      events.append(.text(heldWhitespace))
    }
    pending = Data()
    heldWhitespace = ""
    let result = SplashParsedOutput(
      text: text, reasoning: reasoning,
      calls: reason == .stop ? calls : [], finish: reason)
    calls = []
    return (result, events)
  }

  private func content(_ bytes: Data, into events: inout [SplashOutputDelta]) throws {
    var input = bytes
    if separator {
      while input.first == 10 { input.removeFirst() }
      if input.isEmpty { return }
      separator = false
    }
    pending.append(input)
    while !pending.isEmpty {
      switch state {
      case .output:
        let first = String(decoding: pending, as: UTF8.self).trimmingCharacters(
          in: .whitespacesAndNewlines)
        if first.isEmpty { return }
        state = first.hasPrefix("<") ? .content : .json
      case .json:
        emitText(String(decoding: pending, as: UTF8.self), into: &events)
        pending = Data()
      case .content:
        if let (range, marker) = next(in: pending, tags: textTags) {
          emitText(String(decoding: pending[..<range.lowerBound], as: UTF8.self), into: &events)
          pending = Data(pending[range.upperBound...])
          if marker == Self.call { state = .name }
        } else {
          let keep = heldMarkerBytes(pending, markers: textTags)
          emitText(String(decoding: pending.dropLast(keep), as: UTF8.self), into: &events)
          pending = Data(pending.suffix(keep))
          return
        }
      case .name:
        guard let found = try readName() else { return }
        guard tools[found] != nil, calls.count < 16 else {
          throw SplashError("Model named an unavailable tool")
        }
        name = found
        arguments = [:]
        if text.isEmpty { heldWhitespace = "" }
        state = .arguments
      case .arguments:
        guard let (range, marker) = next(in: pending, tags: Self.argumentTags) else {
          let keep = heldMarkerBytes(pending, markers: Self.argumentTags)
          pending = Data(pending.suffix(keep))
          return
        }
        pending = Data(pending[range.upperBound...])
        if marker == Self.key {
          state = .parameter
        } else {
          guard let name else { throw SplashError("Tool call has no name") }
          let data = try JSONSerialization.data(
            withJSONObject: arguments, options: [.sortedKeys, .withoutEscapingSlashes])
          guard data.count <= 256 * 1024 else {
            throw SplashError("Tool arguments exceed their limit")
          }
          calls.append(SplashToolCandidate(name: name, arguments: data))
          self.name = nil
          arguments = [:]
          visible = false
          state = marker == Self.callEnd ? .content : .closing
        }
      case .parameter:
        guard let found = try readName() else { return }
        guard let name, tools[name]?.parameters[found] != nil, arguments[found] == nil else {
          throw SplashError("Tool named an unknown or duplicate parameter")
        }
        parameter = found
        value = ""
        valueStarted = false
        state = .value
      case .value:
        if let (range, _) = next(in: pending, tags: Self.valueEnds) {
          try appendValue(Data(pending[..<range.lowerBound]))
          guard let name, let parameter, let types = tools[name]?.parameters[parameter] else {
            throw SplashError("Tool parameter has no declared type")
          }
          arguments[parameter] = try convertValue(value, types: types)
          self.parameter = nil
          value = ""
          pending = Data(pending[(range.lowerBound + Self.valueEnd.count)...])
          state = .arguments
        } else {
          let keep = heldMarkerBytes(pending, markers: Self.valueEnds)
          try appendValue(Data(pending.dropLast(keep)))
          pending = Data(pending.suffix(keep))
          return
        }
      case .closing:
        let rest = Data(pending.drop(while: { [9, 10, 13, 32].contains($0) }))
        if rest.starts(with: Self.callEnd) {
          pending = Data(rest.dropFirst(Self.callEnd.count))
          state = .content
        } else if Self.callEnd.starts(with: rest) {
          return
        } else {
          state = .content
        }
      }
    }
  }

  private func appendValue(_ bytes: Data) throws {
    guard !bytes.isEmpty else { return }
    var part = bytes
    if !valueStarted {
      valueStarted = true
      if part.first == 10 { part.removeFirst() }
    }
    value += String(decoding: part, as: UTF8.self)
    guard value.utf8.count <= 256 * 1024 else {
      throw SplashError("Tool parameter exceeds its limit")
    }
  }

  private func readName() throws -> String? {
    if let range = pending.range(of: Self.greater) {
      guard pending.distance(from: pending.startIndex, to: range.lowerBound) <= 256 else {
        throw SplashError("Tool name exceeds its limit")
      }
      let name = String(decoding: trimASCII(Data(pending[..<range.lowerBound])), as: UTF8.self)
      pending = Data(pending[range.upperBound...])
      return name
    }
    guard pending.count <= 256 else { throw SplashError("Tool name exceeds its limit") }
    return nil
  }
  private func next(in data: Data, tags: [Data]) -> (Range<Data.Index>, Data)? {
    tags.compactMap { tag in data.range(of: tag).map { ($0, tag) } }
      .min { $0.0.lowerBound < $1.0.lowerBound }
  }
  private func trimASCII(_ data: Data) -> Data {
    Data(
      data.drop(while: { [9, 10, 13, 32].contains($0) })
        .reversed().drop(while: { [9, 10, 13, 32].contains($0) }).reversed())
  }
  private func emitReasoning(_ part: String, into events: inout [SplashOutputDelta]) {
    if !part.isEmpty {
      reasoning += part
      events.append(.reasoning(part))
    }
  }
  private func emitText(_ part: String, into events: inout [SplashOutputDelta]) {
    guard !part.isEmpty else { return }
    if !visible {
      if part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        heldWhitespace += part
        return
      }
      visible = true
    }
    let combined = heldWhitespace + part
    heldWhitespace = ""
    text += combined
    events.append(.text(combined))
  }

  private func significantDigits(_ number: String) -> Substring {
    let mantissa = number.prefix { $0 != "e" && $0 != "E" }.filter(\.isNumber)
    var digits = mantissa.drop { $0 == "0" }
    while digits.last == "0" { digits.removeLast() }
    return digits
  }

  private func convertValue(_ text: String, types: Set<String>) throws -> Any {
    if types == ["string"] { return text }
    // Foundation may silently round large JSON integer literals into floating
    // point. Workbook numeric tool inputs must fit Int64; precise decimals and
    // larger identifiers travel as strings. Check before Foundation allocates
    // nested containers or performs any lossy conversion.
    let bytes = Array(text.utf8)
    var index = 0
    var depth = 0
    var quoted = false
    var escaped = false
    var stringStart = 0
    // One entry per open object or array. Foundation keeps only one of a repeated key, and the
    // model's other value would vanish without a word.
    var keys: [Set<String>?] = []
    while index < bytes.count {
      let byte = bytes[index]
      if quoted {
        if escaped {
          escaped = false
        } else if byte == 92 {
          escaped = true
        } else if byte == 34 {
          quoted = false
          var next = index + 1
          while next < bytes.count, [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
          if next < bytes.count, bytes[next] == 58, case .some(.some) = keys.last {
            let literal = Data(bytes[stringStart...index])
            let key = try? JSONSerialization.jsonObject(with: literal, options: [.fragmentsAllowed])
            guard let key = key as? String, keys[keys.count - 1]?.insert(key).inserted == true
            else { throw SplashError("Tool argument repeats a key") }
          }
        }
      } else if byte == 34 {
        quoted = true
        stringStart = index
      } else if byte == 91 || byte == 123 {
        depth += 1
        guard depth <= 32 else { throw SplashError("Tool argument structure exceeds its limit") }
        keys.append(byte == 123 ? [] : nil)
      } else if byte == 93 || byte == 125 {
        depth -= 1
        _ = keys.popLast()
      } else if byte == 45 || (48...57).contains(byte) {
        let start = index
        while index + 1 < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index + 1]) {
          index += 1
        }
        let literal = bytes[start...index]
        if literal.allSatisfy({ $0 == 45 || (48...57).contains($0) })
          && Int64(String(decoding: literal, as: UTF8.self)) == nil
        {
          throw SplashError("Tool integer is outside the supported range; use a string")
        }
        // Double keeps any 15 significant digits. Past that, it must give back the digits written.
        let number = String(decoding: literal, as: UTF8.self)
        let written = significantDigits(number)
        if written.count > 15, let double = Double(number), double.isFinite,
          significantDigits(String(double)) != written
        {
          throw SplashError("Tool number has more digits than the workbook keeps; use a string")
        }
      }
      index += 1
    }
    var parsed = try? JSONSerialization.jsonObject(
      with: Data(text.utf8), options: [.fragmentsAllowed])
    if parsed == nil && !types.contains("string") {
      switch text.trimmingCharacters(in: .whitespacesAndNewlines) {
      case "True" where types.contains("boolean"): parsed = true
      case "False" where types.contains("boolean"): parsed = false
      case "None" where types.contains("null"): parsed = NSNull()
      default: break
      }
    }
    guard let parsed else { return text }
    func kind(_ value: Any) -> String {
      if value is String { return "string" }
      if value is NSNull { return "null" }
      if value is [String: Any] { return "object" }
      if value is [Any] { return "array" }
      if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return "boolean" }
        return ["f", "d"].contains(String(cString: number.objCType)) ? "number" : "integer"
      }
      return "unknown"
    }
    var nodes = 0
    func bound(_ value: Any, depth: Int) throws {
      nodes += 1
      guard depth <= 32, nodes <= 65536 else {
        throw SplashError("Tool argument structure exceeds its limit")
      }
      if let object = value as? [String: Any] {
        for value in object.values { try bound(value, depth: depth + 1) }
      } else if let array = value as? [Any] {
        for value in array { try bound(value, depth: depth + 1) }
      } else if let number = value as? NSNumber, !number.doubleValue.isFinite {
        throw SplashError("Tool argument is not finite")
      }
    }
    try bound(parsed, depth: 1)
    let type = kind(parsed)
    if types.contains("string")
      && (type == "string"
        || !(types.contains(type) || (type == "integer" && types.contains("number"))))
    {
      return text
    }
    return parsed
  }
}
