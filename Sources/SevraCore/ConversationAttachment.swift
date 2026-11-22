import Foundation

extension Workbook {
  /// Bind the user's drop/paste to its original conversation before copying.
  /// The receipt stores the destination and invocation ID without a local path.
  public func captureConversationAttachment(
    _ file: URL, linked: Bool = false, conversation: String, token: String,
    cancellation: Cancellation = .init()
  ) throws -> IntakeJob {
    _ = try mutation(
      "conversation_attachment_intent", token: token + "-conversation-intent",
      request: .object(["conversation": .string(conversation), "intake": .string(token)]),
      cancellation: cancellation
    ) {
      try requireLiveChat(conversation)
      return .string(token)
    }
    let job = try captureIntake(
      file, linked: linked, role: .reference, token: token, cancellation: cancellation)
    try publishConversationAttachment(job.id, conversation: conversation)
    return job
  }

  /// Complete recoverable publications after a crash between capture, job
  /// registration and the transcript event. Never retry a filesystem import.
  public func recoverConversationAttachments(cancellation: Cancellation = .init()) throws {
    let pending = try synchronized(cancellation: cancellation) {
      try db.execute(
        """
        SELECT intent.request, imp.result AS source
        FROM operations intent JOIN operations imp
          ON imp.id=json_extract(intent.request,'$.intake')||'-file' AND imp.kind='import'
        LEFT JOIN operations event ON event.id=json_extract(intent.request,'$.intake')||'-use-conversation-event'
        JOIN conversations chat ON chat.id=json_extract(intent.request,'$.conversation') AND chat.deleted=0
        WHERE intent.kind='conversation_attachment_intent' AND event.id IS NULL
        ORDER BY intent.rowid LIMIT 64
        """,
        maxRows: 64, maxBytes: 131_072)
    }
    for row in pending {
      try cancellation.check()
      let request = try Value.parse(row["request"]!.text)
      let source = try Value.parse(row["source"]!.text)
      let job = try beginIntake(
        sourceID: source.text, role: .reference, token: request["intake"].text + "-use")
      try publishConversationAttachment(job.id, conversation: request["conversation"].text)
    }
  }
}
