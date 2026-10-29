import Foundation

extension Workbook {
  func inheritFileReferences(from origin: String, to destination: String, assetID: String?) throws {
    guard let assetID, let previous = try fileReferenceSet(origin) else { return }
    var input = try fileReferenceInput(previous["input_id"]!.text)
    guard input["asset_id"]?.text == assetID else { return }
    input["id"] = .string(identifier())
    input["origin_id"] = .string(destination)
    input["created"] = .string(timestamp())
    input["content_hash"] = .string(
      ToolResultProjection.digest(try fileReferenceInputIdentity(input).json()))
    try db.execute(
      "INSERT INTO file_reference_inputs VALUES(?,?,?,?,?,?,?,?,?,?,?)",
      [
        input["id"]!, input["origin_id"]!, input["asset_id"]!, input["asset_hash"]!,
        input["extraction_parser"]!, input["extraction_state"]!, input["extraction_detail"]!,
        input["content_hash"]!, input["regions"]!, input["truncated"]!, input["created"]!,
      ])
    _ = try publishFileReferenceSet(
      destination, input: input, rows: fileReferenceRows(previous),
      parser: previous["parser"]!.text,
      coverage: previous["coverage"]!.text, detail: previous["detail"]!.text,
      inherited: previous["id"]!.text)
  }
  func availableReferenceSelections(_ selections: [ReferenceSelection], cancellation: Cancellation)
    throws -> [ReferenceSelection]
  {
    try selections.map { selection in
      try cancellation.check()
      var target = selection.target
      if let candidate = target, candidate.workbookID == nil || candidate.workbookID == id {
        let query =
          candidate.mode == .live
          ? "SELECT count(*) FROM heads WHERE logical_id=?"
          : "SELECT count(*) FROM items WHERE id=?"
        if try db.scalar(query, [.string(candidate.identity)]).int != 1 { target = nil }
      }
      return .init(
        startScalar: selection.startScalar, scalarCount: selection.scalarCount, target: target,
        lookup: selection.lookup, id: selection.id)
    }
  }

  func fileReferenceInputIdentity(_ row: [String: Value]) throws -> Value {
    var fields: [String: Value] = [:]
    for key in [
      "origin_id", "asset_id", "asset_hash", "extraction_parser", "extraction_state",
      "extraction_detail", "truncated",
    ] { fields[key] = row[key]! }
    fields["regions"] = try Value.parse(row["regions"]!.text)
    return .object(fields)
  }

  func captureFileReferences(
    _ origin: String, chunks: [Chunk], state: String, detail: String,
    parser: String, cancellation: Cancellation
  ) throws {
    guard ["ready", "partial", "unsupported"].contains(state),
      let assetID = try db.scalar("SELECT asset_id FROM items WHERE id=?", [.string(origin)]).string
    else { return }
    try require(
      parser.utf8.count <= 1024 && detail.utf8.count <= 16_000, "reference_limit",
      "Extraction identity or detail is too large.")
    let assetHash = try asset(assetID).hash
    var regions: [Chunk] = []
    var remaining = Self.referenceBodyLimit
    var locatorBytes = 0
    var truncated = false
    for chunk in chunks {
      try cancellation.check()
      guard regions.count < 512, chunk.locator.utf8.count <= 1024,
        locatorBytes + chunk.locator.utf8.count <= 64_000
      else {
        truncated = true
        break
      }
      var used = 0
      let prefix = chunk.text.unicodeScalars.prefix { scalar in
        guard used + scalar.utf8.count <= remaining else { return false }
        used += scalar.utf8.count
        return true
      }
      let text = String(String.UnicodeScalarView(prefix))
      regions.append(Chunk(text, locator: chunk.locator))
      remaining -= used
      locatorBytes += chunk.locator.utf8.count
      if used < chunk.text.utf8.count {
        truncated = true
        break
      }
    }
    let regionJSON = String(decoding: try JSONEncoder().encode(regions), as: UTF8.self)
    var input: [String: Value] = [
      "origin_id": .string(origin), "asset_id": .string(assetID), "asset_hash": .string(assetHash),
      "extraction_parser": .string(parser), "extraction_state": .string(state),
      "extraction_detail": .string(detail),
      "regions": .string(regionJSON), "truncated": .number(truncated ? 1 : 0),
    ]
    let contentHash = ToolResultProjection.digest(try fileReferenceInputIdentity(input).json())
    input["content_hash"] = .string(contentHash)
    if let existing = try db.execute(
      "SELECT * FROM file_reference_inputs WHERE origin_id=? AND content_hash=? ORDER BY rowid DESC LIMIT 1",
      [.string(origin), .string(contentHash)]
    ).first {
      input = existing
      if let current = try fileReferenceSet(origin), current["input_id"] == input["id"] { return }
    } else {
      input["id"] = .string(identifier())
      input["created"] = .string(timestamp())
      try db.execute(
        "INSERT INTO file_reference_inputs VALUES(?,?,?,?,?,?,?,?,?,?,?)",
        [
          input["id"]!, input["origin_id"]!, input["asset_id"]!, input["asset_hash"]!,
          input["extraction_parser"]!, input["extraction_state"]!, input["extraction_detail"]!,
          input["content_hash"]!, input["regions"]!, input["truncated"]!, input["created"]!,
        ])
    }
    // Returning to an already captured input retains its most recent explicit
    // choices, including unresolved ones, instead of resolving routes anew.
    if let inherited = try db.execute(
      "SELECT * FROM file_reference_sets WHERE origin_id=? AND input_id=? ORDER BY version DESC LIMIT 1",
      [.string(origin), input["id"]!]
    ).first {
      _ = try publishFileReferenceSet(
        origin, input: input, rows: fileReferenceRows(inherited), parser: inherited["parser"]!.text,
        coverage: inherited["coverage"]!.text, detail: inherited["detail"]!.text,
        inherited: inherited["id"]!.text)
      return
    }
    var rows: [[String: Value]] = []
    var coverage =
      state == "unsupported"
      ? "unsupported" : (state == "ready" && !truncated ? "ready" : "partial")
    if state != "unsupported" {
      for (ordinal, region) in regions.enumerated() {
        let parsed = try InlineReferenceParser.parse(region.text, cancellation: cancellation)
        if parsed.state != "ready" { coverage = "partial" }
        let selections = try availableReferenceSelections(
          Array(parsed.selections.prefix(Self.referenceLimit - rows.count)),
          cancellation: cancellation)
        if selections.count < parsed.selections.count { coverage = "partial" }
        rows += try normalizedReferenceBindings(selections, body: region.text).map {
          var row = $0
          row["region_ordinal"] = .number(Double(ordinal))
          row["source_locator"] = .string(region.locator)
          return row
        }
      }
    }
    _ = try publishFileReferenceSet(
      origin, input: input, rows: rows, parser: Self.fileReferenceParser, coverage: coverage,
      detail:
        "Supported links in retained extracted text only. Embedded format-specific hyperlinks and unextracted content are outside this coverage."
        + (truncated ? " The retained text/region limit was reached." : ""), inherited: nil)
  }

