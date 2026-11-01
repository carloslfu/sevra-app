import Foundation

extension Workbook {
  /// Scope filtering selects batches. Consumers still read each entire atomic
  /// batch before evaluating conditions or advancing their durable cursor.
  public func businessBatches(
    after cursor: String? = nil, limit: Int = 20, scopeKind: String? = nil,
    scopeKey: String? = nil, cancellation: Cancellation = .init()
  ) throws -> Value {
    try require((1...50).contains(limit), "business_limit", "Choose 1 to 50 business batches.")
    try require(
      (scopeKind == nil && scopeKey == nil)
        || (["record", "inventory", "dataset"].contains(scopeKind ?? "") && scopeKey != nil),
      "business_scope", "Choose both an exact scope kind and key, or neither.")
    let scopeKey =
      scopeKind == "inventory" ? scopeKey?.precomposedStringWithCanonicalMapping : scopeKey
    return try readBusinessFeed(cancellation: cancellation) {
      let position = try businessCursor(cursor)
      let tail = try businessTail()
      let candidates: [[String: Value]]
      if scopeKind == "record", let scopeKey {
        // A movement is scoped to its subject, so a record is found by its identity instead.
        candidates = try db.execute(
          "SELECT CAST(batch_position AS TEXT) AS position,batch_id AS id FROM business_events WHERE logical_id=? AND family='record-settled' AND batch_position>CAST(? AS INTEGER) GROUP BY batch_position ORDER BY batch_position LIMIT ?",
          [.string(scopeKey), .string(position), .number(Double(limit + 1))],
          maxRows: limit + 1, maxBytes: 1_048_576)
      } else if let scopeKind, let scopeKey {
        // Seek the sparse scope index, rather than scanning unrelated commits.
        candidates = try db.execute(
          "SELECT CAST(batch_position AS TEXT) AS position,batch_id AS id FROM business_events WHERE scope_kind=? AND scope_key=? AND batch_position>CAST(? AS INTEGER) GROUP BY batch_position ORDER BY batch_position LIMIT ?",
          [.string(scopeKind), .string(scopeKey), .string(position), .number(Double(limit + 1))],
          maxRows: limit + 1, maxBytes: 1_048_576)
      } else {
        candidates = try db.execute(
          "SELECT id,CAST(position AS TEXT) AS position FROM business_batches b WHERE b.position>CAST(? AS INTEGER) ORDER BY b.position LIMIT ?",
          [.string(position), .number(Double(limit + 1))], maxRows: limit + 1, maxBytes: 1_048_576)
      }
      let more = candidates.count > limit
      let batches = try candidates.prefix(limit).map { row -> Value in
        try cancellation.check()
        return try businessBatchMetadata(row["id"]!.text)
      }
      let result: Value = .object([
        "workbookID": .string(id), "policy": .string("business-versions-v1"),
        "coverage": .string("committed-semantic-feed"), "tail": tail,
        "scopeKind": scopeKind.map(Value.string) ?? .null,
        "scopeKey": scopeKey.map(Value.string) ?? .null, "batches": .array(batches),
        "hasMore": .bool(more),
        "nextCursor": more ? (batches.last?["id"] ?? .null) : tail["id"],
        "execution": .string("inert"),
      ])
      try boundedBusinessOutput(result)
      return result
    }
  }

  public func businessBatch(
    _ batchID: String, afterOrdinal: Int? = nil, limit: Int = 50,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try require((1...100).contains(limit), "business_limit", "Choose 1 to 100 business entries.")
    return try readBusinessFeed(cancellation: cancellation) {
      let batch = try businessBatchMetadata(batchID)
      if let afterOrdinal {
        try require(
          afterOrdinal >= 0 && afterOrdinal < 250_000
            && db.scalar(
              "SELECT EXISTS(SELECT 1 FROM business_events WHERE batch_id=? AND ordinal=?)",
              [.string(batchID), .number(Double(afterOrdinal))]
            ).int == 1,
          "business_cursor", "This entry cursor does not belong to the selected batch.")
      }
      let rows = try db.execute(
        "SELECT * FROM business_events WHERE batch_id=? AND ordinal>? ORDER BY ordinal LIMIT ?",
        [.string(batchID), .number(Double(afterOrdinal ?? -1)), .number(Double(limit + 1))],
        maxRows: limit + 1, maxBytes: 8_388_608)
      let more = rows.count > limit
      let events = try rows.prefix(limit).map { row -> Value in
        try cancellation.check()
        return .object([
          "id": row["id"]!, "ordinal": row["ordinal"]!, "family": row["family"]!,
          "scopeKind": row["scope_kind"]!, "scopeKey": row["scope_key"]!,
          "recordKind": row["record_kind"]!, "logicalID": row["logical_id"]!,
          "beforeID": row["before_id"]!, "afterID": row["after_id"]!,
          "payload": try Value.parse(row["payload"]!.text),
        ])
      }
      let result: Value = .object([
        "workbookID": .string(id), "batch": batch, "events": .array(events),
        "hasMore": .bool(more), "batchComplete": .bool(!more),
        "nextOrdinal": events.last?["ordinal"] ?? afterOrdinal.map { .number(Double($0)) } ?? .null,
        "execution": .string("inert"),
      ])
      try boundedBusinessOutput(result)
      return result
    }
  }

  func readBusinessFeed<T>(cancellation: Cancellation, _ body: () throws -> T) throws -> T {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.shortWait {
        try db.budget(cancellation: control, seconds: 3) { try db.readTransaction(body) }
      }
    }
  }
  private func businessCursor(_ cursor: String?) throws -> String {
    guard let cursor else { return "0" }
    guard
      let position = try db.scalar(
        "SELECT CAST(position AS TEXT) FROM business_batches WHERE id=?", [.string(cursor)]
      ).string
    else {
      throw SevraError("business_cursor", "This cursor does not belong to the workbook feed.")
    }
    return position
  }
  private func businessTail() throws -> Value {
    guard
      let row = try db.execute(
        "SELECT id,CAST(position AS TEXT) AS position FROM business_batches b ORDER BY b.position DESC LIMIT 1"
      ).first
    else { return .null }
    return .object(row)
  }
  func businessBatchMetadata(_ id: String) throws -> Value {
    guard
      let row = try db.execute(
        "SELECT id,CAST(position AS TEXT) AS position,recorded,actor,policy,(SELECT count(*) FROM business_events e WHERE e.batch_id=b.id) AS event_count FROM business_batches b WHERE id=?",
        [.string(id)], maxRows: 1, maxBytes: 65_536
      ).first
    else { throw SevraError("business_batch", "The selected business batch is missing.") }
    return .object([
      "id": row["id"]!, "position": row["position"]!, "recorded": row["recorded"]!,
      "actor": try Value.parse(row["actor"]!.text), "policy": row["policy"]!,
      "eventCount": row["event_count"]!, "atomic": .bool(true),
    ])
  }
  func boundedBusinessOutput(_ result: Value) throws {
    try require(
      try result.json().utf8.count <= 8_388_608, "business_limit",
      "Business output exceeds 8 MiB. Read fewer entries; the cursor has not advanced.")
  }
}
