import Foundation

extension Workbook {
  /// The request just before this one, when it stopped. A checkpoint can cover its message, and
  /// then a person asking to continue would be referring to something the model cannot see.
  /// This names it and what it finished. Its text stays behind history_read, never a new task.
  func stoppedRequest(conversation: String, runID: String) throws -> Value {
    guard
      let previous = try db.execute(
        "SELECT a.id,a.status,r.message_id FROM agent_runs a JOIN run_requests r ON r.run_id=a.id WHERE a.conversation_id=? AND a.rowid<(SELECT rowid FROM agent_runs WHERE id=?) ORDER BY a.rowid DESC LIMIT 1",
        [.string(conversation), .string(runID)]
      ).first, ["cancelled", "failed", "interrupted"].contains(previous["status"]!.text)
    else { return .null }
    var finished: [Value] = []
    var seen = Set<String>()
    for call in try db.execute(
      "SELECT tool,arguments FROM tool_calls WHERE run_id=? AND state='completed' ORDER BY rowid LIMIT 64",
      [previous["id"]!]
    ) {
      let arguments = try Value.parse(call["arguments"]!.text)
      var title = arguments["title"].string
      if title == nil, let id = arguments["id"].string {
        title = try db.scalar("SELECT title FROM items WHERE id=?", [.string(id)]).string
      }
      guard finished.count < 16, seen.insert(call["tool"]!.text + (title ?? "")).inserted else {
        continue
      }
      finished.append(.object(["tool": call["tool"]!, "title": title.map(Value.string) ?? .null]))
    }
    return .object([
      "messageID": previous["message_id"]!, "status": previous["status"]!,
      "finished": .array(finished),
      "notice": .string(
        "The previous request stopped before finishing and is not pending. Only if the current request asks to continue it, read its exact text with history_read using this messageID, then do what remains. Finished work is saved. Do not repeat it."
      ),
    ])
  }
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
          let result =
            receipt["result"]["receiptID"] == .null
            ? receipt["result"] : ToolResultProjection.visibleValue(receipt["result"])
          if let id =
            (receipt["resultIdentity"]["id"].string ?? result["id"].string
              ?? result["item"]["id"].string),
            try db.scalar("SELECT count(*) FROM items WHERE id=?", [.string(id)]).int == 1
          {
            ids.insert(id)
          }
        }
        for id in references { try inspect(historyMessage(id, conversation: conversation)) }
        let callRows = try db.execute(
          "SELECT id,call_id,tool,state,operation_token,message_id,result_hash FROM tool_calls WHERE run_id=? ORDER BY rowid DESC LIMIT 100",
          [.string(runID)]
        ).reversed()
        let details = try continuationDetails(
          calls: Array(callRows), runID: runID, conversation: conversation)
        let calls = try callRows.map { row -> Value in
          var info = row.filter { !["call_id", "result_hash"].contains($0.key) }
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
          guard
            let row = try db.execute(
              "SELECT old.id AS originalVersion,current.id AS currentVersion,current.title,current.status,current.meaning,current.kind,json_extract(current.data,'$.datasetID') AS datasetID FROM items old JOIN heads h ON h.logical_id=old.logical_id JOIN items current ON current.id=h.item_id WHERE old.id=?",
              [.string(id)]
            ).first
          else { throw SevraError("integrity", "A continuation item has no current head.") }
          return .object(row)
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
          "readEvidence": details["reads"], "savedSpaces": details["spaces"],
          "documentCopies": details["documentCopies"],
          "callsOmitted": .bool(
            (try db.scalar("SELECT count(*) FROM tool_calls WHERE run_id=?", [.string(runID)]).int
              ?? 0)
              > calls.count),
          "unresolvedCalls": .array(unresolved), "unresolvedCount": unresolvedCount,
          "stoppedRequest": try stoppedRequest(conversation: conversation, runID: runID),
          "referencedOutcomes": .array(outcomes), "revision": .number(Double(try revision())),
          "authority": .string(
            "Host state, not new permission. Do not repeat completed calls. Failed/cancelled/interrupted earlier requests are closed. Accepted estimates remain estimates. Prepared calls have uncertain outcomes and must not be automatically replayed."
          ),
        ])
      }
    }
  }
}
