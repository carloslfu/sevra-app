import Foundation

/// A bounded view of the existing request and tool journal. This is execution
/// history, never a second ledger or a source of business authority.
public struct RequestActivity: Identifiable, Sendable {
  public let id: String
  public let requestID: String
  public let conversation: String
  public let state: String
  public let model: String
  public let started: Date
  public let updated: Date
  public let steps: [ToolActivity]
  public let hasMoreSteps: Bool
}

public struct ToolActivity: Identifiable, Sendable {
  public let id: String
  /// The model's ID for the call, which ties the step to the thought that led to it.
  public let callID: String
  public let tool: String
  public let state: String
  /// Bounded label fields only. Inspect toolCall(id) for the exact inputs.
  public let arguments: Value
  /// A complete small result only. Large results remain in the receipt browser.
  public let result: Value?

  public init(
    id: String, callID: String, tool: String, state: String, arguments: Value, result: Value?
  ) {
    self.id = id
    self.callID = callID
    self.tool = tool
    self.state = state
    self.arguments = arguments
    self.result = result
  }

  public var originalID: String? { tool == "read" ? result?["item"]["id"].string : nil }

  public var title: String {
    switch tool {
    case "search", "history_search": return "Search for “\(arguments["query"].text.prefix(160))”"
    case "read":
      return result?["item"]["title"].string.map { "Read " + String($0.prefix(200)) }
        ?? "Read original"
    case "history_read": return "Read earlier conversation"
    case "datasets": return "Inspect tables"
    case "rows": return "Read table rows"
    case "sql": return "Query tables"
    case "run": return "Run a script"
    case "calculate": return "Calculate"
    case "save_space": return "Save space"
    case "edit_space": return "Update space"
    case "spaces": return "Inspect spaces"
    case "references": return "Follow references"
    case "tool_result": return "Read saved result"
    default: return tool.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }

  public var detail: String {
    if state == "prepared" { return "No final receipt yet. Changes may be incomplete." }
    if state == "failed" {
      return String((result?["error"].string ?? "The tool reported a failure.").prefix(400))
    }
    if tool == "search", let result, case .array(let hits) = result["hits"] {
      let more = result["nextCursor"] != .null
      return "\(hits.count) document or record matches on this page"
        + (more ? "; more pages available." : ".")
        + " Matching does not establish complete coverage."
    }
    if tool == "rows", let result, case .array(let rows) = result["rows"] {
      return "\(rows.count) rows inspected on this page."
    }
    if tool == "read", let result {
      let count = result["chunks"].array.count
      return "\(count) text \(count == 1 ? "chunk" : "chunks") inspected"
        + (result["chunkPage"]["hasMore"] == .bool(true) ? "; more available." : ".")
    }
    if let title = result?["title"].string { return String(title.prefix(200)) }
    return "Result saved"
  }
}

extension Workbook {
  /// Exact visible request IDs, scoped to their conversation. Never scans old
  /// history to decorate a new request; never reads unbounded asset/result bytes.
  public func requestActivities(messageIDs: [String], conversation: String) throws
    -> [RequestActivity]
  {
    try require(messageIDs.count <= 200, "activity_limit", "Too many activity requests.")
    guard !messageIDs.isEmpty else { return [] }
    return try synchronized {
      let placeholders = messageIDs.map { _ in "?" }.joined(separator: ",")
      let runs = try db.execute(
        "SELECT a.*,r.message_id FROM run_requests r JOIN agent_runs a ON a.id=r.run_id WHERE a.conversation_id=? AND r.message_id IN (\(placeholders)) ORDER BY a.rowid",
        [.string(conversation)] + messageIDs.map(Value.string))
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      var remainingResultBytes = 512 * 1024
      func date(_ text: String) -> Date {
        if let value = formatter.date(from: text) { return value }
        return ISO8601DateFormatter().date(from: text) ?? .distantPast
      }
      return try runs.map { run in
        let calls = try db.execute(
          "SELECT id,call_id,tool,state,substr(json_extract(arguments,'$.query'),1,160) AS query,CASE WHEN length(CAST(result AS BLOB))<=16384 THEN result ELSE NULL END AS small_result FROM tool_calls WHERE run_id=? ORDER BY rowid LIMIT 65",
          [run["id"]!])
        let steps = try calls.prefix(64).map { call in
          let text = call["small_result"]?.string
          let result: Value?
          if let text, text.utf8.count <= remainingResultBytes {
            remainingResultBytes -= text.utf8.count
            result = try Value.parse(text)
          } else {
            result = nil
          }
          return ToolActivity(
            id: call["id"]!.text, callID: call["call_id"]!.text, tool: call["tool"]!.text,
            state: call["state"]!.text,
            arguments: .object(call["query"]?.string.map { ["query": .string($0)] } ?? [:]),
            result: result)
        }
        return RequestActivity(
          id: run["id"]!.text, requestID: run["message_id"]!.text,
          conversation: conversation, state: run["status"]!.text, model: run["model"]!.text,
          started: date(run["created"]!.text), updated: date(run["updated"]!.text),
          steps: steps, hasMoreSteps: calls.count > 64)
      }
    }
  }
}

/// What the model thought on one call, saved with its run so the person can read it.
/// Working notes, never evidence: the model never reads them again and nothing checks them.
public struct ActivityThought: Identifiable, Sendable, Equatable {
  /// The run's step, one per model call.
  public let step: Int
  /// The call it made, when it made exactly one.
  public let callID: String?
  public let tool: String?
  public let text: String
  /// Set when the call did not become a step: "answer", "answer_refused", "unusable" or "too_long".
  public var outcome: String?
  /// Why Sevra did not accept the call, in the words it sent back to the model.
  public var note: String?
  /// The answer Sevra sent back, as the model wrote it.
  public var draft: String?
  public var id: String { String(step) }
  public static let limit = 16_000
  /// The live status while the model reasons, as the engine reports it.
  public static let reasoningPhase = "Working through the request"
  /// A call with no reasoning and nothing sent back is kept only to place its step in order.
  public var isVisible: Bool { !text.isEmpty || outcome != nil }

