import Foundation

/// Qualification-only observer. Ordinary execution installs no observer.
package enum InventoryConditionPublicationProbe {
  package enum Stage: Sendable { case prepared, committed }
  @TaskLocal package static var observer: (@Sendable (Stage) throws -> Void)?
}

struct InventoryConditionWork: Codable {
  var cursorID: String?
  var cursorPosition = "0"
  var ready = false
  var through: String
  var requestedThrough: String
  var phase = "idle"
  var pendingBatch: String?
  var ordinal = -1
  var scanEffective = ""
  var scanLogical = ""
  var effectCount = 0
  var rebuildRequired = false
  var basis: Value = .null
  var quantity: String?
  var lastObservation: String?
  var lastCertainID: String?
  var lastCertainTruth: Bool?
  var gap = false
  var pendingInputCount = 0
  var inputOverflow = false
}

extension Workbook {
  /// Saves an inert, explicitly stepped derivation. No timer, grant or workflow.
  public func createInventoryCondition(
    subject: String, rule: Value, effectiveThrough: String, token: String,
    cancellation: Cancellation = .init(), actor: ChangeActor? = nil
  ) throws -> Value {
    try workflowToken(token)
    try require(
      !subject.isEmpty && subject.utf8.count <= 200
        && !subject.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
      "condition_scope", "Use an inventory subject with 1 to 200 UTF-8 bytes.")
    let rule = try NativeConditionRule(rule).definition
    try require(
      rule["scope"] == .string("inventory:" + subject), "condition_scope",
      "The rule scope must be inventory: followed by the exact subject.")
    let through = try BusinessTime.normalized(effectiveThrough)
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try mutation(
      "condition_create", token: token,
      request: .object(["subject": .string(subject), "rule": rule, "through": .string(through)]),
      cancellation: control, actor: actor
    ) {
      let anchor = try self.db.scalar(
        "SELECT id FROM business_batches ORDER BY position DESC LIMIT 1")
      let source = try self.insertItem(
        category: "source", kind: "condition_intent", title: "Track an inventory condition",
        text:
          "Save a condition baseline and inert candidate requests. No automatic work is enabled.",
        data: .object([
          "subject": .string(subject), "rule": rule, "anchorID": anchor,
          "effectiveThrough": .string(through), "policy": .string("inventory-condition-v1"),
        ]), meaning: "rule", status: "accepted", scenario: "actual", inputs: [],
        transformation: "inventory-condition-v1")
      let consumer = identifier()
      let state = InventoryConditionWork(through: through, requestedThrough: through)
      try self.db.execute(
        "INSERT INTO condition_consumers VALUES(?,?,?,?,?,?,?)",
        [
          .string(consumer), .string(source), .string(subject), .string(try rule.json()), anchor,
          .string(try ChangeFormat.encode(state)), .string(timestamp()),
        ])
      return try self.inventoryConditionStatus(consumer)
    }
  }

  public func inventoryCondition(_ id: String, cancellation: Cancellation = .init()) throws -> Value
  {
    try readBusinessFeed(cancellation: cancellation) { try inventoryConditionStatus(id) }
  }

  /// Advances at most one 100-row page. A complete batch/group, observation,
  /// candidate and completed cursor are published together, or not at all.
  public func stepInventoryCondition(
    _ id: String, through: String, token: String, cancellation: Cancellation = .init()
  ) throws -> Value {
    try workflowToken(token)
    let through = try BusinessTime.normalized(through)
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    let publicationGuard: () throws -> Void = {
      try InventoryConditionPublicationProbe.observer?(.prepared)
      try control.check()
    }
    let result = try mutation(
      "condition_step", token: token,
      request: .object(["consumerID": .string(id), "through": .string(through)]),
      cancellation: control, actor: .programmatic("SevraCore.inventory-condition"),
      commitGuard: publicationGuard
    ) {
      let row = try self.inventoryConditionRow(id)
      var work = try self.inventoryConditionWork(row)
      try require(
        through >= work.requestedThrough, "condition_clock",
        "The retained condition horizon cannot move backwards.")
      work.requestedThrough = through
      if work.phase == "idle" {
        try self.beginInventoryConditionPage(row, work: &work)
      }
      switch work.phase {
      case "batch": try self.applyInventoryConditionBatch(row, work: &work, control: control)
      case "clock": try self.applyInventoryConditionClock(row, work: &work, control: control)
      case "rebuild": try self.rebuildInventoryCondition(row, work: &work, control: control)
      default: break
      }
      if work.phase == "finalize" { try self.finalizeInventoryCondition(row, work: &work) }
      try self.db.execute(
        "UPDATE condition_consumers SET state=? WHERE id=?",
        [.string(try ChangeFormat.encode(work)), .string(id)])
      let result = try self.inventoryConditionStatus(id)
      try self.boundedBusinessOutput(result)
      return result
    }
    try InventoryConditionPublicationProbe.observer?(.committed)
    return result
  }

