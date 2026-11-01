import Foundation

@testable import SevraCore

func checkBusinessOrigins(at root: URL) {
  func fixture(_ name: String) throws -> (Workbook, Value) {
    let url = root.appendingPathComponent("BusinessOrigins-" + name + ".sevra")
    let data = try createAutomaticAncestryFixture(at: url)
    return (try Workbook(url), data)
  }
  func trace(_ book: Workbook, _ inputs: [String]) throws -> Value {
    let result = try book.businessOrigins(inputs: inputs)
    try expect(result["minimalCauseSet"] == .bool(false))
    try expect(result["independentBusinessRoots"] == .string("not-established"))
    try expect(result["dispatchEligibility"] == .string("not-evaluated"))
    try expect(result["execution"] == .string("none") && result["enabled"] == .bool(false))
    try expect(
      result["coverage"] == .string("retained-business-dependencies-to-automatic-producers"))
    return result
  }
  func original(_ book: Workbook, _ title: String, inputs: [String] = []) throws -> String {
    try book.addItem(category: "source", kind: "observation", title: title, inputs: inputs).id
  }
  check(
    "business origin retains an authoritative automatic producer through human acceptance and correction"
  ) {
    let (book, data) = try fixture("Review")
    let accepted = try book.item(data["acceptedID"].text)
    let correction = try book.movement(
      subject: "parts", quantity: "6", occurrence: accepted.data["occurrence"].text,
      effective: accepted.data["effective"].text, input: data["sourceID"].text,
      supersedes: accepted.id)
    for id in [data["proposalID"].text, accepted.id, correction.id] {
      let result = try trace(book, [id, id])
      try expect(result["inputs"].array.count == 1 && result["automaticProducers"].array.count == 1)
      let producer = result["automaticProducers"].array[0]
      try expect(producer["runID"] == data["runID"] && producer["admission"]["depth"].int == 1)
      try expect(producer["invocationSourceID"] == data["invocationID"])
      try expect(result["items"].array.contains { $0["automaticBoundary"] == .bool(true) })
    }
  }
  check("automatic authored configuration does not contaminate independent manual business data") {
    let (book, data) = try fixture("Control")
    let action = try book.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.receivingDefinition(),
      inputs: [data["acceptedID"].text])
    let workflow = try book.saveApplicationDefinition(
      logicalID: identifier(), content: book.workflowTemplate(action.id))
    var args = data["arguments"].object
    args["delivery"] = .string("new-independent-delivery")
    let run = try book.startWorkflow(workflow.id, arguments: .object(args), token: "manual")
    let session = try book.authorizeWorkflowExecution(run["id"].text)
    let waiting = try book.continueWorkflow(session, owner: "control-origin")
    let proposal = waiting["steps"].array[0]["output"]["value"]["proposals"].array[0].text
    let broad = try book.automaticDerivationAncestry(inputs: [proposal])
    let result = try trace(book, [proposal])
    try expect(
      broad["automaticRuns"].array.count == 1 && result["automaticProducers"].array.isEmpty)
    try expect(result["originalInputCandidates"].array == [data["sourceID"]])
    try expect(result["controlLinks"].array.contains { $0["parent"] == .string(action.sourceID) })
    try expect(!result["items"].array.contains { $0["id"] == data["acceptedID"] })
  }
  check("manual continuation and new human Sources retain automatic business inputs") {
    let (book, data) = try fixture("Manual")
    var args = data["arguments"].object
    args["delivery"] = .string("manual-follow-up")
    args["evidence"] = data["acceptedID"]
    let run = try book.startWorkflow(
      data["workflowID"].text, arguments: .object(args), token: "manual")
    let session = try book.authorizeWorkflowExecution(run["id"].text)
    let waiting = try book.continueWorkflow(session, owner: "manual-origin")
    let id = waiting["steps"].array[0]["output"]["value"]["proposals"].array[0].text
    let human = try original(book, "Human explanation", inputs: [id])
    let result = try trace(book, [human])
    try expect(result["automaticProducers"].array.map { $0["runID"] } == [data["runID"]])
  }
  check("dual data control and producer roles remain traversed instead of being overwritten") {
    let (book, data) = try fixture("Dual")
    let id = try book.mutation("synthetic.origin-dual") {
      .string(
        try book.insertItem(
          category: "record", kind: "document", title: "Dual", text: "", data: .null,
          meaning: "estimate", status: "draft", scenario: "planning",
          inputs: [data["invocationID"].text],
          transformation: "synthetic", controlInputs: [data["invocationID"].text],
          producerInputs: [data["invocationID"].text]))
    }.text
    let result = try trace(book, [id])
    let edge = result["edges"].array.first { $0["child"] == .string(id) }!
    try expect(edge["roles"] == .array([.string("data"), .string("control"), .string("producer")]))
    try expect(edge["traversed"] == .bool(true) && result["automaticProducers"].array.count == 1)
    try expect(result["controlLinks"].array.count >= 1)
  }
  check("technical control only and data free derived leaves stay visibly unclassified") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("OriginLeaves.sevra"), title: "Leaves")
    let input = try original(book, "Independent-looking input")
    var technical = ""
    let derived = try book.mutation("synthetic.origin-leaves") {
      technical = try book.insertItem(
        category: "source", kind: "annotation", title: "Technical", text: "", data: .null,
        meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
        transformation: "synthetic",
        controlInputs: [input])
      return .string(
        try book.insertItem(
          category: "record", kind: "calculation", title: "Constant", text: "2", data: .null,
          meaning: "estimate", status: "draft", scenario: "planning", inputs: [],
          transformation: "synthetic",
          controlInputs: [technical]))
    }.text
    let leaf = try trace(book, [derived])
    try expect(leaf["itemCount"].int == 1 && leaf["unclassifiedOrigins"].array.count == 1)
    try expect(leaf["originalInputCandidates"].array.isEmpty)
    let metadata = try trace(book, [technical])
    try expect(metadata["unclassifiedOrigins"].array.count == 1)
    try expect(try trace(book, [input])["originalInputCandidates"].array == [.string(input)])
  }
  check("origin inspection is read only and reconstructs without restoring live grants") {
    let (book, data) = try fixture("Reconstruction")
    let before = try book.db.authorityDigest()
    let result = try trace(book, [data["acceptedID"].text])
    try expect(result == trace(book, [data["acceptedID"].text]))
    try expect(try book.db.authorityDigest() == before)
    let copy = try book.reconstruct(to: root.appendingPathComponent("BusinessOriginCopy.sevra"))
    try expect(result == trace(copy, [data["acceptedID"].text]))
    _ = try copy.verify()
  }
  check("missing altered extra foreign and unsupported seals refuse complete business origin") {
    for damage in 0..<5 {
      let (book, source) = try businessFixture(root, "OriginSeal\(damage)")
      let spare = try original(book, "Spare")
      let record = try book.addItem(
        category: "record", kind: "document", title: "Derived", inputs: [source.id])
      _ = try book.db.transaction {
        switch damage {
        case 0: try book.db.execute("DELETE FROM lineage WHERE child=?", [.string(record.id)])
        case 1:
          try book.db.execute("UPDATE lineage SET roles=2 WHERE child=?", [.string(record.id)])
        case 2:
          try book.db.execute(
            "INSERT INTO lineage VALUES(?,?,'derives-from','synthetic',1)",
            [.string(record.id), .string(spare)])
        case 3:
          try book.db.execute(
            "UPDATE items SET derivation=json_set(derivation,'$.itemID','foreign') WHERE id=?",
            [.string(record.id)])
        default:
          try book.db.execute("UPDATE items SET derivation='{}' WHERE id=?", [.string(record.id)])
        }
      }
      try refuses("derivation_integrity") { _ = try book.businessOrigins(inputs: [record.id]) }
    }
  }
  check("erased automatic kind actor arguments policy and admission cannot become a manual origin")
  {
    for damage in 0..<6 {
      let (book, data) = try fixture("ProducerDamage\(damage)")
      _ = try book.db.transaction {
        let id = data["invocationID"]
        switch damage {
        case 0: try book.db.execute("UPDATE items SET data='{}' WHERE id=?", [id])
        case 1: try book.db.execute("UPDATE items SET kind='observation' WHERE id=?", [id])
        case 2:
          try book.db.execute(
            "UPDATE items SET data=json_set(data,'$.actor','wrong') WHERE id=?", [id])
        case 3:
          try book.db.execute(
            "UPDATE items SET data=json_set(data,'$.normalizedArguments',json('{}')) WHERE id=?",
            [id])
        case 4:
          try book.db.execute(
            "UPDATE items SET data=json_set(data,'$.policy','unsupported') WHERE id=?", [id])
        default:
          try book.db.execute("DELETE FROM automatic_root_members WHERE run_id=?", [data["runID"]])
        }
      }
      var refused = false
      do { _ = try book.businessOrigins(inputs: [data["acceptedID"].text]) } catch let error
        as SevraError
      {
        refused = ["origin_producer", "ancestry_integrity", "causal_integrity"].contains(error.code)
      }
      try expect(refused)
    }
  }
  check("origin validates direct producer policies and cannot hide them by relabeling kind") {
    for damage in 0..<4 {
      let (book, data) = try fixture("DirectDamage\(damage)")
      let action = try book.saveApplicationDefinition(
        logicalID: identifier(), content: ActionRegistry.receivingDefinition())
      var arguments = data["arguments"].object
      arguments["delivery"] = .string("direct-policy-test")
      let plan = try book.previewApplicationAction(action.id, arguments: .object(arguments))
      let saved = try book.invokeApplicationAction(
        action.id, arguments: .object(arguments), preview: plan, token: "direct")
      let proposal = saved["proposals"].array[0].text
      try expect(try trace(book, [proposal])["automaticProducers"].array.isEmpty)
      _ = try book.db.transaction {
        let id = saved["sourceID"]
        switch damage {
        case 0:
          try book.db.execute(
            "UPDATE items SET data=json_remove(data,'$.producerPolicy') WHERE id=?", [id])
        case 1:
          try book.db.execute(
            "UPDATE items SET data=json_set(data,'$.producerPolicy','unknown') WHERE id=?", [id])
        case 2: try book.db.execute("UPDATE items SET kind='observation' WHERE id=?", [id])
        default:
          try book.db.execute(
            "UPDATE items SET data=json_set(data,'$.plan.fingerprint','wrong') WHERE id=?", [id])
        }
      }
      try refuses("origin_producer") { _ = try book.businessOrigins(inputs: [proposal]) }
    }
  }
  check("a sealed shared DAG stays complete while a coherently resealed cycle still refuses") {
    let book = try Workbook.create(at: root.appendingPathComponent("OriginDAG.sevra"), title: "DAG")
    let base = try original(book, "Base")
    let a = try original(book, "A", inputs: [base])
    let b = try original(book, "B", inputs: [base])
    let top = try original(book, "Top", inputs: [a, b, base])
    let result = try trace(book, [top, a])
    try expect(result["itemCount"].int == 4 && result["edgeCount"].int == 5)
    try expect(result["maximumLineageDepth"].int == 2)
    _ = try book.db.transaction {
      try book.db.execute(
        "INSERT INTO lineage VALUES(?,?,'derives-from','synthetic-cycle',1)",
        [.string(base), .string(top)])
      let seal = try book.calculatedItemDerivation(derivationRow(book, base))
      try book.db.execute(
        "UPDATE items SET derivation=? WHERE id=?", [.string(try seal.json()), .string(base)])
    }
    try refuses("ancestry_cycle") { _ = try book.businessOrigins(inputs: [top]) }
  }
  check("business origin rejects malformed missing excessive and cancelled input selections") {
    let (book, source) = try businessFixture(root, "OriginInput")
    for inputs in [
      [], [""], [String(repeating: "x", count: 257)], Array(repeating: source.id, count: 17),
    ] {
      try refuses("origin_input") { _ = try book.businessOrigins(inputs: inputs) }
    }
    try refuses("origin_item") { _ = try book.businessOrigins(inputs: ["missing"]) }
    let cancellation = Cancellation()
    cancellation.cancel()
    try refuses("cancelled") {
      _ = try book.businessOrigins(inputs: [source.id], cancellation: cancellation)
    }
  }
  check("origin inspection bounds metadata before decoding and ignores unrelated original bodies") {
    let (book, source) = try businessFixture(root, "OriginBytes")
    let large = try book.addItem(
      category: "source", kind: "observation", title: "Large original",
      data: .string(String(repeating: "x", count: 1_048_577)))
    try expect(try trace(book, [large.id])["originalInputCandidates"].array == [.string(large.id)])
    let invocation = try book.addHostOwnedItem(
      category: "source", kind: "application_invocation", title: "Oversize producer",
      data: .string(String(repeating: "x", count: 1_048_577)), inputs: [source.id])
    try refuses("origin_limit") { _ = try book.businessOrigins(inputs: [invocation.id]) }
    _ = try book.db.transaction {
      try book.db.execute(
        "UPDATE items SET derivation=? WHERE id=?",
        [.string(String(repeating: "x", count: 4097)), .string(source.id)])
    }
    try refuses("origin_limit") { _ = try book.businessOrigins(inputs: [source.id]) }
  }
  check("origin rejects an oversized edge page before retaining an unbounded transformation") {
    let (book, source) = try businessFixture(root, "OriginEdgeBytes")
    let id = try book.addItem(
      category: "record", kind: "document", title: "Oversize edge", inputs: [source.id],
      transformation: String(repeating: "x", count: 2_097_153)
    ).id
    try refuses("query_result_limit") { _ = try book.businessOrigins(inputs: [id]) }
  }
  check("origin output is charged while building and refuses oversized multi page graphs") {
    let (book, source) = try businessFixture(root, "OriginOutputBytes")
    var previous = source.id
    for index in 0..<9 {
      previous = try book.addItem(
        category: "source", kind: "observation", title: "Page\(index)", inputs: [previous],
        transformation: String(repeating: "x", count: 1_000_000)
      ).id
    }
    try refuses("origin_limit") { _ = try book.businessOrigins(inputs: [previous]) }
  }
  check("origin inspection cancels an actual SQLite lock without changing retained authority") {
    let (book, source) = try businessFixture(root, "OriginLock")
    let before = try book.db.authorityDigest()
    let other = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    try other.execute("BEGIN EXCLUSIVE")
    defer { _ = try? other.execute("ROLLBACK") }
    let cancellation = Cancellation()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { cancellation.cancel() }
    let started = ProcessInfo.processInfo.systemUptime
    try refuses("cancelled") {
      _ = try book.businessOrigins(inputs: [source.id], cancellation: cancellation)
    }
    try expect(ProcessInfo.processInfo.systemUptime - started < 1)
    try other.execute("ROLLBACK")
    try expect(try book.db.authorityDigest() == before)
  }
}
