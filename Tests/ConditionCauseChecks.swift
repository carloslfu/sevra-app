import Foundation

@testable import SevraCore

func createConditionCauseFixture(at url: URL) throws -> Value {
  let book = try Workbook.create(at: url, title: "Synthetic shared business roots")
  let opening = try book.recordBusinessObservation(title: "Opening count", token: "opening")
  try book.setOpeningBalance(
    subject: "parts", quantity: "20", effective: "2026-01-01", sourceID: opening.id)
  var consumers: [String] = []
  for index in 0..<2 {
    let id = try book.createInventoryCondition(
      subject: "parts", rule: inventoryConditionRule(),
      effectiveThrough: "2026-12-31", token: "condition-\(index)")["id"].text
    _ = try conditionInputObservation(book, id)
    consumers.append(id)
  }
  let source = try book.recordBusinessObservation(title: "Independent sale", token: "sale")
  let movement = try book.movement(
    subject: "parts", quantity: "-15", occurrence: "sale-1",
    effective: "2026-02-01", input: source.id)
  _ = try book.accept(movement.id, actor: .human("synthetic reviewer"))
  let observations = try consumers.map { try conditionInputObservation(book, $0)["id"] }
  return .object([
    "sourceID": .string(source.id), "consumerIDs": .array(consumers.map(Value.string)),
    "observationIDs": .array(observations),
  ])
}