  public func inventoryConditionObservations(
    _ id: String, after: String? = nil, limit: Int = 20, cancellation: Cancellation = .init()
  ) throws -> Value {
    try require((1...50).contains(limit), "condition_limit", "Read 1 to 50 observations.")
    return try readBusinessFeed(cancellation: cancellation) {
      _ = try inventoryConditionRow(id)
      var sequence: Value = .string("0")
      if let after {
        sequence = try db.scalar(
          "SELECT CAST(rowid AS TEXT) FROM condition_observations WHERE id=? AND consumer_id=?",
          [.string(after), .string(id)])
        try require(sequence != .null, "condition_cursor", "Use an observation from this consumer.")
      }
      let rows = try db.execute(
        "SELECT o.id,o.payload,c.id AS candidate_id,c.state AS candidate_state,c.detail FROM condition_observations o LEFT JOIN condition_candidates c ON c.observation_id=o.id WHERE o.consumer_id=? AND o.rowid>CAST(? AS INTEGER) ORDER BY o.rowid LIMIT ?",
        [.string(id), sequence, .number(Double(limit + 1))], maxRows: limit + 1, maxBytes: 8_388_608
      )
      let page = Array(rows.prefix(limit))
      let result: Value = .object([
        "observations": .array(
          try page.map { row in
            .object([
              "observation": try Value.parse(row["payload"]!.text),
              "candidateID": row["candidate_id"]!, "candidateState": row["candidate_state"]!,
              "detail": row["detail"]!,
            ])
          }), "hasMore": .bool(rows.count > limit),
        "nextCursor": rows.count > limit ? page.last!["id"]! : .null,
        "execution": .string("inert"), "enabled": .bool(false),
      ])
      try boundedBusinessOutput(result)
      return result
    }
  }

  public func dismissInventoryConditionCandidate(
    _ candidate: String, reason: String, token: String, cancellation: Cancellation = .init(),
    actor: ChangeActor? = nil
  ) throws -> Value {
    try workflowToken(token)
    try require(
      !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reason.utf8.count <= 1024,
      "condition_reason", "Keep a nonempty dismissal reason up to 1,024 UTF-8 bytes.")
    return try mutation(
      "condition_dismiss", token: token,
      request: .object(["candidateID": .string(candidate), "reason": .string(reason)]),
      cancellation: Cancellation(parent: cancellation, deadlineAfterSeconds: 3), actor: actor
    ) {
      guard
        let row = try self.db.execute(
          "SELECT * FROM condition_candidates WHERE id=?", [.string(candidate)]
        ).first
      else { throw SevraError("condition_candidate", "The candidate request is missing.") }
      try require(
        row["state"] == .string("pending"), "condition_candidate",
        "The request was already dismissed.")
      let source = try self.insertItem(
        category: "source", kind: "condition_dismissal", title: "Dismiss a condition candidate",
        text: reason,
        data: .object(["candidateID": .string(candidate), "execution": .string("inert")]),
        meaning: "actual", status: "accepted", scenario: "actual",
        inputs: [], transformation: "inventory-condition-dismissal-v1",
        controlInputs: [try self.inventoryConditionRow(row["consumer_id"]!.text)["source_id"]!.text]
      )
      try self.db.execute(
        "UPDATE condition_candidates SET state='dismissed',detail=?,decision_source=? WHERE id=?",
        [.string(reason), .string(source), .string(candidate)])
      return .object([
        "candidateID": .string(candidate), "state": .string("dismissed"),
        "sourceID": .string(source), "execution": .string("inert"),
      ])
    }
  }

  func inventoryConditionRow(_ id: String) throws -> [String: Value] {
    guard
      let row = try db.execute("SELECT * FROM condition_consumers WHERE id=?", [.string(id)]).first
    else { throw SevraError("condition_consumer", "The saved condition is missing.") }
    return row
  }
  func inventoryConditionWork(_ row: [String: Value]) throws -> InventoryConditionWork {
    try JSONDecoder().decode(InventoryConditionWork.self, from: Data(row["state"]!.text.utf8))
  }
  func inventoryConditionStatus(_ id: String) throws -> Value {
    let row = try inventoryConditionRow(id)
    let work = try inventoryConditionWork(row)
    let pending = try db.scalar(
      "SELECT count(*) FROM condition_candidates WHERE consumer_id=? AND state='pending'",
      [.string(id)])
    let observation: Value
    if let last = work.lastObservation {
      observation = try Value.parse(
        db.scalar("SELECT payload FROM condition_observations WHERE id=?", [.string(last)]).text)
    } else {
      observation = .null
    }
    let more = try db.scalar(
      "SELECT EXISTS(SELECT 1 FROM business_batches WHERE position>CAST(? AS INTEGER))",
      [.string(work.cursorPosition)])
    return .object([
      "id": .string(id), "workbookID": .string(self.id), "subject": row["subject"]!,
      "rule": try Value.parse(row["rule"]!.text), "sourceID": row["source_id"]!,
      "anchorID": row["anchor_id"]!,
      "established": .bool(work.ready), "phase": .string(work.phase),
      "cursorID": work.cursorID.map(Value.string) ?? .null,
      "cursorPosition": .string(work.cursorPosition),
      "effectiveThrough": observation["effectiveThrough"],
      "workingEffectiveThrough": .string(work.through),
      "requestedThrough": .string(work.requestedThrough),
      "pendingBatchID": work.pendingBatch.map(Value.string) ?? .null,
      "pendingOrdinal": .number(Double(work.ordinal)), "pendingCandidates": pending,
      "backpressure": .bool(work.phase == "finalize" && pending.int == 100),
      "hasMore": .bool(
        !work.ready || work.phase != "idle" || more.int == 1 || work.through < work.requestedThrough
      ),
      "lastCompleteObservation": observation, "execution": .string("inert"),
      "enabled": .bool(false),
      "coverage": .string("retained-batches-and-explicit-clock"),
    ])
  }
}
