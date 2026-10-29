import Foundation

extension Workbook {
  public func inventoryConditionInputs(
    _ observationID: String, after: String? = nil, limit: Int = 20,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      !observationID.isEmpty && observationID.utf8.count <= 256
        && (after == nil || (!after!.isEmpty && after!.utf8.count <= 256)),
      "condition_input", "Use an exact observation and its input cursor.")
    try require((1...50).contains(limit), "condition_limit", "Read one to 50 condition inputs.")
    return try readBusinessFeed(cancellation: cancellation) {
      let (row, observation) = try self.conditionInputObservation(observationID)
      let consumer = try self.inventoryConditionRow(row["consumer_id"]!.text)
      if let after {
        try require(
          try self.db.scalar(
            "SELECT EXISTS(SELECT 1 FROM condition_observation_inputs WHERE observation_id=? AND id=?)",
            [.string(observationID), .string(after)]
          ).int == 1, "condition_cursor", "Use an input from this exact observation.")
      }
      let rows = try self.db.execute(
        "SELECT id,payload FROM condition_observation_inputs WHERE observation_id=? AND id>? ORDER BY id LIMIT ?",
        [.string(observationID), .string(after ?? ""), .number(Double(limit + 1))],
        maxRows: limit + 1, maxBytes: 1_048_576)
      let page = Array(rows.prefix(limit))
      let entries = try page.map { entry -> Value in
        try cancellation.check()
        let value = try Value.parse(entry["payload"]!.text)
        try self.validateConditionInput(
          entry["id"]!.text, value: value, consumer: consumer,
          batch: row["batch_id"]!.string, effective: row["effective"]!.text)
        let inputs = Set([value["beforeID"], value["afterID"]].compactMap(\.string)).sorted()
        return .object([
          "id": entry["id"]!, "input": value, "inputIDs": .array(inputs.map(Value.string)),
        ])
      }
      let result: Value = .object([
        "observationID": .string(observationID), "consumerID": row["consumer_id"]!,
        "previousObservationID": observation["previousObservationID"],
        "previousCertainObservationID": observation["previousCertainObservationID"],
        "changeInputs": observation["changeInputs"], "entries": .array(entries),
        "hasMore": .bool(rows.count > limit),
        "nextCursor": rows.count > limit ? page.last!["id"]! : .null,
        "execution": .string("none"), "enabled": .bool(false),
      ])
      try self.boundedBusinessOutput(result)
      return result
    }
  }

  func conditionInputObservation(_ id: String) throws -> ([String: Value], Value) {
    guard
      let row = try db.execute(
        "SELECT *,CAST(rowid AS TEXT) AS observation_position FROM condition_observations WHERE id=?",
        [.string(id)],
        maxRows: 1, maxBytes: 1_048_576
      ).first
    else {
      throw SevraError("condition_observation", "The exact complete observation is missing.")
    }
    let observation = try Value.parse(row["payload"]!.text)
    let summary = observation["changeInputs"]
    let count = try db.scalar(
      "SELECT count(*) FROM (SELECT id FROM condition_observation_inputs WHERE observation_id=? LIMIT 10001)",
      [.string(id)]
    ).int!
    let overflow = summary["overflow"] == .bool(true)
    try require(
      count <= ConditionInput.limit && observation["id"] == .string(id)
        && observation["consumerID"] == row["consumer_id"]
        && observation["knowledgeBatchID"] == row["batch_id"]
        && observation["effectiveThrough"] == row["effective"]
        && summary
          == ConditionInput.summary(
            count: count, overflow: overflow,
            baseline: observation["previousCertainObservationID"] == .null,
            gap: observation["coverageGap"] == .bool(true) || observation["known"] == .bool(false))
        && (!overflow || count == ConditionInput.limit),
      "condition_input_integrity",
      "The complete observation lost its exact input count, coverage or coordinates.")
    let previous = try db.execute(
      "SELECT id,payload FROM condition_observations WHERE consumer_id=? AND rowid<CAST(? AS INTEGER) ORDER BY rowid DESC LIMIT 1",
      [row["consumer_id"]!, row["observation_position"]!], maxRows: 1, maxBytes: 1_048_576
    ).first
    let previousValue = try previous.map { try Value.parse($0["payload"]!.text) }
    let certain =
      previousValue?["known"] == .bool(true)
      ? previous!["id"]! : previousValue?["previousCertainObservationID"] ?? .null
    try require(
      (previous?["id"] ?? .null) == observation["previousObservationID"]
        && certain == observation["previousCertainObservationID"], "condition_input_integrity",
      "The observation lost its previous complete or certain observation.")
    return (row, observation)
  }

  func verifyConditionInputStorage() throws {
    let consumers = try db.execute("SELECT * FROM condition_consumers")
    for consumer in consumers {
      let work = try inventoryConditionWork(consumer)
      let count = try db.scalar(
        "SELECT count(*) FROM (SELECT id FROM condition_pending_inputs WHERE consumer_id=? LIMIT 10001)",
        [consumer["id"]!]
      ).int!
      try require(
        count == work.pendingInputCount && count <= ConditionInput.limit
          && (!work.inputOverflow || count == ConditionInput.limit)
          && (work.phase != "idle" || (count == 0 && !work.inputOverflow)),
        "condition_input_integrity", "The unfinished condition input window is inconsistent.")
      try verifyConditionInputRows(
        table: "condition_pending_inputs", ownerKey: "consumer_id",
        owner: consumer["id"]!.text, consumer: consumer, batch: work.pendingBatch ?? work.cursorID,
        effective: work.through)
    }
    var after = "0"
    while true {
      let rows = try db.execute(
        "SELECT id,CAST(rowid AS TEXT) AS position FROM condition_observations WHERE rowid>CAST(? AS INTEGER) ORDER BY rowid LIMIT 100",
        [.string(after)])
      if rows.isEmpty { break }
      for entry in rows {
        let (row, _) = try conditionInputObservation(entry["id"]!.text)
        let consumer = try inventoryConditionRow(row["consumer_id"]!.text)
        try verifyConditionInputRows(
          table: "condition_observation_inputs", ownerKey: "observation_id",
          owner: entry["id"]!.text, consumer: consumer, batch: row["batch_id"]!.string,
          effective: row["effective"]!.text)
        after = entry["position"]!.text
      }
    }
  }

  private func verifyConditionInputRows(
    table: String, ownerKey: String, owner: String,
    consumer: [String: Value], batch: String?, effective: String
  ) throws {
    var after = ""
    while true {
      let rows = try db.execute(
        "SELECT id,payload FROM \(table) WHERE \(ownerKey)=? AND id>? ORDER BY id LIMIT 100",
        [.string(owner), .string(after)], maxRows: 100, maxBytes: 2_097_152)
      if rows.isEmpty { break }
      for row in rows {
        try validateConditionInput(
          row["id"]!.text, value: Value.parse(row["payload"]!.text),
          consumer: consumer, batch: batch, effective: effective)
        after = row["id"]!.text
      }
    }
  }
}
