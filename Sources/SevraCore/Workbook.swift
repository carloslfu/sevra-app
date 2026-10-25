import Darwin
import Foundation

public final class Workbook: @unchecked Sendable {
  public let url: URL
  let db: Database
  private let lock = NSRecursiveLock()
  private var lockFD: Int32 = -1
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
    db = try Database(url.appendingPathComponent("workbook.sqlite"))
    try require(
      try db.scalar("PRAGMA application_id").int == Schema.applicationID, "format",
      "This is not a Sevra workbook.")
    try require(
      try db.scalar("PRAGMA user_version").int == Schema.version, "schema",
      "This workbook needs another version of Sevra.")
    // Canonical schema comparison refuses extra triggers/views from imported files.
    let reference = try Database(URL(fileURLWithPath: "/:memory:"), create: true)
    try reference.script(Schema.sql)
    let schemaQuery =
      "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name"
    try require(
      try db.execute(schemaQuery) == reference.execute(schemaQuery), "schema",
      "Unrecognized workbook schema. Open only a canonical Sevra package.")
    lockFD = Darwin.open(
      url.appendingPathComponent(".write-lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    try require(lockFD >= 0, "lock", "Cannot open the workbook lock.")
    // FTS triggers are our own schema; virtual table writes need trusted schema on system SQLite.
    try db.execute("PRAGMA trusted_schema=ON")
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
  @discardableResult func mutation(
    _ kind: String, token: String = identifier(), request: Value = .null, expected: Int? = nil,
    _ body: () throws -> Value
  ) throws -> Value {
    try synchronized {
      guard flock(lockFD, LOCK_EX) == 0 else { throw SevraError("lock", "Cannot lock workbook.") }
      defer { flock(lockFD, LOCK_UN) }
      return try db.transaction {
        if let prior = try db.execute(
          "SELECT kind,request,result FROM operations WHERE id=?", [.string(token)]
        ).first {
          try require(
            prior["request"]?.text == request.json() && prior["kind"]?.text == kind, "idempotency",
            "The operation identifier was reused with different arguments.")
          return try Value.parse(prior["result"]!.text)
        }
        let rev = try revision()
        if let expected {
          try require(
            rev == expected, "stale_revision", "The workbook changed. Refresh and try again.")
        }
        let result = try body()
        try db.execute("UPDATE meta SET value=? WHERE key='revision'", [.string(String(rev + 1))])
        try db.execute(
          "INSERT INTO operations VALUES(?,?,?,?,?,?)",
          [
            .string(token), .string(kind), .string(try request.json()), .string(try result.json()),
            .string(timestamp()), .number(Double(rev + 1)),
          ])
        return result
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
  @discardableResult public func addItem(
    category: String, kind: String, title: String, text: String = "", data: Value = .object([:]),
    meaning: String = "actual", status: String = "draft", scenario: String = "actual",
    inputs: [String] = [], transformation: String = "human", assetID: String? = nil,
    supersedes: String? = nil, token: String = identifier(), expectedRevision: Int? = nil
  ) throws -> Item {
    let req: Value = .object([
      "category": .string(category), "kind": .string(kind), "title": .string(title),
      "text": .string(text), "data": data, "meaning": .string(meaning), "status": .string(status),
      "scenario": .string(scenario), "inputs": .array(inputs.map(Value.string)),
      "transformation": .string(transformation), "asset": assetID.map(Value.string) ?? .null,
      "supersedes": supersedes.map(Value.string) ?? .null,
    ])
    let result = try mutation("item", token: token, request: req, expected: expectedRevision) {
      .string(
        try insertItem(
          category: category, kind: kind, title: title, text: text, data: data, meaning: meaning,
          status: status, scenario: scenario, inputs: inputs, transformation: transformation,
          assetID: assetID, supersedes: supersedes))
    }
    return try item(result.text)
  }
  func insertItem(
    category: String, kind: String, title: String, text: String, data: Value, meaning: String,
    status: String, scenario: String, inputs: [String], transformation: String,
    assetID: String? = nil, supersedes: String? = nil
  ) throws -> String {
    try require(
      !title.isEmpty && title.utf8.count <= 4096 && text.utf8.count <= 16_000_000, "limit",
      "Record title or text exceeds the supported bounds.")
    try require(
      category != "record" || !inputs.isEmpty, "lineage",
      "Derived records require at least one exact input version.")
    let old = try supersedes.map { try item($0) }
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
    }
    let id = identifier()
    let logical = old?.logicalID ?? identifier()
    try db.execute(
      "INSERT INTO items VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
      [
        .string(id), .string(logical), .number(Double((old?.version ?? 0) + 1)), .string(category),
        .string(kind), .string(title), .string(meaning), .string(status), .string(scenario),
        .string(text), .string(try data.json()), assetID.map(Value.string) ?? .null,
        supersedes.map(Value.string) ?? .null, .string(timestamp()),
      ])
    try db.execute(
      "INSERT INTO heads VALUES(?,?) ON CONFLICT(logical_id) DO UPDATE SET item_id=excluded.item_id",
      [.string(logical), .string(id)])
    for parent in Set(inputs) {
      _ = try item(parent)
      try db.execute(
        "INSERT INTO lineage VALUES(?,?,?,?)",
        [.string(id), .string(parent), .string("derives-from"), .string(transformation)])
    }
    if let supersedes {
      try db.execute(
        "INSERT OR IGNORE INTO lineage VALUES(?,?,?,?)",
        [.string(id), .string(supersedes), .string("supersedes"), .string(transformation)])
    }
    try insertChunks(id, title: title, chunks: [Chunk(text.isEmpty ? data.text : text)])
    return id
  }
  public func lineage(_ id: String) throws -> [Value] {
    try synchronized {
      try db.execute(
        "SELECT * FROM lineage WHERE child=? OR parent=? LIMIT 200", [.string(id), .string(id)]
      ).map(Value.object)
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
