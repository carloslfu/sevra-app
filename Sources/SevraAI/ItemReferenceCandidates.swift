import Foundation
import SevraCore

/// A bounded vocabulary for exact item lookup, separate from inspected evidence.
/// Discovery may mention an item without establishing any claim about it.
package enum ItemReferenceCandidates {
  package static let maximum = 256

  package static func normalized(_ values: [String]) throws -> [String] {
    let ids = Array(Set(values)).sorted()
    try require(
      ids.count <= maximum && ids.allSatisfy { UUID(uuidString: $0) != nil },
      "context_limit",
      "This exploration has too many or invalid item references. Narrow the question.")
    return ids
  }

  package static func ids(in messages: [InferenceMessage]) throws -> [String] {
    try normalized(messages.flatMap(\.itemReferences))
  }

  /// A record's ID looks just like a message's, so history_read offers only messages.
  package static func historyIDs(in messages: [InferenceMessage]) -> [String]? {
    messages.first?.historyReferences
  }

  package static func annotate(
    _ messages: [InferenceMessage], workbook: Workbook,
    history: (conversation: String, before: String?)? = nil
  ) throws -> [InferenceMessage] {
    guard !messages.isEmpty else { return [] }
    let regex = try NSRegularExpression(
      pattern:
        "(?i)(?<![0-9a-z])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-z])")
    var mentioned: [String] = []
    var seen = Set<String>()
    var navigation: [String] = []
    let citation = try NSRegularExpression(
      pattern: "(?i)(?:message:|[?&]message=)"
        + "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})")
    for message in messages.reversed() {
      // Reading preserves original bytes, including URLs superseded by saved
      // bindings. Those raw routes are not canonical lookup authority. The
      // read's structural references (or an explicit discovery result) supply
      // exact destinations independently. Do not rewrite the model's evidence.
      let lookupText: String
      if message.role == "tool", ["read", "tool_result"].contains(message.toolName ?? "") {
        lookupText = message.content
          .replacingOccurrences(of: #"\\+/"#, with: "/", options: .regularExpression)
          .replacingOccurrences(
            of: #"(?i)sevra://(?:workbook/[0-9a-f-]{36}/item|item)/[0-9a-f-]{36}"#,
            with: "saved-reference-route", options: .regularExpression)
      } else {
        lookupText = message.content
      }
      let matches = regex.matches(
        in: lookupText, range: NSRange(lookupText.startIndex..., in: lookupText))
      if message.role == "assistant" {
        // A compacted original may be older than every visible history row.
        // Preserve explicit navigation pointers ahead of incidental row IDs.
        // These are lookup candidates only; normal scope and read checks below
        // still apply, and no summary becomes inspected evidence.
        navigation += citation.matches(
          in: lookupText, range: NSRange(lookupText.startIndex..., in: lookupText)
        ).compactMap { Range($0.range(at: 1), in: lookupText).map { String(lookupText[$0]) } }
        if let digest = try? Value.parse(lookupText), digest["derivedNotes"] != .null {
          navigation += ContextDigest.references(digest["derivedNotes"]).sorted()
        }
      } else if ["user", "tool"].contains(message.role) {
        // Current requests and ranked discovery/results take precedence over
        // IDs merely visible in a historical envelope.
        navigation += matches.compactMap {
          Range($0.range, in: lookupText).map { String(lookupText[$0]) }
        }
      }
      // Saved history packs chronological messages into one assistant envelope.
      // Apply the same newest-first selection inside that envelope: otherwise
      // older unrelated IDs can fill all 32 history choices and make a visible
      // recent answer's original citation impossible to read. Discovery tool
      // results retain their ranked order.
      let ordered = message.role == "assistant" ? Array(matches.reversed()) : matches
      for match in ordered {
        guard let range = Range(match.range, in: lookupText) else { continue }
        let id = String(lookupText[range])
        if seen.insert(id).inserted { mentioned.append(id) }
      }
    }
    try require(
      mentioned.count <= 2048, "context_limit",
      "Too many lookup values in this context. Narrow the question.")
    // A table read page by page can outrun the limit. Its rows give way first, oldest first:
    // their values are already in view, and anything else may be the only way to reach it.
    var verified: [String] = []
    var rows: [String] = []
    var earlier: [String] = []
    var visited = Set<String>()
    // Prioritization cannot add values outside the bounded visible UUID set.
    for id in navigation.filter({ seen.contains($0) }) + mentioned
    where visited.insert(id).inserted {
      do {
        if try workbook.item(id).kind == "row" { rows.append(id) } else { verified.append(id) }
      } catch let error as SevraError where error.code == "not_found" {
        guard let history, earlier.count < 32,
          (try? workbook.readHistoryEvidence(
            id, conversation: history.conversation, beforeMessage: history.before)) != nil
        else { continue }
        earlier.append(id)
      }
    }
    let choices = try normalized(verified + rows.prefix(max(0, maximum - verified.count)))
    // Replace any previous annotation, including one dropped/rebuilt by context
    // maintenance. No hidden candidate catalog survives a visible-context change.
    return messages.enumerated().map { index, message in
      var annotated = message
      annotated.itemReferences = index == 0 ? choices : []
      annotated.historyReferences = index == 0 && history != nil ? earlier.sorted() : nil
      return annotated
    }
  }

  package static func validate(tool: String, arguments: Value, choices: [String]) throws {
    guard ["read", "lineage", "references"].contains(tool), !choices.isEmpty else { return }
    try require(
      arguments["id"].string.map(choices.contains) == true, "item_reference",
      "Choose the exact item ID from the read/lineage/references tool choices. This value is not one of them. Use search to discover another item; do not guess an ID or use conversation history for a workbook item."
    )
  }
}
