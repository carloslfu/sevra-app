import Foundation

/// Permission to prepare calendar slots in this open connection only. This is
/// neither serializable nor authority to execute workflows or accept effects.
public final class AutomationPlanningSession: @unchecked Sendable {
  let workbook: Workbook
  public let activationID: String
  public let generation: Int
  let sourceID: String
  init(_ workbook: Workbook, activation: Value) {
    self.workbook = workbook
    activationID = activation["id"].text
    generation = activation["generation"].int!
    sourceID = activation["source_id"].text
  }
}

enum AutomationTime {
  static func text(_ date: Date) throws -> String {
    try require(date.timeIntervalSince1970.isFinite, "schedule_date", "Use a finite instant.")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let parts = calendar.dateComponents([.era, .year], from: date)
    try require(
      parts.era == 1 && (1...9998).contains(parts.year ?? 0), "schedule_date",
      "Use Gregorian years 1 through 9998.")
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
  static func date(_ text: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: text), try Self.text(date) == text else {
      throw SevraError("automation_time", "Invalid retained UTC millisecond instant.")
    }
    return date
  }
}

extension Workbook {
  /// A new explicit foreground planning decision. Opening or reconstructing a
  /// workbook never calls this. Expected generation is zero for the first decision.
  public func authorizeAutomationPlanning(
    _ exactID: String, expectedGeneration: Int, after: Date, token: String,
    actor: ChangeActor? = nil, cancellation: Cancellation = .init()
  ) throws -> AutomationPlanningSession {
    try authorizeAutomation(
      exactID, expectedGeneration: expectedGeneration, after: after, policy: "calendar-prepare-v1",
      allowAI: false, token: token, actor: actor, cancellation: cancellation)
  }

  func authorizeAutomation(
    _ exactID: String, expectedGeneration: Int, after: Date, policy: String, allowAI: Bool,
    token: String, actor: ChangeActor?, cancellation: Cancellation
  ) throws -> AutomationPlanningSession {
    try workflowToken(token)
    let instant = try AutomationTime.text(after)
    let actor = actor ?? .programmatic("SevraCore.automation-authorization")
    let result = try mutation(
      "automation_authorize", token: token,
      request: .object([
        "definitionID": .string(exactID), "expectedGeneration": .number(Double(expectedGeneration)),
        "after": .string(instant), "policy": .string(policy), "allowAI": .bool(allowAI),
      ]), cancellation: cancellation, actor: actor
    ) {
      let saved = try self.applicationDefinition(exactID)
      try require(
        saved.id == exactID && saved.kind == "automation", "automation_binding",
        "Authorize an exact saved automation version.")
      try require(
        try DefinitionAutomation(DefinitionDescriptor(saved.content)).condition == nil,
        "automation_trigger", "Use explicit inventory-condition authorization for this definition.")
      let retained = try self.validateAutomationDefinition(DefinitionDescriptor(saved.content))
      if policy == "foreground-drafts-v1" {
        let workflow = try DefinitionWorkflow(DefinitionDescriptor(retained.workflow.content))
        try require(
          allowAI || !workflow.steps.contains { $0.kind == "interpret" },
          "automation_ai_scope", "Explicit local-AI permission is required for this exact workflow."
        )
      }
      let previous =
        try self.db.execute(
          "SELECT * FROM automation_activations WHERE logical_id=?", [.string(saved.logicalID)]
        ).first.map(Value.object) ?? .null
      let generation = previous["generation"].int ?? 0
      try require(
        generation == expectedGeneration && generation < 1_000_000_000, "stale_automation",
        "Refresh the exact automation generation before authorizing.")
      let id = previous["id"].string ?? identifier()
      let cursor = max(previous["cursor"].string ?? instant, instant)
      let active: Value
      if let runID = previous["active_run_id"].string {
        let run = try self.workflowRun(runID)
        active = ["completed", "cancelled"].contains(run["state"].text) ? .null : run
      } else {
        active = .null
      }
      try require(
        active == .null || previous["definition_id"] == .string(exactID),
        "automation_busy",
        "Finish or explicitly stop the active run before changing this automation version.")
      let released = try self.revokeAutomationClaim(active, sourceID: previous["source_id"].text)
      let pending = try self.pendingAutomationOccurrence(id)
      let decisions =
        pending == .null ? [] : [self.automationDecision(pending, "authorization_changed")]
      let inputs = [
        saved.sourceID, previous["source_id"].string, previous["coverage_source"].string,
        pending["source_id"].string, active["source_id"].string,
      ]
      .compactMap { $0 }
      let source = try self.insertItem(
        category: "source", kind: "automation_authorization",
        title: (policy == "foreground-drafts-v1" ? "Authorize " : "Prepare ") + saved.title,
        text: actor.label
          + (policy == "foreground-drafts-v1"
            ? " authorized exact foreground draft workflows. Business changes require separate review."
            : " authorized foreground calendar preparation only. Workflow execution is not enabled."),
        data: .object([
          "activationID": .string(id), "logicalID": .string(saved.logicalID),
          "definitionID": .string(exactID), "generation": .number(Double(generation + 1)),
          "state": .string("armed"), "policy": .string(policy), "allowAI": .bool(allowAI),
          "resumedRunID": active["id"], "releasedAttempts": .array(released),
          "actor": try encoded(actor), "startAfter": .string(instant), "cursor": .string(cursor),
          "previousSourceID": previous["source_id"],
          "previousCoverageSourceID": previous["coverage_source"], "through": .string(cursor),
          "decisions": .array(decisions),
        ]), meaning: "actual", status: "accepted", scenario: "actual",
        inputs: [], transformation: "automation-authorization-v1",
        controlInputs: Array(Set(inputs)).sorted())
      if previous == .null {
        try self.db.execute(
          "INSERT INTO automation_activations(id,logical_id,definition_id,source_id,actor,generation,state,policy,cursor,observed_through,catch_up_remaining,coverage_source,created,updated) VALUES(?,?,?,?,?,?,'armed',?,?,?,0,?,?,?)",
          [
            .string(id), .string(saved.logicalID), .string(exactID), .string(source),
            .string(try encoded(actor).json()), .number(Double(generation + 1)), .string(policy),
            .string(cursor),
            .string(cursor), .string(source),
            .string(timestamp()), .string(timestamp()),
          ])
      } else {
        try self.db.execute(
          "UPDATE automation_activations SET definition_id=?,source_id=?,actor=?,generation=?,state='armed',policy=?,cursor=?,observed_through=?,catch_up_remaining=0,coverage_source=?,updated=?,consumer_id=NULL WHERE id=?",
          [
            .string(exactID), .string(source), .string(try encoded(actor).json()),
            .number(Double(generation + 1)), .string(policy), .string(cursor), .string(cursor),
            .string(source),
            .string(timestamp()),
            .string(id),
          ])
      }
      try self.applyAutomationDecisions(decisions, source: source)
      try self.automationEvent(
        id, generation: generation + 1, kind: "authorized", source: source,
        scope: policy == "foreground-drafts-v1" ? "foreground-drafts" : "preparation-only")
      return try self.automationActivation(id)
    }
    // An old operation receipt is history, not permission to revive a paused or
    // reauthorized generation. Check again before issuing this process capability.
    return try synchronized {
      let current = try automationActivation(result["id"].text)
      try require(
        current["state"] == .string("armed") && current["generation"] == result["generation"]
          && current["source_id"] == result["source_id"],
        "stale_automation", "This authorization receipt has been superseded.")
      return AutomationPlanningSession(self, activation: current)
    }
  }

