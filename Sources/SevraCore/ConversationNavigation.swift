import Foundation

public struct ConversationWindow: Sendable {
  public let messages: [Message]
  public let hasEarlier: Bool
  public let hasLater: Bool
}

extension Workbook {
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
    conversation: String, around anchor: String?, cancellation: Cancellation,
    reservedPresentationBytes: Int = 0
  ) throws -> ConversationWindow {
    try requireLiveChat(conversation)
    let position: Value
    if let anchor {
      let location = try messageLocation(anchor)
      try require(
        location["conversation_id"].text == conversation, "history_scope",
        "The message belongs to another chat.")
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
    var bytes = reservedPresentationBytes
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
