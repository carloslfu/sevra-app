import Foundation

public struct WorkflowClarificationEntry: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let target: Value
  public var values: Value = .object([:])
  public var reason = ""
  public let token: String
  public var receipt: Value?
  public var preparation: Value?
  public init(target: Value) {
    id = identifier()
    self.target = target
    token = identifier()
  }
}

/// Unsent input is presentation state. Only submission creates new evidence.
public struct WorkflowClarificationDraft: Codable, Equatable, Sendable {
  public var version = 1
  public var entry: WorkflowClarificationEntry
  public var alternatives: [WorkflowClarificationEntry] = []
  public init(target: Value) { entry = .init(target: target) }
  public static var nativeActor: ChangeActor { .human("SevraNativeWorkflowClarification") }
}

extension Workbook {
  public func newWorkflowClarificationDraft(_ runID: String) throws -> WorkflowClarificationDraft {
    .init(target: try workflowClarification(runID))
  }

  /// Historical targets stay readable after retry/cancel. Submission still
  /// compares the exact *current* paused output inside the business transaction.
  private func checkClarificationDraftTarget(_ target: Value) throws {
    let original = try item(target["originalRecordID"].text)
    let requestID = original.data["requestID"].text
    let request = try Value.parse(
      db.scalar(
        "SELECT result FROM operations WHERE id=? AND kind='workflow_interpretation_request'",
        [.string(requestID)]
      ).text)
    let published = try Value.parse(
      db.scalar(
        "SELECT result FROM operations WHERE id=? AND kind='workflow_step'",
        [.string("workflow-step:" + request["attemptID"].text)]
      ).text)
    guard published["id"] == target["runID"],
      let step = published["steps"].array.first(where: { $0["step_id"] == target["stepID"] }),
      step["output"]["value"]["recordID"] == .string(original.id),
      step["output"]["value"]["response"]["state"] == .string("needs_input"),
      try workflowClarificationTarget(runID: target["runID"].text, step: step) == target
    else {
      throw SevraError(
        "clarification_draft", "Keep the exact original missing-information request.")
    }
  }

  public func workflowClarificationDraftReceipt(_ entry: WorkflowClarificationEntry) throws
    -> Value?
  {
    try synchronized {
      guard
        let saved = try db.execute(
          "SELECT kind,request,result FROM operations WHERE id=?", [.string(entry.token)]
        ).first
      else { return nil }
      let arguments = try Value.parse(saved["request"]!.text)["arguments"]
      var expected: [String: Value] = [
        "target": entry.target, "values": entry.values, "reason": .string(entry.reason),
        "actor": try encoded(WorkflowClarificationDraft.nativeActor),
      ]
      if let preparation = entry.preparation { expected["preparation"] = preparation }
      try require(
        saved["kind"] == .string("workflow_clarification")
          && arguments == .object(expected),
        "clarification_draft_token",
        "This retry identity belongs to different supplied information.")
      return try clarificationDraftReceipt(Value.parse(saved["result"]!.text), entry: entry)
    }
  }

  private func clarificationDraftReceipt(_ run: Value, entry: WorkflowClarificationEntry) throws
    -> Value
  {
    guard run["id"] == entry.target["runID"],
      let step = run["steps"].array.first(where: { $0["step_id"] == entry.target["stepID"] }),
      step["output"]["value"]["clarification"]["target"] == entry.target
    else { throw SevraError("clarification_draft", "The saved operation lost its exact answer.") }
    let supplied = step["output"]["value"]["clarification"]
    return .object([
      "operationID": .string(entry.token), "runID": run["id"], "state": run["state"],
      "stepID": entry.target["stepID"], "sourceID": supplied["sourceID"],
      "recordID": supplied["recordID"],
    ])
  }

