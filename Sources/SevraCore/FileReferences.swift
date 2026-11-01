import Foundation

public struct ExtractedReferenceSelection: Codable, Sendable {
  public let region: Int
  public let selection: ReferenceSelection
  public init(region: Int, selection: ReferenceSelection) {
    self.region = region
    self.selection = selection
  }
}

extension Workbook {
  static let fileReferenceParser = "extracted-" + InlineReferenceParser.identity
  static let fileReferenceManualParser = "extracted-selections-v1"

  func currentFileReferenceSet(_ origin: String) throws -> String? {
    try db.scalar("SELECT set_id FROM file_reference_heads WHERE origin_id=?", [.string(origin)])
      .string
  }

  func fileReferenceSet(_ origin: String, snapshotID: String? = nil) throws -> [String: Value]? {
    guard let id = try snapshotID ?? currentFileReferenceSet(origin) else { return nil }
    try Self.validateReferenceIdentity(id)
    guard
      let bytes = try db.execute(
        "SELECT length(CAST(bindings AS BLOB)) AS bytes FROM file_reference_sets WHERE id=? AND origin_id=?",
        [.string(id), .string(origin)]
      ).first?["bytes"]?.int
    else {
      throw SevraError(
        "reference_snapshot", "This extracted annotation does not belong to the exact file version."
      )
    }
    try require(
      bytes <= 2_000_000, "integrity",
      "Extracted references exceed their stored bounds.")
    return try db.execute(
      "SELECT * FROM file_reference_sets WHERE id=? AND origin_id=?",
      [.string(id), .string(origin)]
    ).first
  }

  func fileReferenceRows(_ set: [String: Value]) throws -> [[String: Value]] {
    let bindings = try Value.parse(set["bindings"]!.text)
    guard case .array(let values) = bindings, values.count <= Self.referenceLimit else {
      throw SevraError("integrity", "Invalid extracted reference array.")
    }
    return try values.map {
      guard case .object(let row) = $0, let region = row["region_ordinal"]?.int,
        Set(row.keys)
          == Set([
            "reference_id", "start_scalar", "scalar_count", "label", "lookup_text",
            "target_workbook", "target_mode", "target_logical", "target_version", "resolution",
            "region_ordinal", "source_locator",
          ]),
        let referenceID = row["reference_id"]?.string,
        (try? Self.validateReferenceIdentity(referenceID)) != nil,
        let label = row["label"]?.string, label.utf8.count <= 1024,
        let lookup = row["lookup_text"]?.string, lookup.utf8.count <= 1024,
        region >= 0, region < 512, row["region_ordinal"] == .number(Double(region)),
        let locator = row["source_locator"]?.string, locator.utf8.count <= 1024
      else { throw SevraError("integrity", "Invalid extracted reference locator.") }
      _ = try decodeReference(row)
      return row
    }
  }

  func fileReferenceInput(_ id: String) throws -> [String: Value] {
    guard
      let bounds = try db.execute(
        "SELECT length(CAST(regions AS BLOB)) AS bytes FROM file_reference_inputs WHERE id=?",
        [.string(id)]
      ).first,
      (bounds["bytes"]?.int ?? Int.max) <= 8_000_000,
      let row = try db.execute("SELECT * FROM file_reference_inputs WHERE id=?", [.string(id)])
        .first
    else { throw SevraError("integrity", "Missing or oversized retained extraction input.") }
    return row
  }

  func fileReferenceRegions(_ input: [String: Value]) throws -> [Chunk] {
    let regions = try JSONDecoder().decode([Chunk].self, from: Data(input["regions"]!.text.utf8))
    try require(
      regions.count <= 512
        && regions.reduce(0, { $0 + $1.text.utf8.count }) <= Self.referenceBodyLimit
        && regions.allSatisfy { $0.locator.utf8.count <= 1024 }
        && regions.reduce(0, { $0 + $1.locator.utf8.count }) <= 64_000, "integrity",
      "Retained extraction regions exceed their bounds.")
    return regions
  }

  /// Captured extraction text is separate from replaceable FTS chunks and the
  /// original asset. A ready parse covers only supported syntax in that text.
  public func fileReferenceSnapshot(
    _ originVersionID: String, snapshotID: String? = nil,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try synchronized(cancellation: cancellation) {
      try db.budget(cancellation: cancellation, seconds: 3) {
        try db.readTransaction {
          try exactReferenceOrigin(originVersionID)
          guard var set = try fileReferenceSet(originVersionID, snapshotID: snapshotID) else {
            return .object([
              "id": .null, "originVersionID": .string(originVersionID),
              "coverage": .string("not_indexed"), "references": .array([]),
            ])
          }
          let input = try fileReferenceInput(set["input_id"]!.text)
          var metadata = input
          metadata.removeValue(forKey: "regions")
          let occurrences = try fileReferenceRows(set).map { row -> Value in
            let reference = try decodeReference(row)
            return .object([
              "reference": try JSONDecoder().decode(
                Value.self, from: JSONEncoder().encode(reference)),
              "region": row["region_ordinal"]!,
              "locator": .string(
                row["source_locator"]!.text
                  + "; scalar=\(reference.startScalar); count=\(reference.scalarCount)"),
            ])
          }
          set.removeValue(forKey: "bindings")
          set["input"] = .object(metadata)
          set["references"] = .array(occurrences)
          return .object(set)
        }
      }
    }
  }

