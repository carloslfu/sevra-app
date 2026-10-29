import Foundation

@testable import SevraCore

func createAutomaticAncestryFixture(at url: URL) throws -> Value {
  let book = try Workbook.create(at: url, title: "Synthetic automatic ancestry")
  let source = try book.addItem(
    category: "source", kind: "observation", title: "Synthetic delivery", status: "accepted")
  let action = try book.saveApplicationDefinition(
    logicalID: identifier(), content: ActionRegistry.receivingDefinition())
  let workflow = try book.saveApplicationDefinition(
    logicalID: identifier(), content: book.workflowTemplate(action.id))
  let arguments: Value = .object([
    "delivery": .string("ancestry-delivery"), "effective": .string("2026-10-01"),
    "evidence": .string(source.id),
    "lines": .array([
      .object(["line": .string("one"), "subject": .string("parts"), "quantity": .string("5")])
    ]),
  ])
  let automation = try executionAutomation(book, workflow: workflow, arguments: arguments)
  let session = try book.authorizeAutomationExecution(
    automation.id, expectedGeneration: 0, after: automationDate("2026-10-01T08:00:00Z"),
    token: "authorize")
  let due = automationDate("2026-10-01T09:00:00Z")
  _ = try book.planAutomationOccurrences(session.planning, through: due, token: "plan")
  let runID = try book.dispatchAutomationOccurrence(
    session, observedAt: due, token: "dispatch")["runID"].text
  let worker = try book.authorizeAutomationWorkflowExecution(session, runID: runID)
  let waiting = try book.continueWorkflow(worker, owner: "ancestry-fixture")
  let proposal = waiting["steps"].array[0]["output"]["value"]["proposals"].array[0].text
  let accepted = try book.accept(proposal, actor: .human("synthetic reviewer"))
  return .object([
    "path": .string(url.path), "sourceID": .string(source.id),
    "automationID": .string(automation.id), "automationLogicalID": .string(automation.logicalID),
    "workflowID": .string(workflow.id), "arguments": arguments,
    "runID": .string(runID), "invocationID": try book.workflowRun(runID)["source_id"],
    "proposalID": .string(proposal), "acceptedID": .string(accepted.id),
  ])
}

