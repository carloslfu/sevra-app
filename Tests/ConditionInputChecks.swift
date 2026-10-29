import Foundation

@testable import SevraCore

func conditionInputFixture(_ root: URL, _ name: String) throws -> (Workbook, Item, String) {
  let (book, source) = try businessFixture(root, "ConditionInputs" + name)
  try book.setOpeningBalance(
    subject: "parts", quantity: "20", effective: "2026-01-01", sourceID: source.id)
  let id = try book.createInventoryCondition(
    subject: "parts", rule: inventoryConditionRule(),
    effectiveThrough: "2026-12-31", token: "create")["id"].text
  _ = try drainInventoryCondition(book, id)
  return (book, source, id)
}

func conditionInputMove(
  _ book: Workbook, _ source: Item, _ quantity: String,
  date: String = "2026-01-02", supersedes: Item? = nil
) throws -> Item {
  try book.movement(
    subject: "parts", quantity: quantity,
    occurrence: supersedes?.data["occurrence"].text ?? identifier(), effective: date,
    input: source.id, status: "accepted", supersedes: supersedes?.id)
}

func conditionInputObservation(_ book: Workbook, _ id: String) throws -> Value {
  try drainInventoryCondition(book, id)["lastCompleteObservation"]
}

func conditionInputPages(_ book: Workbook, _ observation: String) throws -> [Value] {
  var entries: [Value] = []
  var cursor: String?
  repeat {
    let page = try book.inventoryConditionInputs(observation, after: cursor, limit: 50)
    entries += page["entries"].array
    cursor = page["nextCursor"].string
  } while cursor != nil
  return entries
}

