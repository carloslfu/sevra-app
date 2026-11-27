import CryptoKit
import Foundation

/// The check trigger: an automation that starts when its saved check starts finding rows.
///
/// The check is a saved SQL tool with no inputs that only reads. The automation follows the
/// check's latest version, which is validated again at every evaluation, and each change records
/// the exact version that ran. While the app is open on a Mac where the person enabled the
/// automation, the native owner runs it after workbook changes and on a modest poll. It fires
/// when the check finds a row it did not find last time, each row told apart by its first column,
/// and stays quiet while the same rows stay. A row that leaves and comes back is new again. Each
/// change of the rows found is saved as a Source with the automation's own state, so reopening
/// the workbook does not fire it again.
///
/// The saved state outlives pauses and app restarts. The first evaluation after a reopen or a
/// resume compares with it, so rows that appeared meanwhile fire once and rows that came and
/// went meanwhile fire nothing. The first check after enabling starts from no rows, so rows it
/// finds then fire. A check whose statements changed starts fresh the same way: the person
/// changed the rule, so rows it finds are news even if the old rule had found rows.
extension Workbook {
  public static let checkTransitionPolicy = "check-transition-v1"
  /// The rows of a check that are told apart: more than this many and the rest go unwatched.
  static let checkWatchedRows = 1_000

  /// What tells a check's row apart: a short digest of its first column.
  static func checkRowKey(_ row: Value) -> String {
    let first = (try? (row.array.first ?? .null).json()) ?? ""
    return SHA256.hash(data: Data(first.utf8)).prefix(8).map { String(format: "%02x", $0) }
      .joined()
  }

  /// How a row names itself in a check's alert: its first column, as the guide asks.
  static func checkRowName(_ row: Value) -> String {
    let first = row.array.first ?? .null
    return first.string ?? ((try? first.json()) ?? "")
  }

  /// The rows a check finds now, for a check about to be saved with an automation.
  func checkRows(_ tool: ApplicationDefinition, cancellation: Cancellation = .init()) throws -> Value {
    let statements = try DefinitionTool(DefinitionDescriptor(tool.content)).statements
    return try synchronized(cancellation: cancellation) { () throws -> Value in
      let session = try ChatSQLSession(self, readOnly: true, cancellation: cancellation)
      defer { session.close() }
      session.scratch.shownRows = Self.checkWatchedRows
      session.scratch.shownBytes = 16_000_000
      return try session.run(statements).last ?? .null
    }
  }

  /// A refusal when rows a check finds share a first column, so they would alert as one.
  func checkRepeats(_ tool: ApplicationDefinition) throws -> String? {
    let found = try checkRows(tool)
    var seen = Set<String>()
    guard
      let repeated = found["rows"].array.map(Self.checkRowName).first(where: {
        !seen.insert($0).inserted
      })
    else { return nil }
    let column = found["columns"].array.first.map(\.text)
    return "The check's first column" + (column.map { " " + $0 } ?? "") + " repeats \"" + repeated
      + "\" in the rows it finds now. Each row alerts once by its first column, so put a column that names one row first, such as its id or name. Nothing was saved."
  }

  /// Where a check automation's edge stands: whether its check last found rows, how many, and
  /// the Source of that change. Nil before its first change.
  public func automationCheckState(_ activationID: String) throws -> Value {
    try synchronized {
      guard
        let row = try db.execute(
          "SELECT * FROM automation_checks WHERE activation_id=?", [.string(activationID)]
        ).first
      else { return .null }
      var state = row
      state["newRowNames"] =
        (try? item(row["source_id"]?.text ?? "").data["newRowNames"]) ?? .array([])
      return .object(state)
    }
  }

