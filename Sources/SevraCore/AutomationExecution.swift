import Foundation

/// Explicit authority for exact foreground draft workflows. No saved row or
/// imported Source can instantiate it. Business acceptance remains separate.
public final class AutomationExecutionSession: @unchecked Sendable {
  public let planning: AutomationPlanningSession
  public let allowAI: Bool
  let deviceFence: (@Sendable () throws -> Void)?
  init(
    _ planning: AutomationPlanningSession, allowAI: Bool,
    deviceFence: (@Sendable () throws -> Void)? = nil
  ) {
    self.planning = planning
    self.allowAI = allowAI
    self.deviceFence = deviceFence
  }
}

extension Workbook {
  package func deviceAutomationPending(_ session: AutomationExecutionSession) throws -> Value {
    try synchronized {
      _ = try automationExecutionSession(session)
      return try pendingAutomationOccurrence(session.planning.activationID)
    }
  }

  package func deviceAutomationScope(_ session: AutomationExecutionSession) throws -> Value {
    try synchronized { try automationExecutionSession(session) }
  }
  /// Trusted native owner only. The owner verifies its private, physical-file
  /// registration before calling; saved workbook state alone never invokes this.
  package func restoreDeviceAutomationExecution(
    activationID: String, definitionID: String, generation: Int, sourceID: String,
    allowAI: Bool, fence: @escaping @Sendable () throws -> Void
  ) throws -> AutomationExecutionSession {
    try synchronized {
      try fence()
      let current = try automationActivation(activationID)
      try require(
        current["definition_id"] == .string(definitionID)
          && current["generation"].int == generation
          && current["source_id"] == .string(sourceID)
          && current["state"] == .string("armed"),
        "automation_authority", "This device registration was superseded. Enable the scope again.")
      let session = AutomationExecutionSession(
        AutomationPlanningSession(self, activation: current), allowAI: allowAI, deviceFence: fence)
      _ = try automationExecutionSession(session)
      return session
    }
  }

  public func authorizeAutomationExecution(
    _ exactID: String, expectedGeneration: Int, after: Date, allowAI: Bool = false,
    token: String, actor: ChangeActor? = nil, cancellation: Cancellation = .init()
  ) throws -> AutomationExecutionSession {
    let planning = try authorizeAutomation(
      exactID, expectedGeneration: expectedGeneration, after: after, policy: "foreground-drafts-v1",
      allowAI: allowAI, token: token, actor: actor, cancellation: cancellation)
    let session = AutomationExecutionSession(planning, allowAI: allowAI)
    _ = try synchronized { try automationExecutionSession(session) }
    return session
  }

  func automationExecutionSession(_ session: AutomationExecutionSession) throws -> Value {
    try session.deviceFence?()
    let activation = try automationSession(session.planning)
    try require(
      activation["policy"] == .string("foreground-drafts-v1")
        && activation["allowAI"] == .bool(session.allowAI),
      "automation_authority", "Explicitly authorize the exact foreground execution scope.")
    return activation
  }

  public func authorizeAutomationWorkflowExecution(
    _ session: AutomationExecutionSession, runID: String
  ) throws -> WorkflowExecutionSession {
    try synchronized {
      try db.readTransaction {
        try validateAutomationWorkflow(session, runID: runID)
        return WorkflowExecutionSession(self, runID: runID, automation: session)
      }
    }
  }

  func validateAutomationWorkflow(_ session: AutomationExecutionSession, runID: String) throws {
    let activation = try automationExecutionSession(session)
    let binding = try automationRunBinding(runID)
    let source = try item(session.planning.sourceID)
    try require(
      binding["activation_id"] == activation["id"] && activation["active_run_id"] == .string(runID)
        && binding["definition_id"] == activation["definition_id"]
        && (binding["authorization_source"] == .string(session.planning.sourceID)
          || source.data["resumedRunID"] == .string(runID)),
      "automation_authority", "This grant does not cover the exact scheduled workflow run.")
  }

  func automationRunBinding(_ runID: String) throws -> Value {
    guard
      let row = try db.execute(
        "SELECT * FROM automation_runs WHERE run_id=?", [.string(runID)]
      ).first
    else { throw SevraError("automation_run", "The scheduled run binding was not found.") }
    return .object(row)
  }

  /// Atomically publish at most one run. The caller must finish bounded catch-up
  /// first. No model, timer, business acceptance or external effect runs here.
  public func dispatchAutomationOccurrence(
    _ session: AutomationExecutionSession, observedAt: Date = Date(), token: String,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try dispatchAutomaticCalendarRun(
      session, observedAt: observedAt, token: token, cancellation: cancellation)
  }

