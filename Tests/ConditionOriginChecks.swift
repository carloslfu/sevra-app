import Foundation

@testable import SevraCore

func createConditionOriginFixture(at url: URL) throws -> Value {
  var data = try createAutomaticAncestryFixture(at: url).object
  let book = try Workbook(url)
  let source = try book.item(data["sourceID"]!.text)
  try book.setOpeningBalance(
    subject: "parts", quantity: "20", effective: "2026-01-01", sourceID: source.id)
  let id = try book.createInventoryCondition(
    subject: "parts", rule: inventoryConditionRule(),
    effectiveThrough: "2026-12-31", token: "condition")["id"].text
  let baseline = try conditionInputObservation(book, id)
  let accepted = try book.item(data["acceptedID"]!.text)
  let correction = try conditionInputMove(
    book, source, "-15", date: accepted.data["effective"].text, supersedes: accepted)
  let observation = try conditionInputObservation(book, id)
  try expect(observation["disposition"].text == "transition" && observation["quantity"].text == "5")
  data["consumerID"] = .string(id)
  data["baselineID"] = baseline["id"]
  data["observationID"] = observation["id"]
  data["correctionID"] = .string(correction.id)
  return .object(data)
}

func checkConditionOrigins(at root: URL) {
  func fixture(_ name: String) throws -> (Workbook, Value) {
    let url = root.appendingPathComponent("ConditionOrigin-" + name + ".sevra")
    let data = try createConditionOriginFixture(at: url)
    return (try Workbook(url), data)
  }
  func trace(_ book: Workbook, _ id: String) throws -> Value {
    let value = try book.inventoryConditionOrigins(id)
    try expect(
      value["minimalCauseSet"] == .bool(false)
        && value["independentBusinessRoots"].text == "not-established")
    try expect(
      value["dispatchEligibility"].text == "not-evaluated" && value["execution"].text == "none"
        && value["enabled"] == .bool(false))
    let members = try conditionInputPages(book, id)
    let pairs = members.map { Value.array([$0["id"], $0["input"]]) }
    try expect(value["inputCount"].int == members.count)
    try expect(value["inputSetHash"] == .string(ChangeFormat.hash(try Value.array(pairs).json())))
    return value
  }
  check("exact condition window retains automatic origin through accepted movement correction") {
    let (book, data) = try fixture("Automatic")
    let value = try trace(book, data["observationID"].text)
    try expect(
      value["inputCount"].int == 1 && value["automaticProducerRunIDs"].array == [data["runID"]])
    try expect(
      Set(value["origins"]["inputs"].array.map(\.text))
        == Set([data["acceptedID"].text, data["correctionID"].text]))
    try expect(value["previousCertainObservationID"] == data["baselineID"])
    try expect(value["retainedChangeInputs"]["automaticParents"].text == "not-resolved")
  }
  check("condition origins exclude unrelated records and keep exact scoped atomic changes") {
    let (book, source, id) = try conditionInputFixture(root, "OriginScope")
    var relevant: [String] = []
    var unrelated = ""
    _ = try book.mutation("synthetic.condition-origin-scope") {
      for (subject, quantity) in [("parts", "-15"), ("parts", "1"), ("other", "-99")] {
        let item = try book.insertMovement(
          book.movementRequest(
            subject: subject, quantity: quantity,
            occurrence: identifier(), effective: "2026-01-02", input: source.id, status: "accepted")
        )
        if subject == "parts" { relevant.append(item) } else { unrelated = item }
      }
      return .null
    }
    let observation = try conditionInputObservation(book, id)
    let value = try trace(book, observation["id"].text)
    try expect(
      value["inputCount"].int == 2
        && Set(value["origins"]["inputs"].array.map(\.text)) == Set(relevant))
    try expect(!value["origins"]["items"].array.contains { $0["id"] == .string(unrelated) })
    try expect(value["automaticProducerRunIDs"].array.isEmpty)
  }
  check("condition window excludes automatic configuration from independent manual data") {
    let (book, data) = try fixture("Control")
    let action = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: ActionRegistry.receivingDefinition(), inputs: [data["acceptedID"].text])
    var arguments = data["arguments"].object
    arguments["delivery"] = .string("manual-control-test")
    let plan = try book.previewApplicationAction(action.id, arguments: .object(arguments))
    let submitted = try book.invokeApplicationAction(
      action.id, arguments: .object(arguments), preview: plan, token: "manual")
    _ = try book.accept(submitted["proposals"].array[0].text)
    let observation = try conditionInputObservation(book, data["consumerID"].text)
    let value = try trace(book, observation["id"].text)
    try expect(value["automaticProducerRunIDs"].array.isEmpty)
    try expect(
      value["origins"]["controlLinks"].array.contains { $0["parent"] == .string(action.sourceID) })
    try expect(value["origins"]["originalInputCandidates"].array.contains(data["sourceID"]))
    try expect(!value["origins"]["items"].array.contains { $0["id"] == data["acceptedID"] })
  }
  check("205 condition members resolve across pages without the public16 input truncation") {
    let (book, source, id) = try conditionInputFixture(root, "OriginPages")
    let baseline = try conditionInputObservation(book, id)
    _ = try book.mutation("synthetic.condition-origin-pages") {
      for _ in 0..<205 {
        _ = try book.insertMovement(
          book.movementRequest(
            subject: "parts", quantity: "1", occurrence: identifier(),
            effective: "2026-01-02", input: source.id, status: "accepted"))
      }
      return .null
    }
    let partial = try book.stepInventoryCondition(id, through: "2026-12-31", token: "partial")
    try expect(partial["lastCompleteObservation"] == baseline)
    try refuses("condition_origin_coverage") {
      _ = try book.inventoryConditionOrigins(baseline["id"].text)
    }
    let observation = try conditionInputObservation(Workbook(book.url), id)
    let value = try trace(book, observation["id"].text)
    try expect(value["inputCount"].int == 205 && value["origins"]["inputs"].array.count == 205)
    try expect(value["origins"]["itemCount"].int == 206)
  }
  check("condition resolution shares real1024 graph and starting version limits") {
    let (book, source, id) = try conditionInputFixture(root, "OriginLimits")
    for count in [1023, 1024, 1025] {
      _ = try book.mutation("synthetic.condition-origin-bound") {
        for _ in 0..<count {
          _ = try book.insertMovement(
            book.movementRequest(
              subject: "parts", quantity: "1", occurrence: identifier(),
              effective: "2026-01-02", input: source.id, status: "accepted"))
        }
        return .null
      }
      let observation = try conditionInputObservation(book, id)
      if count == 1023 {
        try expect(try trace(book, observation["id"].text)["origins"]["itemCount"].int == 1024)
      } else {
        try refuses(count == 1024 ? "origin_limit" : "condition_origin_limit") {
          _ = try book.inventoryConditionOrigins(observation["id"].text)
        }
      }
      try expect(observation["changeInputs"]["coverage"].text == "complete")
    }
  }
  check("empty complete windows stay empty without claiming independent origins") {
    let (book, source, id) = try conditionInputFixture(root, "OriginEmpty")
    _ = try book.movement(
      subject: "other", quantity: "-1", occurrence: identifier(), effective: "2026-01-02",
      input: source.id, status: "accepted")
    let observation = try conditionInputObservation(book, id)
    let value = try trace(book, observation["id"].text)
    try expect(value["inputCount"].int == 0 && value["origins"]["items"].array.isEmpty)
    try expect(
      value["automaticProducerRunIDs"].array.isEmpty
        && value["origins"]["originalInputCandidates"].array.isEmpty)
  }
  check("clock activation uses the introducing version and captured effective instant") {
    let (book, source, id) = try conditionInputFixture(root, "OriginClock")
    let movement = try conditionInputMove(book, source, "-15", date: "2030-01-01")
    _ = try conditionInputObservation(book, id)
    _ = try book.stepInventoryCondition(id, through: "2030-01-02", token: "clock-origin")
    _ = try drainInventoryCondition(book, id, through: "2030-01-02")
    let observations = try book.inventoryConditionObservations(id, limit: 50)["observations"].array
      .map { $0["observation"] }
    guard
      let observation = observations.first(where: {
        $0["effectiveThrough"].text.hasPrefix("2030-01-01")
      })
    else {
      throw SevraError("test", "The requested clock observation is missing.")
    }
    let value = try trace(book, observation["id"].text)
    try expect(value["origins"]["inputs"].array == [.string(movement.id)])
    try expect(
      value["effectiveThrough"] == observation["effectiveThrough"] && value["inputCount"].int == 1)
    let entry = try conditionInputPages(book, observation["id"].text)[0]["input"]
    try expect(
      entry["kind"].text == "effect-clock" && entry["effective"] == value["effectiveThrough"])
  }
  check("baseline unknown and recovered gap windows cannot resolve to independent roots") {
    let (book, _, id) = try conditionInputFixture(root, "OriginUnknown")
    let baseline = try conditionInputObservation(book, id)
    try refuses("condition_origin_coverage") {
      _ = try book.inventoryConditionOrigins(baseline["id"].text)
    }
    _ = try book.mutation("synthetic.condition-origin-unknown") {
      try book.db.execute(
        "UPDATE bases SET quantity='5',effective=? WHERE subject='parts'",
        [.string(try BusinessTime.normalized("2030-01-01"))])
      return .null
    }
    let unknown = try conditionInputObservation(book, id)
    try refuses("condition_origin_coverage") {
      _ = try book.inventoryConditionOrigins(unknown["id"].text)
    }
    _ = try book.stepInventoryCondition(id, through: "2030-01-01", token: "basis-origin")
    _ = try drainInventoryCondition(book, id, through: "2030-01-01")
    let recovery = try book.inventoryCondition(id)["lastCompleteObservation"]
    try expect(recovery["coverageGap"] == .bool(true))
    try refuses("condition_origin_coverage") {
      _ = try book.inventoryConditionOrigins(recovery["id"].text)
    }
  }
  check("same Source basis events keep distinct condition window digests") {
    let (book, _, id) = try conditionInputFixture(root, "OriginBasis")
    var hashes: [Value] = []
    for quantity in ["5", "20", "5"] {
      _ = try book.mutation("synthetic.condition-origin-basis") {
        try book.db.execute(
          "UPDATE bases SET quantity=? WHERE subject='parts'", [.string(quantity)])
        return .null
      }
      let observation = try conditionInputObservation(book, id)
      let value = try trace(book, observation["id"].text)
      try expect(value["inputCount"].int == 1 && value["origins"]["inputs"].array.count == 1)
      hashes.append(value["inputSetHash"])
    }
    try expect(Set(hashes.map(\.text)).count == 3)
  }
  check("condition origin inspection is read only and reconstructs exactly without live grants") {
    let (book, data) = try fixture("Reconstruct")
    let before = try book.db.authorityDigest()
    let value = try trace(book, data["observationID"].text)
    let copy = try book.reconstruct(to: root.appendingPathComponent("ConditionOriginCopy.sevra"))
    try expect(value == trace(copy, data["observationID"].text))
    try expect(try book.db.authorityDigest() == before)
    _ = try copy.verify()
  }
  check("missing foreign altered oversize or unsealed condition inputs refuse the whole origin") {
    for damage in 0..<7 {
      let (book, data) = try fixture("Damage\(damage)")
      var expected = "condition_input_integrity"
      _ = try book.db.transaction {
        let observation = data["observationID"]
        switch damage {
        case 0:
          try book.db.execute(
            "DELETE FROM condition_observation_inputs WHERE observation_id=?", [observation])
        case 1:
          try book.db.execute(
            "UPDATE condition_observation_inputs SET id='foreign' WHERE observation_id=?",
            [observation])
        case 2:
          try book.db.execute(
            "UPDATE condition_observation_inputs SET payload=json_set(payload,'$.eventID','foreign') WHERE observation_id=?",
            [observation])
        case 3:
          try book.db.execute(
            "UPDATE condition_observations SET payload=json_set(payload,'$.previousObservationID','foreign') WHERE id=?",
            [observation])
        case 4:
          expected = "derivation_integrity"
          try book.db.execute("UPDATE items SET derivation='{}' WHERE id=?", [data["correctionID"]])
        case 5:
          expected = "condition_origin_limit"
          try book.db.execute(
            "UPDATE condition_observation_inputs SET payload=? WHERE observation_id=?",
            [.string(String(repeating: "x", count: 16385)), observation])
        default:
          expected = "causal_integrity"
          try book.db.execute("DELETE FROM automatic_root_members WHERE run_id=?", [data["runID"]])
        }
      }
      try refuses(expected) { _ = try book.inventoryConditionOrigins(data["observationID"].text) }
    }
  }
  check("condition origin request validation and real lock cancellation preserve authority") {
    let (book, data) = try fixture("Cancel")
    for id in ["", String(repeating: "x", count: 257)] {
      try refuses("condition_input") { _ = try book.inventoryConditionOrigins(id) }
    }
    try refuses("condition_observation") { _ = try book.inventoryConditionOrigins("missing") }
    let before = try book.db.authorityDigest()
    let other = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    try other.execute("BEGIN EXCLUSIVE")
    defer { _ = try? other.execute("ROLLBACK") }
    let cancellation = Cancellation()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { cancellation.cancel() }
    let started = ProcessInfo.processInfo.systemUptime
    try refuses("cancelled") {
      _ = try book.inventoryConditionOrigins(data["observationID"].text, cancellation: cancellation)
    }
    try expect(ProcessInfo.processInfo.systemUptime - started < 1)
    try other.execute("ROLLBACK")
    try expect(try book.db.authorityDigest() == before)
  }
}
