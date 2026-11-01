import Foundation

extension Workbook {
  public func claimWorkflowStep(
    _ session: WorkflowExecutionSession, owner: String,
    leaseSeconds: TimeInterval = 30, token: String = identifier(),
    withoutPreparation: Bool = false, cancellation: Cancellation = .init()
  ) throws -> Value {
    try workflowSession(session)
    try workflowToken(token)
    try require(
      !owner.isEmpty && owner.utf8.count <= 128 && leaseSeconds.isFinite
        && (0.05...60).contains(leaseSeconds), "workflow_claim",
      "Use a bounded worker identity and lease from 0.05 to 60 seconds.")
    let deviceFence: () throws -> Void = { try session.automation?.deviceFence?() }
    let result = try mutation(
      "workflow_claim", token: token,
      request: .object([
        "runID": .string(session.runID), "owner": .string(owner), "seconds": .number(leaseSeconds),
      ]),
      cancellation: cancellation, actor: .programmatic("SevraCore.workflowWorker"),
      commitGuard: deviceFence
    ) {
      try self.workflowSession(session)
      let run = try self.workflowRun(session.runID)
      if ["completed", "cancelled"].contains(run["state"].text) { return .null }
      try require(
        run["state"] != .string("needs_attention"), "workflow_attention",
        "Inspect the failed step before explicitly retrying.")
      guard let step = run["steps"].array.first(where: { $0["state"] != .string("completed") })
      else {
        throw SevraError("workflow_integrity", "An active workflow has no unfinished step.")
      }
      // The refusal rolls back here, so the step stays queued for the coordinator.
      if withoutPreparation,
        let refusal = DefinitionWorkflow.preparationRefusal(step["kind"].text)
      {
        throw refusal
      }
      let runID = session.runID
      let stepID = step["step_id"].text
      if step["state"] == .string("waiting_review"),
        let review = try? self.workflowReview(runID, stepID: stepID, recordApprovals: false),
        review["ready"] == .bool(false)
      {
        return .null
      }
      let now = Date().timeIntervalSince1970
      let prior = try self.db.execute(
        "SELECT * FROM workflow_attempts WHERE run_id=? AND step_id=? ORDER BY generation DESC LIMIT 1",
        [.string(runID), .string(stepID)]
      ).first
      if prior?["state"] == .string("claimed") {
        try require(
          Double(prior!["deadline"]!.text).map { $0 <= now } == true,
          "workflow_busy", "Another worker still owns this step.")
        try self.db.execute(
          "UPDATE workflow_attempts SET state='expired',updated=? WHERE id=?",
          [.string(timestamp()), prior!["id"]!])
      }
      let generation = (prior?["generation"]?.int ?? 0) + 1
      try require(
        generation <= 1_000_000_000, "workflow_limit", "The worker generation limit was reached.")
      if generation - (step["attempt_base"].int ?? 0) > 32 {
        let detail =
          "This step exhausted 32 worker attempts. Inspect it, then explicitly retry to resume the same run. Completed work is preserved."
        try self.db.execute(
          "UPDATE workflow_steps SET state='needs_attention',detail=?,updated=? WHERE run_id=? AND step_id=?",
          [.string(detail), .string(timestamp()), .string(runID), .string(stepID)])
        try self.db.execute(
          "UPDATE workflow_runs SET state='needs_attention',detail=?,updated=? WHERE id=?",
          [.string(detail), .string(timestamp()), .string(runID)])
        try self.workflowEvent(runID, stepID: stepID, kind: "retry_limit", payload: .string(detail))
        return .object(["refusal": .string("workflow_retry_limit"), "detail": .string(detail)])
      }
      let id = identifier()
      try self.db.execute(
        "INSERT INTO workflow_attempts VALUES(?,?,?,?,?,?,'claimed',?,?,?)",
        [
          .string(id), .string(runID), .string(stepID), .number(Double(generation)), .string(owner),
          .number(now + leaseSeconds), .string(timestamp()), .string(timestamp()),
          .string(self.workflowClaimAuthorization(session, run: run)),
        ])
      try self.db.execute(
        "UPDATE workflow_steps SET state='claimed',updated=? WHERE run_id=? AND step_id=?",
        [.string(timestamp()), .string(runID), .string(stepID)])
      try self.db.execute(
        "UPDATE workflow_runs SET state='running',updated=? WHERE id=?",
        [.string(timestamp()), .string(runID)])
      return .object(
        try self.db.execute("SELECT * FROM workflow_attempts WHERE id=?", [.string(id)])[0])
    }
    if let refusal = result["refusal"].string {
      throw SevraError(refusal, result["detail"].text)
    }
    return result
  }

