import Foundation

struct AutomationCausalPlan: Equatable {
  static let policy = "automation-causality-v1"
  let definitionID: String
  let logicalID: String
  let depth: Int
  let parents: [String]
  let roots: [String]
  let calendarOccurrence: String?
  let independentInputs: [String]

  init(
    definitionID: String, logicalID: String, depth: Int, parents: [String], roots: [String],
    calendarOccurrence: String?, independentInputs: [String] = []
  ) {
    self.definitionID = definitionID
    self.logicalID = logicalID
    self.depth = depth
    self.parents = parents
    self.roots = roots
    self.calendarOccurrence = calendarOccurrence
    self.independentInputs = independentInputs
  }

  var context: Value {
    .object([
      "policy": .string(Self.policy), "definitionID": .string(definitionID),
      "logicalID": .string(logicalID), "depth": .number(Double(depth)),
      "parents": .array(parents.map(Value.string)), "roots": .array(roots.map(Value.string)),
      "independentInputs": .array(independentInputs.map(Value.string)),
    ])
  }

  static func calendarRoot(_ occurrence: String) throws -> String {
    "automatic-root:"
      + ChangeFormat.hash(try Value.array([.string(policy), .string(occurrence)]).json())
  }
}

extension Workbook {
  /// Internal admission primitive. Its caller owns the captured dispatch
  /// transaction and exact execution grant; saved origins confer no authority.
  func planAutomationCausality(
    definitionID: String, calendarOccurrence: String? = nil, parents supplied: [String] = [],
    independentInputs suppliedInputs: [String] = []
  ) throws -> AutomationCausalPlan {
    try requireCausalMutation()
    let definition = try applicationDefinition(definitionID)
    try require(
      definition.id == definitionID && definition.kind == "automation", "causal_target",
      "Admission requires an exact saved automation version.")
    let parents = Array(Set(supplied)).sorted()
    let independent = Array(Set(suppliedInputs)).sorted()
    try require(
      supplied.count <= 8 && suppliedInputs.count <= 1024
        && (calendarOccurrence != nil
          ? parents.isEmpty && independent.isEmpty : !parents.isEmpty || !independent.isEmpty),
      "causal_parents",
      "Use an exact calendar occurrence or bounded automatic/declared input causes.")
    if let occurrence = calendarOccurrence {
      try require(
        try db.scalar(
          "SELECT EXISTS(SELECT 1 FROM automation_occurrences o WHERE o.id=? AND o.definition_id=? AND o.state IN ('pending','dispatched') AND NOT EXISTS(SELECT 1 FROM automation_runs a WHERE a.occurrence_id=o.id))",
          [.string(occurrence), .string(definitionID)]
        ).int == 1, "causal_seed", "Use an unbound exact calendar occurrence for this automation.")
      let root = try AutomationCausalPlan.calendarRoot(occurrence)
      try require(
        try db.scalar("SELECT EXISTS(SELECT 1 FROM automatic_roots WHERE id=?)", [.string(root)])
          .int == 0, "causal_seed", "This calendar root was already retained.")
      return AutomationCausalPlan(
        definitionID: definitionID, logicalID: definition.logicalID, depth: 1,
        parents: [], roots: [root], calendarOccurrence: occurrence)
    }
    let graph = try automationCausalGraph(parents)
    try require(
      Set(graph.values.flatMap(\.independentInputs) + independent).count <= 1024,
      "causal_inputs", "Automatic ancestry can retain at most1,024 distinct independent inputs.")
    try require(
      !graph.values.contains { $0.logicalID == definition.logicalID }, "causal_self_trigger",
      "This automation already appears in the automatic ancestry. Its output cannot trigger itself."
    )
    let depth = 1 + (parents.compactMap { graph[$0]?.depth }.max() ?? 0)
    try require(depth <= 8, "causal_depth", "The automatic chain reached its depth limit of eight.")
    let declarations = try qualifiedAdmissionInputs(independent)
    let roots = Set(parents.flatMap { graph[$0]!.roots } + declarations.map { $0["rootID"].text })
      .sorted()
    try require(roots.count <= 8, "causal_roots", "A run can inherit at most eight roots.")
    for parent in parents {
      try require(
        try causalSuccessorCount(parent) < 8, "causal_fanout",
        "An automatic parent reached its limit of eight direct successors.")
    }
    for root in roots {
      try require(
        try causalRootCount(root) < 32, "causal_work_limit",
        "An automatic root reached its total-work limit of 32 runs.")
    }
    return AutomationCausalPlan(
      definitionID: definitionID, logicalID: definition.logicalID, depth: depth,
      parents: parents, roots: roots, calendarOccurrence: nil, independentInputs: independent)
  }

