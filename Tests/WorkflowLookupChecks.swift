import Foundation

@testable import SevraCore

func checkWorkflowLookups(at root: URL) {
  func fixture(
    _ name: String, codes: [String] = ["0012"], calculation: Bool = false, limit: Int = 10
  ) throws -> (Workbook, Dataset, ApplicationDefinition, ApplicationDefinition, Value) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Lookup-" + name + ".sevra"), title: name)
    let evidence = try book.addItem(
      category: "source", kind: "observation", title: "Delivery", text: "Received 2 bolts.",
      status: "accepted")
    try book.setOpeningBalance(
      subject: "bolts", quantity: "20", effective: "2026-10-01", sourceID: evidence.id)
    let table = try book.createDataset(
      title: "Catalog",
      columns: [
        .init(id: "code", title: "Supplier code"), .init(id: "subject", title: "Stock subject"),
        .init(id: "count", title: "Count", type: "decimal", unit: "items"),
        .init(id: "enabled", title: "Enabled", type: "boolean"),
      ],
      rows: codes.map {
        [
          "code": .string($0), "subject": .string("bolts"), "count": .string("2"),
          "enabled": .bool(false),
        ]
      }, sourceID: evidence.id)
    let query = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("query"), "title": .string("Match supplier code"),
        "description": .string("Explicit exact catalog lookup"),
        "parameters": .array([ActionRegistry.field("code", "Supplier code", "text")]),
        "payload": .object([
          "dataMode": .string("exact"),
          "query": .object([
            "sources": .array([
              .object(["datasetID": .string(table.id), "definitionID": .string(table.definitionID)])
            ]),
            "select": .array(
              ["subject", "count", "enabled"].map {
                .object([
                  "id": .string($0),
                  "column": .object(["source": .number(0), "column": .string($0)]),
                ])
              }),
            "filters": .array([
              .object([
                "column": .object(["source": .number(0), "column": .string("code")]),
                "op": .string("eq"), "value": .object(["parameter": .string("code")]),
              ])
            ]), "limit": .number(Double(limit)),
          ]),
        ]),
      ]))
    let action = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("action"), "title": .string("Receive matched product"),
        "description": .string("Draft only"),
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
    func field(_ name: String, unit: String? = nil) -> Value {
      var m: [String: Value] = ["step": .string("match"), "field": .string(name)]
      if let unit { m["unit"] = .string(unit) }
      return .object(m)
    }
    var steps: [Value] = [
      .object([
        "id": .string("match"), "kind": .string("evaluate"),
        "binding": .object(["mode": .string("exact"), "versionID": .string(query.id)]),
        "arguments": .object(["code": .object(["parameter": .string("code")])]),
      ])
    ]
    if calculation {
      let function = try book.saveApplicationDefinition(
        logicalID: identifier(),
        content: .object([
          "kind": .string("function"), "title": .string("Checked quantity"),
          "description": .string("Synthetic scalar counterexample"),
          "parameters": .array([
            ActionRegistry.field("quantity", "Quantity", "decimal", unit: "items"),
            ActionRegistry.field("flag", "Flag", "boolean"),
          ]),
          "payload": .object([
            "expression": .string("IF(flag,quantity*2,quantity)"), "unit": .string("items"),
          ]),
        ]))
      steps.append(
        .object([
          "id": .string("calculate"), "kind": .string("evaluate"),
          "binding": .object(["mode": .string("exact"), "versionID": .string(function.id)]),
          "arguments": .object([
            "quantity": field("count", unit: "items"), "flag": field("enabled"),
          ]),
        ]))
    }
    steps.append(
      .object([
        "id": .string("propose"), "kind": .string("action"),
        "binding": .object(["mode": .string("exact"), "versionID": .string(action.id)]),
        "arguments": .object([
          "subject": field("subject"),
          "quantity": calculation
            ? .object(["step": .string("calculate"), "unit": .string("items")])
            : .object(["literal": .string("2"), "unit": .string("items")]),
          "occurrence": .object(["literal": .string("delivery-" + name)]),
          "effective": .object(["literal": .string("2026-10-29")]),
          "evidence": .object(["parameter": .string("evidence")]),
          "meaning": .object(["literal": .string("actual")]),
        ]),
      ]))
    steps.append(
      .object(["id": .string("review"), "kind": .string("review"), "review": .string("propose")]))
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("workflow"), "title": .string("Receive by supplier code"),
        "description": .string("Explicit catalog lookup and review"),
        "parameters": .array([
          ActionRegistry.field("code", "Supplier code", "text"),
          ActionRegistry.field("evidence", "Evidence", "item"),
        ]),
        "payload": .object(["readPolicy": .string("latest-at-step"), "steps": .array(steps)]),
      ]))
    return (
      book, table, query, workflow,
      .object(["code": .string("0012"), "evidence": .string(evidence.id)])
    )
  }
  func start(_ book: Workbook, _ workflow: ApplicationDefinition, _ args: Value) throws
    -> WorkflowExecutionSession
  {
    let run = try book.startWorkflow(workflow.id, arguments: args, token: "start")
    return try book.authorizeWorkflowExecution(run["id"].text)
  }
  check(
    "workflow lookup selects one exact product, retains lineage and reviews its stock effect once"
  ) {
    let (book, table, query, workflow, args) = try fixture("Matched")
    let row = try book.rows(table.id)[0]
    let session = try start(book, workflow, args)
    let claim = try book.claimWorkflowStep(session, owner: "lookup")
    let matched = try book.completeWorkflowStep(session, claim: claim)
    try expect(try book.completeWorkflowStep(session, claim: claim) == matched)
    _ = try book.editRows(
      table.id,
      edits: [
        .init(
          id: row.id,
          values: row.data.object.merging(["subject": .string("nuts")]) { _, fresh in fresh })
      ])
    let waiting = try book.continueWorkflow(session, owner: "receive")
    try expect(waiting["state"] == .string("waiting_review"))
    let action = waiting["steps"].array[1]["output"]["value"]
    let parents = try book.lineage(action["sourceID"].text).map { $0["parent"].text }
    try expect(parents.contains(row.id) && parents.contains(query.sourceID))
    try expectInputRole(book, child: action["sourceID"].text, parent: row.id, roles: 1)
    try expectInputRole(book, child: action["sourceID"].text, parent: query.sourceID, roles: 2)
    try expectInputRole(
      book, child: action["sourceID"].text,
      parent: book.datasetDefinition(table.id).sourceID, roles: 2)
    try expectInputRole(
      book, child: action["sourceID"].text,
      parent: book.workflowRun(session.runID)["source_id"].text, roles: 4)
    try expect(try book.balance(subject: "bolts")["quantity"] == .string("20"))
    _ = try book.accept(action["proposals"].array[0].text, actor: .human("test-review"))
    let done = try book.continueWorkflow(session, owner: "finish")
    try expect(done["state"] == .string("completed"))
    try expect(try book.balance(subject: "bolts")["quantity"] == .string("22"))
    let copy = try book.reconstruct(to: root.appendingPathComponent("Lookup-MatchedCopy.sevra"))
    try expect(try copy.workflowRun(session.runID) == done)
    try expect(try copy.balance(subject: "bolts")["quantity"] == .string("22"))
    try expect(try book.verify()["ok"] == .bool(true) && copy.verify()["ok"] == .bool(true))
  }
  check("selected catalog values retain data provenance through an intervening scalar function") {
    let (book, table, query, workflow, args) = try fixture("ScalarRoles", calculation: true)
    let row = try book.rows(table.id)[0]
    let session = try start(book, workflow, args)
    let waiting = try book.continueWorkflow(session, owner: "scalar-roles")
    try expect(waiting["state"] == .string("waiting_review"))
    let action = waiting["steps"].array[2]["output"]["value"]
    let calculation = waiting["steps"].array[1]["output"]["value"]
    try expectInputRole(book, child: action["sourceID"].text, parent: row.id, roles: 1)
    try expectInputRole(book, child: action["sourceID"].text, parent: query.sourceID, roles: 2)
    try expectInputRole(
      book, child: action["sourceID"].text,
      parent: book.applicationDefinition(calculation["definitionID"].text).sourceID, roles: 2)
    let proposal = try book.item(action["proposals"].array[0].text)
    try expect(proposal.data["quantity"] == .string("2"))
    try expectInputRole(book, child: proposal.id, parent: action["sourceID"].text, roles: 4)
    _ = try book.verify()
  }
  check("lookup checkpoint faults and cancellation preserve history before exact retry") {
    let (book, _, _, workflow, args) = try fixture("Checkpoint")
    let session = try start(book, workflow, args)
    let claim = try book.claimWorkflowStep(session, owner: "lookup")
    let before = try book.workflowRun(session.runID)
    let history = try book.committedHistory(limit: 1000)
    try book.db.execute(
      "CREATE TEMP TRIGGER lookup_fault BEFORE INSERT ON workflow_outbox WHEN NEW.kind='completed' BEGIN SELECT RAISE(ABORT,'lookup_fault'); END"
    )
    try refuses("database") { _ = try book.completeWorkflowStep(session, claim: claim) }
    try book.db.execute("DROP TRIGGER lookup_fault")
    try expect(try book.workflowRun(session.runID) == before)
    try expect(try book.committedHistory(limit: 1000) == history)
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses("cancelled") {
      _ = try book.completeWorkflowStep(session, claim: claim, cancellation: cancelled)
    }
    try expect(try book.workflowRun(session.runID) == before)
    try expect(try book.committedHistory(limit: 1000) == history)
    let saved = try book.completeWorkflowStep(session, claim: claim)
    try expect(try book.completeWorkflowStep(session, claim: claim) == saved)
    try expect(saved["steps"].array[0]["output"]["value"]["result"]["rows"].array.count == 1)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check(
    "zero or duplicate product matches pause before publication and explicit catalog repair resumes the same run"
  ) {
    for (name, codes, limit) in [
      ("Missing", ["other"], 10), ("Duplicate", ["0012", "0012"], 10),
      ("Paged", ["0012", "0012"], 1),
    ] {
      let (book, table, _, workflow, args) = try fixture(name, codes: codes, limit: limit)
      let session = try start(book, workflow, args)
      try refuses(limit == 1 ? "workflow_partial" : "workflow_lookup") {
        _ = try book.advanceWorkflow(session, owner: "lookup")
      }
      let failed = try book.workflowRun(session.runID)
      try expect(
        failed["state"] == .string("needs_attention") && failed["steps"].array[0]["output"] == .null
      )
      try expect(try book.items().filter { $0.kind == "movement" }.isEmpty)
      let rows = try book.rows(table.id)
      _ = try book.editRows(
        table.id,
        edits: rows.enumerated().map { index, row in
          .init(
            id: row.id,
            values: row.data.object.merging([
              "code": .string(index == 0 ? "0012" : "other")
            ]) { _, fresh in fresh })
        })
      _ = try book.retryWorkflow(session, token: "repaired")
      let waiting = try book.continueWorkflow(session, owner: "repaired")
      try expect(waiting["state"] == .string("waiting_review"))
      try expect(waiting["steps"].array[0]["output"]["value"]["result"]["rows"].array.count == 1)
      try expect(try book.balance(subject: "bolts")["quantity"] == .string("20"))
      try expect(try book.verify()["ok"] == .bool(true))
    }
  }
  check(
    "lookup meanings survive calculations and cannot promote estimates or other scenarios into actual stock"
  ) {
    for (name, meaning, scenario) in [
      ("Estimate", "estimate", "actual"), ("Scenario", "actual", "planned"),
    ] {
      let (book, table, _, workflow, args) = try fixture(name, calculation: true)
      let old = try book.rows(table.id)[0]
      let row = try book.addItem(
        category: "record", kind: "row", title: old.title, data: old.data,
        meaning: meaning, status: "accepted", scenario: scenario, inputs: [old.id],
        supersedes: old.id)
      let session = try start(book, workflow, args)
      _ = try book.advanceWorkflow(session, owner: "lookup")
      _ = try book.advanceWorkflow(session, owner: "calculate")
      try refuses("interpretation_meaning") {
        _ = try book.advanceWorkflow(session, owner: "action")
      }
      try expect(try book.items().filter { $0.kind == "movement" }.isEmpty)
      try expect(try book.balance(subject: "bolts")["quantity"] == .string("20"))
      try expect(
        try book.workflowRun(session.runID)["steps"].array[0]["output"]["value"]["result"]["rows"]
          .array[0]["inputs"].array[0]["versionID"] == .string(row.id))
      try expect(try book.verify()["ok"] == .bool(true))
    }
  }
  check(
    "lookup unknown and empty fields refuse before checkpoint while false and zero remain values"
  ) {
    for (name, value) in [("Null", Value.null), ("Empty", Value.string(" "))] {
      let (book, table, _, workflow, args) = try fixture(name)
      let row = try book.rows(table.id)[0]
      _ = try book.editRows(
        table.id,
        edits: [
          .init(
            id: row.id, values: row.data.object.merging(["subject": value]) { _, fresh in fresh })
        ])
      let session = try start(book, workflow, args)
      try refuses("workflow_lookup") { _ = try book.advanceWorkflow(session, owner: "lookup") }
      try expect(try book.workflowRun(session.runID)["steps"].array[0]["output"] == .null)
      try expect(try book.verify()["ok"] == .bool(true))
    }
    let (book, table, _, workflow, args) = try fixture("ZeroFalse", calculation: true)
    let row = try book.rows(table.id)[0]
    _ = try book.editRows(
      table.id,
      edits: [
        .init(
          id: row.id, values: row.data.object.merging(["count": .string("0")]) { _, fresh in fresh }
        )
      ])
    var content = workflow.content.object
    content["payload"] = .object([
      "readPolicy": .string("latest-at-step"),
      "steps": .array(Array(workflow.payload["steps"].array.prefix(2))),
    ])
    let pure = try book.saveApplicationDefinition(
      logicalID: identifier(), content: .object(content))
    let session = try start(book, pure, args)
    let done = try book.continueWorkflow(session, owner: "pure")
    try expect(done["state"] == .string("completed"))
    try expect(done["steps"].array[1]["output"]["value"]["result"] == .string("0"))
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check(
    "lookup definitions refuse unknown fields, implicit type conversion, joins and aggregate identities"
  ) {
    let (book, table, query, workflow, _) = try fixture("Definitions")
    func replaceQuery(_ id: String) -> Value {
      var content = workflow.content.object
      var steps = workflow.payload["steps"].array
      var first = steps[0].object
      first["binding"] = .object(["mode": .string("exact"), "versionID": .string(id)])
      steps[0] = .object(first)
      content["payload"] = .object([
        "readPolicy": .string("latest-at-step"), "steps": .array(steps),
      ])
      return .object(content)
    }
    for (field, error) in [
      ("missing", "workflow_lookup"), ("count", "workflow_mapping"),
      ("enabled", "workflow_mapping"),
    ] {
      var content = workflow.content.object
      var steps = workflow.payload["steps"].array
      var action = steps[1].object
      var args = action["arguments"]!.object
      args["subject"] = .object(["step": .string("match"), "field": .string(field)])
      action["arguments"] = .object(args)
      steps[1] = .object(action)
      content["payload"] = .object([
        "readPolicy": .string("latest-at-step"), "steps": .array(steps),
      ])
      let revision = try book.revision()
      try refuses(error) {
        _ = try book.saveApplicationDefinition(logicalID: identifier(), content: .object(content))
      }
      try expect(try book.revision() == revision)
    }
    for join in [false, true] {
      var content = query.content.object
      var raw = query.payload["query"].object
      if join {
        raw["sources"] = .array(
          raw["sources"]!.array + [
            .object(["datasetID": .string(table.id), "definitionID": .string(table.definitionID)])
          ])
        raw["joins"] = .array([
          .object([
            "kind": .string("inner"),
            "left": .object(["source": .number(0), "column": .string("code")]),
            "right": .string("code"),
          ])
        ])
      } else {
        raw["select"] = .array([
          .object(["id": .string("subject"), "aggregate": .string("countRows")])
        ])
      }
      content["payload"] = .object(["dataMode": .string("exact"), "query": .object(raw)])
      let unsupported = try book.saveApplicationDefinition(
        logicalID: identifier(), content: .object(content))
      let revision = try book.revision()
      try refuses("workflow_lookup") {
        _ = try book.saveApplicationDefinition(
          logicalID: identifier(), content: replaceQuery(unsupported.id))
      }
      try expect(try book.revision() == revision)
    }
    try expect(try book.workflowRuns().isEmpty && book.verify()["ok"] == .bool(true))
  }
}
