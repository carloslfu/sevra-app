import Foundation

extension Workbook {
  public func startAgentRun(conversation: String, model: String) throws -> String {
    let id = identifier()
    _ = try mutation("agent_run", request: .string(id)) {
      try db.execute(
        "UPDATE agent_runs SET status='interrupted',updated=? WHERE status='running'",
        [.string(timestamp())])
      try db.execute(
        "INSERT INTO agent_runs VALUES(?,?,?,?,?,?,?,?)",
        [
          .string(id), .string(conversation), .string("running"), .string(model), .number(0),
          .string("[]"), .string(timestamp()), .string(timestamp()),
        ])
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
      try db.execute("SELECT * FROM agent_runs ORDER BY rowid DESC LIMIT 100").map(Value.object)
    }
  }
}
