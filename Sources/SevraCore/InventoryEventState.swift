import Foundation

extension Workbook {
  /// An exact retained knowledge cutoff and an explicit effective-time cutoff.
  /// This bounded reconciliation oracle is not a per-poll condition evaluator.
  public func inventoryAtBusinessBatch(
    _ batchID: String, subject: String, effectiveThrough: String,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    let effectiveThrough = try BusinessTime.normalized(effectiveThrough)
    return try readBusinessFeed(cancellation: cancellation) {
      let batch = try businessBatchMetadata(batchID)
      let position = batch["position"]
      let basisEvent = try db.execute(
        "SELECT id,batch_id,after_id,payload FROM business_events WHERE scope_kind='inventory' AND scope_key=? AND family='inventory-basis' AND batch_position<=CAST(? AS INTEGER) ORDER BY batch_position DESC,ordinal DESC LIMIT 1",
        [.string(subject), position], maxRows: 1, maxBytes: 8_388_608
      ).first
      var result: [String: Value] = [
        "workbookID": .string(id), "knowledgeBatch": batch, "subject": .string(subject),
        "effectiveThrough": .string(effectiveThrough), "quantity": .null,
        "basis": .null, "effects": .array([]), "known": .bool(false),
        "coverage": .string("exact-retained-business-cutoff"), "execution": .string("inert"),
      ]
      guard let basisEvent else {
        result["reason"] = .string("unknown_basis")
        return try finishInventoryState(result)
      }
      let payload = try Value.parse(basisEvent["payload"]!.text)
      try require(
        Set(payload.object.keys) == ["before", "after"], "inventory_history_integrity",
        "The retained opening basis is malformed.")
      let basis = payload["after"]
      if basis == .null {
        try require(
          basisEvent["after_id"] == .null, "inventory_history_integrity",
          "The removed basis has an inconsistent input reference.")
        result["basis"] = .object([
          "eventID": basisEvent["id"]!, "batchID": basisEvent["batch_id"]!, "removed": .bool(true),
        ])
        result["reason"] = .string("unknown_basis")
        return try finishInventoryState(result)
      }
      try require(
        Set(basis.object.keys) == ["subject", "quantity", "effective", "sourceID"]
          && basis["subject"] == .string(subject) && basis["quantity"].string != nil
          && basis["effective"].string != nil && basis["sourceID"].string != nil
          && basis["sourceID"] == basisEvent["after_id"]
          && db.scalar("SELECT EXISTS(SELECT 1 FROM items WHERE id=?)", [basis["sourceID"]]).int
            == 1,
        "inventory_history_integrity", "The retained opening basis lost its exact input.")
      let basisTime = try BusinessTime.normalized(basis["effective"].text)
      try require(
        basisTime == basis["effective"].text, "inventory_history_integrity",
        "The retained opening time is not normalized.")
      var total = try Numbers.decimal(basis["quantity"].text)
      result["basis"] = .object([
        "eventID": basisEvent["id"]!, "batchID": basisEvent["batch_id"]!,
        "inputID": basis["sourceID"], "quantity": basis["quantity"],
        "effective": basis["effective"],
      ])
      guard basisTime <= effectiveThrough else {
        result["reason"] = .string("basis_not_effective")
        return try finishInventoryState(result)
      }
      // Later committed versions cannot mask this cutoff's settled state. The
      // anti-join is logical, across scopes, rather than against today's heads.
      let rows = try db.execute(
        """
        SELECT e.id AS event_id,e.batch_id,i.id AS item_id,i.logical_id,f.occurrence,f.quantity,f.effective
        FROM business_events e INDEXED BY business_events_scope
        CROSS JOIN items i CROSS JOIN effects f INDEXED BY effects_item
        WHERE i.id=e.after_id AND f.item_id=i.id
          AND e.scope_kind='inventory' AND e.scope_key=? AND e.family='record-settled'
          AND e.record_kind='movement' AND e.batch_position<=CAST(? AS INTEGER)
          AND i.category='record' AND i.kind='movement' AND i.status='accepted'
          AND i.meaning='actual' AND i.scenario='actual' AND f.subject=? AND f.kind='inventory'
          AND f.effective>? AND f.effective<=?
          AND NOT EXISTS(SELECT 1 FROM business_events n WHERE n.logical_id=e.logical_id
            AND n.family='record-settled' AND n.batch_position>e.batch_position
            AND n.batch_position<=CAST(? AS INTEGER))
        ORDER BY f.effective,i.id LIMIT 10001
        """,
        [
          .string(subject), position, .string(subject), .string(basisTime),
          .string(effectiveThrough), position,
        ],
        maxRows: 10_001, maxBytes: 8_388_608)
      try require(
        rows.count <= 10_000, "inventory_history_limit",
        "Historical reconciliation is limited to 10,000 contributing effects. No partial quantity was returned."
      )
      var occurrences: Set<String> = []
      var logicalIDs: Set<String> = []
      var effects: [Value] = []
      for row in rows {
        try cancellation.check()
        try require(
          occurrences.insert(row["occurrence"]!.text).inserted
            && logicalIDs.insert(row["logical_id"]!.text).inserted,
          "inventory_history_integrity", "The retained inventory duplicates a business occurrence.")
        total = try exactInventorySum(total, Numbers.decimal(row["quantity"]!.text))
        effects.append(
          .object([
            "eventID": row["event_id"]!, "batchID": row["batch_id"]!, "itemID": row["item_id"]!,
            "logicalID": row["logical_id"]!, "occurrence": row["occurrence"]!,
            "quantity": row["quantity"]!, "effective": row["effective"]!,
          ]))
      }
      result["known"] = .bool(true)
      result["quantity"] = .string(Numbers.string(total))
      result["effects"] = .array(effects)
      return try finishInventoryState(result)
    }
  }

  private func finishInventoryState(_ result: [String: Value]) throws -> Value {
    let value = Value.object(result)
    try boundedBusinessOutput(value)
    return value
  }

  private func exactInventorySum(_ total: Decimal, _ quantity: Decimal) throws -> Decimal {
    var lhs = total
    var rhs = quantity
    var sum = Decimal()
    try require(
      NSDecimalAdd(&sum, &lhs, &rhs, .plain) == .noError, "inventory_history_precision",
      "The historical quantity exceeds exact decimal precision. No rounded balance was returned.")
    return try Numbers.decimal(Numbers.string(sum))
  }
}
