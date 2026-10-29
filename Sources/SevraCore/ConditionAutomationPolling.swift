import Foundation

extension Workbook {
  /// Validates unsaved typed intent without creating a definition or permission.
  public func previewAutomationDraft(
    _ content: Value, after: Date, cancellation: Cancellation = .init()
  ) throws -> Value {
    try readBusinessFeed(cancellation: cancellation) {
      let descriptor = try DefinitionDescriptor(content)
      let retained = try validateAutomationDefinition(descriptor)
      let trigger = try DefinitionAutomation(descriptor)
      var result: [String: Value] = [
        "workflowID": .string(retained.workflow.id), "arguments": retained.arguments,
        "enabled": .bool(false), "execution": .string("inert"),
      ]
      if let condition = trigger.condition {
        result["condition"] = .object([
          "subject": .string(condition.subject), "rule": condition.rule,
          "baselinePolicy": .string("initial-enable-no-prior-crossing"),
        ])
      } else {
        result["calendar"] = try trigger.schedule.preview(after: after, cancellation: cancellation)
      }
      return .object(result)
    }
  }

  public func inventoryConditionQueue(
    _ id: String, limit: Int = 20, cancellation: Cancellation = .init()
  ) throws -> Value {
    try require((1...50).contains(limit), "condition_limit", "Read one to 50 waiting transitions.")
    return try readBusinessFeed(cancellation: cancellation) {
      _ = try inventoryConditionRow(id)
      let rows = try db.execute(
        "SELECT c.id,o.payload FROM condition_candidates c JOIN condition_observations o ON o.id=c.observation_id WHERE c.consumer_id=? AND c.state='pending' ORDER BY o.rowid LIMIT ?",
        [.string(id), .number(Double(limit + 1))], maxRows: limit + 1, maxBytes: 8_388_608)
      return .object([
        "candidates": .array(
          try rows.prefix(limit).map {
            .object(["candidateID": $0["id"]!, "observation": try Value.parse($0["payload"]!.text)])
          }),
        "hasMore": .bool(rows.count > limit), "execution": .string("none"),
      ])
    }
  }

  /// A read-only native-owner probe. Time alone does not write an idle checkpoint;
  /// only unread batches, unfinished pages or newly effective inputs need a step.
  package func deviceConditionWork(
    _ session: AutomationExecutionSession, through: Date, cancellation: Cancellation = .init()
  ) throws -> Value {
    let instant = try BusinessTime.normalized(AutomationTime.text(through))
    return try readBusinessFeed(cancellation: cancellation) {
      let activation = try conditionExecutionScope(session)
      let row = try inventoryConditionRow(activation["consumer_id"].text)
      let work = try inventoryConditionWork(row)
      let pending = try db.scalar(
        "SELECT count(*) FROM condition_candidates WHERE consumer_id=? AND state='pending'",
        [row["id"]!])
      let batch = try db.scalar(
        "SELECT EXISTS(SELECT 1 FROM business_batches WHERE position>CAST(? AS INTEGER))",
        [.string(work.cursorPosition)])
      let due = try db.scalar(
        "SELECT effective FROM condition_effects WHERE consumer_id=? AND effective>? ORDER BY effective LIMIT 1",
        [row["id"]!, .string(work.through)])
      let basisTime = work.basis["effective"].string.flatMap { $0 > work.through ? $0 : nil }
      let next = [basisTime, due.string].compactMap { $0 }.min()
      let needsStep =
        !work.ready || work.phase != "idle" || batch.int == 1
        || work.through < work.requestedThrough || next.map { $0 <= instant } == true
      let ahead = work.requestedThrough > instant
      return .object([
        "consumerID": row["id"]!, "needsStep": .bool(needsStep && !ahead),
        "horizonAhead": .bool(ahead), "pendingCandidates": pending,
        "nextEffective": next.map(Value.string) ?? .null,
        "established": .bool(work.ready), "execution": .string("none"),
      ])
    }
  }
}
