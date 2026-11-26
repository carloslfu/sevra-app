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
  @discardableResult public func accept(
    _ id: String, token: String = identifier(), cancellation: Cancellation = .init(),
    actor: ChangeActor = .programmatic("SevraCore.accept")
  ) throws -> Item {
    // Accepting a reviewed update rewrites up to 10,000 rows in one change.
    let accepted = try mutation(
      "accept", token: token, request: .string(id), cancellation: cancellation, actor: actor,
      deadlineSeconds: 30,
      reading: { try item($0.text) }
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
      if old.kind == "table-intake-update", let runID = old.data["workflow"]["runID"].string {
        WorkflowPublicationProbe.observer?(.prepared, runID)
      }
      return .string(newID)
    }
    if accepted.kind == "table-intake-update", let runID = accepted.data["workflow"]["runID"].string
    {
      WorkflowPublicationProbe.observer?(.committed, runID)
    }
    return accepted
  }
}
