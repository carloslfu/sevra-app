import CSQLite
import Foundation

extension Workbook {
  /// Each change with its cause, read from records saved with it: the operation
  /// receipt sharing its ID and, for an AI tool, the tool call and the request.
  public func committedHistory(limit: Int = 100) throws -> [Value] {
    try require(
      (1...1000).contains(limit), "limit", "History supports 1 to 1,000 changes per inspection.")
    return try synchronized {
      let rows = try db.execute(
        """
        SELECT c.id,c.previous_id,c.hash,c.recorded,c.writer_id,c.actor,c.row_changes,
          o.kind AS operation
        FROM committed_changes c LEFT JOIN operations o ON o.id=c.id
        ORDER BY c.rowid DESC LIMIT ?
        """,
        [.number(Double(limit))])
      let keys = rows.map { Self.toolCallKeys(in: $0["id"]!.text) }
      let calls = try toolCalls(for: Set(keys.flatMap { $0.map(\.key) }))
      return try zip(rows, keys).map { row, keys in
        var toolCall = Value.null
        if let found = keys.lazy.compactMap({ key in calls[key.key].map { (key, $0) } }).first {
          var fields = found.1
          fields["relation"] = .string(found.0.relation)
          toolCall = .object(fields)
        }
        return .object([
          "id": row["id"]!, "previousID": row["previous_id"]!, "hash": row["hash"]!,
          "recorded": row["recorded"]!, "writerID": row["writer_id"]!,
          "actor": try Value.parse(row["actor"]!.text), "rowChanges": row["row_changes"]!,
          "cause": .object(["operation": row["operation"]!, "toolCall": toolCall]),
        ])
      }
    }
  }

  private static let callIdentity = try! NSRegularExpression(
    pattern: "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?:-[0-9a-f]{24})?")

  /// A tool's changes are saved under IDs built from its call: the operation token
  /// (run ID and argument hash) exactly, or the call ID or token inside a longer ID
  /// such as `sql-<call>-<step>` or `run-<token>`, with `~undo` or `~rollback` after it
  /// when the change takes the call's work back. Earlier keys in the ID come first.
  static func toolCallKeys(in id: String) -> [(key: String, relation: String)] {
    let text = id as NSString
    return callIdentity.matches(in: id, range: NSRange(location: 0, length: text.length))
      .flatMap { match -> [(key: String, relation: String)] in
        let token = text.substring(with: match.range)
        let rest = text.substring(from: match.range.location + match.range.length)
        let relation =
          rest.hasPrefix("~undo") ? "undo" : rest.hasPrefix("~rollback") ? "rollback" : "made"
        // A token holds the run ID first; the call ID is the bare form.
        let bare = String(token.prefix(36))
        return token.count > 36
          ? [(token, relation), (bare, relation)] : [(token, relation)]
      }
  }

  /// The earliest tool call for each key, by call ID or operation token. A repeated
  /// call with the same arguments shares a token but changed nothing new.
  private func toolCalls(for keys: Set<String>) throws -> [String: [String: Value]] {
    var found: [String: (order: Int64, fields: [String: Value])] = [:]
    let all = keys.sorted()
    for start in stride(from: 0, to: all.count, by: 400) {
      let chunk = all[start..<min(start + 400, all.count)].map(Value.string)
      let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
      for row in try db.execute(
        """
        SELECT t.rowid AS sequence,t.id,t.tool,t.run_id,t.operation_token,r.message_id
        FROM tool_calls t LEFT JOIN run_requests r ON r.run_id=t.run_id
        WHERE t.id IN (\(marks)) OR t.operation_token IN (\(marks))
        """, chunk + chunk)
      {
        let order = Int64(row["sequence"]!.int ?? 0)
        let fields: [String: Value] = [
          "id": row["id"]!, "tool": row["tool"]!, "runID": row["run_id"]!,
          "requestMessageID": row["message_id"]!,
        ]
        for key in [row["id"]!.text, row["operation_token"]!.text] where keys.contains(key) {
          if found[key].map({ $0.order > order }) ?? true { found[key] = (order, fields) }
        }
      }
    }
    return found.mapValues(\.fields)
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
      "SELECT key,value FROM meta WHERE key='space-navigation' OR key LIKE 'conversation-view:%' OR key LIKE 'form-draft:%' OR key LIKE 'workflow-clarification-draft:%' OR key LIKE 'table-update-draft:%' ORDER BY key"
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
    _ = try checked.verify(cancellation: cancellation)
    try cancellation.check()
    try fm.moveItem(at: package, to: destination)
    return try Workbook(destination)
  }
}
