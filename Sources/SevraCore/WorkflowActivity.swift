import Foundation

extension Workbook {
  /// Current bounded activity, newest first. Queue mutations invalidate the
  /// continuation; refreshing starts a new coherent observation.
  public func workflowActivity(
    state: String? = nil, limit: Int = 20, cursor: String? = nil,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      (1...50).contains(limit)
        && (state == nil
          || ["queued", "running", "waiting_review", "needs_attention", "completed", "cancelled"]
            .contains(state!)),
      "workflow_limit", "Use a known workflow state and 1 to 50 results.")
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction {
          let revision = try revision()
          let snapshot = try workflowReadSnapshot()
          var predicates: [String] = []
          var values: [Value] = []
          if let state {
            predicates.append("r.state=?")
            values.append(.string(state))
          }
          if let cursor {
            guard cursor.utf8.count <= 4096, let data = Data(base64Encoded: cursor),
              let saved = try? Value.parse(String(decoding: data, as: UTF8.self)),
              saved["workbookID"] == .string(id),
              saved["state"] == (state.map(Value.string) ?? .null),
              saved["limit"] == .number(Double(limit)),
              let after = saved["after"].string, UUID(uuidString: after) != nil,
              let updated = saved["updated"].string, updated.utf8.count <= 64
            else { throw SevraError("workflow_cursor", "Invalid activity continuation.") }
            try require(
              saved["snapshot"] == .string(snapshot), "stale_workflow_activity",
              "Workflow activity changed. Refresh to see current work.")
            predicates.append("(r.updated<? OR (r.updated=? AND r.id<?))")
            values += [.string(updated), .string(updated), .string(after)]
          }
          values.append(.number(Double(limit + 1)))
          let rows = try db.execute(
            "SELECT r.id,r.definition_id,r.state,r.detail,r.created,r.updated,d.title FROM workflow_runs r JOIN app_definitions d ON d.id=r.definition_id"
              + (predicates.isEmpty ? "" : " WHERE " + predicates.joined(separator: " AND "))
              + " ORDER BY r.updated DESC,r.id DESC LIMIT ?",
            values, maxRows: limit + 1, maxBytes: 2_097_152)
          let page = Array(rows.prefix(limit))
          var next: Value = .null
          if rows.count > limit, let last = page.last {
            next = .string(
              Data(
                try Value.object([
                  "workbookID": .string(id), "snapshot": .string(snapshot),
                  "state": state.map(Value.string) ?? .null, "limit": .number(Double(limit)),
                  "after": last["id"]!, "updated": last["updated"]!,
                ]).json().utf8
              ).base64EncodedString())
          }
          return .object([
            "workbookID": .string(id), "revision": .number(Double(revision)),
            "snapshot": .string(snapshot),
            "runs": .array(page.map(Value.object)), "nextCursor": next,
          ])
        }
      }
    }
  }

  /// A read does not authorize or resume execution.
  public func inspectWorkflow(_ runID: String, cancellation: Cancellation = .init()) throws
    -> Value
  {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction {
          let run = try workflowRun(runID)
          let actor = try JSONDecoder().decode(
            ChangeActor.self, from: Data(run["actor"].json().utf8))
          try actor.validate()
          let definition = try applicationDefinition(run["definition_id"].text)
          let workflow = try DefinitionWorkflow(DefinitionDescriptor(definition.content))
          var steps: [Value] = []
          for saved in run["steps"].array {
            try control.check()
            var step = saved.object
            guard let plan = workflow.steps.first(where: { $0.id == saved["step_id"].text }) else {
              throw SevraError(
                "workflow_integrity", "The saved step is missing from its definition.")
            }
            if let binding = plan.binding {
              let target = try applicationDefinition(binding.target)
              step["title"] = .string(target.title)
              step["definitionSource"] = .string(target.sourceID)
              if target.kind == "interpretation" {
                step["outputFields"] = target.payload["outputs"]
              }
            } else {
              step["title"] = .string("Review proposals")
            }
            var proposals: [Value] = []
            for proposalID in saved["output"]["value"]["proposals"].array {
              let original = try item(proposalID.text)
              let current = try item(original.logicalID)
              proposals.append(
                .object([
                  "id": .string(original.id), "currentID": .string(current.id),
                  "title": .string(original.title), "meaning": .string(original.meaning),
                  "scenario": .string(original.scenario), "status": .string(current.status),
                  "changed": .bool(current.id != original.id),
                ]))
            }
            step["proposals"] = .array(proposals)
            var attempt =
              try db.execute(
                "SELECT id,generation,state,deadline,updated FROM workflow_attempts WHERE run_id=? AND step_id=? ORDER BY generation DESC LIMIT 1",
                [.string(runID), saved["step_id"]]
              ).first ?? [:]
            if let id = attempt["id"]?.string,
              let response = try db.scalar(
                "SELECT result FROM operations WHERE id=? AND kind='workflow_interpretation_response'",
                [.string("workflow-response:" + id)]
              ).string
            {
              let captured = try Value.parse(response)
              attempt["modelResponse"] = captured["response"]
              attempt["model"] = captured["request"]["model"]
              attempt["requestID"] = captured["request"]["requestID"]
            }
            step["attempt"] = .object(attempt)
            steps.append(.object(step))
          }
          return .object([
            "run": run, "definition": try encoded(definition), "steps": .array(steps),
            "actorLabel": .string(actor.label),
          ])
        }
      }
    }
  }

  /// An explicit manual continuation, bounded by the 16-step definition. It
  /// stops at review, attention or completion and never polls waiting work.
  public func continueWorkflow(
    _ session: WorkflowExecutionSession, owner: String, cancellation: Cancellation = .init()
  ) throws -> Value {
    try workflowSession(session)
    var run = try workflowRun(session.runID)
    for _ in 0..<16 {
      try cancellation.check()
      if ["completed", "cancelled", "needs_attention"].contains(run["state"].text) { return run }
      run = try advanceWorkflow(session, owner: owner, cancellation: cancellation)
      if run["state"] == .string("waiting_review") { return run }
    }
    return run
  }
}
