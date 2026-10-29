import Foundation

extension Workbook {
  func verifyAutomationOverlap(_ activation: Value) throws {
    if let id = activation["active_run_id"].string {
      let binding = try automationRunBinding(id)
      try require(
        binding["activation_id"] == activation["id"], "automation_integrity",
        "The active run belongs to a different automation.")
    }
    let active = try db.execute(
      "SELECT a.run_id FROM automation_runs a JOIN workflow_runs r ON r.id=a.run_id WHERE a.activation_id=? AND r.state NOT IN ('completed','cancelled') LIMIT 2",
      [activation["id"]])
    try require(
      active.count <= 1 && (active.isEmpty || active[0]["run_id"] == activation["active_run_id"]),
      "automation_integrity", "A live automation run lost its overlap reservation.")
  }

  func verifyAutomationDispatchDecision(_ occurrence: Value, source: Item) throws {
    let authority = try item(source.data["authorizationSourceID"].text)
    let age = try AutomationTime.date(source.data["observedAt"].text).timeIntervalSince(
      AutomationTime.date(occurrence["due"].text))
    try require(
      source.meaning == "actual" && source.status == "accepted"
        && source.data["policy"] == .string("foreground-drafts-v1")
        && source.data["definitionID"] == occurrence["definition_id"]
        && source.data["generation"] == occurrence["generation"]
        && source.data["occurrenceID"] == occurrence["id"]
        && authority.kind == "automation_authorization" && authority.category == "source"
        && authority.status == "accepted"
        && authority.data["state"] == .string("armed")
        && authority.data["policy"] == .string("foreground-drafts-v1")
        && authority.data["activationID"] == occurrence["activation_id"]
        && authority.data["definitionID"] == occurrence["definition_id"]
        && authority.data["generation"] == occurrence["generation"]
        && (occurrence["state"] == .string("dispatched")
          ? (0...86_400).contains(age) && source.data["runID"].string != nil
          : age > 86_400 && occurrence["detail"] == .string("late")
            && source.data["runID"] == .null),
      "automation_integrity", "A dispatch decision lost its exact authority or lateness evidence.")
    try automationLineage(source.id, authority.id)
  }

