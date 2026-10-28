import CSQLite
import Foundation

extension Workbook {
  public func committedHistory(limit: Int = 100) throws -> [Value] {
    try require(
      (1...1000).contains(limit), "limit", "History supports 1 to 1,000 changes per inspection.")
    return try synchronized {
      try db.execute(
        "SELECT id,previous_id,hash,recorded,writer_id,actor,row_changes FROM committed_changes ORDER BY rowid DESC LIMIT ?",
        [.number(Double(limit))]
      ).map { row in
        return .object([
          "id": row["id"]!, "previousID": row["previous_id"]!, "hash": row["hash"]!,
          "recorded": row["recorded"]!, "writerID": row["writer_id"]!,
          "actor": try Value.parse(row["actor"]!.text), "rowChanges": row["row_changes"]!,
        ])
      }
    }
  }

  /// Reconstruct into a new package. The original is never edited. A failed or
  /// cancelled replay leaves no published destination, and no execution adapter
  /// is involved. Saved running/prepared results remain inert history.
  public func reconstruct(to destination: URL, cancellation: Cancellation = .init()) throws
    -> Workbook
  {
    let fm = FileManager.default
    try require(
      !fm.fileExists(atPath: destination.path), "exists", "Choose a new reconstruction destination."
    )
    let staging = destination.deletingLastPathComponent().appendingPathComponent(
      ".sevra-reconstruct-" + identifier())
    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: staging) }
    let sourceURL = staging.appendingPathComponent("source.sqlite")
    try synchronized { try db.backup(to: sourceURL, cancellation: cancellation) }
    let source = try Database(sourceURL)
    let package = staging.appendingPathComponent("workbook.sevra")
    try fm.createDirectory(at: package, withIntermediateDirectories: true)
    try fm.copyItem(
      at: url.appendingPathComponent("manifest.json"),
      to: package.appendingPathComponent("manifest.json"))
    for name in ["assets", "staging"] {
      try fm.createDirectory(
        at: package.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    let target = try Database(package.appendingPathComponent("workbook.sqlite"), create: true)
    try target.script(Schema.sql)
    try target.execute("PRAGMA trusted_schema=ON")
    try target.execute("INSERT INTO meta VALUES('workbook-id',?)", [.string(id)])
    try require(
      sevra_enable_triggers(target.handle, 0) == SQLITE_OK, "change_triggers",
      "Cannot disable execution triggers for reconstruction.")
    try source.visitCommittedChanges(cancellation: cancellation) { payload, hash in
      try target.applyCommitted(payload, hash: hash, cancellation: cancellation)
    }
    try cancellation.check()
    try require(
      try source.authorityDigest(cancellation: cancellation)
        == target.authorityDigest(cancellation: cancellation), "change_closure",
      "Committed history does not reconstruct all authoritative state. The original workbook is preserved."
    )
    // User presentation is a current checkpoint, not a stream of keystrokes.
    for row in try source.execute(
      "SELECT key,value FROM meta WHERE key='space-navigation' OR key LIKE 'conversation-view:%' ORDER BY key"
    ) {
      try target.execute(
        "INSERT INTO meta VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        [row["key"]!, row["value"]!])
    }
    // Only immutable included dependencies are copied. Paths and access bookmarks
    // for explicitly linked files were never captured in committed payloads.
    for asset in try source.execute(
      "SELECT id,path,hash FROM assets WHERE mode='included' ORDER BY id")
    {
      try cancellation.check()
      let relative = asset["path"]!.text
      let original = try safePath(relative)
      let copy = package.appendingPathComponent(relative)
      try fm.createDirectory(
        at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
      if !fm.fileExists(atPath: copy.path) {
        try Self.copyStream(original, to: copy, cancellation: cancellation)
      }
      try require(
        try Self.hashFile(copy, cancellation: cancellation) == asset["hash"]!.text, "change_asset",
        "An included historical asset is missing or corrupt.")
    }
    try target.execute("INSERT INTO search_fts(search_fts) VALUES('rebuild')")
    try target.execute("INSERT INTO names_fts(names_fts) VALUES('rebuild')")
    try target.execute("INSERT INTO message_fts(message_fts) VALUES('rebuild')")
    try target.execute("INSERT INTO definition_fts(definition_fts) VALUES('rebuild')")
    try require(
      sevra_enable_triggers(target.handle, 1) == SQLITE_OK, "change_triggers",
      "Cannot restore canonical storage triggers.")
    let checked = try Workbook(package)
    _ = try checked.verify()
    try cancellation.check()
    try fm.moveItem(at: package, to: destination)
    return try Workbook(destination)
  }
}
