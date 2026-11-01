import Foundation

extension Workbook {
  /// Annotate a Source without changing its original text. Records publish their
  /// bindings with a new text version instead. Nil expectedSnapshotID explicitly
  /// means no snapshot may exist. Retries retain the original receipt.
  @discardableResult public func annotateReferences(
    _ originVersionID: String, selections: [ReferenceSelection], expectedSnapshotID: String?,
    token: String = identifier(), cancellation: Cancellation = .init()
  ) throws -> ReferenceSnapshot {
    try Self.validateReferenceIdentity(originVersionID)
    if let expectedSnapshotID { try Self.validateReferenceIdentity(expectedSnapshotID) }
    let request: Value = .object([
      "originVersionID": .string(originVersionID),
      "selections": try Self.referenceSelectionsValue(selections),
      "expectedSnapshotID": expectedSnapshotID.map(Value.string) ?? .null,
    ])
    let result = try mutation(
      "reference_annotation", token: token, request: request, cancellation: cancellation
    ) {
      try exactReferenceOrigin(originVersionID)
      try require(
        try db.scalar("SELECT category FROM items WHERE id=?", [.string(originVersionID)]).text
          == "source",
        "reference_annotation",
        "Record links belong to an immutable text version. Save a revised document with its references."
      )
      let current = try currentReferenceSet(originVersionID)
      try require(
        current == expectedSnapshotID, "stale_reference",
        "Reference annotations changed. Refresh before applying your choices.")
      return .string(
        try writeReferenceSelections(originVersionID, selections: selections, previous: current))
    }
    // Saved by now, so a late Stop must not read as a failed save.
    return try referenceSnapshot(originVersionID, snapshotID: result.text)
  }

  func publishInitialReferences(
    _ origin: String, selections: [ReferenceSelection], inheritedOrigin: String?
  ) throws {
    try require(
      try currentReferenceSet(origin) == nil, "integrity",
      "Initial reference annotations were already published.")
    let inherited = try inheritedOrigin.map { try readReferenceSnapshot($0, snapshotID: nil) }
    _ = try writeReferenceSelections(
      origin, selections: selections, previous: nil, inherited: inherited)
  }

  func referenceBody(_ origin: String) throws -> String {
    try require(
      (try db.scalar("SELECT length(CAST(body AS BLOB)) FROM items WHERE id=?", [.string(origin)])
        .int ?? Int.max) <= Self.referenceBodyLimit,
      "reference_limit",
      "This body exceeds the first reference-annotation limit. Its original content remains available."
    )
    return try db.scalar("SELECT body FROM items WHERE id=?", [.string(origin)]).text
  }

  func normalizedReferenceBindings(
    _ selections: [ReferenceSelection], body: String, allowedIDs: Set<String> = []
  ) throws -> [[String: Value]] {
    _ = try Self.referenceSelectionsValue(selections)
    let scalars = Array(body.unicodeScalars)
    var usedIDs = Set<String>()
    var previousEnd = 0
    var bindings: [[String: Value]] = []
    for selection in selections {
      let start = selection.startScalar
      let count = selection.scalarCount
      try require(
        start >= previousEnd && start <= scalars.count && count > 0 && count <= 1024
          && count <= scalars.count - start,
        "reference_range",
        "Choose nonoverlapping labels in body order using exact Unicode scalar coordinates.")
      let label = String(String.UnicodeScalarView(scalars[start..<(start + count)]))
      try require(
        label.utf8.count <= 1024, "reference_limit", "A reference label is limited to 1024 bytes.")
      previousEnd = start + count
      if let referenceID = selection.id {
        try require(
          allowedIDs.contains(referenceID), "reference_identity",
          "Only a prior occurrence can retain its reference identity.")
      }
      let referenceID = selection.id ?? identifier()
      try require(
        usedIDs.insert(referenceID).inserted, "reference_identity",
        "A reference identity occurs twice in this body.")
      var row: [String: Value] = [
        "reference_id": .string(referenceID), "start_scalar": .number(Double(start)),
        "scalar_count": .number(Double(count)), "label": .string(label),
        "lookup_text": .string(selection.lookup ?? label), "target_workbook": .null,
        "target_mode": .null, "target_logical": .null, "target_version": .null,
        "resolution": .string("unresolved"),
      ]
      if let target = selection.target {
        let workbook = target.workbookID ?? id
        row["target_workbook"] = .string(workbook)
        row["target_mode"] = .string(target.mode.rawValue)
        row[target.mode == .live ? "target_logical" : "target_version"] = .string(target.identity)
        row["resolution"] = .string(workbook == id ? "bound" : "external")
        if workbook == id {
          let column = target.mode == .live ? "logical_id" : "id"
          guard
            let item = try db.execute(
              "SELECT id,logical_id FROM items WHERE \(column)=? LIMIT 1",
              [.string(target.identity)]
            ).first
          else {
            throw SevraError(
              "reference_target",
              "Choose an existing stable local target. Names are not identities.")
          }
          row["target_logical"] = item["logical_id"]!
        }
      }
      bindings.append(row)
    }
    return bindings
  }

