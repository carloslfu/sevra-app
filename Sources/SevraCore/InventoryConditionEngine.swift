import Foundation

extension Workbook {
  func beginInventoryConditionPage(_ row: [String: Value], work: inout InventoryConditionWork)
    throws
  {
    let next = try db.execute(
      "SELECT id,CAST(position AS TEXT) AS position,recorded FROM business_batches b WHERE b.position>CAST(? AS INTEGER) ORDER BY b.position LIMIT 1",
      [.string(work.cursorPosition)]
    ).first
    if !work.ready {
      if row["anchor_id"] == .null {
        try beginInventoryConditionRebuild(&work)
      } else {
        guard let next else {
          throw SevraError("condition_integrity", "The retained baseline batch is missing.")
        }
        work.pendingBatch = next["id"]!.text
        work.ordinal = -1
        work.phase = "batch"
      }
      return
    }
    let boundary =
      try next.map {
        max(
          work.through,
          min(work.requestedThrough, try BusinessTime.normalized($0["recorded"]!.text)))
      } ?? work.requestedThrough
    var due = try db.scalar(
      "SELECT effective FROM condition_effects WHERE consumer_id=? AND effective>? AND effective<=? ORDER BY effective LIMIT 1",
      [row["id"]!, .string(work.through), .string(boundary)]
    ).string
    if let basisTime = work.basis["effective"].string,
      basisTime > work.through && basisTime <= boundary
    {
      due = min(due ?? basisTime, basisTime)
    }
    if let due {
      let basisWasFuture = work.basis["effective"].string.map { $0 > work.through } ?? false
      work.through = due
      work.scanLogical = ""
      work.pendingBatch = nil
      if basisWasFuture && work.basis["effective"].text <= due {
        try retainConditionClockInput(
          row, eventID: work.basis["eventID"].text,
          kind: "basis-clock", work: &work)
        try beginInventoryConditionRebuild(&work)
      } else {
        work.phase = "clock"
      }
    } else if let next {
      work.through = boundary
      work.rebuildRequired =
        try db.scalar(
          "SELECT EXISTS(SELECT 1 FROM business_events WHERE scope_kind='inventory' AND scope_key=? AND batch_position=CAST(? AS INTEGER) AND family='inventory-basis')",
          [row["subject"]!, next["position"]!]
        ).int == 1
      work.pendingBatch = next["id"]!.text
      work.ordinal = -1
      work.phase = "batch"
    } else if boundary > work.through {
      work.through = boundary
      work.pendingBatch = nil
      work.phase = "finalize"
    }
  }

  /// Returns how many entries of the page this took.
  func applyInventoryConditionBatch(
    _ row: [String: Value], work: inout InventoryConditionWork, limit: Int, control: Cancellation
  ) throws -> Int {
    guard let batch = work.pendingBatch else {
      throw SevraError("condition_integrity", "An unfinished business batch has no identity.")
    }
    let entries = try db.execute(
      "SELECT * FROM business_events WHERE batch_id=? AND ordinal>? ORDER BY ordinal LIMIT ?",
      [.string(batch), .number(Double(work.ordinal)), .number(Double(limit + 1))],
      maxRows: limit + 1, maxBytes: 8_388_608)
    try require(
      !entries.isEmpty, "condition_integrity",
      "An unfinished business batch lost its remaining entries.")
    var basisChanged = false
    for entry in entries.prefix(limit) {
      try control.check()
      if entry["family"] == .string("record-settled") {
        try updateInventoryConditionEffect(row, event: entry, work: &work)
      } else if entry["family"] == .string("inventory-basis")
        && entry["scope_key"] == row["subject"]
      {
        try retainConditionInput(row, event: entry, kind: "basis-change", work: &work)
        let basis = try Value.parse(entry["payload"]!.text)["after"]
        if basis == .null {
          work.basis = .null
        } else {
          try require(
            basis["sourceID"] == entry["after_id"] && basis["subject"] == row["subject"],
            "condition_integrity", "The retained opening basis is inconsistent.")
          _ = try Numbers.decimal(basis["quantity"].text)
          try require(
            try BusinessTime.normalized(basis["effective"].text) == basis["effective"].text,
            "condition_integrity", "The opening basis time is not normalized.")
          work.basis = .object([
            "inputID": basis["sourceID"], "quantity": basis["quantity"],
            "effective": basis["effective"],
            "eventID": entry["id"]!, "batchID": entry["batch_id"]!,
          ])
        }
        basisChanged = true
      }
      work.ordinal = entry["ordinal"]!.int!
    }
    // Basis events follow settled records in the publisher's fixed family order.
    // If a page ends after a basis replacement, retain the required rebuild phase.
    if basisChanged {
      work.quantity = nil
      work.rebuildRequired = true
    }
    if entries.count <= limit {
      if !work.ready && row["anchor_id"] != .string(batch) {
        let metadata = try businessBatchMetadata(batch)
        work.cursorID = batch
        work.cursorPosition = metadata["position"].text
        work.pendingBatch = nil
        work.phase = "idle"
      } else if !work.ready || work.rebuildRequired || work.quantity == nil {
        try beginInventoryConditionRebuild(&work)
      } else {
        work.phase = "finalize"
      }
    }
    return min(entries.count, limit)
  }

