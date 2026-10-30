import CryptoKit
import Foundation

/// A file's use is independent from its parser and from included/linked storage.
/// `values` explicitly imports saved cell values, without claiming Excel continuity.
public enum IntakeRole: String, Codable, Sendable { case reference, analysis, values, update }

public struct IntakeJob: Codable, Sendable, Identifiable {
  public let id: String
  public let sourceID: String
  public let role: IntakeRole?
  public let state: String
  public let report: Value
  public let datasetIDs: [String]
  public let detail: String
}

extension Workbook {
  /// One durable request spans capture, role selection and interpretation. A retry can
  /// finish from the saved original even if the input file has moved or disappeared.
  public func captureIntake(
    _ file: URL, linked: Bool = false, role: IntakeRole? = nil,
    token: String = UUID().uuidString, cancellation: Cancellation = .init()
  ) throws -> IntakeJob {
    try cancellation.check()
    try require(
      !token.isEmpty && token.utf8.count <= 512, "intake_token",
      "Invalid intake request identifier.")
    let pathHash = SHA256.hash(data: Data(file.standardizedFileURL.path.utf8))
      .map { String(format: "%02x", $0) }.joined()
    _ = try mutation(
      "intake_capture_request", token: token,
      request: .object([
        "input": .string(pathHash), "linked": .bool(linked),
        "role": role.map { .string($0.rawValue) } ?? .null,
      ]), cancellation: cancellation
    ) { .string(token) }
    let captured: Item
    if let prior = try synchronized({
      try db.execute(
        "SELECT result FROM operations WHERE id=? AND kind='import'",
        [.string(token + "-file")]
      ).first
    }) {
      captured = try item(Value.parse(prior["result"]!.text).text)
    } else {
      captured = try importFile(
        file, linked: linked, origin: "intake:" + token,
        cancellation: cancellation, token: token + "-file", independentInput: true)
    }
    return try beginIntake(sourceID: captured.id, role: role, token: token + "-use")
  }

  /// Recover the narrow crash window between a committed capture and job registration.
  func recoverCapturedIntake(_ source: Item) throws -> IntakeJob? {
    guard let assetID = source.assetID, let origin = try asset(assetID).origin,
      origin.hasPrefix("intake:")
    else { return nil }
    let token = String(origin.dropFirst("intake:".count))
    guard
      let request = try synchronized({
        try db.execute(
          "SELECT request FROM operations WHERE id=? AND kind='intake_capture_request'",
          [.string(token)]
        ).first
      })
    else { return nil }
    let role = try Value.parse(request["request"]!.text)["role"].string.flatMap(
      IntakeRole.init(rawValue:))
    return try beginIntake(sourceID: source.id, role: role, token: token + "-use")
  }

  /// Register after capture. Retrying this token cannot substitute another source or role.
  /// Another role may later use the same immutable source without copying it again.
  public func beginIntake(
    sourceID: String, role: IntakeRole? = nil, token: String = UUID().uuidString
  ) throws -> IntakeJob {
    _ = try mutation(
      "intake_begin", token: token,
      request: .object([
        "source": .string(sourceID), "role": role.map { .string($0.rawValue) } ?? .null,
      ])
    ) {
      let source = try item(sourceID)
      try require(
        source.category == "source" && source.assetID != nil, "intake_source",
        "Choose a captured original file.")
      let now = timestamp()
      try db.execute(
        "INSERT INTO intake_jobs VALUES(?,?,?,'captured',NULL,'{}','[]',?,?,?)",
        [
          .string(token), .string(source.id), role.map { .string($0.rawValue) } ?? .null,
          .string("Original saved. Indexing and use have not completed."), .string(now),
          .string(now),
        ])
      return .string(token)
    }
    return try intakeJob(token)
  }

