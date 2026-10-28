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

  package static func annotate(
    _ messages: [InferenceMessage], workbook: Workbook
  ) throws -> [InferenceMessage] {
    guard !messages.isEmpty else { return [] }
    let regex = try NSRegularExpression(
      pattern:
        "(?i)(?<![0-9a-z])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-z])")
    var mentioned = Set<String>()
    for message in messages {
      for match in regex.matches(
        in: message.content, range: NSRange(message.content.startIndex..., in: message.content))
      {
        guard let range = Range(match.range, in: message.content) else { continue }
        mentioned.insert(String(message.content[range]))
      }
    }
    try require(
      mentioned.count <= 2048, "context_limit",
      "Too many lookup values in this context. Narrow the question.")
    var verified: [String] = []
    for id in mentioned.sorted() {
      do {
        _ = try workbook.item(id)
        verified.append(id)
      } catch let error as SevraError where error.code == "not_found" {
        continue
      }
    }
    let choices = try normalized(verified)
    // Replace any previous annotation, including one dropped/rebuilt by context
    // maintenance. No hidden candidate catalog survives a visible-context change.
    return messages.enumerated().map { index, message in
      InferenceMessage(
        role: message.role, content: message.content, toolCalls: message.toolCalls,
        toolCallId: message.toolCallId, toolName: message.toolName, reasoning: message.reasoning,
        itemReferences: index == 0 ? choices : [], conversationActions: message.conversationActions,
        documentCopyIDs: message.documentCopyIDs)
    }
  }

  package static func validate(tool: String, arguments: Value, choices: [String]) throws {
    guard ["read", "lineage"].contains(tool), !choices.isEmpty else { return }
    try require(
      arguments["id"].string.map(choices.contains) == true, "item_reference",
      "Choose the exact item ID from the read/lineage tool choices. This value is not one of them. Use search to discover another item; do not guess an ID or use conversation history for a workbook item."
    )
  }
}
