import Foundation

@testable import SevraCore

func inventoryConditionRule(_ subject: String = "parts", threshold: String = "10") -> Value {
  .object([
    "policy": .string("native-condition-v1"), "scope": .string("inventory:" + subject),
    "operator": .string("<"), "threshold": .string(threshold),
  ])
}

func drainInventoryCondition(_ book: Workbook, _ id: String, through: String = "2026-12-31") throws
  -> Value
{
  for _ in 0..<1000 {
    let status = try book.inventoryCondition(id)
    if status["hasMore"] == .bool(false) || status["backpressure"] == .bool(true) { return status }
    _ = try book.stepInventoryCondition(id, through: through, token: identifier())
  }
  throw SevraError("test", "The condition did not finish its bounded pages.")
}

func checkInventoryConditions(at root: URL) {
  func fixture(_ name: String, quantity: String = "20", through: String = "2026-12-31") throws -> (
    Workbook, Item, String
  ) {
    let (book, source) = try businessFixture(root, "InventoryCondition" + name)
    try book.setOpeningBalance(
      subject: "parts", quantity: quantity, effective: "2026-01-01", sourceID: source.id)
    let consumer = try book.createInventoryCondition(
      subject: "parts", rule: inventoryConditionRule(), effectiveThrough: through,
      token: "create-condition")
    return (book, source, consumer["id"].text)
  }
  func move(_ book: Workbook, _ source: Item, _ quantity: String, date: String = "2026-01-02")
    throws -> Item
  {
    try book.movement(
      subject: "parts", quantity: quantity, occurrence: identifier(), effective: date,
      input: source.id, status: "accepted")
  }
  func observations(_ book: Workbook, _ id: String) throws -> [Value] {
    try book.inventoryConditionObservations(id, limit: 50)["observations"].array.map {
      $0["observation"]
    }
  }
  check(
    "condition establishes exact captured baseline without firing already true or earlier crossings"
  ) {
    let (book, source, id) = try fixture("Baseline", quantity: "5")
    _ = try move(book, source, "-1")
    let state = try drainInventoryCondition(book, id)
    let rows = try observations(book, id)
    try expect(state["established"] == .bool(true) && state["pendingCandidates"].int == 0)
    try expect(rows[0]["disposition"].text == "baseline" && rows[0]["quantity"].text == "5")
    try expect(rows[1]["quantity"].text == "4" && rows[1]["disposition"].text == "unchanged")
    try expect(state["enabled"] == .bool(false) && state["execution"].text == "inert")
    try expect(try !book.item(state["sourceID"].text).isBusinessEvidence)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("condition preserves intermediate batches and distinct recrossings between polls") {
    let (book, source, id) = try fixture("Crossings")
    _ = try drainInventoryCondition(book, id)
    for quantity in ["-15", "1", "10", "-10"] { _ = try move(book, source, quantity) }
    let state = try drainInventoryCondition(book, id)
    try expect(state["pendingCandidates"].int == 2)
    let rows = try observations(book, id)
    try expect(
      rows.map { $0["disposition"].text } == [
        "baseline", "transition", "unchanged", "reset", "transition",
      ])
    try expect(Set(rows.compactMap { $0["candidateID"].string }).count == 2)
  }
  check("condition bootstrap and large atomic batch resume without page-boundary observations") {
    let (book, source, id) = try fixture("LargeAtomic")
    _ = try drainInventoryCondition(book, id)
    let before = try book.inventoryCondition(id)["lastCompleteObservation"]
    _ = try book.mutation("synthetic.condition-batch", token: "large-condition-batch") {
      for n in 0..<205 {
        let request = try book.movementRequest(
          subject: "parts", quantity: n == 204 ? "190" : "-1", occurrence: "atomic-\(n)",
          effective: "2026-01-02", input: source.id, status: "accepted")
        _ = try book.insertMovement(request)
      }
      return .null
    }
    let first = try book.stepInventoryCondition(id, through: "2026-12-31", token: "first-page")
    try expect(first["phase"].text == "batch" && first["pendingOrdinal"].int == 99)
    try expect(first["lastCompleteObservation"] == before && first["pendingCandidates"].int == 0)
    let reopened = try Workbook(book.url)
    let second = try reopened.stepInventoryCondition(
      id, through: "2026-12-31", token: "second-page")
    try expect(second["phase"].text == "batch" && second["lastCompleteObservation"] == before)
    let finished = try drainInventoryCondition(reopened, id)
    try expect(
      finished["pendingCandidates"].int == 1
        && finished["lastCompleteObservation"]["quantity"].text == "6")
    try expect(try observations(book, id).count == 2)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check(
    "condition bootstrap captures only its anchor while later accepted changes remain successors"
  ) {
    let (book, source) = try businessFixture(root, "ConditionBootstrap")
    try book.setOpeningBalance(
      subject: "parts", quantity: "200", effective: "2026-01-01", sourceID: source.id)
    _ = try book.mutation("synthetic.bootstrap") {
      for n in 0..<105 {
        _ = try book.insertMovement(
          book.movementRequest(
            subject: "parts", quantity: "-1", occurrence: "bootstrap-\(n)", effective: "2026-01-02",
            input: source.id, status: "accepted"))
      }
      return .null
    }
    let id = try book.createInventoryCondition(
      subject: "parts", rule: inventoryConditionRule(threshold: "90"),
      effectiveThrough: "2026-12-31", token: "bootstrap-create")["id"].text
    _ = try book.stepInventoryCondition(id, through: "2026-12-31", token: "bootstrap-first")
    _ = try move(book, source, "-10")
    let state = try drainInventoryCondition(Workbook(book.url), id)
    let rows = try observations(book, id)
    try expect(
      rows.first?["quantity"].text == "95" && rows.first?["disposition"].text == "baseline")
    try expect(state["pendingCandidates"].int == 1 && rows.last?["quantity"].text == "85")
  }
  check(
    "condition exact corrections withdraw old effects across scopes and ignore non-actual claims"
  ) {
    let (book, source, id) = try fixture("Corrections")
    _ = try drainInventoryCondition(book, id)
    let first = try move(book, source, "-15")
    _ = try drainInventoryCondition(book, id)
    _ = try book.movement(
      subject: "parts", quantity: "-99", occurrence: "estimate", effective: "2026-01-02",
      input: source.id, meaning: "estimate", status: "accepted")
    _ = try book.movement(
      subject: "parts", quantity: "-99", occurrence: "draft", effective: "2026-01-02",
      input: source.id)
    _ = try book.addItem(
      category: "record", kind: "movement", title: "No exact effect",
      data: .object(["subject": .string("other")]), status: "accepted", inputs: [source.id],
      supersedes: first.id)
    let state = try drainInventoryCondition(book, id)
    try expect(
      state["lastCompleteObservation"]["quantity"].text == "20"
        && state["pendingCandidates"].int == 1)
    let oracle = try book.inventoryAtBusinessBatch(
      state["cursorID"].text, subject: "parts", effectiveThrough: "2026-12-31")
    try expect(oracle["quantity"] == state["lastCompleteObservation"]["quantity"])
  }
  check("condition handles future effect dates without new workbook business edits") {
    let (book, source, id) = try fixture("Future", through: "2026-12-31")
    _ = try move(book, source, "-15", date: "2030-01-01")
    _ = try move(book, source, "15", date: "2030-01-02")
    _ = try move(book, source, "-15", date: "2030-01-03")
    _ = try drainInventoryCondition(book, id)
    let horizon = try book.stepInventoryCondition(
      id, through: "2030-01-04", token: "future-horizon")
    try expect(horizon["lastCompleteObservation"]["effectiveThrough"].text.hasPrefix("2030-01-01"))
    let state = try drainInventoryCondition(book, id, through: "2030-01-04")
    try expect(
      state["pendingCandidates"].int == 2
        && state["lastCompleteObservation"]["quantity"].text == "5")
    let transitions = try observations(book, id).filter { $0["disposition"].text == "transition" }
    try expect(
      transitions.map { String($0["effectiveThrough"].text.prefix(10)) } == [
        "2030-01-01", "2030-01-03",
      ])
  }
  check("condition equal-time future groups are atomic across pages") {
    let (book, source, id) = try fixture("ClockAtomic", through: "2026-12-31")
    _ = try book.mutation("synthetic.clock-group") {
      for n in 0..<105 {
        _ = try book.insertMovement(
          book.movementRequest(
            subject: "parts", quantity: n == 104 ? "104" : "-1", occurrence: "clock-\(n)",
            effective: "2030-01-01", input: source.id, status: "accepted"))
      }
      return .null
    }
    _ = try drainInventoryCondition(book, id)
    let before = try book.inventoryCondition(id)["lastCompleteObservation"]
    let partial = try book.stepInventoryCondition(id, through: "2030-01-02", token: "clock-partial")
    try expect(partial["phase"].text == "clock" && partial["lastCompleteObservation"] == before)
    let state = try drainInventoryCondition(Workbook(book.url), id, through: "2030-01-02")
    try expect(
      state["pendingCandidates"].int == 0
        && state["lastCompleteObservation"]["quantity"].text == "20")
  }
  check("condition missing and future basis are unknown and first certain result is a baseline") {
    let (book, source) = try businessFixture(root, "ConditionUnknown")
    let id = try book.createInventoryCondition(
      subject: "parts", rule: inventoryConditionRule(), effectiveThrough: "2026-12-31",
      token: "unknown-create")["id"].text
    let unknown = try drainInventoryCondition(book, id)
    try expect(unknown["lastCompleteObservation"]["quantity"] == .null)
    try book.setOpeningBalance(
      subject: "parts", quantity: "5", effective: "2030-01-01", sourceID: source.id)
    let future = try drainInventoryCondition(book, id)
    try expect(future["lastCompleteObservation"]["reason"].text == "basis_not_effective")
    _ = try book.stepInventoryCondition(id, through: "2030-01-02", token: "basis-clock")
    let state = try drainInventoryCondition(book, id, through: "2030-01-02")
    try expect(state["pendingCandidates"].int == 0)
    let certain = try observations(book, id).filter { $0["known"] == .bool(true) }
    try expect(
      certain[0]["disposition"].text == "baseline" && certain[0]["coverageGap"] == .bool(true))
  }
  check("condition unknown gap preserves false truth and reports an observed crossing") {
    let (book, source, id) = try fixture("Gap")
    _ = try drainInventoryCondition(book, id)
    _ = try book.mutation("synthetic.remove-basis") {
      try book.db.execute("DELETE FROM bases WHERE subject='parts'")
      return .null
    }
    _ = try drainInventoryCondition(book, id)
    try book.setOpeningBalance(
      subject: "parts", quantity: "5", effective: "2026-01-01", sourceID: source.id)
    let state = try drainInventoryCondition(book, id)
    try expect(
      state["pendingCandidates"].int == 1
        && state["lastCompleteObservation"]["coverageGap"] == .bool(true))
  }
  check("condition basis changes rebuild current projection with exact immutable lineage") {
    let (book, source, id) = try fixture("BasisRebuild")
    _ = try move(book, source, "-2")
    _ = try move(book, source, "-3", date: "2026-02-02")
    _ = try drainInventoryCondition(book, id)
    _ = try book.mutation("synthetic.replace-basis") {
      try book.db.execute(
        "UPDATE bases SET quantity='30',effective=? WHERE subject='parts'",
        [.string(BusinessTime.normalized("2026-02-01"))])
      return .null
    }
    let state = try drainInventoryCondition(book, id)
    try expect(state["lastCompleteObservation"]["quantity"].text == "27")
    try expect(state["lastCompleteObservation"]["basis"]["inputID"].text == source.id)
    let oracle = try book.inventoryAtBusinessBatch(
      state["cursorID"].text, subject: "parts", effectiveThrough: "2026-12-31")
    try expect(oracle["quantity"] == state["lastCompleteObservation"]["quantity"])
  }
  check("condition requests retry and read-only status survive inert reconstruction") {
    let (book, source, id) = try fixture("Reconstruction")
    _ = try drainInventoryCondition(book, id)
    _ = try move(book, source, "-15")
    let first = try book.stepInventoryCondition(id, through: "2026-12-31", token: "exact-step")
    try expect(
      try book.stepInventoryCondition(id, through: "2026-12-31", token: "exact-step") == first)
    let digest = try book.db.authorityDigest()
    _ = try book.inventoryCondition(id)
    _ = try book.inventoryConditionObservations(id)
    try expect(try book.db.authorityDigest() == digest)
    let restored = try book.reconstruct(to: root.appendingPathComponent("ConditionRestored.sevra"))
    try expect(try restored.inventoryCondition(id) == book.inventoryCondition(id))
    try expect(
      try restored.inventoryConditionObservations(id) == book.inventoryConditionObservations(id))
    try expect(try restored.db.scalar("SELECT count(*) FROM automation_activations").int == 0)
    try expect(try restored.verify()["ok"] == .bool(true))
  }
  check("condition precision failure and publication interruption leave no partial result") {
    let (book, source, id) = try fixture(
      "Precision", quantity: "99999999999999999999999999999999999999")
    _ = try drainInventoryCondition(book, id)
    _ = try move(book, source, "0.1")
    let before = try book.inventoryCondition(id)
    let digest = try book.db.authorityDigest()
    try refuses("condition_precision") {
      _ = try book.stepInventoryCondition(id, through: "2026-12-31", token: "lossy-step")
    }
    try expect(try book.db.authorityDigest() == digest && book.inventoryCondition(id) == before)
    let (other, input, otherID) = try fixture("Rollback")
    _ = try drainInventoryCondition(other, otherID)
    _ = try move(other, input, "-15")
    let initial = try other.db.authorityDigest()
    try refuses("synthetic-interrupt") {
      _ = try InventoryConditionPublicationProbe.$observer.withValue({ stage in
        if stage == .prepared { throw SevraError("synthetic-interrupt", "Stop before publication") }
      }) {
        try other.stepInventoryCondition(otherID, through: "2026-12-31", token: "interrupted-step")
      }
    }
    try expect(try other.db.authorityDigest() == initial)
    try expect(try drainInventoryCondition(other, otherID)["pendingCandidates"].int == 1)
  }
  check("condition pending capacity holds exact cursor until explicit dismissal without coalescing")
  {
    let (book, source, id) = try fixture("Capacity")
    _ = try drainInventoryCondition(book, id)
    for _ in 0..<101 {
      _ = try move(book, source, "-15")
      _ = try move(book, source, "15")
    }
    let blocked = try drainInventoryCondition(book, id)
    try expect(
      blocked["pendingCandidates"].int == 100 && blocked["backpressure"] == .bool(true),
      "Expected capacity block: \(blocked)")
    let cursor = blocked["cursorID"]
    let retry = try book.stepInventoryCondition(id, through: "2026-12-31", token: "still-full")
    try expect(
      retry["cursorID"] == cursor
        && retry["lastCompleteObservation"] == blocked["lastCompleteObservation"],
      "Blocked retry changed complete observation")
    let candidate = try book.inventoryConditionObservations(id, limit: 50)["observations"].array
      .first { $0["candidateID"] != .null }!["candidateID"].text
    let dismissal = try book.dismissInventoryConditionCandidate(
      candidate, reason: "Reviewed and dismissed", token: "dismiss-candidate")
    try expect(
      try book.dismissInventoryConditionCandidate(
        candidate, reason: "Reviewed and dismissed", token: "dismiss-candidate") == dismissal)
    let done = try drainInventoryCondition(book, id)
    try expect(
      done["pendingCandidates"].int == 100 && done["hasMore"] == .bool(false),
      "Expected completed successor: \(done)")
    try expect(
      try book.db.scalar(
        "SELECT count(*) FROM condition_candidates WHERE consumer_id=?", [.string(id)]
      ).int == 101, "Expected 101 retained candidates")
  }
  check("atomic basis replacement avoids arithmetic against the superseded opening basis") {
    let (book, source, id) = try fixture(
      "AtomicBasisPrecision", quantity: "99999999999999999999999999999999999999")
    _ = try drainInventoryCondition(book, id)
    _ = try book.mutation("synthetic.atomic-new-basis") {
      _ = try book.insertMovement(
        book.movementRequest(
          subject: "parts", quantity: "0.1", occurrence: "atomic-basis-fraction",
          effective: "2026-01-02", input: source.id, status: "accepted"))
      try book.db.execute("UPDATE bases SET quantity='0' WHERE subject='parts'")
      return .null
    }
    let state = try drainInventoryCondition(book, id)
    try expect(
      state["lastCompleteObservation"]["quantity"].text == "0.1"
        && state["pendingCandidates"].int == 1)
    try expect(
      try book.inventoryAtBusinessBatch(
        state["cursorID"].text, subject: "parts", effectiveThrough: "2026-12-31")["quantity"].text
        == "0.1")
  }
  check("condition basis rebuild resumes a saved projection page without publishing partial sums") {
    let (book, source, id) = try fixture("RebuildPages")
    _ = try book.mutation("synthetic.rebuild-effects") {
      for n in 0..<205 {
        _ = try book.insertMovement(
          book.movementRequest(
            subject: "parts", quantity: "1", occurrence: "rebuild-\(n)", effective: "2026-01-02",
            input: source.id, status: "accepted"))
      }
      return .null
    }
    let before = try drainInventoryCondition(book, id)["lastCompleteObservation"]
    _ = try book.mutation("synthetic.rebuild-basis") {
      try book.db.execute("UPDATE bases SET quantity='30' WHERE subject='parts'")
      return .null
    }
    let pending = try book.stepInventoryCondition(id, through: "2026-12-31", token: "rebuild-start")
    try expect(pending["phase"].text == "rebuild" && pending["lastCompleteObservation"] == before)
    let page = try book.stepInventoryCondition(id, through: "2026-12-31", token: "rebuild-page")
    try expect(page["phase"].text == "rebuild" && page["lastCompleteObservation"] == before)
    let state = try drainInventoryCondition(Workbook(book.url), id)
    try expect(state["lastCompleteObservation"]["quantity"].text == "235")
    try expect(
      try book.inventoryAtBusinessBatch(
        state["cursorID"].text, subject: "parts", effectiveThrough: "2026-12-31")["quantity"].text
        == "235")
  }
  check(
    "condition clock eligibility precedes later knowledge and never backdates a retrospective correction"
  ) {
    let (book, source) = try businessFixture(root, "ConditionClockOrder")
    try book.setOpeningBalance(
      subject: "parts", quantity: "20", effective: "2026-01-01", sourceID: source.id)
    _ = try FixtureContext.$current.withValue(
      FixtureContext(seed: 20031, date: "2026-01-02T00:00:00Z")
    ) {
      try move(book, source, "-15", date: "2026-01-20")
    }
    let id = try book.createInventoryCondition(
      subject: "parts", rule: inventoryConditionRule(), effectiveThrough: "2026-01-02",
      token: "ordered-create")["id"].text
    _ = try drainInventoryCondition(book, id, through: "2026-01-02")
    _ = try FixtureContext.$current.withValue(
      FixtureContext(seed: 20032, date: "2026-02-01T00:00:00Z")
    ) {
      try move(book, source, "15", date: "2026-01-21")
    }
    _ = try book.stepInventoryCondition(id, through: "2026-03-01", token: "ordered-clock")
    _ = try drainInventoryCondition(book, id, through: "2026-03-01")
    let rows = try observations(book, id)
    try expect(
      rows[1]["disposition"].text == "transition"
        && rows[1]["effectiveThrough"].text.hasPrefix("2026-01-20"))
    try expect(
      rows[2]["disposition"].text == "reset"
        && rows[2]["effectiveThrough"].text.hasPrefix("2026-02-01"))
  }
  check("condition cancels a real SQLite lock without retaining a partial cursor") {
    let (book, _, id) = try fixture("Locked")
    let before = try book.inventoryCondition(id)
    let other = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    try other.execute("BEGIN EXCLUSIVE")
    defer { _ = try? other.execute("ROLLBACK") }
    let control = Cancellation()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { control.cancel() }
    let started = ProcessInfo.processInfo.systemUptime
    try refuses("cancelled") {
      _ = try book.stepInventoryCondition(
        id, through: "2026-12-31", token: "locked-step", cancellation: control)
    }
    try expect(ProcessInfo.processInfo.systemUptime - started < 1)
    try other.execute("ROLLBACK")
    try expect(try book.inventoryCondition(id) == before)
  }
  check("condition input, cursor, horizon and cancellation refusals preserve state") {
    let (book, _, id) = try fixture("Refusals")
    _ = try drainInventoryCondition(book, id)
    let digest = try book.db.authorityDigest()
    try refuses("condition_clock") {
      _ = try book.stepInventoryCondition(id, through: "2025-01-01", token: "backwards")
    }
    try refuses("condition_cursor") {
      _ = try book.inventoryConditionObservations(id, after: "foreign")
    }
    try refuses("condition_limit") { _ = try book.inventoryConditionObservations(id, limit: 51) }
    try refuses("condition_scope") {
      _ = try book.createInventoryCondition(
        subject: "other", rule: inventoryConditionRule(), effectiveThrough: "2026-12-31",
        token: "wrong-scope")
    }
    let cancellation = Cancellation()
    cancellation.cancel()
    try refuses("cancelled") {
      _ = try book.stepInventoryCondition(
        id, through: "2026-12-31", token: "cancelled", cancellation: cancellation)
    }
    try expect(try book.db.authorityDigest() == digest)
  }
}

func inventoryConditionDeathWorker(_ path: String, consumer: String, stage: String) throws {
  let book = try Workbook(URL(fileURLWithPath: path))
  try require(["prepared", "committed"].contains(stage), "test", "Choose a publication boundary.")
  let observer: @Sendable (InventoryConditionPublicationProbe.Stage) throws -> Void = { boundary in
    if (stage == "prepared" && boundary == .prepared)
      || (stage == "committed" && boundary == .committed)
    {
      print("CONDITION_PUBLICATION_" + stage)
      fflush(stdout)
      while true { Thread.sleep(forTimeInterval: 1) }
    }
  }
  _ = try InventoryConditionPublicationProbe.$observer.withValue(observer) {
    try book.stepInventoryCondition(consumer, through: "2026-12-31", token: "condition-death-step")
  }
}

func checkInventoryConditionLimit(at root: URL) {
  check("incremental condition retains10000 effects and refuses10001 without a partial observation")
  {
    let (book, source) = try businessFixture(root, "ConditionProjectionLimit")
    try book.setOpeningBalance(
      subject: "parts", quantity: "20", effective: "2026-01-01", sourceID: source.id)
    let id = try book.createInventoryCondition(
      subject: "parts", rule: inventoryConditionRule(), effectiveThrough: "2026-12-31",
      token: "limit-create")["id"].text
    _ = try drainInventoryCondition(book, id)
    for batch in 0..<10 {
      _ = try book.mutation("synthetic.condition-limit", token: "condition-limit-\(batch)") {
        for n in 0..<1000 {
          _ = try book.insertMovement(
            book.movementRequest(
              subject: "parts", quantity: "1", occurrence: "limit-\(batch)-\(n)",
              effective: "2026-01-02", input: source.id, status: "accepted"))
        }
        return .null
      }
    }
    let complete = try drainInventoryCondition(book, id)
    try expect(complete["lastCompleteObservation"]["quantity"].text == "10020")
    _ = try book.movement(
      subject: "parts", quantity: "1", occurrence: "limit-overflow", effective: "2026-01-02",
      input: source.id, status: "accepted")
    let digest = try book.db.authorityDigest()
    try refuses("condition_projection_limit") {
      _ = try book.stepInventoryCondition(id, through: "2026-12-31", token: "limit-overflow-step")
    }
    try expect(try book.db.authorityDigest() == digest)
    try expect(
      try book.inventoryCondition(id)["lastCompleteObservation"]
        == complete["lastCompleteObservation"])
  }
}
