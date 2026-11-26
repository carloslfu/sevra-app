import CryptoKit
import Foundation

/// An exact host-prepared change. A model cannot approve it through workspace_action.
/// Append-only conversation receipts preserve the preview, human input and outcome.
public struct ChatApproval: Equatable, Sendable {
  public let id: String
  public let action: String
  public let arguments: Value
  public let title: String
  public var revision: Int { 1 }
  public func effectDigest() throws -> String {
    let effect = try Value.object(["action": .string(action), "arguments": arguments]).json()
    return SHA256.hash(data: Data(effect.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

extension Workbook {
  @discardableResult public func prepareChatApproval(
    action: String, arguments: Value, title: String, conversation: String
  ) throws -> String {
    _ = try ChatOperations.validate(action, arguments: arguments, readOnly: false)
    return try addMessage(
      title,
      role: "event", conversation: conversation,
      payload: .object([
        "kind": .string("chat_approval"), "action": .string(action),
        "arguments": arguments, "title": .string(title),
      ]))
  }

  public func pendingChatApproval(conversation: String) throws -> ChatApproval? {
    try synchronized {
      guard
        let row = try db.execute(
          """
          SELECT m.id,p.payload FROM messages m JOIN message_payloads p ON p.message_id=m.id
          WHERE m.conversation_id=? AND json_extract(p.payload,'$.kind')='chat_approval'
          ORDER BY m.rowid DESC LIMIT 1
          """, [.string(conversation)]
        ).first
      else { return nil }
      let id = row["id"]!.text
      let handled =
        try db.scalar(
          """
          SELECT count(*) FROM messages m JOIN message_payloads p ON p.message_id=m.id
          WHERE m.conversation_id=? AND json_extract(p.payload,'$.approvalID')=?
            AND json_extract(p.payload,'$.kind') IN ('chat_approval_started','chat_approval_cancelled')
          """, [.string(conversation), .string(id)]
        ).int ?? 0
      guard handled == 0 else { return nil }
      let payload = try Value.parse(row["payload"]!.text)
      return .init(
        id: id, action: payload["action"].text, arguments: payload["arguments"],
        title: payload["title"].text)
    }
  }

  /// This is called only by the native composer, with a saved human message.
  /// Claim before executing: a crash must never replay an uncertain change.
  public func claimChatApproval(conversation: String, messageID: String, cancel: Bool = false)
    throws -> ChatApproval
  {
    try claimChatApproval(conversation: conversation, cancel: cancel, expected: nil) { approval in
      guard
        let message = try db.execute(
          "SELECT role,body FROM messages WHERE id=? AND conversation_id=? AND rowid>(SELECT rowid FROM messages WHERE id=?)",
          [.string(messageID), .string(conversation), .string(approval.id)]
        ).first
      else {
        throw SevraError("chat_approval", "Confirmation must come from this conversation.")
      }
      let body = message["body"]!.text.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
      try require(
        message["role"] == .string("user")
          && (cancel ? body == "cancel approval" : ["confirm", "confirm change"].contains(body)),
        "chat_approval", "A new human confirmation is required.")
      return messageID
    }
  }

  /// Native controls pass the exact effect displayed to the human. Save their
  /// confirmation and claim together, before dispatching the effect.
  public func claimChatApproval(
    _ expected: ChatApproval, conversation: String, cancel: Bool = false, humanText: String
  ) throws -> ChatApproval {
    try claimChatApproval(conversation: conversation, cancel: cancel, expected: expected) {
      approval in
      let id = identifier()
      try insertSurfaceMessage(
        id, conversation: conversation, role: "user", body: humanText, state: "complete",
        payload: .object([
          "kind": .string("chat_approval_response"), "approvalID": .string(approval.id),
          "revision": .number(Double(approval.revision)),
          "effectDigest": .string(try approval.effectDigest()),
        ]))
      return id
    }
  }

  private func claimChatApproval(
    conversation: String, cancel: Bool, expected: ChatApproval?,
    humanMessage: (ChatApproval) throws -> String
  ) throws -> ChatApproval {
    var claimed: ChatApproval?
    _ = try mutation(
      "chat_approval_claim", request: .string(expected?.id ?? conversation),
      actor: .human("Sevra.chat-confirmation")
    ) {
      guard let approval = try pendingChatApproval(conversation: conversation),
        expected == nil || expected == approval
      else {
        throw SevraError("chat_approval", "This change is no longer waiting for confirmation.")
      }
      let messageID = try humanMessage(approval)
      let receiptID = identifier()
      try db.execute(
        "INSERT INTO messages VALUES(?,?,?,?,?,?)",
        [
          .string(receiptID), .string(conversation), .string("event"),
          .string(
            cancel
              ? "Approval cancelled. No change was applied." : "Applying your confirmed change."),
          .string("complete"), .string(timestamp()),
        ])
      let payload: Value = .object([
        "kind": .string(cancel ? "chat_approval_cancelled" : "chat_approval_started"),
        "approvalID": .string(approval.id), "messageID": .string(messageID),
        "revision": .number(Double(approval.revision)),
        "effectDigest": .string(try approval.effectDigest()),
      ])
      try db.execute(
        "INSERT INTO message_payloads VALUES(?,?)",
        [.string(receiptID), .string(try payload.json())])
      claimed = approval
      return .string(approval.id)
    }
    return claimed!
  }

  public func finishChatApproval(
    _ approval: ChatApproval, conversation: String, result: Value, error: String? = nil
  ) throws {
    _ = try addMessage(
      error.map {
        "The confirmed change did not finish: " + $0 + " Inspect saved results before retrying."
      }
        ?? Self.completion(approval, result: result),
      role: "event", conversation: conversation,
      payload: .object([
        "kind": .string("chat_approval_result"), "approvalID": .string(approval.id),
        "result": result, "error": error.map(Value.string) ?? .null,
      ]))
  }

  /// What the chat says once a confirmed change is saved: what happened, in words.
  static func completion(_ approval: ChatApproval, result: Value) -> String {
    let title = "“" + result["title"].text + "”"
    let changed = Workbook.tableChangeSummary(result)
    if !changed.isEmpty {
      return changed.joined(separator: " ")
        + (result["undo"].string != nil ? " You can undo this." : "")
    }
    switch result["status"].string {
    case "removed": return "Removed " + title + ". History keeps it, and Restore brings it back."
    case "restored":
      return "Restored " + title + "." + (result["note"].string.map { " " + $0 } ?? "")
    default:
      return "Done. "
        + approval.title.components(separatedBy: "\n")[0].replacingOccurrences(of: "?", with: ".")
    }
  }
}