  func writeReferenceSelections(
    _ origin: String, selections: [ReferenceSelection], previous: String?,
    inherited: ReferenceSnapshot? = nil, parser: String = "explicit-selections-v1",
    coverage: String = "partial",
    detail: String = "Explicit selections only. Automatic mention parsing has not run."
  ) throws -> String {
    _ = try Self.referenceSelectionsValue(selections)
    let body = try referenceBody(origin)
    let prior = try readReferenceSnapshot(origin, snapshotID: previous)
    let allowedIDs = Set((prior.references + (inherited?.references ?? [])).map(\.id))
    let bindings = try normalizedReferenceBindings(selections, body: body, allowedIDs: allowedIDs)
    let hash = ToolResultProjection.digest(body)
    var evidenceData: [String: Value] = [
      "originVersionID": .string(origin), "bodyHash": .string(hash),
      "previousSnapshotID": previous.map(Value.string) ?? .null,
      "previousOriginSnapshotID": inherited?.id.map(Value.string) ?? .null,
      "references": .array(bindings.map(Value.object)),
    ]
    if parser != "explicit-selections-v1" {
      evidenceData["parser"] = .string(parser)
      evidenceData["coverage"] = .string(coverage)
    }
    let evidence = try insertItem(
      category: "source", kind: "annotation",
      title: parser == "explicit-selections-v1" ? "Reference choices" : "Reference parse",
      text: parser == "explicit-selections-v1"
        ? "Explicit reference selections for an immutable item version."
        : "Deterministic body-link parsing event for an immutable item version. This does not establish a business relationship.",
      data: .object(evidenceData), meaning: "actual", status: "accepted", scenario: "actual",
      inputs: [],
      transformation: parser == "explicit-selections-v1" ? "reference-selection-v1" : parser,
      controlInputs: [origin])
    let set = identifier()
    try db.execute(
      "INSERT INTO reference_sets VALUES(?,?,?,?,?,?,?,?,?,?,?)",
      [
        .string(set), .string(origin), .number(Double(prior.version + 1)),
        previous.map(Value.string) ?? .null, .null, .string(hash),
        .string(parser), .string(coverage), .string(detail),
        .string(evidence), .string(timestamp()),
      ])
    for (ordinal, row) in bindings.enumerated() {
      try db.execute(
        "INSERT INTO reference_bindings VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
        [
          .string(set), row["reference_id"]!, .number(Double(ordinal)), row["start_scalar"]!,
          row["scalar_count"]!, row["label"]!, row["lookup_text"]!, row["target_workbook"]!,
          row["target_mode"]!, row["target_logical"]!, row["target_version"]!, row["resolution"]!,
        ])
    }
    try db.execute(
      "INSERT INTO reference_heads VALUES(?,?) ON CONFLICT(origin_id) DO UPDATE SET set_id=excluded.set_id",
      [.string(origin), .string(set)])
    try refreshReferenceIndex(origin)
    return set
  }

