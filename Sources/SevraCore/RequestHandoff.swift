import Foundation

public enum ContinuedWork: String, Codable, Sendable {
  // Serialized tool identifiers match the shared command registry.
  // swift-format-ignore: AlwaysUseLowerCamelCase
  case answer, draft, save_space, edit_space, restore_space, propose_movement, propose_record,
    propose_table,
    propose_table_edit
}

/// Host-owned continuation of one admitted submission, never a model rewrite.
public struct AgentRequestHandoff: Sendable {
  public let request: AgentRequest
  public let sourceID: String
  public let originMessage: String
  public let conversation: String
  public let work: ContinuedWork
  public let task: String
  public let evidence: Value
}

extension Workbook {
  /// Check before creating a thread. A fresh phase cannot replay earlier work,
  /// inherit a second handoff, or use an unjournaled model call. Earlier read-only
  /// calls may precede it within the same total response budget.
  public func validateRequestHandoff(
    runID: String, conversation: String, cancellation: Cancellation = .init()
  ) throws {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        let rows = try db.execute(
          "SELECT a.status,r.message_id,p.payload FROM agent_runs a JOIN run_requests r ON r.run_id=a.id LEFT JOIN message_payloads p ON p.message_id=r.message_id WHERE a.id=? AND a.conversation_id=?",
          [.string(runID), .string(conversation)])
        guard let run = rows.first, run["status"]?.text == "running" else {
          throw SevraError(
            "handoff_scope", "Continue only the active request in this conversation.")
        }
        let payload = try run["payload"]?.string.map(Value.parse) ?? .null
        try require(
          payload["kind"].text != "continued_request", "handoff_limit",
          "This request already moved into its new thread. Finish the remaining work here.")
        let calls = try db.execute(
          "SELECT t.tool,t.state,o.id AS committed FROM tool_calls t LEFT JOIN operations o ON o.id=t.operation_token WHERE t.run_id=? ORDER BY t.rowid LIMIT 13",
          [.string(runID)])
        try require(
          !calls.isEmpty && calls.count <= 12
            && calls.last?["tool"]?.text == "start_thread_and_continue"
            && ["prepared", "completed"].contains(calls.last?["state"]?.text ?? "")
            && calls.dropLast().allSatisfy { call in
              WorkbookTools.readOnlyTools.contains(call["tool"]?.text ?? "")
                || (call["tool"]?.text == "start_thread_and_continue"
                  && call["state"]?.text == "failed" && call["committed"] == .null)
            }, "handoff_order",
          "The request already attempted changes. Keep its saved work and receipts here; do not restart those changes in another thread."
        )
      }
    }
  }

  /// Called after the creation receipt is saved, while the same inference lease
  /// is held. The journal makes retries idempotent; no code resumes this on open.
  public func handoffAgentRequest(
    runID: String, receiptID: String, sourceID: String, steps: Int, metrics: Value,
    cancellation: Cancellation = .init()
  ) throws -> AgentRequestHandoff {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    let value = try mutation(
      "request_handoff", token: "request-handoff-" + runID,
      request: .object([
        "run": .string(runID), "receipt": .string(receiptID), "source": .string(sourceID),
      ]),
      cancellation: control
    ) {
      guard
        let origin = try db.execute(
          "SELECT a.*,r.message_id,m.body FROM agent_runs a JOIN run_requests r ON r.run_id=a.id JOIN messages m ON m.id=r.message_id WHERE a.id=? AND m.conversation_id=a.conversation_id AND m.role='user'",
          [.string(runID)]
        ).first
      else {
        throw SevraError("handoff_scope", "The original submitted request is unavailable.")
      }
      let conversation = origin["conversation_id"]!.text
      try validateRequestHandoff(runID: runID, conversation: conversation, cancellation: control)
      guard
        let call = try db.execute(
          "SELECT * FROM tool_calls WHERE id=? AND run_id=? AND tool='start_thread_and_continue' AND state='completed'",
          [.string(receiptID), .string(runID)]
        ).first
      else {
        throw SevraError("handoff_receipt", "The new thread needs a completed creation receipt.")
      }
      let outcome = try JSONDecoder().decode(
        ConversationActionResult.self,
        from: Data(call["result"]!.text.utf8))
      let arguments = try Value.parse(call["arguments"]!.text)
      let task = arguments["task"].text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let work = ContinuedWork(rawValue: arguments["work"].string ?? "answer") else {
        throw SevraError("handoff_scope", "Choose a supported continuation task.")
      }
      let target = outcome.conversation
      try require(
        outcome.kind == .created && outcome.originConversation == conversation
          && target != conversation, "handoff_scope",
        "The creation receipt does not identify a new thread.")
      let created = try db.scalar(
        "SELECT result FROM operations WHERE id=? AND kind='start_thread'",
        [call["operation_token"]!])
      try require(
        try created.string.map(Value.parse) == .string(target), "handoff_receipt",
        "The thread must be the committed result of this creation call.")
      try require(
        try db.scalar("SELECT count(*) FROM messages WHERE conversation_id=?", [.string(target)])
          .int == 0,
        "handoff_changed",
        "The new thread already has messages. Open it to review before continuing.")
      let source = try item(sourceID)
      try require(
        source.category == "source" && source.kind == "request"
          && source.text == origin["body"]!.text
          && source.data["messageID"] == origin["message_id"]!
          && source.data["conversationID"] == .string(conversation), "handoff_source",
        "Continue with the exact original request Source.")
      let child = AgentRequest(runID: identifier(), messageID: identifier())
      let now = timestamp()
      let evidence = try handoffEvidence(runID: runID, conversation: conversation)
      let payload: Value = .object([
        "kind": .string("continued_request"), "originMessageID": origin["message_id"]!,
        "originRunID": .string(runID), "sourceID": .string(sourceID),
        "receiptID": .string(receiptID),
        "work": .string(work.rawValue),
        "task": .string(task),
        "evidence": evidence,
        "notice": .string(
          "Exact request carried by the host from its original conversation, not a new submission or a model paraphrase."
        ),
      ])
      try db.execute(
        "INSERT INTO messages VALUES(?,?,'user',?,'complete',?)",
        [.string(child.messageID), .string(target), origin["body"]!, .string(now)])
      try db.execute(
        "INSERT INTO message_payloads VALUES(?,?)",
        [.string(child.messageID), .string(try payload.json())])
      try db.execute(
        "INSERT INTO agent_runs VALUES(?,?,'running',?,0,'[]',?,?)",
        [.string(child.runID), .string(target), origin["model"]!, .string(now), .string(now)])
      try db.execute(
        "INSERT INTO run_requests VALUES(?,?)", [.string(child.runID), .string(child.messageID)])
      try db.execute(
        "UPDATE agent_runs SET status='continued',steps=?,metrics=?,updated=? WHERE id=?",
        [.number(Double(steps)), .string(try metrics.json()), .string(now), .string(runID)])
      let acknowledgment = identifier()
      try db.execute(
        "INSERT INTO messages VALUES(?,?,'assistant',?,'complete',?)",
        [
          .string(acknowledgment), .string(conversation),
          .string("Created a thread. Your request continues there."), .string(now),
        ])
      try db.execute(
        "INSERT INTO message_payloads VALUES(?,?)",
        [
          .string(acknowledgment),
          .string(
            try Value.object([
              "kind": .string("conversation_action"), "result": try encoded(outcome),
              "runID": .string(runID), "receiptID": .string(receiptID),
              "continuationRunID": .string(child.runID),
            ]).json()),
        ])
      return .object([
        "runID": .string(child.runID), "messageID": .string(child.messageID),
        "sourceID": .string(sourceID), "originMessage": origin["message_id"]!,
        "conversation": .string(target),
        "work": .string(work.rawValue),
        "task": .string(task),
        "evidence": evidence,
      ])
    }
    return .init(
      request: .init(runID: value["runID"].text, messageID: value["messageID"].text),
      sourceID: value["sourceID"].text, originMessage: value["originMessage"].text,
      conversation: value["conversation"].text,
      work: ContinuedWork(rawValue: value["work"].text) ?? .answer, task: value["task"].text,
      evidence: value["evidence"])
  }
}
