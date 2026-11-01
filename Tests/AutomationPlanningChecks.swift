import Foundation

@testable import SevraCore

func automationPlanningFixture(at url: URL, schedule: Value? = nil) throws -> (
  Workbook, ApplicationDefinition
) {
  let book = try Workbook.create(at: url, title: "Synthetic calendar preparation")
  let function = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("function"), "title": .string("Synthetic daily total"),
      "description": .string("Deterministic fixture"), "parameters": .array([]),
      "payload": .object(["expression": .string("1+2"), "unit": .string("items")]),
    ]))
  let workflow = try book.saveApplicationDefinition(
    logicalID: identifier(), content: book.workflowTemplate(function.id))
  let automation = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("automation"), "title": .string("Daily draft report"),
      "description": .string("Prepare only; never execute"), "parameters": .array([]),
      "payload": .object([
        "policy": .string("calendar-drafts-v1"),
        "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow.id)]),
        "arguments": .object([:]),
        "schedule": schedule
          ?? .object([
            "policy": .string("native-calendar-v1"), "timeZone": .string("UTC"),
            "hour": .number(9), "minute": .number(0),
            "recurrence": .object(["kind": .string("daily")]),
          ]),
      ]),
    ]))
  return (book, automation)
}

func automationDate(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

func createAutomationPlanningFixture(at url: URL) throws -> Value {
  let (book, definition) = try automationPlanningFixture(at: url)
  let session = try book.authorizeAutomationPlanning(
    definition.id, expectedGeneration: 0, after: automationDate("2026-10-01T08:00:00Z"),
    token: "authorize")
  _ = try book.planAutomationOccurrences(
    session, through: automationDate("2026-10-04T09:00:00Z"), token: "prepare")
  _ = try book.verify()
  return .object([
    "workbook": .string(url.path), "activationID": .string(session.activationID),
    "generation": .number(Double(session.generation)), "definitionID": .string(definition.id),
  ])
}

func checkAutomationPlanning(at root: URL) {
  func fixture(_ name: String, schedule: Value? = nil) throws -> (Workbook, ApplicationDefinition) {
    try automationPlanningFixture(
      at: root.appendingPathComponent("Planning-" + name + ".sevra"), schedule: schedule)
  }
  let start = automationDate("2026-10-01T08:00:00Z")
  func authorize(_ book: Workbook, _ definition: ApplicationDefinition, token: String = "authorize")
    throws -> AutomationPlanningSession
  {
    try book.authorizeAutomationPlanning(
      definition.id, expectedGeneration: 0, after: start, token: token,
      actor: .human("synthetic-test"))
  }
  func slots(_ book: Workbook, _ session: AutomationPlanningSession) throws -> [Value] {
    let result = try book.automationOccurrences(session.activationID, limit: 50)
    return result["occurrences"].array
  }
  check(
    "calendar planning requires explicit exact-generation authority and retains honest Source attribution"
  ) {
    let (book, definition) = try fixture("Authority")
    let revision = try book.revision()
    try refuses("automation_binding") {
      _ = try book.authorizeAutomationPlanning(
        definition.logicalID, expectedGeneration: 0, after: start, token: "logical")
    }
    try refuses("stale_automation") {
      _ = try book.authorizeAutomationPlanning(
        definition.id, expectedGeneration: 1, after: start, token: "stale")
    }
    try expect(try book.revision() == revision)
    let session = try authorize(book, definition)
    let activation = try book.automationActivation(session.activationID)
    try expect(
      activation["state"].text == "armed" && activation["execution"].text == "preparation-only")
    try expect(
      activation["actor"]["kind"].text == "human" && activation["sessionRequired"] == .bool(true))
    let source = try book.item(activation["source_id"].text)
    try expect(
      source.data["actor"] == activation["actor"]
        && source.data["definitionID"].text == definition.id)
    try expect(try book.lineage(source.id).contains { $0["parent"].text == definition.sourceID })
    try expect(try book.workflowRuns().isEmpty)
    _ = try book.verify()
  }
  check("calendar preparation includes a due instant once and keeps workflow execution inert") {
    let (book, definition) = try fixture("Due")
    let session = try authorize(book, definition)
    let before = try book.planAutomationOccurrences(
      session, through: automationDate("2026-10-01T08:59:59Z"), token: "before")
    try expect(before["preparedCount"].int == 0)
    let atDue = try book.planAutomationOccurrences(
      session, through: automationDate("2026-10-01T09:00:00Z"), token: "due")
    try expect(atDue["preparedCount"].int == 1 && atDue["pending"]["state"].text == "pending")
    let again = try book.planAutomationOccurrences(
      session, through: automationDate("2026-10-01T09:00:00Z"), token: "again")
    try expect(again["preparedCount"].int == 0 && again["pending"]["id"] == atDue["pending"]["id"])
    try expect(try slots(book, session).count == 1 && book.workflowRuns().isEmpty)
    let source = try book.item(atDue["sourceID"].text)
    try expect(source.data["actor"]["kind"].text == "programmatic")
    _ = try book.verify()
  }
  check(
    "calendar backlog is bounded, coalesced and explicit about lateness and incomplete catch-up"
  ) {
    let (book, definition) = try fixture("Backlog")
    let session = try authorize(book, definition)
    let through = automationDate("2026-10-04T09:00:00Z")
    let first = try book.planAutomationOccurrences(
      session, through: through, token: "first", limit: 2)
    try expect(
      first["preparedCount"].int == 2 && first["catchUpRemaining"] == .bool(true)
        && first["pending"] == .null)
    let second = try book.planAutomationOccurrences(
      session, through: through, token: "second", limit: 2)
    try expect(second["preparedCount"].int == 2 && second["catchUpRemaining"] == .bool(false))
    let rows = try slots(book, session)
    try expect(
      rows.map { $0["detail"].text } == ["late", "late", "coalesced", "awaiting_dispatch"])
    try expect(rows.filter { $0["state"].text == "pending" }.count == 1)
    _ = try book.verify()
  }
  check("calendar coverage never consumes the next unscanned midnight slot") {
    let (book, definition) = try fixture(
      "Horizon",
      schedule: .object([
        "policy": .string("native-calendar-v1"), "timeZone": .string("UTC"), "hour": .number(0),
        "minute": .number(0), "recurrence": .object(["kind": .string("daily")]),
      ]))
    let session = try authorize(book, definition)
    let first = try book.planAutomationOccurrences(
      session, through: automationDate("2026-10-05T00:00:00Z"), token: "first", horizonDays: 2)
    try expect(
      first["cursor"].text == "2026-10-02T23:59:59.999Z" && first["catchUpRemaining"] == .bool(true)
    )
    let next = try book.planAutomationOccurrences(
      session, through: automationDate("2026-10-05T00:00:00Z"), token: "next")
    try expect(next["preparedCount"].int == 3)
    try expect(
      try slots(book, session).map { $0["slot_key"].text } == [
        "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05",
      ])
    _ = try book.verify()
  }
  check("a daylight-saving gap or fold keeps its date's slot and a run at that instant verifies") {
    for (name, zone, hour, minute, due, key) in [
      ("Spring", "America/New_York", 2, 30, "2026-03-08T07:00:00Z", "2026-03-08"),
      ("DayEnd", "America/Nuuk", 23, 30, "2026-03-29T01:00:00Z", "2026-03-28"),
      ("Fall", "America/New_York", 1, 30, "2026-11-01T05:30:00Z", "2026-11-01"),
    ] {
      let (book, definition) = try fixture(
        name,
        schedule: .object([
          "policy": .string("native-calendar-v1"), "timeZone": .string(zone),
          "hour": .number(Double(hour)), "minute": .number(Double(minute)),
          "recurrence": .object(["kind": .string("daily")]),
        ]))
      let instant = automationDate(due)
      let session = try book.authorizeAutomationExecution(
        definition.id, expectedGeneration: 0, after: instant.addingTimeInterval(-60),
        token: "authorize")
      // One scanned day ends exactly at the day-end slot, and the cursor must still pass it.
      let planned = try book.planAutomationOccurrences(
        session.planning, through: instant, token: "plan", horizonDays: 1)
      try expect(planned["pending"]["slot_key"].text == key, try planned.json())
      try expect(try AutomationTime.date(planned["cursor"].text) >= instant, try planned.json())
      let again = try book.planAutomationOccurrences(
        session.planning, through: instant.addingTimeInterval(1), token: "again")
      try expect(again["preparedCount"].int == 0, try again.json())
      let dispatched = try book.dispatchAutomationOccurrence(
        session, observedAt: instant, token: "dispatch")
      let run = try book.authorizeAutomationWorkflowExecution(
        session, runID: dispatched["runID"].text)
      try expect(try book.continueWorkflow(run, owner: "test")["state"].text == "completed")
      try expect(try book.verify()["ok"] == .bool(true))
    }
  }
  check("verification keeps a retained slot's instant and checks its date against the rule") {
    let rule = try NativeCalendarSchedule(
      .object([
        "policy": .string("native-calendar-v1"), "timeZone": .string("America/Bogota"),
        "hour": .number(9), "minute": .number(0),
        "recurrence": .object(["kind": .string("weekly"), "weekdays": .array([.number(1)])]),
      ]))
    let saved = try rule.preview(after: automationDate("2026-10-01T00:00:00Z"), count: 1)[
      "occurrences"
    ].array[0]
    try expect(saved["localDate"].text == "2026-10-05" && rule.selects(saved))
    // A later zone rule change moves what preview computes, never what was already planned.
    func edited(_ field: String, _ value: Value) -> Value {
      var slot = saved.object
      slot[field] = value
      return .object(slot)
    }
    try expect(rule.selects(edited("due", .string("2026-10-05T15:00:00.000Z"))))
    for (field, value) in [
      ("requestedLocalTime", Value.string("10:00:00")), ("timeZone", .string("UTC")),
      ("slotKey", .string("2026-10-12")), ("localDate", .string("2026-10-06")),
      ("localDate", .string("2026-02-30")), ("localDate", .null),
    ] {
      try expect(!rule.selects(edited(field, value)), field)
    }
  }
  check(
    "pause cancels pending preparation, revokes sessions and cannot be undone by an old receipt"
  ) {
    let (book, definition) = try fixture("Pause")
    let session = try authorize(book, definition)
    _ = try book.planAutomationOccurrences(
      session, through: automationDate("2026-10-01T09:00:00Z"), token: "due")
    let paused = try book.pauseAutomation(
      session.activationID, expectedGeneration: 1, token: "pause", actor: .human("synthetic-test"))
    try expect(paused["generation"].int == 2 && paused["state"].text == "paused")
    let revision = try book.revision()
    try expect(
      try book.pauseAutomation(
        session.activationID, expectedGeneration: 1, token: "pause", actor: .human("synthetic-test")
      ) == paused)
    try refuses("automation_authority") {
      _ = try book.planAutomationOccurrences(
        session, through: automationDate("2026-10-01T09:00:00Z"), token: "due")
    }
    try refuses("stale_automation") { _ = try authorize(book, definition) }
    try expect(
      try book.revision() == revision && slots(book, session)[0]["detail"].text == "paused")
    _ = try book.verify()
  }
  check(
    "authorization retries do not rotate authority and different arguments cannot reuse the token"
  ) {
    let (book, definition) = try fixture("Retry")
    let first = try authorize(book, definition)
    let revision = try book.revision()
    let retry = try authorize(book, definition)
    try expect(first.generation == retry.generation && first.activationID == retry.activationID)
    try refuses("idempotency") {
      _ = try book.authorizeAutomationPlanning(
        definition.id, expectedGeneration: 0, after: start.addingTimeInterval(1),
        token: "authorize", actor: .human("synthetic-test"))
    }
    try expect(try book.revision() == revision)
    let planned = try book.planAutomationOccurrences(
      first, through: automationDate("2026-10-01T09:00:00Z"), token: "due")
    let plannedRevision = try book.revision()
    try expect(
      try book.planAutomationOccurrences(
        retry, through: automationDate("2026-10-01T09:00:00Z"), token: "due") == planned)
    try expect(try book.revision() == plannedRevision)
    _ = try book.verify()
  }
  check(
    "reopening a workbook issues no authority and explicit reauthorization revokes the other connection"
  ) {
    let (book, definition) = try fixture("Reopen")
    let session = try authorize(book, definition)
    let reopened = try Workbook(book.url)
    try refuses("automation_authority") {
      _ = try reopened.planAutomationOccurrences(session, through: start, token: "borrowed")
    }
    let newSession = try reopened.authorizeAutomationPlanning(
      definition.id, expectedGeneration: 1, after: start, token: "new-process")
    try refuses("automation_authority") {
      _ = try book.planAutomationOccurrences(session, through: start, token: "revoked")
    }
    _ = try reopened.planAutomationOccurrences(
      newSession, through: automationDate("2026-10-01T09:00:00Z"), token: "due")
    try expect(try slots(reopened, newSession).count == 1)
    _ = try reopened.verify()
  }
  check("clock rollback and resume preserve high-water coverage without replaying a slot") {
    let (book, definition) = try fixture("Clock")
    let session = try authorize(book, definition)
    let future = automationDate("2026-10-04T09:00:00Z")
    let plan = try book.planAutomationOccurrences(session, through: future, token: "future")
    let rolled = try book.planAutomationOccurrences(session, through: start, token: "rollback")
    try expect(rolled["preparedCount"].int == 0 && rolled["cursor"] == plan["cursor"])
    _ = try book.pauseAutomation(session.activationID, expectedGeneration: 1, token: "pause")
    let resumed = try book.authorizeAutomationPlanning(
      definition.id, expectedGeneration: 2, after: start, token: "resume")
    try refuses("stale_automation") {
      _ = try book.pauseAutomation(session.activationID, expectedGeneration: 1, token: "pause")
    }
    let again = try book.planAutomationOccurrences(resumed, through: future, token: "again")
    try expect(again["preparedCount"].int == 0 && again["pending"] == .null)
    try expect(try slots(book, resumed).count == 4)
    _ = try book.verify()
  }
  check("planning honors first-only repeated times and never creates the second folded slot") {
    let (book, definition) = try fixture(
      "Fold",
      schedule: .object([
        "policy": .string("native-calendar-v1"), "timeZone": .string("America/New_York"),
        "hour": .number(1), "minute": .number(30),
        "recurrence": .object(["kind": .string("daily")]),
      ]))
    let session = try book.authorizeAutomationPlanning(
      definition.id, expectedGeneration: 0, after: automationDate("2026-11-01T00:00:00Z"),
      token: "authorize")
    _ = try book.planAutomationOccurrences(
      session, through: automationDate("2026-11-01T07:00:00Z"), token: "fold")
    let rows = try slots(book, session)
    try expect(rows.count == 1 && rows[0]["due"].text == "2026-11-01T05:30:00.000Z")
    _ = try book.verify()
  }
  check(
    "a new definition head does not retarget an authorization and an explicit edit starts without backfill"
  ) {
    let (book, definition) = try fixture("Edit")
    let session = try authorize(book, definition)
    var content = definition.content.object
    content["title"] = .string("Changed exact schedule intention")
    let newer = try book.saveApplicationDefinition(
      logicalID: definition.logicalID, content: .object(content),
      expectedDefinitionID: definition.id)
    try expect(
      try book.automationActivation(session.activationID)["definition_id"].text == definition.id)
    let next = try book.authorizeAutomationPlanning(
      newer.id, expectedGeneration: 1, after: automationDate("2026-10-05T10:00:00Z"), token: "edit")
    let result = try book.planAutomationOccurrences(
      next, through: automationDate("2026-10-06T09:00:00Z"), token: "next")
    try expect(
      result["preparedCount"].int == 1 && result["pending"]["slot_key"].text == "2026-10-06")
    _ = try book.verify()
  }
  check(
    "publication faults and cancellation roll back authorization, cursor, queue and outbox together"
  ) {
    let (book, definition) = try fixture("Rollback")
    let revision = try book.revision()
    try book.db.execute(
      "CREATE TEMP TRIGGER fail_planning BEFORE INSERT ON main.committed_changes BEGIN SELECT RAISE(ABORT,'injected planning fault'); END;"
    )
    try refuses { _ = try authorize(book, definition) }
    try expect(try book.revision() == revision && book.automationEvents()["events"].array.isEmpty)
    try book.db.execute("DROP TRIGGER fail_planning")
    let session = try authorize(book, definition)
    let activation = try book.automationActivation(session.activationID)
    let events = try book.automationEvents()
    try book.db.execute(
      "CREATE TEMP TRIGGER fail_planning BEFORE INSERT ON main.committed_changes BEGIN SELECT RAISE(ABORT,'injected planning fault'); END;"
    )
    try refuses {
      _ = try book.planAutomationOccurrences(
        session, through: automationDate("2026-10-04T09:00:00Z"), token: "failure")
    }
    try book.db.execute("DROP TRIGGER fail_planning")
    try expect(
      try book.automationActivation(session.activationID) == activation
        && book.automationEvents() == events && slots(book, session).isEmpty)
    let cancellation = Cancellation()
    cancellation.cancel()
    try refuses("cancelled") {
      _ = try book.planAutomationOccurrences(
        session, through: start, token: "cancelled", cancellation: cancellation)
    }
    _ = try book.verify()
  }
  check("occurrence and outbox pagination are bounded and read-only") {
    let (book, definition) = try fixture("Pagination")
    let session = try authorize(book, definition)
    _ = try book.planAutomationOccurrences(
      session, through: automationDate("2026-10-04T09:00:00Z"), token: "due")
    let revision = try book.revision()
    let activations = try book.automationActivations(limit: 1)
    try expect(
      activations["activations"].array.count == 1 && activations["hasMore"] == .bool(false))
    try expect(
      try book.automationActivations(after: session.activationID)["activations"].array.isEmpty)
    try refuses("automation_limit") { _ = try book.automationActivations(limit: 51) }
    let first = try book.automationOccurrences(session.activationID, limit: 2)
    let second = try book.automationOccurrences(
      session.activationID, after: first["nextCursor"].text, limit: 2)
    try expect(first["hasMore"] == .bool(true) && second["hasMore"] == .bool(false))
    try expect(first["occurrences"].array.count == 2 && second["occurrences"].array.count == 2)
    let events = try book.automationEvents(limit: 1)
    try expect(
      events["hasMore"] == .bool(true)
        && book.automationEvents(after: events["after"].int!, limit: 1)["hasMore"] == .bool(false))
    try refuses("automation_limit") {
      _ = try book.automationOccurrences(session.activationID, limit: 51)
    }
    try refuses("automation_cursor") {
      _ = try book.automationOccurrences(session.activationID, after: "missing")
    }
    try expect(try book.revision() == revision)
    _ = try book.verify()
  }
  check(
    "inert reconstruction preserves every activation and occurrence family but cannot borrow a live session"
  ) {
    let (book, definition) = try fixture("Reconstruct")
    let session = try authorize(book, definition)
    _ = try book.planAutomationOccurrences(
      session, through: automationDate("2026-10-04T09:00:00Z"), token: "due")
    let copy = try book.reconstruct(to: root.appendingPathComponent("Planning-inert.sevra"))
    try expect(
      try copy.automationActivation(session.activationID)
        == book.automationActivation(session.activationID))
    try expect(
      try copy.automationOccurrences(session.activationID)
        == book.automationOccurrences(session.activationID))
    try expect(try copy.automationEvents() == book.automationEvents())
    try refuses("automation_authority") {
      _ = try copy.planAutomationOccurrences(session, through: start, token: "copy")
    }
    try expect(try copy.workflowRuns().isEmpty && copy.workflowEvents()["events"].array.isEmpty)
    _ = try copy.verify()
  }
  check("simultaneous planning cannot duplicate a slot or leave two pending requests") {
    let (book, definition) = try fixture("Concurrent")
    let session = try authorize(book, definition)
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "synthetic-calendar-planners", attributes: .concurrent)
    let resultLock = NSLock()
    var results: [Result<Value, Error>] = []
    for index in 0..<2 {
      group.enter()
      queue.async {
        let result = Result {
          try book.planAutomationOccurrences(
            session, through: automationDate("2026-10-04T09:00:00Z"),
            token: "worker-" + String(index))
        }
        resultLock.lock()
        results.append(result)
        resultLock.unlock()
        group.leave()
      }
    }
    try expect(group.wait(timeout: .now() + 30) == .success)
    var succeeded = 0
    for result in results {
      switch result {
      case .success: succeeded += 1
      case .failure(let error): try expect((error as? SevraError)?.code == "stale_automation")
      }
    }
    try expect(succeeded >= 1 && results.count == 2)
    let rows = try slots(book, session)
    try expect(rows.count == 4 && rows.filter { $0["state"] == .string("pending") }.count == 1)
    _ = try book.verify()
  }
  check("clock rollback cannot clear an unfinished bounded catch-up target") {
    let (book, definition) = try fixture("BacklogClock")
    let session = try authorize(book, definition)
    let through = automationDate("2026-10-05T09:00:00Z")
    _ = try book.planAutomationOccurrences(session, through: through, token: "page-one", limit: 1)
    let earlier = try book.planAutomationOccurrences(
      session, through: start, token: "clock-rollback", limit: 1)
    try expect(
      earlier["catchUpRemaining"] == .bool(true)
        && earlier["through"].text == "2026-10-05T09:00:00.000Z")
    try expect(earlier["cursor"].text == "2026-10-02T09:00:00.000Z" && earlier["pending"] == .null)
    let activation = try book.automationActivation(session.activationID)
    try expect(
      activation["catch_up_remaining"].int == 1
        && activation["observed_through"] == earlier["through"])
    let finished = try book.planAutomationOccurrences(session, through: start, token: "finish")
    try expect(finished["catchUpRemaining"] == .bool(false) && finished["preparedCount"].int == 3)
    try expect(try slots(book, session).count == 5)
    _ = try book.verify()
  }
  check("changing coverage to a plausible different target still fails exact Source integrity") {
    let (book, definition) = try fixture("CoverageEvidence")
    let session = try authorize(book, definition)
    _ = try book.planAutomationOccurrences(
      session, through: automationDate("2026-10-04T09:00:00Z"), token: "first", limit: 1)
    _ = try book.db.transaction {
      try book.db.execute(
        "UPDATE automation_activations SET observed_through='2026-10-03T09:00:00.000Z' WHERE id=?",
        [.string(session.activationID)])
    }
    try refuses("automation_integrity") { _ = try book.verify() }
  }
  check("automation integrity rejects altered decisions or lost original Source lineage") {
    let (book, definition) = try fixture("Integrity")
    let session = try authorize(book, definition)
    let first = try book.planAutomationOccurrences(
      session, through: automationDate("2026-10-01T09:00:00Z"), token: "due")
    _ = try book.planAutomationOccurrences(
      session, through: automationDate("2026-10-02T09:00:00Z"), token: "later")
    _ = try book.db.transaction {
      try book.db.execute(
        "UPDATE automation_occurrences SET detail='late' WHERE id=?", [first["pending"]["id"]])
    }
    try refuses("automation_integrity") { _ = try book.verify() }
    let (other, target) = try fixture("Lineage")
    let authority = try authorize(other, target)
    let plan = try other.planAutomationOccurrences(
      authority, through: automationDate("2026-10-01T09:00:00Z"), token: "due")
    _ = try other.db.transaction {
      try other.db.execute(
        "DELETE FROM lineage WHERE child=? AND parent=?",
        [plan["sourceID"], .string(authority.sourceID)])
    }
    try refuses("automation_integrity") { _ = try other.verify() }
  }
}
