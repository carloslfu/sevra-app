import Foundation

public struct ConversationWindow: Sendable {
  public let messages: [Message]
  public let hasEarlier: Bool
  public let hasLater: Bool
}

extension Workbook {
  public static func threadTitle(from text: String) -> String {
    let plain =
      (try? AttributedString(
        markdown: String(text.prefix(4096)),
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      .map { String($0.characters) } ?? String(text.prefix(4096))
    let words = plain.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(
      separator: " ")
    var title = String(words.prefix(64)).unicodeScalars.filter {
      !CharacterSet.controlCharacters.contains($0)
    }.map(String.init).joined()
    while title.utf8.count > 480 { title.removeLast() }
    return title.isEmpty ? "New thread" : title + (words.count > 64 ? "…" : "")
  }

  @discardableResult public func startThread(
    parentMessage: String, title: String? = nil,
    token: String = identifier()
  ) throws -> String {
    let request: Value = .object([
      "parent": .string(parentMessage), "title": title.map(Value.string) ?? .null,
    ])
    return try mutation("start_thread", token: token, request: request) {
      let location = try messageLocation(parentMessage)
      let parent = try historyMessage(parentMessage, conversation: location["conversation_id"].text)
      try require(
        parent.role != "tool", "conversation",
        "Start a thread from a conversation message, not a tool receipt.")
      var name = try Self.validThreadTitle(title ?? Self.threadTitle(from: parent.body))
      if title == nil {
        let base = name
        var suffix = 2
        while try db.scalar("SELECT count(*) FROM conversations WHERE title=?", [.string(name)]).int
          != 0
        {
          name = base + " (\(suffix))"
          suffix += 1
          if suffix > 100 {
            name = base + " " + String(identifier().prefix(8))
            break
          }
        }
      }
      let id = identifier()
      try db.execute(
        "INSERT INTO conversations VALUES(?,?,?)",
        [.string(id), .string(name), .string(parentMessage)])
      return .string(id)
    }.text
  }

  public func renameThread(
    _ id: String, title: String, expectedTitle: String? = nil,
    token: String = identifier()
  ) throws {
    let name = try Self.validThreadTitle(title)
    _ = try mutation(
      "rename_thread", token: token,
      request: .object([
        "id": .string(id), "title": .string(name),
        "expected": expectedTitle.map(Value.string) ?? .null,
      ])
    ) {
      let current = try db.scalar("SELECT title FROM conversations WHERE id=?", [.string(id)])
      try require(
        id != "main" && current != .null, "conversation", "Choose an existing thread to rename.")
      try require(
        expectedTitle == nil || current.text == expectedTitle, "thread_changed",
        "This thread was renamed elsewhere. Reopen Rename thread to review its current title.")
      try db.execute("UPDATE conversations SET title=? WHERE id=?", [.string(name), .string(id)])
      return .string(name)
    }
  }

  private static func validThreadTitle(_ title: String) throws -> String {
    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
    try require(
      !name.isEmpty && name.utf8.count <= 512 && name.count <= 120
        && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
      "thread_title", "Use a thread title of 1 to 120 characters on one line.")
    return name
  }

  /// UI history is separate from agent retrieval. At most 100 visible messages
  /// and 2 MiB are loaded, using conversation-local keysets rather than global
  /// row-id arithmetic. The exact anchor survives interleaved sibling messages.
  public func conversationWindow(
    conversation: String, around anchor: String? = nil,
    cancellation: Cancellation = .init()
  ) throws -> ConversationWindow {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction {
          try readConversationWindow(
            conversation: conversation, around: anchor, cancellation: control)
        }
      }
    }
  }
  // Caller owns the workbook lock and a coherent, budgeted read transaction.
  func readConversationWindow(
    conversation: String, around anchor: String?, cancellation: Cancellation
  ) throws -> ConversationWindow {
    try require(
      try db.scalar("SELECT count(*) FROM conversations WHERE id=?", [.string(conversation)])
        .int == 1,
      "history_scope", "This conversation does not exist.")
    let position: Value
    if let anchor {
      let location = try messageLocation(anchor)
      try require(
        location["conversation_id"].text == conversation, "history_scope",
        "The message belongs to another conversation.")
      try require(
        try historyMessage(anchor, conversation: conversation).role != "tool",
        "history_scope",
        "Tool receipts are available through history tools rather than the message browser.")
      position = location["rowid"]
    } else {
      position = .null
    }
    func candidates(_ predicate: String, descending: Bool, limit: Int) throws -> [[String:
      Value]]
    {
      try db.execute(
        "SELECT rowid,id,length(CAST(body AS BLOB)) AS bytes FROM messages WHERE conversation_id=? AND role!='tool' "
          + predicate + " ORDER BY rowid " + (descending ? "DESC" : "ASC") + " LIMIT ?",
        [.string(conversation)] + (position == .null ? [] : [position]) + [
          .number(Double(limit))
        ])
    }
    let earlier = try candidates(
      position == .null ? "" : "AND rowid<?", descending: true,
      limit: position == .null ? 100 : 50)
    let later =
      position == .null ? [] : try candidates("AND rowid>=?", descending: false, limit: 50)
    var selected: [[String: Value]] = []
    var bytes = 0
    var full = [false, false]
    // Start with the anchor and alternate outward so the byte budget does
    // not silently exclude the very message the user chose to inspect.
    for index in 0..<max(earlier.count, later.count) {
      try cancellation.check()
      for (side, rows) in [later, earlier].enumerated()
      where !full[side] && index < rows.count {
        let row = rows[index]
        let size = row["bytes"]?.int ?? 0
        try require(size <= 128_000, "integrity", "Stored message exceeds the format limit.")
        if bytes + size > 2 * 1024 * 1024 {
          full[side] = true
          continue
        }
        bytes += size
        selected.append(row)
      }
    }
    selected.sort { ($0["rowid"]?.int ?? 0) < ($1["rowid"]?.int ?? 0) }
    let messages = try selected.map {
      try cancellation.check()
      return try historyMessage($0["id"]!.text, conversation: conversation)
    }
    let first = selected.first?["rowid"] ?? .null
    let last = selected.last?["rowid"] ?? .null
    let earlierExists =
      try db.scalar(
        "SELECT EXISTS(SELECT 1 FROM messages WHERE conversation_id=? AND role!='tool' AND rowid<?)",
        [.string(conversation), first]
      ).int == 1
    let laterExists =
      try db.scalar(
        "SELECT EXISTS(SELECT 1 FROM messages WHERE conversation_id=? AND role!='tool' AND rowid>?)",
        [.string(conversation), last]
      ).int == 1
    return ConversationWindow(
      messages: messages, hasEarlier: earlierExists, hasLater: laterExists)
  }

}
