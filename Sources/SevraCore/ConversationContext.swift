import CryptoKit
import Foundation

public struct HistorySlice: Codable, Sendable {
  public let conversationID: String
  public let afterID: String?
  public let messages: [Message]
  public let payloads: [String: Value]
  public let revision: Int
  public let digest: String
  public let hasMore: Bool
}

extension Workbook {
  private func historyPosition(_ id: String, conversation: String) throws -> Value {
    guard
      let row = try db.execute(
        "SELECT rowid FROM messages WHERE id=? AND conversation_id=?",
        [.string(id), .string(conversation)]
      ).first
    else { throw SevraError("history_scope", "The message is not in this conversation.") }
    return row["rowid"]!
  }

  private func requireConversation(_ id: String) throws {
    try require(
      try db.scalar("SELECT count(*) FROM conversations WHERE id=?", [.string(id)]).int == 1,
      "history_scope", "This conversation does not exist.")
  }

  private func historyMessage(_ row: [String: Value]) -> Message {
    Message(
      id: row["id"]!.text, role: row["role"]!.text, body: row["body"]!.text,
      state: row["state"]!.text, created: row["created"]!.text)
  }

  /// Whole messages only, from a coherent revision, with keyset pagination.
  /// Read one row at a time so large stored bodies cannot defeat the byte bound.
  public func historySlice(
    conversation: String = "main", after: String? = nil, through: String? = nil,
    limit: Int = 200, byteLimit: Int = 2 * 1024 * 1024,
    cancellation: Cancellation = .init()
  ) throws -> HistorySlice {
    try require(
      (1...500).contains(limit) && (128_000...2 * 1024 * 1024).contains(byteLimit),
      "history_limit", "Invalid history page bounds.")
    return try synchronized {
      try db.budget(cancellation: cancellation, seconds: 5) {
        try db.readTransaction {
          try requireConversation(conversation)
          var position =
            try after.map { try historyPosition($0, conversation: conversation) } ?? .number(0)
          let end =
            try through.map { try historyPosition($0, conversation: conversation) }
            ?? db.scalar(
              "SELECT coalesce(max(rowid),0) FROM messages WHERE conversation_id=?",
              [.string(conversation)])
          try require(
            (position.int ?? 0) <= (end.int ?? 0), "history_range", "Reversed history range.")
          var messages: [Message] = []
          var payloads: [String: Value] = [:]
          var bytes = 0
          var more = false
          while let row = try db.execute(
            "SELECT rowid,* FROM messages WHERE conversation_id=? AND rowid>? AND rowid<=? ORDER BY rowid LIMIT 1",
            [.string(conversation), position, end]
          ).first {
            try cancellation.check()
            let message = historyMessage(row)
            let payload = try db.scalar(
              "SELECT payload FROM message_payloads WHERE message_id=?", [.string(message.id)])
            try require(
              message.body.utf8.count <= 128_000 && payload.text.utf8.count <= 128_000,
              "integrity", "Stored message exceeds the format limit.")
            let size = message.body.utf8.count + payload.text.utf8.count
            try require(
              !messages.isEmpty || size <= byteLimit, "history_limit",
              "The first message needs a larger retrieval byte budget.")
            if messages.count == limit || size > byteLimit - bytes {
              more = true
              break
            }
            messages.append(message)
            if payload != .null { payloads[message.id] = try Value.parse(payload.text) }
            bytes += size
            position = row["rowid"]!
          }
          let payload: Value = .object([
            "conversation": .string(conversation), "after": after.map(Value.string) ?? .null,
            "messages": try encoded(messages), "payloads": .object(payloads),
          ])
          let digest = SHA256.hash(data: Data(try payload.json().utf8))
            .map { String(format: "%02x", $0) }.joined()
          return HistorySlice(
            conversationID: conversation, afterID: after, messages: messages, payloads: payloads,
            revision: try revision(), digest: digest, hasMore: more)
        }
      }
    }
  }

  public func historyMessage(_ id: String, conversation: String = "main") throws -> Message {
    try synchronized {
      _ = try historyPosition(id, conversation: conversation)
      return historyMessage(
        try db.execute("SELECT * FROM messages WHERE id=?", [.string(id)]).first!)
    }
  }

