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
  public let tool: String
  public let state: String
  /// Bounded label fields only. Inspect toolCall(id) for the exact inputs.
  public let arguments: Value
  /// A complete small result only. Large results remain in the receipt browser.
  public let result: Value?

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
    case "calculate": return "Calculate"
    case "compare_rows": return "Compare table rows"
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
          "SELECT id,tool,state,substr(json_extract(arguments,'$.query'),1,160) AS query,CASE WHEN length(CAST(result AS BLOB))<=16384 THEN result ELSE NULL END AS small_result FROM tool_calls WHERE run_id=? ORDER BY rowid LIMIT 65",
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
            id: call["id"]!.text, tool: call["tool"]!.text, state: call["state"]!.text,
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
