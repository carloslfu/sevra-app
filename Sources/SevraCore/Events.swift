import Foundation

public enum BusinessTime {
  public static func normalized(_ value: String) throws -> String {
    try require(
      value.utf8.count <= 40
        && value.range(
          of:
            "^[0-9]{4}-[0-9]{2}-[0-9]{2}(?:T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]{1,9})?(?:Z|[+-][0-9]{2}:[0-9]{2}))?\\z",
          options: .regularExpression) != nil,
      "date", "Use YYYY-MM-DD or an ISO timestamp with seconds and an explicit time zone.")
    let parts = value.prefix(10).split(separator: "-").compactMap { Int($0) }
    let calendar = Calendar(identifier: .gregorian)
    let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
    try require(
      parts[0] > 0 && components.isValidDate(in: calendar), "date",
      "This calendar date does not exist.")
    if value.count > 10 {
      let time = value.dropFirst(11).prefix(8).split(separator: ":").compactMap { Int($0) }
      try require(
        time[0] < 24 && time[1] < 60 && time[2] < 60, "date", "This clock time does not exist.")
      if !value.hasSuffix("Z") {
        let zone = value.suffix(5).split(separator: ":").compactMap { Int($0) }
        try require(zone[0] < 24 && zone[1] < 60, "date", "Invalid time-zone offset.")
      }
    }
    let input = value.count == 10 ? value + "T00:00:00Z" : value
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = parser.date(from: input)
    if date == nil {
      parser.formatOptions = [.withInternetDateTime]
      date = parser.date(from: input)
    }
    guard let date else {
      throw SevraError("date", "Use an ISO 8601 date or timestamp, including a time zone.")
    }
    // This calendar jumps from 1582-10-04 to 1582-10-15 and moves any date between them.
    if value < "1583" {
      parser.formatOptions = [.withInternetDateTime]
      let written = String(value.prefix(19))
      let wall = parser.date(from: written + (value.count == 10 ? "T00:00:00Z" : "Z"))
      let change = parser.date(from: "1582-10-15T00:00:00Z")!
      try require(
        wall.map { parser.string(from: $0).hasPrefix(written) && ($0 < change) == (date < change) }
          == true, "date", "This calendar date does not exist.")
    }
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    parser.timeZone = TimeZone(secondsFromGMT: 0)
    // An offset can carry a date out of the four-digit years, where this text stops naming it.
    let normalized = parser.string(from: date)
    let stored = parser.date(from: normalized)
    try require(
      normalized.utf8.count == 24 && stored.map { abs($0.timeIntervalSince(date)) < 1 } == true,
      "date", "Use a date between the years 0001 and 9999.")
    return normalized
  }
}

extension Workbook {
  /// Drafts do not replace the last accepted/withdrawn decision.
  /// Call within the workbook transaction when restoring a review decision.
  func settledVersion(_ logicalID: String, before version: Int) throws -> Item? {
    try db.execute(
      "SELECT * FROM items WHERE logical_id=? AND version<? AND status IN ('accepted','rejected') ORDER BY version DESC LIMIT 1",
      [.string(logicalID), .number(Double(version))]
    ).first.map(decodeItem)
  }
  public func setOpeningBalance(
    subject: String, quantity: String, effective: String, sourceID: String
  ) throws {
    let effective = try BusinessTime.normalized(effective)
    let subject = subject.precomposedStringWithCanonicalMapping
    _ = try Numbers.decimal(quantity)
    _ = try item(sourceID)
    _ = try mutation(
      "opening_balance",
      request: .object(["subject": .string(subject), "quantity": .string(quantity)])
    ) {
      try require(
        try db.scalar("SELECT count(*) FROM bases WHERE subject=?", [.string(subject)]).int == 0,
        "basis_exists",
        "This subject already has an opening basis. Record a correction or reconciliation explicitly."
      )
      try db.execute(
        "INSERT INTO bases VALUES(?,?,?,?)",
        [.string(subject), .string(quantity), .string(effective), .string(sourceID)])
      return .string(subject)
    }
  }
  @discardableResult public func movement(
    subject: String, quantity: String, occurrence: String, effective: String, input: String,
    meaning: String = "actual", status: String = "draft", supersedes: String? = nil,
    token: String = identifier(), requestSourceID: String? = nil,
    cancellation: Cancellation = .init(), actor: ChangeActor? = nil
  ) throws -> Item {
    let request = try movementRequest(
      subject: subject, quantity: quantity, occurrence: occurrence, effective: effective,
      input: input, meaning: meaning, status: status, supersedes: supersedes,
      requestSourceID: requestSourceID)
    let result = try mutation(
      "movement", token: token, request: request, cancellation: cancellation, actor: actor
    ) { .string(try self.insertMovement(request)) }
    return try item(result.text)
  }