  func publishFileReferenceSet(
    _ origin: String, input: [String: Value], rows: [[String: Value]],
    parser: String, coverage: String, detail: String, inherited: String?
  ) throws -> String {
    let previous = try fileReferenceSet(origin)
    let bindings = Value.array(rows.map(Value.object))
    let source = try insertItem(
      category: "source", kind: "annotation",
      title: parser == Self.fileReferenceManualParser
        ? "Extracted reference choices" : "Extracted reference parse",
      text:
        "Reference annotations for retained extracted text. This is not a business relationship or a change to the original asset.",
      data: .object([
        "originVersionID": .string(origin), "inputID": input["id"]!,
        "contentHash": input["content_hash"]!,
        "previousSnapshotID": previous?["id"] ?? .null,
        "inheritedSnapshotID": inherited.map(Value.string) ?? .null,
        "parser": .string(parser), "coverage": .string(coverage), "references": bindings,
      ]), meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
      transformation: parser, controlInputs: [origin])
    let set = identifier()
    try db.execute(
      "INSERT INTO file_reference_sets VALUES(?,?,?,?,?,?,?,?,?,?,?)",
      [
        .string(set), .string(origin), input["id"]!,
        .number(Double((previous?["version"]?.int ?? 0) + 1)), previous?["id"] ?? .null,
        .string(parser), .string(coverage), .string(detail), .string(source),
        .string(try bindings.json()), .string(timestamp()),
      ])
    try db.execute(
      "INSERT INTO file_reference_heads VALUES(?,?) ON CONFLICT(origin_id) DO UPDATE SET set_id=excluded.set_id",
      [.string(origin), .string(set)])
    try refreshFileReferenceIndex(origin)
    return set
  }

  func refreshFileReferenceIndex(_ origin: String) throws {
    try db.execute("DELETE FROM file_reference_index WHERE origin_id=?", [.string(origin)])
    guard let set = try fileReferenceSet(origin) else { return }
    let current = try db.scalar(
      "SELECT EXISTS(SELECT 1 FROM heads WHERE item_id=?)", [.string(origin)])
    for (ordinal, row) in try fileReferenceRows(set).enumerated() {
      try db.execute(
        "INSERT INTO file_reference_index VALUES(?,?,?,?,?,?,?,?,?,?)",
        [
          .string(origin), row["reference_id"]!, set["id"]!, .number(Double(ordinal)), current,
          row["target_workbook"]!, row["target_mode"]!, row["target_logical"]!,
          row["target_version"]!, row["resolution"]!,
        ])
    }
  }

  func rebuildFileReferenceIndex(cancellation: Cancellation) throws {
    try db.execute("DELETE FROM file_reference_index")
    var after = ""
    while true {
      let rows = try db.execute(
        "SELECT origin_id FROM file_reference_heads WHERE origin_id>? ORDER BY origin_id LIMIT 32",
        [.string(after)])
      if rows.isEmpty { break }
      for row in rows {
        try cancellation.check()
        after = row["origin_id"]!.text
        try refreshFileReferenceIndex(after)
      }
    }
  }
}