  /// Shared trusted admission path. Production calendar callers leave inherited
  /// parents nil. Business-trigger selection is not exposed by this primitive.
  func dispatchAutomaticCalendarRun(
    _ session: AutomationExecutionSession, observedAt: Date, token: String,
    cancellation: Cancellation = .init(), inheriting parentRuns: [String]? = nil,
    independentInputs: [String] = []
  ) throws -> Value {
    try workflowToken(token)
    let instant = try AutomationTime.text(observedAt)
    let observation = try AutomationTime.date(instant)
    let authority = session.planning
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    let fence: () throws -> Void = {
      try control.check()
      _ = try self.automationExecutionSession(session)
      try control.check()
    }
    let result = try mutation(
      "automation_dispatch", token: token,
      request: .object([
        "activationID": .string(authority.activationID),
        "generation": .number(Double(authority.generation)),
        "authorizationSourceID": .string(authority.sourceID), "observedAt": .string(instant),
        "inheritedParents": parentRuns.map { .array($0.map(Value.string)) } ?? .null,
        "independentInputs": .array(independentInputs.map(Value.string)),
      ]), cancellation: control, actor: .programmatic("SevraCore.automationDispatcher"),
      commitGuard: fence
    ) {
      let activation = try self.automationExecutionSession(session)
      try require(
        activation["catch_up_remaining"].int == 0, "automation_catch_up",
        "Complete bounded catch-up before dispatching a stale intermediate request.")
      if let runID = activation["active_run_id"].string {
        let run = try self.workflowRun(runID)
        if !["completed", "cancelled"].contains(run["state"].text) {
          return .object([
            "status": .string("active"), "run": run, "execution": .string("foreground-drafts"),
          ])
        }
      }
      let pending = try self.pendingAutomationOccurrence(authority.activationID)
      if pending == .null {
        return .object(["status": .string("idle"), "execution": .string("none")])
      }
      try require(
        pending["generation"].int == authority.generation
          && pending["definition_id"] == activation["definition_id"],
        "stale_automation", "The pending slot belongs to a different automation authorization.")
      let due = try AutomationTime.date(pending["due"].text)
      if due > observation {
        return .object([
          "status": .string("future"), "occurrenceID": pending["id"], "due": pending["due"],
          "execution": .string("none"),
        ])
      }
      let late = observation.timeIntervalSince(due) > 86_400
      let runID = late ? nil : identifier()
      let decision: Value = .object([
        "id": pending["id"], "state": .string(late ? "skipped" : "dispatched"),
        "detail": .string(late ? "late" : "workflow_queued"),
      ])
      let source = try self.insertItem(
        category: "source", kind: "automation_dispatch",
        title: late ? "Skip late scheduled request" : "Dispatch scheduled workflow",
        text: late
          ? "The pending calendar request exceeded its lateness bound; no run was started."
          : "The dispatcher queued an exact authorized foreground draft workflow. Business changes still require review.",
        data: .object([
          "activationID": activation["id"], "definitionID": activation["definition_id"],
          "generation": .number(Double(authority.generation)),
          "authorizationSourceID": .string(authority.sourceID),
          "occurrenceID": pending["id"], "runID": runID.map(Value.string) ?? .null,
          "observedAt": .string(instant), "policy": .string("foreground-drafts-v1"),
          "decisions": .array([decision]),
        ]), meaning: "actual", status: "accepted", scenario: "actual",
        inputs: [], transformation: "automation-dispatch-v1",
        controlInputs: [authority.sourceID, pending["source_id"].text].sorted())
      try self.applyAutomationDecisions([decision], source: source)
      if let runID {
        let automation = try self.applicationDefinition(activation["definition_id"].text)
        let retained = try self.validateAutomationDefinition(
          DefinitionDescriptor(automation.content))
        let causal = try self.planAutomationCausality(
          definitionID: automation.id,
          calendarOccurrence: parentRuns == nil && independentInputs.isEmpty
            ? pending["id"].text : nil,
          parents: parentRuns ?? [], independentInputs: independentInputs)
        let origin: Value = .object([
          "activationID": activation["id"], "automationID": activation["definition_id"],
          "occurrenceID": pending["id"], "generation": .number(Double(authority.generation)),
          "authorizationSourceID": .string(authority.sourceID), "dispatchSourceID": .string(source),
          "due": pending["due"],
          "causality": causal.context,
        ])
        _ = try self.insertWorkflowRun(
          retained.workflow.id, arguments: retained.arguments,
          actor: .programmatic("SevraCore.automationDispatcher"),
          additionalInputs: causal.independentInputs,
          origin: origin,
          policy: "automation-drafts-v1", runID: runID,
          controlInputs: [authority.sourceID, pending["source_id"].text, source],
          producerInputs: try causal.parents.map {
            try self.db.scalar("SELECT source_id FROM workflow_runs WHERE id=?", [.string($0)]).text
          })
        try self.db.execute(
          "INSERT INTO automation_runs VALUES(?,?,?,?,?,?,?,?)",
          [
            pending["id"], activation["id"], .string(runID), activation["definition_id"],
            .string(authority.sourceID), .string(source), .number(Double(authority.generation)),
            .string(timestamp()),
          ])
        try self.retainAutomationCausality(causal, runID: runID, sourceID: source)
        try self.db.execute(
          "UPDATE automation_activations SET active_run_id=?,updated=? WHERE id=?",
          [.string(runID), .string(timestamp()), activation["id"]])
      }
      try self.automationEvent(
        authority.activationID, generation: authority.generation,
        kind: late ? "dispatch_skipped" : "dispatched", source: source, scope: "foreground-drafts")
      AutomationPublicationProbe.observer?(.prepared, authority.activationID)
      return .object([
        "status": .string(late ? "late" : "queued"), "occurrenceID": pending["id"],
        "runID": runID.map(Value.string) ?? .null, "sourceID": .string(source),
        "execution": .string(late ? "none" : "foreground-drafts"),
      ])
    }
    AutomationPublicationProbe.observer?(.committed, authority.activationID)
    return result
  }
}

/// Fixture-only publication barriers; no product or workbook path installs one.
package enum AutomationPublicationProbe {
  package enum Stage { case prepared, committed }
  @TaskLocal package static var observer: (@Sendable (Stage, String) -> Void)?
}
