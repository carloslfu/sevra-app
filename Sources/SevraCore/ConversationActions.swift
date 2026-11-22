import Foundation

public struct ConversationAppReceipt: Decodable, Equatable, Sendable {
  public let appID: String
  public let version: Int
  public let transaction: String
  public let action: String
  public let partial: Bool
}

extension Workbook {
  public func conversationAppReceipt(_ messageID: String, conversation: String)
    throws -> ConversationAppReceipt?
  {
    try synchronized {
      let raw = try db.scalar(
        """
        SELECT json_extract(p.payload,'$.reversibleOutcome')
        FROM messages m JOIN message_payloads p ON p.message_id=m.id
        WHERE m.id=? AND m.conversation_id=? AND m.role='assistant' AND m.state='complete'
          AND json_extract(p.payload,'$.tool')='finish'
        """, [.string(messageID), .string(conversation)])
      guard let data = raw.string, data.utf8.count <= 1024 else { return nil }
      return try? JSONDecoder().decode(ConversationAppReceipt.self, from: Data(data.utf8))
    }
  }
}