  func movementRequest(
    subject: String, quantity: String, occurrence: String, effective: String, input: String,
    meaning: String = "actual", status: String = "draft", supersedes: String? = nil,
    requestSourceID: String? = nil
  ) throws -> Value {
    let effective = try BusinessTime.normalized(effective)
    // SQL compares these by bytes and Swift by canonical equivalence, so keep one form.
    let subject = subject.precomposedStringWithCanonicalMapping
    let occurrence = occurrence.precomposedStringWithCanonicalMapping
    try require(
      !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !occurrence.isEmpty,
      "movement", "Subject and occurrence must not be empty.")
    // Consumers read effects in bounded rows, so one oversized value would stop them for good.
    try require(
      occurrence.utf8.count <= 512, "movement", "An occurrence is limited to 512 bytes.")
    _ = try Numbers.decimal(quantity)
    var fields: [String: Value] = [
      "subject": .string(subject), "quantity": .string(quantity), "occurrence": .string(occurrence),
      "effective": .string(effective), "input": .string(input), "meaning": .string(meaning),
      "status": .string(status), "supersedes": supersedes.map(Value.string) ?? .null,
    ]
    if let requestSourceID { fields["requestSourceID"] = .string(requestSourceID) }
    return .object(fields)
  }

  /// The same read-only domain preconditions serve preview and transactional publication.
  func validateMovement(_ request: Value) throws {
    let subject = request["subject"].text
    let occurrence = request["occurrence"].text
    let input = try item(request["input"].text)
    try require(input.id == request["input"].text, "movement_input", "Use exact local evidence.")
    if let requestID = request["requestSourceID"].string {
      let source = try item(requestID)
      try require(
        source.id == requestID && source.category == "source" && source.kind == "request",
        "movement_request", "The movement request must reference its captured user submission.")
    }
    // Nothing turns an estimate, plan or other scenario into actual stock. A captured request
    // is the user's own report, so its `plan` meaning says nothing about the event it reports.
    let actual = request["meaning"] == .string("actual")
    try require(
      !actual
        || ((input.meaning == "actual" || input.kind == "request") && input.scenario == "actual"),
      "interpretation_meaning", "Actual stock cannot rest on an estimate, plan or another scenario."
    )
    let previous = try request["supersedes"].string.map(item)
    if let previous {
      try require(
        !actual || (previous.meaning == "actual" && previous.scenario == "actual"),
        "interpretation_meaning",
        "A correction cannot turn an estimate or plan into actual stock. Record the event as its own occurrence."
      )
      try require(
        previous.id == request["supersedes"].text, "movement_revision",
        "A correction needs the exact movement version.")
      try require(
        previous.kind == "movement" && previous.data["subject"].text == subject
          && previous.data["occurrence"].text == occurrence,
        "movement_revision", "A correction must keep the same inventory subject and occurrence.")
      try require(
        try item(previous.logicalID).id == previous.id, "stale_revision",
        "This record has a newer version.")
    }
    let existing = try db.execute(
      "SELECT DISTINCT i.logical_id FROM effects e JOIN items i ON i.id=e.item_id WHERE e.occurrence=? AND e.subject=? AND e.kind='inventory'",
      [.string(occurrence), .string(subject)])
    try require(
      existing.isEmpty
        || (previous != nil
          && existing.allSatisfy {
            $0["logical_id"]?.text == previous?.logicalID
          }),
      "duplicate_effect",
      "This business occurrence already has an inventory effect. Add supporting evidence or correct its existing record."
    )
  }

