import Foundation

extension Workbook {
  /// Selects real retained candidates and derives all causes inside the captured
  /// writer. Callers cannot provide a candidate, parents, roots or input overrides.
  public func dispatchInventoryCondition(
    _ session: AutomationExecutionSession, observedAt: Date = Date(), token: String,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try workflowToken(token)
    let instant = try AutomationTime.text(observedAt)
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    let authority = session.planning
    var prepared = false
    let fence: () throws -> Void = {
      if prepared { AutomationPublicationProbe.observer?(.prepared, authority.activationID) }
      try control.check()
      _ = try self.conditionExecutionScope(session)
      try control.check()
    }
    let result = try mutation(
      "condition_dispatch", token: token,
      request: .object([
        "activationID": .string(authority.activationID),
        "generation": .number(Double(authority.generation)),
        "authorizationSourceID": .string(authority.sourceID), "observedAt": .string(instant),
      ]), cancellation: control, actor: .programmatic("SevraCore.automationDispatcher"),
      commitGuard: fence
    ) {
      let activation = try self.conditionExecutionScope(session)
      if let id = activation["active_run_id"].string {
        let run = try self.workflowRun(id)
        if !["completed", "cancelled"].contains(run["state"].text) {
          return .object([
            "status": .string("active"), "run": run, "execution": .string("foreground-drafts"),
          ])
        }
      }
      guard
        let candidate = try self.db.execute(
          "SELECT c.* FROM condition_candidates c JOIN condition_observations o ON o.id=c.observation_id WHERE c.consumer_id=? AND c.state='pending' ORDER BY o.rowid LIMIT 1",
          [activation["consumer_id"]], maxRows: 1, maxBytes: 16_384
        ).first
      else {
        return .object(["status": .string("idle"), "execution": .string("none")])
      }
      let observation = try self.validateDispatchCandidate(candidate)
      if observation["effectiveThrough"].text > (try BusinessTime.normalized(instant)) {
        return .object([
          "status": .string("future"), "candidateID": candidate["id"]!,
          "effectiveThrough": observation["effectiveThrough"], "execution": .string("none"),
        ])
      }
      let causes = try self.inspectInventoryConditionCauses(
        candidate["observation_id"]!.text, cancellation: control)
      try require(
        causes["resolution"] == .string("resolved"), "condition_cause_blocked",
        "The earliest queued transition has incomplete business causes. Inspect or explicitly dismiss it before continuing."
      )
      let automation = try self.applicationDefinition(activation["definition_id"].text)
      let retained = try self.validateAutomationDefinition(DefinitionDescriptor(automation.content))
      let causal = try self.planAutomationCausality(
        definitionID: automation.id, parents: causes["automaticParentRunIDs"].array.map(\.text),
        independentInputs: causes["declaredInputs"].array.map { $0["sourceID"].text })
      try require(
        causal.roots == causes["rootIDs"].array.map(\.text), "causal_stale",
        "The retained transition causes changed before admission.")
      let readCommit = try self.db.scalar(
        "SELECT id FROM committed_changes ORDER BY rowid DESC LIMIT 1")
      let runID = identifier()
      let trigger: Value = .object([
        "consumerID": activation["consumer_id"], "candidateID": candidate["id"]!,
        "observationID": candidate["observation_id"]!,
        "knowledgeBatchID": observation["knowledgeBatchID"],
        "effectiveThrough": observation["effectiveThrough"], "quantity": observation["quantity"],
        "inputSetHash": causes["inputSetHash"], "workflowReadCommitID": readCommit,
      ])
      let source = try self.insertItem(
        category: "source", kind: "automation_dispatch",
        title: "Dispatch inventory-condition workflow",
        text:
          "The exact retained stock transition queued an authorized draft workflow. Its later steps read their own recorded inputs; business changes require review.",
        data: .object([
          "activationID": activation["id"], "definitionID": activation["definition_id"],
          "generation": .number(Double(authority.generation)),
          "authorizationSourceID": .string(authority.sourceID),
          "candidateID": candidate["id"]!, "runID": .string(runID), "observedAt": .string(instant),
          "policy": .string("condition-drafts-v1"), "trigger": trigger,
        ]), meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
        transformation: "condition-dispatch-v1",
        controlInputs: [
          authority.sourceID,
          try self.inventoryConditionRow(activation["consumer_id"].text)["source_id"]!.text,
        ])
      let origin: Value = .object([
        "activationID": activation["id"], "automationID": activation["definition_id"],
        "candidateID": candidate["id"]!, "generation": .number(Double(authority.generation)),
        "authorizationSourceID": .string(authority.sourceID), "dispatchSourceID": .string(source),
        "trigger": trigger, "causality": causal.context,
      ])
      _ = try self.insertWorkflowRun(
        retained.workflow.id, arguments: retained.arguments,
        actor: .programmatic("SevraCore.automationDispatcher"),
        additionalInputs: causal.independentInputs, origin: origin, policy: "automation-drafts-v1",
        runID: runID,
        controlInputs: [
          authority.sourceID, source,
          try self.inventoryConditionRow(activation["consumer_id"].text)["source_id"]!.text,
        ],
        producerInputs: try causal.parents.map {
          try self.db.scalar("SELECT source_id FROM workflow_runs WHERE id=?", [.string($0)]).text
        })
      try self.db.execute(
        "INSERT INTO automation_runs VALUES(NULL,?,?,?,?,?,?,?,?)",
        [
          activation["id"], .string(runID), activation["definition_id"],
          .string(authority.sourceID),
          .string(source), .number(Double(authority.generation)), .string(timestamp()),
          candidate["id"]!,
        ])
      try self.retainAutomationCausality(causal, runID: runID, sourceID: source)
      try self.db.execute(
        "UPDATE condition_candidates SET state='dispatched',detail='workflow_queued',decision_source=? WHERE id=?",
        [.string(source), candidate["id"]!])
      try self.db.execute(
        "UPDATE automation_activations SET active_run_id=?,updated=? WHERE id=?",
        [.string(runID), .string(timestamp()), activation["id"]])
      try self.automationEvent(
        authority.activationID, generation: authority.generation, kind: "dispatched",
        source: source, scope: "foreground-drafts")
      prepared = true
      return .object([
        "status": .string("queued"), "candidateID": candidate["id"]!, "runID": .string(runID),
        "sourceID": .string(source), "trigger": trigger, "execution": .string("foreground-drafts"),
      ])
    }
    AutomationPublicationProbe.observer?(.committed, authority.activationID)
    return result
  }

  func validateDispatchCandidate(_ candidate: [String: Value]) throws -> Value {
    let (row, observation) = try conditionInputObservation(candidate["observation_id"]!.text)
    let consumer = try inventoryConditionRow(candidate["consumer_id"]!.text)
    let rule = try NativeConditionRule(Value.parse(consumer["rule"]!.text))
    let identity: Value = .object(["rule": rule.definition, "observationID": row["id"]!])
    let previous = try conditionInputObservation(observation["previousCertainObservationID"].text).1
    try require(
      candidate["id"] == .string("condition:" + ChangeFormat.hash(try identity.json()))
        && candidate["consumer_id"] == row["consumer_id"]
        && observation["candidateID"] == candidate["id"]
        && observation["disposition"] == .string("transition")
        && row["disposition"] == .string("transition")
        && observation["rule"] == rule.definition && observation["truth"] == .bool(true)
        && observation["known"] == .bool(true) && rule.truth(observation["quantity"].text)
        && previous["consumerID"] == candidate["consumer_id"] && previous["truth"] == .bool(false),
      "condition_candidate", "The candidate lost its exact false-to-true observation and rule.")
    return observation
  }
}
