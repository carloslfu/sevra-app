import Foundation

@testable import SevraCore

func checkAutomationCausality(at directory: URL) {
  func fixture(_ name: String) throws -> CausalFixture {
    try CausalFixture(directory.appendingPathComponent("Causality-" + name + ".sevra"))
  }
  check("a calendar run retains one exact root and truthful read-only admission") {
    let f = try fixture("Calendar")
    let run = try f.admit(f.initial)
    let revision = try f.book.revision()
    let history = try f.book.committedHistory()
    let trace = try f.book.automationCausality(run.id)
    let invocation = try f.book.item(f.book.workflowRun(run.id)["source_id"].text)
    try expect(trace["origin"] == invocation.data["origin"]["causality"])
    try expect(trace["origin"]["depth"].int == 1 && trace["origin"]["parents"].array.isEmpty)
    try expect(
      trace["rootCharges"].array.count == 1
        && trace["rootCharges"].array[0]["admittedRuns"].int == 1)
    try expect(
      trace["dispatchEligibility"].text == "not-evaluated" && trace["enabled"] == .bool(false))
    try expect(trace["execution"].text == "none" && trace["ancestorCount"].int == 0)
    try expect(try f.book.revision() == revision && f.book.committedHistory() == history)
    _ = try f.book.verify()
  }
  check("dispatch retry and active deferral cannot double-charge a calendar root") {
    let f = try fixture("Retry")
    let (_, session) = try f.prepare(f.initial)
    let first = try f.book.dispatchAutomationOccurrence(session, observedAt: f.due, token: "retry")
    let trace = try f.book.automationCausality(first["runID"].text)
    let revision = try f.book.revision()
    try expect(
      try f.book.dispatchAutomationOccurrence(session, observedAt: f.due, token: "retry") == first)
    try expect(try f.book.revision() == revision)
    try expect(
      try f.book.dispatchAutomationOccurrence(session, observedAt: f.due, token: "other")["status"]
        .text == "active")
    try expect(try f.book.automationCausality(first["runID"].text) == trace)
    try expect(try f.book.db.scalar("SELECT count(*) FROM automatic_admissions").int == 1)
  }
  check("future, idle and skipped late slots admit no automatic work") {
    let f = try fixture("Noop")
    let (_, session) = try f.prepare(f.initial)
    try expect(
      try f.book.dispatchAutomationOccurrence(session, observedAt: f.start, token: "future")[
        "status"
      ].text == "future")
    let late = f.due.addingTimeInterval(86_401)
    try expect(
      try f.book.dispatchAutomationOccurrence(session, observedAt: late, token: "late")["status"]
        .text == "late")
    try expect(
      try f.book.dispatchAutomationOccurrence(session, observedAt: late, token: "idle")["status"]
        .text == "idle")
    try expect(try f.book.db.scalar("SELECT count(*) FROM automatic_roots").int == 0)
    try expect(try f.book.db.scalar("SELECT count(*) FROM automatic_admissions").int == 0)
    _ = try f.book.verify()
  }
  check("the next calendar tick is an independent root for the same automation") {
    let f = try fixture("Tomorrow")
    let first = try f.admit(f.initial)
    try f.finish(first)
    let tomorrow = f.due.addingTimeInterval(86_400)
    _ = try f.book.planAutomationOccurrences(
      first.session.planning, through: tomorrow, token: "next-day")
    let second = try f.book.dispatchAutomationOccurrence(
      first.session, observedAt: tomorrow, token: "tomorrow")
    let a = try f.book.automationCausality(first.id)
    let b = try f.book.automationCausality(second["runID"].text)
    try expect(a["origin"]["roots"] != b["origin"]["roots"])
    try expect(
      a["origin"]["logicalID"] == b["origin"]["logicalID"] && b["origin"]["depth"].int == 1)
    try expect(a["rootCharges"].array[0]["admittedRuns"].int == 1)
    _ = try f.book.verify()
  }
  check("trusted inherited admission retains a parent invocation and counts automatic depth") {
    let f = try fixture("Inherited")
    let seed = try f.admit(f.initial)
    let child = try f.admit(parents: [seed.id, seed.id])
    let a = try f.book.automationCausality(seed.id)
    let b = try f.book.automationCausality(child.id)
    try expect(b["origin"]["parents"] == .array([.string(seed.id)]))
    try expect(b["origin"]["roots"] == a["origin"]["roots"] && b["origin"]["depth"].int == 2)
    try expect(a["rootCharges"].array[0]["admittedRuns"].int == 2 && a["directSuccessors"].int == 1)
    let invocation = try f.book.workflowRun(child.id)["source_id"].text
    try expect(
      try f.book.automaticDerivationAncestry(inputs: [invocation])["automaticRuns"].array.count == 2
    )
    _ = try f.book.verify()
  }
  check("merged roots charge each distinct root once and shared DAG paths do not multiply charges")
  {
    let f = try fixture("Merge")
    let a = try f.admit(f.initial)
    let b = try f.admit()
    let merge = try f.admit(parents: [a.id, b.id, a.id])
    let child = try f.admit(parents: [a.id, merge.id])
    let trace = try f.book.automationCausality(child.id)
    try expect(trace["origin"]["depth"].int == 3 && trace["ancestorCount"].int == 3)
    try expect(trace["origin"]["roots"].array.count == 2)
    try expect(trace["rootCharges"].array.map { $0["admittedRuns"].int! }.sorted() == [3, 3])
    _ = try f.book.verify()
  }
  check("self-output and A to B to A refuse after completion without clearing prior charges") {
    let f = try fixture("Self")
    let a = try f.admit(f.initial)
    let b = try f.admit(parents: [a.id])
    try f.finish(a)
    let tomorrow = f.due.addingTimeInterval(86_400)
    _ = try f.book.planAutomationOccurrences(a.session.planning, through: tomorrow, token: "next")
    let before = try f.book.committedHistory()
    for parents in [[a.id], [b.id]] {
      try refuses("causal_self_trigger") {
        _ = try f.book.dispatchAutomaticCalendarRun(
          a.session, observedAt: tomorrow, token: identifier(), inheriting: parents)
      }
    }
    try expect(try f.book.committedHistory() == before)
    try expect(
      try f.book.automationCausality(a.id)["rootCharges"].array[0]["admittedRuns"].int == 2)
    _ = try f.book.verify()
  }
  check("editing and re-enabling a logical automation cannot reset its self-output ancestry") {
    let f = try fixture("Edited")
    let a = try f.admit(f.initial)
    try f.finish(a)
    var content = f.initial.content.object
    content["title"] = .string("Edited exact version")
    let edited = try f.book.saveApplicationDefinition(
      logicalID: f.initial.logicalID, content: .object(content), expectedDefinitionID: f.initial.id)
    let tomorrow = f.due.addingTimeInterval(86_400)
    let (_, session) = try f.prepare(edited, generation: 1, after: f.due, at: tomorrow)
    try refuses("causal_self_trigger") {
      _ = try f.book.dispatchAutomaticCalendarRun(
        session, observedAt: tomorrow, token: "edited", inheriting: [a.id])
    }
    try expect(
      try f.book.automationCausality(a.id)["rootCharges"].array[0]["admittedRuns"].int == 1)
    _ = try f.book.verify()
  }
  check("depth eight succeeds and a ninth automatic run in that chain rolls back") {
    let f = try fixture("Depth")
    var last = try f.admit(f.initial)
    for _ in 2...8 { last = try f.admit(parents: [last.id]) }
    try expect(try f.book.automationCausality(last.id)["origin"]["depth"].int == 8)
    try f.reject("causal_depth", parents: [last.id])
    _ = try f.book.verify()
  }
  check("eight direct successors succeed and the ninth rolls back without a charge") {
    let f = try fixture("Fanout")
    let seed = try f.admit(f.initial)
    for _ in 0..<8 { _ = try f.admit(parents: [seed.id]) }
    try f.reject("causal_fanout", parents: [seed.id])
    let trace = try f.book.automationCausality(seed.id)
    try expect(
      trace["directSuccessors"].int == 8 && trace["rootCharges"].array[0]["admittedRuns"].int == 9)
    _ = try f.book.verify()
  }
  check("a branching root admits 32 total runs and refuses run 33 below all other bounds") {
    let f = try fixture("Total")
    let seed = try f.admit(f.initial)
    let children = try (0..<8).map { _ in try f.admit(parents: [seed.id]) }
    for index in 0..<23 { _ = try f.admit(parents: [children[index / 8].id]) }
    try expect(
      try f.book.automationCausality(seed.id)["rootCharges"].array[0]["admittedRuns"].int == 32)
    try f.reject("causal_work_limit", parents: [children[3].id])
    _ = try f.book.verify()
  }
  check("eight roots merge but nine roots or nine supplied parents refuse") {
    let f = try fixture("Roots")
    let roots = try (0..<9).map { _ in try f.admit() }
    let merge = try f.admit(parents: Array(roots.prefix(8)).map(\.id))
    try expect(try f.book.automationCausality(merge.id)["origin"]["roots"].array.count == 8)
    try f.reject("causal_roots", parents: [merge.id, roots[8].id])
    try f.reject("causal_parents", parents: roots.map(\.id))
    _ = try f.book.verify()
  }
  check("missing and manual parents refuse instead of inventing an independent root") {
    let f = try fixture("Missing")
    let manual = try f.book.startWorkflow(f.workflow.id, arguments: .object([:]), token: "manual")
    try f.reject("causal_origin", parents: [manual["id"].text])
    try f.reject("causal_origin", parents: ["missing"])
    try f.reject("causal_parents", parents: [])
    _ = try f.book.verify()
  }
  check("admission cannot run outside a captured transaction or reuse a stale target plan") {
    let f = try fixture("Transactions")
    let seed = try f.admit(f.initial)
    try refuses("causal_transaction") {
      _ = try f.book.planAutomationCausality(definitionID: f.initial.id, parents: [seed.id])
    }
    let (target, _) = try f.prepare()
    var plan: AutomationCausalPlan!
    _ = try f.book.mutation("synthetic.causal-plan") {
      plan = try f.book.planAutomationCausality(definitionID: target.id, parents: [seed.id])
      return .null
    }
    try refuses("causal_transaction") {
      try f.book.retainAutomationCausality(plan, runID: "unbound", sourceID: "unbound")
    }
    for _ in 0..<8 { _ = try f.admit(parents: [seed.id]) }
    let revision = try f.book.revision()
    try refuses("causal_fanout") {
      _ = try f.book.mutation("synthetic.stale-admission") {
        try f.book.retainAutomationCausality(plan, runID: "unbound", sourceID: "unbound")
        return .null
      }
    }
    try expect(try f.book.revision() == revision)
    _ = try f.book.verify()
  }
  check("completion, cancellation, pause, reopen and inert reconstruction retain all charges") {
    let f = try fixture("Recovery")
    let seed = try f.admit(f.initial)
    let child = try f.admit(parents: [seed.id])
    try f.finish(seed)
    _ = try f.book.cancelWorkflow(child.id, token: "cancel")
    _ = try f.book.pauseAutomation(
      child.session.planning.activationID, expectedGeneration: 1, token: "pause")
    let trace = try f.book.automationCausality(child.id)
    let reopened = try Workbook(f.book.url)
    try expect(try reopened.automationCausality(child.id) == trace)
    let copy = try f.book.reconstruct(to: directory.appendingPathComponent("CausalityCopy.sevra"))
    try expect(try copy.automationCausality(child.id) == trace)
    try expect(
      trace["rootCharges"].array[0]["admittedRuns"].int == 2 && trace["enabled"] == .bool(false))
    try refuses("automation_authority") {
      _ = try copy.dispatchAutomationOccurrence(seed.session, observedAt: f.due, token: "borrow")
    }
    _ = try copy.verify()
  }
  check("missing, malformed and cancelled origin inspections refuse without writes") {
    let f = try fixture("Inputs")
    let seed = try f.admit(f.initial)
    for id in ["", String(repeating: "x", count: 257)] {
      try refuses("causal_input") { _ = try f.book.automationCausality(id) }
    }
    try refuses("causal_origin") { _ = try f.book.automationCausality("missing") }
    let cancellation = Cancellation()
    cancellation.cancel()
    let revision = try f.book.revision()
    try refuses("cancelled") {
      _ = try f.book.automationCausality(seed.id, cancellation: cancellation)
    }
    try expect(try f.book.revision() == revision)
  }
  check("origin inspection cancels an actual exclusive SQLite lock within one second") {
    let f = try fixture("Lock")
    let seed = try f.admit(f.initial)
    let other = try Database(f.book.url.appendingPathComponent("workbook.sqlite"))
    try other.execute("BEGIN EXCLUSIVE")
    defer { _ = try? other.execute("ROLLBACK") }
    let cancellation = Cancellation()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { cancellation.cancel() }
    let start = ProcessInfo.processInfo.systemUptime
    try refuses("cancelled") {
      _ = try f.book.automationCausality(seed.id, cancellation: cancellation)
    }
    try expect(ProcessInfo.processInfo.systemUptime - start < 1)
  }
  check("budget reads use reverse indexes instead of scanning unrelated saved history") {
    let f = try fixture("Indexes")
    let seed = try f.admit(f.initial)
    let root = try f.book.automationCausality(seed.id)["origin"]["roots"].array[0]
    for (sql, value) in [
      ("SELECT run_id FROM automatic_root_members WHERE root_id=? LIMIT 33", root),
      ("SELECT run_id FROM automatic_parents WHERE parent_run_id=? LIMIT 9", .string(seed.id)),
    ] {
      let plan = try f.book.db.execute("EXPLAIN QUERY PLAN " + sql, [value])
      try expect(plan.contains { $0["detail"]!.text.contains("USING COVERING INDEX") })
      try expect(!plan.contains { $0["detail"]!.text.contains("SCAN ") })
    }
  }
  checkAutomationCausalityCorruption(at: directory)
}
