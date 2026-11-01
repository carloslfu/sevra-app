import Foundation

extension Workbook {
  func verifyAutomationPlanning() throws {
    var after = ""
    while true {
      let rows = try db.execute(
        "SELECT * FROM automation_activations WHERE id>? ORDER BY id LIMIT 100", [.string(after)])
      if rows.isEmpty { break }
      for row in rows {
        let activation = Value.object(row)
        let saved = try applicationDefinition(activation["definition_id"].text)
        let source = try item(activation["source_id"].text)
        let actor = try Value.parse(activation["actor"].text)
        try require(
          saved.kind == "automation" && saved.id == activation["definition_id"].text
            && saved.logicalID == activation["logical_id"].text
            && source.category == "source" && source.status == "accepted"
            && source.meaning == "actual" && source.kind == "automation_authorization"
            && source.data["activationID"] == activation["id"]
            && source.data["logicalID"] == activation["logical_id"]
            && source.data["definitionID"] == activation["definition_id"]
            && source.data["generation"] == activation["generation"]
            && source.data["state"] == activation["state"]
            && source.data["policy"] == activation["policy"]
            && source.data["consumerID"] == activation["consumer_id"]
            && source.data["actor"] == actor
            && [Value.bool(true), .bool(false)].contains(source.data["allowAI"])
            && (activation["policy"] != .string("calendar-prepare-v1")
              || source.data["allowAI"] == .bool(false))
            && source.data["cursor"].text <= activation["cursor"].text,
          "automation_integrity", "The activation disagrees with its exact authorization Source.")
        try JSONDecoder().decode(ChangeActor.self, from: Data(actor.json().utf8)).validate()
        _ = try AutomationTime.date(activation["cursor"].text)
        _ = try AutomationTime.date(activation["observed_through"].text)
        try require(
          activation["observed_through"].text >= activation["cursor"].text
            && activation["catch_up_remaining"].int
              == (activation["cursor"].text < activation["observed_through"].text ? 1 : 0),
          "automation_integrity", "The activation lost its observed catch-up high-water mark.")
        _ = try AutomationTime.date(source.data["cursor"].text)
        let coverage = try item(activation["coverage_source"].text)
        try require(
          coverage.category == "source"
            && ["automation_authorization", "automation_planning"].contains(coverage.kind)
            && coverage.data["activationID"] == activation["id"]
            && coverage.data["generation"] == activation["generation"]
            && coverage.data["cursor"] == activation["cursor"]
            && coverage.data["through"] == activation["observed_through"],
          "automation_integrity", "The cursor and catch-up target lost their exact coverage Source."
        )
        if let previous = coverage.data["previousCoverageSourceID"].string {
          try automationLineage(coverage.id, previous)
        }
        if let previous = source.data["previousSourceID"].string {
          try automationLineage(source.id, previous)
        }
        if source.data["state"] == .string("armed") {
          try automationLineage(source.id, saved.sourceID)
        }
        let invalidPending = try db.scalar(
          "SELECT EXISTS(SELECT 1 FROM automation_occurrences WHERE activation_id=? AND state='pending' AND (?!='armed' OR generation!=? OR definition_id!=?))",
          [
            activation["id"], activation["state"], activation["generation"],
            activation["definition_id"],
          ])
        try require(
          invalidPending.int == 0, "automation_integrity",
          "A revoked activation retains pending work.")
        try verifyConditionActivation(activation)
        try verifyAutomationOverlap(activation)
        after = activation["id"].text
      }
    }
    after = ""
    while true {
      let rows = try db.execute(
        "SELECT * FROM automation_occurrences WHERE id>? ORDER BY id LIMIT 100", [.string(after)])
      if rows.isEmpty { break }
      for row in rows {
        let occurrence = Value.object(row)
        let activation = try automationActivation(occurrence["activation_id"].text)
        let source = try item(occurrence["source_id"].text)
        let decision = try item(occurrence["decision_source"].text)
        let entry = source.data["occurrences"].array.filter { $0["id"] == occurrence["id"] }
        let retained = decision.data["decisions"].array.filter { $0["id"] == occurrence["id"] }
        let slot = try Value.parse(occurrence["slot"].text)
        let saved = try applicationDefinition(occurrence["definition_id"].text)
        try require(
          saved.kind == "automation" && saved.logicalID == activation["logical_id"].text
            && source.category == "source" && source.status == "accepted"
            && source.meaning == "actual" && source.kind == "automation_planning"
            && source.data["activationID"] == occurrence["activation_id"]
            && source.data["definitionID"] == occurrence["definition_id"]
            && source.data["generation"] == occurrence["generation"]
            && occurrence["generation"].int! <= activation["generation"].int!
            && entry.count == 1 && entry[0]["slot"] == slot
            && slot["slotKey"] == occurrence["slot_key"] && slot["due"] == occurrence["due"]
            && source.data["cursor"].text >= occurrence["due"].text
            && decision.category == "source"
            && ["automation_planning", "automation_authorization", "automation_dispatch"].contains(
              decision.kind)
            && decision.data["activationID"] == occurrence["activation_id"]
            && retained.count == 1 && retained[0]["state"] == occurrence["state"]
            && retained[0]["detail"] == occurrence["detail"]
            && (occurrence["state"] == .string("pending")
              ? occurrence["detail"] == .string("awaiting_dispatch")
              : occurrence["state"] == .string("dispatched")
                ? occurrence["detail"] == .string("workflow_queued")
                : ["late", "coalesced", "paused", "authorization_changed"].contains(
                  occurrence["detail"].text)),
          "automation_integrity",
          "An occurrence lost its original slot or latest decision evidence.")
        if decision.kind == "automation_dispatch" {
          try verifyAutomationDispatchDecision(occurrence, source: decision)
        }
        let rule = try DefinitionAutomation(DefinitionDescriptor(saved.content)).schedule
        try require(
          rule.selects(slot), "automation_integrity",
          "The occurrence does not match its pinned calendar rule.")
        let authorization = try item(source.data["authorizationSourceID"].text)
        try require(
          authorization.kind == "automation_authorization"
            && authorization.data["activationID"] == occurrence["activation_id"]
            && authorization.data["generation"] == occurrence["generation"]
            && authorization.data["state"] == .string("armed"),
          "automation_integrity", "An occurrence lost its preparation authorization.")
        try automationLineage(source.id, authorization.id)
        if decision.id != source.id { try automationLineage(decision.id, source.id) }
        after = occurrence["id"].text
      }
    }
    try verifyAutomationRuns()
    var sequence = 0
    while true {
      let rows = try db.execute(
        "SELECT * FROM automation_outbox WHERE sequence>? ORDER BY sequence LIMIT 100",
        [.number(Double(sequence))])
      if rows.isEmpty { break }
      for row in rows {
        let source = try item(row["source_id"]!.text)
        let planned = row["kind"] == .string("planned")
        let dispatched = ["dispatched", "dispatch_skipped"].contains(row["kind"]!.text)
        let scope =
          planned
            || ![.string("foreground-drafts-v1"), .string("condition-drafts-v1")].contains(
              source.data["policy"])
          ? "preparation-only" : "foreground-drafts"
        try require(
          source.category == "source"
            && source.kind
              == (planned
                ? "automation_planning"
                : dispatched ? "automation_dispatch" : "automation_authorization")
            && source.data["activationID"] == row["activation_id"]
            && source.data["generation"] == row["generation"]
            && (planned || dispatched
              || source.data["state"]
                == .string(row["kind"] == .string("authorized") ? "armed" : "paused"))
            && (try Value.parse(row["payload"]!.text))
              == .object(["scope": .string(scope)]),
          "automation_integrity", "The automation outbox disagrees with its saved Source.")
        sequence = row["sequence"]!.int!
      }
    }
  }

  func automationLineage(_ child: String, _ parent: String) throws {
    try require(
      try db.scalar(
        "SELECT EXISTS(SELECT 1 FROM lineage WHERE child=? AND parent=?)",
        [.string(child), .string(parent)]
      ).int == 1,
      "automation_integrity", "Automation preparation lost its exact Source lineage.")
  }
}
