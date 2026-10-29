import Foundation

extension Workbook {
  func verifyFileReferences() throws {
    try require(
      try db.execute(
        "SELECT h.origin_id FROM file_reference_heads h JOIN file_reference_sets s ON s.id=h.set_id WHERE h.origin_id!=s.origin_id OR EXISTS(SELECT 1 FROM file_reference_sets n WHERE n.origin_id=s.origin_id AND n.version>s.version) LIMIT 1"
      ).isEmpty,
      "integrity", "An extracted reference head does not select the latest annotation.")
    try require(
      try db.execute(
        "SELECT s.origin_id FROM file_reference_sets s LEFT JOIN file_reference_heads h ON h.origin_id=s.origin_id WHERE h.origin_id IS NULL LIMIT 1"
      ).isEmpty,
      "integrity", "An extracted reference history has no head.")
    try require(
      try db.execute(
        "SELECT r.origin_id FROM file_reference_index r LEFT JOIN file_reference_heads h ON h.origin_id=r.origin_id WHERE h.set_id IS NULL OR h.set_id!=r.set_id LIMIT 1"
      ).isEmpty,
      "integrity", "An extracted reference index has no matching canonical head.")
    var after = 0
    while true {
      let rows = try db.execute(
        "SELECT rowid AS sequence,id FROM file_reference_inputs WHERE rowid>? ORDER BY rowid LIMIT 32",
        [.number(Double(after))])
      if rows.isEmpty { break }
      for entry in rows {
        let input = try fileReferenceInput(entry["id"]!.text)
        _ = try fileReferenceRegions(input)
        try require(
          ["ready", "partial", "unsupported"].contains(input["extraction_state"]!.text)
            && input["extraction_parser"]!.text.utf8.count <= 1024
            && input["extraction_detail"]!.text.utf8.count <= 16_000,
          "integrity", "Invalid retained extraction identity.")
        try require(
          input["content_hash"]!.text
            == ToolResultProjection.digest(try fileReferenceInputIdentity(input).json()),
          "integrity", "Retained extraction text or identity changed.")
        try require(
          try db.scalar(
            "SELECT count(*) FROM items i JOIN assets a ON a.id=i.asset_id WHERE i.id=? AND i.asset_id=? AND a.hash=?",
            [input["origin_id"]!, input["asset_id"]!, input["asset_hash"]!]
          ).int == 1,
          "integrity", "Retained extraction no longer identifies its original asset.")
        try require(
          try db.scalar(
            "SELECT EXISTS(SELECT 1 FROM file_reference_sets WHERE input_id=?)", [input["id"]!]
          ).int == 1,
          "integrity", "Retained extraction has no annotation history.")
        after = entry["sequence"]!.int!
      }
    }
    after = 0
    while true {
      let rows = try db.execute(
        "SELECT rowid AS sequence,origin_id,id FROM file_reference_sets WHERE rowid>? ORDER BY rowid LIMIT 32",
        [.number(Double(after))])
      if rows.isEmpty { break }
      for entry in rows {
        let origin = entry["origin_id"]!.text
        let set = try fileReferenceSet(origin, snapshotID: entry["id"]!.text)!
        let input = try fileReferenceInput(set["input_id"]!.text)
        let regions = try fileReferenceRegions(input)
        let bindings = try fileReferenceRows(set)
        let version = set["version"]!.int ?? 0
        try require(
          input["origin_id"]?.text == origin && version > 0
            && set["version"] == .number(Double(version)), "integrity",
          "Invalid extracted annotation version or origin.")
        if let previous = set["previous_id"]?.string {
          try require(
            try db.scalar(
              "SELECT count(*) FROM file_reference_sets WHERE id=? AND origin_id=? AND version=? AND rowid<?",
              [
                .string(previous), .string(origin), .number(Double(version - 1)),
                entry["sequence"]!,
              ]
            ).int == 1,
            "integrity", "Extracted annotation history is not a versioned chain.")
        } else {
          try require(version == 1, "integrity", "Extracted annotation history is incomplete.")
        }
        let source = try item(set["source_id"]!.text)
        try require(
          source.category == "source" && source.kind == "annotation"
            && source.data["originVersionID"].text == origin
            && source.data["inputID"] == input["id"]
            && source.data["contentHash"] == input["content_hash"]
            && source.data["previousSnapshotID"] == (set["previous_id"] ?? .null)
            && source.data["parser"] == set["parser"] && source.data["coverage"] == set["coverage"]
            && Data(try source.data["references"].json().utf8)
              == Data(try Value.array(bindings.map(Value.object)).json().utf8),
          "integrity", "Extracted choices differ from their annotation Source.")
        if let inherited = source.data["inheritedSnapshotID"].string {
          guard
            let prior = try db.execute(
              "SELECT * FROM file_reference_sets WHERE id=? AND rowid<?",
              [.string(inherited), entry["sequence"]!]
            ).first
          else { throw SevraError("integrity", "Missing inherited extracted annotations.") }
          let priorInput = try fileReferenceInput(prior["input_id"]!.text)
          for key in [
            "asset_id", "asset_hash", "extraction_parser", "extraction_state", "extraction_detail",
            "truncated",
          ] {
            try require(
              priorInput[key] == input[key], "integrity", "Inherited extracted input changed.")
          }
          try require(
            try Value.parse(priorInput["regions"]!.text) == Value.parse(input["regions"]!.text)
              && prior["bindings"] == set["bindings"] && prior["parser"] == set["parser"]
              && prior["coverage"] == set["coverage"],
            "integrity", "Inherited extracted bindings changed.")
          if prior["origin_id"] != set["origin_id"] {
            try require(
              try db.scalar(
                "SELECT EXISTS(SELECT 1 FROM lineage WHERE child=? AND parent=? AND relation IN ('derives-from','supersedes'))",
                [.string(origin), prior["origin_id"]!]
              ).int == 1, "integrity",
              "Extracted bindings were inherited from an unrelated origin.")
          }
        }
        try require(
          Set(bindings.map { $0["reference_id"]!.text }).count == bindings.count, "integrity",
          "An extracted reference identity occurs twice.")
        var lastRegion = -1
        for (region, entries) in Dictionary(grouping: bindings, by: { $0["region_ordinal"]!.int! })
          .sorted(by: { $0.key < $1.key })
        {
          try require(
            region >= 0 && region < regions.count && region >= lastRegion, "integrity",
            "An extracted reference region is unavailable.")
          lastRegion = region
          let references = try entries.map { try decodeReference($0) }
          let selections = references.map { reference in
            ReferenceSelection(
              startScalar: reference.startScalar, scalarCount: reference.scalarCount,
              target: reference.targetMode.map { mode in
                ReferenceTarget(
                  mode: mode,
                  identity: (mode == .live ? reference.targetLogicalID : reference.targetVersionID)!,
                  workbookID: reference.targetWorkbookID)
              }, lookup: reference.lookup, id: reference.id)
          }
          let normalized = try normalizedReferenceBindings(
            selections, body: regions[region].text, allowedIDs: Set(references.map(\.id)))
          for (expected, actual) in zip(normalized, entries) {
            var row = actual
            row.removeValue(forKey: "region_ordinal")
            row.removeValue(forKey: "source_locator")
            try require(
              try Value.object(expected).json() == Value.object(row).json()
                && actual["source_locator"]?.text == regions[region].locator, "integrity",
              "Extracted label bytes, target or locator changed.")
          }
        }
        try require(
          bindings.map { $0["region_ordinal"]!.int! }
            == bindings.map { $0["region_ordinal"]!.int! }.sorted(), "integrity",
          "Extracted references are out of region order.")
        if set["parser"]?.text == Self.fileReferenceParser {
          try verifyAutomaticFileReferences(set, input: input, regions: regions, bindings: bindings)
        } else {
          try require(
            set["parser"]?.text == Self.fileReferenceManualParser
              && set["coverage"]?.text == "partial", "integrity",
            "Unsupported extracted reference parser or coverage.")
        }
        if try currentFileReferenceSet(origin) == set["id"]?.text {
          let current = try db.scalar(
            "SELECT EXISTS(SELECT 1 FROM heads WHERE item_id=?)", [.string(origin)])
          let expected = bindings.enumerated().map { ordinal, row in
            Value.object([
              "origin_id": .string(origin), "reference_id": row["reference_id"]!,
              "set_id": set["id"]!, "ordinal": .number(Double(ordinal)), "current_origin": current,
              "target_workbook": row["target_workbook"]!, "target_mode": row["target_mode"]!,
              "target_logical": row["target_logical"]!, "target_version": row["target_version"]!,
              "resolution": row["resolution"]!,
            ])
          }
          let actual = try db.execute(
            "SELECT * FROM file_reference_index WHERE origin_id=? ORDER BY ordinal",
            [.string(origin)]
          ).map(Value.object)
          try require(
            actual == expected, "integrity",
            "The extracted reference index differs from saved bindings. Rebuild the reference index."
          )
        }
        after = entry["sequence"]!.int!
      }
    }
  }

