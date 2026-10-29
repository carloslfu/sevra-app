import Foundation

@testable import SevraCore

func checkAutomationCausalityCorruption(at directory: URL) {
  check("missing admissions, roots, lineage, changed origin and inconsistent depth all refuse") {
    for corruption in 0..<8 {
      let f = try CausalFixture(
        directory.appendingPathComponent("CausalDamage-\(corruption).sevra"))
      let seed = try f.admit(f.initial)
      let child = try f.admit(parents: [seed.id])
      let run = try f.book.workflowRun(child.id)
      _ = try f.book.db.transaction {
        switch corruption {
        case 0:
          try f.book.db.execute(
            "DELETE FROM automatic_root_members WHERE run_id=?", [.string(child.id)])
        case 1:
          try f.book.db.execute(
            "UPDATE automatic_admissions SET depth=3 WHERE run_id=?", [.string(child.id)])
        case 2:
          try f.book.db.execute(
            "UPDATE automatic_admissions SET source_id=? WHERE run_id=?",
            [seed.receipt["sourceID"], .string(child.id)])
        case 3:
          let parent = try f.book.workflowRun(seed.id)["source_id"]
          try f.book.db.execute(
            "DELETE FROM lineage WHERE child=? AND parent=?", [run["source_id"], parent])
        case 4:
          let invocation = try f.book.item(run["source_id"].text)
          var data = invocation.data.object
          data["origin"] = .null
          try f.book.db.execute(
            "UPDATE items SET data=? WHERE id=?",
            [.string(try Value.object(data).json()), run["source_id"]])
        case 5:
          try f.book.db.execute(
            "UPDATE items SET data=? WHERE id=?",
            [.string(String(repeating: "x", count: 1_048_577)), run["source_id"]])
        case 6:
          let parent = try f.book.workflowRun(seed.id)["source_id"]
          try f.book.db.execute(
            "UPDATE lineage SET roles=1 WHERE child=? AND parent=?", [run["source_id"], parent])
        default:
          try f.book.db.execute("DELETE FROM automatic_parents WHERE run_id=?", [.string(child.id)])
          try f.book.db.execute(
            "DELETE FROM automatic_root_members WHERE run_id=?", [.string(child.id)])
          try f.book.db.execute(
            "DELETE FROM automatic_admissions WHERE run_id=?", [.string(child.id)])
        }
      }
      try refuses { _ = try f.book.automationCausality(child.id) }
      try refuses { _ = try f.book.verify() }
    }
  }
  check("a coherent forged cycle still fails the automatic graph depth invariant") {
    let f = try CausalFixture(directory.appendingPathComponent("CausalCycle.sevra"))
    let seed = try f.admit(f.initial)
    let child = try f.admit(parents: [seed.id])
    let source = try f.book.workflowRun(seed.id)["source_id"]
    let childSource = try f.book.workflowRun(child.id)["source_id"]
    let invocation = try f.book.item(source.text)
    var data = invocation.data.object
    var origin = data["origin"]!.object
    var context = origin["causality"]!.object
    context["parents"] = .array([.string(child.id)])
    origin["causality"] = .object(context)
    data["origin"] = .object(origin)
    _ = try f.book.db.transaction {
      try f.book.db.execute(
        "INSERT INTO automatic_parents VALUES(?,?)", [.string(seed.id), .string(child.id)])
      try f.book.db.execute(
        "INSERT INTO lineage VALUES(?,?,'derives-from','synthetic-corruption',1)",
        [source, childSource])
      try f.book.db.execute(
        "UPDATE items SET data=? WHERE id=?", [.string(try Value.object(data).json()), source])
    }
    try refuses("causal_integrity") { _ = try f.book.automationCausality(child.id) }
    try refuses { _ = try f.book.verify() }
  }
  check("altered prepared admission is refused before any run or charge can be published") {
    let f = try CausalFixture(directory.appendingPathComponent("CausalAltered.sevra"))
    let seed = try f.admit(f.initial)
    let (definition, _) = try f.prepare()
    let revision = try f.book.revision()
    try refuses("causal_stale") {
      _ = try f.book.mutation("synthetic.altered-admission") {
        let plan = try f.book.planAutomationCausality(
          definitionID: definition.id, parents: [seed.id])
        let altered = AutomationCausalPlan(
          definitionID: plan.definitionID, logicalID: plan.logicalID,
          depth: plan.depth + 1, parents: plan.parents, roots: plan.roots, calendarOccurrence: nil)
        try f.book.retainAutomationCausality(altered, runID: "unbound", sourceID: "unbound")
        return .null
      }
    }
    try expect(try f.book.revision() == revision)
  }
  check("cancellation at the dispatch publication barrier rolls back the root and every charge") {
    let f = try CausalFixture(directory.appendingPathComponent("CausalCancelled.sevra"))
    let (_, session) = try f.prepare(f.initial)
    let revision = try f.book.revision()
    let cancellation = Cancellation()
    try AutomationPublicationProbe.$observer.withValue({ stage, _ in
      if stage == .prepared { cancellation.cancel() }
    }) {
      try refuses("cancelled") {
        _ = try f.book.dispatchAutomationOccurrence(
          session, observedAt: f.due, token: "cancelled", cancellation: cancellation)
      }
    }
    try expect(try f.book.revision() == revision)
    try expect(try f.book.db.scalar("SELECT count(*) FROM automatic_roots").int == 0)
    let run = try f.book.dispatchAutomationOccurrence(
      session, observedAt: f.due, token: "cancelled")
    try expect(
      try f.book.automationCausality(run["runID"].text)["rootCharges"].array[0]["admittedRuns"].int
        == 1)
    _ = try f.book.verify()
  }
}