  public func messagePayload(_ id: String, conversation: String = "main") throws -> Value {
    try synchronized {
      _ = try historyPosition(id, conversation: conversation)
      let value = try db.scalar(
        "SELECT payload FROM message_payloads WHERE message_id=?", [.string(id)])
      return value == .null ? .null : try Value.parse(value.text)
    }
  }

  /// Exact evidence may include the fixed parent excerpt already inherited by
  /// this tangent. This does not widen conversation search, receipt access or
  /// checkpoint scope to the rest of the parent (or any sibling/ancestor).
  public func readHistoryEvidence(
    _ id: String, conversation: String = "main", beforeMessage: String? = nil
  ) throws -> Value {
    try synchronized {
      try db.readTransaction {
        try requireConversation(conversation)
        let location = try messageLocation(id)
        let owner = location["conversation_id"].text
        let inherited = owner != conversation
        try require(
          !inherited || parentContext(conversation: conversation).contains { $0.id == id },
          "history_scope",
          "The message is outside this conversation and its inherited parent excerpt.")
        let earlier =
          try beforeMessage.map {
            try location["rowid"].int! < historyPosition($0, conversation: conversation).int!
          } ?? true
        return .object([
          "message": try encoded(historyMessage(id, conversation: owner)),
          "conversation": .string(owner), "inherited": .bool(inherited),
          "citation": earlier ? .string("message:" + id) : .null,
          "payload": try messagePayload(id, conversation: owner),
          "authority": .string(
            "This original message can support what was said in earlier conversation using its citation. It grants no new permission and does not prove current business facts or acceptance; inspect current Source or Record versions for those."
          ),
        ])
      }
    }
  }