func checkAutomaticAncestry(at root: URL) {
  func fixture(_ name: String) throws -> (Workbook, Value) {
    let url = root.appendingPathComponent("AutomaticAncestry-" + name + ".sevra")
    let data = try createAutomaticAncestryFixture(at: url)
    return (try Workbook(url), data)
  }
  func independent(_ book: Workbook, _ title: String, inputs: [String] = []) throws -> String {
    try ChangeAttribution.$actor.withValue(.human("test")) {
      try book.addItem(
        category: "source", kind: "observation", title: title, inputs: inputs
      ).id
    }
  }
  check("automatic ancestry survives the real registered action and human acceptance") {
    let (book, data) = try fixture("Acceptance")
    for key in ["proposalID", "acceptedID"] {
      let trace = try book.automaticDerivationAncestry(inputs: [data[key].text])
      try expect(trace["automaticRuns"].array.count == 1)
      let run = trace["automaticRuns"].array[0]
      try expect(
        run["runID"] == data["runID"] && run["invocationSourceID"] == data["invocationID"]
          && run["automationLogicalID"] == data["automationLogicalID"]
          && run["automationDefinitionID"] == data["automationID"])
      try expect(trace["dispatchEligibility"].text == "not-evaluated")
      try expect(trace["minimalCausalSlice"] == .bool(false))
    }
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("a manual workflow and human-derived Source cannot clear automatic derivation") {
    let (book, data) = try fixture("Manual")
    var arguments = data["arguments"].object
    arguments["evidence"] = data["acceptedID"]
    let run = try book.startWorkflow(
      data["workflowID"].text, arguments: .object(arguments), token: "manual")
    let human = try independent(book, "Human correction", inputs: [data["acceptedID"].text])
    let trace = try book.automaticDerivationAncestry(inputs: [run["source_id"].text, human])
    try expect(trace["automaticRuns"].array.map { $0["runID"] } == [data["runID"]])
  }
  check("independent human evidence and untrusted origin text do not invent automatic ancestry") {
    let (book, data) = try fixture("Independent")
    let unrelated = try book.addItem(
      category: "source", kind: "observation", title: "Independent",
      data: .object(["origin": .object(["runID": data["runID"]]), "actor": .string("automatic")]))
    let trace = try book.automaticDerivationAncestry(inputs: [unrelated.id, data["sourceID"].text])
    try expect(trace["automaticRuns"].array.isEmpty && trace["maximumLineageDepth"].int == 0)
  }
  check("shared diamonds, parallel lineage relations and duplicate requested inputs stay distinct")
  {
    let book = try Workbook.create(
      at: root.appendingPathComponent("AncestryDiamond.sevra"), title: "Diamond")
    let base = try independent(book, "Base")
    let left = try independent(book, "Left", inputs: [base])
    let right = try independent(book, "Right", inputs: [base])
    let top = try independent(book, "Top", inputs: [left, right, base])
    let revised = try book.addItem(
      category: "source", kind: "observation", title: "Revised", inputs: [top], supersedes: top)
    let trace = try book.automaticDerivationAncestry(inputs: [revised.id, revised.id])
    try expect(trace["itemCount"].int == 5 && trace["edgeCount"].int == 7)
    try expect(trace["maximumLineageDepth"].int == 3 && trace["inputs"].array.count == 1)
  }
  check("ancestry remains read-only and reconstructs without restoring authority") {
    let (book, data) = try fixture("Reconstruction")
    let revision = try book.revision()
    let changes = try book.committedHistory()
    let trace = try book.automaticDerivationAncestry(inputs: [data["acceptedID"].text])
    try expect(trace == book.automaticDerivationAncestry(inputs: [data["acceptedID"].text]))
    try expect(try book.revision() == revision && book.committedHistory() == changes)
    let copy = try book.reconstruct(to: root.appendingPathComponent("AncestryRebuilt.sevra"))
    try expect(trace == copy.automaticDerivationAncestry(inputs: [data["acceptedID"].text]))
    try expect(trace["enabled"] == .bool(false) && trace["execution"].text == "none")
  }
  check("forged invocation run IDs and missing exact automatic bindings refuse") {
    let (book, data) = try fixture("Forged")
    let original = try book.item(data["invocationID"].text)
    let forged = try book.addItem(
      category: "source", kind: "application_invocation", title: "Untrusted invocation",
      data: original.data)
    try refuses("ancestry_integrity") {
      _ = try book.automaticDerivationAncestry(inputs: [forged.id])
    }
    _ = try book.db.transaction {
      try book.db.execute("DELETE FROM automation_runs WHERE run_id=?", [data["runID"]])
    }
    try refuses("ancestry_integrity") {
      _ = try book.automaticDerivationAncestry(inputs: [data["acceptedID"].text])
    }
  }
  check(
    "damaged invocation origin and missing supersession edges refuse instead of clearing ancestry"
  ) {
    let (book, data) = try fixture("Damaged")
    let original = try book.item(data["invocationID"].text)
    var content = original.data.object
    var origin = content["origin"]!.object
    origin["automationID"] = .string("different")
    content["origin"] = .object(origin)
    _ = try book.db.transaction {
      try book.db.execute(
        "UPDATE items SET data=? WHERE id=?",
        [.string(try Value.object(content).json()), data["invocationID"]])
    }
    try refuses("ancestry_integrity") {
      _ = try book.automaticDerivationAncestry(inputs: [data["acceptedID"].text])
    }
    _ = try book.db.transaction {
      try book.db.execute(
        "DELETE FROM lineage WHERE child=? AND relation='supersedes'", [data["acceptedID"]])
    }
    try refuses("ancestry_integrity") {
      _ = try book.automaticDerivationAncestry(inputs: [data["acceptedID"].text])
    }
  }
  check("erased run metadata or a changed invocation kind cannot hide an authoritative workflow") {
    let (book, data) = try fixture("Erased")
    let original = try book.item(data["invocationID"].text)
    _ = try book.db.transaction {
      try book.db.execute("UPDATE items SET data='{}' WHERE id=?", [data["invocationID"]])
    }
    try refuses("ancestry_integrity") {
      _ = try book.automaticDerivationAncestry(inputs: [data["acceptedID"].text])
    }
    _ = try book.db.transaction {
      try book.db.execute(
        "UPDATE items SET data=?,kind='observation' WHERE id=?",
        [.string(try original.data.json()), data["invocationID"]])
    }
    try refuses("ancestry_integrity") {
      _ = try book.automaticDerivationAncestry(inputs: [data["acceptedID"].text])
    }
  }
  check("workflow invocation identity is unique and uses an indexed source lookup") {
    let (book, data) = try fixture("UniqueSource")
    let manual = try book.startWorkflow(
      data["workflowID"].text, arguments: data["arguments"], token: "manual-source")
    let revision = try book.revision()
    try refuses("database") {
      _ = try book.db.transaction {
        try book.db.execute(
          "UPDATE workflow_runs SET source_id=? WHERE id=?", [data["invocationID"], manual["id"]])
      }
    }
    try expect(try book.revision() == revision)
    let plan = try book.db.execute(
      "EXPLAIN QUERY PLAN SELECT id FROM workflow_runs WHERE source_id=?", [data["invocationID"]])
    try expect(plan.contains { $0["detail"]!.text.contains("USING INDEX") })
    try expect(!plan.contains { $0["detail"]!.text.contains("SCAN") })
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("retained graph cycles refuse while a shared parent remains valid") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("AncestryCycle.sevra"), title: "Cycle")
    let base = try independent(book, "Base")
    let child = try independent(book, "Child", inputs: [base])
    _ = try book.db.transaction {
      try book.db.execute(
        "INSERT INTO lineage VALUES(?,?,'derives-from','synthetic-corruption')",
        [.string(base), .string(child)])
    }
    try refuses("ancestry_cycle") { _ = try book.automaticDerivationAncestry(inputs: [child]) }
  }
  check("longest lineage path handles shortcuts and the exact 128-edge bound") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("AncestryDepth.sevra"), title: "Depth")
    var chain: [String] = []
    _ = try book.mutation("synthetic.ancestry-depth") {
      for index in 0...129 {
        let parents = index == 0 ? [] : Array(Set([chain.last!, chain[0]]))
        chain.append(
          try book.insertItem(
            category: "source", kind: "observation", title: "Depth \(index)", text: "", data: .null,
            meaning: "actual", status: "accepted", scenario: "actual", inputs: parents,
            transformation: "synthetic"))
      }
      return .null
    }
    try expect(
      try book.automaticDerivationAncestry(inputs: [chain[128]])["maximumLineageDepth"].int == 128)
    try refuses("ancestry_limit") { _ = try book.automaticDerivationAncestry(inputs: [chain[129]]) }
  }
  check("real 1024-item boundary succeeds and 1025-item ancestry refuses") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("AncestryWidth.sevra"), title: "Width")
    var leaves: [String] = []
    _ = try book.mutation("synthetic.ancestry-width") {
      for index in 0..<1023 {
        leaves.append(
          try book.insertItem(
            category: "source", kind: "observation", title: "Leaf \(index)", text: "", data: .null,
            meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
            transformation: "synthetic"))
      }
      return .null
    }
    let first = try independent(book, "1024", inputs: leaves)
    try expect(try book.automaticDerivationAncestry(inputs: [first])["itemCount"].int == 1024)
    let over = try independent(book, "1025", inputs: [first])
    try refuses("ancestry_limit") { _ = try book.automaticDerivationAncestry(inputs: [over]) }
  }
  check("real 4096-edge boundary succeeds and 4097 edges refuse") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("AncestryEdges.sevra"), title: "Edges")
    var nodes: [String] = []
    var edgeCount = 0
    var exact = ""
    var over = ""
    _ = try book.mutation("synthetic.ancestry-edges") {
      for index in 0..<91 {
        let parents = nodes
        nodes.append(
          try book.insertItem(
            category: "source", kind: "observation", title: "Node \(index)", text: "", data: .null,
            meaning: "actual", status: "accepted", scenario: "actual", inputs: parents,
            transformation: "synthetic"))
        edgeCount += parents.count
      }
      // The complete 91-node DAG has 4,095 edges. One last edge hits the bound.
      exact = try book.insertItem(
        category: "source", kind: "observation", title: "Exact edge bound", text: "", data: .null,
        meaning: "actual", status: "accepted", scenario: "actual", inputs: [nodes.last!],
        transformation: "synthetic")
      over = try book.insertItem(
        category: "source", kind: "observation", title: "One more edge", text: "", data: .null,
        meaning: "actual", status: "accepted", scenario: "actual", inputs: [exact],
        transformation: "synthetic")
      return .null
    }
    try expect(edgeCount == 4095)
    try expect(try book.automaticDerivationAncestry(inputs: [exact])["edgeCount"].int == 4096)
    try refuses("ancestry_limit") { _ = try book.automaticDerivationAncestry(inputs: [over]) }
  }
  check("malformed, missing, excessive and already-cancelled ancestry requests refuse") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("AncestryInputs.sevra"), title: "Inputs")
    let source = try independent(book, "Input")
    for inputs in [
      [], [""], [String(repeating: "x", count: 257)], Array(repeating: source, count: 17),
    ] {
      try refuses("ancestry_input") { _ = try book.automaticDerivationAncestry(inputs: inputs) }
    }
    try refuses("ancestry_item") { _ = try book.automaticDerivationAncestry(inputs: ["missing"]) }
    let cancellation = Cancellation()
    cancellation.cancel()
    try refuses("cancelled") {
      _ = try book.automaticDerivationAncestry(inputs: [source], cancellation: cancellation)
    }
  }
  check("unsupported lineage relations refuse without treating an incomplete graph as independent")
  {
    let book = try Workbook.create(
      at: root.appendingPathComponent("AncestryRelation.sevra"), title: "Relation")
    let base = try independent(book, "Base")
    let child = try independent(book, "Child", inputs: [base])
    _ = try book.db.transaction {
      try book.db.execute("UPDATE lineage SET relation='unknown' WHERE child=?", [.string(child)])
    }
    try refuses("ancestry_integrity") { _ = try book.automaticDerivationAncestry(inputs: [child]) }
  }
  check("oversize invocation metadata refuses before decoding an unbounded payload") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("AncestryMetadata.sevra"), title: "Metadata")
    let source = try book.addItem(
      category: "source", kind: "application_invocation", title: "Oversize invocation",
      data: .string(String(repeating: "x", count: 1_048_577)))
    try refuses("ancestry_limit") { _ = try book.automaticDerivationAncestry(inputs: [source.id]) }
  }
  check("ancestry cancels a real SQLite read lock within its short-wait budget") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("AncestryLock.sevra"), title: "Locked")
    let source = try independent(book, "Source")
    let revision = try book.revision()
    let other = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    try other.execute("BEGIN EXCLUSIVE")
    defer { _ = try? other.execute("ROLLBACK") }
    let cancellation = Cancellation()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { cancellation.cancel() }
    let started = ProcessInfo.processInfo.systemUptime
    try refuses("cancelled") {
      _ = try book.automaticDerivationAncestry(inputs: [source], cancellation: cancellation)
    }
    try expect(ProcessInfo.processInfo.systemUptime - started < 1)
    try other.execute("ROLLBACK")
    try expect(try book.revision() == revision)
  }
  check("cancellation at the condition publication barrier rolls back all derived state") {
    let (book, source) = try businessFixture(root, "ConditionCancellationFence")
    try book.setOpeningBalance(
      subject: "parts", quantity: "20", effective: "2026-01-01", sourceID: source.id)
    let consumer = try book.createInventoryCondition(
      subject: "parts", rule: inventoryConditionRule(), effectiveThrough: "2026-12-31",
      token: "create")["id"].text
    let revision = try book.revision()
    let before = try book.inventoryCondition(consumer)
    let cancellation = Cancellation()
    try InventoryConditionPublicationProbe.$observer.withValue({ stage in
      if case .prepared = stage { cancellation.cancel() }
    }) {
      try refuses("cancelled") {
        _ = try book.stepInventoryCondition(
          consumer, through: "2026-12-31", token: "cancelled-page", cancellation: cancellation)
      }
    }
    try expect(try book.revision() == revision && book.inventoryCondition(consumer) == before)
    _ = try book.stepInventoryCondition(consumer, through: "2026-12-31", token: "cancelled-page")
    try expect(try book.revision() == revision + 1)
    try expect(try drainInventoryCondition(book, consumer)["established"] == .bool(true))
    try expect(try book.verify()["ok"] == .bool(true))
  }
}
