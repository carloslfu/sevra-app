import Foundation

@testable import SevraCore

/// The check trigger: an automation that starts when a saved read-only SQL tool starts finding
/// rows, on the edge, with its state saved so a reopen does not fire it again.
func checkCheckAutomations(at root: URL) {
  let start = automationDate("2026-10-01T08:00:00Z")
  func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }
  struct Fixture {
    let book: Workbook
    let parts: Dataset
    let definition: ApplicationDefinition
    let check: Workbook.SavedTool
  }
  func fixture(_ name: String) throws -> Fixture {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Check-" + name + ".sevra"), title: name)
    let source = try book.addItem(
      category: "source", kind: "observation", title: "Stock count", status: "accepted")
    let parts = try book.createDataset(
      title: "Parts",
      columns: [
        .init(id: "name", title: "Name"), .init(id: "qty", title: "Qty", type: "decimal"),
        .init(id: "reorder", title: "Reorder", type: "decimal"),
      ],
      rows: [["name": .string("bolts"), "qty": .string("20"), "reorder": .string("10")]],
      sourceID: source.id)
    _ = try book.chatSaveTool(
      name: "low_stock", description: "Parts below their reorder level.", inputs: [],
      statements: ["SELECT name FROM parts WHERE qty < reorder"], source: nil,
      token: "save-low-stock", requestSourceID: nil)
    let check = try book.savedTools().first { $0.name == "low_stock" }!
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(), content: book.workflowTemplate(noteAction(book).id))
    let definition = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: checkAutomationContent(
        check: check.logicalID, workflow: workflow.id,
        arguments: noteArguments(source.id, title: "Reorder parts")))
    return Fixture(book: book, parts: parts, definition: definition, check: check)
  }
  func setQuantity(_ f: Fixture, _ qty: String) throws {
    _ = try f.book.chatSQL(
      statements: ["UPDATE parts SET qty = \(qty) WHERE name = 'bolts'"], readOnly: false,
      token: identifier(), requestSourceID: nil)
  }
  func occurrences(_ f: Fixture, _ session: AutomationExecutionSession) throws -> [Value] {
    let page = try f.book.automationOccurrences(session.planning.activationID, limit: 50)
    return page["occurrences"].array
  }

  check("a check fires once when it starts finding rows, and stays quiet while rows persist") {
    let f = try fixture("Edge")
    let session = try f.book.authorizeExecution(f.definition, generation: 0, after: start)
    let clear = try f.book.checkAutomation(session.planning, observedAt: at(1), token: "c1")
    try expect(clear["status"] == .string("clear") && clear["changed"] == .bool(false))
    try expect(try occurrences(f, session).isEmpty)
    try setQuantity(f, "5")
    let fired = try f.book.checkAutomation(session.planning, observedAt: at(2), token: "c2")
    try expect(fired["status"] == .string("fired") && fired["rows"].int == 1)
    let dispatched = try f.book.dispatchAutomationOccurrence(
      session, observedAt: at(2), token: "d2")
    try expect(dispatched["status"] == .string("queued") && dispatched["runID"].string != nil)
    let revision = try f.book.revision()
    let quiet = try f.book.checkAutomation(session.planning, observedAt: at(3), token: "c3")
    try expect(quiet["status"] == .string("finding") && quiet["changed"] == .bool(false))
    try expect(try f.book.revision() == revision && occurrences(f, session).count == 1)
    // The run it queued drafts for review, like a scheduled one.
    let worker = try f.book.authorizeAutomationWorkflowExecution(
      session, runID: dispatched["runID"].text)
    let run = try f.book.advanceWorkflow(worker, owner: "test")
    try expect(run["state"] == .string("queued") || run["state"] == .string("waiting_review"))
    _ = try f.book.verify()
  }

  check("a reopen does not fire again, and no rows then rows fires once more") {
    let f = try fixture("Reopen")
    let session = try f.book.authorizeExecution(f.definition, generation: 0, after: start)
    try setQuantity(f, "5")
    _ = try f.book.checkAutomation(session.planning, observedAt: at(1), token: "c1")
    _ = try f.book.dispatchAutomationOccurrence(session, observedAt: at(1), token: "d1")
    let reopened = try Workbook(f.book.url)
    let again = try reopened.authorizeExecution(f.definition, generation: 1, after: at(2))
    let stays = try reopened.checkAutomation(again.planning, observedAt: at(3), token: "c2")
    try expect(stays["status"] == .string("finding") && stays["changed"] == .bool(false))
    try expect(
      try reopened.automationOccurrences(again.planning.activationID)["occurrences"].array.count
        == 1)
    let g = Fixture(book: reopened, parts: f.parts, definition: f.definition, check: f.check)
    try setQuantity(g, "50")
    let cleared = try reopened.checkAutomation(again.planning, observedAt: at(4), token: "c3")
    try expect(cleared["status"] == .string("cleared"))
    try expect(try reopened.automationCheckState(again.planning.activationID)["finding"].int == 0)
    try setQuantity(g, "1")
    let fired = try reopened.checkAutomation(again.planning, observedAt: at(5), token: "c4")
    try expect(fired["status"] == .string("fired"))
    let all = try reopened.automationOccurrences(again.planning.activationID)["occurrences"].array
    try expect(all.count == 2 && all.filter { $0["state"] == .string("pending") }.count == 1)
    _ = try reopened.verify()
  }

  check("a check that writes, takes inputs or is a script is refused") {
    let f = try fixture("Refused")
    let workflow = try f.book.applicationDefinition(
      f.definition.payload["workflow"]["versionID"].text)
    func refusedCheck(_ name: String, inputs: [(name: String, type: String)] = [],
      statements: [String] = [], source: String? = nil) throws
    {
      _ = try f.book.chatSaveTool(
        name: name, description: "", inputs: inputs, statements: statements, source: source,
        token: "save-" + name, requestSourceID: nil)
      let tool = try f.book.savedTools().first { $0.name == name }!
      try refuses("automation_check") {
        _ = try f.book.saveApplicationDefinition(
          logicalID: identifier(),
          content: checkAutomationContent(
            check: tool.logicalID, workflow: workflow.id,
            arguments: f.definition.payload["arguments"]))
      }
    }
    try refusedCheck("bump", statements: ["UPDATE parts SET qty = qty + 1"])
    try refusedCheck(
      "below", inputs: [("level", "decimal")],
      statements: ["SELECT name FROM parts WHERE qty < :level"])
    try expect(try f.book.verify()["ok"] == .bool(true))
  }

  check("a paused or never enabled check automation does not fire") {
    let f = try fixture("Paused")
    let session = try f.book.authorizeExecution(f.definition, generation: 0, after: start)
    _ = try f.book.pauseAutomation(
      session.planning.activationID, expectedGeneration: 1, token: "pause")
    try setQuantity(f, "5")
    try refuses("automation_authority") {
      _ = try f.book.checkAutomation(session.planning, observedAt: at(1), token: "c1")
    }
    try expect(try f.book.automationCheckState(session.planning.activationID) == .null)
    try expect(try occurrences(f, session).isEmpty && f.book.workflowRuns().isEmpty)
    // A check that is not enabled on this Mac does not run either.
    let resumed = try f.book.authorizeExecution(f.definition, generation: 2, after: at(2))
    try f.book.disableTool(f.check.definitionID)
    try refuses("tool_disabled") {
      _ = try f.book.checkAutomation(resumed.planning, observedAt: at(3), token: "c2")
    }
    try expect(try occurrences(f, resumed).isEmpty)
    _ = try f.book.verify()
  }

  func saveCheck(_ f: Fixture, _ statement: String, description: String = "Parts below their reorder level.",
    inputs: [(name: String, type: String)] = []) throws
  {
    _ = try f.book.chatSaveTool(
      name: "low_stock", description: description, inputs: inputs, statements: [statement],
      source: nil, token: identifier(), requestSourceID: nil)
  }
  func checkSource(_ f: Fixture, _ result: Value) throws -> Item { try f.book.item(result["sourceID"].text) }

  check("an edited check is followed, and a changed rule starts fresh while a new description does not") {
    let f = try fixture("Edited")
    let session = try f.book.authorizeExecution(f.definition, generation: 0, after: start)
    try setQuantity(f, "5")
    let first = try f.book.checkAutomation(session.planning, observedAt: at(1), token: "c1")
    try expect(first["status"] == .string("fired"))
    try expect(try checkSource(f, first).data["checkID"] == .string(f.check.definitionID))
    _ = try f.book.dispatchAutomationOccurrence(session, observedAt: at(1), token: "d1")
    // Only the description changes: the same rule, so rows that stay fire nothing.
    try saveCheck(f, "SELECT name FROM parts WHERE qty < reorder", description: "Parts to reorder.")
    let same = try f.book.checkAutomation(session.planning, observedAt: at(2), token: "c2")
    try expect(same["status"] == .string("finding") && same["changed"] == .bool(false))
    // The threshold changes: the new rule has never run, so its rows fire once, and the
    // change records the exact new version that ran.
    try saveCheck(f, "SELECT name FROM parts WHERE qty < reorder * 2")
    let edited = try f.book.savedTools().first { $0.name == "low_stock" }!
    try expect(edited.logicalID == f.check.logicalID && edited.definitionID != f.check.definitionID)
    let fresh = try f.book.checkAutomation(session.planning, observedAt: at(3), token: "c3")
    try expect(fresh["status"] == .string("fired"))
    let source = try checkSource(f, fresh)
    try expect(
      source.data["checkID"] == .string(edited.definitionID)
        && source.data["changedCheck"] == .bool(true))
    try expect(try occurrences(f, session).count == 2)
    _ = try f.book.dispatchAutomationOccurrence(session, observedAt: at(3), token: "d3")
    // Rows of the new rule stay: nothing more.
    let stays = try f.book.checkAutomation(session.planning, observedAt: at(4), token: "c4")
    try expect(stays["status"] == .string("finding") && stays["changed"] == .bool(false))
    // A rule that finds nothing after an edit saves that, so the page shows the new state.
    try saveCheck(f, "SELECT name FROM parts WHERE qty < 0")
    let cleared = try f.book.checkAutomation(session.planning, observedAt: at(5), token: "c5")
    try expect(cleared["status"] == .string("cleared"))
    try expect(try f.book.automationCheckState(session.planning.activationID)["finding"].int == 0)
    _ = try f.book.verify()
  }

  check("a check changed into inputs, writes or removed makes the automation wait with the reason") {
    let f = try fixture("Invalid")
    let session = try f.book.authorizeExecution(f.definition, generation: 0, after: start)
    try saveCheck(f, "SELECT name FROM parts WHERE qty < :level", inputs: [("level", "decimal")])
    do {
      _ = try f.book.checkAutomation(session.planning, observedAt: at(1), token: "c1")
      throw SevraError("test", "A check with inputs ran.")
    } catch let error as SevraError where error.code == "automation_check" {
      try expect(error.message.contains("takes no inputs") && error.message.contains("waits"))
    }
    try saveCheck(f, "UPDATE parts SET qty = qty + 1")
    try refuses("automation_check") {
      _ = try f.book.checkAutomation(session.planning, observedAt: at(2), token: "c2")
    }
    _ = try f.book.retireTool("low_stock")
    do {
      _ = try f.book.checkAutomation(session.planning, observedAt: at(3), token: "c3")
      throw SevraError("test", "A removed check ran.")
    } catch let error as SevraError where error.code == "automation_check" {
      try expect(error.message.contains("was removed"))
    }
    try expect(try occurrences(f, session).isEmpty)
    // Saving a working check again resumes it with no other step.
    try saveCheck(f, "SELECT name FROM parts WHERE qty < reorder")
    try setQuantity(f, "5")
    let fired = try f.book.checkAutomation(session.planning, observedAt: at(4), token: "c4")
    try expect(fired["status"] == .string("fired"))
    _ = try f.book.verify()
  }

  check("rows that appeared while paused or closed fire once on resume, and rows that came and went fire nothing") {
    let f = try fixture("Missed")
    // Rows already present at enable fire at once: the person asked to know.
    try setQuantity(f, "5")
    let session = try f.book.authorizeExecution(f.definition, generation: 0, after: start)
    let now = try f.book.checkAutomation(session.planning, observedAt: at(1), token: "c1")
    try expect(now["status"] == .string("fired"))
    _ = try f.book.dispatchAutomationOccurrence(session, observedAt: at(1), token: "d1")
    try setQuantity(f, "50")
    _ = try f.book.checkAutomation(session.planning, observedAt: at(2), token: "c2")
    // Paused, then the rows come back: the first check after resuming fires once.
    _ = try f.book.pauseAutomation(
      session.planning.activationID, expectedGeneration: session.planning.generation, token: "p1")
    try setQuantity(f, "3")
    let reopened = try Workbook(f.book.url)
    let resumed = try reopened.authorizeExecution(
      f.definition, generation: session.planning.generation + 1, after: at(3))
    let missed = try reopened.checkAutomation(resumed.planning, observedAt: at(4), token: "c3")
    try expect(missed["status"] == .string("fired"))
    _ = try reopened.dispatchAutomationOccurrence(resumed, observedAt: at(4), token: "d3")
    try setQuantity(Fixture(book: reopened, parts: f.parts, definition: f.definition, check: f.check), "50")
    _ = try reopened.checkAutomation(resumed.planning, observedAt: at(5), token: "c4")
    // Paused again, rows come and go: nothing fires on resume.
    _ = try reopened.pauseAutomation(
      resumed.planning.activationID, expectedGeneration: resumed.planning.generation, token: "p2")
    let g = Fixture(book: reopened, parts: f.parts, definition: f.definition, check: f.check)
    try setQuantity(g, "2")
    try setQuantity(g, "40")
    let again = try reopened.authorizeExecution(
      f.definition, generation: resumed.planning.generation + 1, after: at(6))
    let quiet = try reopened.checkAutomation(again.planning, observedAt: at(7), token: "c5")
    try expect(quiet["status"] == .string("clear") && quiet["changed"] == .bool(false))
    try expect(
      try reopened.automationOccurrences(again.planning.activationID)["occurrences"].array.count
        == 2)
    _ = try reopened.verify()
  }

  check("an alert in place of a workflow drafts that alert for review when the check fires") {
    let f = try fixture("Alert")
    // The check by name, as chat writes it, and no parameters: both are filled in.
    let content = try f.book.boundAutomation(
      .object([
        "kind": .string("automation"), "title": .string("Low stock"),
        "description": .string("Alert when a part is below its reorder level"),
        "payload": .object([
          "policy": .string("check-v1"), "check": .object(["name": .string("low_stock")]),
          "alert": .string("A part is below its reorder level. Reorder it."),
        ]),
      ]), token: "alert", requestRunID: nil, requestSourceID: nil, cancellation: .init())
    try expect(
      content["payload"]["check"]["logicalID"] == .string(f.check.logicalID)
        && content["parameters"] == .array([]))
    let alert = try f.book.saveApplicationDefinition(logicalID: identifier(), content: content)
    let session = try f.book.authorizeExecution(alert, generation: 0, after: start)
    try setQuantity(f, "3")
    _ = try f.book.checkAutomation(session.planning, observedAt: at(1), token: "c1")
    let runID = try f.book.dispatchAutomationOccurrence(
      session, observedAt: at(1), token: "d1")["runID"].text
    let worker = try f.book.authorizeAutomationWorkflowExecution(session, runID: runID)
    _ = try f.book.advanceWorkflow(worker, owner: "test")
    let drafts = try f.book.items(kind: "document").filter { $0.status == "draft" }
    try expect(drafts.count == 1 && drafts[0].text.contains("reorder level"))
    _ = try f.book.verify()
  }

  func schedule() -> Value {
    .object([
      "policy": .string("native-calendar-v1"), "timeZone": .string("UTC"), "hour": .number(9),
      "minute": .number(0),
      "recurrence": .object(["kind": .string("weekly"), "weekdays": .array([.number(1)])]),
    ])
  }
  func automation(_ title: String, _ payload: [String: Value]) -> Value {
    .object([
      "kind": .string("automation"), "title": .string(title),
      "description": .string(title), "payload": .object(payload),
    ])
  }
  func dispatchWeekly(_ book: Workbook, _ definition: ApplicationDefinition) throws -> Value {
    // 2026-10-05 is a Monday.
    let session = try book.authorizeExecution(definition, generation: 0, after: start)
    let due = automationDate("2026-10-05T09:00:00Z")
    _ = try book.planAutomationOccurrences(session.planning, through: due, token: "plan")
    let runID = try book.dispatchAutomationOccurrence(
      session, observedAt: due, token: "dispatch")["runID"].text
    let worker = try book.authorizeAutomationWorkflowExecution(session, runID: runID)
    return try book.advanceWorkflow(worker, owner: "test")
  }

  check("a reminder on a schedule drafts its sentence for review, citing the request") {
    let f = try fixture("Reminder")
    let request = try f.book.captureUserRequest(
      "every Monday remind me to order supplies", data: .object([:]), token: "request")
    let content = try f.book.boundAutomation(
      automation(
        "Order supplies",
        [
          "policy": .string("calendar-v1"), "schedule": schedule(),
          "alert": .string("Order supplies."),
        ]), token: "reminder", requestRunID: nil, requestSourceID: request.id,
      cancellation: .init())
    try expect(
      content["payload"]["arguments"]["evidence"] == .string(request.id)
        && content["payload"]["workflow"]["versionID"]
          == .string(try f.book.applicationDefinition(Workbook.checkAlertWorkflowID).id))
    let reminder = try f.book.saveApplicationDefinition(
      logicalID: identifier(), content: content, inputs: [request.id])
    let notice = try f.book.previewAutomation(reminder.id, after: start)["notice"].text
    try expect(notice.contains("drafts its changes for review"))
    _ = try dispatchWeekly(f.book, reminder)
    let drafts = try f.book.items(kind: "document").filter { $0.status == "draft" }
    try expect(drafts.count == 1 && drafts[0].text.contains("Order supplies."))
    // Outside a chat request there is no request to cite.
    try refuses("automation_definition") {
      _ = try f.book.boundAutomation(
        automation(
          "Order supplies",
          [
            "policy": .string("calendar-v1"), "schedule": schedule(),
            "alert": .string("Order supplies."),
          ]), token: "reminder-2", requestRunID: nil, requestSourceID: nil,
        cancellation: .init())
    }
    _ = try f.book.verify()
  }

  check("a schedule runs a saved tool directly, and the enable notice names the tool") {
    let f = try fixture("Tool")
    _ = try f.book.chatSaveTool(
      name: "restock", description: "Adds stock to a part.",
      inputs: [(name: "amount", type: "decimal")],
      statements: ["UPDATE parts SET qty = qty + :amount WHERE name = 'bolts'"], source: nil,
      token: "save-restock", requestSourceID: nil)
    let content = try f.book.boundAutomation(
      automation(
        "Weekly restock",
        [
          "policy": .string("calendar-v1"), "schedule": schedule(),
          "tool": .object(["name": .string("restock")]),
          "arguments": .object(["amount": .string("5")]),
        ]), token: "restock", requestRunID: nil, requestSourceID: nil, cancellation: .init())
    let saved = try f.book.saveApplicationDefinition(logicalID: identifier(), content: content)
    try expect(
      try f.book.singleToolName(ofWorkflow: content["payload"]["workflow"]["versionID"].text)
        == "restock")
    let notice = try f.book.previewAutomation(saved.id, after: start)["notice"].text
    try expect(notice.contains("restock") && notice.contains("without review"))
    let run = try dispatchWeekly(f.book, saved)
    try expect(run["state"].text == "completed")
    try expect(
      try f.book.rows(f.parts.id, offset: 0, limit: 5).first?.data["qty"].text == "25")
    // The same tool again reuses its one-step workflow.
    let again = try f.book.boundAutomation(
      automation(
        "Restock when low",
        [
          "policy": .string("check-v1"), "check": .object(["name": .string("low_stock")]),
          "tool": .object(["name": .string("restock")]),
          "arguments": .object(["amount": .string("5")]),
        ]), token: "restock-2", requestRunID: nil, requestSourceID: nil, cancellation: .init())
    try expect(again["payload"]["workflow"] == content["payload"]["workflow"])
    _ = try f.book.verify()
  }

  check("an automation missing what it does says exactly which shape to use") {
    let f = try fixture("Shapes")
    func refusal(_ payload: [String: Value], parameters: Value? = nil) -> String {
      var content = automation("Weekly", payload).object
      if let parameters { content["parameters"] = parameters }
      do {
        _ = try f.book.boundAutomation(
          .object(content), token: identifier(), requestRunID: nil, requestSourceID: nil,
          cancellation: .init())
        return ""
      } catch let error as SevraError { return error.message } catch { return "" }
    }
    let nothing = refusal(["policy": .string("calendar-v1"), "schedule": schedule()])
    try expect(
      nothing.hasPrefix("Say what it does") && nothing.contains("alert: \"one sentence\"")
        && nothing.contains("tool: {name"))
    try expect(
      refusal(["schedule": schedule(), "alert": .string("Hi.")]).hasPrefix("Set policy"))
    try expect(
      refusal(["policy": .string("calendar-v1"), "alert": .string("Hi.")]).contains(
        "needs schedule"))
    try expect(
      refusal([
        "policy": .string("calendar-v1"), "schedule": schedule(),
        "workflow": .object(["mode": .string("exact"), "versionID": .string(identifier())]),
      ]).contains("no saved workflow has that versionID"))
    try expect(
      refusal(
        ["policy": .string("calendar-v1"), "schedule": schedule(), "alert": .string("Hi.")],
        parameters: .array([.object(["id": .string("x")])])
      ).contains("parameters to []"))
    try expect(
      refusal([
        "policy": .string("calendar-v1"), "schedule": schedule(),
        "tool": .object(["name": .string("nope")]),
      ]).contains("Saved tools: low_stock"))
  }
}

func checkAutomationContent(check: String, workflow: String, arguments: Value) -> Value {
  .object([
    "kind": .string("automation"), "title": .string("When stock runs low"),
    "description": .string("Prepare the note when the check finds rows"),
    "parameters": .array([]),
    "payload": .object([
      "policy": .string("check-v1"),
      "check": .object(["mode": .string("live"), "logicalID": .string(check)]),
      "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow)]),
      "arguments": arguments,
    ]),
  ])
}

extension Workbook {
  fileprivate func authorizeExecution(
    _ definition: ApplicationDefinition, generation: Int, after: Date
  ) throws -> AutomationExecutionSession {
    try authorizeAutomationExecution(
      definition.id, expectedGeneration: generation, after: after, token: identifier(),
      actor: .human("test"))
  }
}