  func applyInventoryConditionClock(
    _ row: [String: Value], work: inout InventoryConditionWork, control: Cancellation
  ) throws {
    let effects = try db.execute(
      "SELECT * FROM condition_effects WHERE consumer_id=? AND effective=? AND logical_id>? ORDER BY logical_id LIMIT 101",
      [row["id"]!, .string(work.through), .string(work.scanLogical)], maxRows: 101,
      maxBytes: 1_048_576)
    for effect in effects.prefix(100) {
      try control.check()
      if inventoryConditionEligible(effect, work: work), let total = work.quantity {
        try retainConditionClockInput(
          row, eventID: effect["event_id"]!.text,
          kind: "effect-clock", work: &work)
        work.quantity = try conditionExactSum(total, effect["quantity"]!.text)
      }
      work.scanLogical = effect["logical_id"]!.text
    }
    if effects.count <= 100 { work.phase = "finalize" }
  }

  func beginInventoryConditionRebuild(_ work: inout InventoryConditionWork) throws {
    work.scanEffective = ""
    work.scanLogical = ""
    if let basisTime = work.basis["effective"].string, basisTime <= work.through {
      work.quantity = try Numbers.string(Numbers.decimal(work.basis["quantity"].text))
      work.phase = "rebuild"
    } else {
      work.quantity = nil
      work.phase = "finalize"
    }
  }

  func rebuildInventoryCondition(
    _ row: [String: Value], work: inout InventoryConditionWork, control: Cancellation
  ) throws {
    let effects = try db.execute(
      "SELECT * FROM condition_effects WHERE consumer_id=? AND effective>? AND effective<=? AND (effective,logical_id)>(?,?) ORDER BY effective,logical_id LIMIT 101",
      [
        row["id"]!, work.basis["effective"], .string(work.through), .string(work.scanEffective),
        .string(work.scanLogical),
      ],
      maxRows: 101, maxBytes: 1_048_576)
    for effect in effects.prefix(100) {
      try control.check()
      guard let quantity = work.quantity else {
        throw SevraError("condition_integrity", "The working sum is missing.")
      }
      work.quantity = try conditionExactSum(quantity, effect["quantity"]!.text)
      work.scanEffective = effect["effective"]!.text
      work.scanLogical = effect["logical_id"]!.text
    }
    if effects.count <= 100 { work.phase = "finalize" }
  }

  /// Only a crossing waits for the queue. Every other observation still publishes.
  func inventoryConditionHeld(
    _ row: [String: Value], work: InventoryConditionWork, pending: Int
  ) throws -> Bool {
    guard work.phase == "finalize", pending >= 100, work.lastCertainTruth == false else {
      return false
    }
    return try work.quantity.map(NativeConditionRule(Value.parse(row["rule"]!.text)).truth) == true
  }