  public func heartbeatWorkflowStep(
    _ session: WorkflowExecutionSession, claim: Value,
    leaseSeconds: TimeInterval = 30, token: String = identifier()
  ) throws -> Value {
    try workflowSession(session)
    try workflowToken(token)
    try require(
      leaseSeconds.isFinite && (0.05...60).contains(leaseSeconds), "workflow_claim",
      "Use a lease from 0.05 to 60 seconds.")
    let deviceFence: () throws -> Void = { try session.automation?.deviceFence?() }
    return try mutation(
      "workflow_heartbeat", token: token,
      request: .object(["claim": claim, "seconds": .number(leaseSeconds)]),
      cancellation: .init(), actor: .programmatic("SevraCore.workflowWorker"),
      commitGuard: deviceFence
    ) {
      _ = try self.validateWorkflowClaim(session, claim: claim)
      try self.db.execute(
        "UPDATE workflow_attempts SET deadline=?,updated=? WHERE id=?",
        [.number(Date().timeIntervalSince1970 + leaseSeconds), .string(timestamp()), claim["id"]])
      return .object(
        try self.db.execute("SELECT * FROM workflow_attempts WHERE id=?", [claim["id"]])[0])
    }
  }

  func validateWorkflowClaim(_ session: WorkflowExecutionSession, claim: Value) throws -> Value {
    try workflowSession(session)
    try require(
      try claim.json().utf8.count <= 8192, "workflow_claim", "The worker claim exceeds 8 KiB.")
    guard claim["id"].string != nil,
      let row = try db.execute(
        "SELECT a.* FROM workflow_attempts a JOIN workflow_steps s ON s.run_id=a.run_id AND s.step_id=a.step_id JOIN workflow_runs r ON r.id=a.run_id WHERE a.id=? AND a.run_id=? AND a.state='claimed' AND s.state='claimed' AND r.state='running' AND a.generation=(SELECT max(generation) FROM workflow_attempts WHERE run_id=a.run_id AND step_id=a.step_id)",
        [claim["id"], .string(session.runID)]
      ).first,
      row["owner"] == claim["owner"], row["generation"] == claim["generation"],
      row["authorization_source"] == claim["authorization_source"],
      try workflowClaimAuthorityMatches(session, sourceID: row["authorization_source"]!.text),
      row["step_id"] == claim["step_id"], row["run_id"] == claim["run_id"],
      Double(row["deadline"]!.text).map({ $0 > Date().timeIntervalSince1970 }) == true
    else {
      throw SevraError(
        "workflow_fenced",
        "This worker claim expired, was replaced or no longer has execution authority.")
    }
    return .object(row)
  }

  public func failWorkflowStep(
    _ session: WorkflowExecutionSession, claim: Value,
    detail: String, token: String = identifier()
  ) throws -> Value {
    try workflowSession(session)
    try workflowToken(token)
    try require(
      !detail.isEmpty && detail.utf8.count <= 4096, "workflow_limit",
      "Use an error detail from 1 to 4096 bytes.")
    let deviceFence: () throws -> Void = { try session.automation?.deviceFence?() }
    return try mutation(
      "workflow_failure", token: token,
      request: .object(["claim": claim, "detail": .string(detail)]), cancellation: .init(),
      actor: .programmatic("SevraCore.workflowWorker"),
      commitGuard: deviceFence
    ) {
      _ = try self.validateWorkflowClaim(session, claim: claim)
      try self.db.execute(
        "UPDATE workflow_attempts SET state='failed',updated=? WHERE id=?",
        [.string(timestamp()), claim["id"]])
      try self.db.execute(
        "UPDATE workflow_steps SET state='needs_attention',detail=?,updated=? WHERE run_id=? AND step_id=?",
        [.string(detail), .string(timestamp()), .string(session.runID), claim["step_id"]])
      try self.db.execute(
        "UPDATE workflow_runs SET state='needs_attention',detail=?,updated=? WHERE id=?",
        [.string(detail), .string(timestamp()), .string(session.runID)])
      try self.workflowEvent(
        session.runID, stepID: claim["step_id"].text, kind: "failed", payload: .string(detail))
      return try self.workflowRun(session.runID)
    }
  }