  func retainAutomationCausality(_ plan: AutomationCausalPlan, runID: String, sourceID: String)
    throws
  {
    try requireCausalMutation()
    // Recompute while still holding the owning writer transaction. Do not trust
    // a previously prepared object after new admissions or altered arguments.
    let fresh: AutomationCausalPlan
    if let occurrence = plan.calendarOccurrence {
      // The exact run binding now exists, so validate this seed directly here.
      let binding = try automationRunBinding(runID)
      try require(
        binding["occurrence_id"] == .string(occurrence), "causal_integrity",
        "The calendar root does not match the queued occurrence.")
      let definition = try applicationDefinition(plan.definitionID)
      try require(
        definition.kind == "automation", "causal_target", "Admission requires an automation.")
      try require(
        try db.scalar(
          "SELECT EXISTS(SELECT 1 FROM automatic_roots WHERE occurrence_id=?)",
          [.string(occurrence)]
        ).int == 0,
        "causal_stale", "This calendar occurrence already has an automatic root.")
      fresh = AutomationCausalPlan(
        definitionID: definition.id, logicalID: definition.logicalID, depth: 1, parents: [],
        roots: [try AutomationCausalPlan.calendarRoot(occurrence)], calendarOccurrence: occurrence)
    } else {
      fresh = try planAutomationCausality(
        definitionID: plan.definitionID, parents: plan.parents,
        independentInputs: plan.independentInputs)
    }
    try require(
      fresh == plan, "causal_stale", "The automatic admission changed before publication.")
    try require(
      try db.scalar(
        "SELECT EXISTS(SELECT 1 FROM automatic_admissions WHERE run_id=?)", [.string(runID)]
      ).int == 0,
      "causal_stale", "This automatic run already has an admission.")
    let binding = try automationRunBinding(runID)
    let run = try workflowRun(runID)
    let invocation = try item(run["source_id"].text)
    try require(
      binding["definition_id"] == .string(plan.definitionID)
        && binding["dispatch_source"] == .string(sourceID)
        && run["policy"] == .string("automation-drafts-v1")
        && invocation.data["origin"]["causality"] == plan.context,
      "causal_integrity", "The admission does not match its exact saved automatic invocation.")
    if let occurrence = plan.calendarOccurrence {
      try db.execute(
        "INSERT INTO automatic_roots VALUES(?,'calendar',?,NULL,?,?,?)",
        [
          .string(plan.roots[0]), .string(occurrence), .string(AutomationCausalPlan.policy),
          .string(sourceID), .string(timestamp()),
        ])
    }
    try retainBusinessCausalRoots(try qualifiedAdmissionInputs(plan.independentInputs))
    try db.execute(
      "INSERT INTO automatic_admissions VALUES(?,?,?,?,?,?)",
      [
        .string(runID), .string(plan.definitionID), .string(plan.logicalID),
        .number(Double(plan.depth)), .string(AutomationCausalPlan.policy), .string(sourceID),
      ])
    for root in plan.roots {
      try db.execute(
        "INSERT INTO automatic_root_members VALUES(?,?)", [.string(runID), .string(root)])
    }
    for parent in plan.parents {
      try db.execute(
        "INSERT INTO automatic_parents VALUES(?,?)", [.string(runID), .string(parent)])
    }
    for source in plan.independentInputs {
      try db.execute(
        "INSERT INTO automatic_independent_inputs VALUES(?,?)", [.string(runID), .string(source)])
    }
  }

  func requireCausalMutation() throws {
    try require(
      db.changes?.pending != nil && db.changes?.publishing == false, "causal_transaction",
      "Automatic admission belongs inside the owning captured dispatch transaction.")
  }

  func causalRootCount(_ root: String) throws -> Int {
    try db.scalar(
      "SELECT count(*) FROM (SELECT run_id FROM automatic_root_members WHERE root_id=? LIMIT 33)",
      [.string(root)]
    ).int ?? 0
  }

  func causalSuccessorCount(_ parent: String) throws -> Int {
    try db.scalar(
      "SELECT count(*) FROM (SELECT run_id FROM automatic_parents WHERE parent_run_id=? LIMIT 9)",
      [.string(parent)]
    ).int ?? 0
  }
}
