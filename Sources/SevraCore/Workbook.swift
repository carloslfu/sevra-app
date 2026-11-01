import Darwin
import Foundation

public final class Workbook: @unchecked Sendable {
  public let url: URL
  /// Package identity survives copying/export. Links never use the filesystem path.
  public let id: String
  let db: Database
  private let lock = NSRecursiveLock()
  private var lockFD: Int32 = -1
  /// Tables whose rows changed in the running transaction.
  var tablesWithChangedRows = Set<String>()
  public static func create(at url: URL, title: String) throws -> Workbook {
    try require(
      !FileManager.default.fileExists(atPath: url.path), "exists", "Choose a new workbook location."
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    do {
      for path in ["assets", "staging"] {
        try FileManager.default.createDirectory(
          at: url.appendingPathComponent(path), withIntermediateDirectories: true)
      }
      let manifest: Value = .object([
        "format": .string("sevra"), "version": .number(1), "id": .string(identifier()),
        "title": .string(title),
      ])
      try Data(try manifest.json().utf8).write(
        to: url.appendingPathComponent("manifest.json"), options: .atomic)
      let database = try Database(url.appendingPathComponent("workbook.sqlite"), create: true)
      try database.script(Schema.sql)
      try database.execute("INSERT INTO meta VALUES('workbook-id',?)", [manifest["id"]])
      return try Workbook(url)
    } catch {
      try? FileManager.default.removeItem(at: url)
      throw error
    }
  }
  public init(_ url: URL) throws {
    self.url = url.standardizedFileURL
    let manifestURL = url.appendingPathComponent("manifest.json")
    for name in [
      "manifest.json", "workbook.sqlite", "workbook.sqlite-journal", "workbook.sqlite-wal",
      "workbook.sqlite-shm", ".write-lock", "assets", "staging",
    ] {
      let file = url.appendingPathComponent(name)
      let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
      try require(
        attrs?[.type] as? FileAttributeType != .typeSymbolicLink, "package_path",
        "A workbook cannot contain a symbolic link at " + name)
    }
    let size = try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    try require(size <= 64_000, "manifest", "Workbook manifest is too large.")
    let m = try Value.parse(String(contentsOf: manifestURL, encoding: .utf8))
    try require(
      m["format"].text == "sevra" && m["version"].int == 1, "format", "Unsupported workbook format."
    )
    try require(
      m["id"].string != nil, "workbook_identity", "The workbook identity must be a string.")
    try Self.validateReferenceIdentity(m["id"].text)
    id = m["id"].text
    db = try Database(url.appendingPathComponent("workbook.sqlite"))
    try require(
      try db.scalar("PRAGMA application_id").int == Schema.applicationID, "format",
      "This is not a Sevra workbook.")
    let incomingVersion = try db.scalar("PRAGMA user_version").int
    try require(
      incomingVersion == Schema.version, "schema",
      "This development workbook uses an unsupported format. Its files were not changed. Use a matching development build to recover or export it."
    )
    let descriptor = Darwin.open(
      url.appendingPathComponent(".write-lock").path,
      O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    try require(descriptor >= 0, "lock", "Cannot open the workbook lock.")
    var opened = false
    defer {
      flock(descriptor, LOCK_UN)
      if !opened { Darwin.close(descriptor) }
    }
    try require(flock(descriptor, LOCK_EX) == 0, "lock", "Cannot lock the workbook for opening.")
    try validateSchema()
    try db.enableChangeCapture(workbookID: id)
    lockFD = descriptor
    opened = true
  }
  private func validateSchema() throws {
    // Pre-1.0 development formats have no compatibility commitment. Never
    // reset an unsupported document, execute its triggers or guess a migration.
    try db.transaction {
      try require(
        try db.scalar("PRAGMA user_version").int == Schema.version, "schema",
        "This development workbook needs a matching build. Its data was not changed.")
      try db.validateCanonicalSchema()
      try require(
        try db.execute("PRAGMA foreign_key_check").isEmpty, "integrity",
        "Invalid workbook references.")
      try require(
        try db.scalar("SELECT value FROM meta WHERE key='workbook-id'").text == id,
        "workbook_identity", "The workbook manifest and database identities do not match.")
      try db.execute("PRAGMA trusted_schema=ON")
    }
  }
  deinit { if lockFD >= 0 { Darwin.close(lockFD) } }
  public var title: String {
    ((try? Value.parse(
      String(contentsOf: url.appendingPathComponent("manifest.json"), encoding: .utf8)))?["title"]
      .text) ?? url.deletingPathExtension().lastPathComponent
  }
  public func revision() throws -> Int {
    try synchronized { try db.scalar("SELECT value FROM meta WHERE key='revision'").int ?? 0 }
  }
  func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
  func synchronized<T>(cancellation: Cancellation, _ body: () throws -> T) throws -> T {
    while !lock.try() {
      try cancellation.check()
      Thread.sleep(forTimeInterval: 0.005)
    }
    defer { lock.unlock() }
    try cancellation.check()
    return try body()
  }
  @discardableResult func mutation(
    _ kind: String, token: String = identifier(), request: Value = .null, expected: Int? = nil,
    cancellation: Cancellation? = nil, actor: ChangeActor? = nil,
    deadlineSeconds: TimeInterval = 3, commitGuard: (() throws -> Void)? = nil,
    _ body: () throws -> Value
  ) throws -> Value {
    let receiptRequest: Value =
      try actor.map {
        .object(["arguments": request, "actor": try encoded($0)])
      } ?? request
    func transaction() throws -> Value {
      let previousActor = db.changes?.actor
      if let actualActor = actor ?? ChangeAttribution.actor { db.changes?.actor = actualActor }
      defer { if let previousActor { db.changes?.actor = previousActor } }
      return try db.transaction(beforeCommit: commitGuard) {
        if let prior = try db.execute(
          "SELECT kind,request,result FROM operations WHERE id=?", [.string(token)]
        ).first {
          try require(
            prior["request"]?.text == receiptRequest.json() && prior["kind"]?.text == kind,
            "idempotency",
            "The operation identifier was reused with different arguments.")
          return try Value.parse(prior["result"]!.text)
        }
        let rev = try revision()
        if let expected {
          try require(
            rev == expected, "stale_revision", "The workbook changed. Refresh and try again.")
        }
        tablesWithChangedRows = []
        let result = try body()
        try recalculateChangedSheets()
        try db.execute("UPDATE meta SET value=? WHERE key='revision'", [.string(String(rev + 1))])
        try db.execute(
          "INSERT INTO operations VALUES(?,?,?,?,?,?)",
          [
            .string(token), .string(kind), .string(try receiptRequest.json()),
            .string(try result.json()),
            .string(timestamp()), .number(Double(rev + 1)),
          ])
        return result
      }
    }
    if let cancellation {
      return try synchronized(cancellation: cancellation) {
        while flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
          try require(errno == EWOULDBLOCK || errno == EAGAIN, "lock", "Cannot lock workbook.")
          try cancellation.check()
          Thread.sleep(forTimeInterval: 0.01)
        }
        defer { flock(lockFD, LOCK_UN) }
        return try db.shortWait {
          try db.budget(cancellation: cancellation, seconds: deadlineSeconds) { try transaction() }
        }
      }
    }
    return try synchronized {
      guard flock(lockFD, LOCK_EX) == 0 else { throw SevraError("lock", "Cannot lock workbook.") }
      defer { flock(lockFD, LOCK_UN) }
      return try transaction()
    }
  }
  /// Small UI-state writes share the package lock, but do not journal keystrokes
  /// or advance business revisions. Call off the main actor. Lock acquisition is
  /// bounded, including writers in other processes.
  func presentationMutation<T>(_ body: () throws -> T) throws -> T {
    let control = Cancellation(deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      while flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
        try require(errno == EWOULDBLOCK || errno == EAGAIN, "lock", "Cannot lock workbook.")
        try control.check()
        Thread.sleep(forTimeInterval: 0.01)
      }
      defer { flock(lockFD, LOCK_UN) }
      return try db.shortWait {
        try db.budget(cancellation: control, seconds: 3) { try db.transaction(body) }
      }
    }
  }
  /// Disposable projections share the package transaction/lock, but publish no
  /// receipt or business revision when only trusted index DDL changes.
  func localProjectionMutation<T>(cancellation: Cancellation, _ body: () throws -> T) throws -> T {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      while flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
        try require(errno == EWOULDBLOCK || errno == EAGAIN, "lock", "Cannot lock workbook.")
        try control.check()
        Thread.sleep(forTimeInterval: 0.01)
      }
      defer { flock(lockFD, LOCK_UN) }
      return try db.shortWait {
        try db.budget(cancellation: control, seconds: 3) { try db.transaction(body) }
      }
    }
  }
  public func item(_ id: String) throws -> Item {
    try synchronized {
      guard
        let r = try db.execute(
          "SELECT * FROM items WHERE id=? OR id=(SELECT item_id FROM heads WHERE logical_id=?) LIMIT 1",
          [.string(id), .string(id)]
        ).first
      else { throw SevraError("not_found", "Record not found: \(id)") }
      return try decodeItem(r)
    }
  }
  /// The stored version `item(_:)` resolves to, without reading its content.
  func itemVersionID(_ id: String) throws -> String {
    try synchronized {
      guard
        let r = try db.execute(
          "SELECT id FROM items WHERE id=? OR id=(SELECT item_id FROM heads WHERE logical_id=?) LIMIT 1",
          [.string(id), .string(id)]
        ).first
      else { throw SevraError("not_found", "Record not found: \(id)") }
      return r["id"]!.text
    }
  }
  func decodeItem(_ r: [String: Value]) throws -> Item {
    guard let version = r["version"]?.int, version > 0,
      ["source", "record"].contains(r["category"]?.text ?? ""),
      ["draft", "accepted", "rejected"].contains(r["status"]?.text ?? "")
    else { throw SevraError("integrity", "Invalid record metadata.") }
    return Item(
      id: r["id"]!.text, logicalID: r["logical_id"]!.text, version: version,
      category: r["category"]!.text, kind: r["kind"]!.text, title: r["title"]!.text,
      meaning: r["meaning"]!.text, status: r["status"]!.text, scenario: r["scenario"]!.text,
      text: r["body"]!.text, data: try Value.parse(r["data"]!.text), assetID: r["asset_id"]?.string,
      supersedes: r["supersedes"]?.string, created: r["created"]!.text)
  }
  public func items(
    kind: String? = nil, excludingRows: Bool = false, limit: Int = 100, offset: Int = 0
  ) throws -> [Item] {
    try synchronized {
      try db.execute(
        "SELECT i.* FROM items i JOIN heads h ON h.item_id=i.id WHERE (? IS NULL OR kind=?) AND (?=0 OR kind!='row') ORDER BY created DESC,i.id LIMIT ? OFFSET ?",
        [
          kind.map(Value.string) ?? .null, kind.map(Value.string) ?? .null, .bool(excludingRows),
          .number(Double(min(max(limit, 1), 500))), .number(Double(max(offset, 0))),
        ]
      ).map(decodeItem)
    }
  }
  /// Home excludes rows, captured requests and technical annotations before its
  /// limit. Bodies and structured payloads are never selected or decoded.
  public func recentItemSummaries(limit: Int = 20) throws -> [ItemSummary] {
    try synchronized {
      try db.execute(
        "SELECT i.id,i.category,i.kind,i.title,i.meaning,i.status,i.asset_id FROM items i JOIN heads h ON h.item_id=i.id WHERE i.kind NOT IN ('row',\(Item.technicalKindSQL)) ORDER BY i.created DESC,i.id LIMIT ?",
        [.number(Double(min(max(limit, 1), 100)))]
      ).map { row in
        ItemSummary(
          id: row["id"]!.text, category: row["category"]!.text, kind: row["kind"]!.text,
          title: row["title"]!.text, meaning: row["meaning"]!.text, status: row["status"]!.text,
          assetID: row["asset_id"]?.string)
      }
    }
  }
  /// The entry for free-form writers: `propose_record`, `draft` and the CLI's `add`.
  /// A pipeline writes the kinds it owns through `addHostOwnedItem` or `insertItem`.
  @discardableResult public func addItem(
    category: String, kind: String, title: String, text: String = "", data: Value = .object([:]),
    meaning: String = "actual", status: String = "draft", scenario: String = "actual",
    inputs: [String] = [], transformation: String = "human", assetID: String? = nil,
    supersedes: String? = nil, token: String = identifier(), expectedRevision: Int? = nil,
    references: [ReferenceSelection]? = nil
  ) throws -> Item {
    // A request or annotation Source authorizes nothing. Agents capture requests here.
    try require(
      !Item.hostOwnedKinds.contains(kind)
        || (category == "source" && ["request", "annotation"].contains(kind)),
      "proposal_tool",
      "Sevra writes this kind itself. Use propose_table, propose_table_edit, propose_movement or publish_result, or name a domain kind such as forecast or analysis."
    )
    // Verification reads this key on every document Record, null included.
    try require(
      !(category == "record" && kind == "document"
        && data.object.keys.contains("documentComposition")),
      "proposal_tool", "Only a composed draft records its copied passages.")
    return try addHostOwnedItem(
      category: category, kind: kind, title: title, text: text, data: data, meaning: meaning,
      status: status, scenario: scenario, inputs: inputs, transformation: transformation,
      assetID: assetID, supersedes: supersedes, token: token, expectedRevision: expectedRevision,
      references: references)
  }
  @discardableResult package func addHostOwnedItem(
    category: String, kind: String, title: String, text: String = "", data: Value = .object([:]),
    meaning: String = "actual", status: String = "draft", scenario: String = "actual",
    inputs: [String] = [], transformation: String = "human", assetID: String? = nil,
    supersedes: String? = nil, token: String = identifier(), expectedRevision: Int? = nil,
    references: [ReferenceSelection]? = nil
  ) throws -> Item {
    var fields: [String: Value] = [
      "category": .string(category), "kind": .string(kind), "title": .string(title),
      "text": .string(text), "data": data, "meaning": .string(meaning), "status": .string(status),
      "scenario": .string(scenario), "inputs": .array(inputs.map(Value.string)),
      "transformation": .string(transformation), "asset": assetID.map(Value.string) ?? .null,
      "supersedes": supersedes.map(Value.string) ?? .null,
    ]
    if let references { fields["references"] = try Self.referenceSelectionsValue(references) }
    let result = try mutation(
      "item", token: token, request: .object(fields), expected: expectedRevision
    ) {
      let saved = try insertItem(
        category: category, kind: kind, title: title, text: text, data: data, meaning: meaning,
        status: status, scenario: scenario, inputs: inputs, transformation: transformation,
        assetID: assetID, supersedes: supersedes, inheritReferenceBindings: references == nil)
      if let references {
        try publishInitialReferences(saved, selections: references, inheritedOrigin: supersedes)
      }
      return .string(saved)
    }
    return try item(result.text)
  }
  func insertItem(
    category: String, kind: String, title: String, text: String, data: Value, meaning: String,
    status: String, scenario: String, inputs: [String], transformation: String,
    assetID: String? = nil, supersedes: String? = nil, referenceOrigin: String? = nil,
    inheritReferenceBindings: Bool = true, controlInputs: [String] = [],
    producerInputs: [String] = []
  ) throws -> String {
    try require(
      !title.isEmpty && title.utf8.count <= 4096 && text.utf8.count <= 16_000_000, "limit",
      "Record title or text exceeds the supported bounds.")
    try require(
      category != "record" || !inputs.isEmpty || !producerInputs.isEmpty || !controlInputs.isEmpty,
      "lineage",
      "Derived records require at least one exact input version.")
    let old = try supersedes.map { try item($0) }
    var savedData = data
    var schemaInputs: [String] = []
    if let old, kind == "row",
      let datasetID = try db.scalar(
        "SELECT dataset_id FROM dataset_rows WHERE logical_id=?", [.string(old.logicalID)]
      ).string
    {
      let active = Set(try db.managedSchema(datasetID).columns.map(\.id))
      var values = old.data.object.filter { !active.contains($0.key) }
      values.merge(data.object) { _, new in new }
      savedData = .object(values)
      schemaInputs = [try datasetDefinition(datasetID).sourceID]
    }
    if let old {
      try require(
        old.category == category && old.kind == kind, "version",
        "A revision must preserve its category and domain kind.")
      try require(
        try db.scalar("SELECT item_id FROM heads WHERE logical_id=?", [.string(old.logicalID)]).text
          == old.id, "stale_revision", "This record has a newer version.")
    }
    if let old {
      try db.execute("UPDATE chunks SET is_current=0 WHERE item_id=?", [.string(old.id)])
      try db.execute(
        "UPDATE reference_index SET current_origin=0 WHERE origin_id=?", [.string(old.id)])
      try db.execute(
        "UPDATE file_reference_index SET current_origin=0 WHERE origin_id=?", [.string(old.id)])
    }
    let id = identifier()
    let logical = old?.logicalID ?? identifier()
    let edges = try prepareDerivationEdges(
      inputs: inputs, controls: schemaInputs + controlInputs,
      producers: producerInputs, supersedes: supersedes, transformation: transformation)
    let derivation = try ItemDerivation.seal(id, edges: edges)
    try db.execute(
      "INSERT INTO items VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
      [
        .string(id), .string(logical), .number(Double((old?.version ?? 0) + 1)), .string(category),
        .string(kind), .string(title), .string(meaning), .string(status), .string(scenario),
        .string(text), .string(try savedData.json()), assetID.map(Value.string) ?? .null,
        supersedes.map(Value.string) ?? .null, .string(timestamp()), .string(try derivation.json()),
      ])
    try db.execute(
      "INSERT INTO heads VALUES(?,?) ON CONFLICT(logical_id) DO UPDATE SET item_id=excluded.item_id",
      [.string(logical), .string(id)])
    if kind == "row" { try refreshManagedRow(logical) }
    for edge in edges {
      try db.execute(
        "INSERT INTO lineage VALUES(?,?,?,?,?)",
        [
          .string(id), edge["parent"]!,
          edge["relation"]!, edge["transformation"]!, edge["roles"]!,
        ])
    }
    try insertChunks(id, title: title, chunks: [Chunk(text.isEmpty ? data.text : text)])
    if inheritReferenceBindings, let origin = referenceOrigin ?? old?.id {
      try inheritReferences(from: origin, to: id, text: text)
    }
    if inheritReferenceBindings && !["row", "request", "annotation"].contains(kind) {
      try indexReferenceBody(id, text: text)
    }
    if let origin = referenceOrigin ?? old?.id {
      try inheritFileReferences(from: origin, to: id, assetID: assetID)
    }
    return id
  }
  public func lineage(_ id: String) throws -> [Value] {
    try synchronized {
      try db.execute(
        "SELECT * FROM lineage WHERE child=? OR parent=? LIMIT 200", [.string(id), .string(id)]
      ).map(ItemDerivation.publicEdge)
    }
  }
  public func counts() throws -> Value {
    try synchronized {
      .object([
        "sources": try db.scalar(
          "SELECT count(*) FROM heads h JOIN items i ON i.id=h.item_id WHERE category='source'"),
        "records": try db.scalar(
          "SELECT count(*) FROM heads h JOIN items i ON i.id=h.item_id WHERE category='record'"),
        "assets": try db.scalar("SELECT count(*) FROM assets"),
        "chunks": try db.scalar("SELECT count(*) FROM chunks"),
        "revision": .number(Double(try revision())),
      ])
    }
  }
}
