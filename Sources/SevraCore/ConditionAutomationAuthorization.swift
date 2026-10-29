import Foundation

extension Workbook {
  /// An explicit host decision, separate from saving a portable rule. Resume
  /// retains its queue; fromNow records why the previous queue is dismissed.
  public func authorizeInventoryConditionExecution(
    _ exactID: String, expectedGeneration: Int, after: Date, allowAI: Bool = false,
    fromNow: Bool = false, token: String, actor: ChangeActor? = nil,
    cancellation: Cancellation = .init()
  ) throws -> AutomationExecutionSession {
    try workflowToken(token)
    let instant = try AutomationTime.text(after)
    let through = try BusinessTime.normalized(instant)
    let actor = actor ?? .programmatic("SevraCore.condition-authorization")
    let result = try mutation(
      "condition_authorize", token: token,
      request: .object([
        "definitionID": .string(exactID), "expectedGeneration": .number(Double(expectedGeneration)),
        "after": .string(instant), "allowAI": .bool(allowAI), "fromNow": .bool(fromNow),
      ]), cancellation: cancellation, actor: actor
    ) {
      let saved = try self.applicationDefinition(exactID)
      try require(
        saved.id == exactID && saved.kind == "automation", "automation_binding",
        "Authorize an exact saved condition automation version.")
      let descriptor = try DefinitionDescriptor(saved.content)
      guard let condition = try DefinitionAutomation(descriptor).condition else {
        throw SevraError(
          "automation_trigger", "This definition uses a calendar, not an inventory condition.")
      }
      let target = try self.validateAutomationDefinition(descriptor).workflow
      let workflow = try DefinitionWorkflow(DefinitionDescriptor(target.content))
      try require(
        allowAI || !workflow.steps.contains { $0.kind == "interpret" },
        "automation_ai_scope", "Explicit local-AI permission is required for this exact workflow.")
      let previous = try self.automationState(exactID)
      let generation = previous["generation"].int ?? 0
      try require(
        generation == expectedGeneration && generation < 1_000_000_000,
        "stale_automation", "Refresh the exact automation generation before authorizing.")
      let active = try previous["active_run_id"].string.map { try self.workflowRun($0) } ?? .null
      let live = active != .null && !["completed", "cancelled"].contains(active["state"].text)
      let previousConsumer = try previous["consumer_id"].string.map {
        try self.inventoryConditionRow($0)
      }
      let previousRule = try previousConsumer.map { try Value.parse($0["rule"]!.text) }
      let sameScope =
        previousConsumer?["owner_logical"] == .string(saved.logicalID)
        && previousConsumer?["subject"] == .string(condition.subject)
        && previousRule == condition.rule
      try require(
        !live || (!fromNow && sameScope && previous["definition_id"] == .string(exactID)),
        "automation_busy",
        "Finish or explicitly stop the active run before changing its trigger or workflow.")
      let released = try self.revokeAutomationClaim(
        live ? active : .null, sourceID: previous["source_id"].text)
      let consumer: String
      if !fromNow && sameScope {
        consumer = previousConsumer!["id"]!.text
      } else {
        consumer = try self.insertInventoryCondition(
          subject: condition.subject, rule: condition.rule, through: through, owner: saved)
      }
      let pending =
        try previous["id"].string.map { try self.pendingAutomationOccurrence($0) } ?? .null
      let calendarDecisions =
        pending == .null ? [] : [self.automationDecision(pending, "authorization_changed")]
      let skipped: [[String: Value]]
      if fromNow, let old = previousConsumer {
        skipped = try self.db.execute(
          "SELECT id FROM condition_candidates WHERE consumer_id=? AND state='pending' LIMIT 101",
          [old["id"]!])
        try require(
          skipped.count <= 100, "condition_limit", "The retained condition queue exceeds its bound."
        )
      } else {
        skipped = []
      }
      let activationID = previous["id"].string ?? identifier()
      let cursor = max(previous["cursor"].string ?? instant, instant)
      let source = try self.insertItem(
        category: "source", kind: "automation_authorization", title: "Authorize " + saved.title,
        text: actor.label
          + " authorized this exact inventory-condition draft workflow on this connection. Business changes require separate review.",
        data: .object([
          "activationID": .string(activationID), "logicalID": .string(saved.logicalID),
          "definitionID": .string(exactID), "generation": .number(Double(generation + 1)),
          "state": .string("armed"), "policy": .string("condition-drafts-v1"),
          "allowAI": .bool(allowAI), "consumerID": .string(consumer), "fromNow": .bool(fromNow),
          "resumedRunID": live ? active["id"] : .null, "releasedAttempts": .array(released),
          "skippedCandidateIDs": .array(skipped.map { $0["id"]! }),
          "actor": try encoded(actor), "startAfter": .string(instant),
          "cursor": .string(cursor), "through": .string(cursor),
          "previousSourceID": previous["source_id"],
          "previousCoverageSourceID": previous["coverage_source"],
          "decisions": .array(calendarDecisions),
        ]), meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
        transformation: "condition-authorization-v1",
        controlInputs: Array(
          Set(
            [saved.sourceID, try self.inventoryConditionRow(consumer)["source_id"]!.text]
              + [
                previous["source_id"].string, previous["coverage_source"].string,
                pending["source_id"].string,
              ].compactMap { $0 })
        ).sorted())
      try self.applyAutomationDecisions(calendarDecisions, source: source)
      for row in skipped {
        try self.db.execute(
          "UPDATE condition_candidates SET state='dismissed',detail='explicit_from_now',decision_source=? WHERE id=?",
          [.string(source), row["id"]!])
      }
      if previous == .null {
        try self.db.execute(
          "INSERT INTO automation_activations(id,logical_id,definition_id,source_id,actor,generation,state,policy,cursor,observed_through,catch_up_remaining,coverage_source,created,updated,consumer_id) VALUES(?,?,?,?,?,?,'armed','condition-drafts-v1',?,?,0,?,?,?,?)",
          [
            .string(activationID), .string(saved.logicalID), .string(saved.id), .string(source),
            .string(try encoded(actor).json()), .number(Double(generation + 1)),
            .string(cursor), .string(cursor), .string(source), .string(timestamp()),
            .string(timestamp()), .string(consumer),
          ])
      } else {
        try self.db.execute(
          "UPDATE automation_activations SET definition_id=?,source_id=?,actor=?,generation=?,state='armed',policy='condition-drafts-v1',cursor=?,observed_through=?,catch_up_remaining=0,coverage_source=?,updated=?,consumer_id=?,active_run_id=? WHERE id=?",
          [
            .string(saved.id), .string(source), .string(try encoded(actor).json()),
            .number(Double(generation + 1)),
            .string(cursor), .string(cursor), .string(source), .string(timestamp()),
            .string(consumer),
            live ? active["id"] : .null, .string(activationID),
          ])
      }
      try self.automationEvent(
        activationID, generation: generation + 1, kind: "authorized", source: source,
        scope: "foreground-drafts")
      return try self.automationActivation(activationID)
    }
    return try synchronized {
      let current = try automationActivation(result["id"].text)
      try require(
        current["state"] == .string("armed") && current["generation"] == result["generation"]
          && current["source_id"] == result["source_id"], "stale_automation",
        "This authorization receipt has been superseded.")
      let session = AutomationExecutionSession(
        AutomationPlanningSession(self, activation: current), allowAI: allowAI)
      _ = try automationExecutionSession(session)
      return session
    }
  }

  /// One bounded observer page. It never dispatches or performs business work.
  public func stepAutomationCondition(
    _ session: AutomationExecutionSession, through: String, token: String,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    let activation = try synchronized { try conditionExecutionScope(session) }
    return try advanceInventoryCondition(
      activation["consumer_id"].text, through: through,
      token: token, cancellation: cancellation,
      fence: { _ = try self.conditionExecutionScope(session) })
  }

  func conditionExecutionScope(_ session: AutomationExecutionSession) throws -> Value {
    let activation = try automationExecutionSession(session)
    try require(
      activation["policy"] == .string("condition-drafts-v1")
        && activation["consumer_id"].string != nil,
      "automation_trigger", "Explicitly authorize this exact inventory-condition scope.")
    try verifyConditionActivation(activation)
    return activation
  }
}