  public func intakeJob(_ id: String) throws -> IntakeJob {
    try synchronized {
      guard let row = try db.execute("SELECT * FROM intake_jobs WHERE id=?", [.string(id)]).first
      else { throw SevraError("not_found", "Intake not found.") }
      return try decodeIntake(row)
    }
  }

  public func intakeJobs(sourceID: String? = nil, limit: Int = 100) throws -> [IntakeJob] {
    try require((1...500).contains(limit), "intake_limit", "Choose 1 to 500 intake results.")
    return try synchronized {
      let filter = sourceID == nil ? "" : " WHERE source_id=?"
      let parameters = sourceID.map { [Value.string($0)] } ?? []
      return try db.execute(
        "SELECT * FROM intake_jobs" + filter + " ORDER BY rowid DESC LIMIT ?",
        parameters + [.number(Double(limit))]
      ).map(decodeIntake)
    }
  }

  private func decodeIntake(_ row: [String: Value]) throws -> IntakeJob {
    .init(
      id: row["id"]!.text, sourceID: row["source_id"]!.text,
      role: row["role"]?.string.flatMap(IntakeRole.init(rawValue:)),
      state: row["state"]!.text, report: try Value.parse(row["report"]!.text),
      datasetIDs: try Value.parse(row["dataset_ids"]!.text).array.map(\.text),
      detail: row["detail"]!.text)
  }

  /// Role selection is a current explicit instruction, not an inference from file contents.
  public func chooseIntakeRole(
    _ id: String, role: IntakeRole, token: String = UUID().uuidString
  ) throws -> IntakeJob {
    _ = try mutation(
      "intake_role", token: token,
      request: .object(["id": .string(id), "role": .string(role.rawValue)])
    ) {
      let job = try intakeJob(id)
      try require(
        job.role == nil && job.state != "running", "intake_role",
        "This intake already has a use. Start another use from the saved original.")
      try db.execute(
        "UPDATE intake_jobs SET role=?,state='captured',attempt=NULL,detail=?,updated=? WHERE id=?",
        [
          .string(role.rawValue), .string("Use selected. Ready to continue."),
          .string(timestamp()), .string(id),
        ])
      return .string(id)
    }
    return try intakeJob(id)
  }

