import Foundation

@testable import SevraCore

func checkConditionInputCorruption(at root: URL) {
  check("missing or erased input members and contradictory observation links refuse") {
    for damage in 0..<4 {
      let (book, source, id) = try conditionInputFixture(root, "Damage\(damage)")
      _ = try conditionInputMove(book, source, "-15")
      let observation = try conditionInputObservation(book, id)
      _ = try book.db.transaction {
        if damage == 0 {
          try book.db.execute(
            "DELETE FROM condition_observation_inputs WHERE observation_id=?", [observation["id"]])
        } else if damage == 1 {
          try book.db.execute(
            "UPDATE condition_observation_inputs SET payload='{}' WHERE observation_id=?",
            [observation["id"]])
        } else {
          var fields = observation.object
          fields[damage == 2 ? "previousObservationID" : "previousCertainObservationID"] =
            observation["id"]
          try book.db.execute(
            "UPDATE condition_observations SET payload=? WHERE id=?",
            [.string(try Value.object(fields).json()), observation["id"]])
        }
      }
      try refuses { _ = try book.inventoryConditionInputs(observation["id"].text) }
      try refuses { _ = try book.verify() }
    }
  }
  check("a content-consistent forged input from another subject still fails scope validation") {
    let (book, source, id) = try conditionInputFixture(root, "ForgedScope")
    var otherID = ""
    _ = try book.mutation("synthetic.forged-input-batch") {
      _ = try book.insertMovement(
        book.movementRequest(
          subject: "parts", quantity: "-15", occurrence: "parts", effective: "2026-01-02",
          input: source.id, status: "accepted"))
      otherID = try book.insertMovement(
        book.movementRequest(
          subject: "other", quantity: "-15", occurrence: "other", effective: "2026-01-02",
          input: source.id, status: "accepted"))
      return .null
    }
    let observation = try conditionInputObservation(book, id)
    let eventID = try book.db.scalar(
      "SELECT id FROM business_events WHERE batch_id=? AND after_id=?",
      [observation["knowledgeBatchID"], .string(otherID)]
    ).text
    let event = try book.conditionInputEvent(eventID)
    let value = ConditionInput.value("record-change", event: event)
    let key = try ConditionInput.identity(value, consumer: id)
    _ = try book.db.transaction {
      try book.db.execute(
        "DELETE FROM condition_observation_inputs WHERE observation_id=?", [observation["id"]])
      try book.db.execute(
        "INSERT INTO condition_observation_inputs VALUES(?,?,?)",
        [observation["id"], .string(key), .string(try value.json())])
    }
    try refuses("condition_input_integrity") {
      _ = try book.inventoryConditionInputs(observation["id"].text)
    }
    try refuses("condition_input_integrity") { _ = try book.verify() }
  }
  check("input retention deduplicates an exact entry inside its captured transaction") {
    let (book, source, id) = try conditionInputFixture(root, "Dedup")
    let movement = try conditionInputMove(book, source, "-15")
    let eventID = try book.db.scalar(
      "SELECT id FROM business_events WHERE after_id=?", [.string(movement.id)]
    ).text
    let event = try book.conditionInputEvent(eventID)
    let consumer = try book.inventoryConditionRow(id)
    var work = try book.inventoryConditionWork(consumer)
    try refuses("synthetic_rollback") {
      _ = try book.mutation("synthetic.duplicate-input") {
        try book.retainConditionInput(consumer, event: event, kind: "record-change", work: &work)
        try book.retainConditionInput(consumer, event: event, kind: "record-change", work: &work)
        try expect(work.pendingInputCount == 1)
        try expect(
          try book.db.scalar(
            "SELECT count(*) FROM condition_pending_inputs WHERE consumer_id=?", [.string(id)]
          ).int == 1)
        throw SevraError("synthetic_rollback", "Keep this isolated capture test inert.")
      }
    }
    try refuses("condition_input_transaction") {
      try book.retainConditionInput(consumer, event: event, kind: "record-change", work: &work)
    }
  }
  check("input inspection cancels a real exclusive SQLite lock within one second") {
    let (book, source, id) = try conditionInputFixture(root, "Locked")
    _ = try conditionInputMove(book, source, "-15")
    let observation = try conditionInputObservation(book, id)
    let other = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    try other.execute("BEGIN EXCLUSIVE")
    defer { _ = try? other.execute("ROLLBACK") }
    let cancellation = Cancellation()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { cancellation.cancel() }
    let start = ProcessInfo.processInfo.systemUptime
    try refuses("cancelled") {
      _ = try book.inventoryConditionInputs(observation["id"].text, cancellation: cancellation)
    }
    try expect(ProcessInfo.processInfo.systemUptime - start < 1)
  }
}

