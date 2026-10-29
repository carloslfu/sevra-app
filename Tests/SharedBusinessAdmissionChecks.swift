import Foundation

@testable import SevraCore

func checkSharedBusinessAdmissions(at directory: URL) {
  func fixture(_ name: String) throws -> CausalFixture {
    try CausalFixture(directory.appendingPathComponent("SharedAdmissions-" + name + ".sevra"))
  }
  check("unrelated automatic targets share one declared business root and its charges") {
    let f = try fixture("Shared")
    let input = try f.book.recordBusinessObservation(title: "One original delivery")
    let first = try f.admit(f.initial, independentInputs: [input.id, input.id])
    let second = try f.admit(independentInputs: [input.id])
    let a = try f.book.automationCausality(first.id)
    let b = try f.book.automationCausality(second.id)
    try expect(a["origin"]["roots"] == b["origin"]["roots"])
    try expect(a["origin"]["independentInputs"] == .array([.string(input.id)]))
    try expect(a["origin"]["depth"].int == 1 && b["origin"]["parents"].array.isEmpty)
    try expect(a["rootCharges"].array[0]["admittedRuns"].int == 2)
    try expect(try f.book.db.scalar("SELECT count(*) FROM automatic_roots").int == 1)
    try expectInputRole(
      f.book, child: f.book.workflowRun(second.id)["source_id"].text, parent: input.id, roles: 1)
    _ = try f.book.verify()
  }
  check("several declared Sources in one atomic input use one persisted root across targets") {
    let f = try fixture("Atomic")
    var sources: [String] = []
    _ = try f.book.mutation("synthetic.shared-input") {
      for index in 0..<2 {
        let source = try f.book.insertItem(
          category: "source", kind: "observation", title: "Observation\(index)", text: "",
          data: .null,
          meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
          transformation: "synthetic")
        try f.book.declareNewBusinessInput(source, kind: "observation")
        sources.append(source)
      }
      return .null
    }
    let a = try f.admit(independentInputs: [sources[0]])
    let b = try f.admit(independentInputs: [sources[1]])
    let c = try f.admit(independentInputs: sources)
    let trace = try f.book.automationCausality(c.id)
    try expect(trace["rootCharges"].array.count == 1)
    try expect(trace["rootCharges"].array[0]["admittedRuns"].int == 3)
    try expect(try f.book.automationCausality(a.id)["origin"]["roots"] == trace["origin"]["roots"])
    try expect(try f.book.automationCausality(b.id)["origin"]["roots"] == trace["origin"]["roots"])
    _ = try f.book.verify()
  }
  check("one business cause admits32 total unrelated targets and refuses target33 atomically") {
    let f = try fixture("Total")
    let input = try f.book.recordBusinessObservation(title: "One original input")
    var runs: [CausalRun] = []
    for _ in 0..<32 { runs.append(try f.admit(independentInputs: [input.id])) }
    let (_, session) = try f.prepare()
    let before = try f.book.committedHistory()
    try refuses("causal_work_limit") {
      _ = try f.book.dispatchAutomaticCalendarRun(
        session, observedAt: f.due, token: "over-budget", independentInputs: [input.id])
    }
    try expect(try f.book.committedHistory() == before)
    try expect(
      try f.book.automationCausality(runs[0].id)["rootCharges"].array[0]["admittedRuns"].int == 32)
    try expect(try f.book.db.scalar("SELECT count(*) FROM automatic_independent_inputs").int == 32)
    try expect(try f.book.db.scalar("SELECT count(*) FROM automatic_roots").int == 1)
    _ = try f.book.verify()
  }
  check("mixed automatic and independent inputs merge roots once without resetting ancestry") {
    let f = try fixture("Mixed")
    let a = try f.admit(f.initial)
    let input = try f.book.recordBusinessObservation(title: "New independently supplied fact")
    let b = try f.admit(parents: [a.id], independentInputs: [input.id])
    let c = try f.admit(parents: [a.id, b.id], independentInputs: [input.id])
    let trace = try f.book.automationCausality(c.id)
    try expect(trace["origin"]["depth"].int == 3 && trace["ancestorCount"].int == 2)
    try expect(trace["rootCharges"].array.map { $0["admittedRuns"].int! }.sorted() == [2, 3])
    try f.finish(a)
    let tomorrow = f.due.addingTimeInterval(86_400)
    _ = try f.book.planAutomationOccurrences(a.session.planning, through: tomorrow, token: "later")
    let next = try f.book.recordBusinessObservation(title: "Another new fact")
    try refuses("causal_self_trigger") {
      _ = try f.book.dispatchAutomaticCalendarRun(
        a.session, observedAt: tomorrow, token: "cannot-clear", inheriting: [c.id],
        independentInputs: [next.id])
    }
    _ = try f.book.verify()
  }
  check("eight distinct business roots merge while a ninth or an undeclared input cannot admit") {
    let f = try fixture("Bounds")
    let sources = try (0..<9).map { try f.book.recordBusinessObservation(title: "Input\($0)").id }
    let run = try f.admit(independentInputs: Array(sources.prefix(8)))
    try expect(try f.book.automationCausality(run.id)["origin"]["roots"].array.count == 8)
    for (inputs, code) in [
      (sources, "causal_roots"), (["missing"], "causal_inputs"),
      ([String(repeating: "x", count: 257)], "causal_inputs"),
      (Array(repeating: sources[0], count: 1025), "causal_parents"),
    ] {
      let (_, session) = try f.prepare()
      let before = try f.book.committedHistory()
      try refuses(code) {
        _ = try f.book.dispatchAutomaticCalendarRun(
          session, observedAt: f.due, token: identifier(), independentInputs: inputs)
      }
      try expect(try f.book.committedHistory() == before)
    }
    let generic = try f.book.addItem(
      category: "source", kind: "observation", title: "A label is not intent")
    let (_, session) = try f.prepare()
    try refuses("causal_inputs") {
      _ = try f.book.dispatchAutomaticCalendarRun(
        session, observedAt: f.due, token: "generic", independentInputs: [generic.id])
    }
    _ = try f.book.verify()
  }
  check("shared roots survive completion pause reopen and inert reconstruction without a grant") {
    let f = try fixture("Recovery")
    let input = try f.book.recordBusinessObservation(title: "Original input")
    let a = try f.admit(f.initial, independentInputs: [input.id])
    let b = try f.admit(parents: [a.id])
    try f.finish(a)
    _ = try f.book.pauseAutomation(
      b.session.planning.activationID, expectedGeneration: 1, token: "pause")
    let trace = try f.book.automationCausality(b.id)
    let copy = try f.book.reconstruct(
      to: directory.appendingPathComponent("SharedAdmissionCopy.sevra"))
    try expect(try copy.automationCausality(b.id) == trace)
    try expect(try Workbook(f.book.url).automationCausality(b.id) == trace)
    try expect(trace["rootCharges"].array[0]["admittedRuns"].int == 2)
    try refuses("automation_authority") {
      _ = try copy.dispatchAutomationOccurrence(a.session, observedAt: f.due, token: "borrow")
    }
    _ = try copy.verify()
  }
  check("failed shared admission publication rolls back its root relation and every charge") {
    let f = try fixture("Rollback")
    let input = try f.book.recordBusinessObservation(title: "Original input")
    let (_, session) = try f.prepare(f.initial)
    let before = try f.book.committedHistory()
    let cancellation = Cancellation()
    try AutomationPublicationProbe.$observer.withValue({ stage, _ in
      if stage == .prepared { cancellation.cancel() }
    }) {
      try refuses("cancelled") {
        _ = try f.book.dispatchAutomaticCalendarRun(
          session, observedAt: f.due, token: "rollback", cancellation: cancellation,
          independentInputs: [input.id])
      }
    }
    try expect(try f.book.committedHistory() == before)
    for table in [
      "automatic_roots", "automatic_admissions", "automatic_independent_inputs",
      "automatic_root_members",
    ] {
      try expect(try f.book.db.scalar("SELECT count(*) FROM " + table).int == 0)
    }
    let receipt = try f.book.dispatchAutomaticCalendarRun(
      session, observedAt: f.due, token: "rollback", independentInputs: [input.id])
    try expect(
      try f.book.automationCausality(receipt["runID"].text)["rootCharges"].array[0]["admittedRuns"]
        .int == 1)
    _ = try f.book.verify()
  }
  check("missing or altered business root coordinates inputs and lineage refuse inspection") {
    for damage in 0..<6 {
      let f = try fixture("Damage\(damage)")
      let input = try f.book.recordBusinessObservation(title: "Original input")
      let run = try f.admit(f.initial, independentInputs: [input.id])
      let db = try Database(f.book.url.appendingPathComponent("workbook.sqlite"))
      try db.execute("PRAGMA foreign_keys=OFF")
      switch damage {
      case 0:
        try db.execute("DELETE FROM automatic_independent_inputs WHERE run_id=?", [.string(run.id)])
      case 1: try db.execute("DELETE FROM business_inputs WHERE source_id=?", [.string(input.id)])
      case 2: try db.execute("UPDATE automatic_roots SET commit_id='foreign'")
      case 3: try db.execute("UPDATE automatic_roots SET source_id=?", [run.receipt["sourceID"]])
      case 4:
        try db.execute(
          "UPDATE lineage SET roles=2 WHERE child=? AND parent=?",
          [f.book.workflowRun(run.id)["source_id"], .string(input.id)])
      default: try db.execute("UPDATE items SET kind='request' WHERE id=?", [.string(input.id)])
      }
      try refuses { _ = try f.book.automationCausality(run.id) }
      try refuses { _ = try f.book.verify() }
    }
  }
}

