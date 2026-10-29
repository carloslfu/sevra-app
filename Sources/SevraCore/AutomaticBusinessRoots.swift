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
}
