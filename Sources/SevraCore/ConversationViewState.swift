import Foundation

/// Presentation state only. Unsent text is neither evidence nor model history.
public struct ConversationReadingPosition: Codable, Equatable, Sendable {
  public var message: String?
  public var fraction: Double
  public init(message: String? = nil, fraction: Double = 0) {
    self.message = message
    self.fraction = fraction
  }
}

public struct SavedConversationDraft: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let text: String
  public let saved: String
}

public struct ConversationViewState: Codable, Equatable, Sendable {
  public var version = 1
  public var draft = ""
  public var reading = ConversationReadingPosition()
  public var savedDrafts: [SavedConversationDraft] = []
  public init() {}
}

extension Workbook {
  public func conversationViewState(_ conversation: String) throws -> ConversationViewState {
    let control = Cancellation(deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.shortWait {
        try db.budget(cancellation: control, seconds: 3) {
          try db.readTransaction {
            try readConversationViewState(conversation)
          }
        }
      }
    }
  }

  private func readConversationViewState(_ conversation: String) throws -> ConversationViewState {
    try requireConversation(conversation)
    let size =
      try db.scalar(
        "SELECT length(CAST(value AS BLOB)) FROM meta WHERE key=?",
        [.string("conversation-view:" + conversation)]
      ).int ?? 0
    try require(
      size <= 1_200_000, "draft_limit", "The saved conversation state is too large.")
    let raw = try db.scalar(
      "SELECT value FROM meta WHERE key=?", [.string("conversation-view:" + conversation)])
    guard let text = raw.string else { return ConversationViewState() }
    try require(
      text.utf8.count <= 1_200_000, "draft_limit",
      "The saved conversation state is too large.")
    let state = try JSONDecoder().decode(ConversationViewState.self, from: Data(text.utf8))
    try validateConversationView(state, conversation: conversation)
    return state
  }

  /// Compare the draft, not the business revision: scrolling must not invalidate
  /// proposals or force a transcript rebuild. Competing text requires an explicit
  /// keep-both action. Every retained alternative stays outside search/history.
  @discardableResult public func saveConversationViewState(
    _ conversation: String, draft: String, reading: ConversationReadingPosition,
    expectedDraft: String, preserveOtherDraft: Bool = false, removeSavedDraft: String? = nil
  ) throws -> ConversationViewState {
    try presentationMutation {
      var state = try readConversationViewState(conversation)
      let readingOnly = draft == expectedDraft && !preserveOtherDraft
      let conflict = !readingOnly && state.draft != expectedDraft && state.draft != draft
      try require(
        !conflict || preserveOtherDraft, "draft_conflict",
        "Another window saved a different draft. Your text is still here. Keep both drafts before continuing."
      )
      if let removeSavedDraft { state.savedDrafts.removeAll { $0.id == removeSavedDraft } }
      if preserveOtherDraft && !state.draft.isEmpty && state.draft != draft
        && !state.savedDrafts.contains(where: { $0.text == state.draft })
      {
        try require(
          state.savedDrafts.count < 8, "draft_limit",
          "Eight other drafts are already saved. Remove an unneeded saved draft before keeping another."
        )
        state.savedDrafts.append(.init(id: identifier(), text: state.draft, saved: timestamp()))
      }
      if !readingOnly { state.draft = draft }
      state.reading = reading
      try validateConversationView(state, conversation: conversation)
      let text = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
      try require(
        text.utf8.count <= 1_200_000, "draft_limit",
        "The saved conversation drafts exceed the 1.2 MB storage limit. Shorten the draft or remove an unneeded saved alternative."
      )
      try db.execute(
        "INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        [.string("conversation-view:" + conversation), .string(text)])
      return state
    }
  }

  private func requireConversation(_ id: String) throws {
    try require(
      try db.scalar("SELECT count(*) FROM conversations WHERE id=?", [.string(id)]).int == 1,
      "conversation", "Conversation not found.")
  }
  private func validateConversationView(_ state: ConversationViewState, conversation: String) throws
  {
    try require(
      state.version == 1 && state.draft.utf8.count <= 128_000
        && state.savedDrafts.count <= 8
        && state.savedDrafts.allSatisfy { $0.text.utf8.count <= 128_000 },
      "draft_limit",
      "Conversation drafts support up to 128 KB of text and eight saved alternatives.")
    try require(
      state.reading.fraction.isFinite && (0...1).contains(state.reading.fraction),
      "reading_position", "Invalid conversation reading position.")
    if let message = state.reading.message {
      try require(
        try messageLocation(message)["conversation_id"].text == conversation,
        "history_scope", "The reading position belongs to another conversation.")
    }
  }
}
