import Foundation

/// A current view of a proposal, separate from its immutable conversation receipt.
public struct ProposalReviewState: Equatable, Sendable {
  public let proposalID: String
  public let currentVersionID: String
  public let currentVersion: Int
  public let status: String
}

extension Workbook {
  // The caller owns the bounded workspace read transaction. Only the visible
  // message window is projected; no source bodies or full tool results are loaded.
  func proposalReviewStates(
    messages: [Message], conversation: String, cancellation: Cancellation
  ) throws -> [String: ProposalReviewState] {
    var states: [String: ProposalReviewState] = [:]
    for message in messages where message.role == "assistant" && message.state == "needs_review" {
      try cancellation.check()
      let payload = try messagePayload(message.id, conversation: conversation)
      let receiptID: Value
      if payload == .null {
        // Older versions did not save a proposal-message association. Recognize
        // only an immediately preceding, journaled proposal result in this chat.
        // Never infer the target from prose, a link or a different conversation.
        receiptID = try db.scalar(
          """
          SELECT t.id FROM tool_calls t WHERE t.message_id=(
            SELECT id FROM messages WHERE conversation_id=?
              AND rowid<(SELECT rowid FROM messages WHERE id=?) ORDER BY rowid DESC LIMIT 1)
          """, [.string(conversation), .string(message.id)])
      } else {
        guard payload["kind"].text == "proposal", payload["itemID"].string != nil else { continue }
        receiptID = payload["receiptID"]
      }
      guard receiptID.string != nil,
        let row = try db.execute(
          """
          SELECT original.id AS proposal_id, headItem.id AS current_id,
            headItem.version, headItem.status
          FROM tool_calls t JOIN agent_runs a ON a.id=t.run_id
          JOIN messages receipt ON receipt.id=t.message_id
          JOIN messages proposal ON proposal.id=? AND proposal.conversation_id=a.conversation_id
          JOIN items original ON original.id=json_extract(t.result,'$.id')
          JOIN heads h ON h.logical_id=original.logical_id
          JOIN items headItem ON headItem.id=h.item_id
          WHERE t.id=? AND a.conversation_id=? AND t.state='completed'
            AND receipt.conversation_id=a.conversation_id AND receipt.rowid<proposal.rowid
            AND t.tool IN ('propose_record','propose_movement','propose_table','propose_table_edit','publish_result')
            AND json_extract(t.result,'$.status')='draft'
            AND original.category='record' AND original.status='draft'
          """, [.string(message.id), receiptID, .string(conversation)]
        ).first,
        payload == .null || payload["itemID"] == row["proposal_id"],
        let version = row["version"]?.int
      else { continue }
      states[message.id] = ProposalReviewState(
        proposalID: row["proposal_id"]!.text, currentVersionID: row["current_id"]!.text,
        currentVersion: version, status: row["status"]!.text)
    }
    return states
  }
}
