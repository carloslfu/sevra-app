import Foundation

@testable import SevraCore

func conditionAutomation(
  _ book: Workbook, workflow: ApplicationDefinition, logicalID: String = identifier(),
  base: String? = nil, threshold: String = "10", arguments: Value = .object([:])
) throws -> ApplicationDefinition {
  try book.saveApplicationDefinition(
    logicalID: logicalID,
    content: .object([
      "kind": .string("automation"), "title": .string("Prepare low-stock report"),
      "description": .string("Synthetic actual inventory transition"), "parameters": .array([]),
      "payload": .object([
        "policy": .string("inventory-condition-drafts-v1"),
        "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow.id)]),
        "arguments": arguments,
        "condition": .object([
          "subject": .string("parts"),
          "rule": inventoryConditionRule(threshold: threshold),
        ]),
      ]),
    ]), expectedDefinitionID: base)
}

final class ConditionDispatchFixture {
  let book: Workbook
  let workflow: ApplicationDefinition
  let definition: ApplicationDefinition
  let session: AutomationExecutionSession
  let through = "2026-12-31"
  let observed = automationDate("2027-01-01T00:00:00Z")
  var consumer: String {
    get throws { try book.automationState(definition.id)["consumer_id"].text }
  }

  init(_ url: URL, opening: String = "20") throws {
    let (book, calendar) = try automationPlanningFixture(at: url)
    self.book = book
    workflow = try book.applicationDefinition(calendar.payload["workflow"]["versionID"].text)
    let source = try book.recordBusinessObservation(title: "Counted opening inventory")
    try book.setOpeningBalance(
      subject: "parts", quantity: opening, effective: "2026-01-01", sourceID: source.id)
    definition = try conditionAutomation(book, workflow: workflow)
    session = try book.authorizeInventoryConditionExecution(
      definition.id, expectedGeneration: 0,
      after: automationDate("2026-12-31T00:00:00Z"), token: "enable", actor: .human("synthetic"))
    _ = try drain(session)
  }
  func drain(_ session: AutomationExecutionSession) throws -> Value {
    var result = Value.null
    for _ in 0..<1000 {
      result = try book.stepAutomationCondition(session, through: through, token: identifier())
      if result["hasMore"] == .bool(false) { return result }
    }
    throw SevraError("test", "Condition did not finish bounded pages.")
  }
  @discardableResult func move(_ amount: String, declared: Bool = true, input: String? = nil) throws
    -> Item
  {
    let source: String
    if let input {
      source = input
    } else if declared {
      source = try book.recordBusinessObservation(title: "New counted business input").id
    } else {
      source = try book.addItem(category: "source", kind: "observation", title: "Undeclared label")
        .id
    }
    return try book.movement(
      subject: "parts", quantity: amount, occurrence: identifier(),
      effective: "2026-02-01", input: source, status: "accepted")
  }
  func dispatch(_ session: AutomationExecutionSession? = nil, token: String = identifier()) throws
    -> Value
  {
    try book.dispatchInventoryCondition(session ?? self.session, observedAt: observed, token: token)
  }
  func finish(_ result: Value, session: AutomationExecutionSession? = nil) throws {
    let worker = try book.authorizeAutomationWorkflowExecution(
      session ?? self.session, runID: result["runID"].text)
    try expect(
      try book.continueWorkflow(worker, owner: "condition-fixture")["state"].text == "completed")
  }
}

