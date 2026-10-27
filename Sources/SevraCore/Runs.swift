import Foundation

extension Workbook {
  /// Exact request-to-run linkage, independent of recent-run pagination and prose.
  public func requestRunStatus(_ messageID: String) throws -> String? {
    try synchronized {
      try db.scalar(
        "SELECT a.status FROM run_requests r JOIN agent_runs a ON a.id=r.run_id WHERE r.message_id=?",
        [.string(messageID)]
      ).string
    }
  }
  func runRequestMessage(_ id: String) throws -> String? {
    try synchronized {
      try db.scalar("SELECT message_id FROM run_requests WHERE run_id=?", [.string(id)]).string
    }
  }

  public func startAgentRun(conversation: String, model: String, requestMessageID: String? = nil)
    throws -> String
  {
    let id = identifier()
    _ = try mutation("agent_run", request: .string(id)) {
      if let requestMessageID {
        try require(
          try db.scalar(
            "SELECT count(*) FROM messages WHERE id=? AND conversation_id=? AND role='user'",
            [.string(requestMessageID), .string(conversation)]
          ).int == 1,
          "run_request", "The run needs a user message in this conversation.")
      }
      try db.execute(
        "UPDATE agent_runs SET status='interrupted',updated=? WHERE status='running'",
        [.string(timestamp())])
      try db.execute(
        "INSERT INTO agent_runs VALUES(?,?,?,?,?,?,?,?)",
        [
          .string(id), .string(conversation), .string("running"), .string(model), .number(0),
          .string("[]"), .string(timestamp()), .string(timestamp()),
        ])
      if let requestMessageID {
        try db.execute(
          "INSERT INTO run_requests VALUES(?,?)", [.string(id), .string(requestMessageID)])
      }
      return .string(id)
    }
    return id
  }
  public func finishAgentRun(_ id: String, status: String, steps: Int, metrics: Value) throws {
    try require(
      ["complete", "needs_review", "failed", "cancelled", "interrupted"].contains(status), "run",
      "Invalid terminal state.")
    _ = try mutation(
      "agent_terminal", request: .object(["id": .string(id), "status": .string(status)])
    ) {
      try db.execute(
        "UPDATE agent_runs SET status=?,steps=?,metrics=?,updated=? WHERE id=?",
        [
          .string(status), .number(Double(steps)), .string(try metrics.json()),
          .string(timestamp()), .string(id),
        ])
      return .string(id)
    }
  }
  public func agentRuns() throws -> [Value] {
    try synchronized {
      try db.execute(
        "SELECT a.*,r.message_id AS request_message_id FROM agent_runs a LEFT JOIN run_requests r ON r.run_id=a.id ORDER BY a.rowid DESC LIMIT 100"
      ).map(Value.object)
    }
  }
}
