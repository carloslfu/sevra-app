import Foundation

extension Workbook {
  func fileReferenceCoverageStatus(_ origin: String) throws -> Value {
    let row = try db.execute(
      "SELECT s.id,s.input_id,s.coverage,i.extraction_parser,i.extraction_state,i.truncated FROM file_reference_heads h JOIN file_reference_sets s ON s.id=h.set_id JOIN file_reference_inputs i ON i.id=s.input_id WHERE h.origin_id=?",
      [.string(origin)]
    ).first
    return .object([
      "snapshot": row.map(Value.object) ?? .null, "latestExtraction": try extractionStatus(origin),
      "notice": .string(
        "Coverage applies to supported links in the retained extraction only; it does not cover embedded hyperlinks or unextracted content. A failed or running retry can retain the previous snapshot."
      ),
    ])
  }

  func incomingFileReferenceLinks(
    _ anchor: [String: Value], targetScope: ReferenceTargetScope,
    historical: Bool, filters: [(String, String?)], after: Value, limit: Int,
    cancellation: Cancellation
  ) throws -> [(Value, Value)] {
    var predicate = "r.target_workbook=? AND r.target_logical=? AND r.resolution='bound'"
    var args: [Value] = [.string(id), anchor["logical_id"]!]
    if !historical { predicate += " AND r.current_origin=1" }
    if targetScope == .exact {
      predicate += " AND (r.target_version=? OR (r.target_mode='live' AND ?=1))"
      args += [anchor["id"]!, anchor["is_current"]!]
    }
    predicate += " AND i.kind NOT IN ('request','annotation')"
    for (column, value) in filters {
      if let value {
        predicate += " AND i.\(column)=?"
        args.append(.string(value))
      }
    }
    let index = historical ? "file_reference_incoming_history" : "file_reference_incoming_current"
    let origins = try db.execute(
      "SELECT DISTINCT r.origin_id FROM file_reference_index r INDEXED BY \(index) JOIN items i ON i.id=r.origin_id WHERE \(predicate) AND r.origin_id>? ORDER BY r.origin_id LIMIT ?",
      args + [after, .number(Double(limit + 1))])
    return try origins.map { candidate in
      try cancellation.check()
      let origin = candidate["origin_id"]!
      guard let set = try fileReferenceSet(origin.text) else {
        throw SevraError("integrity", "An indexed file annotation is missing.")
      }
      let matches = try fileReferenceRows(set).filter { row in
        row["resolution"]?.text == "bound" && row["target_workbook"]?.text == id
          && row["target_logical"] == anchor["logical_id"]
          && (targetScope == .logical || row["target_version"] == anchor["id"]
            || (row["target_mode"]?.text == "live" && anchor["is_current"]?.int == 1))
      }
      guard let first = matches.first else {
        throw SevraError(
          "integrity", "Indexed file references differ from their saved annotations.")
      }
      let reference = try decodeReference(first)
      let metadata = try db.execute(
        "SELECT \(Self.referenceMetadata) FROM items i JOIN heads h ON h.logical_id=i.logical_id WHERE i.id=?",
        [origin]
      ).first!
      return (
        .object([
          "evidence": .object(metadata), "mentionCount": .number(Double(matches.count)),
          "firstReferenceID": .string(reference.id), "snapshotID": set["id"]!,
          "snapshotKind": .string("extracted"),
          "label": .string(reference.label),
          "locator": .string(
            first["source_locator"]!.text
              + "; scalar=\(reference.startScalar); count=\(reference.scalarCount)"),
          "discoveryReason": .string("mention"),
          "discoveryScopes": .array([.string("extracted_text")]),
        ]), origin
      )
    }
  }

  public func resolveFileReference(
    _ referenceID: String, originVersionID: String,
    snapshotID: String? = nil, cancellation: Cancellation = .init()
  ) throws -> Value {
    try Self.validateReferenceIdentity(referenceID)
    return try synchronized(cancellation: cancellation) {
      try db.budget(cancellation: cancellation, seconds: 3) {
        try db.readTransaction {
          try exactReferenceOrigin(originVersionID)
          guard let set = try fileReferenceSet(originVersionID, snapshotID: snapshotID),
            let row = try fileReferenceRows(set).first(where: {
              $0["reference_id"]?.text == referenceID
            })
          else {
            throw SevraError(
              "reference_not_found", "The reference is absent from this extracted annotation.")
          }
          let reference = try decodeReference(row)
          var destination: Value = .null
          if reference.resolution == .bound {
            try require(
              reference.targetWorkbookID == id, "integrity",
              "A local reference changed workbook identity.")
            let predicate =
              reference.targetMode == .live ? "i.id=h.item_id AND i.logical_id=?" : "i.id=?"
            let identity =
              reference.targetMode == .live ? reference.targetLogicalID : reference.targetVersionID
            destination =
              try db.execute(
                "SELECT \(Self.referenceMetadata) FROM items i JOIN heads h ON h.logical_id=i.logical_id WHERE \(predicate)",
                [identity.map(Value.string) ?? .null]
              ).first.map(Value.object) ?? .null
          }
          return .object([
            "referenceID": .string(referenceID), "originVersionID": .string(originVersionID),
            "snapshotID": set["id"]!,
            "inputID": set["input_id"]!, "region": row["region_ordinal"]!,
            "label": .string(reference.label),
            "locator": .string(
              row["source_locator"]!.text
                + "; scalar=\(reference.startScalar); count=\(reference.scalarCount)"),
            "resolution": .string(reference.resolution.rawValue), "destination": destination,
            "detail": .string(
              "Navigation metadata only. Read the exact destination before citing. No external workbook, file or network address is opened."
            ),
          ])
        }
      }
    }
  }
}