  /// Runs the check once and saves a change of its edge. A change to rows queues one pending
  /// request, which `dispatchAutomationOccurrence` turns into the workflow run. Nothing is saved
  /// while the check's answer stays the same.
  public func checkAutomation(
    _ session: AutomationPlanningSession, observedAt: Date = Date(), token: String,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try workflowToken(token)
    let instant = try AutomationTime.text(observedAt)
    let snapshot = try synchronized(cancellation: cancellation) { () throws -> Value in
      try db.readTransaction {
        let activation = try automationSession(session)
        let saved = try applicationDefinition(activation["definition_id"].text)
        guard let check = try DefinitionAutomation(DefinitionDescriptor(saved.content)).check else {
          throw SevraError(
            "automation_trigger", "This automation runs on a schedule, not on a check.")
        }
        let tool = try resolveDefinition(check)
        let name: String
        do {
          name = try automationCheck(tool).name
        } catch let error as SevraError where error.code == "automation_check" {
          throw SevraError(
            "automation_check",
            error.message
              + " This automation waits until the check works again. Change the check back, or edit the automation and choose another check."
          )
        }
        try require(
          isToolEnabled(tool.id), "tool_disabled",
          "The check \(name) came with this workbook and is not enabled on this Mac. Enable it under Tools in the workbook's menu."
        )
        let state = try automationCheckState(session.activationID)
        // The exact check version the saved state came from, to tell an edited check.
        let ranID = try state["source_id"].string.map { try item($0).data["checkID"].text }
        let ran = try ranID.map {
          try DefinitionTool(DefinitionDescriptor(applicationDefinition($0).content))
        }
        let statements = try DefinitionTool(DefinitionDescriptor(tool.content)).statements
        return .object([
          "activation": activation, "checkID": .string(tool.id), "name": .string(name),
          "state": state, "changedCheck": .bool(ran.map { $0.statements != statements } ?? false),
        ])
      }
    }
    let tool = try applicationDefinition(snapshot["checkID"].text)
    let result = try checkRows(tool, cancellation: cancellation)
    let rows = result["rowCount"].int ?? 0
    let finding = rows > 0
    let keys = Set(result["rows"].array.map(Self.checkRowKey))
    let previous = snapshot["state"]
    let storedKeys = Set(
      try previous["source_id"].string.map { try item($0).data["rowKeys"].array.map(\.text) } ?? [])
    // A changed check starts fresh, as if just enabled. Its state is saved when it differs from
    // the stored one, so the page does not keep showing what the old check found.
    let changedCheck = snapshot["changedCheck"] == .bool(true)
    let known = changedCheck ? [] : storedKeys
    let fresh = keys.subtracting(known)
    let newRows = fresh.count
    // The new rows by name, for the check's record and the automation page.
    var named = Set<String>()
    let newNames = result["rows"].array.filter {
      fresh.contains(Self.checkRowKey($0)) && named.insert(Self.checkRowKey($0)).inserted
    }.prefix(10).map(Self.checkRowName)
    let listed = newNames.isEmpty ? "" : ": " + newNames.joined(separator: ", ")
      + (newRows > newNames.count ? " and \(newRows - newNames.count) more" : "")
    guard keys != known || (changedCheck && keys != storedKeys)
    else {
      return .object([
        "status": .string(finding ? "finding" : "clear"), "rows": .number(Double(rows)),
        "changed": .bool(false), "check": snapshot["name"], "execution": .string("none"),
      ])
    }
    let activation = snapshot["activation"]
    let authority = session
    let fence: () throws -> Void = { _ = try self.automationSession(session) }
    return try mutation(
      "automation_check", token: token,
      request: .object([
        "activationID": .string(authority.activationID),
        "generation": .number(Double(authority.generation)),
        "sourceID": .string(authority.sourceID), "observedAt": .string(instant),
        "rows": .number(Double(rows)),
      ]), cancellation: cancellation, actor: .programmatic("SevraCore.check-trigger"),
      commitGuard: fence
    ) {
      _ = try self.automationSession(session)
      try require(
        try self.automationCheckState(authority.activationID) == previous, "stale_automation",
        "Another check changed this automation's state. Check again.")
      let pending = try self.pendingAutomationOccurrence(authority.activationID)
      var decisions: [Value] = []
      var entries: [Value] = []
      let occurrenceID = identifier()
      let fires = newRows > 0
      if fires {
        if pending != .null { decisions.append(self.automationDecision(pending, "coalesced")) }
        let slot: Value = .object([
          "kind": .string("check"), "slotKey": .string("check:" + occurrenceID), "due": .string(instant),
          "rows": .number(Double(rows)),
        ])
        entries.append(
          .object([
            "id": .string(occurrenceID), "slot": slot, "state": .string("pending"),
            "detail": .string("awaiting_dispatch"),
          ]))
        decisions.append(
          .object([
            "id": .string(occurrenceID), "state": .string("pending"),
            "detail": .string("awaiting_dispatch"),
          ]))
      }
      let source = try self.insertItem(
        category: "source", kind: "automation_check",
        title: fires ? "Check found new rows" : finding ? "Check rows changed" : "Check found no rows",
        text: fires
          ? "The saved check \(snapshot["name"].text) found \(newRows) new "
            + (newRows == 1 ? "row" : "rows") + (changedCheck ? " after it was changed" : "")
            + listed + ". The automation queued one request."
          : finding
            ? "The saved check \(snapshot["name"].text) finds \(rows) "
              + (rows == 1 ? "row" : "rows") + ", none of them new."
            : "The saved check \(snapshot["name"].text) found no rows"
              + (changedCheck ? " after it was changed" : " again") + ". New rows will start the automation.",
        data: .object([
          "activationID": .string(authority.activationID),
          "definitionID": activation["definition_id"],
          "generation": .number(Double(authority.generation)),
          "authorizationSourceID": .string(authority.sourceID),
          "checkID": snapshot["checkID"], "rows": .number(Double(rows)),
          "finding": .bool(finding), "newRows": .number(Double(newRows)),
          "newRowNames": .array(newNames.map(Value.string)),
          "rowKeys": .array(keys.sorted().map(Value.string)), "previousCheckSourceID": previous["source_id"],
          "changedCheck": .bool(changedCheck),
          "observedAt": .string(instant), "occurrences": .array(entries),
          "decisions": .array(decisions), "policy": .string(Self.checkTransitionPolicy),
        ]), meaning: "actual", status: "accepted", scenario: "actual",
        inputs: [], transformation: "automation-check-transition-v1",
        controlInputs: Array(
          Set(
            [authority.sourceID, tool.sourceID] + (previous["source_id"].string.map { [$0] } ?? [])
              + (pending["source_id"].string.map { [$0] } ?? []))
        ).sorted())
      try self.applyAutomationDecisions(
        decisions.filter { $0["id"] != .string(occurrenceID) }, source: source)
      for entry in entries {
        let slot = entry["slot"]
        try self.db.execute(
          "INSERT INTO automation_occurrences VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
          [
            entry["id"], .string(authority.activationID), activation["definition_id"],
            .number(Double(authority.generation)), slot["slotKey"], slot["due"],
            .string(try slot.json()), entry["state"], entry["detail"], .string(source),
            .string(source), .string(timestamp()), .string(timestamp()),
          ])
      }
      try self.db.execute(
        "INSERT INTO automation_checks VALUES(?,?,?,?,?) ON CONFLICT(activation_id) DO UPDATE SET finding=excluded.finding,rows=excluded.rows,source_id=excluded.source_id,updated=excluded.updated",
        [
          .string(authority.activationID), .number(finding ? 1 : 0), .number(Double(rows)),
          .string(source), .string(timestamp()),
        ])
      try self.automationEvent(
        authority.activationID, generation: authority.generation, kind: "checked", source: source)
      return .object([
        "status": .string(fires ? "fired" : finding ? "finding" : "cleared"),
        "rows": .number(Double(rows)), "newRows": .number(Double(newRows)),
        "newRowNames": .array(newNames.map(Value.string)), "changed": .bool(true), "check": snapshot["name"], "sourceID": .string(source),
        "occurrenceID": fires ? .string(occurrenceID) : .null,
        "execution": .string("preparation-only"),
      ])
    }
  }