func checkConditionCauses(at root: URL) {
  func trace(_ book: Workbook, _ id: String) throws -> Value {
    let value = try book.inventoryConditionCauses(id)
    try expect(value["dispatchEligibility"].text == "not-evaluated")
    try expect(
      value["budgetEnforcement"].text == "not-enabled"
        && value["inputAuthenticity"].text == "not-verified")
    try expect(
      value["minimalCauseSet"] == .bool(false) && value["execution"].text == "none"
        && value["enabled"] == .bool(false))
    return value
  }
  func fixture(_ name: String) throws -> (Workbook, Value) {
    let url = root.appendingPathComponent("ConditionCause-" + name + ".sevra")
    let data = try createConditionCauseFixture(at: url)
    return (try Workbook(url), data)
  }
  check("two consumers responding to one accepted business change share one original root") {
    let (book, data) = try fixture("Shared")
    let a = try trace(book, data["observationIDs"].array[0].text)
    let b = try trace(book, data["observationIDs"].array[1].text)
    try expect(a["resolution"].text == "resolved" && b["resolution"].text == "resolved")
    try expect(a["rootIDs"] == b["rootIDs"] && a["rootIDs"].array.count == 1)
    try expect(a["consumerID"] != b["consumerID"] && a["inputSetHash"] != b["inputSetHash"])
    try expect(a["declaredInputs"].array.map { $0["sourceID"] } == [data["sourceID"]])
    try expect(
      a["automaticParentRunIDs"].array.isEmpty && a["undeclaredOriginalInputIDs"].array.isEmpty)
  }
  check("republishing or correcting the same original does not mint another independent root") {
    let (book, data) = try fixture("Republish")
    let old = try trace(book, data["observationIDs"].array[0].text)
    _ = try book.movement(
      subject: "parts", quantity: "1", occurrence: "sale-2", effective: "2026-03-01",
      input: data["sourceID"].text, status: "accepted")
    let observation = try conditionInputObservation(book, data["consumerIDs"].array[0].text)
    let new = try trace(book, observation["id"].text)
    try expect(
      new["rootIDs"] == old["rootIDs"] && new["knowledgeBatchID"] != old["knowledgeBatchID"])
    try expect(new["resolution"].text == "resolved")
  }
  check("human review and withdrawal Sources reference their exact proposal without fresh origins")
  {
    let (book, data) = try fixture("Review")
    let source = data["sourceID"].text
    let draft = try book.movement(
      subject: "parts", quantity: "1", occurrence: "withdraw",
      effective: "2026-02-01", input: source)
    let withdrawn = try book.withdrawDraft(draft.id, actor: .human("synthetic"))
    let origins = try book.businessOrigins(inputs: [withdrawn.id])
    try expect(origins["originalInputCandidates"].array == [.string(source)])
    try expect(origins["unclassifiedOrigins"].array.isEmpty)
    _ = try book.verify()
  }
  check("automatic correction with an explicit independent observation retains both root kinds") {
    let url = root.appendingPathComponent("ConditionCause-Mixed.sevra")
    let data = try createAutomaticAncestryFixture(at: url)
    let book = try Workbook(url)
    let count = try book.recordBusinessObservation(title: "Independent opening count")
    try book.setOpeningBalance(
      subject: "parts", quantity: "20", effective: "2026-01-01", sourceID: count.id)
    let consumer = try book.createInventoryCondition(
      subject: "parts", rule: inventoryConditionRule(),
      effectiveThrough: "2026-12-31", token: "consumer")["id"].text
    _ = try conditionInputObservation(book, consumer)
    let independent = try book.recordBusinessObservation(title: "Independent adjustment")
    let old = try book.item(data["acceptedID"].text)
    let correction = try book.movement(
      subject: "parts", quantity: "-15", occurrence: old.data["occurrence"].text,
      effective: old.data["effective"].text, input: independent.id, supersedes: old.id)
    _ = try book.accept(correction.id, actor: .human("synthetic"))
    let observation = try conditionInputObservation(book, consumer)
    let value = try trace(book, observation["id"].text)
    try expect(
      value["resolution"].text == "resolved" && value["rootIDs"].array.count == 2, try value.json())
    try expect(value["automaticParentRunIDs"].array == [data["runID"]])
    try expect(
      value["inheritedRootIDs"] == book.automationCausality(data["runID"].text)["origin"]["roots"])
    try expect(
      value["independentRootIDs"].array.count == 1
        && value["declaredInputs"].array[0]["sourceID"] == .string(independent.id))
    _ = try book.verify()
  }
  check("automatically authored controls do not contaminate a new manual business origin") {
    let url = root.appendingPathComponent("ConditionCause-Control.sevra")
    let data = try createAutomaticAncestryFixture(at: url)
    let book = try Workbook(url)
    let independent = try book.recordBusinessObservation(title: "Independent delivery")
    try book.setOpeningBalance(
      subject: "parts", quantity: "20", effective: "2026-01-01", sourceID: independent.id)
    let consumer = try book.createInventoryCondition(
      subject: "parts", rule: inventoryConditionRule(),
      effectiveThrough: "2026-12-31", token: "consumer")["id"].text
    _ = try conditionInputObservation(book, consumer)
    let action = try book.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.receivingDefinition(),
      inputs: [data["acceptedID"].text])
    var arguments = data["arguments"].object
    arguments["evidence"] = .string(independent.id)
    arguments["delivery"] = .string("manual independent delivery")
    let preview = try book.previewApplicationAction(action.id, arguments: .object(arguments))
    let result = try book.invokeApplicationAction(
      action.id, arguments: .object(arguments), preview: preview, token: "manual")
    _ = try book.accept(result["proposals"].array[0].text)
    let observation = try conditionInputObservation(book, consumer)
    let value = try trace(book, observation["id"].text)
    try expect(value["resolution"].text == "resolved" && value["rootIDs"].array.count == 1)
    try expect(
      value["automaticParentRunIDs"].array.isEmpty && value["inheritedRootIDs"].array.isEmpty)
    try expect(value["declaredInputs"].array.map { $0["sourceID"] } == [.string(independent.id)])
  }
  check("unregistered original labels block complete cause resolution instead of inventing a root")
  {
    let (book, source, consumer) = try conditionInputFixture(root, "CauseUnknown")
    _ = try conditionInputMove(book, source, "-15")
    let observation = try conditionInputObservation(book, consumer)
    let value = try trace(book, observation["id"].text)
    try expect(value["resolution"].text == "blocked")
    try expect(value["undeclaredOriginalInputIDs"].array == [.string(source.id)])
    try expect(value["blockedReasons"].array.contains(.string("undeclared-original-inputs")))
    try expect(value["rootIDs"].array.isEmpty)
  }
  check("effective-time activation keeps its introducing original root across clocks and consumers")
  {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ConditionCause-Clock.sevra"), title: "Clock")
    let source = try book.recordBusinessObservation(title: "Independent count")
    try book.setOpeningBalance(
      subject: "parts", quantity: "20", effective: "2026-01-01", sourceID: source.id)
    let consumer = try book.createInventoryCondition(
      subject: "parts", rule: inventoryConditionRule(),
      effectiveThrough: "2026-02-01", token: "consumer")["id"].text
    _ = try drainInventoryCondition(book, consumer, through: "2026-02-01")[
      "lastCompleteObservation"]
    _ = try book.movement(
      subject: "parts", quantity: "-15", occurrence: "future", effective: "2026-03-01",
      input: source.id, status: "accepted")
    let before = try drainInventoryCondition(book, consumer, through: "2026-02-01")[
      "lastCompleteObservation"]
    let original = try trace(book, before["id"].text)
    _ = try book.stepInventoryCondition(consumer, through: "2026-04-01", token: "advance")
    _ = try drainInventoryCondition(book, consumer, through: "2026-04-01")[
      "lastCompleteObservation"]
    let observations = try book.inventoryConditionObservations(consumer, limit: 50)["observations"]
      .array
    let clockObservations = observations.map { $0["observation"] }.filter {
      $0["effectiveThrough"].text.hasPrefix("2026-03-01")
    }
    guard let clock = clockObservations.last else {
      throw SevraError("test", "Missing clock observation")
    }
    let value = try trace(book, clock["id"].text)
    try expect(value["rootIDs"] == original["rootIDs"] && value["resolution"].text == "resolved")
  }
  check(
    "eight roots resolve and a ninth remains visibly blocked without a partial dispatchable set"
  ) {
    let (book, data) = try fixture("RootLimit")
    let consumer = data["consumerIDs"].array[0].text
    for count in [8, 9] {
      let sources = try (0..<count).map {
        try book.recordBusinessObservation(title: "Independent \(count)-\($0)")
      }
      _ = try book.mutation("synthetic.many-roots") {
        for source in sources {
          _ = try book.insertMovement(
            book.movementRequest(
              subject: "parts", quantity: "1",
              occurrence: identifier(), effective: "2026-02-01", input: source.id,
              status: "accepted"))
        }
        return .null
      }
      let observation = try conditionInputObservation(book, consumer)
      let value = try trace(book, observation["id"].text)
      try expect(value["rootIDs"].array.count == count)
      try expect(value["resolution"].text == (count == 8 ? "resolved" : "blocked"))
      try expect(
        value["blockedReasons"].array.contains(.string("more-than-eight-roots")) == (count == 9))
    }
  }
  check("cause inspection is read only and reconstructs identical shared identities inertly") {
    let (book, data) = try fixture("Rebuild")
    let observation = data["observationIDs"].array[0].text
    let before = try book.db.authorityDigest()
    let value = try trace(book, observation)
    let copy = try book.reconstruct(to: root.appendingPathComponent("ConditionCauseCopy.sevra"))
    try expect(try trace(copy, observation) == value && book.db.authorityDigest() == before)
    try expect(try copy.db.scalar("SELECT count(*) FROM automatic_admissions").int == 0)
    _ = try copy.verify()
  }
  check("cancelled cause inspection and malformed coordinates refuse without changing state") {
    let (book, data) = try fixture("Cancel")
    let cancelled = Cancellation()
    cancelled.cancel()
    let before = try book.db.authorityDigest()
    try refuses("cancelled") {
      _ = try book.inventoryConditionCauses(
        data["observationIDs"].array[0].text, cancellation: cancelled)
    }
    try refuses("condition_input") { _ = try book.inventoryConditionCauses("") }
    try refuses("condition_input") {
      _ = try book.inventoryConditionCauses(String(repeating: "x", count: 257))
    }
    try expect(try book.db.authorityDigest() == before)
  }
}