  private func validateClarificationDraft(_ draft: WorkflowClarificationDraft, runID: String) throws
  {
    let entries = [draft.entry] + draft.alternatives
    try require(
      draft.version == 1 && draft.alternatives.count <= 8
        && Set(entries.map(\.id)).count == entries.count
        && Set(entries.map(\.token)).count == entries.count,
      "clarification_draft_limit", "Keep at most eight distinct saved alternatives.")
    for entry in entries {
      try checkClarificationDraftTarget(entry.target)
      if let preparation = entry.preparation {
        try validateWorkflowAnswerPreparation(preparation, target: entry.target)
      }
      let fields = Set(entry.target["fields"].array.map { $0["id"].text })
      guard UUID(uuidString: entry.id) != nil, UUID(uuidString: entry.token) != nil,
        entry.target["runID"] == .string(runID), case .object(let values) = entry.values,
        Set(values.keys).isSubset(of: fields), try entry.values.json().utf8.count <= 65_536,
        entry.reason.utf8.count <= 4096
      else { throw SevraError("clarification_draft_limit", "Keep bounded declared input fields.") }
      if let receipt = entry.receipt {
        try require(
          try workflowClarificationDraftReceipt(entry) == receipt,
          "clarification_draft", "Keep the exact saved clarification receipt.")
      }
    }
  }

  private func clarificationDraftKey(_ runID: String) throws -> String {
    try require(UUID(uuidString: runID) != nil, "clarification_draft", "Use a local workflow run.")
    return "workflow-clarification-draft:" + runID
  }