  func verifyAutomationRuns() throws {
    try require(
      try db.scalar(
        "SELECT EXISTS(SELECT 1 FROM workflow_runs r LEFT JOIN automation_runs a ON a.run_id=r.id WHERE (r.policy='automation-drafts-v1' AND a.run_id IS NULL) OR (r.policy!='automation-drafts-v1' AND a.run_id IS NOT NULL))"
      ).int == 0, "automation_integrity", "A scheduled workflow lost its dispatch binding.")
    try require(
      try db.scalar(
        "SELECT EXISTS(SELECT 1 FROM automation_occurrences o LEFT JOIN automation_runs a ON a.occurrence_id=o.id WHERE (o.state='dispatched' AND a.occurrence_id IS NULL) OR (o.state!='dispatched' AND a.occurrence_id IS NOT NULL))"
      ).int == 0, "automation_integrity", "A dispatched occurrence lost its exact run.")
    var after = ""
    while true {
      let rows = try db.execute(
        "SELECT * FROM automation_runs WHERE run_id>? ORDER BY run_id LIMIT 100", [.string(after)])
      if rows.isEmpty { break }
      for row in rows {
        let binding = Value.object(row)
        let run = try workflowRun(binding["run_id"].text)
        let invocation = try item(run["source_id"].text)
        let dispatch = try item(binding["dispatch_source"].text)
        let authority = try item(binding["authorization_source"].text)
        let saved = try applicationDefinition(binding["definition_id"].text)
        let retained = try validateAutomationDefinition(DefinitionDescriptor(saved.content))
        let descriptor = try DefinitionDescriptor(retained.workflow.content)
        let normalized = Value.object(try definitionArguments(descriptor, retained.arguments))
        let occurrence =
          try db.execute(
            "SELECT * FROM automation_occurrences WHERE id=?", [binding["occurrence_id"]]
          ).first.map(Value.object) ?? .null
        let origin: Value = .object([
          "activationID": binding["activation_id"], "automationID": binding["definition_id"],
          "occurrenceID": binding["occurrence_id"], "generation": binding["generation"],
          "authorizationSourceID": binding["authorization_source"],
          "dispatchSourceID": binding["dispatch_source"], "due": occurrence["due"],
          "causality": try automationCausalGraph([run["id"].text])[run["id"].text]!.context,
        ])
        let decision: Value = .object([
          "id": occurrence["id"], "state": .string("dispatched"),
          "detail": .string("workflow_queued"),
        ])
        try require(
          run["policy"] == .string("automation-drafts-v1")
            && run["definition_id"] == .string(retained.workflow.id)
            && run["arguments"] == normalized && invocation.data["origin"] == origin
            && run["actor"] == encoded(ChangeActor.programmatic("SevraCore.automationDispatcher"))
            && occurrence["activation_id"] == binding["activation_id"]
            && occurrence["generation"] == binding["generation"]
            && occurrence["definition_id"] == binding["definition_id"]
            && occurrence["state"] == .string("dispatched")
            && occurrence["decision_source"] == binding["dispatch_source"]
            && authority.kind == "automation_authorization" && authority.category == "source"
            && authority.status == "accepted"
            && authority.data["state"] == .string("armed")
            && authority.data["policy"] == .string("foreground-drafts-v1")
            && authority.data["activationID"] == binding["activation_id"]
            && authority.data["definitionID"] == binding["definition_id"]
            && authority.data["generation"] == binding["generation"]
            && dispatch.kind == "automation_dispatch" && dispatch.category == "source"
            && dispatch.status == "accepted"
            && dispatch.data["activationID"] == binding["activation_id"]
            && dispatch.data["definitionID"] == binding["definition_id"]
            && dispatch.data["generation"] == binding["generation"]
            && dispatch.data["authorizationSourceID"] == binding["authorization_source"]
            && dispatch.data["occurrenceID"] == occurrence["id"]
            && dispatch.data["runID"] == run["id"]
            && dispatch.data["policy"] == .string("foreground-drafts-v1")
            && dispatch.data["decisions"] == .array([decision]),
          "automation_integrity",
          "The scheduled run disagrees with its exact occurrence, authorization or dispatch Source."
        )
        let observed = try AutomationTime.date(dispatch.data["observedAt"].text)
        let due = try AutomationTime.date(occurrence["due"].text)
        try require(
          (0...86_400).contains(observed.timeIntervalSince(due)), "automation_integrity",
          "A run was dispatched outside its calendar eligibility window.")
        let workflow = try DefinitionWorkflow(descriptor)
        try require(
          authority.data["allowAI"] == .bool(true)
            || !workflow.steps.contains { $0.kind == "interpret" }, "automation_integrity",
          "The scheduled workflow lost its AI permission.")
        for parent in [authority.id, occurrence["source_id"].text, dispatch.id] {
          try automationLineage(invocation.id, parent)
        }
        try automationLineage(dispatch.id, authority.id)
        try automationLineage(dispatch.id, occurrence["source_id"].text)
        after = run["id"].text
      }
    }
    try verifyAutomationCausality()
  }

  func verifyWorkflowAttemptAuthorities(_ run: Value) throws {
    var after = ""
    while true {
      let rows = try db.execute(
        "SELECT * FROM workflow_attempts WHERE run_id=? AND id>? ORDER BY id LIMIT 100",
        [run["id"], .string(after)])
      if rows.isEmpty { break }
      for row in rows {
        let source = try item(row["authorization_source"]!.text)
        let valid: Bool
        if run["policy"] == .string("manual-drafts-v1") {
          valid = row["authorization_source"] == run["source_id"]
        } else if source.kind == "workflow_authorization" {
          valid =
            source.data["runID"] == run["id"]
            && source.data["policy"] == .string("manual-operation-v1")
          try automationLineage(source.id, run["source_id"].text)
        } else {
          let binding = try automationRunBinding(run["id"].text)
          valid =
            source.kind == "automation_authorization"
            && source.data["activationID"] == binding["activation_id"]
            && source.data["definitionID"] == binding["definition_id"]
            && source.data["state"] == .string("armed")
            && source.data["policy"] == .string("foreground-drafts-v1")
            && source.data["generation"].int! >= binding["generation"].int!
            && (source.id == binding["authorization_source"].text
              || source.data["resumedRunID"] == run["id"])
          if try db.scalar(
            "SELECT kind FROM workflow_steps WHERE run_id=? AND step_id=?",
            [run["id"], row["step_id"]!]) == .string("interpret")
          {
            try require(
              source.data["allowAI"] == .bool(true), "workflow_integrity",
              "An AI attempt lost its explicit local-model permission.")
          }
        }
        try require(
          valid && source.category == "source" && source.status == "accepted"
            && source.meaning == "actual", "workflow_integrity",
          "A worker claim lost its exact execution authorization Source.")
        after = row["id"]!.text
      }
    }
  }
}