  public func pauseAutomation(
    _ activationID: String, expectedGeneration: Int, token: String,
    actor: ChangeActor? = nil, cancellation: Cancellation = .init()
  ) throws -> Value {
    try workflowToken(token)
    let actor = actor ?? .programmatic("SevraCore.automation-pause")
    let result = try mutation(
      "automation_pause", token: token,
      request: .object([
        "id": .string(activationID), "generation": .number(Double(expectedGeneration)),
      ]),
      cancellation: cancellation, actor: actor
    ) {
      let previous = try self.automationActivation(activationID)
      try require(
        previous["generation"].int == expectedGeneration && expectedGeneration < 1_000_000_000,
        "stale_automation", "Refresh the exact automation generation before pausing.")
      let active = try previous["active_run_id"].string.map { try self.workflowRun($0) } ?? .null
      let released = try self.revokeAutomationClaim(active, sourceID: previous["source_id"].text)
      let pending = try self.pendingAutomationOccurrence(activationID)
      let decisions = pending == .null ? [] : [self.automationDecision(pending, "paused")]
      let source = try self.insertItem(
        category: "source", kind: "automation_authorization", title: "Pause automation",
        text: actor.label
          + " paused this automation and revoked its prior sessions. Independent manual work is preserved.",
        data: .object([
          "activationID": .string(activationID), "logicalID": previous["logical_id"],
          "definitionID": previous["definition_id"],
          "generation": .number(Double(expectedGeneration + 1)),
          "state": .string("paused"), "releasedAttempts": .array(released),
          "policy": previous["policy"], "consumerID": previous["consumer_id"],
          "allowAI": try self.item(previous["source_id"].text).data["allowAI"],
          "actor": try encoded(actor),
          "cursor": previous["cursor"], "through": previous["observed_through"],
          "previousCoverageSourceID": previous["coverage_source"],
          "previousSourceID": previous["source_id"],
          "decisions": .array(decisions),
        ]), meaning: "actual", status: "accepted", scenario: "actual",
        inputs: [], transformation: "automation-authorization-v1",
        controlInputs: Array(
          Set(
            [previous["source_id"].text, previous["coverage_source"].text]
              + (pending["source_id"].string.map { [$0] } ?? []))
        ).sorted())
      try self.db.execute(
        "UPDATE automation_activations SET source_id=?,actor=?,generation=?,state='paused',coverage_source=?,updated=? WHERE id=?",
        [
          .string(source), .string(try encoded(actor).json()),
          .number(Double(expectedGeneration + 1)), .string(source),
          .string(timestamp()), .string(activationID),
        ])
      try self.applyAutomationDecisions(decisions, source: source)
      try self.automationEvent(
        activationID, generation: expectedGeneration + 1, kind: "paused", source: source,
        scope: [.string("foreground-drafts-v1"), .string("condition-drafts-v1")].contains(
          previous["policy"])
          ? "foreground-drafts" : "preparation-only")
      return try self.automationActivation(activationID)
    }
    let current = try automationActivation(activationID)
    try require(
      current["state"] == .string("paused") && current["generation"] == result["generation"]
        && current["source_id"] == result["source_id"],
      "stale_automation", "This pause receipt has been superseded.")
    return result
  }

