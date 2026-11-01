import Foundation

enum BusinessInput {
  static let policy = "business-input-v1"
  static let kinds: Set<String> = ["observation", "external-file", "request"]

  static func root(workbook: String, commit: String) throws -> String {
    "business-root:"
      + ChangeFormat.hash(
        try Value.array([.string(policy), .string(workbook), .string(commit)]).json())
  }
}

extension Workbook {
  /// An explicit new observation, rather than a review, revision or derivation.
  /// The host owns that intent. This is not an ordinary model tool or truth claim.
  @discardableResult public func recordBusinessObservation(
    title: String, text: String = "", data: Value = .object([:]), token: String = identifier(),
    cancellation: Cancellation = .init()
  ) throws -> Item {
    try require(
      !token.isEmpty && token.utf8.count <= 512, "business_input",
      "Use a nonempty observation token up to 512 UTF-8 bytes.")
    let result = try mutation(
      "business_observation", token: token,
      request: .object(["title": .string(title), "text": .string(text), "data": data]),
      cancellation: cancellation
    ) {
      let source = try insertItem(
        category: "source", kind: "observation", title: title, text: text, data: data,
        meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
        transformation: BusinessInput.policy)
      try declareNewBusinessInput(source, kind: "observation")
      return .string(source)
    }
    return try item(result.text)
  }

  /// The user's words as the host received them. A movement can rest on these alone, so
  /// they start a business origin. A `request` Source any other writer saves does not.
  package func captureUserRequest(
    _ text: String, data: Value, token: String, cancellation: Cancellation = .init()
  ) throws -> Item {
    let result = try mutation(
      "user_request", token: token, request: .object(["text": .string(text), "data": data]),
      cancellation: cancellation
    ) {
      let source = try insertItem(
        category: "source", kind: "request", title: "User request", text: text, data: data,
        meaning: "plan", status: "accepted", scenario: "actual", inputs: [],
        transformation: "conversation-submission-v1")
      try declareNewBusinessInput(source, kind: "request")
      return .string(source)
    }
    return try item(result.text)
  }

  func declareNewBusinessInput(_ id: String, kind: String) throws {
    try require(
      db.changes?.publishing == false && db.changes?.actor.kind != "ai"
        && BusinessInput.kinds.contains(kind),
      "business_input", "Only an explicit host input can establish a new business origin.")
    try db.validateNewBusinessInput(id, kind: kind)
    db.changes?.businessInputs[id] = kind
  }

  func verifyBusinessInputDeclarations() throws {
    var total = 0
    try db.visitCommittedEnvelopes { change, _, _ in
      for entry in change.changes where entry.table == "business_inputs" {
        try require(
          entry.before == nil && entry.resetProjection == nil && entry.after != nil,
          "business_input_integrity", "Independent input declarations are immutable.")
        let row = entry.after!
        try db.validateBusinessInputDeclaration(row, change: change)
        try require(
          try db.savedRow("business_inputs", id: row.rowID) == row,
          "business_input_integrity", "A declared original input lost its retained coordinates.")
        total += 1
      }
    }
    try require(
      try db.scalar("SELECT count(*) FROM business_inputs").int == total,
      "business_input_integrity", "An original input declaration has no creating change.")
  }
}

extension Database {
  func validateNewBusinessInput(_ id: String, kind: String) throws {
    try require(
      changes?.pending?.contains {
        $0.table == "items" && $0.before == nil && $0.after?.values.first?.string == id
      } == true, "business_input", "An existing Source cannot be declared independent later.")
    let row = try execute(
      "SELECT category,kind,version,supersedes,asset_id FROM items WHERE id=?", [.string(id)],
      maxRows: 1, maxBytes: 8192
    ).first
    try require(
      row?["category"] == .string("source") && row?["version"] == .number(1)
        && row?["supersedes"] == .null
        && ((kind == row?["kind"]?.string && kind != "external-file")
          || (kind == "external-file" && row?["kind"] == .string("document")
            && row?["asset_id"] != .null))
        && scalar("SELECT EXISTS(SELECT 1 FROM lineage WHERE child=?)", [.string(id)]).int == 0,
      "business_input", "An independent input must be a new original observation or file.")
  }

  func validateBusinessInputDeclaration(_ row: ChangeRow, change: CommittedChange) throws {
    let values = row.values
    guard values.count == 5, let source = values[0].string,
      values[1].string == change.id, case .integer(let position) = values[2],
      let index = Int(position), change.changes.indices.contains(index),
      let kind = values[3].string, BusinessInput.kinds.contains(kind),
      values[4].string == BusinessInput.policy
    else {
      throw SevraError("business_input_integrity", "An original input declaration is malformed.")
    }
    let entry = change.changes[index]
    let item = entry.after?.values ?? []
    try require(
      change.actor.kind != "ai" && entry.table == "items" && entry.before == nil
        && entry.resetProjection == nil && item.count == 15 && item[0].string == source
        && item[2] == .integer("1") && item[3].string == "source" && item[12] == .null
        && ((kind == item[4].string && kind != "external-file")
          || (kind == "external-file" && item[4].string == "document" && item[11] != .null))
        && !change.changes.contains {
          $0.table == "lineage" && $0.after?.values.first?.string == source
        },
      "business_input_integrity", "An original input lost its exact creating Source insertion.")
    let current = try execute(
      "SELECT logical_id,version,category,kind,asset_id,supersedes FROM items WHERE id=?",
      [.string(source)], maxRows: 1, maxBytes: 8192
    ).first
    try require(
      current?["logical_id"]?.string == item[1].string && current?["version"] == .number(1)
        && current?["category"]?.string == item[3].string
        && current?["kind"]?.string == item[4].string
        && current?["asset_id"]?.string == item[11].string && current?["supersedes"] == .null
        && scalar("SELECT EXISTS(SELECT 1 FROM lineage WHERE child=?)", [.string(source)]).int == 0,
      "business_input_integrity", "A declared original input changed identity or gained derivation."
    )
  }
}

extension ChangeCapture {
  func publishBusinessInputs(_ database: Database, commitID: String) throws {
    try require(
      businessInputs.isEmpty || actor.kind != "ai", "business_input",
      "AI output cannot declare an independent input.")
    for (source, kind) in businessInputs.sorted(by: { $0.key < $1.key }) {
      try database.validateNewBusinessInput(source, kind: kind)
      guard
        let position = pending?.firstIndex(where: {
          $0.table == "items" && $0.before == nil && $0.after?.values.first?.string == source
        })
      else { throw SevraError("business_input_integrity", "The new input lost its insertion.") }
      try database.execute(
        "INSERT INTO business_inputs VALUES(?,?,?,?,?)",
        [
          .string(source), .string(commitID), .number(Double(position)), .string(kind),
          .string(BusinessInput.policy),
        ])
    }
  }
}