func createConditionInputFixture(at url: URL) throws -> Value {
  let book = try Workbook.create(at: url, title: "Synthetic transition inputs")
  let source = try book.addItem(
    category: "source", kind: "observation", title: "Synthetic delivery")
  try book.setOpeningBalance(
    subject: "parts", quantity: "20", effective: "2026-01-01", sourceID: source.id)
  let id = try book.createInventoryCondition(
    subject: "parts", rule: inventoryConditionRule(), effectiveThrough: "2026-12-31",
    token: "create")["id"].text
  let baseline = try conditionInputObservation(book, id)
  _ = try book.mutation("synthetic.installed-inputs") {
    for n in 0..<205 {
      _ = try book.insertMovement(
        book.movementRequest(
          subject: "parts", quantity: n == 204 ? "190" : "-1", occurrence: "installed-input-\(n)",
          effective: "2026-01-02", input: source.id, status: "accepted"))
    }
    return .null
  }
  let observed = try conditionInputObservation(book, id)
  _ = try book.verify()
  return .object([
    "consumerID": .string(id), "baselineID": baseline["id"], "observationID": observed["id"],
    "expectedInputs": .number(205), "observation": observed,
  ])
}

func checkConditionInputLimit(at root: URL) {
  check(
    "real10000 transition inputs are complete and10001 retains exact numeric state with explicit overflow"
  ) {
    let (book, source, id) = try conditionInputFixture(root, "ActualLimit")
    var originals: [String] = []
    _ = try book.mutation("synthetic.input-limit-exact") {
      for n in 0..<10_000 {
        originals.append(
          try book.insertMovement(
            book.movementRequest(
              subject: "parts", quantity: "1", occurrence: "input-limit-\(n)",
              effective: "2026-01-02", input: source.id, status: "accepted")))
      }
      return .null
    }
    let exact = try conditionInputObservation(book, id)
    try expect(exact["quantity"].text == "10020" && exact["changeInputs"]["count"].int == 10_000)
    try expect(
      exact["changeInputs"]["coverage"].text == "complete"
        && exact["changeInputs"]["overflow"] == .bool(false))
    try expect(try conditionInputPages(book, exact["id"].text).count == 10_000)
    _ = try book.mutation("synthetic.input-limit-overflow") {
      for (n, old) in originals.enumerated() {
        _ = try book.insertMovement(
          book.movementRequest(
            subject: "parts", quantity: "1", occurrence: "input-limit-\(n)",
            effective: "2026-01-02", input: source.id, status: "accepted", supersedes: old))
      }
      try book.db.execute("UPDATE bases SET quantity='30' WHERE subject='parts'")
      return .null
    }
    let overflow = try conditionInputObservation(Workbook(book.url), id)
    try expect(
      overflow["quantity"].text == "10030" && overflow["changeInputs"]["count"].int == 10_000)
    try expect(
      overflow["changeInputs"]["coverage"].text == "limit-exceeded"
        && overflow["changeInputs"]["overflow"] == .bool(true))
    try expect(try conditionInputPages(book, overflow["id"].text).count == 10_000)
    try expect(
      try book.db.scalar(
        "SELECT count(*) FROM condition_pending_inputs WHERE consumer_id=?", [.string(id)]
      ).int == 0)
  }
}