  public init(
    step: Int, callID: String? = nil, tool: String? = nil, text: String,
    outcome: String? = nil, note: String? = nil, draft: String? = nil
  ) {
    self.step = step
    self.callID = callID
    self.tool = tool
    self.text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.limit))
    self.outcome = outcome
    self.note = note.map { String($0.prefix(4_000)) }
    self.draft = draft.map { String($0.prefix(4_000)) }
  }
  /// The entry saved in the run's metrics.
  public var value: Value {
    .object([
      "kind": .string("reasoning"), "step": .number(Double(step)),
      "callID": callID.map(Value.string) ?? .null, "tool": tool.map(Value.string) ?? .null,
      "text": .string(text), "outcome": outcome.map(Value.string) ?? .null,
      "note": note.map(Value.string) ?? .null, "draft": draft.map(Value.string) ?? .null,
    ])
  }
  public init?(_ value: Value) {
    guard value["kind"] == .string("reasoning"), let step = value["step"].int,
      let text = value["text"].string
    else { return nil }
    self.init(
      step: step, callID: value["callID"].string, tool: value["tool"].string, text: text,
      outcome: value["outcome"].string, note: value["note"].string, draft: value["draft"].string)
  }
}

/// One row of the activity: a thought, or a step the run took.
public enum ActivityEntry: Identifiable, Sendable {
  case thought(ActivityThought)
  case step(ToolActivity)
  public var id: String {
    switch self {
    case .thought(let thought): return "thought-" + thought.id
    case .step(let step): return "step-" + step.id
    }
  }
}

extension RequestActivity {
  /// Each thought, then the step it led to, in the order they ran. A step no call names, as
  /// the host takes on its own, stays after the step before it. A thought whose step is not
  /// shown keeps its place.
  public static func timeline(steps: [ToolActivity], thoughts: [ActivityThought])
    -> [ActivityEntry]
  {
    let named = Set(thoughts.compactMap(\.callID))
    var entries: [ActivityEntry] = []
    var remaining = steps[...]
    for thought in thoughts.sorted(by: { $0.step < $1.step }) {
      if let callID = thought.callID,
        let index = remaining.firstIndex(where: { $0.callID == callID })
      {
        entries += remaining[..<index].map(ActivityEntry.step)
        if thought.isVisible { entries.append(.thought(thought)) }
        entries.append(.step(remaining[index]))
        remaining = remaining[(index + 1)...]
        while let next = remaining.first, !named.contains(next.callID) {
          entries.append(.step(next))
          remaining = remaining.dropFirst()
        }
      } else if thought.isVisible {
        entries.append(.thought(thought))
      }
    }
    return entries + remaining.map(ActivityEntry.step)
  }
}

extension Workbook {
  /// The saved thoughts of one run in this conversation, in step order.
  public func runThoughts(_ runID: String, conversation: String) throws -> [ActivityThought] {
    try synchronized {
      let rows = try db.execute(
        "SELECT j.value FROM agent_runs a, json_each(a.metrics) j WHERE a.id=? AND a.conversation_id=? AND json_valid(a.metrics) AND json_type(a.metrics)='array' AND json_extract(j.value,'$.kind')='reasoning' ORDER BY j.key LIMIT 100",
        [.string(runID), .string(conversation)])
      var bytes = 0
      var thoughts: [ActivityThought] = []
      for row in rows {
        guard let text = row["value"]?.string else { continue }
        bytes += text.utf8.count
        guard bytes <= 2 * 1024 * 1024 else { break }
        if let thought = ActivityThought(try Value.parse(text)) { thoughts.append(thought) }
      }
      return thoughts
    }
  }
}