  public func retryWorkflow(
    _ session: WorkflowExecutionSession, token: String,
    actor: ChangeActor = .programmatic("SevraCore.workflowManualRetry")
  ) throws -> Value {
    try workflowSession(session)
    try workflowToken(token)
    let deviceFence: () throws -> Void = { try session.automation?.deviceFence?() }
    return try mutation(
      "workflow_retry", token: token, request: .string(session.runID),
      cancellation: .init(), actor: actor,
      commitGuard: deviceFence
    ) {
      try self.workflowSession(session)
      let run = try self.workflowRun(session.runID)
      try require(
        run["state"] == .string("needs_attention"), "workflow_state",
        "Only a failed workflow needs retry.")
      try self.db.execute(
        "UPDATE workflow_steps SET state='pending',detail='',updated=?,attempt_base=(SELECT coalesce(max(generation),0) FROM workflow_attempts a WHERE a.run_id=workflow_steps.run_id AND a.step_id=workflow_steps.step_id) WHERE run_id=? AND state='needs_attention'",
        [.string(timestamp()), .string(session.runID)])
      try self.db.execute(
        "UPDATE workflow_runs SET state='queued',detail='',updated=? WHERE id=?",
        [.string(timestamp()), .string(session.runID)])
      try self.workflowEvent(session.runID, stepID: nil, kind: "retry", payload: .null)
      return try self.workflowRun(session.runID)
    }
  }

  public func cancelWorkflow(_ session: WorkflowExecutionSession, token: String) throws -> Value {
    try workflowSession(session)
    try workflowToken(token)
    let deviceFence: () throws -> Void = { try session.automation?.deviceFence?() }
    return try mutation(
      "workflow_cancel", token: token, request: .string(session.runID),
      cancellation: .init(), actor: .programmatic("SevraCore.workflowManualCancel"),
      commitGuard: deviceFence
    ) {
      try self.workflowSession(session)
      return try self.cancelWorkflowRun(session.runID)
    }
  }
  public func cancelWorkflow(
    _ runID: String, token: String, actor: ChangeActor = .programmatic("SevraCore.workflowStop"),
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try workflowToken(token)
    return try mutation(
      "workflow_stop", token: token, request: .string(runID), cancellation: cancellation,
      actor: actor
    ) {
      try self.cancelWorkflowRun(runID)
    }
  }

  private func cancelWorkflowRun(_ runID: String) throws -> Value {
    let run = try self.workflowRun(runID)
    if ["completed", "cancelled"].contains(run["state"].text) { return run }
    try self.db.execute(
      "UPDATE workflow_attempts SET state='cancelled',updated=? WHERE run_id=? AND state='claimed'",
      [.string(timestamp()), .string(runID)])
    try self.db.execute(
      "UPDATE workflow_steps SET state='cancelled',updated=? WHERE run_id=? AND state!='completed'",
      [.string(timestamp()), .string(runID)])
    try self.db.execute(
      "UPDATE workflow_runs SET state='cancelled',detail='Completed drafts and accepted business effects are preserved.',updated=? WHERE id=?",
      [.string(timestamp()), .string(runID)])
    try self.workflowEvent(runID, stepID: nil, kind: "cancelled", payload: .null)
    return try self.workflowRun(runID)
  }

  func workflowClaimAuthorityMatches(_ session: WorkflowExecutionSession, sourceID: String) throws
    -> Bool
  {
    if let automation = session.automation { return sourceID == automation.planning.sourceID }
    if session.manualSourceID != nil {
      let source = try item(sourceID)
      return source.kind == "workflow_authorization" && source.category == "source"
        && source.data["runID"] == .string(session.runID)
        && source.data["policy"] == .string("manual-operation-v1")
    }
    return sourceID == (try workflowRun(session.runID))["source_id"].text
  }

  func workflowClaimAuthorization(_ session: WorkflowExecutionSession, run: Value) -> String {
    session.automation?.planning.sourceID ?? session.manualSourceID ?? run["source_id"].text
  }

}