  /// Identical bytes can carry bindings through status/rename/Undo versions.
  /// Changed free text does not guess occurrence alignment or name resolution.
  func inheritReferences(from origin: String, to destination: String, text: String) throws {
    guard let set = try currentReferenceSet(origin) else { return }
    let snapshot = try readReferenceSnapshot(origin, snapshotID: set)
    guard snapshot.bodyHash == ToolResultProjection.digest(text) else { return }
    let inherited = identifier()
    try db.execute(
      "INSERT INTO reference_sets SELECT ?,?,1,NULL,id,body_hash,parser,coverage,detail,source_id,? FROM reference_sets WHERE id=?",
      [.string(inherited), .string(destination), .string(timestamp()), .string(set)])
    try db.execute(
      "INSERT INTO reference_bindings SELECT ?,reference_id,ordinal,start_scalar,scalar_count,label,lookup_text,target_workbook,target_mode,target_logical,target_version,resolution FROM reference_bindings WHERE set_id=?",
      [.string(inherited), .string(set)])
    try db.execute(
      "INSERT INTO reference_heads VALUES(?,?)", [.string(destination), .string(inherited)])
    try refreshReferenceIndex(destination)
  }

  /// All annotation versions remain verifiable without using titles, FTS or a model.
  func verifyReferences() throws {
    try require(
      try db.scalar(
        "SELECT count(*) FROM reference_heads h JOIN reference_sets s ON s.id=h.set_id WHERE h.origin_id!=s.origin_id OR EXISTS(SELECT 1 FROM reference_sets n WHERE n.origin_id=s.origin_id AND n.version>s.version)"
      ).int == 0,
      "integrity", "Reference annotation heads are inconsistent.")
    try require(
      try db.scalar(
        "SELECT count(*) FROM reference_sets s WHERE NOT EXISTS(SELECT 1 FROM reference_heads h WHERE h.origin_id=s.origin_id)"
      ).int == 0,
      "integrity", "A reference annotation has no retained head.")
    var after = 0
    while true {
      let batch = try db.execute(
        "SELECT rowid AS sequence,* FROM reference_sets WHERE rowid>? ORDER BY rowid LIMIT 64",
        [.number(Double(after))])
      if batch.isEmpty { break }
      for row in batch {
        let origin = row["origin_id"]!.text
        let set = row["id"]!.text
        let snapshot = try readReferenceSnapshot(origin, snapshotID: set)
        let body = try referenceBody(origin)
        try require(
          snapshot.bodyHash == ToolResultProjection.digest(body), "integrity",
          "Reference labels no longer address their original body.")
        if let previous = snapshot.previousID {
          let prior = try readReferenceSnapshot(origin, snapshotID: previous)
          try require(
            prior.version + 1 == snapshot.version, "integrity",
            "Reference annotation history is inconsistent.")
        } else {
          try require(
            snapshot.version == 1, "integrity", "Reference annotation history is incomplete.")
        }
        try require(
          (snapshot.parser == "explicit-selections-v1" && snapshot.coverage == "partial")
            || (snapshot.parser == InlineReferenceParser.identity
              && ["ready", "partial"].contains(snapshot.coverage)),
          "integrity", "Unsupported reference parsing or coverage claim.")
        let source = try item(snapshot.sourceID!)
        try require(
          source.id == snapshot.sourceID && source.category == "source"
            && source.kind == "annotation", "integrity",
          "Reference choices lack their original Source.")
        if let parent = snapshot.inheritedFrom {
          guard
            let inheritedRow = try db.execute(
              "SELECT origin_id,rowid AS sequence FROM reference_sets WHERE id=?", [.string(parent)]
            ).first
          else {
            throw SevraError("integrity", "Inherited reference annotations are missing.")
          }
          let inherited = try readReferenceSnapshot(
            inheritedRow["origin_id"]!.text, snapshotID: parent)
          try require(
            inherited.bodyHash == snapshot.bodyHash && inherited.sourceID == snapshot.sourceID
              && inherited.references == snapshot.references && snapshot.version == 1
              && inheritedRow["sequence"]!.int! < row["sequence"]!.int!
              && zip(inherited.references, snapshot.references).allSatisfy {
                $0.lookup.utf8.elementsEqual($1.lookup.utf8)
              },
            "integrity", "Inherited reference annotations changed their bindings.")
        } else {
          try require(
            source.data["originVersionID"].text == origin
              && source.data["bodyHash"].text == snapshot.bodyHash
              && source.data["previousSnapshotID"].string == snapshot.previousID,
            "integrity", "Reference choices no longer match their annotation Source.")
          let stored = try db.execute(
            "SELECT reference_id,start_scalar,scalar_count,label,lookup_text,target_workbook,target_mode,target_logical,target_version,resolution FROM reference_bindings WHERE set_id=? ORDER BY ordinal",
            [.string(set)])
          try require(
            Data(Value.array(stored.map(Value.object)).json().utf8)
              == Data(source.data["references"].json().utf8), "integrity",
            "Reference bindings changed after selection.")
          if snapshot.parser == InlineReferenceParser.identity {
            let parsed = try InlineReferenceParser.parse(body)
            try require(
              source.data["parser"].text == snapshot.parser
                && source.data["coverage"].text == snapshot.coverage
                && parsed.state == snapshot.coverage
                && parsed.selections.count == snapshot.references.count,
              "integrity", "Reference parsing no longer matches its saved input.")
            for (selection, reference) in zip(parsed.selections, snapshot.references) {
              try require(
                selection.startScalar == reference.startScalar
                  && selection.scalarCount == reference.scalarCount
                  && (selection.lookup ?? "").utf8.elementsEqual(reference.lookup.utf8),
                "integrity", "Parsed reference locations changed.")
              if reference.resolution != .unresolved {
                guard let target = selection.target else {
                  throw SevraError("integrity", "A parsed name acquired an unselected binding.")
                }
                let workbook = target.workbookID ?? id
                try require(
                  workbook == reference.targetWorkbookID && target.mode == reference.targetMode
                    && target.identity
                      == (target.mode == .live
                        ? reference.targetLogicalID : reference.targetVersionID),
                  "integrity", "A parsed stable route changed its target.")
              }
            }
          }
        }
        let scalars = Array(body.unicodeScalars)
        var end = 0
        for reference in snapshot.references {
          try Self.validateReferenceIdentity(reference.id)
          let start = reference.startScalar
          let count = reference.scalarCount
          try require(
            start >= end && start <= scalars.count && count > 0 && count <= 1024
              && count <= scalars.count - start, "integrity", "Invalid reference label coordinates."
          )
          let text = String(String.UnicodeScalarView(scalars[start..<(start + count)]))
          try require(
            text.utf8.elementsEqual(reference.label.utf8) && text.utf8.count <= 1024
              && reference.lookup.utf8.count <= 1024, "integrity",
            "A reference label changed its original bytes.")
          end = start + count
          if reference.resolution == .bound {
            try require(
              reference.targetWorkbookID == id, "integrity", "A local reference changed workbook.")
            let target = try db.execute(
              "SELECT logical_id FROM items WHERE \(reference.targetMode == .live ? "logical_id" : "id")=? LIMIT 1",
              [
                .string(
                  reference.targetMode == .live
                    ? reference.targetLogicalID! : reference.targetVersionID!)
              ]
            ).first
            try require(
              target?["logical_id"]?.text == reference.targetLogicalID, "integrity",
              "A bound reference lost its stable target.")
          } else if reference.resolution == .external {
            try require(
              reference.targetWorkbookID != id, "integrity", "A foreign reference changed workbook."
            )
          }
        }
        after = row["sequence"]!.int!
      }
    }
    try verifyReferenceIndex()
  }
}