func createSharedAdmissionFixture(at url: URL) throws -> Value {
  let f = try CausalFixture(url)
  let input = try f.book.recordBusinessObservation(title: "Shared original input")
  let first = try f.admit(f.initial, independentInputs: [input.id])
  for _ in 0..<24 { _ = try f.admit(independentInputs: [input.id]) }
  let children = try (0..<9).map { _ in try executionAutomation(f.book, workflow: f.workflow).id }
  return .object([
    "sourceID": .string(input.id), "runID": .string(first.id),
    "children": .array(children.map(Value.string)),
    "origin": try f.book.automationCausality(first.id),
  ])
}

func sharedAdmissionWorker(path: String, definition: String, input: String) throws -> Value {
  let book = try Workbook(URL(fileURLWithPath: path))
  let session = try book.authorizeAutomationExecution(
    definition, expectedGeneration: 0, after: automationDate("2026-10-01T08:00:00Z"),
    token: "shared-authorize:" + definition)
  let due = automationDate("2026-10-01T09:00:00Z")
  _ = try book.planAutomationOccurrences(
    session.planning, through: due, token: "shared-plan:" + definition)
  return try book.dispatchAutomaticCalendarRun(
    session, observedAt: due, token: "shared-dispatch:" + definition, independentInputs: [input])
}

func sharedAdmissionDeathWorker(at url: URL, stage: String) throws {
  try require(
    ["prepared", "committed"].contains(stage), "fixture", "Use an exact publication boundary.")
  let f = try CausalFixture(url)
  let input = try f.book.recordBusinessObservation(title: "Original input")
  let (_, session) = try f.prepare(f.initial)
  _ = try AutomationPublicationProbe.$observer.withValue(
    { current, _ in
      if (current == .prepared && stage == "prepared")
        || (current == .committed && stage == "committed")
      {
        print(try! Value.object(["stage": .string(stage), "sourceID": .string(input.id)]).json())
        _ = readLine()
      }
    },
    operation: {
      try f.book.dispatchAutomaticCalendarRun(
        session, observedAt: f.due, token: "shared-death", independentInputs: [input.id])
    })
}