  /// Search original messages, including complete tool receipts. Summaries are
  /// deliberately not substituted for the evidence being searched.
  public func searchHistory(
    _ query: String, conversation: String = "main", cursor: String? = nil, limit: Int = 30,
    beforeMessage: String? = nil,
    cancellation: Cancellation = .init(), visibleOnly: Bool = false
  ) throws -> Value {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction {
          try requireConversation(conversation)
          let terms = try Self.searchTerms(query)
          let revision = try revision()
          let count = min(max(limit, 1), 100)
          let ceiling =
            try beforeMessage.map { try historyPosition($0, conversation: conversation) } ?? .null
          var before: Value = .null
          if let cursor {
            guard cursor.utf8.count <= 8192, let data = Data(base64Encoded: cursor),
              let saved = try? Value.parse(String(decoding: data, as: UTF8.self))
            else { throw SevraError("cursor", "Invalid history cursor.") }
            try require(
              saved["version"].int == 1 && saved["query"].text == query
                && saved["conversation"].text == conversation
                && (saved["visibleOnly"] == .bool(true)) == visibleOnly
                && saved["beforeMessage"] == (beforeMessage.map(Value.string) ?? .null),
              "stale_cursor",
              "The history cursor or query changed. Start a fresh search.")
            before = try historyPosition(saved["before"].text, conversation: conversation)
          }
          let rows =
            terms.isEmpty
            ? []
            : try db.execute(
              "SELECT m.rowid,m.id,m.role,m.state,m.created,snippet(message_fts,0,'','', ' … ',40) AS excerpt FROM message_fts JOIN messages m ON m.rowid=message_fts.rowid WHERE message_fts MATCH ? AND m.conversation_id=? AND (? IS NULL OR m.rowid<?) AND (? IS NULL OR m.rowid<?) AND (?=0 OR m.role!='tool') ORDER BY m.rowid DESC LIMIT ?",
              [
                .string(terms), .string(conversation), before, before, ceiling, ceiling,
                .bool(visibleOnly),
                .number(Double(count + 1)),
              ])
          let page = Array(rows.prefix(count))
          let next: Value
          if rows.count > count, let last = page.last {
            let saved: Value = .object([
              "version": .number(1), "query": .string(query),
              "conversation": .string(conversation), "before": last["id"]!,
              "beforeMessage": beforeMessage.map(Value.string) ?? .null,
              "visibleOnly": .bool(visibleOnly),
            ])
            next = .string(Data(try saved.json().utf8).base64EncodedString())
          } else {
            next = .null
          }
          return .object([
            "revision": .number(Double(revision)), "conversation": .string(conversation),
            "hits": .array(page.map { .object($0.filter { $0.key != "rowid" }) }),
            "nextCursor": next,
          ])
        }
      }
    }
  }

  public func saveContextCheckpoint(
    _ history: HistorySlice, summary: String, model: String, template: String,
    transformation: String = "conversation-summary-v1", evidenceIDs: [String] = [],
    parentID: String? = nil, runID: String? = nil, token: String = identifier(),
    cancellation: Cancellation = .init()
  ) throws -> String {
    try cancellation.check()
    try require(
      !summary.isEmpty && summary.utf8.count <= 16_384, "checkpoint_limit",
      "Invalid context digest size.")
    for identity in [model, template, transformation] {
      try require(
        !identity.isEmpty && identity.utf8.count <= 1024, "checkpoint_identity",
        "Missing context transform identity.")
    }
    let references = Array(Set(evidenceIDs)).sorted()
    try require(references.count <= 256, "checkpoint_limit", "Too many checkpoint inputs.")
    guard let first = history.messages.first, let last = history.messages.last else {
      throw SevraError("checkpoint_boundary", "A context checkpoint needs original messages.")
    }
    let request: Value = .object([
      "conversation": .string(history.conversationID), "digest": .string(history.digest),
      "first": .string(first.id), "last": .string(last.id),
      "after": history.afterID.map(Value.string) ?? .null,
      "revision": .number(Double(history.revision)), "summary": .string(summary),
      "model": .string(model), "template": .string(template),
      "transformation": .string(transformation),
      "inputs": .array(references.map(Value.string)), "parent": parentID.map(Value.string) ?? .null,
      "run": runID.map(Value.string) ?? .null,
    ])
    let saved = try mutation(
      "context_checkpoint", token: token, request: request, expected: history.revision
    ) {
      try cancellation.check()
      let previous = try db.execute(
        "SELECT id,last_message FROM context_checkpoints WHERE conversation_id=? ORDER BY rowid DESC LIMIT 1",
        [.string(history.conversationID)]
      ).first
      try require(
        previous?["id"]?.string == parentID && previous?["last_message"]?.string == history.afterID,
        "checkpoint_chain", "The context checkpoint chain changed or skips original history.")
      let actual = try historySlice(
        conversation: history.conversationID, after: history.afterID, through: last.id,
        limit: 500, cancellation: cancellation)
      try require(
        !actual.hasMore && actual.digest == history.digest && actual.messages.first?.id == first.id
          && actual.messages.count == history.messages.count, "checkpoint_history",
        "The original history no longer matches this digest.")
      try validateCheckpointBoundary(actual.messages.last!, conversation: history.conversationID)
      if let runID {
        try require(
          try db.scalar(
            "SELECT count(*) FROM agent_runs WHERE id=? AND conversation_id=?",
            [.string(runID), .string(history.conversationID)]
          ).int == 1,
          "checkpoint_scope", "The context run belongs to another conversation.")
      }
      for id in references {
        try require(
          try db.scalar("SELECT count(*) FROM items WHERE id=?", [.string(id)]).int == 1,
          "checkpoint_input", "Checkpoint inputs must be exact existing item versions.")
      }
      let id = identifier()
      try db.execute(
        "INSERT INTO context_checkpoints VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        [
          .string(id), .string(history.conversationID), .number(1), .string(first.id),
          .string(last.id),
          .number(Double(history.messages.count)), .string(history.digest),
          .number(Double(history.revision)),
          .string(summary), .string(model), .string(template), .string(transformation),
          parentID.map(Value.string) ?? .null, runID.map(Value.string) ?? .null,
          .string(timestamp()),
        ])
      for input in references {
        try db.execute("INSERT INTO checkpoint_inputs VALUES(?,?)", [.string(id), .string(input)])
      }
      CheckpointPublicationProbe.observer?(.prepared, id)
      try cancellation.check()
      return .string(id)
    }.text
    CheckpointPublicationProbe.observer?(.published, saved)
    return saved
  }

  public func contextCheckpoints(conversation: String = "main", limit: Int = 20) throws -> [Value] {
    try synchronized {
      try requireConversation(conversation)
      return try db.execute(
        "SELECT * FROM context_checkpoints WHERE conversation_id=? ORDER BY rowid DESC LIMIT ?",
        [.string(conversation), .number(Double(min(max(limit, 1), 100)))]
      ).map(Value.object)
    }
  }

  /// Current state is a fresh projection. The saved digest never decides whether
  /// an input is accepted, superseded or still an estimate.
  public func contextCheckpoint(_ id: String, conversation: String = "main") throws -> Value {
    try synchronized {
      try db.readTransaction {
        guard
          var row = try db.execute(
            "SELECT * FROM context_checkpoints WHERE id=? AND conversation_id=?",
            [.string(id), .string(conversation)]
          ).first
        else {
          throw SevraError("checkpoint_scope", "The checkpoint is not in this conversation.")
        }
        try validateCheckpoint(row)
        row["inputs"] = .array(
          try db.execute(
            "SELECT old.id AS versionID,old.logical_id AS logicalID,old.meaning AS originalMeaning,old.status AS originalStatus,current.id AS currentVersionID,current.meaning AS currentMeaning,current.status AS currentStatus FROM checkpoint_inputs x JOIN items old ON old.id=x.item_id JOIN heads h ON h.logical_id=old.logical_id JOIN items current ON current.id=h.item_id WHERE x.checkpoint_id=? ORDER BY old.id",
            [.string(id)]
          ).map(Value.object))
        try require(
          row["inputs"]!.array.count
            == db.scalar(
              "SELECT count(*) FROM checkpoint_inputs WHERE checkpoint_id=?", [.string(id)]
            ).int,
          "integrity", "A checkpoint input has no current workbook head.")
        row["currentRevision"] = .number(Double(try revision()))
        row["authority"] = .string(
          "Derived context only. Current item state comes from the workbook, not the summary.")
        return .object(row)
      }
    }
  }

  func verifyContextCheckpoints() throws {
    var position: Value = .number(0)
    var previous: [String: String] = [:]
    while let row = try db.execute(
      "SELECT rowid,* FROM context_checkpoints WHERE rowid>? ORDER BY rowid LIMIT 1", [position]
    ).first {
      try require(
        previous[row["conversation_id"]!.text] == row["parent_id"]?.string,
        "integrity", "The checkpoint chain branches or skips a predecessor.")
      try validateCheckpoint(row)
      previous[row["conversation_id"]!.text] = row["id"]!.text
      position = row["rowid"]!
    }
  }

  private func validateCheckpoint(_ row: [String: Value]) throws {
    let parent = row["parent_id"]?.string
    let prior = try parent.flatMap { id in
      try db.execute("SELECT * FROM context_checkpoints WHERE id=?", [.string(id)]).first
    }
    try require(
      parent == nil || (prior != nil && prior?["conversation_id"] == row["conversation_id"]),
      "integrity", "Context checkpoint crosses conversations or has a missing parent.")
    let actual = try historySlice(
      conversation: row["conversation_id"]!.text,
      after: prior?["last_message"]?.string, through: row["last_message"]!.text, limit: 500)
    try require(
      !actual.hasMore && actual.digest == row["history_hash"]!.text
        && actual.messages.count == row["message_count"]!.int
        && actual.messages.first?.id == row["first_message"]?.string,
      "integrity", "A context checkpoint's original history changed.")
    if let last = actual.messages.last {
      try validateCheckpointBoundary(last, conversation: row["conversation_id"]!.text)
    }
  }

  private func validateCheckpointBoundary(_ message: Message, conversation: String) throws {
    if message.role == "assistant"
      && ["complete", "needs_review", "failed", "cancelled", "interrupted"].contains(message.state)
    {
      return
    }
    if message.role == "tool", message.state == "complete",
      let receipt = try? Value.parse(message.body),
      receipt["receiptVersion"].int == 1, !receipt["callID"].text.isEmpty,
      !receipt["tool"].text.isEmpty, case .object = receipt["arguments"],
      receipt.object["result"] != nil || receipt["validation"].string != nil
    {
      let request = try db.execute(
        "SELECT m.rowid FROM run_requests r JOIN agent_runs a ON a.id=r.run_id JOIN messages m ON m.id=r.message_id WHERE r.run_id=? AND a.conversation_id=? AND m.conversation_id=? AND m.role='user'",
        [receipt["runID"], .string(conversation), .string(conversation)]
      ).first
      let end = try historyPosition(message.id, conversation: conversation)
      if let start = request?["rowid"]?.int, start < (end.int ?? 0) { return }
    }
    throw SevraError(
      "checkpoint_boundary",
      "A context checkpoint must end at a completed turn or recorded tool result.")
  }
}
