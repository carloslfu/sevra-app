import Foundation

/// One chat in a workbook's list. Chats are independent: each holds only its own messages,
/// and nothing is carried between them.
public struct Chat: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let title: String
  public let created: String
  /// The latest message's time, or the chat's own when it has none. The list sorts by it.
  public let updated: String
  public let messageCount: Int
}

extension Workbook {
  /// The title a chat has until its first message names it.
  public static let newChatTitle = "New chat"

  /// A one-line title from the start of a message: plain text, at most 64 words, without the
  /// period that ends a sentence.
  public static func chatTitle(from text: String) -> String {
    let plain =
      (try? AttributedString(
        markdown: String(text.prefix(4096)),
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      .map { String($0.characters) } ?? String(text.prefix(4096))
    let words = plain.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
    var title = String(
      words.prefix(64).joined(separator: " ").precomposedStringWithCanonicalMapping
        .unicodeScalars.filter { !breaksTitle($0) }.map(Character.init))
    var shortened = words.count > 64
    // A shortened title keeps room for its "…" within the limits a rename checks.
    while title.count > (shortened ? 119 : 120) || title.utf8.count > (shortened ? 477 : 480) {
      title.removeLast()
      shortened = true
    }
    title = title.trimmingCharacters(in: .whitespaces)
    while let last = title.last, ".,;:".contains(last) {
      title.removeLast()
      title = title.trimmingCharacters(in: .whitespaces)
    }
    return title.isEmpty ? newChatTitle : title + (shortened ? "…" : "")
  }

  /// Starts an empty chat. A new workbook has one, and deleting the last one makes another.
  @discardableResult public func createChat(
    token: String = identifier(), cancellation: Cancellation = .init()
  ) throws -> String {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try mutation("create_chat", token: token, cancellation: control) {
      .string(try insertChat())
    }.text
  }

  /// The chats a person can open, most recently active first.
  public func chats(cancellation: Cancellation = .init()) throws -> [Chat] {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) { try readChats() }
    }
  }

  /// One open chat. A deleted or unknown chat is refused.
  public func chat(_ id: String, cancellation: Cancellation = .init()) throws -> Chat {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try requireLiveChat(id)
        guard let chat = try readChats(id: id).first else {
          throw SevraError("chat", "This chat does not exist.")
        }
        return chat
      }
    }
  }

  public func renameChat(
    _ id: String, title: String, token: String = identifier(),
    cancellation: Cancellation = .init()
  ) throws {
    let name = try Self.validChatTitle(title)
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    _ = try mutation(
      "rename_chat", token: token,
      request: .object(["id": .string(id), "title": .string(name)]), cancellation: control
    ) {
      try requireLiveChat(id)
      try db.execute("UPDATE conversations SET title=? WHERE id=?", [.string(name), .string(id)])
      return .string(name)
    }
  }

  /// Removes a chat from the list, with its unsent draft. Its messages stay in the workbook,
  /// because the Sources and receipts its requests created point at them, but it cannot be
  /// opened or written to again.
  /// Returns the chat to show next: the most recent one left, or a new one when none is left.
  /// `closingUnfinishedRuns` is for a caller that knows no answer of its own is running in the
  /// chat, such as the window showing it: a run a crash left marked as running is then closed as
  /// interrupted instead of keeping the chat from being deleted.
  @discardableResult public func deleteChat(
    _ id: String, closingUnfinishedRuns: Bool = false, token: String = identifier(),
    cancellation: Cancellation = .init()
  ) throws -> String {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try mutation(
      "delete_chat", token: token, request: .object(["id": .string(id)]), cancellation: control
    ) {
      try requireLiveChat(id)
      if closingUnfinishedRuns {
        try db.execute(
          "UPDATE agent_runs SET status='interrupted',updated=? WHERE conversation_id=? AND status='running'",
          [.string(timestamp()), .string(id)])
      }
      try require(
        try db.scalar(
          "SELECT count(*) FROM agent_runs WHERE conversation_id=? AND status='running'",
          [.string(id)]
        ).int == 0, "chat_busy", "Stop the answer in this chat before deleting it.")
      try db.execute("UPDATE conversations SET deleted=1 WHERE id=?", [.string(id)])
      try db.execute("DELETE FROM meta WHERE key=?", [.string("conversation-view:" + id)])
      return .string(try readChats().first?.id ?? insertChat())
    }.text
  }

  /// Inside a write: refuses a chat that does not exist or was deleted.
  func requireLiveChat(_ id: String) throws {
    let deleted = try db.scalar("SELECT deleted FROM conversations WHERE id=?", [.string(id)])
    try require(deleted != .null, "chat", "This chat does not exist.")
    try require(deleted.int == 0, "chat_deleted", "This chat was deleted.")
  }

  /// Inside a write that adds a person's message: the first one names a chat still called
  /// "New chat". A chat the person renamed keeps its title.
  func nameNewChat(_ id: String, from text: String) throws {
    try db.execute(
      "UPDATE conversations SET title=? WHERE id=? AND title=? AND NOT EXISTS (SELECT 1 FROM messages WHERE conversation_id=? AND role='user')",
      [.string(Self.chatTitle(from: text)), .string(id), .string(Self.newChatTitle), .string(id)])
  }

  private func insertChat() throws -> String {
    let id = identifier()
    try db.execute(
      "INSERT INTO conversations VALUES(?,?,?,0)",
      [.string(id), .string(Self.newChatTitle), .string(timestamp())])
    return id
  }

  /// Inside a read the caller holds. Times are to the second, so within one second a chat with
  /// no messages yet (just made) comes first, then the chat whose message came last.
  func readChats(id: String? = nil) throws -> [Chat] {
    try db.execute(
      """
      SELECT c.id,c.title,c.created,coalesce(max(m.created),c.created) AS updated,
        count(m.id) AS messages
      FROM conversations c LEFT JOIN messages m ON m.conversation_id=c.id AND m.role!='tool'
      WHERE c.deleted=0 AND (? IS NULL OR c.id=?)
      GROUP BY c.id
      ORDER BY updated DESC,max(m.rowid) IS NOT NULL,max(m.rowid) DESC,c.rowid DESC
      """, [id.map(Value.string) ?? .null, id.map(Value.string) ?? .null]
    ).map {
      Chat(
        id: $0["id"]!.text, title: $0["title"]!.text, created: $0["created"]!.text,
        updated: $0["updated"]!.text, messageCount: $0["messages"]!.int ?? 0)
    }
  }

  private static func validChatTitle(_ title: String) throws -> String {
    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCanonicalMapping
    try require(
      !name.isEmpty && name.utf8.count <= 480 && name.count <= 120
        && !name.unicodeScalars.contains(where: breaksTitle),
      "chat_title", "Use a chat title of 1 to 120 characters on one line.")
    return name
  }

  /// A title stays on one visible line in reading order: no line breaks, controls, direction
  /// overrides or invisible characters. The two joiners stay, because emoji sequences and
  /// Persian words are spelled with them.
  private static func breaksTitle(_ scalar: Unicode.Scalar) -> Bool {
    if scalar.value == 0x200C || scalar.value == 0x200D { return false }
    return [.control, .format, .lineSeparator, .paragraphSeparator].contains(
      scalar.properties.generalCategory)
  }
}
