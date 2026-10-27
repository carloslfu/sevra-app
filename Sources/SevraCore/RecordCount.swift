import Foundation

extension Workbook {
  /// An exact metadata count, independent of FTS wording and extraction state.
  /// This proves only the stated current-record scope, never real-world absence.
  public func countRecords(
    _ filters: Value, cancellation: Cancellation = .init()
  ) throws -> Value {
    let allowed: Set<String> = ["category", "kind", "meaning", "status", "scenario"]
    try require(
      Set(filters.object.keys).isSubset(of: allowed), "count_scope", "Unknown count filter.")
    try require(
      ["source", "record"].contains(filters["category"].text), "count_scope",
      "Choose Sources or Records.")
    for (field, choices) in [
      "meaning": ["actual", "estimate", "plan", "commitment", "assumption", "rule"],
      "status": ["draft", "accepted", "rejected"],
    ] {
      if let value = filters[field].string {
        try require(choices.contains(value), "count_scope", "Unknown " + field + " filter.")
      }
    }
    var terms: [String] = []
    var values: [Value] = []
    for field in allowed.sorted() {
      guard let value = filters[field].string else {
        try require(filters[field] == .null, "count_scope", "Count filters must be text.")
        continue
      }
      try require(
        !value.isEmpty && value.utf8.count <= 128
          && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
        "count_scope", "Invalid count filter.")
      terms.append("i.\(field)=?")
      values.append(.string(value))
    }
    return try synchronized {
      try db.budget(cancellation: cancellation, seconds: 3) {
        try db.readTransaction {
          let count = try db.scalar(
            "SELECT count(*) FROM items i JOIN heads h ON h.item_id=i.id WHERE "
              + terms.joined(separator: " AND "), values)
          try cancellation.check()
          return .object([
            "scope": .string("current-classified-workbook-items"), "filters": filters,
            "count": count, "snapshotRevision": .number(Double(try revision())),
            "notice": .string(
              "Exact count of current classified workbook items matching every filter, including items without extracted text. Not a count of real-world events, unclassified information inside documents, historical versions, or external files. Use this call's receipt ID in finish.coverage; the host renders the scoped count. Do not turn it into a broader absence claim."
            ),
          ])
        }
      }
    }
  }
}