  /// No workbook lock is held during file extraction/inspection. Attempt fencing prevents a
  /// cancelled or superseded worker from replacing a newer result. Table batches are resumable.
  public func runIntake(_ id: String, cancellation: Cancellation = .init()) throws -> IntakeJob {
    try cancellation.check()
    let initial = try intakeJob(id)
    if initial.state == "ready" { return initial }
    let attempt = identifier()
    let claimed = try mutation("intake_run", cancellation: cancellation) {
      let job = try intakeJob(id)
      if job.state == "ready" { return .bool(false) }
      try db.execute(
        "UPDATE intake_jobs SET state='running',attempt=?,detail=?,updated=? WHERE id=?",
        [
          .string(attempt), .string("Indexing the saved original."), .string(timestamp()),
          .string(id),
        ])
      return .bool(true)
    }
    if claimed == .bool(false) { return try intakeJob(id) }
    let active = try intakeJob(id)
    var report = initial.report
    var tables = initial.datasetIDs
    func publish(_ state: String, _ detail: String) throws {
      _ = try mutation(
        "intake_result",
        request: .object([
          "id": .string(id), "attempt": .string(attempt), "state": .string(state),
        ])
      ) {
        try require(
          try db.scalar("SELECT attempt FROM intake_jobs WHERE id=?", [.string(id)]).text
            == attempt,
          "intake_superseded", "A newer intake attempt owns this result.")
        try db.execute(
          "UPDATE intake_jobs SET state=?,report=?,dataset_ids=?,detail=?,updated=? WHERE id=?",
          [
            .string(state), .string(try report.json()),
            .string(try Value.array(tables.map(Value.string)).json()), .string(detail),
            .string(timestamp()), .string(id),
          ])
        return .string(id)
      }
    }
    do {
      try extract(initial.sourceID, cancellation: cancellation)
      report = .object([
        "version": .number(1), "sourceID": .string(initial.sourceID),
        "index": try extractionStatus(initial.sourceID), "conversion": .string("none"),
      ])
      guard let role = active.role else {
        try publish("awaiting_role", "Original saved. How would you like to use it?")
        return try intakeJob(id)
      }
      if role == .reference {
        try publish(
          "ready", "Reference saved. No working tables created. See indexing status for coverage.")
        return try intakeJob(id)
      }
      if role == .update {
        try validateTableUpdateOriginal(initial.sourceID, cancellation: cancellation)
        try publish(
          "awaiting_update",
          "Original saved. Choose the target table, mapping and update method; review before applying."
        )
        return try intakeJob(id)
      }
      let source = try item(initial.sourceID)
      let file = try assetURL(source.assetID!, verify: true, cancellation: cancellation)
      let format = StructuredFormat(rawValue: file.pathExtension.lowercased())
      if let format {
        let parsed = try ExtractionWorker().readTable(
          file, format: format, cancellation: cancellation)
        _ = try assetURL(source.assetID!, verify: true, cancellation: cancellation)
        let sheets: [Value] = parsed.sheets.map { sheet in
          .object([
            "name": .string(sheet.name), "rows": .number(Double(sheet.rows.count)),
            "columns": .number(Double(sheet.rows.map(\.count).max() ?? 0)),
            "formulaCount": .number(Double(sheet.formulas.count)),
            "notes": .array(sheet.notes.map(Value.string)),
          ])
        }
        var fields = report.object
        fields["inspection"] = .object([
          "format": .string(format.rawValue), "sheets": .array(sheets),
          "coverage": .string(
            format == .xlsx ? "saved cell values and formula evidence" : "UTF-8 delimited values"),
          "liveExcelFormulas": .bool(false),
          "uninspectedFeatures": .string(
            format == .xlsx
              ? "Advanced features and native continuity are not qualified by this inspection."
              : "Delimiter and first-row header interpretation require review."),
        ])
        report = .object(fields)
      }
      try cancellation.check()
      try publish("running", "Original indexed and inspected. Continuing the selected use.")
      if role == .analysis {
        try publish(
          "ready", "Analysis input saved. No analysis or permanent working table has been created.")
      } else {
        try require(
          format != nil, "intake_format",
          "Saved-value tables currently support CSV, TSV and XLSX. The original remains available as a reference."
        )
        if format == .xlsx {
          tables = try importXLSX(initial.sourceID, cancellation: cancellation).map(\.id)
        } else {
          tables = [try importCSV(initial.sourceID, cancellation: cancellation).id]
        }
        var fields = report.object
        fields["conversion"] = .string("saved_values")
        report = .object(fields)
        try publish(
          "ready",
          tables.isEmpty
            ? "Original saved. No nonempty tables were found. Excel continuity is not implemented."
            : format == .xlsx
              ? "Saved-value tables created. Excel formulas are retained as evidence and do not recalculate."
              : "Working tables created from delimited values. The first row supplies the headings."
        )
      }
      return try intakeJob(id)
    } catch {
      if active.role == .values {
        // A batch can commit before cancellation or a later sheet fails. Keep its
        // actual dataset identity in the failed receipt instead of implying rollback.
        if let partial = try? synchronized({
          try db.execute(
            "SELECT id FROM datasets WHERE source_id=? OR source_id IN (SELECT child FROM lineage WHERE parent=?) ORDER BY id",
            [.string(initial.sourceID), .string(initial.sourceID)]
          ).map { $0["id"]!.text }
        }) {
          tables = partial
        }
      }
      // A cancelled or superseded worker must never mark a newer attempt failed.
      try? publish(
        cancellation.isCancelled ? "cancelled" : "failed",
        "Original retained. " + String(error.localizedDescription.prefix(4096)))
      throw error
    }
  }
}
