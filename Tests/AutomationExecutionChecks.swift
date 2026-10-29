import Foundation

@testable import SevraCore

func executionAutomation(
  _ book: Workbook, workflow: ApplicationDefinition, arguments: Value = .object([:])
) throws -> ApplicationDefinition {
  try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("automation"), "title": .string("Scheduled draft"),
      "description": .string("Synthetic foreground execution"), "parameters": .array([]),
      "payload": .object([
        "policy": .string("calendar-drafts-v1"),
        "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow.id)]),
        "arguments": arguments,
        "schedule": .object([
          "policy": .string("native-calendar-v1"), "timeZone": .string("UTC"), "hour": .number(9),
          "minute": .number(0), "recurrence": .object(["kind": .string("daily")]),
        ]),
      ]),
    ]))
}

func createAutomationExecutionFixture(at url: URL, ai: Bool = false) throws -> Value {
  if !ai {
    let (book, definition) = try automationPlanningFixture(at: url)
    _ = try book.verify()
    return .object(["workbook": .string(url.path), "definitionID": .string(definition.id)])
  }
  let book = try Workbook.create(at: url, title: "Synthetic AI scope")
  let source = try book.addItem(
    category: "source", kind: "observation", title: "Synthetic receipt", text: "Received5 items")
  let interpretation = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("interpretation"), "title": .string("Read synthetic receipt"),
      "description": .string("Scope fixture"),
      "parameters": .array([ActionRegistry.field("evidence", "Evidence", "item")]),
      "payload": .object([
        "instruction": .string("Read the count"), "evidence": .array([.string("evidence")]),
        "outputs": .array([ActionRegistry.field("quantity", "Count", "decimal", unit: "items")]),
        "meaning": .string("actual"), "scenario": .string("actual"),
      ]),
    ]))
  let workflow = try book.saveApplicationDefinition(
    logicalID: identifier(), content: book.workflowTemplate(interpretation.id))
  let definition = try executionAutomation(
    book, workflow: workflow, arguments: .object(["evidence": .string(source.id)]))
  _ = try book.verify()
  return .object(["workbook": .string(url.path), "definitionID": .string(definition.id)])
}

