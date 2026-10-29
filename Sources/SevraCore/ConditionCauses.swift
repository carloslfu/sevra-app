import Foundation

extension Workbook {
  /// Resolves historical cause identity only. Admission and live permission must
  /// still be checked by the owning dispatcher, which is not enabled here.
  public func inventoryConditionCauses(
    _ observationID: String, cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      !observationID.isEmpty && observationID.utf8.count <= 256,
      "condition_input", "Use an exact complete condition observation.")
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try readBusinessFeed(cancellation: control) {
      try inspectInventoryConditionCauses(observationID, cancellation: control)
    }
  }

  func inspectInventoryConditionCauses(_ observationID: String, cancellation control: Cancellation)
    throws -> Value
  {
    let window = try inspectInventoryConditionOrigins(observationID, cancellation: control)
    let graph = window["origins"]
    let frontier = try businessCauseFrontier(graph, cancellation: control)
    let declarations = try inspectBusinessInputDeclarations(
      frontier.originals, cancellation: control)
    let qualified = Set(declarations.map { $0["sourceID"].text })
    let missing = frontier.originals.filter { !qualified.contains($0) }.map(Value.string)
    let automatic = frontier.automatic
    let parents = automatic.map { $0["runID"].text }.sorted()
    let inherited = Set(automatic.flatMap { $0["admission"]["roots"].array.map(\.text) })
    let independent = Set(declarations.map { $0["rootID"].text })
    let roots = inherited.union(independent).sorted()
    var reasons: [Value] = []
    if !missing.isEmpty { reasons.append(.string("undeclared-original-inputs")) }
    if !frontier.unclassified.isEmpty {
      reasons.append(.string("unclassified-business-origins"))
    }
    if roots.isEmpty { reasons.append(.string("no-qualified-cause")) }
    if roots.count > 8 { reasons.append(.string("more-than-eight-roots")) }
    if parents.count > 8 { reasons.append(.string("more-than-eight-automatic-parents")) }
    let result: Value = .object([
      "workbookID": .string(id), "policy": .string("condition-causes-v1"),
      "observationID": .string(observationID), "consumerID": window["consumerID"],
      "knowledgeBatchID": window["knowledgeBatchID"],
      "effectiveThrough": window["effectiveThrough"],
      "inputSetHash": window["inputSetHash"], "inputCount": window["inputCount"],
      "originInspection": .object([
        "command": .string("condition-origins"), "observationID": .string(observationID),
      ]),
      "resolution": .string(reasons.isEmpty ? "resolved" : "blocked"),
      "blockedReasons": .array(reasons), "declaredInputs": .array(declarations),
      "undeclaredOriginalInputIDs": .array(missing),
      "unclassifiedOrigins": .array(frontier.unclassified),
      "automaticParentRunIDs": .array(parents.map(Value.string)),
      "inheritedRootIDs": .array(inherited.sorted().map(Value.string)),
      "independentRootIDs": .array(independent.sorted().map(Value.string)),
      "rootIDs": .array(roots.map(Value.string)),
      "coverage": .string("complete-retained-window-with-declared-input-origins"),
      "producerFrontier": .string("nearest-automatic-producer-accounts-for-output-inputs"),
      "minimalCauseSet": .bool(false), "inputAuthenticity": .string("not-verified"),
      "dispatchEligibility": .string("not-evaluated"),
      "budgetEnforcement": .string("not-enabled"), "execution": .string("none"),
      "enabled": .bool(false),
    ])
    try boundedBusinessOutput(result)
    try control.check()
    return result
  }

  func inspectBusinessInputDeclarations(_ inputs: [String], cancellation: Cancellation) throws
    -> [Value]
  {
    var groups: [String: [[String: Value]]] = [:]
    for source in inputs.sorted() {
      try cancellation.check()
      if let row = try db.execute(
        "SELECT CAST(rowid AS TEXT) AS row_id,* FROM business_inputs WHERE source_id=?",
        [.string(source)], maxRows: 1, maxBytes: 8192
      ).first {
        groups[row["commit_id"]!.text, default: []].append(row)
      }
    }
    var remaining = 16_777_216
    var result: [Value] = []
    for commit in groups.keys.sorted() {
      try cancellation.check()
      guard
        let row = try db.execute(
          "SELECT hash,CASE WHEN length(CAST(payload AS BLOB))<=? THEN payload END AS payload FROM committed_changes WHERE id=?",
          [.number(Double(remaining)), .string(commit)], maxRows: 1, maxBytes: remaining + 8192
        ).first
      else {
        throw SevraError("business_input_integrity", "A declared input lost its creating change.")
      }
      try require(
        row["payload"] != .null, "business_input_limit",
        "Original input inspection exceeds its 16 MiB creating-change budget.")
      let raw = row["payload"]!.text
      remaining -= raw.utf8.count
      try require(
        ChangeFormat.hash(raw) == row["hash"]!.text,
        "business_input_integrity", "An original input's creating change failed its hash.")
      guard let change = try? JSONDecoder().decode(CommittedChange.self, from: Data(raw.utf8))
      else {
        throw SevraError(
          "business_input_integrity", "The original input's creating change is malformed.")
      }
      try change.actor.validate()
      try require(
        change.id == commit && change.workbookID == id && change.version == 1
          && change.storageVersion == Schema.version && change.changes.count <= 250_000,
        "business_input_integrity",
        "The original input has a foreign or unsupported creating change."
      )
      for declaration in groups[commit]! {
        try cancellation.check()
        let rowID = declaration["row_id"]!.text
        let retained = try db.savedRow("business_inputs", id: rowID)!
        try db.validateBusinessInputDeclaration(retained, change: change)
        try require(
          change.changes.contains {
            $0.table == "business_inputs" && $0.before == nil && $0.after == retained
              && $0.resetProjection == nil
          }, "business_input_integrity", "The creating change does not retain this declaration.")
        result.append(
          .object([
            "sourceID": declaration["source_id"]!, "creatingCommitID": .string(commit),
            "kind": declaration["kind"]!, "policy": declaration["policy"]!,
            "rootID": .string(try BusinessInput.root(workbook: id, commit: commit)),
            "qualification": .string("explicit-host-input-intent"),
          ]))
      }
    }
    return result.sorted { $0["sourceID"].text < $1["sourceID"].text }
  }
}