  public func automationActivation(_ id: String) throws -> Value {
    try synchronized {
      guard
        var row = try db.execute(
          "SELECT * FROM automation_activations WHERE id=?",
          [.string(id)]
        ).first
      else { throw SevraError("automation_not_found", "The activation was not found.") }
      row["actor"] = try Value.parse(row["actor"]!.text)
      row["execution"] = .string(
        [.string("foreground-drafts-v1"), .string("condition-drafts-v1")].contains(row["policy"]!)
          ? "session-required" : "preparation-only")
      row["allowAI"] = try item(row["source_id"]!.text).data["allowAI"]
      row["sessionRequired"] = .bool(true)
      return .object(row)
    }
  }

  func automationSession(_ session: AutomationPlanningSession) throws -> Value {
    try require(
      session.workbook === self, "automation_authority", "Authorize this open workbook explicitly.")
    let current = try automationActivation(session.activationID)
    try require(
      current["generation"].int == session.generation
        && current["source_id"].text == session.sourceID
        && current["state"] == .string("armed"), "automation_authority",
      "This planning session was revoked.")
    return current
  }

  /// Only claims under the superseded automation grant are released. A separately
  /// requested manual operation has a different Source and keeps its own lease.
  func revokeAutomationClaim(_ run: Value, sourceID: String) throws -> [Value] {
    guard let runID = run["id"].string else { return [] }
    let claims = try db.execute(
      "SELECT id,step_id FROM workflow_attempts WHERE run_id=? AND state='claimed' AND authorization_source=?",
      [.string(runID), .string(sourceID)])
    for claim in claims {
      try db.execute(
        "UPDATE workflow_attempts SET state='expired',updated=? WHERE id=?",
        [.string(timestamp()), claim["id"]!])
      try db.execute(
        "UPDATE workflow_steps SET state='pending',updated=? WHERE run_id=? AND step_id=? AND state='claimed'",
        [.string(timestamp()), .string(runID), claim["step_id"]!])
    }
    if !claims.isEmpty {
      try db.execute(
        "UPDATE workflow_runs SET state='queued',detail='Automation permission changed; completed work is preserved.',updated=? WHERE id=? AND state='running'",
        [.string(timestamp()), .string(runID)])
    }
    return claims.map { $0["id"]! }
  }

  func pendingAutomationOccurrence(_ id: String) throws -> Value {
    guard
      var row = try db.execute(
        "SELECT * FROM automation_occurrences WHERE activation_id=? AND state='pending' LIMIT 1",
        [.string(id)]
      ).first
    else { return .null }
    row["slot"] = try Value.parse(row["slot"]!.text)
    return .object(row)
  }
  func automationDecision(_ occurrence: Value, _ reason: String) -> Value {
    .object(["id": occurrence["id"], "state": .string("skipped"), "detail": .string(reason)])
  }
  func applyAutomationDecisions(_ decisions: [Value], source: String) throws {
    for decision in decisions {
      try db.execute(
        "UPDATE automation_occurrences SET state=?,detail=?,decision_source=?,updated=? WHERE id=?",
        [
          decision["state"], decision["detail"], .string(source), .string(timestamp()),
          decision["id"],
        ])
    }
  }
  func automationEvent(
    _ id: String, generation: Int, kind: String, source: String, scope: String = "preparation-only"
  ) throws {
    try db.execute(
      "INSERT INTO automation_outbox(event_id,activation_id,generation,kind,source_id,payload,created) VALUES(?,?,?,?,?,?,?)",
      [
        .string(identifier()), .string(id), .number(Double(generation)), .string(kind),
        .string(source),
        .string(try Value.object(["scope": .string(scope)]).json()),
        .string(timestamp()),
      ])
  }
}
