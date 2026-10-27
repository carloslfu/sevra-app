import Foundation

public enum BusinessTime {
  public static func normalized(_ value: String) throws -> String {
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
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    parser.timeZone = TimeZone(secondsFromGMT: 0)
    return parser.string(from: date)
  }
}

extension Workbook {
  public func setOpeningBalance(
    subject: String, quantity: String, effective: String, sourceID: String
  ) throws {
    let effective = try BusinessTime.normalized(effective)
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
    token: String = identifier(), requestSourceID: String? = nil
  ) throws -> Item {
    let effective = try BusinessTime.normalized(effective)
    try require(
      !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !occurrence.isEmpty,
      "movement", "Subject and occurrence must not be empty.")
    _ = try Numbers.decimal(quantity)
    var fields: [String: Value] = [
      "subject": .string(subject), "quantity": .string(quantity), "occurrence": .string(occurrence),
      "effective": .string(effective), "input": .string(input), "meaning": .string(meaning),
      "status": .string(status), "supersedes": supersedes.map(Value.string) ?? .null,
    ]
    // Preserve legacy idempotency bytes when no host request accompanies a call.
    if let requestSourceID { fields["requestSourceID"] = .string(requestSourceID) }
    let request = Value.object(fields)
    let result = try mutation("movement", token: token, request: request) {
      if let requestSourceID {
        let source = try item(requestSourceID)
        try require(
          source.category == "source" && source.kind == "request", "movement_request",
          "The movement request must reference its captured user submission.")
      }
      let logical = try supersedes.map { try item($0).logicalID }
      let existing = try db.execute(
        "SELECT DISTINCT i.logical_id FROM effects e JOIN items i ON i.id=e.item_id WHERE e.occurrence=? AND e.subject=? AND e.kind='inventory'",
        [.string(occurrence), .string(subject)])
      try require(
        existing.isEmpty
          || (logical != nil && existing.allSatisfy { $0["logical_id"]?.text == logical }),
        "duplicate_effect",
        "This business occurrence already has an inventory effect. Add supporting evidence or correct its existing record."
      )
      let id = try insertItem(
        category: "record", kind: "movement", title: "\(subject): \(quantity)",
        text: "\(quantity) inventory movement for \(subject)", data: request, meaning: meaning,
        status: status, scenario: meaning == "actual" ? "actual" : "planning",
        inputs: Array(
          Set([input] + (supersedes.map { [$0] } ?? []) + (requestSourceID.map { [$0] } ?? []))
        ).sorted(),
        transformation: "inventory-movement-v1",
        supersedes: supersedes)
      try db.execute(
        "INSERT INTO effects VALUES(?,?,?,?,?,?)",
        [
          .string(occurrence), .string(subject), .string("inventory"), .string(id),
          .string(quantity), .string(effective),
        ])
      return .string(id)
    }
    return try item(result.text)
  }
  @discardableResult public func accept(_ id: String, token: String = identifier()) throws -> Item {
    let result = try mutation("accept", token: token, request: .string(id)) {
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
        text: "The user accepted this interpretation.", data: .object(["record": .string(id)]),
        meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
        transformation: "human-accept-v1")
      var acceptedData = old.data
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
      return .string(newID)
    }
    return try item(result.text)
  }
  public func balance(subject: String, asOf: String = "9999-12-31T23:59:59Z") throws -> Value {
    let asOf = try BusinessTime.normalized(asOf)
    return try synchronized {
      guard
        let base = try db.execute("SELECT * FROM bases WHERE subject=?", [.string(subject)]).first
      else { throw SevraError("unknown_basis", "The opening balance is unknown for \(subject).") }
      try require(
        base["effective"]!.text <= asOf, "unknown_basis",
        "No opening basis exists before this date.")
      var total = try Numbers.decimal(base["quantity"]!.text)
      let rows = try db.execute(
        "SELECT e.*,i.logical_id FROM effects e JOIN items i ON i.id=e.item_id WHERE e.subject=? AND i.status='accepted' AND i.meaning='actual' AND i.scenario='actual' AND e.effective>? AND e.effective<=? AND NOT EXISTS(SELECT 1 FROM items n WHERE n.logical_id=i.logical_id AND n.version>i.version AND n.status IN ('accepted','rejected')) ORDER BY e.effective,e.item_id",
        [.string(subject), base["effective"]!, .string(asOf)])
      for row in rows {
        total = try Numbers.decimal(
          Numbers.calculate(
            "a+b", values: ["a": .string(Numbers.string(total)), "b": row["quantity"]!]))
      }
      return .object([
        "subject": .string(subject), "quantity": .string(Numbers.string(total)),
        "basis": base["source_id"]!, "effects": .array(rows.map(Value.object)),
        "asOf": .string(asOf),
      ])
    }
  }
}
