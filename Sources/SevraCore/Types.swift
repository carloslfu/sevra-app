import Foundation

public enum Value: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([Value])
  case object([String: Value])
  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let v = try? c.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? c.decode(String.self) {
      self = .string(v)
    } else if let v = try? c.decode(Double.self) {
      self = .number(v)
    } else if let v = try? c.decode([Value].self) {
      self = .array(v)
    } else {
      self = .object(try c.decode([String: Value].self))
    }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    }
  }
  public var string: String? {
    if case .string(let v) = self { return v }
    return nil
  }
  public var text: String {
    switch self {
    case .string(let s): return s
    case .number(let n): return String(n)
    case .bool(let b): return String(b)
    case .null: return ""
    default: return (try? json()) ?? ""
    }
  }
  public var object: [String: Value] {
    if case .object(let v) = self { return v }
    return [:]
  }
  public var array: [Value] {
    if case .array(let v) = self { return v }
    return []
  }
  public var int: Int? {
    if case .number(let n) = self, n.isFinite, n >= Double(Int.min), n < Double(Int.max) {
      return Int(n)
    }
    return Int(text)
  }
  public subscript(_ key: String) -> Value { object[key] ?? .null }
  public func json() throws -> String {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys]
    return String(decoding: try e.encode(self), as: UTF8.self)
  }
  public static func parse(_ string: String) throws -> Value {
    try JSONDecoder().decode(Value.self, from: Data(string.utf8))
  }
}
public struct SevraError: Error, LocalizedError, Codable {
  public let code: String
  public let message: String
  public init(_ code: String, _ message: String) {
    self.code = code
    self.message = message
  }
  public var errorDescription: String? { message }
}
public func require(_ condition: @autoclosure () throws -> Bool, _ code: String, _ message: String)
  throws
{
  if try !condition() { throw SevraError(code, message) }
}
public func identifier() -> String {
  FixtureContext.current?.identifier() ?? UUID().uuidString.lowercased()
}
public func timestamp() -> String {
  FixtureContext.current?.date ?? ISO8601DateFormatter().string(from: Date())
}
public final class Cancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  private var cancellationReason: String?
  private var progresses: [ObjectIdentifier: Progress] = [:]
  private let parent: Cancellation?
  private let deadline: TimeInterval?
  public init(parent: Cancellation? = nil, deadlineAfterSeconds: TimeInterval? = nil) {
    self.parent = parent
    self.deadline = deadlineAfterSeconds.map { ProcessInfo.processInfo.systemUptime + max(0, $0) }
  }
  public var isExpired: Bool {
    deadline.map { ProcessInfo.processInfo.systemUptime >= $0 } ?? false
  }
  public var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled || (parent?.isCancelled ?? false)
  }
  public func cancel() {
    cancel(reason: nil)
  }
  public func cancel(reason: String?) {
    lock.lock()
    if !cancelled { cancellationReason = reason }
    cancelled = true
    let active = Array(progresses.values)
    lock.unlock()
    for progress in active { progress.cancel() }
  }
  public func track(_ progress: Progress) {
    lock.lock()
    progresses[ObjectIdentifier(progress)] = progress
    let stopped = cancelled
    lock.unlock()
    if stopped { progress.cancel() }
  }
  public func untrack(_ progress: Progress) {
    lock.lock()
    progresses.removeValue(forKey: ObjectIdentifier(progress))
    lock.unlock()
  }
  public func check() throws {
    try parent?.check()
    if isExpired {
      throw SevraError(
        "deadline",
        "The operation reached its processing deadline. Retained content remains available.")
    }
    lock.lock()
    let stopped = cancelled
    let reason = cancellationReason
    lock.unlock()
    if stopped { throw SevraError("cancelled", reason ?? "The operation was cancelled.") }
  }
}
/// A catalog entry identifies an exact version without loading its body or data.
/// Open that version explicitly when its evidence is needed.
public struct ItemSummary: Codable, Identifiable, Equatable, Sendable {
  public let id: String
  public let category: String
  public let kind: String
  public let title: String
  public let meaning: String
  public let status: String
  public let assetID: String?
}

public struct Item: Codable, Identifiable, Equatable, Sendable {
  public static let technicalKinds: Set<String> = [
    "request", "annotation", "application_definition", "application_invocation",
    "automation_authorization", "automation_planning", "automation_dispatch",
    "workflow_authorization", "condition_intent", "condition_dismissal", "excel-formulas",
  ]
  static let technicalKindSQL = technicalKinds.sorted().map { "'" + $0 + "'" }.joined(
    separator: ",")
  public var isBusinessEvidence: Bool { !Self.technicalKinds.contains(kind) }

  public let id: String
  public let logicalID: String
  public let version: Int
  public let category: String
  public let kind: String
  public let title: String
  public let meaning: String
  public let status: String
  public let scenario: String
  public let text: String
  public let data: Value
  public let assetID: String?
  public let supersedes: String?
  public let created: String
}
public struct SearchHit: Codable, Identifiable, Equatable, Sendable {
  public let id: Int
  public let itemID: String
  public let title: String
  public let snippet: String
  public let locator: String
  public let rank: Double
}
public struct SearchPage: Codable, Sendable {
  public let hits: [SearchHit]
  public let incomplete: Int
  public let nextOffset: Int?
  public let nextCursor: String?
}
public struct Asset: Codable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let path: String
  public let hash: String
  public let bytes: Int64
  public let mediaType: String
  public let mode: String
  public let origin: String?
}
public struct Chunk: Codable, Sendable {
  public let text: String
  public let locator: String
  public init(_ text: String, locator: String = "text") {
    self.text = text
    self.locator = locator
  }
}

extension Item {
  public var referenceMarkdown: String {
    let label = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
      of: "[", with: "\\["
    ).replacingOccurrences(of: "]", with: "\\]")
    return "[" + label + "](sevra://item/" + id + ")"
  }
}
