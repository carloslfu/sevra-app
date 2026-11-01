import Foundation

extension Workbook {
  /// Exact definition lookup avoids scanning an unbounded activation catalog.
  public func automationState(_ exactDefinitionID: String) throws -> Value {
    try synchronized {
      let definition = try applicationDefinition(exactDefinitionID)
      try require(
        definition.id == exactDefinitionID && definition.kind == "automation",
        "automation_binding", "Inspect an exact saved schedule version.")
      guard
        let id = try db.scalar(
          "SELECT id FROM automation_activations WHERE logical_id=?",
          [.string(definition.logicalID)]
        ).string
      else { return .null }
      return try automationActivation(id)
    }
  }
  public func automationActivations(after: String = "", limit: Int = 20) throws -> Value {
    try require(
      (1...50).contains(limit) && after.utf8.count <= 256, "automation_limit",
      "Read 1 to 50 activations with a cursor up to 256 bytes.")
    return try synchronized {
      try db.readTransaction {
        let rows = try db.execute(
          "SELECT id FROM automation_activations WHERE id>? ORDER BY id LIMIT ?",
          [.string(after), .number(Double(limit + 1))])
        let page = Array(rows.prefix(limit))
        return .object([
          "activations": .array(try page.map { try automationActivation($0["id"]!.text) }),
          "nextCursor": rows.count > limit ? page.last!["id"]! : .null,
          "hasMore": .bool(rows.count > limit), "execution": .string("none"),
          "sessionRequired": .bool(true),
        ])
      }
    }
  }

  /// Prepare a bounded page of draft requests. No workflow is dispatched. Native
  /// calendar work happens before acquiring the write transaction; publication is
  /// fenced against the exact authorization and coverage cursor used for planning.
  public func planAutomationOccurrences(
    _ session: AutomationPlanningSession, through: Date, token: String,
    limit: Int = 100, horizonDays: Int = 3660, cancellation: Cancellation = .init()
  ) throws -> Value {
    try workflowToken(token)
    try require(
      (1...100).contains(limit) && (1...3660).contains(horizonDays), "schedule_limit",
      "Prepare 1 to 100 slots within 1 to 3660 civil days.")
    let throughText = try AutomationTime.text(through)
    let snapshot: (Value, NativeCalendarSchedule) = try synchronized(cancellation: cancellation) {
      try db.readTransaction {
        let activation = try automationSession(session)
        let saved = try applicationDefinition(activation["definition_id"].text)
        return (activation, try DefinitionAutomation(DefinitionDescriptor(saved.content)).schedule)
      }
    }
    let activation = snapshot.0
    let observedThrough = max(throughText, activation["observed_through"].text)
    let through = try AutomationTime.date(observedThrough)
    let cursor = try AutomationTime.date(activation["cursor"].text)
    let preview = try snapshot.1.preview(
      after: cursor, count: limit, horizonDays: horizonDays, cancellation: cancellation)
    let eligible = try preview["occurrences"].array.filter {
      try AutomationTime.date($0["due"].text) <= through
    }
    // A full page proves coverage only through its final returned slot. Otherwise
    // the exclusive scanned-day boundary leaves that next day's first slot unread.
    let covered: Date
    if preview["countReached"] == .bool(true), let last = preview["occurrences"].array.last,
      try AutomationTime.date(last["due"].text) <= through
    {
      covered = try AutomationTime.date(last["due"].text)
    } else {
      covered = min(
        through,
        try AutomationTime.date(preview["scannedThroughExclusive"].text).addingTimeInterval(-0.001))
    }
    // A slot past a gap that ended its day sits exactly on the exclusive scan boundary.
    let newest = try eligible.last.map { try AutomationTime.date($0["due"].text) } ?? cursor
    let nextCursor = try AutomationTime.text(max(cursor, covered, newest))
    let actor = ChangeActor.programmatic("SevraCore.calendar-preparation")
    let fence: () throws -> Void = { _ = try self.automationSession(session) }
    return try mutation(
      "automation_plan", token: token,
      request: .object([
        "activationID": .string(session.activationID),
        "generation": .number(Double(session.generation)),
        "sourceID": .string(session.sourceID), "through": .string(throughText),
        "limit": .number(Double(limit)), "horizonDays": .number(Double(horizonDays)),
      ]), cancellation: cancellation, actor: actor,
      commitGuard: fence
    ) {
      let current = try self.automationSession(session)
      try require(
        current["cursor"] == activation["cursor"]
          && current["observed_through"] == activation["observed_through"]
          && current["coverage_source"] == activation["coverage_source"], "stale_automation",
        "Another planner advanced coverage. Refresh before preparing another page.")
      let pending = try self.pendingAutomationOccurrence(session.activationID)
      var decisions: [Value] = []
      if pending != .null {
        let late = through.timeIntervalSince(try AutomationTime.date(pending["due"].text)) > 86_400
        if !eligible.isEmpty || late {
          decisions.append(self.automationDecision(pending, late ? "late" : "coalesced"))
        }
      }
      var entries: [Value] = []
      for (index, slot) in eligible.enumerated() {
        let late = through.timeIntervalSince(try AutomationTime.date(slot["due"].text)) > 86_400
        let state = !late && index == eligible.count - 1 ? "pending" : "skipped"
        let detail = late ? "late" : state == "skipped" ? "coalesced" : "awaiting_dispatch"
        let entry: Value = .object([
          "id": .string(identifier()), "slot": slot, "state": .string(state),
          "detail": .string(detail),
        ])
        entries.append(entry)
        decisions.append(
          .object(["id": entry["id"], "state": entry["state"], "detail": entry["detail"]]))
      }
      let remaining = try AutomationTime.date(nextCursor) < through
      let source = try self.insertItem(
        category: "source", kind: "automation_planning", title: "Prepare calendar occurrences",
        text:
          "The calendar planner retained bounded draft requests. No workflow or business effect ran.",
        data: .object([
          "activationID": .string(session.activationID),
          "definitionID": activation["definition_id"],
          "generation": .number(Double(session.generation)),
          "authorizationSourceID": .string(session.sourceID),
          "actor": try encoded(actor), "previousCoverageSourceID": activation["coverage_source"],
          "previousCursor": activation["cursor"],
          "cursor": .string(nextCursor),
          "through": .string(observedThrough), "requestedThrough": .string(throughText),
          "catchUpRemaining": .bool(remaining),
          "occurrences": .array(entries), "decisions": .array(decisions),
          "policy": .string("calendar-prepare-v1"),
        ]), meaning: "actual", status: "accepted", scenario: "actual",
        inputs: [], transformation: "automation-calendar-preparation-v1",
        controlInputs: Array(
          Set(
            [session.sourceID, activation["coverage_source"].text]
              + (pending["source_id"].string.map { [$0] } ?? []))
        ).sorted())
      // Clear the previous pending row before publishing the new one. The unique
      // partial index enforces one pending request even across independent writers.
      try self.applyAutomationDecisions(decisions, source: source)
      for entry in entries {
        let slot = entry["slot"]
        try self.db.execute(
          "INSERT INTO automation_occurrences VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
          [
            entry["id"], .string(session.activationID), activation["definition_id"],
            .number(Double(session.generation)), slot["slotKey"], slot["due"],
            .string(try slot.json()),
            entry["state"], entry["detail"], .string(source), .string(source),
            .string(timestamp()), .string(timestamp()),
          ])
      }
      try self.db.execute(
        "UPDATE automation_activations SET cursor=?,observed_through=?,catch_up_remaining=?,coverage_source=?,updated=? WHERE id=?",
        [
          .string(nextCursor), .string(observedThrough), .number(remaining ? 1 : 0),
          .string(source),
          .string(timestamp()), .string(session.activationID),
        ])
      try self.automationEvent(
        session.activationID, generation: session.generation, kind: "planned", source: source)
      return .object([
        "activationID": .string(session.activationID),
        "generation": .number(Double(session.generation)),
        "sourceID": .string(source), "cursor": .string(nextCursor),
        "through": .string(observedThrough), "requestedThrough": .string(throughText),
        "catchUpRemaining": .bool(remaining), "preparedCount": .number(Double(entries.count)),
        "pending": try self.pendingAutomationOccurrence(session.activationID),
        "execution": .string("preparation-only"),
      ])
    }
  }