  func finalizeInventoryCondition(_ row: [String: Value], work: inout InventoryConditionWork) throws
  {
    let rule = try NativeConditionRule(Value.parse(row["rule"]!.text))
    let truth = try work.quantity.map(rule.truth)
    let crossing = work.lastCertainTruth == false && truth == true
    let pending =
      try db.scalar(
        "SELECT count(*) FROM condition_candidates WHERE consumer_id=? AND state='pending'",
        [row["id"]!]
      ).int ?? 0
    if try inventoryConditionHeld(row, work: work, pending: pending) { return }
    let batch = work.pendingBatch ?? work.cursorID
    let coordinate: Value = .array([
      row["id"]!, batch.map(Value.string) ?? .null, .string(work.through),
    ])
    let observationID = "condition_observation_" + ChangeFormat.hash(try coordinate.json())
    let disposition =
      truth == nil
      ? "unknown"
      : work.lastCertainTruth == nil
        ? "baseline"
        : crossing
          ? "transition" : work.lastCertainTruth == true && truth == false ? "reset" : "unchanged"
    let candidateID =
      crossing
      ? "condition:"
        + ChangeFormat.hash(
          try Value.object([
            "rule": rule.definition, "observationID": .string(observationID),
          ]).json()) : nil
    let observation: Value = .object([
      "id": .string(observationID), "consumerID": row["id"]!, "rule": rule.definition,
      "knowledgeBatchID": batch.map(Value.string) ?? .null,
      "effectiveThrough": .string(work.through),
      "quantity": work.quantity.map(Value.string) ?? .null, "known": .bool(truth != nil),
      "reason": truth != nil
        ? .null : .string(work.basis == .null ? "unknown_basis" : "basis_not_effective"),
      "truth": truth.map(Value.bool) ?? .null, "disposition": .string(disposition),
      "basis": work.basis,
      "previousCertainObservationID": work.lastCertainID.map(Value.string) ?? .null,
      "previousObservationID": work.lastObservation.map(Value.string) ?? .null,
      "coverageGap": .bool(work.gap && truth != nil),
      "changeInputs": ConditionInput.summary(
        count: work.pendingInputCount, overflow: work.inputOverflow,
        baseline: work.lastCertainID == nil, gap: work.gap || truth == nil),
      "candidateID": candidateID.map(Value.string) ?? .null,
      "execution": .string("inert"), "enabled": .bool(false),
    ])
    try db.execute(
      "INSERT INTO condition_observations VALUES(?,?,?,?,?,?,?)",
      [
        .string(observationID), row["id"]!, batch.map(Value.string) ?? .null, .string(work.through),
        .string(disposition), .string(try observation.json()), .string(timestamp()),
      ])
    try db.execute(
      "INSERT INTO condition_observation_inputs SELECT ?,id,payload FROM condition_pending_inputs WHERE consumer_id=?",
      [.string(observationID), row["id"]!])
    try db.execute("DELETE FROM condition_pending_inputs WHERE consumer_id=?", [row["id"]!])
    work.pendingInputCount = 0
    work.inputOverflow = false
    if let candidateID {
      try db.execute(
        "INSERT INTO condition_candidates VALUES(?,?,?,'pending','awaiting_dispatch_contract',NULL)",
        [
          .string(candidateID), row["id"]!, .string(observationID),
        ])
    }
    work.lastObservation = observationID
    if let truth {
      work.lastCertainTruth = truth
      work.lastCertainID = observationID
      work.gap = false
    } else {
      work.gap = true
    }
    if let pendingBatch = work.pendingBatch {
      work.cursorID = pendingBatch
      work.cursorPosition = try businessBatchMetadata(pendingBatch)["position"].text
    }
    work.ready = true
    work.rebuildRequired = false
    work.pendingBatch = nil
    work.ordinal = -1
    work.phase = "idle"
  }
}
