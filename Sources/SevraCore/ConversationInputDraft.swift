import Foundation

public struct ConversationInputDraft: Codable, Equatable, Sendable {
  public let revision: Int
  public let values: [String: Value]
}

extension Workbook {
  public func conversationInputDraft(_ surface: ConversationSurface) throws
    -> ConversationInputDraft?
  {
    try synchronized { try readConversationInputDraft(surface) }
  }

  private func inputDraftKey(_ surface: ConversationSurface) -> String {
    "conversation-input-draft:" + surface.id + ":" + String(surface.revision)
  }

  func readConversationInputDraft(_ surface: ConversationSurface) throws -> ConversationInputDraft?
  {
    guard
      let raw = try db.scalar(
        "SELECT value FROM meta WHERE key=? AND length(CAST(value AS BLOB))<=8192",
        [.string(inputDraftKey(surface))]
      ).string
    else { return nil }
    return try JSONDecoder().decode(ConversationInputDraft.self, from: Data(raw.utf8))
  }

  @discardableResult public func saveConversationInputDraft(
    _ surface: ConversationSurface, values: [String: Value], expectedRevision: Int
  ) throws -> ConversationInputDraft {
    try presentationMutation {
      guard try isPendingConversationInput(surface),
        let input = surface.input
      else { throw SevraError("conversation_input", "This question has closed.") }
      let current = try readConversationInputDraft(surface)
      try require(
        current?.values == values || (current?.revision ?? 0) == expectedRevision,
        "conversation_input_conflict",
        "Another window saved different answers. Your entries are still in this window.")
      try require(
        Set(values.keys).isSubset(of: Set(input.fields.map(\.id)))
          && values.values.allSatisfy {
            switch $0 {
            case .string(let text): return text.utf8.count <= 1024
            case .bool: return true
            default: return false
            }
          }, "conversation_input", "Use only the question’s bounded fields.")
      if let current, current.values == values { return current }
      try require(
        expectedRevision >= 0 && expectedRevision < 1_000_000_000,
        "conversation_input", "Invalid draft revision.")
      let next = ConversationInputDraft(revision: expectedRevision + 1, values: values)
      let encodedDraft = try encoded(next).json()
      try require(encodedDraft.utf8.count <= 8192, "conversation_input", "The answer is too long.")
      try db.execute(
        "INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        [.string(inputDraftKey(surface)), .string(encodedDraft)])
      return next
    }
  }

  func discardConversationInputDraft(_ surface: ConversationSurface) throws {
    try db.execute("DELETE FROM meta WHERE key=?", [.string(inputDraftKey(surface))])
  }
}