func checkConditionInputs(at root: URL) {
  check("condition baseline excludes past triggers and exact change inspection remains read-only") {
    let (book, source) = try businessFixture(root, "InputsBaseline")
    try book.setOpeningBalance(
      subject: "parts", quantity: "20", effective: "2026-01-01", sourceID: source.id)
    _ = try conditionInputMove(book, source, "1")
    let id = try book.createInventoryCondition(
      subject: "parts", rule: inventoryConditionRule(), effectiveThrough: "2026-12-31",
      token: "create")["id"].text
    let baseline = try conditionInputObservation(book, id)
    try expect(
      baseline["changeInputs"]["coverage"].text == "baseline"
        && baseline["changeInputs"]["count"].int == 0)
    let movement = try conditionInputMove(book, source, "-15")
    let observed = try conditionInputObservation(book, id)
    let revision = try book.revision()
    let page = try book.inventoryConditionInputs(observed["id"].text)
    try expect(
      page["entries"].array.count == 1
        && page["entries"].array[0]["input"]["afterID"].text == movement.id)
    try expect(
      page["previousObservationID"] == baseline["id"]
        && page["previousCertainObservationID"] == baseline["id"])
    try expect(
      page["changeInputs"]["coverage"].text == "complete"
        && page["changeInputs"]["minimalCauseSet"] == .bool(false))
    try expect(
      page["changeInputs"]["automaticParents"].text == "not-resolved"
        && page["enabled"] == .bool(false) && page["execution"].text == "none")
    try expect(
      try book.revision() == revision && book.inventoryConditionInputs(observed["id"].text) == page)
    _ = try book.verify()
  }
  check(
    "unrelated subjects, estimates, drafts and technical controls do not invent relevant inputs"
  ) {
    let (book, source, id) = try conditionInputFixture(root, "Scope")
    _ = try book.movement(
      subject: "other", quantity: "-99", occurrence: "other", effective: "2026-01-02",
      input: source.id, status: "accepted")
    _ = try book.movement(
      subject: "parts", quantity: "-99", occurrence: "estimate", effective: "2026-01-02",
      input: source.id, meaning: "estimate", status: "accepted")
    _ = try book.movement(
      subject: "parts", quantity: "-99", occurrence: "draft", effective: "2026-01-02",
      input: source.id)
    let observation = try conditionInputObservation(book, id)
    try expect(
      observation["quantity"].text == "20" && observation["changeInputs"]["count"].int == 0)
    try expect(try conditionInputPages(book, observation["id"].text).isEmpty)
    _ = try book.verify()
  }
  check("same-quantity corrections and cross-scope withdrawal retain both exact versions") {
    let (book, source, id) = try conditionInputFixture(root, "Corrections")
    let original = try conditionInputMove(book, source, "-15")
    _ = try conditionInputObservation(book, id)
    let revised = try conditionInputMove(book, source, "-15", supersedes: original)
    let correction = try conditionInputObservation(book, id)
    let entry = try conditionInputPages(book, correction["id"].text)[0]
    try expect(
      entry["input"]["beforeID"].text == original.id && entry["input"]["afterID"].text == revised.id
    )
    let withdrawal = try book.addItem(
      category: "record", kind: "movement", title: "Different scope",
      data: .object(["subject": .string("other")]), status: "accepted", inputs: [source.id],
      supersedes: revised.id)
    let withdrawn = try conditionInputObservation(book, id)
    let input = try conditionInputPages(book, withdrawn["id"].text)[0]
    try expect(
      input["input"]["beforeID"].text == revised.id
        && input["input"]["afterID"].text == withdrawal.id)
    try expect(withdrawn["quantity"].text == "20")
    let renewed = try conditionInputMove(book, source, "-2")
    _ = try conditionInputObservation(book, id)
    let rejected = try book.addItem(
      category: "record", kind: "movement", title: "Rejected correction", data: .object([:]),
      status: "rejected", inputs: [source.id], supersedes: renewed.id)
    let rejection = try conditionInputObservation(book, id)
    let rejectedInput = try conditionInputPages(book, rejection["id"].text)[0]
    try expect(
      rejectedInput["input"]["beforeID"].text == renewed.id
        && rejectedInput["input"]["afterID"].text == rejected.id
        && rejection["quantity"].text == "20")
    _ = try book.verify()
  }
  check("same-Source opening-basis changes retain distinct immutable event coordinates") {
    let (book, source, id) = try conditionInputFixture(root, "Basis")
    _ = try book.mutation("synthetic.explicit-basis-correction") {
      try book.db.execute("UPDATE bases SET quantity='5' WHERE subject='parts'")
      return .null
    }
    let changed = try conditionInputObservation(book, id)
    let entry = try conditionInputPages(book, changed["id"].text)[0]
    try expect(entry["input"]["kind"].text == "basis-change")
    try expect(
      entry["input"]["beforeID"].text == source.id && entry["input"]["afterID"].text == source.id)
    let event = try book.conditionInputEvent(entry["input"]["eventID"].text)
    let payload = try Value.parse(event["payload"]!.text)
    try expect(
      payload["before"]["quantity"].text == "20" && payload["after"]["quantity"].text == "5")
    _ = try book.verify()
  }
  check("an atomic batch retains pending inputs across restart without exposing a partial set") {
    let (book, source, id) = try conditionInputFixture(root, "Pages")
    let baseline = try conditionInputObservation(book, id)
    _ = try book.mutation("synthetic.input-batch") {
      for n in 0..<205 {
        _ = try book.insertMovement(
          book.movementRequest(
            subject: "parts", quantity: n == 204 ? "190" : "-1", occurrence: "input-\(n)",
            effective: "2026-01-02", input: source.id, status: "accepted"))
      }
      return .null
    }
    let partial = try book.stepInventoryCondition(id, through: "2026-12-31", token: "partial")
    try expect(
      partial["lastCompleteObservation"] == baseline && partial["pendingOrdinal"].int == 99)
    try expect(
      try book.db.scalar(
        "SELECT count(*) FROM condition_pending_inputs WHERE consumer_id=?", [.string(id)]
      ).int == 100)
    try expect(try conditionInputPages(book, baseline["id"].text).isEmpty)
    let copy = try book.reconstruct(to: root.appendingPathComponent("InputPendingCopy.sevra"))
    _ = try copy.verify()
    let final = try conditionInputObservation(Workbook(book.url), id)
    let copied = try conditionInputObservation(copy, id)
    try expect(final["quantity"].text == "6" && final["changeInputs"]["count"].int == 205)
    try expect(try conditionInputPages(book, final["id"].text).count == 205)
    try expect(copied["changeInputs"] == final["changeInputs"])
    try expect(
      try book.db.scalar(
        "SELECT count(*) FROM condition_pending_inputs WHERE consumer_id=?", [.string(id)]
      ).int == 0)
    _ = try book.verify()
  }
  check("basis rebuild retains its whole batch change inputs through numeric paging") {
    let (book, source, id) = try conditionInputFixture(root, "Rebuild")
    _ = try book.mutation("synthetic.input-rebuild") {
      for n in 0..<105 {
        _ = try book.insertMovement(
          book.movementRequest(
            subject: "parts", quantity: "1", occurrence: "rebuild-input-\(n)",
            effective: "2026-01-02", input: source.id, status: "accepted"))
      }
      try book.db.execute("UPDATE bases SET quantity='30' WHERE subject='parts'")
      return .null
    }
    _ = try book.stepInventoryCondition(id, through: "2026-12-31", token: "one")
    let next = try book.stepInventoryCondition(id, through: "2026-12-31", token: "two")
    try expect(next["phase"].text == "rebuild")
    let observation = try conditionInputObservation(Workbook(book.url), id)
    let inputs = try conditionInputPages(book, observation["id"].text)
    try expect(inputs.count == 106 && observation["quantity"].text == "135")
    try expect(inputs.filter { $0["input"]["kind"].text == "basis-change" }.count == 1)
    _ = try book.verify()
  }
  check("future equal-time effect groups retain exact introducing events and activation instants") {
    let (book, source, id) = try conditionInputFixture(root, "Clock")
    _ = try book.mutation("synthetic.input-clock") {
      for n in 0..<105 {
        _ = try book.insertMovement(
          book.movementRequest(
            subject: "parts", quantity: n == 104 ? "104" : "-1", occurrence: "clock-input-\(n)",
            effective: "2030-01-01", input: source.id, status: "accepted"))
      }
      return .null
    }
    _ = try conditionInputObservation(book, id)
    let partial = try book.stepInventoryCondition(id, through: "2030-01-02", token: "clock")
    try expect(partial["phase"].text == "clock")
    _ = try drainInventoryCondition(Workbook(book.url), id, through: "2030-01-02")
    let clock = try book.inventoryConditionObservations(id, limit: 50)["observations"].array.map {
      $0["observation"]
    }.first { $0["effectiveThrough"].text.hasPrefix("2030-01-01") }!
    let entries = try conditionInputPages(book, clock["id"].text)
    try expect(entries.count == 105 && clock["quantity"].text == "20")
    try expect(
      entries.allSatisfy {
        $0["input"]["kind"].text == "effect-clock"
          && $0["input"]["effective"] == clock["effectiveThrough"]
      })
    _ = try book.verify()
  }
  check("future basis activation and unknown-gap recovery retain linked observation windows") {
    let (book, _, id) = try conditionInputFixture(root, "Unknown")
    let certain = try conditionInputObservation(book, id)
    _ = try book.mutation("synthetic.explicit-future-basis-correction") {
      try book.db.execute(
        "UPDATE bases SET quantity='5',effective=? WHERE subject='parts'",
        [.string(try BusinessTime.normalized("2030-01-01"))])
      return .null
    }
    let unknown = try conditionInputObservation(book, id)
    try expect(
      unknown["changeInputs"]["coverage"].text == "unknown-gap"
        && unknown["previousObservationID"] == certain["id"])
    _ = try book.stepInventoryCondition(id, through: "2030-01-01", token: "activate-future-basis")
    _ = try drainInventoryCondition(book, id, through: "2030-01-01")
    let known = try book.inventoryCondition(id)["lastCompleteObservation"]
    let entries = try conditionInputPages(book, known["id"].text)
    try expect(
      known["coverageGap"] == .bool(true) && known["changeInputs"]["coverage"].text == "unknown-gap"
    )
    try expect(
      known["previousObservationID"] == unknown["id"]
        && known["previousCertainObservationID"] == certain["id"])
    try expect(entries.count == 1 && entries[0]["input"]["kind"].text == "basis-clock")
    _ = try book.verify()
  }
  check("input paging rejects foreign cursors and malformed or cancelled requests") {
    let (book, source, id) = try conditionInputFixture(root, "Cursors")
    _ = try conditionInputMove(book, source, "-15")
    let first = try conditionInputObservation(book, id)
    let foreign = try conditionInputPages(book, first["id"].text)[0]["id"].text
    _ = try conditionInputMove(book, source, "1")
    let second = try conditionInputObservation(book, id)
    try refuses("condition_cursor") {
      _ = try book.inventoryConditionInputs(second["id"].text, after: foreign)
    }
    try refuses("condition_observation") { _ = try book.inventoryConditionInputs("missing") }
    try refuses("condition_input") { _ = try book.inventoryConditionInputs("") }
    try refuses("condition_limit") {
      _ = try book.inventoryConditionInputs(first["id"].text, limit: 51)
    }
    let cancellation = Cancellation()
    cancellation.cancel()
    try refuses("cancelled") {
      _ = try book.inventoryConditionInputs(first["id"].text, cancellation: cancellation)
    }
    let copy = try book.reconstruct(to: root.appendingPathComponent("InputCompleteCopy.sevra"))
    try expect(
      try copy.inventoryConditionInputs(first["id"].text)
        == book.inventoryConditionInputs(first["id"].text))
    _ = try copy.verify()
  }
  check(
    "publication cancellation rolls back pending and completed input rows before a stable retry"
  ) {
    let (book, source, id) = try conditionInputFixture(root, "Cancellation")
    _ = try conditionInputMove(book, source, "-15")
    let digest = try book.db.authorityDigest()
    let cancellation = Cancellation()
    try InventoryConditionPublicationProbe.$observer.withValue({ stage in
      if stage == .prepared { cancellation.cancel() }
    }) {
      try refuses("cancelled") {
        _ = try book.stepInventoryCondition(
          id, through: "2026-12-31", token: "cancel", cancellation: cancellation)
      }
    }
    try expect(try book.db.authorityDigest() == digest)
    let result = try book.stepInventoryCondition(id, through: "2026-12-31", token: "cancel")
    try expect(result["lastCompleteObservation"]["changeInputs"]["count"].int == 1)
    try expect(
      try book.stepInventoryCondition(id, through: "2026-12-31", token: "cancel") == result)
    _ = try book.verify()
  }
  checkConditionInputCorruption(at: root)
}