  public func workflowClarificationDraft(_ runID: String) throws -> WorkflowClarificationDraft? {
    let control = Cancellation(deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction {
          let key = try clarificationDraftKey(runID)
          let size =
            try db.scalar(
              "SELECT length(CAST(value AS BLOB)) FROM meta WHERE key=?", [.string(key)]
            ).int ?? 0
          try require(size <= 1_000_000, "clarification_draft_limit", "Drafts exceed 1 MB.")
          guard let raw = try db.scalar("SELECT value FROM meta WHERE key=?", [.string(key)]).string
          else { return nil }
          let draft = try JSONDecoder().decode(
            WorkflowClarificationDraft.self, from: Data(raw.utf8))
          try validateClarificationDraft(draft, runID: runID)
          return draft
        }
      }
    }
  }

  @discardableResult public func saveWorkflowClarificationDraft(
    _ runID: String, draft: WorkflowClarificationDraft, expected: WorkflowClarificationDraft?,
    keepOther: Bool = false
  ) throws -> WorkflowClarificationDraft {
    try presentationMutation {
      try saveClarificationDraft(runID, draft: draft, expected: expected, keepOther: keepOther)
    }
  }

  func saveClarificationDraft(
    _ runID: String, draft: WorkflowClarificationDraft, expected: WorkflowClarificationDraft?,
    keepOther: Bool
  ) throws -> WorkflowClarificationDraft {
    let current = try workflowClarificationDraft(runID)
    try require(
      current == expected || current == draft || keepOther, "clarification_draft_conflict",
      "Another window changed these inputs. Keep both drafts before continuing.")
    var saved = draft
    if keepOther, let current, current != expected && current != draft {
      let candidates = [current.entry] + current.alternatives + saved.alternatives
      if saved.entry.receipt == nil {
        var replacement = WorkflowClarificationEntry(target: saved.entry.target)
        replacement.values = saved.entry.values
        replacement.reason = saved.entry.reason
        replacement.preparation = saved.entry.preparation
        saved.entry = replacement
      }
      saved.alternatives = []
      for var candidate in candidates {
        if candidate == saved.entry || saved.alternatives.contains(candidate) { continue }
        if candidate.receipt == nil {
          do {
            candidate.receipt = try workflowClarificationDraftReceipt(candidate)
          } catch let error as SevraError where error.code == "clarification_draft_token" {
            // Another window submitted different values under this former
            // draft identity. Preserve these unsent values with a fresh token.
            var replacement = WorkflowClarificationEntry(target: candidate.target)
            replacement.values = candidate.values
            replacement.reason = candidate.reason
            replacement.preparation = candidate.preparation
            candidate = replacement
          }
        }
        if candidate == saved.entry || saved.alternatives.contains(candidate) { continue }
        let entries = [saved.entry] + saved.alternatives
        if entries.contains(where: { $0.id == candidate.id || $0.token == candidate.token }) {
          try require(
            candidate.receipt == nil, "clarification_draft_conflict",
            "A saved receipt cannot share a retry identity with different inputs.")
          var replacement = WorkflowClarificationEntry(target: candidate.target)
          replacement.values = candidate.values
          replacement.reason = candidate.reason
          replacement.preparation = candidate.preparation
          candidate = replacement
        }
        saved.alternatives.append(candidate)
      }
    }
    try validateClarificationDraft(saved, runID: runID)
    let raw = try encoded(saved).json()
    try require(raw.utf8.count <= 1_000_000, "clarification_draft_limit", "Drafts exceed 1 MB.")
    let key = try clarificationDraftKey(runID)
    if current == nil {
      let count =
        try db.scalar(
          "SELECT count(*) FROM meta WHERE key LIKE 'workflow-clarification-draft:%'"
        ).int ?? 0
      try require(
        count < 128 || pruneSubmittedClarificationDrafts(limit: 1) == 1,
        "clarification_draft_limit",
        "This workbook already has 128 drafts with unsent answers. Preserve or finish those inputs before adding another."
      )
    }
    try db.execute(
      "INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
      [.string(key), .string(raw)])
    return saved
  }

  public func previewWorkflowClarificationDraft(_ draft: WorkflowClarificationDraft) throws -> Value
  {
    try synchronized {
      try validateClarificationDraft(draft, runID: draft.entry.target["runID"].text)
      try require(
        draft.entry.receipt == nil, "clarification_submitted", "This answer is already saved.")
      try require(
        try workflowClarification(draft.entry.target["runID"].text) == draft.entry.target,
        "stale_workflow_clarification", "The request changed. Your unsent inputs are retained.")
      let definition = try applicationDefinition(draft.entry.target["definitionID"].text)
      let interpretation = try DefinitionInterpretation(DefinitionDescriptor(definition.content))
      let values = try clarificationValues(
        draft.entry.values, interpretation: interpretation,
        evidenceIDs: draft.entry.target["evidenceIDs"].array)
      try require(
        !draft.entry.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        "workflow_clarification", "Explain the supplied information.")
      return .object([
        "target": draft.entry.target, "values": values, "reason": .string(draft.entry.reason),
        "notice": .string(
          "Save your supplied information. This completes only the paused interpretation; continuing and business review are separate."
        ),
      ])
    }
  }

  public func submitWorkflowClarificationDraft(
    _ draft: WorkflowClarificationDraft, preview: Value, cancellation: Cancellation = .init()
  ) throws -> Value {
    try cancellation.check()
    try synchronized {
      try validateClarificationDraft(draft, runID: draft.entry.target["runID"].text)
    }
    if let receipt = try workflowClarificationDraftReceipt(draft.entry) { return receipt }
    try require(
      try previewWorkflowClarificationDraft(draft) == preview, "stale_workflow_clarification",
      "The preview changed. Preview your retained inputs again.")
    let result = try clarifyWorkflow(
      authorizeWorkflowExecution(draft.entry.target["runID"].text), target: draft.entry.target,
      values: draft.entry.values, reason: draft.entry.reason, token: draft.entry.token,
      actor: WorkflowClarificationDraft.nativeActor, preparation: draft.entry.preparation,
      cancellation: cancellation)
    return try clarificationDraftReceipt(result, entry: draft.entry)
  }

  /// Called inside the presentation transaction. Only discard a cached entry
  /// when every answer has its exact durable business-operation receipt.
  func pruneSubmittedClarificationDrafts(limit: Int) throws -> Int {
    try require(
      (1...128).contains(limit), "clarification_draft_limit", "Use a bounded cache cleanup.")
    let rows = try db.execute(
      "SELECT key FROM meta WHERE key LIKE 'workflow-clarification-draft:%' ORDER BY key LIMIT 128")
    var removed = 0
    for row in rows {
      let key = row["key"]!.text
      guard
        let draft = try workflowClarificationDraft(
          String(key.dropFirst("workflow-clarification-draft:".count)))
      else { continue }
      var complete = true
      for entry in [draft.entry] + draft.alternatives {
        do {
          if try workflowClarificationDraftReceipt(entry) == nil {
            complete = false
            break
          }
        } catch let error as SevraError where error.code == "clarification_draft_token" {
          complete = false
          break
        }
      }
      if complete {
        try db.execute("DELETE FROM meta WHERE key=?", [.string(key)])
        removed += 1
        if removed == limit { break }
      }
    }
    return removed
  }

  func verifyWorkflowClarificationDrafts() throws {
    let rows = try db.execute(
      "SELECT key FROM meta WHERE key LIKE 'workflow-clarification-draft:%' ORDER BY key LIMIT 129")
    try require(rows.count <= 128, "clarification_draft_limit", "Too many clarification drafts.")
    for row in rows {
      _ = try workflowClarificationDraft(
        String(row["key"]!.text.dropFirst("workflow-clarification-draft:".count)))
    }
  }
}