func checkConditionDispatch(at directory: URL) {
  func fixture(_ name: String, opening: String = "20") throws -> ConditionDispatchFixture {
    try ConditionDispatchFixture(
      directory.appendingPathComponent("ConditionDispatch-" + name + ".sevra"), opening: opening)
  }
  check("condition definitions preview inert intent and calendar authority cannot activate them") {
    let f = try fixture("Definition")
    let before = try f.book.revision()
    let preview = try f.book.previewAutomation(f.definition.id, after: f.observed)
    try expect(
      preview["condition"]["rule"] == inventoryConditionRule() && preview["enabled"] == .bool(false)
    )
    try refuses("automation_trigger") {
      _ = try f.book.authorizeAutomationExecution(
        f.definition.id, expectedGeneration: 1, after: f.observed, token: "wrong")
    }
    try refuses("automation_trigger") {
      _ = try f.book.planAutomationOccurrences(
        f.session.planning, through: f.observed, token: "calendar")
    }
    try refuses("automation_trigger") {
      _ = try f.book.dispatchAutomationOccurrence(
        f.session, observedAt: f.observed, token: "calendar-dispatch")
    }
    try expect(try f.book.revision() == before)
    _ = try f.book.verify()
  }
  check(
    "unsaved automation preview validates scope and typed arguments without saving intent or permission"
  ) {
    let f = try fixture("Draft")
    let before = try f.book.committedHistory()
    let preview = try f.book.previewAutomationDraft(f.definition.content, after: f.observed)
    try expect(
      preview["condition"]["rule"] == inventoryConditionRule()
        && preview["execution"].text == "inert")
    var content = f.definition.content.object
    var payload = content["payload"]!.object
    payload["condition"] = .object(["subject": .string("other"), "rule": inventoryConditionRule()])
    content["payload"] = .object(payload)
    try refuses("condition_scope") {
      _ = try f.book.previewAutomationDraft(.object(content), after: f.observed)
    }
    try expect(try f.book.committedHistory() == before)
  }
  check(
    "native condition probes stay read-only and notice due effective inputs without idle writes"
  ) {
    let f = try fixture("Probe")
    let source = try f.book.recordBusinessObservation(title: "Future scheduled business input")
    _ = try f.book.movement(
      subject: "parts", quantity: "-15", occurrence: "future", effective: "2028-01-01",
      input: source.id, status: "accepted")
    _ = try f.drain(f.session)
    let before = try f.book.committedHistory()
    for _ in 0..<10 {
      let probe = try f.book.deviceConditionWork(f.session, through: f.observed)
      try expect(probe["needsStep"] == .bool(false) && probe["pendingCandidates"].int == 0)
    }
    try expect(try f.book.committedHistory() == before)
    let due = automationDate("2028-01-01T00:00:00Z")
    try expect(try f.book.deviceConditionWork(f.session, through: due)["needsStep"] == .bool(true))
    _ = try f.book.stepAutomationCondition(f.session, through: "2028-01-01", token: "due")
    let run = try f.book.dispatchInventoryCondition(
      f.session, observedAt: due, token: "due-dispatch")
    try expect(run["status"].text == "queued" && run["trigger"]["quantity"].text == "5")
    _ = try f.book.verify()
  }
  check("initial true condition establishes a baseline without inventing a crossing") {
    let f = try fixture("InitialTrue", opening: "5")
    try expect(try f.book.inventoryCondition(f.consumer)["pendingCandidates"].int == 0)
    try expect(try f.dispatch()["status"].text == "idle" && f.book.workflowRuns().isEmpty)
    _ = try f.book.verify()
  }
  check(
    "actual candidate dispatch binds one exact condition workflow and shared original cause atomically"
  ) {
    let f = try fixture("Dispatch")
    let movement = try f.move("-15")
    let observation = try f.drain(f.session)["lastCompleteObservation"]
    let result = try f.dispatch(token: "dispatch")
    let run = try f.book.workflowRun(result["runID"].text)
    let binding = try f.book.automationRunBinding(run["id"].text)
    try expect(
      binding["occurrence_id"] == .null && binding["candidate_id"] == observation["candidateID"])
    try expect(
      result["trigger"]["quantity"].text == "5"
        && result["trigger"]["observationID"] == observation["id"])
    let causes = try f.book.inventoryConditionCauses(observation["id"].text)
    try expect(
      try f.book.automationCausality(run["id"].text)["origin"]["roots"] == causes["rootIDs"])
    let commits = try f.book.committedHistory()
    try expect(try f.dispatch(token: "dispatch") == result && f.book.committedHistory() == commits)
    try expect(try f.dispatch()["status"].text == "active" && f.book.workflowRuns().count == 1)
    try expect(try f.book.item(run["source_id"].text).text.contains("inventory-condition"))
    try f.finish(result)
    try expect(try f.dispatch()["status"].text == "idle")
    try expect(try f.book.balance(subject: "parts")["quantity"].text == "5")
    try expect(try f.book.item(movement.id).status == "accepted")
    _ = try f.book.verify()
  }
  check("pause revokes old sessions and resume retains the exact ordered candidate queue") {
    let f = try fixture("Resume")
    _ = try f.move("-15")
    _ = try f.drain(f.session)
    let old = try f.consumer
    _ = try f.book.pauseAutomation(
      f.session.planning.activationID, expectedGeneration: 1, token: "pause")
    try refuses("automation_authority") { _ = try f.dispatch() }
    let resumed = try f.book.authorizeInventoryConditionExecution(
      f.definition.id, expectedGeneration: 2,
      after: f.observed, token: "resume")
    try expect(
      try f.consumer == old && f.book.inventoryCondition(old)["pendingCandidates"].int == 1)
    let result = try f.dispatch(resumed)
    try f.finish(result, session: resumed)
    try refuses("stale_automation") {
      _ = try f.book.authorizeInventoryConditionExecution(
        f.definition.id, expectedGeneration: 0,
        after: automationDate("2026-12-31T00:00:00Z"), token: "enable", actor: .human("synthetic"))
    }
    _ = try f.book.verify()
  }
  check("explicit from-now dismisses old candidates with evidence and creates a fresh baseline") {
    let f = try fixture("FromNow")
    _ = try f.move("-15")
    _ = try f.drain(f.session)
    let old = try f.consumer
    let next = try f.book.authorizeInventoryConditionExecution(
      f.definition.id, expectedGeneration: 1,
      after: f.observed, fromNow: true, token: "from-now", actor: .human("synthetic"))
    try expect(try f.consumer != old)
    try expect(
      try f.book.db.scalar(
        "SELECT detail FROM condition_candidates WHERE consumer_id=?", [.string(old)]
      ).text == "explicit_from_now")
    let status = try f.book.inventoryCondition(f.consumer)
    try expect(status["established"] == .bool(false) && status["pendingCandidates"].int == 0)
    _ = try f.book.stepAutomationCondition(next, through: "2027-01-01", token: "baseline")
    _ = try f.book.verify()
  }
  check("blocked earliest candidate cannot be bypassed by a later independently rooted crossing") {
    let f = try fixture("Blocked")
    _ = try f.move("-15", declared: false)
    _ = try f.drain(f.session)
    let first = try f.book.inventoryConditionObservations(f.consumer)["observations"].array.first {
      $0["candidateID"] != .null
    }!["candidateID"]
    _ = try f.move("15")
    _ = try f.drain(f.session)
    _ = try f.move("-15")
    _ = try f.drain(f.session)
    let before = try f.book.committedHistory()
    try refuses("condition_cause_blocked") { _ = try f.dispatch() }
    try expect(try f.book.committedHistory() == before && f.book.workflowRuns().isEmpty)
    _ = try f.book.dismissInventoryConditionCandidate(
      first.text, reason: "Synthetic explicit investigation dismissal", token: "dismiss")
    try expect(try f.dispatch()["status"].text == "queued")
    _ = try f.book.verify()
  }
  check("distinct transitions dispatch in observation order beyond single-digit positions") {
    let f = try fixture("Order")
    for index in 0..<12 {
      _ = try f.move(index % 2 == 0 ? "-15" : "15")
      _ = try f.drain(f.session)
    }
    let pending = try f.book.db.execute(
      "SELECT c.id FROM condition_candidates c JOIN condition_observations o ON o.id=c.observation_id WHERE c.consumer_id=? ORDER BY o.rowid",
      [.string(try f.consumer)]
    ).map { $0["id"]! }
    for candidate in pending {
      let run = try f.dispatch()
      try expect(run["candidateID"] == candidate)
      try f.finish(run)
    }
    try expect(pending.count == 6 && f.book.workflowRuns().count == 6)
    _ = try f.book.verify()
  }
  check("manual work does not consume automatic candidates") {
    let f = try fixture("Manual")
    _ = try f.move("-15")
    _ = try f.drain(f.session)
    let manual = try f.book.startWorkflow(f.workflow.id, arguments: .object([:]), token: "manual")
    _ = try f.book.continueWorkflow(
      f.book.authorizeWorkflowExecution(manual["id"].text), owner: "manual")
    try expect(try f.book.inventoryCondition(f.consumer)["pendingCandidates"].int == 1)
    let automatic = try f.dispatch()
    try expect(automatic["runID"] != manual["id"])
    _ = try f.book.verify()
  }
  check("future effective observations remain pending without a run or root charge") {
    let f = try fixture("Future")
    _ = try f.move("-15")
    _ = try f.drain(f.session)
    let result = try f.book.dispatchInventoryCondition(
      f.session, observedAt: automationDate("2026-12-01T00:00:00Z"), token: "future")
    try expect(result["status"].text == "future" && f.book.workflowRuns().isEmpty)
    try expect(try f.book.db.scalar("SELECT count(*) FROM automatic_root_members").int == 0)
    _ = try f.book.verify()
  }
  check("late condition dispatch preserves trigger evidence separately from current workflow state")
  {
    let f = try fixture("Delayed")
    _ = try f.move("-15")
    _ = try f.drain(f.session)
    _ = try f.move("20")
    _ = try f.drain(f.session)
    let result = try f.dispatch()
    try expect(
      result["trigger"]["quantity"].text == "5"
        && f.book.balance(subject: "parts")["quantity"].text == "25")
    try expect(result["trigger"]["workflowReadCommitID"].string != nil)
    try f.finish(result)
    _ = try f.book.verify()
  }
  check("exact workflow version edits require a new grant but reuse the same owned rule queue") {
    let f = try fixture("Version")
    _ = try f.move("-15")
    _ = try f.drain(f.session)
    let next = try conditionAutomation(
      f.book, workflow: f.workflow, logicalID: f.definition.logicalID, base: f.definition.id)
    let session = try f.book.authorizeInventoryConditionExecution(
      next.id, expectedGeneration: 1, after: f.observed, token: "edited")
    try expect(try f.book.automationState(next.id)["consumer_id"].text == f.consumer)
    try refuses("automation_authority") { _ = try f.dispatch() }
    _ = try f.dispatch(session)
    _ = try f.book.verify()
  }
  check("a separate condition target inherits actual automatic causes without minting another root")
  {
    let f = try fixture("Inherited")
    _ = try f.move("-15")
    _ = try f.drain(f.session)
    let first = try f.dispatch()
    try f.finish(first)
    let second = try conditionAutomation(f.book, workflow: f.workflow)
    let session = try f.book.authorizeInventoryConditionExecution(
      second.id, expectedGeneration: 0,
      after: automationDate("2026-12-31T00:00:00Z"), token: "second")
    _ = try f.drain(session)
    let input = try f.book.workflowRun(first["runID"].text)["source_id"].text
    _ = try f.move("15", input: input)
    _ = try f.drain(session)
    _ = try f.move("-15", input: input)
    _ = try f.drain(session)
    let next = try f.dispatch(session)
    let origin = try f.book.automationCausality(next["runID"].text)
    try expect(
      origin["origin"]["parents"] == .array([first["runID"]]) && origin["origin"]["depth"].int == 2)
    try expect(
      origin["origin"]["independentInputs"].array.isEmpty
        && origin["rootCharges"].array[0]["admittedRuns"].int == 2)
    _ = try f.book.verify()
  }
  check("condition action drafts wait for human review and resume the same run after pause") {
    let f = try fixture("Review")
    let evidence = try f.book.recordBusinessObservation(title: "Supplier delivery evidence")
    let action = try f.book.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.receivingDefinition())
    let workflow = try f.book.saveApplicationDefinition(
      logicalID: identifier(), content: f.book.workflowTemplate(action.id))
    let definition = try conditionAutomation(
      f.book, workflow: workflow,
      arguments: .object([
        "delivery": .string("review-delivery"), "effective": .string("2026-02-02"),
        "evidence": .string(evidence.id),
        "lines": .array([
          .object(["line": .string("one"), "subject": .string("parts"), "quantity": .string("5")])
        ]),
      ]))
    let session = try f.book.authorizeInventoryConditionExecution(
      definition.id, expectedGeneration: 0,
      after: automationDate("2026-12-31T00:00:00Z"), token: "review-enable")
    _ = try f.drain(session)
    _ = try f.move("-15")
    _ = try f.drain(session)
    let result = try f.dispatch(session)
    let worker = try f.book.authorizeAutomationWorkflowExecution(
      session, runID: result["runID"].text)
    let waiting = try f.book.continueWorkflow(worker, owner: "review")
    try expect(
      waiting["state"].text == "waiting_review"
        && f.book.balance(subject: "parts")["quantity"].text == "5")
    try expect(try f.dispatch(session)["status"].text == "active")
    _ = try f.book.pauseAutomation(
      session.planning.activationID, expectedGeneration: 1, token: "review-pause")
    _ = try f.book.accept(
      waiting["steps"].array[0]["output"]["value"]["proposals"].array[0].text,
      actor: .human("synthetic reviewer"))
    try refuses("automation_authority") {
      _ = try f.book.continueWorkflow(worker, owner: "revoked")
    }
    let resumed = try f.book.authorizeInventoryConditionExecution(
      definition.id, expectedGeneration: 2,
      after: f.observed, token: "review-resume")
    try f.finish(result, session: resumed)
    try expect(
      try f.book.balance(subject: "parts")["quantity"].text == "10"
        && f.book.workflowRuns().count == 1)
    _ = try f.book.verify()
  }
  check("final device fence removal rolls back candidate, workflow and every shared charge") {
    let f = try fixture("Fence")
    _ = try f.move("-15")
    _ = try f.drain(f.session)
    let revoked = Cancellation()
    let session = AutomationExecutionSession(
      AutomationPlanningSession(
        f.book, activation: try f.book.deviceAutomationScope(f.session),
        deviceFence: { try revoked.check() }), allowAI: false)
    let before = try f.book.committedHistory()
    let observer: @Sendable (AutomationPublicationProbe.Stage, String) -> Void = { stage, _ in
      if stage == .prepared { revoked.cancel() }
    }
    try refuses("cancelled") {
      _ = try AutomationPublicationProbe.$observer.withValue(observer) { try f.dispatch(session) }
    }
    try expect(try f.book.committedHistory() == before && f.book.workflowRuns().isEmpty)
    try expect(try f.book.inventoryCondition(f.consumer)["pendingCandidates"].int == 1)
    try expect(try f.book.db.scalar("SELECT count(*) FROM automatic_root_members").int == 0)
    _ = try f.book.verify()
  }
  check("retained automatic invocation provenance cannot trigger its own logical condition again") {
    let f = try fixture("SelfLoop")
    _ = try f.move("-15")
    _ = try f.drain(f.session)
    let first = try f.dispatch()
    try f.finish(first)
    let run = try f.book.workflowRun(first["runID"].text)
    let resultID = run["source_id"].text
    try expect(!resultID.isEmpty)
    _ = try f.move("15", input: resultID)
    _ = try f.drain(f.session)
    _ = try f.move("-15", input: resultID)
    _ = try f.drain(f.session)
    let before = try f.book.committedHistory()
    try refuses("causal_self_trigger") { _ = try f.dispatch() }
    try expect(try f.book.committedHistory() == before && f.book.workflowRuns().count == 1)
    _ = try f.book.verify()
  }
  check("reconstruction retains actual bindings and charges without granting execution to a copy") {
    let f = try fixture("Copy")
    _ = try f.move("-15")
    _ = try f.drain(f.session)
    let result = try f.dispatch()
    let rebuilt = try f.book.reconstruct(
      to: directory.appendingPathComponent("ConditionRebuilt.sevra"))
    try expect(
      try rebuilt.automationRunBinding(result["runID"].text)
        == f.book.automationRunBinding(result["runID"].text))
    try expect(
      try rebuilt.automationCausality(result["runID"].text)
        == f.book.automationCausality(result["runID"].text))
    try refuses("automation_authority") {
      _ = try rebuilt.dispatchInventoryCondition(f.session, observedAt: f.observed, token: "copy")
    }
    _ = try rebuilt.verify()
    _ = try f.book.verify()
  }
}

