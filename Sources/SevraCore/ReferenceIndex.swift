import Foundation

extension Workbook {
  /// The projection can be replaced without reinterpreting a saved binding.
  func refreshReferenceIndex(_ origin: String) throws {
    try db.execute("DELETE FROM reference_index WHERE origin_id=?", [.string(origin)])
    guard let set = try currentReferenceSet(origin) else { return }
    try db.execute(
      "INSERT INTO reference_index SELECT ?,reference_id,set_id,ordinal,EXISTS(SELECT 1 FROM heads WHERE item_id=?),target_workbook,target_mode,target_logical,target_version,resolution FROM reference_bindings WHERE set_id=?",
      [.string(origin), .string(origin), .string(set)])
    try db.execute(
      "INSERT INTO reference_coverage SELECT origin_id,id,parser,body_hash,coverage,detail,created FROM reference_sets WHERE id=? ON CONFLICT(origin_id) DO UPDATE SET set_id=excluded.set_id,parser=excluded.parser,body_hash=excluded.body_hash,state=excluded.state,detail=excluded.detail,updated=excluded.updated",
      [.string(set)])
  }

  func indexReferenceBody(_ origin: String, text: String, cancellation: Cancellation = .init())
    throws
  {
    // An existing annotation is authority, including unresolved choices. Reindexing
    // must never bind a formerly missing name or replace a user selection.
    if try currentReferenceSet(origin) != nil { return }
    if try db.scalar("SELECT count(*) FROM reference_coverage WHERE origin_id=?", [.string(origin)])
      .int == 1
    {
      return
    }
    let parsed = try InlineReferenceParser.parse(text, cancellation: cancellation)
    let selections = try availableReferenceSelections(parsed.selections, cancellation: cancellation)
    if !selections.isEmpty {
      _ = try writeReferenceSelections(
        origin, selections: selections, previous: nil,
        parser: InlineReferenceParser.identity, coverage: parsed.state, detail: parsed.detail)
    } else {
      try storeReferenceCoverage(
        origin, hash: parsed.state == "unsupported" ? nil : ToolResultProjection.digest(text),
        state: parsed.state, detail: parsed.detail)
    }
  }

  private func storeReferenceCoverage(
    _ origin: String, hash: String?, state: String, detail: String
  ) throws {
    try db.execute(
      "INSERT INTO reference_coverage VALUES(?,NULL,?,?,?,?,?)",
      [
        .string(origin), .string(InlineReferenceParser.identity), hash.map(Value.string) ?? .null,
        .string(state), .string(detail), .string(timestamp()),
      ])
  }

  /// First-time parsing of a stored body is explicit and bounded. Already saved
  /// choices are reused; this operation is not a name-resolution retry.
  @discardableResult public func indexReferences(
    _ originVersionID: String, token: String = identifier(), cancellation: Cancellation = .init()
  ) throws -> ReferenceSnapshot {
    try Self.validateReferenceIdentity(originVersionID)
    let result = try mutation(
      "index_references", token: token, request: .string(originVersionID),
      cancellation: cancellation
    ) {
      try exactReferenceOrigin(originVersionID)
      let metadata = try db.execute(
        "SELECT kind,length(CAST(body AS BLOB)) AS bytes FROM items WHERE id=?",
        [.string(originVersionID)]
      ).first!
      try require(
        !["row", "request", "annotation"].contains(metadata["kind"]!.text), "reference_scope",
        "This internal item is outside body-link indexing.")
      if (metadata["bytes"]?.int ?? Int.max) > Self.referenceBodyLimit {
        if try db.scalar(
          "SELECT count(*) FROM reference_coverage WHERE origin_id=?", [.string(originVersionID)]
        ).int == 0 {
          try storeReferenceCoverage(
            originVersionID, hash: nil, state: "unsupported",
            detail: "The body exceeds the bounded link-parser size. Original text is retained.")
        }
      } else {
        try indexReferenceBody(
          originVersionID, text: referenceBody(originVersionID), cancellation: cancellation)
      }
      return try JSONDecoder().decode(
        Value.self,
        from: JSONEncoder().encode(readReferenceSnapshot(originVersionID, snapshotID: nil)))
    }
    return try JSONDecoder().decode(ReferenceSnapshot.self, from: Data(result.json().utf8))
  }