func checkAutomationExecution(at root: URL) {
  let start = automationDate("2026-10-01T08:00:00Z")
  let due = automationDate("2026-10-01T09:00:00Z")
  func fixture(_ name: String) throws -> (
    Workbook, ApplicationDefinition, AutomationExecutionSession
  ) {
    let (book, definition) = try automationPlanningFixture(
      at: root.appendingPathComponent("Execute-" + name + ".sevra"))
    let session = try book.authorizeAutomationExecution(
      definition.id, expectedGeneration: 0, after: start, token: "authorize",
      actor: .human("synthetic"))
    return (book, definition, session)
  }
  func dispatch(_ book: Workbook, _ session: AutomationExecutionSession) throws -> Value {
    _ = try book.planAutomationOccurrences(session.planning, through: due, token: "plan")
    return try book.dispatchAutomationOccurrence(session, observedAt: due, token: "dispatch")
  }
  check("preparation permission cannot be relabeled as execution or borrowed by another connection")
  {
    let (book, definition) = try automationPlanningFixture(
      at: root.appendingPathComponent("Execute-planning.sevra"))
    let plan = try book.authorizeAutomationPlanning(
      definition.id, expectedGeneration: 0, after: start, token: "plan")
    let forged = AutomationExecutionSession(plan, allowAI: false)
    let revision = try book.revision()
    try refuses("automation_authority") {
      _ = try book.dispatchAutomationOccurrence(forged, observedAt: due, token: "execute")
    }
    let other = try Workbook(book.url)
    try refuses("automation_authority") {
      _ = try other.dispatchAutomationOccurrence(forged, observedAt: due, token: "borrow")
    }
    try expect(try book.revision() == revision && book.workflowRuns().isEmpty)
    _ = try book.verify()
  }
  check(
    "authorization Sources stay outside business evidence while execution provenance remains inspectable"
  ) {
    let (book, _, session) = try fixture("EvidenceScope")
    let receipt = try dispatch(book, session)
    let id = receipt["runID"].text
    let manual = try book.authorizeWorkflowExecution(id, token: "manual")
    let tools = WorkbookTools(book)
    let sources = try book.items().filter {
      [
        "automation_authorization", "automation_planning", "automation_dispatch",
        "workflow_authorization",
      ].contains($0.kind)
    }
    try expect(sources.count == 4)
    for source in sources {
      try expect(!source.isBusinessEvidence)
      try refuses("item_scope") { _ = try tools.readableItem(source.id) }
      try expect(try book.search("foreground", kind: source.kind, businessOnly: true).hits.isEmpty)
    }
    let claim = try book.claimWorkflowStep(manual, owner: "manual", token: "claim")
    let inspection = try book.inspectWorkflow(id)
    try expect(
      inspection["invocation"]["policy"].text == "automation-drafts-v1"
        && inspection["invocation"]["origin"]["activationID"].text == session.planning.activationID)
    try expect(
      inspection["steps"].array[0]["attempt"]["authorization"]["sourceID"]
        == claim["authorization_source"])
    try expect(
      try book.workflowActivity()["runs"].array[0]["policy"].text == "automation-drafts-v1")
    _ = try book.verify()
  }
  check(
    "scheduled dispatch atomically retains exact inputs, run binding, Source lineage and honest policy"
  ) {
    let (book, definition, session) = try fixture("Provenance")
    let receipt = try dispatch(book, session)
    let run = try book.workflowRun(receipt["runID"].text)
    let invocation = try book.item(run["source_id"].text)
    try expect(
      receipt["status"].text == "queued" && run["state"].text == "queued"
        && run["policy"].text == "automation-drafts-v1")
    try expect(
      invocation.data["origin"]["automationID"].text == definition.id
        && invocation.data["actor"]["kind"].text == "programmatic")
    try expect(
      invocation.text.contains("scheduled") && !invocation.text.contains("manual workflow"))
    try expect(invocation.data["origin"]["authorizationSourceID"].text == session.planning.sourceID)
    let revision = try book.revision()
    try expect(
      try book.dispatchAutomationOccurrence(session, observedAt: due, token: "dispatch") == receipt)
    try expect(try book.revision() == revision)
    let again = try book.dispatchAutomationOccurrence(
      session, observedAt: due, token: "different-token")
    try expect(
      again["status"].text == "active" && again["run"]["id"] == run["id"]
        && book.workflowRuns().count == 1)
    _ = try book.verify()
  }
  check("one active run blocks overlap; a completed run releases the next calendar request") {
    let (book, _, session) = try fixture("Overlap")
    let runID = try dispatch(book, session)["runID"].text
    let next = automationDate("2026-10-02T09:00:00Z")
    _ = try book.planAutomationOccurrences(session.planning, through: next, token: "next")
    let blocked = try book.dispatchAutomationOccurrence(session, observedAt: next, token: "blocked")
    try expect(blocked["status"].text == "active" && blocked["run"]["id"].text == runID)
    let worker = try book.authorizeAutomationWorkflowExecution(session, runID: runID)
    let completed = try book.advanceWorkflow(worker, owner: "synthetic")
    try expect(
      completed["state"].text == "completed"
        && completed["steps"].array[0]["output"]["value"]["result"].text == "3")
    let dispatched = try book.dispatchAutomationOccurrence(
      session, observedAt: next, token: "second")
    try expect(dispatched["runID"].text != runID && book.workflowRuns().count == 2)
    _ = try book.verify()
  }
  check("scheduled business actions wait for exact review and retain domain occurrence identities")
  {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Execute-review.sevra"), title: "Scheduled receiving")
    let source = try book.addItem(
      category: "source", kind: "observation", title: "Synthetic delivery", status: "accepted")
    try book.setOpeningBalance(
      subject: "bolts", quantity: "20", effective: "2026-01-01", sourceID: source.id)
    let action = try book.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.receivingDefinition())
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(), content: book.workflowTemplate(action.id))
    let arguments: Value = .object([
      "delivery": .string("delivery-one"), "effective": .string("2026-10-01"),
      "evidence": .string(source.id),
      "lines": .array([
        .object(["line": .string("one"), "subject": .string("bolts"), "quantity": .string("5")])
      ]),
    ])
    let definition = try executionAutomation(book, workflow: workflow, arguments: arguments)
    let session = try book.authorizeAutomationExecution(
      definition.id, expectedGeneration: 0, after: start, token: "authorize")
    let id = try dispatch(book, session)["runID"].text
    let worker = try book.authorizeAutomationWorkflowExecution(session, runID: id)
    let waiting = try book.continueWorkflow(worker, owner: "scheduled")
    try expect(
      waiting["state"].text == "waiting_review"
        && book.balance(subject: "bolts")["quantity"].text == "20")
    let blocked = try book.dispatchAutomationOccurrence(
      session, observedAt: due, token: "blocked-review")
    try expect(blocked["status"].text == "active" && blocked["run"]["id"].text == id)
    let proposals = waiting["steps"].array[0]["output"]["value"]["proposals"].array
    try expect(proposals.count == 1)
    _ = try book.accept(proposals[0].text, actor: .human("synthetic exact review"))
    let completed = try book.continueWorkflow(worker, owner: "reviewed")
    try expect(
      completed["state"].text == "completed"
        && book.balance(subject: "bolts")["quantity"].text == "25")
    try expect(try book.balance(subject: "bolts")["effects"].array.count == 1)
    _ = try book.verify()
  }
  check(
    "incomplete catch-up cannot dispatch an intermediate slot; clock rollback defers future work"
  ) {
    let (book, _, session) = try fixture("Clock")
    _ = try book.planAutomationOccurrences(
      session.planning, through: automationDate("2026-10-04T09:00:00Z"), token: "bounded", limit: 1)
    try refuses("automation_catch_up") {
      _ = try book.dispatchAutomationOccurrence(session, observedAt: due, token: "too-soon")
    }
    _ = try book.planAutomationOccurrences(
      session.planning, through: automationDate("2026-10-04T09:00:00Z"), token: "finish")
    let future = try book.dispatchAutomationOccurrence(
      session, observedAt: start, token: "rollback")
    try expect(future["status"].text == "future" && book.workflowRuns().isEmpty)
    _ = try book.verify()
  }
  check("dispatch rechecks lateness and allows the exact 24-hour boundary") {
    let (book, _, session) = try fixture("Late")
    _ = try book.planAutomationOccurrences(session.planning, through: due, token: "plan")
    let late = try book.dispatchAutomationOccurrence(
      session, observedAt: due.addingTimeInterval(86_400.001), token: "late")
    try expect(
      late["status"].text == "late" && late["runID"] == .null && book.workflowRuns().isEmpty)
    try expect(
      try book.automationOccurrences(session.planning.activationID)["occurrences"].array[0][
        "detail"
      ].text == "late")
    _ = try book.verify()
    let (edge, _, permit) = try fixture("LateEdge")
    _ = try edge.planAutomationOccurrences(permit.planning, through: due, token: "plan")
    let accepted = try edge.dispatchAutomationOccurrence(
      permit, observedAt: due.addingTimeInterval(86_400), token: "edge")
    try expect(accepted["status"].text == "queued")
    _ = try edge.verify()
  }
  check(
    "pause immediately releases automation claims and fences publication; explicit resume uses the same run"
  ) {
    let (book, definition, session) = try fixture("Pause")
    let id = try dispatch(book, session)["runID"].text
    let worker = try book.authorizeAutomationWorkflowExecution(session, runID: id)
    let claim = try book.claimWorkflowStep(worker, owner: "old-worker", token: "claim")
    _ = try book.pauseAutomation(
      session.planning.activationID, expectedGeneration: 1, token: "pause")
    try expect(try book.workflowRun(id)["state"].text == "queued")
    try refuses("automation_authority") { _ = try book.completeWorkflowStep(worker, claim: claim) }
    let resumed = try book.authorizeAutomationExecution(
      definition.id, expectedGeneration: 2, after: start, token: "resume")
    let active = try book.dispatchAutomationOccurrence(
      resumed, observedAt: due, token: "resume-dispatch")
    try expect(active["run"]["id"].text == id)
    let newWorker = try book.authorizeAutomationWorkflowExecution(resumed, runID: id)
    let replacement = try book.claimWorkflowStep(newWorker, owner: "new-worker", token: "replace")
    try expect(
      replacement["generation"].int == 2
        && replacement["authorization_source"] != claim["authorization_source"])
    let completed = try book.completeWorkflowStep(newWorker, claim: replacement)
    try expect(completed["state"].text == "completed" && book.workflowRuns().count == 1)
    _ = try book.verify()
  }
  check(
    "manual continuation has new provenance, preserves its lease across pause and cannot enable schedules"
  ) {
    let (book, _, session) = try fixture("Manual")
    let id = try dispatch(book, session)["runID"].text
    let manual = try book.authorizeWorkflowExecution(
      id, token: "manual", actor: .human("synthetic Continue"))
    let source = try book.item(manual.manualSourceID!)
    try expect(
      source.kind == "workflow_authorization" && source.data["policy"].text == "manual-operation-v1"
    )
    let claim = try book.claimWorkflowStep(manual, owner: "manual-worker", token: "claim")
    _ = try book.pauseAutomation(
      session.planning.activationID, expectedGeneration: 1, token: "pause")
    try expect(try book.workflowRun(id)["state"].text == "running")
    // Separate CLI processes may explicitly operate the same manual claim.
    let nextManual = try book.authorizeWorkflowExecution(id, token: "manual-finish")
    let done = try book.completeWorkflowStep(nextManual, claim: claim)
    try expect(done["state"].text == "completed" && done["policy"].text == "automation-drafts-v1")
    try refuses("automation_authority") {
      _ = try book.dispatchAutomationOccurrence(session, observedAt: due, token: "not-enabled")
    }
    _ = try book.verify()
  }
  check("a new manual permission cannot publish a claim held by an automation worker") {
    let (book, _, session) = try fixture("ManualFence")
    let id = try dispatch(book, session)["runID"].text
    let automated = try book.authorizeAutomationWorkflowExecution(session, runID: id)
    let claim = try book.claimWorkflowStep(automated, owner: "automation", token: "claim")
    let manual = try book.authorizeWorkflowExecution(id, token: "manual")
    try refuses("workflow_fenced") { _ = try book.completeWorkflowStep(manual, claim: claim) }
    _ = try book.completeWorkflowStep(automated, claim: claim)
    _ = try book.verify()
  }
  check(
    "changing exact version requires finishing or Stop; Stop creates no execution authorization"
  ) {
    let (book, definition, session) = try fixture("Edit")
    let id = try dispatch(book, session)["runID"].text
    var content = definition.content.object
    content["title"] = .string("New intention")
    let new = try book.saveApplicationDefinition(
      logicalID: definition.logicalID, content: .object(content),
      expectedDefinitionID: definition.id)
    try refuses("automation_busy") {
      _ = try book.authorizeAutomationExecution(
        new.id, expectedGeneration: 1, after: start, token: "edit")
    }
    let before = try book.counts()
    let stopped = try book.cancelWorkflow(id, token: "stop", actor: .human("synthetic Stop"))
    try expect(
      stopped["state"].text == "cancelled" && book.counts()["sources"] == before["sources"]
        && book.counts()["records"] == before["records"])
    let next = try book.authorizeAutomationExecution(
      new.id, expectedGeneration: 1, after: due, token: "new")
    try expect(next.planning.generation == 2)
    _ = try book.verify()
  }
  check(
    "execution permission is inert after reconstruction, and explicit new permission resumes without redispatch"
  ) {
    let (book, definition, session) = try fixture("Reconstruct")
    let id = try dispatch(book, session)["runID"].text
    let worker = try book.authorizeAutomationWorkflowExecution(session, runID: id)
    let copy = try book.reconstruct(to: root.appendingPathComponent("Execute-inert.sevra"))
    try expect(
      try copy.workflowRun(id) == book.workflowRun(id)
        && copy.automationEvents() == book.automationEvents())
    try refuses("workflow_authority") { _ = try copy.advanceWorkflow(worker, owner: "borrow") }
    let forged = WorkflowExecutionSession(copy, runID: id)
    try refuses("workflow_authority") { _ = try copy.advanceWorkflow(forged, owner: "saved-text") }
    let permitted = try copy.authorizeAutomationExecution(
      definition.id, expectedGeneration: 1, after: start, token: "explicit-copy")
    let receipt = try copy.dispatchAutomationOccurrence(
      permitted, observedAt: due, token: "same-run")
    try expect(
      receipt["status"].text == "active" && receipt["run"]["id"].text == id
        && copy.workflowRuns().count == 1)
    let completed = try copy.advanceWorkflow(
      copy.authorizeAutomationWorkflowExecution(permitted, runID: id), owner: "explicit")
    try expect(completed["state"].text == "completed")
    _ = try copy.verify()
  }
  check("AI execution requires explicit scope before creating a grant or loading a model") {
    let url = root.appendingPathComponent("Execute-AI.sevra")
    let fixture = try createAutomationExecutionFixture(at: url, ai: true)
    let book = try Workbook(url)
    let revision = try book.revision()
    try refuses("automation_ai_scope") {
      _ = try book.authorizeAutomationExecution(
        fixture["definitionID"].text, expectedGeneration: 0, after: start, token: "denied")
    }
    try expect(try book.revision() == revision)
    let session = try book.authorizeAutomationExecution(
      fixture["definitionID"].text, expectedGeneration: 0, after: start, allowAI: true,
      token: "allow")
    let id = try dispatch(book, session)["runID"].text
    let worker = try book.authorizeAutomationWorkflowExecution(session, runID: id)
    try book.validateWorkflowExecution(worker, forAI: true)
    _ = try book.pauseAutomation(
      session.planning.activationID, expectedGeneration: 1, token: "pause")
    try refuses("automation_authority") { try book.validateWorkflowExecution(worker, forAI: true) }
    _ = try book.verify()
  }
  check(
    "dispatch publication failure and cancellation leave no partial run, binding, decisions or events"
  ) {
    let (book, _, session) = try fixture("Rollback")
    _ = try book.planAutomationOccurrences(session.planning, through: due, token: "plan")
    let revision = try book.revision()
    let events = try book.automationEvents()
    let occurrences = try book.automationOccurrences(session.planning.activationID)
    try book.db.execute(
      "CREATE TEMP TRIGGER fail_dispatch BEFORE INSERT ON main.committed_changes BEGIN SELECT RAISE(ABORT,'injected dispatch failure'); END;"
    )
    try refuses {
      _ = try book.dispatchAutomationOccurrence(session, observedAt: due, token: "fault")
    }
    try book.db.execute("DROP TRIGGER fail_dispatch")
    try expect(
      try book.revision() == revision && book.automationEvents() == events
        && book.automationOccurrences(session.planning.activationID) == occurrences
        && book.workflowRuns().isEmpty)
    let cancellation = Cancellation()
    cancellation.cancel()
    try refuses("cancelled") {
      _ = try book.dispatchAutomationOccurrence(
        session, observedAt: due, token: "cancel", cancellation: cancellation)
    }
    _ = try book.verify()
  }
  check("concurrent dispatch has exactly one run and one occurrence binding") {
    let (book, _, session) = try fixture("Concurrency")
    _ = try book.planAutomationOccurrences(session.planning, through: due, token: "plan")
    let group = DispatchGroup()
    let lock = NSLock()
    var results: [Result<Value, Error>] = []
    for index in 0..<2 {
      group.enter()
      DispatchQueue.global().async {
        let result = Result {
          try book.dispatchAutomationOccurrence(
            session, observedAt: due, token: "dispatch-" + String(index))
        }
        lock.lock()
        results.append(result)
        lock.unlock()
        group.leave()
      }
    }
    try expect(group.wait(timeout: .now() + 30) == .success)
    let values = try results.map { try $0.get() }
    try expect(
      Set(values.map { $0["status"].text }) == ["active", "queued"]
        && book.workflowRuns().count == 1)
    _ = try book.verify()
  }
  check(
    "integrity rejects a missing binding, changed original intent and incorrect worker authorization"
  ) {
    for corruption in 0..<3 {
      let (book, _, session) = try fixture("Corrupt-" + String(corruption))
      let id = try dispatch(book, session)["runID"].text
      let worker = try book.authorizeAutomationWorkflowExecution(session, runID: id)
      _ = try book.claimWorkflowStep(worker, owner: "fixture", token: "claim")
      _ = try book.db.transaction {
        if corruption == 0 {
          try book.db.execute("DELETE FROM automatic_root_members WHERE run_id=?", [.string(id)])
          try book.db.execute("DELETE FROM automatic_admissions WHERE run_id=?", [.string(id)])
          try book.db.execute("DELETE FROM automation_runs WHERE run_id=?", [.string(id)])
        } else if corruption == 1 {
          try book.db.execute(
            "UPDATE automation_runs SET generation=999 WHERE run_id=?", [.string(id)])
        } else {
          try book.db.execute(
            "UPDATE workflow_attempts SET authorization_source=(SELECT source_id FROM workflow_runs WHERE id=?) WHERE run_id=?",
            [.string(id), .string(id)])
        }
      }
      try refuses { _ = try book.verify() }
    }
  }
}
