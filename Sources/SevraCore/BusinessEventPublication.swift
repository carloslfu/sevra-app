import Foundation

extension Database {
  func publishBusinessEvents(
    _ changes: [RowChange], commitID: String, recorded: String, actor: ChangeActor
  ) throws {
    let entries = try deriveBusinessEvents(changes)
    guard !entries.isEmpty else { return }
    let position = try scalar(
      "SELECT CAST(COALESCE(MAX(position),0)+1 AS TEXT) FROM business_batches"
    ).text
    try require(
      Int64(position).map { $0 > 0 } == true, "business_limit", "Business sequence is exhausted.")
    try execute(
      "INSERT INTO business_batches VALUES(?,?,?,?,?)",
      [
        .string(commitID), .string(position), .string(recorded),
        .string(try ChangeFormat.encode(actor)), .string("business-versions-v1"),
      ])
    for (ordinal, entry) in entries.enumerated() {
      try execute(
        "INSERT INTO business_events VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
        [
          .string(try BusinessEventEntry.identity(batch: commitID, ordinal: ordinal)),
          .string(commitID), .string(position), .number(Double(ordinal)), .string(entry.family),
          .string(entry.scopeKind), .string(entry.scopeKey), .string(entry.recordKind),
          entry.logicalID.map(Value.string) ?? .null, entry.beforeID.map(Value.string) ?? .null,
          entry.afterID.map(Value.string) ?? .null, .string(try entry.payload.json()),
        ])
    }
  }

  /// Validate meaning against retained inputs, in addition to their saved hash.
  /// Immutable version lookups never resolve a historical current head.
  func verifyBusinessEvents() throws {
    var position: Int64 = 0
    try visitCommittedEnvelopes { change, _, _ in
      let entries = try deriveBusinessEvents(change.changes)
      let batch = try execute(
        "SELECT id,CAST(position AS TEXT) AS position,recorded,actor,policy FROM business_batches WHERE id=?",
        [.string(change.id)]
      ).first
      if entries.isEmpty {
        try require(batch == nil, "business_integrity", "A technical commit has a business batch.")
        return
      }
      try require(position < Int64.max, "business_integrity", "Invalid business sequence.")
      position += 1
      try require(
        batch?["position"] == .string(String(position))
          && batch?["recorded"] == .string(change.recorded)
          && batch?["actor"] == .string(try ChangeFormat.encode(change.actor))
          && batch?["policy"] == .string("business-versions-v1"),
        "business_integrity", "Business batch metadata disagrees with its committed change.")
      let actual = try execute(
        "SELECT * FROM business_events WHERE batch_id=? ORDER BY ordinal", [.string(change.id)],
        maxRows: entries.count + 1, maxBytes: 67_108_864)
      try require(
        actual.count == entries.count, "business_integrity",
        "Business entries are missing or extra.")
      for (ordinal, entry) in entries.enumerated() {
        let row = actual[ordinal]
        try require(
          row["id"] == .string(try BusinessEventEntry.identity(batch: change.id, ordinal: ordinal))
            && row["ordinal"] == .number(Double(ordinal))
            && row["family"] == .string(entry.family)
            && row["scope_kind"] == .string(entry.scopeKind)
            && row["scope_key"] == .string(entry.scopeKey)
            && row["record_kind"] == .string(entry.recordKind)
            && row["logical_id"] == (entry.logicalID.map(Value.string) ?? .null)
            && row["before_id"] == (entry.beforeID.map(Value.string) ?? .null)
            && row["after_id"] == (entry.afterID.map(Value.string) ?? .null)
            && row["payload"] == .string(try entry.payload.json()),
          "business_integrity", "A business entry disagrees with its retained inputs.")
      }
    }
    try require(
      try scalar("SELECT CAST(count(*) AS TEXT) FROM business_batches").text == String(position),
      "business_integrity", "The business feed has an unverified batch.")
  }
}
