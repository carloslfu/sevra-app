import Foundation

enum ConditionInput {
  static let policy = "inventory-transition-inputs-v1"
  static let limit = 10_000

  static func value(_ kind: String, event: [String: Value], effective: String? = nil) -> Value {
    .object([
      "kind": .string(kind), "eventID": event["id"]!, "batchID": event["batch_id"]!,
      "beforeID": effective == nil ? event["before_id"]! : .null,
      "afterID": event["after_id"]!, "effective": effective.map(Value.string) ?? .null,
    ])
  }

  static func identity(_ value: Value, consumer: String) throws -> String {
    "condition-input:"
      + ChangeFormat.hash(
        try Value.array([.string(policy), .string(consumer), value]).json())
  }

  static func summary(count: Int, overflow: Bool, baseline: Bool, gap: Bool) -> Value {
    .object([
      "policy": .string(policy), "count": .number(Double(count)), "overflow": .bool(overflow),
      "coverage": .string(
        overflow ? "limit-exceeded" : baseline ? "baseline" : gap ? "unknown-gap" : "complete"),
      "minimalCauseSet": .bool(false), "automaticParents": .string("not-resolved"),
      "dispatchEligibility": .string("not-evaluated"),
    ])
  }
}

extension Workbook {
  func retainConditionClockInput(
    _ consumer: [String: Value], eventID: String, kind: String, work: inout InventoryConditionWork
  ) throws {
    let event = try conditionInputEvent(eventID)
    try retainConditionInput(
      consumer, event: event, kind: kind, effective: work.through, work: &work)
  }

  func retainConditionInput(
    _ consumer: [String: Value], event: [String: Value], kind: String, effective: String? = nil,
    work: inout InventoryConditionWork
  ) throws {
    try require(
      db.changes?.pending != nil && db.changes?.publishing == false,
      "condition_input_transaction",
      "Condition inputs belong inside the captured consumer transaction.")
    // Establishing the captured anchor does not turn old changes into new triggers.
    guard work.ready, !work.inputOverflow else { return }
    let value = ConditionInput.value(kind, event: event, effective: effective)
    let id = try ConditionInput.identity(value, consumer: consumer["id"]!.text)
    let key = [consumer["id"]!, .string(id)]
    if try db.scalar(
      "SELECT EXISTS(SELECT 1 FROM condition_pending_inputs WHERE consumer_id=? AND id=?)", key
    ).int == 1 {
      return
    }
    if work.pendingInputCount == ConditionInput.limit {
      work.inputOverflow = true
      return
    }
    let payload = try value.json()
    try require(
      payload.utf8.count <= 16_384, "condition_input_limit", "A condition input exceeds 16 KiB.")
    try db.execute("INSERT INTO condition_pending_inputs VALUES(?,?,?)", key + [.string(payload)])
    work.pendingInputCount += 1
  }

  func conditionInputEvent(_ id: String) throws -> [String: Value] {
    guard
      let event = try db.execute(
        "SELECT * FROM business_events WHERE id=?", [.string(id)],
        maxRows: 1, maxBytes: 65_536
      ).first
    else {
      throw SevraError(
        "condition_input_integrity", "An exact introducing business event is missing.")
    }
    return event
  }

  func conditionInputEffect(_ id: Value, subject: String) throws -> [String: Value]? {
    if id == .null { return nil }
    let effects = try db.execute(
      "SELECT f.* FROM items i JOIN effects f ON f.item_id=i.id WHERE i.id=? AND i.category='record' AND i.kind='movement' AND i.status='accepted' AND i.meaning='actual' AND i.scenario='actual' AND f.kind='inventory' AND f.subject=? LIMIT 2",
      [id, .string(subject)], maxRows: 2, maxBytes: 65_536)
    try require(
      effects.count <= 1, "condition_input_integrity",
      "An exact version has conflicting inventory effects.")
    return effects.first
  }

  func validateConditionInput(
    _ id: String, value: Value, consumer: [String: Value], batch: String?, effective: String
  ) throws {
    let event = try conditionInputEvent(value["eventID"].text)
    let kind = value["kind"].text
    let clock = ["effect-clock", "basis-clock"].contains(kind)
    try require(
      ["record-change", "basis-change", "effect-clock", "basis-clock"].contains(kind)
        && value == ConditionInput.value(kind, event: event, effective: clock ? effective : nil)
        && id == ConditionInput.identity(value, consumer: consumer["id"]!.text),
      "condition_input_integrity",
      "A retained condition input lost its exact content or coordinates.")
    if clock {
      guard let batch else {
        throw SevraError(
          "condition_input_integrity", "A clock input has no retained knowledge batch.")
      }
      try require(
        try db.scalar(
          "SELECT EXISTS(SELECT 1 FROM business_batches WHERE id=? AND position>=CAST(? AS INTEGER))",
          [.string(batch), event["batch_position"]!]
        ).int == 1,
        "condition_input_integrity", "A clock input uses knowledge later than its observation.")
    } else {
      try require(
        event["batch_id"] == batch.map(Value.string), "condition_input_integrity",
        "A changed input does not belong to the observed atomic batch.")
    }
    if kind == "record-change" {
      let before = try conditionInputEffect(event["before_id"]!, subject: consumer["subject"]!.text)
      let after = try conditionInputEffect(event["after_id"]!, subject: consumer["subject"]!.text)
      try require(
        event["family"] == .string("record-settled") && (before != nil || after != nil),
        "condition_input_integrity",
        "A settled input has no prior or current effect in this inventory scope.")
    } else if kind == "effect-clock" {
      let effect = try conditionInputEffect(event["after_id"]!, subject: consumer["subject"]!.text)
      try require(
        event["family"] == .string("record-settled") && effect?["effective"] == .string(effective),
        "condition_input_integrity",
        "The exact inventory input did not become effective at this instant.")
    } else {
      let data = try Value.parse(event["payload"]!.text)
      try require(
        event["family"] == .string("inventory-basis") && event["scope_kind"] == .string("inventory")
          && event["scope_key"] == consumer["subject"]
          && (kind != "basis-clock"
            || (data["after"]["sourceID"] == event["after_id"]
              && data["after"]["effective"] == .string(effective))),
        "condition_input_integrity",
        "The exact opening-basis event or eligibility instant is inconsistent.")
    }
  }
}