func createConditionDispatchFixture(at url: URL, targets: Int = 1, admitted: Int = 0) throws
  -> Value
{
  let f = try ConditionDispatchFixture(url)
  var definitions = [f.definition]
  var sessions = [f.session]
  for _ in 1..<max(1, targets) {
    let definition = try conditionAutomation(f.book, workflow: f.workflow)
    let session = try f.book.authorizeInventoryConditionExecution(
      definition.id, expectedGeneration: 0,
      after: automationDate("2026-12-31T00:00:00Z"), token: "enable:" + definition.id)
    _ = try f.drain(session)
    definitions.append(definition)
    sessions.append(session)
  }
  let movement = try f.move("-15")
  for session in sessions { _ = try f.drain(session) }
  var runs: [Value] = []
  for session in sessions.prefix(admitted) { runs.append(try f.dispatch(session)) }
  _ = try f.book.verify()
  return .object([
    "sourceID": .string(
      try f.book.db.scalar(
        "SELECT parent FROM lineage WHERE child=? AND roles=1", [.string(movement.id)]
      ).text),
    "definitions": .array(definitions.map { .string($0.id) }),
    "remaining": .array(definitions.dropFirst(admitted).map { .string($0.id) }),
    "admitted": .array(runs), "observedAt": .string(try AutomationTime.text(f.observed)),
  ])
}

func conditionDispatchWorker(at url: URL, definition: String, stage: String? = nil) throws -> Value
{
  let book = try Workbook(url)
  let state = try book.automationState(definition)
  let session = try book.authorizeInventoryConditionExecution(
    definition,
    expectedGeneration: state["generation"].int!, after: automationDate("2027-01-01T00:00:00Z"),
    token: identifier())
  let observer: @Sendable (AutomationPublicationProbe.Stage, String) -> Void = { point, _ in
    if (point == .prepared && stage == "prepared") || (point == .committed && stage == "committed")
    {
      print(
        try! Value.object([
          "stage": .string(stage!),
          "headCommitID": book.db.scalar(
            "SELECT id FROM committed_changes ORDER BY rowid DESC LIMIT 1"),
          "operationSaved": book.db.scalar(
            "SELECT count(*) FROM operations WHERE id=?", [.string("dispatch:" + definition)]),
        ]).json())
      fflush(stdout)
      _ = readLine()
    }
  }
  return try AutomationPublicationProbe.$observer.withValue(
    observer,
    operation: {
      try book.dispatchInventoryCondition(
        session, observedAt: automationDate("2027-01-01T00:00:00Z"), token: "dispatch:" + definition
      )
    })
}
