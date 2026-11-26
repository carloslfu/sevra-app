import Foundation

extension Workbook {
  func qualifiedAdmissionInputs(
    _ sources: [String], cancellation: Cancellation = .init(), limit: Int = 1024
  ) throws
    -> [Value]
  {
    try require(
      sources.count <= limit && sources.allSatisfy { !$0.isEmpty && $0.utf8.count <= 256 },
      "causal_inputs", "Use at most1,024 exact declared original inputs.")
    let exact = Array(Set(sources)).sorted()
    let declarations = try inspectBusinessInputDeclarations(exact, cancellation: cancellation)
    try require(
      declarations.count == exact.count, "causal_inputs",
      "Every independent input must retain its exact original creating declaration.")
    return declarations
  }

  func retainBusinessCausalRoots(_ declarations: [Value]) throws {
    var retained = Set<String>()
    for declaration in declarations {
      let root = declaration["rootID"].text
      guard retained.insert(root).inserted else { continue }
      if try db.scalar("SELECT EXISTS(SELECT 1 FROM automatic_roots WHERE id=?)", [.string(root)])
        .int == 1
      {
        try validateBusinessCausalRoot(root, commit: declaration["creatingCommitID"].text)
      } else {
        try db.execute(
          "INSERT INTO automatic_roots VALUES(?,'business',NULL,?,?,?,?)",
          [
            .string(root), declaration["creatingCommitID"], .string(BusinessInput.policy),
            declaration["sourceID"], .string(timestamp()),
          ])
      }
    }
  }

  func validateBusinessCausalRoot(
    _ id: String, commit: String, cancellation: Cancellation = .init(),
    declarations: [String: Value]? = nil
  ) throws {
    guard
      let row = try db.execute(
        "SELECT kind,occurrence_id,commit_id,policy,source_id FROM automatic_roots WHERE id=?",
        [.string(id)], maxRows: 1, maxBytes: 8192
      ).first
    else { throw SevraError("causal_integrity", "A business root lost its retained identity.") }
    try require(
      row["kind"] == .string("business") && row["occurrence_id"] == .null
        && row["commit_id"] == .string(commit) && row["policy"] == .string(BusinessInput.policy)
        && id == BusinessInput.root(workbook: self.id, commit: commit),
      "causal_integrity", "A business root lost its exact creating change.")
    let source: Value
    if let declarations {
      source = declarations[row["source_id"]!.text] ?? .null
    } else {
      source = try qualifiedAdmissionInputs([row["source_id"]!.text], cancellation: cancellation)[0]
    }
    try require(
      source["creatingCommitID"] == .string(commit) && source["rootID"] == .string(id),
      "causal_integrity", "A business root lost its representative original input.")
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
