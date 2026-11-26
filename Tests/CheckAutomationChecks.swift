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
        check: check.definitionID, workflow: workflow.id,
        arguments: noteArguments(source.id, title: "Reorder parts")))
    return Fixture(book: book, parts: parts, definition: definition)
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
    let g = Fixture(book: reopened, parts: f.parts, definition: f.definition)
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
            check: tool.definitionID, workflow: workflow.id,
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
    let check = f.definition.payload["check"]["versionID"].text
    try f.book.disableTool(check)
    try refuses("tool_disabled") {
      _ = try f.book.checkAutomation(resumed.planning, observedAt: at(3), token: "c2")
    }
    try expect(try occurrences(f, resumed).isEmpty)
    _ = try f.book.verify()
  }

  check("an alert in place of a workflow drafts that alert for review when the check fires") {
    let f = try fixture("Alert")
    let check = f.definition.payload["check"]
    let content = try f.book.checkAlertAutomation(
      .object([
        "kind": .string("automation"), "title": .string("Low stock"),
        "description": .string("Alert when a part is below its reorder level"),
        "parameters": .array([]),
        "payload": .object([
          "policy": .string("check-drafts-v1"), "check": check,
          "alert": .string("A part is below its reorder level. Reorder it."),
        ]),
      ]), token: "alert", requestRunID: nil, requestSourceID: nil, cancellation: .init())
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
}

func checkAutomationContent(check: String, workflow: String, arguments: Value) -> Value {
  .object([
    "kind": .string("automation"), "title": .string("When stock runs low"),
    "description": .string("Prepare the note when the check finds rows"),
    "parameters": .array([]),
    "payload": .object([
      "policy": .string("check-drafts-v1"),
      "check": .object(["mode": .string("exact"), "versionID": .string(check)]),
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
