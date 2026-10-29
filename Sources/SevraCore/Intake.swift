import CryptoKit
import Foundation

extension Workbook {
  public static func rowDigest(_ rows: [[String: Value]]) throws -> String {
    var digest = SHA256()
    for row in rows { digest.update(data: Data((try Value.object(row).json() + "\n").utf8)) }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }
  /// Committed batches survive cancellation. Retry uses the same source version and batch tokens.
  public func importDataset(
    title: String, columns: [Column], rows: [[String: Value]], sourceID: String,
    cancellation: Cancellation = .init(), progress: (Int, Int) -> Void = { _, _ in }
  ) throws -> Dataset {
    let token = "structured-import-v1-" + sourceID
    let table = try createDataset(
      title: title, columns: columns, rows: [], sourceID: sourceID, token: token)
    _ = try mutation("import_start", token: token + "-start", request: .number(Double(rows.count)))
    {
      let status: Value = .object([
        "sourceID": .string(sourceID), "datasetID": .string(table.id), "title": .string(title),
        "completed": .number(0), "total": .number(Double(rows.count)),
        "state": .string(rows.isEmpty ? "ready" : "partial"),
      ])
      try db.execute(
        "INSERT INTO meta VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        [.string("intake:" + table.id), .string(try status.json())])
      return .string(table.id)
    }
    for offset in stride(from: 0, to: rows.count, by: 1000) {
      try cancellation.check()
      let batch = Array(rows[offset..<min(rows.count, offset + 1000)])
      _ = try mutation(
        "import_batch", token: token + "-" + String(offset),
        request: .object([
          "rows": .string(try Self.rowDigest(batch)), "total": .number(Double(rows.count)),
        ])
      ) {
        let definition = try datasetDefinition(table.id)
        try require(
          definition.version == 1 && !definition.archived && definition.columns == columns,
          "import_changed",
          "The table definition changed after intake began. Keep the committed rows and review a new import instead of resuming into a different schema."
        )
        try require(
          try dataset(table.id).rowCount == offset, "import_changed",
          "Import rows changed. Resume from the same original source version.")
        for (index, values) in batch.enumerated() {
          try cancellation.check()
          try validateValues(values, columns: columns)
          let id = try insertItem(
            category: "record", kind: "row", title: "\(title.prefix(500)), row \(offset+index+1)",
            text: values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.text)" }.joined(
              separator: "\n"), data: .object(values), meaning: "actual", status: "accepted",
            scenario: "actual", inputs: [sourceID],
            transformation: "structured-import-v1", controlInputs: [definition.sourceID])
          try insertDatasetMember(
            table.id, ordinal: offset + index,
            logicalID: try item(id).logicalID)
        }
        let status: Value = .object([
          "sourceID": .string(sourceID), "datasetID": .string(table.id), "title": .string(title),
          "completed": .number(Double(offset + batch.count)), "total": .number(Double(rows.count)),
          "state": .string(offset + batch.count == rows.count ? "ready" : "partial"),
        ])
        try db.execute(
          "INSERT INTO meta VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
          [.string("intake:" + table.id), .string(try status.json())])
        return .string(table.id)
      }
      progress(min(rows.count, offset + batch.count), rows.count)
    }
    return try dataset(table.id)
  }
  public func intakeStatus() throws -> [Value] {
    try synchronized {
      try db.execute("SELECT value FROM meta WHERE key LIKE 'intake:%'").map {
        try Value.parse($0["value"]!.text)
      }
    }
  }
  public func pendingExtractions() throws -> [Value] {
    try synchronized {
      let indexed = try db.execute(
        "SELECT e.*,i.title,i.asset_id FROM extraction e JOIN items i ON i.id=e.item_id JOIN heads h ON h.item_id=i.id WHERE e.state IN ('queued','running','failed','cancelled') ORDER BY e.updated LIMIT 500"
      ).map(Extractor.displayStatus)
      guard indexed.count < 500 else { return indexed }
      let tables = try db.execute(
        "SELECT m.value FROM meta m JOIN heads h ON h.item_id=substr(m.key,19) WHERE m.key LIKE 'structured-intake:%' AND json_extract(m.value,'$.state') <> 'ready' ORDER BY m.key LIMIT ?",
        [.number(Double(500 - indexed.count))]
      ).map { try Value.parse($0["value"]!.text) }
      let jobs = try db.execute(
        "SELECT j.id AS job_id,j.source_id AS item_id,i.title,j.state,j.detail FROM intake_jobs j JOIN items i ON i.id=j.source_id WHERE j.state<>'ready' ORDER BY j.rowid DESC LIMIT ?",
        [.number(Double(500 - indexed.count - tables.count))]
      ).map(Value.object)
      return indexed + tables + jobs
    }
  }

  /// Intake status survives a parser failure or host interruption. It is derived
  /// operational state, independent from the file's successful content index.
  func trackStructuredIntake<T>(
    _ sourceID: String, cancellation: Cancellation, _ operation: () throws -> T
  ) throws -> T {
    try cancellation.check()
    let source = try item(sourceID)
    let attempt = identifier()
    let key = "structured-intake:" + sourceID
    var status: [String: Value] = [
      "item_id": .string(sourceID), "title": .string(source.title),
      "asset_id": source.assetID.map(Value.string) ?? .null,
      "attempt": .string(attempt), "state": .string("running"),
      "detail": .string("Reading table data. Resume if this import is interrupted."),
      "updated": .string(timestamp()), "parser": .string("structured-v1"),
    ]
    func store(_ value: [String: Value]?) throws {
      _ = try mutation(
        "structured_intake",
        request: .object([
          "source": .string(sourceID), "attempt": .string(attempt),
          "state": value?["state"] ?? .string("ready"),
        ])
      ) {
        let current = try db.execute("SELECT value FROM meta WHERE key=?", [.string(key)]).first
        if value?["state"]?.text != "running" {
          guard let current, try Value.parse(current["value"]!.text)["attempt"].text == attempt
          else {
            return .bool(false)
          }
        }
        if let value {
          try db.execute(
            "INSERT INTO meta VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            [.string(key), .string(try Value.object(value).json())])
        } else {
          var ready = status
          ready["state"] = .string("ready")
          ready["detail"] = .string("Table import complete.")
          ready["updated"] = .string(timestamp())
          try db.execute(
            "UPDATE meta SET value=? WHERE key=?",
            [.string(try Value.object(ready).json()), .string(key)])
        }
        return .bool(true)
      }
    }
    try store(status)
    do {
      let result = try operation()
      try store(nil)
      return result
    } catch {
      status["state"] = .string(cancellation.isCancelled ? "cancelled" : "failed")
      status["detail"] = .string("Table import: " + String(error.localizedDescription.prefix(4096)))
      status["updated"] = .string(timestamp())
      try store(status)
      throw error
    }
  }
  public func resumeIntake(_ sourceID: String, cancellation: Cancellation = .init()) throws {
    let existing = try intakeJobs(sourceID: sourceID, limit: 1).first
    if let job = try existing ?? recoverCapturedIntake(item(sourceID)) {
      if job.state == "ready" {
        // Retrying indexing never silently changes the selected use.
        try extract(sourceID, cancellation: cancellation)
      } else {
        _ = try runIntake(job.id, cancellation: cancellation)
      }
      return
    }
    let source = try item(sourceID)
    guard let id = source.assetID else {
      throw SevraError("asset", "Choose an original file source.")
    }
    _ = try assetURL(id, cancellation: cancellation)
    // Explicit importCSV/importXLSX calls already declared a table conversion.
    // Otherwise a source without intake state needs a role, including ZIP members.
    let tableWasRequested = try synchronized {
      try !db.execute(
        "SELECT value FROM meta WHERE key=?",
        [.string("structured-intake:" + sourceID)]
      ).isEmpty
    }
    let job = try beginIntake(sourceID: sourceID, role: tableWasRequested ? .values : nil)
    _ = try runIntake(job.id, cancellation: cancellation)
  }
}
