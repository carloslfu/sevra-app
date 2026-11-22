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

/// A message written while a reply was running. It is sent later, as if typed then, with the
/// selection that was attached when it was written.
public struct QueuedConversationMessage: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public var text: String
  public let context: String
  public let queued: String
  public init(id: String, text: String, context: String, queued: String) {
    self.id = id
    self.text = text
    self.context = context
    self.queued = queued
  }
}

/// Messages waiting for the running reply to finish, in the order they will be sent. The person
/// owns the order and the text. A stopped or failed reply, or a question waiting for an answer,
/// pauses the queue; only the person resumes it. There is no count limit: the queue is bounded
/// only by its total size, so it always fits in the chat's saved state.
public struct ConversationQueue: Codable, Equatable, Sendable {
  public static let maximumContextBytes = 32_000
  /// Total text and selections of all waiting messages, well inside the saved state's limit.
  public static let maximumBytes = 2_000_000
  public private(set) var messages: [QueuedConversationMessage] = []
  public var paused = false
  public init() {}

  public var isEmpty: Bool { messages.isEmpty }
  /// Bytes the waiting messages hold: text, selections and a fixed allowance per message for
  /// its identifier, time and encoding, so many short messages are counted too.
  public var bytes: Int { messages.reduce(0) { $0 + Self.size(of: $1) } }
  static let perMessageBytes = 256
  static func size(of message: QueuedConversationMessage) -> Int {
    perMessageBytes + message.text.utf8.count + message.context.utf8.count
  }

  public mutating func add(_ text: String, context: String = "", id: String, queued: String)
    throws
  {
    let text = try Self.admitted(text)
    try require(
      context.utf8.count <= Self.maximumContextBytes, "queue_context",
      "The selection is too large to keep with a waiting message. Remove the selection or wait for the reply."
    )
    try require(
      bytes + Self.perMessageBytes + text.utf8.count + context.utf8.count <= Self.maximumBytes,
      "queue_full",
      "The waiting messages are too large to keep together. Send, shorten or remove some before adding another."
    )
    messages.append(.init(id: id, text: text, context: context, queued: queued))
  }
  public mutating func edit(_ id: String, text: String) throws {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    let text = try Self.admitted(text)
    try require(
      bytes - messages[index].text.utf8.count + text.utf8.count <= Self.maximumBytes, "queue_full",
      "The waiting messages are too large to keep together. Shorten this message or remove another.")
    messages[index].text = text
  }
  public mutating func remove(_ id: String) {
    messages.removeAll { $0.id == id }
    if messages.isEmpty { paused = false }
  }
  /// Moves one message up (negative) or down (positive), stopping at either end.
  public mutating func move(_ id: String, by offset: Int) {
    guard let from = messages.firstIndex(where: { $0.id == id }) else { return }
    let to = min(max(from + offset, 0), messages.count - 1)
    guard to != from else { return }
    messages.insert(messages.remove(at: from), at: to)
  }
  /// Places one message before the message at `destination` in the current order, or last.
  public mutating func move(_ id: String, before destination: String?) {
    guard let from = messages.firstIndex(where: { $0.id == id }), id != destination else { return }
    let message = messages.remove(at: from)
    let to = destination.flatMap { d in messages.firstIndex { $0.id == d } } ?? messages.count
    messages.insert(message, at: to)
  }
  /// The next message to send, removed from the queue. A paused queue gives nothing.
  public mutating func takeNext() -> QueuedConversationMessage? {
    guard !paused, !messages.isEmpty else { return nil }
    return messages.removeFirst()
  }
  /// A message that could not be sent returns to the top, and the queue pauses. Refused when
  /// the person filled the queue to its size limit meanwhile.
  public mutating func putBack(_ message: QueuedConversationMessage) -> Bool {
    guard bytes + Self.size(of: message) <= Self.maximumBytes,
      !messages.contains(where: { $0.id == message.id })
    else { return false }
    messages.insert(message, at: 0)
    paused = true
    return true
  }
  public mutating func clear() {
    messages = []
    paused = false
  }

  private static func admitted(_ text: String) throws -> String {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    try require(!text.isEmpty, "queue_empty", "A waiting message needs some text.")
    try require(
      text.utf8.count <= AgentRequest.maximumPromptBytes, "prompt_limit",
      "Please shorten this message to 16,000 bytes or less.")
    return text
  }
  func validated() throws {
    try require(
      bytes <= Self.maximumBytes
        && Set(messages.map(\.id)).count == messages.count
        && messages.allSatisfy {
          !$0.text.isEmpty && $0.text.utf8.count <= AgentRequest.maximumPromptBytes
            && $0.context.utf8.count <= Self.maximumContextBytes
        },
      "queue_invalid", "The saved waiting messages are not valid.")
  }
}

public struct ConversationViewState: Codable, Equatable, Sendable {
  public var version = 1
  public var draft = ""
  public var reading = ConversationReadingPosition()
  public var savedDrafts: [SavedConversationDraft] = []
  public var queue = ConversationQueue()
  public init() {}
  private enum CodingKeys: String, CodingKey { case version, draft, reading, savedDrafts, queue }
  /// Chats saved before the queue existed have no queue key.
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version)
    draft = try values.decode(String.self, forKey: .draft)
    reading = try values.decode(ConversationReadingPosition.self, forKey: .reading)
    savedDrafts = try values.decode([SavedConversationDraft].self, forKey: .savedDrafts)
    queue = try values.decodeIfPresent(ConversationQueue.self, forKey: .queue) ?? .init()
  }
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

  /// The largest saved state of one chat: its draft, kept alternatives and waiting messages,
  /// JSON-encoded. Text with many quotes or line breaks can encode at up to twice its size.
  static let maximumConversationStateBytes = 6_000_000

  private func readConversationViewState(_ conversation: String) throws -> ConversationViewState {
    try requireLiveChat(conversation)
    let size =
      try db.scalar(
        "SELECT length(CAST(value AS BLOB)) FROM meta WHERE key=?",
        [.string("conversation-view:" + conversation)]
      ).int ?? 0
    try require(
      size <= Self.maximumConversationStateBytes, "draft_limit", "The saved conversation state is too large.")
    let raw = try db.scalar(
      "SELECT value FROM meta WHERE key=?", [.string("conversation-view:" + conversation)])
    guard let text = raw.string else { return ConversationViewState() }
    try require(
      text.utf8.count <= Self.maximumConversationStateBytes, "draft_limit",
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
    expectedDraft: String, preserveOtherDraft: Bool = false, removeSavedDraft: String? = nil,
    queue: ConversationQueue? = nil
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
      if let queue { state.queue = queue }
      try validateConversationView(state, conversation: conversation)
      let text = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
      try require(
        text.utf8.count <= Self.maximumConversationStateBytes, "draft_limit",
        "The saved conversation drafts exceed the 6 MB storage limit. Shorten the draft or remove an unneeded saved alternative."
      )
      try db.execute(
        "INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        [.string("conversation-view:" + conversation), .string(text)])
      return state
    }
  }

  private func validateConversationView(_ state: ConversationViewState, conversation: String) throws
  {
    try require(
      state.version == 1 && state.draft.utf8.count <= 128_000
        && state.savedDrafts.count <= 8
        && state.savedDrafts.allSatisfy { $0.text.utf8.count <= 128_000 },
      "draft_limit",
      "Conversation drafts support up to 128 KB of text and eight saved alternatives.")
    try state.queue.validated()
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
