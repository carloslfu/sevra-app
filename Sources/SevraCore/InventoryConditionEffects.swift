import Foundation

extension Workbook {
  func inventoryConditionEligible(_ row: [String: Value], work: InventoryConditionWork) -> Bool {
    guard let basisTime = work.basis["effective"].string, basisTime <= work.through,
      let effective = row["effective"]?.string
    else { return false }
    return effective > basisTime && effective <= work.through
  }

  func updateInventoryConditionEffect(
    _ consumer: [String: Value], event: [String: Value], work: inout InventoryConditionWork
  ) throws {
    let identity = [consumer["id"]!, event["logical_id"]!]
    let previous = try db.execute(
      "SELECT * FROM condition_effects WHERE consumer_id=? AND logical_id=?", identity
    ).first
    let expectedBefore = try conditionInputEffect(
      event["before_id"]!, subject: consumer["subject"]!.text)
    try require(
      previous?["item_id"] == expectedBefore?["item_id"], "condition_integrity",
      "The inventory projection lost the exact prior settled effect.")
    // Every settled revision, including a generic cross-scope replacement, can
    // remove the old logical effect. Only an exact accepted actual adds one.
    if let previous {
      if work.ready && !work.rebuildRequired, let total = work.quantity,
        inventoryConditionEligible(previous, work: work)
      {
        work.quantity = try conditionExactSum(total, previous["quantity"]!.text, subtract: true)
      }
      try db.execute("DELETE FROM condition_effects WHERE consumer_id=? AND logical_id=?", identity)
      work.effectCount -= 1
    }
    let effects = try db.execute(
      "SELECT f.* FROM items i JOIN effects f ON f.item_id=i.id WHERE i.id=? AND i.logical_id=? AND i.category='record' AND i.kind='movement' AND i.status='accepted' AND i.meaning='actual' AND i.scenario='actual' AND f.kind='inventory' AND f.subject=? LIMIT 2",
      [event["after_id"]!, event["logical_id"]!, consumer["subject"]!], maxRows: 2, maxBytes: 65_536
    )
    try require(
      effects.count <= 1, "condition_integrity", "A settled version has multiple inventory effects."
    )
    if previous != nil || !effects.isEmpty {
      try retainConditionInput(consumer, event: event, kind: "record-change", work: &work)
    }
    guard let effect = effects.first else { return }
    _ = try Numbers.decimal(effect["quantity"]!.text)
    try require(
      try BusinessTime.normalized(effect["effective"]!.text) == effect["effective"]!.text,
      "condition_integrity", "The inventory effect time is not normalized.")
    try require(
      work.effectCount < 10_000, "condition_projection_limit",
      "The condition projection is limited to 10,000 current effects. No partial observation was published."
    )
    if work.ready && !work.rebuildRequired, let total = work.quantity,
      inventoryConditionEligible(effect, work: work)
    {
      work.quantity = try conditionExactSum(total, effect["quantity"]!.text)
    }
    try db.execute(
      "INSERT INTO condition_effects VALUES(?,?,?,?,?,?,?,?)",
      [
        consumer["id"]!, event["logical_id"]!, event["after_id"]!, event["id"]!, event["batch_id"]!,
        effect["occurrence"]!, effect["quantity"]!, effect["effective"]!,
      ])
    work.effectCount += 1
  }

  func conditionExactSum(_ total: String, _ quantity: String, subtract: Bool = false) throws
    -> String
  {
    var lhs = try Numbers.decimal(total)
    var rhs = try Numbers.decimal(quantity)
    var result = Decimal()
    let error =
      subtract
      ? NSDecimalSubtract(&result, &lhs, &rhs, .plain) : NSDecimalAdd(&result, &lhs, &rhs, .plain)
    try require(
      error == .noError, "condition_precision",
      "The condition sum exceeds exact decimal precision. No rounded observation was published.")
    return try Numbers.string(Numbers.decimal(Numbers.string(result)))
  }
}
