import Foundation

extension Workbook {
  /// Compensating row versions and stable membership restoration, inside the undo transaction.
  /// Metadata is inverted so undoing this result performs a checked redo.
  func restoreTableIntake(_ current: Item, cancellation: Cancellation) throws -> Value {
    let data = current.data
    let datasetID = current.data["datasetID"].text
    try require(
      try tableFingerprint(datasetID) == data["afterFingerprint"].text,
      "stale_revision",
      "The table changed after this update. Review its current data before undoing.")
    let desired = data["beforeMembership"].array
    let versions = data["rowVersions"].array
    try require(
      desired.count <= 10_000 && versions.count <= 11_000,
      "update_limit", "This undo exceeds the bounded table-update limits.")
    for pair in versions {
      try cancellation.check()
      let row = try item(pair["after"].text)
      try require(
        try item(row.logicalID).id == row.id, "stale_revision",
        "An affected row changed after this update, including a removed row.")
    }
    let starting = try tableMembership(datasetID)
    let desiredLogicals = Set(desired.map { $0["logical_id"].text })
    try require(
      desiredLogicals.count == desired.count
        && Set(desired.map { $0["row_id"].text }).count == desired.count,
      "update_definition", "Invalid saved membership for this undo.")
    let decision = try insertItem(
      category: "source", kind: "decision", title: "Restore table update",
      text: "The user requested a checked restoration of the previous table state.",
      data: .object(["record": .string(current.id)]), meaning: "actual",
      status: "accepted", scenario: "actual", inputs: [],
      transformation: "human-table-intake-undo-v1")
    var inverse: [Value] = []
    for member in starting where !desiredLogicals.contains(member["logical_id"].text) {
      try cancellation.check()
      let old = try item(member["item_id"].text)
      let next = try intakeRowVersion(
        old, values: old.data, status: "rejected",
        inputs: [current.id, decision], transformation: "table-intake-undo-remove-v1")
      inverse.append(.object(["before": .string(old.id), "after": .string(next)]))
    }
    for member in desired {
      try cancellation.check()
      let saved = try item(member["item_id"].text)
      try require(
        saved.category == "record" && saved.kind == "row"
          && saved.logicalID == member["logical_id"].text
          && member["ordinal"].int != nil && member["ordinal"].int! >= 0,
        "update_definition", "Invalid saved row for this undo.")
      let now = try item(saved.logicalID)
      if now.id != saved.id {
        let next = try insertItem(
          category: "record", kind: saved.kind, title: saved.title,
          text: rowDescription(saved.data.object), data: saved.data,
          meaning: saved.meaning, status: saved.status, scenario: saved.scenario,
          inputs: [now.id, saved.id, current.id, decision],
          transformation: "table-intake-undo-restore-v1", supersedes: now.id)
        inverse.append(.object(["before": .string(now.id), "after": .string(next)]))
      }
    }
    try db.execute("DELETE FROM dataset_rows WHERE dataset_id=?", [.string(datasetID)])
    for member in desired {
      try cancellation.check()
      try db.execute(
        "INSERT INTO dataset_rows VALUES(?,?,?,?)",
        [.string(datasetID), member["row_id"], member["ordinal"], member["logical_id"]])
    }
    var restored = data.object
    restored["beforeMembership"] = .array(starting)
    restored["afterMembership"] = .array(try tableMembership(datasetID))
    restored["rowVersions"] = .array(inverse)
    restored["afterFingerprint"] = .string(try tableFingerprint(datasetID))
    return .object(restored)
  }
}