  /// Integrity of the check trigger: each saved change agrees with its Source, its occurrence
  /// and the automation's authorization.
  func verifyAutomationChecks() throws {
    var after = ""
    while true {
      let rows = try db.execute(
        "SELECT * FROM automation_checks WHERE activation_id>? ORDER BY activation_id LIMIT 100",
        [.string(after)])
      if rows.isEmpty { break }
      for row in rows {
        let state = Value.object(row)
        let source = try item(state["source_id"].text)
        try require(
          source.category == "source" && source.kind == "automation_check"
            && source.status == "accepted" && source.meaning == "actual"
            && source.data["activationID"] == state["activation_id"]
            && source.data["finding"] == .bool(state["finding"].int == 1)
            && source.data["rows"].int == state["rows"].int
            && source.data["policy"] == .string(Self.checkTransitionPolicy),
          "automation_integrity", "A check's saved state disagrees with its Source.")
        after = state["activation_id"].text
      }
    }
  }

  /// One occurrence a check change queued: its slot is the change itself.
  func verifyCheckOccurrence(_ occurrence: Value, slot: Value, source: Item) throws {
    let automation = try DefinitionAutomation(
      DefinitionDescriptor(applicationDefinition(occurrence["definition_id"].text).content))
    try require(
      automation.check?.target
        == (try? applicationDefinition(source.data["checkID"].text).logicalID)
        && source.data["policy"] == .string(Self.checkTransitionPolicy)
        && source.data["finding"] == .bool(true)
        && slot == .object([
          "kind": .string("check"), "slotKey": .string("check:" + occurrence["id"].text),
          "due": source.data["observedAt"], "rows": source.data["rows"],
        ]) && (source.data["rows"].int ?? 0) > 0,
      "automation_integrity", "An occurrence does not match the check change that queued it.")
  }
}

extension Workbook {
  public static let checkAlertActionID = "5e7a1e47-a1e7-8000-8000-000000000003"
  public static let checkAlertWorkflowID = "5e7a1e47-a1e7-8000-8000-000000000004"

  /// The business evidence an alert from `check` cites: the Source of the first table the
  /// check reads, since an alert document needs one and the check watches exactly that table.
  func checkAlertEvidence(_ check: ApplicationDefinition) throws -> Item {
    let tool = try automationCheck(check)
    let rehearsal = try SQLScratch(
      tables: datasets(), readOnly: true, draft: false, inputs: [:], cancellation: .init())
    defer { rehearsal.close() }
    _ = try rehearsal.rehearse(tool.statements)
    for key in rehearsal.readTables {
      let table = rehearsal.table(key)
      if let source = try datasetSource(table.id) {
        let evidence = try item(source)
        if evidence.isBusinessEvidence { return evidence }
      }
      // A table made in chat comes from the request, which is not business evidence. Its rows are.
      if let row = try db.scalar(
        "SELECT logical_id FROM dataset_rows WHERE dataset_id=? ORDER BY ordinal LIMIT 1",
        [.string(table.id)]
      ).string {
        let evidence = try item(row)
        if evidence.isBusinessEvidence { return evidence }
      }
    }
    throw SevraError(
      "automation_check",
      "The check \(tool.name) reads no table with rows or a Source an alert can cite. Add a row to the table it reads, or choose a workflow for it to run instead."
    )
  }
}