  private func verifyAutomaticFileReferences(
    _ set: [String: Value], input: [String: Value], regions: [Chunk], bindings: [[String: Value]]
  ) throws {
    var coverage =
      input["extraction_state"]?.text == "unsupported"
      ? "unsupported"
      : (input["extraction_state"]?.text == "ready" && input["truncated"]?.int == 0
        ? "ready" : "partial")
    var expected: [(Int, ReferenceSelection)] = []
    if coverage != "unsupported" {
      for (region, text) in regions.enumerated() {
        let parsed = try InlineReferenceParser.parse(text.text)
        if parsed.state != "ready" { coverage = "partial" }
        let kept = Array(parsed.selections.prefix(Self.referenceLimit - expected.count))
        if kept.count < parsed.selections.count { coverage = "partial" }
        expected += kept.map { (region, $0) }
      }
    }
    try require(
      set["coverage"]?.text == coverage && expected.count == bindings.count, "integrity",
      "Extracted parsing no longer matches its retained input.")
    for ((region, selection), row) in zip(expected, bindings) {
      let reference = try decodeReference(row)
      try require(
        row["region_ordinal"]?.int == region && reference.startScalar == selection.startScalar
          && reference.scalarCount == selection.scalarCount
          && reference.lookup.utf8.elementsEqual((selection.lookup ?? "").utf8), "integrity",
        "Parsed extracted locations changed.")
      if reference.resolution != .unresolved {
        guard let target = selection.target else {
          throw SevraError("integrity", "A parsed extracted name acquired a binding.")
        }
        try require(
          (target.workbookID ?? id) == reference.targetWorkbookID
            && target.mode == reference.targetMode
            && target.identity
              == (target.mode == .live ? reference.targetLogicalID : reference.targetVersionID),
          "integrity", "An extracted route changed its target.")
      }
    }
  }
}