  /// Trusted callers already hold the canonical mutation transaction. Never nest mutations.
  func insertMovement(
    _ request: Value, additionalInputs: [String] = [], producerInputs: [String] = []
  ) throws -> String {
    try validateMovement(request)
    let subject = request["subject"].text
    let quantity = request["quantity"].text
    let meaning = request["meaning"].text
    let supersedes = request["supersedes"].string
    let id = try insertItem(
      category: "record", kind: "movement", title: "\(subject): \(quantity)",
      text: "\(quantity) inventory movement for \(subject)", data: request, meaning: meaning,
      status: request["status"].text, scenario: meaning == "actual" ? "actual" : "planning",
      inputs: Array(
        Set(
          [request["input"].text] + additionalInputs
            + (supersedes.map { [$0] } ?? [])
            + (request["requestSourceID"].string.map { [$0] } ?? []))
      ).sorted(),
      transformation: "inventory-movement-v1", supersedes: supersedes,
      producerInputs: producerInputs)
    try db.execute(
      "INSERT INTO effects VALUES(?,?,?,?,?,?)",
      [
        request["occurrence"], .string(subject), .string("inventory"), .string(id),
        .string(quantity), request["effective"],
      ])
    return id
  }
  @discardableResult public func accept(
    _ id: String, token: String = identifier(), cancellation: Cancellation = .init(),
    actor: ChangeActor = .programmatic("SevraCore.accept")
  ) throws -> Item {
    // Accepting a reviewed update rewrites up to 10,000 rows in one change.
    let result = try mutation(
      "accept", token: token, request: .string(id), cancellation: cancellation, actor: actor,
      deadlineSeconds: 30
    ) {
      try validateDecisionActor(actor)
      let old = try item(id)
      try require(
        try db.scalar("SELECT item_id FROM heads WHERE logical_id=?", [.string(old.logicalID)]).text
          == id, "stale_revision",
        "This record has a newer version. Review the current version before accepting.")
      try require(
        old.status != "rejected", "rejected",
        "This interpretation was withdrawn. Undo that withdrawal or create a revised proposal before accepting."
      )
      if old.status == "accepted" { return .string(old.id) }
      let evidence = try insertItem(
        category: "source", kind: "decision", title: "Accept \(old.title)",
        text: actor.label + " accepted this interpretation.", data: try decisionData(id),
        meaning: "actual", status: "accepted", scenario: "actual", inputs: [old.id],
        transformation: "decision-accept-v2", controlInputs: decisionInputs())
      var acceptedData = old.data
      if old.kind == "table-intake-update" {
        acceptedData = try applyTableIntake(old, decision: evidence, cancellation: cancellation)
        if old.data["workflow"] != .null {
          var applied = acceptedData.object
          applied["acceptanceOperationID"] = .string(token)
          applied["decisionID"] = .string(evidence)
          acceptedData = .object(applied)
        }
      }
      if old.kind == "table-creation" {
        let columns = try JSONDecoder().decode(
          [Column].self, from: Data(old.data["columns"].json().utf8))
        let datasetID = identifier()
        try insertDataset(
          id: datasetID, title: old.data["title"].text, columns: columns,
          rows: old.data["rows"].array.map(\.object), sourceID: evidence,
          inputs: [old.id, evidence], meaning: old.meaning)
        var values = old.data.object
        values["datasetID"] = .string(datasetID)
        acceptedData = .object(values)
      }
      if old.kind == "table-change" {
        let edits = try JSONDecoder().decode(
          [RowEdit].self, from: Data(old.data["edits"].json().utf8))
        let change = try applyRows(
          old.data["datasetID"].text, edits: edits, request: old.data, proposalID: old.id)
        var values = old.data.object
        values["tableChangeID"] = change["id"]
        acceptedData = .object(values)
      }
      let newID = try insertItem(
        category: old.category, kind: old.kind, title: old.title, text: old.text,
        data: acceptedData,
        meaning: old.meaning, status: "accepted", scenario: old.scenario,
        inputs: [old.id, evidence], transformation: "accept-v1", assetID: old.assetID,
        supersedes: old.id)
      try db.execute(
        "INSERT INTO effects SELECT occurrence,subject,kind,?,quantity,effective FROM effects WHERE item_id=?",
        [.string(newID), .string(old.id)])
      if old.kind == "table-intake-update", let runID = old.data["workflow"]["runID"].string {
        WorkflowPublicationProbe.observer?(.prepared, runID)
      }
      return .string(newID)
    }
    let accepted = try item(result.text)
    if accepted.kind == "table-intake-update", let runID = accepted.data["workflow"]["runID"].string
    {
      WorkflowPublicationProbe.observer?(.committed, runID)
    }
    return accepted
  }
  /// A dated entry is not stock until its date arrives, so `asOf` defaults to now. Accepted
  /// effects outside the period stay visible: a quantity never hides what it left out.
  public func balance(subject: String, asOf: String? = nil) throws -> Value {
    let asOf = try BusinessTime.normalized(asOf ?? timestamp())
    let subject = subject.precomposedStringWithCanonicalMapping
    return try synchronized {
      guard
        let base = try db.execute("SELECT * FROM bases WHERE subject=?", [.string(subject)]).first
      else { throw SevraError("unknown_basis", "The opening balance is unknown for \(subject).") }
      try require(
        base["effective"]!.text <= asOf, "unknown_basis",
        "No opening basis exists before this date.")
      var total = try Numbers.decimal(base["quantity"]!.text)
      let settled =
        "FROM effects e JOIN items i ON i.id=e.item_id WHERE e.subject=? AND i.status='accepted' AND i.meaning='actual' AND i.scenario='actual' AND NOT EXISTS(SELECT 1 FROM items n WHERE n.logical_id=i.logical_id AND n.version>i.version AND n.status IN ('accepted','rejected'))"
      let period: [Value] = [.string(subject), base["effective"]!, .string(asOf)]
      let rows = try db.execute(
        "SELECT e.*,i.logical_id \(settled) AND e.effective>? AND e.effective<=? ORDER BY e.effective,e.item_id",
        period)
      for row in rows {
        total = try exactInventorySum(total, Numbers.decimal(row["quantity"]!.text))
      }
      let outside = "AND (e.effective<=? OR e.effective>?)"
      let excluded = try db.execute(
        "SELECT e.*,i.logical_id \(settled) \(outside) ORDER BY e.effective,e.item_id LIMIT 20",
        period)
      return .object([
        "subject": .string(subject), "quantity": .string(Numbers.string(total)),
        "basis": base["source_id"]!, "effects": .array(rows.map(Value.object)),
        "asOf": .string(asOf),
        "excludedCount": try db.scalar("SELECT count(*) \(settled) \(outside)", period),
        "excludedEffects": .array(
          excluded.map { row in
            var effect = row
            effect["reason"] = .string(
              row["effective"]!.text > asOf ? "after-as-of" : "not-after-basis")
            return .object(effect)
          }),
      ])
    }
  }
}