  public func automationOccurrences(_ activationID: String, after: String? = nil, limit: Int = 20)
    throws -> Value
  {
    try require((1...50).contains(limit), "automation_limit", "Read 1 to 50 occurrences.")
    return try synchronized {
      try db.readTransaction {
        _ = try automationActivation(activationID)
        var bindings: [Value] = [.string(activationID)]
        var clause = ""
        if let after {
          guard
            let cursor = try db.execute(
              "SELECT due,id FROM automation_occurrences WHERE id=? AND activation_id=?",
              [.string(after), .string(activationID)]
            ).first
          else { throw SevraError("automation_cursor", "Choose a cursor from this activation.") }
          clause = " AND (due,id)>(?,?)"
          bindings += [cursor["due"]!, cursor["id"]!]
        }
        bindings.append(.number(Double(limit + 1)))
        let rows = try db.execute(
          "SELECT * FROM automation_occurrences WHERE activation_id=?" + clause
            + " ORDER BY due,id LIMIT ?", bindings)
        let page = Array(rows.prefix(limit))
        return .object([
          "occurrences": .array(
            try page.map { row in
              var row = row
              row["slot"] = try Value.parse(row["slot"]!.text)
              return .object(row)
            }), "nextCursor": rows.count > limit ? page.last!["id"]! : .null,
          "hasMore": .bool(rows.count > limit), "execution": .string("none"),
          "sessionRequired": .bool(true),
        ])
      }
    }
  }

  public func automationEvents(after: Int = 0, limit: Int = 20) throws -> Value {
    try require(
      after >= 0 && (1...50).contains(limit), "automation_limit",
      "Use a nonnegative cursor and 1 to 50 events.")
    return try synchronized {
      let rows = try db.execute(
        "SELECT * FROM automation_outbox WHERE sequence>? ORDER BY sequence LIMIT ?",
        [.number(Double(after)), .number(Double(limit + 1))])
      let page = Array(rows.prefix(limit))
      return .object([
        "events": .array(
          try page.map { row in
            var row = row
            row["payload"] = try Value.parse(row["payload"]!.text)
            return .object(row)
          }), "after": page.last?["sequence"] ?? .number(Double(after)),
        "hasMore": .bool(rows.count > limit),
      ])
    }
  }
}