  /// Owner-facing retained text, not a model read/citation receipt. The locator
  /// and asset hash identify the original whose rendering can be inspected.
  public func fileReferenceRegion(
    _ originVersionID: String, snapshotID: String, region: Int,
    offset: Int = 0, limit: Int = 4000, cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      region >= 0 && region < 512 && offset >= 0 && offset <= Self.referenceBodyLimit && limit > 0
        && limit <= 6000,
      "reference_limit", "Choose a bounded retained-extraction region page.")
    return try synchronized(cancellation: cancellation) {
      try db.budget(cancellation: cancellation, seconds: 3) {
        try db.readTransaction {
          guard let set = try fileReferenceSet(originVersionID, snapshotID: snapshotID) else {
            throw SevraError("reference_snapshot", "Missing file annotation.")
          }
          let input = try fileReferenceInput(set["input_id"]!.text)
          let regions = try fileReferenceRegions(input)
          try require(
            region < regions.count, "reference_region",
            "The region is absent from this retained extraction.")
          let scalars = regions[region].text.unicodeScalars
          try require(
            offset <= scalars.count, "reference_range", "The offset is beyond this region.")
          let text = String(String.UnicodeScalarView(scalars.dropFirst(offset).prefix(limit)))
          let next = offset + text.unicodeScalars.count
          return .object([
            "originVersionID": .string(originVersionID), "snapshotID": .string(snapshotID),
            "inputID": input["id"]!,
            "assetID": input["asset_id"]!, "assetHash": input["asset_hash"]!,
            "locator": .string(regions[region].locator),
            "region": .number(Double(region)), "offsetScalar": .number(Double(offset)),
            "text": .string(text),
            "nextOffsetScalar": next < scalars.count ? .number(Double(next)) : .null,
          ])
        }
      }
    }
  }

  public func fileReferenceHistory(
    _ originVersionID: String, beforeVersion: Int? = nil,
    limit: Int = 20, cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      limit > 0 && limit <= 50 && (beforeVersion ?? 1) > 0, "reference_limit",
      "Choose a bounded extracted annotation history page.")
    return try synchronized(cancellation: cancellation) {
      try db.budget(cancellation: cancellation, seconds: 3) {
        try exactReferenceOrigin(originVersionID)
        let rows = try db.execute(
          "SELECT id,input_id,version,previous_id,parser,coverage,created FROM file_reference_sets WHERE origin_id=? AND version<? ORDER BY version DESC LIMIT ?",
          [
            .string(originVersionID), .number(Double(beforeVersion ?? Int.max)),
            .number(Double(limit + 1)),
          ])
        return .object([
          "versions": .array(rows.prefix(limit).map(Value.object)),
          "nextBeforeVersion": rows.count > limit ? rows[limit - 1]["version"]! : .null,
        ])
      }
    }
  }

  @discardableResult public func annotateFileReferences(
    _ originVersionID: String,
    selections: [ExtractedReferenceSelection], expectedSnapshotID: String,
    token: String = identifier(),
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try Self.validateReferenceIdentity(originVersionID)
    try Self.validateReferenceIdentity(expectedSnapshotID)
    try require(
      selections.count <= Self.referenceLimit, "reference_limit",
      "At most 128 extracted references can be selected.")
    for entry in selections { _ = try Self.referenceSelectionsValue([entry.selection]) }
    let request = try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(selections))
    let result = try mutation(
      "file_reference_annotation", token: token,
      request: .object([
        "origin": .string(originVersionID), "expectedSnapshotID": .string(expectedSnapshotID),
        "selections": request,
      ]), cancellation: cancellation
    ) {
      try require(
        try db.scalar("SELECT category FROM items WHERE id=?", [.string(originVersionID)]).text
          == "source", "reference_annotation", "Annotate an exact Source file version.")
      try require(
        try currentFileReferenceSet(originVersionID) == expectedSnapshotID, "stale_reference",
        "The file annotation changed. Refresh before applying your choices.")
      let previous = try fileReferenceSet(originVersionID)!
      let input = try fileReferenceInput(previous["input_id"]!.text)
      let regions = try fileReferenceRegions(input)
      let allowed = Set(try fileReferenceRows(previous).map { $0["reference_id"]!.text })
      var rows: [[String: Value]] = []
      var lastRegion = -1
      for group in Dictionary(grouping: selections, by: \.region).sorted(by: { $0.key < $1.key }) {
        try cancellation.check()
        try require(
          group.key >= 0 && group.key < regions.count && group.key >= lastRegion,
          "reference_region", "Choose an existing retained extraction region.")
        lastRegion = group.key
        let normalized = try normalizedReferenceBindings(
          group.value.map(\.selection), body: regions[group.key].text, allowedIDs: allowed)
        rows += normalized.map {
          var row = $0
          row["region_ordinal"] = .number(Double(group.key))
          row["source_locator"] = .string(regions[group.key].locator)
          return row
        }
      }
      try require(
        Set(rows.map { $0["reference_id"]!.text }).count == rows.count, "reference_identity",
        "One occurrence identity cannot be used twice.")
      return .string(
        try publishFileReferenceSet(
          originVersionID, input: input, rows: rows,
          parser: Self.fileReferenceManualParser, coverage: "partial",
          detail: "Explicit choices in retained extracted text. Other mentions may exist.",
          inherited: nil))
    }
    // Saved by now, so a late Stop must not read as a failed save.
    return try fileReferenceSnapshot(originVersionID, snapshotID: result.text)
  }
}
