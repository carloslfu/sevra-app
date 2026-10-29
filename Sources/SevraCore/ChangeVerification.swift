import Foundation

extension Database {
  /// Streaming envelope verification. This verifies saved hashes and causality;
  /// reconstruction additionally compares the resulting authoritative state.
  func visitCommittedChanges(
    cancellation: Cancellation = .init(), _ visit: (String, String) throws -> Void
  ) throws {
    try visitCommittedEnvelopes(cancellation: cancellation) { _, payload, hash in
      try visit(payload, hash)
    }
  }

  func visitCommittedEnvelopes(
    cancellation: Cancellation = .init(),
    _ visit: (CommittedChange, String, String) throws -> Void
  ) throws {
    var ordinal = String(Int64.min)
    var previousID: String?
    var previousHash: String?
    let workbook = try scalar("SELECT value FROM meta WHERE key='workbook-id'").text
    while let row = try execute(
      "SELECT CAST(rowid AS TEXT) AS ordinal,* FROM committed_changes WHERE rowid>CAST(? AS INTEGER) ORDER BY rowid LIMIT 1",
      [.string(ordinal)]
    ).first {
      try cancellation.check()
      try require(
        Int64(row["ordinal"]!.text).map { $0 > 0 } == true, "change_integrity",
        "Invalid local change sequence.")
      let payload = row["payload"]!.text
      let hash = row["hash"]!.text
      try require(
        ChangeFormat.hash(payload) == hash, "change_hash",
        "A committed change failed its content hash.")
      let saved = try JSONDecoder().decode(CommittedChange.self, from: Data(payload.utf8))
      try require(
        saved.version == 1 && saved.storageVersion == Schema.version, "change_version",
        "Unsupported saved-change schema.")
      try saved.actor.validate()
      try require(
        saved.workbookID == workbook && !saved.id.isEmpty && !saved.writerID.isEmpty
          && !saved.changes.isEmpty && saved.changes.count <= 250_000
          && saved.id == row["id"]?.text && saved.previousID == row["previous_id"]?.string
          && saved.recorded == row["recorded"]?.text && saved.writerID == row["writer_id"]?.text
          && encoded(saved.actor) == Value.parse(row["actor"]!.text)
          && saved.changes.count == row["row_changes"]?.int,
        "change_integrity", "Saved change envelope disagrees with its retained payload.")
      try require(
        saved.previousID == previousID && saved.previousHash == previousHash, "change_predecessor",
        "Missing or out-of-order saved change predecessor.")
      try visit(saved, payload, hash)
      previousID = saved.id
      previousHash = hash
      ordinal = row["ordinal"]!.text
    }
    try require(
      try scalar(
        "SELECT EXISTS(SELECT 1 FROM operations o LEFT JOIN committed_changes c ON c.id=o.id WHERE c.id IS NULL)"
      ).int == 0, "change_receipt", "An operation receipt is missing its complete committed change."
    )
  }
}
