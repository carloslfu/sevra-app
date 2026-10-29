import Foundation

@testable import SevraCore

func checkWorkflows(at root: URL) {
  func fixture(_ name: String, meaning: String = "actual") throws -> (
    Workbook, ApplicationDefinition, Value
  ) {
    let b = try Workbook.create(
      at: root.appendingPathComponent("Workflow-" + name + ".sevra"), title: name)
    let source = try b.addItem(
      category: "source", kind: "observation", title: "Synthetic receipt", status: "accepted")
    try b.setOpeningBalance(
      subject: "bolts", quantity: "20", effective: "2026-01-01", sourceID: source.id)
    let f = try b.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("function"), "title": .string("Double items"),
        "description": .string("Synthetic"),
        "parameters": .array([
          ActionRegistry.field("quantity", "Quantity", "decimal", unit: "items")
        ]),
        "payload": .object(["expression": .string("quantity*2"), "unit": .string("items")]),
      ]))
    let action = try b.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("action"), "title": .string("Propose movement"),
        "description": .string("Synthetic"),
        "parameters": .array(ActionRegistry.movementParameters),
        "payload": .object([
          "primitive": .object(["id": .string(ActionRegistry.movementID), "version": .number(1)]),
          "arguments": .object(
            Dictionary(
              uniqueKeysWithValues: ActionRegistry.movementParameters.map {
                ($0["id"].text, .object(["parameter": $0["id"]]))
              })),
        ]),
      ]))
    var actionMappings = Dictionary(
      uniqueKeysWithValues: ActionRegistry.movementParameters.map {
        ($0["id"].text, Value.object(["parameter": $0["id"]]))
      })
    actionMappings["quantity"] = .object(["step": .string("double"), "unit": .string("items")])
    let content: Value = .object([
      "kind": .string("workflow"), "title": .string("Count then propose"),
      "description": .string("Manual synthetic workflow"),
      "parameters": .array(ActionRegistry.movementParameters),
      "payload": .object([
        "readPolicy": .string("latest-at-step"),
        "steps": .array([
          .object([
            "id": .string("double"), "kind": .string("evaluate"),
            "binding": .object(["mode": .string("exact"), "versionID": .string(f.id)]),
            "arguments": .object(["quantity": .object(["parameter": .string("quantity")])]),
          ]),
          .object([
            "id": .string("propose"), "kind": .string("action"),
            "binding": .object(["mode": .string("exact"), "versionID": .string(action.id)]),
            "arguments": .object(actionMappings),
          ]),
          .object([
            "id": .string("review"), "kind": .string("review"), "review": .string("propose"),
          ]),
        ]),
      ]),
    ])
    let workflow = try b.saveApplicationDefinition(logicalID: identifier(), content: content)
    let args: Value = .object([
      "quantity": .string("3"), "subject": .string("bolts"),
      "occurrence": .string("delivery-" + name),
      "effective": .string("2026-10-28"), "evidence": .string(source.id),
      "meaning": .string(meaning),
    ])
    return (b, workflow, args)
  }
  func start(_ b: Workbook, _ definition: ApplicationDefinition, _ args: Value) throws
    -> WorkflowExecutionSession
  {
    let run = try b.startWorkflow(definition.id, arguments: args, token: "start")
    return try b.authorizeWorkflowExecution(run["id"].text)
  }
  func draft(_ run: Value) -> String {
    run["steps"].array[1]["output"]["value"]["proposals"].array[0].text
  }

  check("manual workflows retain exact outputs, wait for review and apply inventory once") {
    let (b, definition, args) = try fixture("Receiving")
    let session = try start(b, definition, args)
    let initial = try b.workflowRun(session.runID)
    try expect(
      try b.startWorkflow(definition.id, arguments: args, token: "start")["id"] == initial["id"])
    let first = try b.advanceWorkflow(session, owner: "worker")
    try expect(first["steps"].array[0]["output"]["value"]["result"] == .string("6"))
    let second = try b.advanceWorkflow(session, owner: "worker")
    let proposal = draft(second)
    try expect(try b.item(proposal).data["quantity"] == .string("6"))
    let waiting = try b.advanceWorkflow(session, owner: "worker")
    try expect(waiting["state"] == .string("waiting_review"))
    for _ in 0..<35 {
      try expect(try b.advanceWorkflow(session, owner: "checking-review") == waiting)
    }
    try expect(
      try b.db.scalar(
        "SELECT count(*) FROM workflow_attempts WHERE run_id=? AND step_id='review'",
        [.string(session.runID)]
      ).int == 1)
    try expect(try b.balance(subject: "bolts")["quantity"] == .string("20"))
    let other = try Workbook(b.url)
    let accepted = try other.accept(proposal, actor: .human("test-review"))
    let completed = try b.advanceWorkflow(session, owner: "resumed-worker")
    try expect(completed["state"] == .string("completed"))
    try expect(
      completed["steps"].array[2]["output"]["value"]["accepted"] == .array([.string(accepted.id)]))
    try expect(try b.balance(subject: "bolts")["quantity"] == .string("26"))
    try expect(try b.advanceWorkflow(session, owner: "again")["state"] == .string("completed"))
    try expect(try b.balance(subject: "bolts")["quantity"] == .string("26"))
    _ = try b.verify()
  }

  check(
    "expired and replaced workflow claims cannot publish; exact completion retries remain inert"
  ) {
    let (b, definition, args) = try fixture("Lease")
    let session = try start(b, definition, args)
    let first = try b.claimWorkflowStep(session, owner: "slow", leaseSeconds: 1)
    try refuses("workflow_busy") { _ = try b.claimWorkflowStep(session, owner: "other") }
    Thread.sleep(forTimeInterval: 1.1)
    try refuses("workflow_fenced") { _ = try b.completeWorkflowStep(session, claim: first) }
    let next = try b.claimWorkflowStep(session, owner: "replacement")
    try expect(next["generation"].int == 2)
    try refuses("workflow_fenced") { _ = try b.heartbeatWorkflowStep(session, claim: first) }
    try refuses("workflow_fenced") { _ = try b.completeWorkflowStep(session, claim: first) }
    let done = try b.completeWorkflowStep(session, claim: next)
    let history = try b.committedHistory(limit: 1000)
    try expect(try b.completeWorkflowStep(session, claim: next) == done)
    try expect(try b.committedHistory(limit: 1000) == history)
    _ = try b.verify()
  }

  check("a lease expiring during checkpoint capture rolls back its completed output") {
    let (b, definition, args) = try fixture("CommitLease")
    let session = try start(b, definition, args)
    let claim = try b.claimWorkflowStep(session, owner: "slow-commit", leaseSeconds: 0.25)
    let history = try b.committedHistory(limit: 1000)
    try refuses("workflow_fenced") {
      _ = try WorkflowPublicationProbe.$observer.withValue({ stage, _ in
        if stage == .prepared { Thread.sleep(forTimeInterval: 0.35) }
      }) { try b.completeWorkflowStep(session, claim: claim) }
    }
    try expect(try b.committedHistory(limit: 1000) == history)
    try expect(try b.workflowRun(session.runID)["steps"].array[0]["output"] == .null)
    let replacement = try b.claimWorkflowStep(session, owner: "fast")
    _ = try b.completeWorkflowStep(session, claim: replacement)
    _ = try b.verify()
  }

  check("workflow faults roll back draft effects, step output and outbox before safe retry") {
    let (b, definition, args) = try fixture("Atomic")
    let session = try start(b, definition, args)
    _ = try b.advanceWorkflow(session, owner: "worker")
    let claim = try b.claimWorkflowStep(session, owner: "worker")
    let before = try b.committedHistory(limit: 1000)
    try b.db.execute(
      "CREATE TEMP TRIGGER workflow_fault BEFORE INSERT ON main.workflow_outbox WHEN NEW.kind='completed' BEGIN SELECT RAISE(ABORT,'workflow_fault'); END"
    )
    try refuses { _ = try b.completeWorkflowStep(session, claim: claim) }
    try b.db.execute("DROP TRIGGER workflow_fault")
    try expect(try b.committedHistory(limit: 1000) == before)
    try expect(try b.db.scalar("SELECT count(*) FROM effects").int == 0)
    try expect(try b.workflowRun(session.runID)["steps"].array[1]["output"] == .null)
    let saved = try b.completeWorkflowStep(session, claim: claim)
    try expect(!draft(saved).isEmpty)
    try expect(try b.db.scalar("SELECT count(*) FROM effects").int == 1)
    _ = try b.verify()
  }

  check("workflow acceptance preserves estimates; copied definitions do not turn them into actuals")
  {
    let (b, definition, args) = try fixture("Estimate", meaning: "estimate")
    let session = try start(b, definition, args)
    _ = try b.advanceWorkflow(session, owner: "worker")
    let proposed = try b.advanceWorkflow(session, owner: "worker")
    let accepted = try b.accept(draft(proposed), actor: .human("test-review"))
    try expect(accepted.meaning == "estimate")
    try expect(try b.advanceWorkflow(session, owner: "worker")["state"] == .string("completed"))
    try expect(try b.balance(subject: "bolts")["quantity"] == .string("20"))
    _ = try b.verify()
  }

  check("changed workflow proposals require attention and cancellation preserves committed work") {
    let (b, definition, args) = try fixture("Changed")
    let session = try start(b, definition, args)
    _ = try b.advanceWorkflow(session, owner: "worker")
    let proposed = try b.advanceWorkflow(session, owner: "worker")
    let old = try b.item(draft(proposed))
    _ = try b.addItem(
      category: old.category, kind: old.kind, title: old.title, text: "Changed proposal",
      data: old.data, meaning: old.meaning, inputs: [old.id], supersedes: old.id)
    try refuses("workflow_stale_review") { _ = try b.advanceWorkflow(session, owner: "worker") }
    try expect(try b.workflowRun(session.runID)["state"] == .string("needs_attention"))
    _ = try b.retryWorkflow(session, token: "retry")
    try refuses("workflow_stale_review") { _ = try b.advanceWorkflow(session, owner: "worker") }
    let cancelled = try b.cancelWorkflow(session, token: "cancel")
    try expect(
      cancelled["state"] == .string("cancelled")
        && cancelled["steps"].array[0]["state"] == .string("completed"))
    try expect(try b.item(old.id).status == "draft")
    _ = try b.verify()
  }

  check(
    "workflow reconstruction and archives preserve claims and outputs without execution authority"
  ) {
    let (b, definition, args) = try fixture("Replay")
    let session = try start(b, definition, args)
    _ = try b.advanceWorkflow(session, owner: "worker")
    let claim = try b.claimWorkflowStep(session, owner: "interrupted")
    let saved = try b.workflowRun(session.runID)
    let copy = try b.reconstruct(to: root.appendingPathComponent("Workflow-replayed.sevra"))
    try expect(try copy.workflowRun(session.runID) == saved)
    try refuses("workflow_authority") { _ = try copy.completeWorkflowStep(session, claim: claim) }
    try expect(try copy.db.scalar("SELECT count(*) FROM effects").int == 0)
    let archive = root.appendingPathComponent("Workflow.sevraz")
    try b.export(to: archive)
    let portable = try Workbook.openArchive(
      archive, at: root.appendingPathComponent("Workflow-portable.sevra"))
    try expect(try portable.workflowRun(session.runID) == saved)
    try expect(try portable.committedHistory(limit: 1000) == b.committedHistory(limit: 1000))
    _ = try portable.verify()
  }

  check(
    "workflow queue writes preserve data read snapshots and cancellation fences a current claim"
  ) {
    let (b, definition, args) = try fixture("Cancellation")
    let session = try start(b, definition, args)
    let before = try b.datasetReadSnapshot()
    let claim = try b.claimWorkflowStep(session, owner: "cancelled-worker")
    _ = try b.heartbeatWorkflowStep(session, claim: claim)
    try expect(try b.datasetReadSnapshot() == before)
    _ = try b.cancelWorkflow(session, token: "cancel")
    try refuses("workflow_fenced") { _ = try b.completeWorkflowStep(session, claim: claim) }
    try expect(try b.datasetReadSnapshot() == before)
    let first = try b.workflowEvents(limit: 1)
    try expect(first["hasMore"] == .bool(true))
    let next = try b.workflowEvents(after: first["after"].int!, limit: 1)
    try expect(next["events"].array.count == 1 && next["after"] != first["after"])
    _ = try b.verify()
  }

  check("explicit workflow retry renews a bounded attempt budget without resetting fencing history")
  {
    let (b, definition, args) = try fixture("RetryBudget")
    let session = try start(b, definition, args)
    for index in 1...32 {
      let claim = try b.claimWorkflowStep(session, owner: "interrupted", leaseSeconds: 0.05)
      try expect(claim["generation"].int == index)
      Thread.sleep(forTimeInterval: 0.06)
    }
    try refuses("workflow_retry_limit") {
      _ = try b.claimWorkflowStep(session, owner: "over-budget")
    }
    let paused = try b.workflowRun(session.runID)
    try expect(paused["state"] == .string("needs_attention"))
    try expect(paused["steps"].array[0]["output"] == .null)
    _ = try b.verify()
    _ = try b.retryWorkflow(session, token: "explicit-new-budget")
    let resumed = try b.claimWorkflowStep(session, owner: "resumed")
    try expect(resumed["generation"].int == 33)
    _ = try b.completeWorkflowStep(session, claim: resumed)
    let reconstructed = try b.reconstruct(
      to: root.appendingPathComponent("Workflow-retry-budget.sevra"))
    try expect(try reconstructed.workflowRun(session.runID) == b.workflowRun(session.runID))
    _ = try reconstructed.verify()
  }

  check("workflow queries capture latest step inputs and refuse incomplete pages") {
    let (b, _, _) = try fixture("Query")
    let evidence = try b.addItem(
      category: "source", kind: "observation", title: "Synthetic query inputs")
    let table = try b.createDataset(
      title: "Counts",
      columns: [.init(id: "quantity", title: "Quantity", type: "decimal", unit: "items")],
      rows: [["quantity": .string("2")], ["quantity": .string("5")]], sourceID: evidence.id)
    func queryWorkflow(limit: Int) throws -> ApplicationDefinition {
      let query = try b.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("query"), "title": .string("Current counts"),
          "description": .string("Synthetic"), "parameters": .array([]),
          "payload": .object([
            "dataMode": .string("exact"),
            "query": .object([
              "sources": .array([
                .object([
                  "datasetID": .string(table.id), "definitionID": .string(table.definitionID),
                ])
              ]),
              "select": .array([
                .object([
                  "id": .string("quantity"),
                  "column": .object(["source": .number(0), "column": .string("quantity")]),
                ])
              ]),
              "limit": .number(Double(limit)),
            ]),
          ]),
        ]))
      return try b.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("workflow"), "title": .string("Query workflow"),
          "description": .string("Synthetic"), "parameters": .array([]),
          "payload": .object([
            "readPolicy": .string("latest-at-step"),
            "steps": .array([
              .object([
                "id": .string("counts"), "kind": .string("evaluate"),
                "binding": .object(["mode": .string("exact"), "versionID": .string(query.id)]),
                "arguments": .object([:]),
              ])
            ]),
          ]),
        ]))
    }
    let complete = try queryWorkflow(limit: 10)
    let session = try start(b, complete, .object([:]))
    let row = try b.rows(table.id)[0]
    _ = try b.editRows(table.id, edits: [.init(id: row.id, values: ["quantity": .string("8")])])
    let result = try b.advanceWorkflow(session, owner: "query-worker")
    let evaluation = result["steps"].array[0]["output"]["value"]
    try expect(result["state"] == .string("completed"))
    try expect(evaluation["result"]["rows"].array[0]["values"]["quantity"] == .string("8"))
    let population = evaluation["inputPopulation"].array[0]["rows"].array
    try expect(population.count == 2 && !population.contains { $0["versionID"] == .string(row.id) })
    let partial = try queryWorkflow(limit: 1)
    let run = try b.startWorkflow(partial.id, arguments: .object([:]), token: "partial")
    let partialSession = try b.authorizeWorkflowExecution(run["id"].text)
    try refuses("workflow_partial") {
      _ = try b.advanceWorkflow(partialSession, owner: "partial-worker")
    }
    let refused = try b.workflowRun(partialSession.runID)
    try expect(
      refused["state"] == .string("needs_attention") && refused["steps"].array[0]["output"] == .null
    )
    _ = try b.verify()
  }

  check(
    "workflow bindings reject live closure, forward results, unsupported steps and read-only invocation"
  ) {
    let (b, definition, args) = try fixture("Refusals")
    try refuses("read_only_request") {
      _ = try b.startWorkflow(definition.id, arguments: args, token: "read", readOnly: true)
    }
    var content = definition.content.object
    var payload = content["payload"]!.object
    var steps = payload["steps"]!.array
    var first = steps[0].object
    first["kind"] = .string("shell")
    steps[0] = .object(first)
    payload["steps"] = .array(steps)
    content["payload"] = .object(payload)
    try refuses("workflow_definition") {
      _ = try b.saveApplicationDefinition(logicalID: identifier(), content: .object(content))
    }
    first = definition.payload["steps"].array[0].object
    let target = try b.applicationDefinition(first["binding"]!["versionID"].text)
    first["binding"] = .object(["mode": .string("live"), "logicalID": .string(target.logicalID)])
    steps = definition.payload["steps"].array
    steps[0] = .object(first)
    payload["steps"] = .array(steps)
    content["payload"] = .object(payload)
    try refuses("workflow_binding") {
      _ = try b.saveApplicationDefinition(logicalID: identifier(), content: .object(content))
    }
    first = definition.payload["steps"].array[0].object
    first["arguments"] = .object([
      "quantity": .object(["step": .string("propose"), "unit": .string("items")])
    ])
    steps[0] = .object(first)
    payload["steps"] = .array(steps)
    content["payload"] = .object(payload)
    try refuses("workflow_mapping") {
      _ = try b.saveApplicationDefinition(logicalID: identifier(), content: .object(content))
    }
    try expect(try b.workflowRuns().isEmpty)
    _ = try b.verify()
  }
}
