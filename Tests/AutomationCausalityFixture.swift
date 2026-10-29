import Foundation

@testable import SevraCore

struct CausalRun {
  let id: String
  let definition: ApplicationDefinition
  let session: AutomationExecutionSession
  let receipt: Value
}

final class CausalFixture {
  let book: Workbook
  let initial: ApplicationDefinition
  let workflow: ApplicationDefinition
  let start = automationDate("2026-10-01T08:00:00Z")
  let due = automationDate("2026-10-01T09:00:00Z")

  init(_ url: URL) throws {
    (book, initial) = try automationPlanningFixture(at: url)
    workflow = try book.applicationDefinition(
      initial.content["payload"]["workflow"]["versionID"].text)
  }

  func prepare(
    _ definition: ApplicationDefinition? = nil, generation: Int = 0,
    after: Date? = nil, at: Date? = nil
  ) throws -> (ApplicationDefinition, AutomationExecutionSession) {
    let target = try definition ?? executionAutomation(book, workflow: workflow)
    let session = try book.authorizeAutomationExecution(
      target.id, expectedGeneration: generation, after: after ?? start, token: identifier())
    _ = try book.planAutomationOccurrences(
      session.planning, through: at ?? due, token: identifier())
    return (target, session)
  }

  func admit(
    _ definition: ApplicationDefinition? = nil, parents: [String]? = nil,
    generation: Int = 0, after: Date? = nil, at: Date? = nil
  ) throws -> CausalRun {
    let (target, session) = try prepare(definition, generation: generation, after: after, at: at)
    let receipt = try book.dispatchAutomaticCalendarRun(
      session, observedAt: at ?? due, token: identifier(), inheriting: parents)
    return CausalRun(
      id: receipt["runID"].text, definition: target, session: session, receipt: receipt)
  }

  func reject(_ code: String, parents: [String]) throws {
    let (_, session) = try prepare()
    let revision = try book.revision()
    let history = try book.committedHistory()
    try refuses(code) {
      _ = try book.dispatchAutomaticCalendarRun(
        session, observedAt: due, token: identifier(), inheriting: parents)
    }
    try expect(try book.revision() == revision && book.committedHistory() == history)
    try expect(
      try book.pendingAutomationOccurrence(session.planning.activationID)["state"].text == "pending"
    )
  }

  func finish(_ run: CausalRun) throws {
    let worker = try book.authorizeAutomationWorkflowExecution(run.session, runID: run.id)
    try expect(
      try book.advanceWorkflow(worker, owner: "causal-fixture")["state"].text == "completed")
  }
}

func createAutomationCausalityFixture(at url: URL) throws -> Value {
  let fixture = try CausalFixture(url)
  let seed = try fixture.admit(fixture.initial)
  let children = try (0..<9).map { _ in
    try executionAutomation(fixture.book, workflow: fixture.workflow).id
  }
  return .object([
    "runID": .string(seed.id), "definitionID": .string(seed.definition.id),
    "children": .array(children.map(Value.string)),
    "origin": try fixture.book.automationCausality(seed.id),
  ])
}

func automationCausalityWorker(path: String, definition: String, parent: String) throws -> Value {
  let book = try Workbook(URL(fileURLWithPath: path))
  let session = try book.authorizeAutomationExecution(
    definition, expectedGeneration: 0, after: automationDate("2026-10-01T08:00:00Z"),
    token: "causal-authorize:" + definition)
  let due = automationDate("2026-10-01T09:00:00Z")
  _ = try book.planAutomationOccurrences(
    session.planning, through: due, token: "causal-plan:" + definition)
  return try book.dispatchAutomaticCalendarRun(
    session, observedAt: due, token: "causal-dispatch:" + definition, inheriting: [parent])
}
