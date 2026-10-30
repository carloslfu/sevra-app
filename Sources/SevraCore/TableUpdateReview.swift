import Foundation

/// Exact heading matches a person can accept at a glance. Nothing here is
/// applied: every target still goes through the preview and its checks.
public struct TableUpdateSuggestion: Codable, Equatable, Sendable {
  public let mapping: [IntakeColumnMapping]
  /// Declared unique columns only. Values are never inspected to infer a key.
  public let keys: [String]
  public let notes: [String]
}

extension TableUpdateSource {
  /// Case, width, spaces, hyphens and underscores do not distinguish a heading;
  /// accents and words do. A heading or column with two candidates stays unmapped.
  public func suggestion(for columns: [Column]) -> TableUpdateSuggestion {
    let stored = columns.filter { $0.formula == nil }
    var candidates: [Int: [String]] = [:]
    var claims: [String: [Int]] = [:]
    for (position, heading) in headings.enumerated() {
      let label = Self.label(heading)
      guard !label.isEmpty else { continue }
      let matches = stored.filter { Self.label($0.title) == label || Self.label($0.id) == label }
      candidates[position] = matches.map(\.id)
      for match in matches { claims[match.id, default: []].append(position) }
    }
    var mapping: [IntakeColumnMapping] = []
    var notes: [String] = []
    for position in headings.indices {
      guard let matches = candidates[position], !matches.isEmpty else { continue }
      if matches.count == 1, claims[matches[0]]?.count == 1 {
        mapping.append(.init(position: position, target: matches[0]))
      } else {
        notes.append("\u{201C}\(headings[position])\u{201D} has more than one possible match.")
      }
    }
    let matched = Set(mapping.compactMap(\.target))
    let unique = stored.filter { $0.unique == true && matched.contains($0.id) }
    return .init(mapping: mapping, keys: unique.count == 1 ? [unique[0].id] : [], notes: notes)
  }

  private static func label(_ text: String) -> String {
    text.precomposedStringWithCanonicalMapping
      .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
      .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "_-")))
      .filter { !$0.isEmpty }.joined(separator: " ")
  }
}

/// An in-progress review, saved so leaving or reopening does not lose it. It is a
/// presentation checkpoint: it changes no table, and preview and proposal recheck
/// every choice. An undecided input position has no entry in `decisions`; an entry
/// with a nil target is an explicit Ignore.
public struct TableUpdateDraft: Codable, Equatable, Sendable {
  public var version = 1
  public let sourceID: String
  public var intakeID: String?
  public var headerRow = 1
  public var sheet: String?
  public var datasetID: String?
  public var mode: TableUpdateMode?
  public var decisions: [IntakeColumnMapping] = []
  public var keys: [String] = []
  public var meaning = ""
  public var scenario = ""
  public init(sourceID: String) { self.sourceID = sourceID }

  /// Choices a changed table no longer supports are dropped, not reinterpreted.
  public func reconciled(headings: [String], columns: [Column]?) -> TableUpdateDraft {
    var result = self
    let stored = columns.map { Set($0.filter { $0.formula == nil }.map(\.id)) }
    if stored == nil { result.datasetID = nil }
    result.decisions = decisions.filter { entry in
      headings.indices.contains(entry.position)
        && (entry.target.map { stored?.contains($0) ?? false } ?? true)
    }
    result.keys = keys.filter { stored?.contains($0) ?? false }
    return result
  }
}

extension Workbook {
  public func tableUpdateDraft(_ sourceID: String) throws -> TableUpdateDraft? {
    let control = Cancellation(deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction { try readTableUpdateDraft(sourceID) }
      }
    }
  }

  public func saveTableUpdateDraft(_ draft: TableUpdateDraft) throws {
    try presentationMutation {
      try validateTableUpdateDraft(draft)
      let key = try tableUpdateDraftKey(draft.sourceID)
      let saved = try db.scalar("SELECT count(*) FROM meta WHERE key=?", [.string(key)]).int ?? 0
      if saved == 0 {
        try require(
          try db.scalar("SELECT count(*) FROM meta WHERE key LIKE 'table-update-draft:%'").int ?? 0
            < 256,
          "update_draft_limit", "This workbook already has 256 update drafts.")
      }
      try db.execute(
        "INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        [.string(key), .string(try encoded(draft).json())])
    }
  }

  public func discardTableUpdateDraft(_ sourceID: String) throws {
    try presentationMutation { try removeTableUpdateDraft(sourceID) }
  }

  /// Runs inside the proposal transaction: the draft ends with the review it produced.
  func removeTableUpdateDraft(_ sourceID: String) throws {
    try db.execute("DELETE FROM meta WHERE key=?", [.string(try tableUpdateDraftKey(sourceID))])
  }

  func verifyTableUpdateDrafts() throws {
    let rows = try db.execute(
      "SELECT key FROM meta WHERE key LIKE 'table-update-draft:%' ORDER BY key LIMIT 257")
    try require(rows.count <= 256, "update_draft_limit", "Too many saved update drafts.")
    for row in rows {
      _ = try readTableUpdateDraft(String(row["key"]!.text.dropFirst("table-update-draft:".count)))
    }
  }

  private func tableUpdateDraftKey(_ sourceID: String) throws -> String {
    try require(
      !sourceID.isEmpty && sourceID.utf8.count <= 256, "update_draft",
      "Use a saved original for this update draft.")
    return "table-update-draft:" + sourceID
  }

  private func readTableUpdateDraft(_ sourceID: String) throws -> TableUpdateDraft? {
    let key = try tableUpdateDraftKey(sourceID)
    guard let raw = try db.scalar("SELECT value FROM meta WHERE key=?", [.string(key)]).string
    else { return nil }
    let draft = try JSONDecoder().decode(TableUpdateDraft.self, from: Data(raw.utf8))
    try require(draft.sourceID == sourceID, "update_draft", "This update draft is mislabeled.")
    try validateTableUpdateDraft(draft)
    return draft
  }

  private func validateTableUpdateDraft(_ draft: TableUpdateDraft) throws {
    let source = try item(draft.sourceID)
    let positions = draft.decisions.map(\.position)
    try require(
      draft.version == 1 && source.category == "source" && source.assetID != nil
        && (1...1_048_576).contains(draft.headerRow)
        && draft.decisions.count <= 500 && Set(positions).count == positions.count
        && positions.allSatisfy { (0..<500).contains($0) }
        && draft.keys.count <= 500 && Set(draft.keys).count == draft.keys.count
        && (draft.sheet?.utf8.count ?? 0) <= 4096
        && (draft.meaning.isEmpty
          || ["actual", "estimate", "plan", "commitment", "assumption", "rule"].contains(
            draft.meaning))
        && draft.scenario.utf8.count <= 256,
      "update_draft", "This update draft has invalid choices.")
    try require(
      try encoded(draft).json().utf8.count <= 256_000, "update_draft_limit",
      "This update draft exceeds 256 KB.")
  }
}
