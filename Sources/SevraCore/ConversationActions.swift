import Foundation

/// A host result, never a model-authored navigation destination. Creating and
/// renaming are committed; navigation is a request for the owning window, and
/// a summary remains an editable review until the user explicitly shares it.
public struct ConversationActionResult: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case created, renamed, returnToMain, reviewSummary
  }
  public let kind: Kind
  public let originConversation: String
  public let conversation: String
  public let message: String?
  public let summary: String?
  public var answer: String {
    switch kind {
    case .created: return "Created a thread."
    case .renamed: return "Renamed this thread."
    case .returnToMain: return "Return to the main conversation."
    case .reviewSummary:
      return
        "Review the selected findings before sharing them with the main conversation. Nothing has been shared yet."
    }
  }
}

extension Workbook {
  public func latestShareableAnswer(conversation: String, cancellation: Cancellation = .init())
    throws -> Message?
  {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        let id = try db.scalar(
          "SELECT id FROM messages WHERE conversation_id=? AND role='assistant' AND state='complete' AND NOT EXISTS (SELECT 1 FROM message_payloads p WHERE p.message_id=messages.id AND json_extract(p.payload,'$.kind')='conversation_action') ORDER BY rowid DESC LIMIT 1",
          [.string(conversation)])
        return try id.string.map { try historyMessage($0, conversation: conversation) }
      }
    }
  }
  public func conversationIdentity(_ id: String, cancellation: Cancellation = .init()) throws
    -> Value
  {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        guard
          let row = try db.execute("SELECT * FROM conversations WHERE id=?", [.string(id)]).first
        else { throw SevraError("conversation", "This conversation no longer exists.") }
        return .object(row)
      }
    }
  }

  /// Scope comes from the live run, not tool arguments. A thread action cannot
  /// address a sibling, a later message, or an inherited parent conversation.
  public func conversationAction(
    _ arguments: Value, conversation: String, requestMessage: String,
    expectedTitle: String, token: String, cancellation: Cancellation = .init()
  ) throws -> ConversationActionResult {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    try require(
      arguments.object.keys.allSatisfy {
        ["action", "title", "message", "summary"].contains($0)
      }, "arguments", "Unknown conversation action field.")
    for key in ["title", "message", "summary"] {
      try require(
        arguments[key] == .null || arguments[key].string != nil, "arguments",
        "Use text for " + key + ".")
    }
    let action = arguments["action"].text
    try require(
      ["start_thread", "rename_thread", "return_to_main", "review_summary"].contains(action),
      "arguments", "Choose a supported conversation action.")
    let allowed: Set<String> =
      action == "start_thread"
      ? ["action", "title", "message"]
      : action == "rename_thread"
        ? ["action", "title"]
        : action == "review_summary" ? ["action", "message", "summary"] : ["action"]
    try require(
      Set(arguments.object.keys).isSubset(of: allowed), "arguments",
      "These fields do not apply to this action.")
    let selected: Message? = try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction {
          let request = try historyMessage(requestMessage, conversation: conversation)
          try require(
            request.role == "user", "conversation", "The action needs its current user request.")
          guard ["start_thread", "review_summary"].contains(action) else { return nil }
          let ceiling = try messageLocation(requestMessage)["rowid"]
          let source: String
          if let id = arguments["message"].string {
            source = id
          } else {
            let roles =
              action == "review_summary" ? "role='assistant'" : "role IN ('user','assistant')"
            let last = try db.scalar(
              "SELECT id FROM messages WHERE conversation_id=? AND state='complete' AND NOT EXISTS (SELECT 1 FROM message_payloads p WHERE p.message_id=messages.id AND json_extract(p.payload,'$.kind')='conversation_action') AND "
                + roles
                + " AND rowid<? ORDER BY rowid DESC LIMIT 1",
              [.string(conversation), ceiling])
            source = last.string ?? (action == "start_thread" ? requestMessage : "")
          }
          try require(
            !source.isEmpty, "summary",
            "There is no completed thread answer to share. Ask which findings to use.")
          let message = try historyMessage(source, conversation: conversation)
          try require(
            message.state == "complete" && ["user", "assistant"].contains(message.role)
              && (try messageLocation(source)["rowid"].int ?? 0) <= (ceiling.int ?? 0)
              && (action != "review_summary" || source != requestMessage),
            "history_scope", "Choose a completed earlier exchange in this conversation.")
          return message
        }
      }
    }
    switch action {
    case "start_thread":
      let id = try startThread(
        parentMessage: selected!.id, title: arguments["title"].string,
        token: token, cancellation: control)
      return .init(
        kind: .created, originConversation: conversation, conversation: id, message: selected!.id,
        summary: nil)
    case "rename_thread":
      try require(
        arguments["title"].text.trimmingCharacters(in: .whitespacesAndNewlines) != expectedTitle,
        "unchanged_thread",
        "This thread already has that title. No rename is needed; acknowledge without a conversation action."
      )
      try renameThread(
        conversation, title: arguments["title"].text, expectedTitle: expectedTitle,
        token: token, cancellation: control)
      return .init(
        kind: .renamed, originConversation: conversation, conversation: conversation, message: nil,
        summary: nil)
    case "return_to_main":
      return .init(
        kind: .returnToMain, originConversation: conversation, conversation: "main", message: nil,
        summary: nil)
    default:
      try require(
        conversation != "main", "summary", "These findings are already in the main conversation.")
      let summary = (arguments["summary"].string ?? selected!.body).trimmingCharacters(
        in: .whitespacesAndNewlines)
      try require(
        !summary.isEmpty && summary.utf8.count <= 64_000, "summary",
        "Choose findings of at most 64,000 bytes to review.")
      return .init(
        kind: .reviewSummary, originConversation: conversation, conversation: conversation,
        message: selected!.id, summary: summary)
    }
  }
}
