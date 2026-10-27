import Foundation

extension Workbook {
  /// Reconstruct operation outcomes and current proposal state from records,
  /// never from a model-written digest. Does not resume or mutate any call.
  public func continuationState(conversation: String, runID: String, messageIDs: [String]) throws
    -> Value
  {
    try synchronized {
      try db.readTransaction {
        guard
          let run = try db.execute(
            "SELECT id,status FROM agent_runs WHERE id=? AND conversation_id=?",
            [.string(runID), .string(conversation)]
          ).first
        else {
          throw SevraError("context_scope", "The active run is not in this conversation.")
        }
        let references = Array(Set(messageIDs)).sorted()
        try require(references.count <= 256, "context_limit", "Too many continuation references.")
        var ids = Set<String>()
        var outcomes: [Value] = []
        func inspect(_ message: Message) throws {
          if message.role == "assistant" {
            outcomes.append(
              .object(["messageID": .string(message.id), "state": .string(message.state)]))
          }
          guard message.role == "tool", let receipt = try? Value.parse(message.body) else { return }
          if let id = (receipt["resultIdentity"]["id"].string ?? receipt["result"]["id"].string),
            try db.scalar("SELECT count(*) FROM items WHERE id=?", [.string(id)]).int == 1
          {
            ids.insert(id)
          }
        }
        for id in references { try inspect(historyMessage(id, conversation: conversation)) }
        let calls = try db.execute(
          "SELECT id,tool,state,operation_token,message_id FROM tool_calls WHERE run_id=? ORDER BY rowid LIMIT 100",
          [.string(runID)]
        ).map { row -> Value in
          var info = row
          if let message = row["message_id"]?.string {
            try inspect(historyMessage(message, conversation: conversation))
          }
          if let operation = try db.execute(
            "SELECT kind,result FROM operations WHERE id=?", [row["operation_token"]!]
          ).first {
            info["committedOperation"] = .object([
              "kind": operation["kind"]!, "result": try Value.parse(operation["result"]!.text),
            ])
          }
          return .object(info)
        }
        let current = try ids.sorted().map { id -> Value in
          let original = try item(id)
          let head = try item(original.logicalID)
          return .object([
            "originalVersion": .string(id), "currentVersion": .string(head.id),
            "title": .string(head.title),
            "status": .string(head.status), "meaning": .string(head.meaning),
            "kind": .string(head.kind),
            "datasetID": head.data["datasetID"],
          ])
        }
        let unresolved = try unresolvedToolCalls(conversation: conversation).map { call in
          Value.object(
            call.object.filter {
              [
                "id", "run_id", "tool", "state", "run_status", "operation_token",
                "committedOperation", "notice",
              ].contains($0.key)
            })
        }
        let unresolvedCount = try db.scalar(
          "SELECT count(*) FROM tool_calls t JOIN agent_runs a ON a.id=t.run_id WHERE a.conversation_id=? AND t.state='prepared'",
          [.string(conversation)])
        return .object([
          "run": .object(run), "calls": .array(calls), "recordStates": .array(current),
          "unresolvedCalls": .array(unresolved), "unresolvedCount": unresolvedCount,
          "referencedOutcomes": .array(outcomes), "revision": .number(Double(try revision())),
          "authority": .string(
            "Host state, not new permission. Do not repeat completed calls. Failed/cancelled/interrupted earlier requests are closed. Accepted estimates remain estimates. Prepared calls have uncertain outcomes and must not be automatically replayed."
          ),
        ])
      }
    }
  }
}