  /// Catch up a migrated workbook a page at a time, committing complete origins.
  /// Stop/restart skips retained completed coverage rather than replaying bindings.
  public func indexReferenceBodies(
    afterID: String? = nil, limit: Int = 20, cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      limit > 0 && limit <= 50, "reference_limit", "Index at most 50 body versions per page.")
    if let afterID { try Self.validateReferenceIdentity(afterID) }
    let candidates = try synchronized(cancellation: cancellation) {
      try db.budget(cancellation: cancellation, seconds: 3) {
        try db.execute(
          "SELECT i.id FROM items i LEFT JOIN reference_coverage c ON c.origin_id=i.id WHERE c.origin_id IS NULL AND i.kind NOT IN ('row','submission',\(Item.technicalKindSQL)) AND i.id>? ORDER BY i.id LIMIT ?",
          [.string(afterID ?? ""), .number(Double(limit + 1))])
      }
    }
    var processed: [Value] = []
    for row in candidates.prefix(limit) {
      try cancellation.check()
      _ = try indexReferences(row["id"]!.text, cancellation: cancellation)
      processed.append(row["id"]!)
    }
    return .object([
      "scope": .string("item_body"), "processed": .array(processed),
      "nextAfterID": candidates.count > limit ? processed.last! : .null,
      "notice": .string(
        "This indexes stored item bodies only. Extracted file contents have separate coverage. No name is automatically resolved."
      ),
    ])
  }

  /// Rebuild current-annotation lookup rows from canonical bindings. No parsing,
  /// model call, external access, new Source or target resolution occurs.
  public func rebuildReferenceIndex(cancellation: Cancellation = .init()) throws {
    _ = try mutation("rebuild_reference_index", cancellation: cancellation) {
      try db.execute("DELETE FROM reference_index")
      try db.execute(
        "INSERT INTO reference_index SELECT s.origin_id,r.reference_id,r.set_id,r.ordinal,EXISTS(SELECT 1 FROM heads h WHERE h.item_id=s.origin_id),r.target_workbook,r.target_mode,r.target_logical,r.target_version,r.resolution FROM reference_bindings r JOIN reference_sets s ON s.id=r.set_id JOIN reference_heads h ON h.set_id=s.id"
      )
      try db.execute(
        "INSERT INTO reference_coverage SELECT h.origin_id,s.id,s.parser,s.body_hash,s.coverage,s.detail,s.created FROM reference_heads h JOIN reference_sets s ON s.id=h.set_id WHERE 1 ON CONFLICT(origin_id) DO UPDATE SET set_id=excluded.set_id,parser=excluded.parser,body_hash=excluded.body_hash,state=excluded.state,detail=excluded.detail,updated=excluded.updated"
      )
      try rebuildFileReferenceIndex(cancellation: cancellation)
      return .bool(true)
    }
  }

  func verifyReferenceIndex() throws {
    let expected =
      "SELECT s.origin_id,r.reference_id,r.set_id,r.ordinal,EXISTS(SELECT 1 FROM heads h WHERE h.item_id=s.origin_id),r.target_workbook,r.target_mode,r.target_logical,r.target_version,r.resolution FROM reference_bindings r JOIN reference_sets s ON s.id=r.set_id JOIN reference_heads h ON h.set_id=s.id"
    let actual =
      "SELECT origin_id,reference_id,set_id,ordinal,current_origin,target_workbook,target_mode,target_logical,target_version,resolution FROM reference_index"
    try require(
      try db.execute(expected + " EXCEPT " + actual + " LIMIT 1").isEmpty
        && db.execute(actual + " EXCEPT " + expected + " LIMIT 1").isEmpty,
      "integrity", "The reference index differs from saved bindings. Rebuild the reference index.")
    try require(
      try db.execute(
        "SELECT h.origin_id FROM reference_heads h LEFT JOIN reference_coverage c ON c.origin_id=h.origin_id WHERE c.set_id IS NULL OR c.set_id!=h.set_id LIMIT 1"
      ).isEmpty,
      "integrity", "Reference coverage is missing its saved annotation version.")
    try require(
      try db.execute(
        "SELECT c.origin_id FROM reference_coverage c JOIN reference_sets s ON s.id=c.set_id WHERE c.origin_id!=s.origin_id OR c.parser!=s.parser OR c.body_hash!=s.body_hash OR c.state!=s.coverage OR c.detail!=s.detail LIMIT 1"
      ).isEmpty,
      "integrity", "Reference coverage differs from its annotation snapshot.")
    var after = ""
    while true {
      let rows = try db.execute(
        "SELECT origin_id,parser,body_hash,state FROM reference_coverage WHERE set_id IS NULL AND origin_id>? ORDER BY origin_id LIMIT 64",
        [.string(after)])
      if rows.isEmpty { break }
      for row in rows {
        let origin = row["origin_id"]!.text
        let bytes =
          try db.scalar(
            "SELECT length(CAST(body AS BLOB)) FROM items WHERE id=?", [.string(origin)]
          ).int ?? Int.max
        try require(
          row["parser"]!.text == InlineReferenceParser.identity, "integrity",
          "Unsupported empty reference coverage parser.")
        if bytes > Self.referenceBodyLimit {
          try require(
            row["state"]!.text == "unsupported" && row["body_hash"] == .null, "integrity",
            "An oversized body claims completed link coverage.")
        } else {
          let body = try referenceBody(origin)
          let parsed = try InlineReferenceParser.parse(body)
          try require(
            row["body_hash"]!.text == ToolResultProjection.digest(body) && parsed.selections.isEmpty
              && parsed.state == row["state"]!.text,
            "integrity", "Empty reference coverage no longer matches its original body.")
        }
        after = origin
      }
    }
  }
}
