import Foundation

struct AutomationCausalNode {
  let runID: String
  let definitionID: String
  let logicalID: String
  let depth: Int
  let sourceID: String
  let roots: [String]
  let parents: [String]
  let independentInputs: [String]
  var context: Value {
    AutomationCausalPlan(
      definitionID: definitionID, logicalID: logicalID, depth: depth, parents: parents,
      roots: roots, calendarOccurrence: nil, independentInputs: independentInputs
    ).context
  }
}

extension Workbook {
  /// Historical inspection only. It does not restore any device/session grant.
  public func automationCausality(_ runID: String, cancellation: Cancellation = .init()) throws
    -> Value
  {
    try require(
      !runID.isEmpty && runID.utf8.count <= 256, "causal_input",
      "Inspect an exact automatic run identity.")
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try readBusinessFeed(cancellation: control) {
      let graph = try automationCausalGraph([runID], cancellation: control)
      let node = graph[runID]!
      return .object([
        "runID": .string(runID), "origin": node.context, "dispatchSourceID": .string(node.sourceID),
        "ancestorCount": .number(Double(graph.count - 1)),
        "rootCharges": .array(
          try node.roots.map { root in
            .object([
              "rootID": .string(root), "admittedRuns": .number(Double(try causalRootCount(root))),
            ])
          }),
        "directSuccessors": .number(Double(try causalSuccessorCount(runID))),
        "limits": .object([
          "parents": .number(8), "roots": .number(8), "depth": .number(8),
          "directSuccessors": .number(8), "runsPerRoot": .number(32),
        ]),
        "coverage": .string("retained-automatic-admissions"),
        "dispatchEligibility": .string("not-evaluated"),
        "execution": .string("none"), "enabled": .bool(false),
      ])
    }
  }

  func automationCausalGraph(_ inputs: [String], cancellation: Cancellation = .init()) throws
    -> [String: AutomationCausalNode]
  {
    var queue = Array(Set(inputs)).sorted()
    var discovered = Set(queue)
    var graph: [String: AutomationCausalNode] = [:]
    var index = 0
    while index < queue.count {
      try cancellation.check()
      let id = queue[index]
      index += 1
      let node = try automationCausalNode(id)
      graph[id] = node
      for parent in node.parents where discovered.insert(parent).inserted {
        try require(
          discovered.count <= 256, "causal_integrity",
          "The automatic ancestry exceeds its retained policy bound.")
        queue.append(parent)
      }
    }
    var ancestors: [String: Set<String>] = [:]
    var independentSources = Set(graph.values.flatMap(\.independentInputs))
    try require(
      independentSources.count <= 1024, "causal_integrity",
      "The automatic ancestry exceeds1,024 distinct independent inputs.")
    let allRoots = Set(graph.values.flatMap(\.roots))
    try require(allRoots.count <= 8, "causal_roots", "The ancestry merges more than eight roots.")
    for root in allRoots {
      let row = try db.execute(
        "SELECT kind,source_id FROM automatic_roots WHERE id=?", [.string(root)],
        maxRows: 1, maxBytes: 8192
      ).first
      if row?["kind"] == .string("business") { independentSources.insert(row!["source_id"]!.text) }
    }
    let declarations = try qualifiedAdmissionInputs(
      independentSources.sorted(), cancellation: cancellation, limit: 1032)
    let declarationsBySource = Dictionary(
      uniqueKeysWithValues: declarations.map { ($0["sourceID"].text, $0) })
    var validatedBusinessRoots = Set<String>()
    var roots: Set<String> = []
    for node in graph.values.sorted(by: { $0.depth < $1.depth }) {
      try cancellation.check()
      roots.formUnion(node.roots)
      try require(roots.count <= 8, "causal_roots", "The ancestry merges more than eight roots.")
      var logicals: Set<String> = []
      var inheritedRoots: Set<String> = []
      var expectedDepth = 1
      for parentID in node.parents {
        guard let parent = graph[parentID], let prior = ancestors[parentID],
          parent.depth < node.depth
        else {
          throw SevraError(
            "causal_integrity", "The automatic ancestry has a cycle or inconsistent depth.")
        }
        logicals.formUnion(prior)
        logicals.insert(parent.logicalID)
        inheritedRoots.formUnion(parent.roots)
        expectedDepth = max(expectedDepth, parent.depth + 1)
      }
      let independent = node.independentInputs.compactMap { declarationsBySource[$0] }
      try require(
        independent.count == node.independentInputs.count, "causal_integrity",
        "An automatic run lost its exact independent input declarations.")
      for declaration in independent {
        try cancellation.check()
        if validatedBusinessRoots.insert(declaration["rootID"].text).inserted {
          try validateBusinessCausalRoot(
            declaration["rootID"].text, commit: declaration["creatingCommitID"].text,
            cancellation: cancellation, declarations: declarationsBySource)
        }
        inheritedRoots.insert(declaration["rootID"].text)
      }
      let calendarSeed = node.parents.isEmpty && independent.isEmpty
      try require(
        expectedDepth == node.depth && !logicals.contains(node.logicalID)
          && (calendarSeed ? node.roots.count == 1 : inheritedRoots == Set(node.roots)),
        "causal_integrity",
        "The automatic admission lost its depth, roots or self-output protection.")
      if calendarSeed { try validateCalendarCausalRoot(node) }
      ancestors[node.runID] = logicals
      try require(
        try causalSuccessorCount(node.runID) <= 8, "causal_integrity",
        "An automatic parent exceeds its successor bound.")
    }
    for root in roots {
      try require(
        try causalRootCount(root) <= 32, "causal_integrity",
        "An automatic root exceeds its total-work bound.")
    }
    return graph
  }

  private func automationCausalNode(_ runID: String) throws -> AutomationCausalNode {
    guard
      let row = try db.execute(
        "SELECT c.*,a.definition_id AS bound_definition,a.dispatch_source,a.activation_id,a.occurrence_id,a.candidate_id,a.generation,a.authorization_source,d.logical_id AS bound_logical,d.kind,w.policy AS run_policy,w.definition_id AS workflow_definition,w.source_id AS invocation FROM automatic_admissions c JOIN automation_runs a ON a.run_id=c.run_id JOIN workflow_runs w ON w.id=c.run_id JOIN app_definitions d ON d.id=a.definition_id WHERE c.run_id=?",
        [.string(runID)], maxRows: 1, maxBytes: 65_536
      ).first
    else {
      throw SevraError("causal_origin", "The exact automatic run has no retained admission.")
    }
    let parents = try db.execute(
      "SELECT parent_run_id FROM automatic_parents WHERE run_id=? ORDER BY parent_run_id LIMIT 9",
      [.string(runID)], maxRows: 9, maxBytes: 65_536
    ).map { $0["parent_run_id"]!.text }
    let roots = try db.execute(
      "SELECT root_id FROM automatic_root_members WHERE run_id=? ORDER BY root_id LIMIT 9",
      [.string(runID)], maxRows: 9, maxBytes: 65_536
    ).map { $0["root_id"]!.text }
    let independent = try db.execute(
      "SELECT source_id FROM automatic_independent_inputs WHERE run_id=? ORDER BY source_id LIMIT 1025",
      [.string(runID)], maxRows: 1025, maxBytes: 524_288
    ).map { $0["source_id"]!.text }
    try require(
      parents.count <= 8 && independent.count <= 1024 && (1...8).contains(roots.count)
        && (1...8).contains(row["depth"]!.int ?? 0)
        && row["policy"] == .string(AutomationCausalPlan.policy)
        && row["kind"] == .string("automation")
        && row["run_policy"] == .string("automation-drafts-v1")
        && row["definition_id"] == row["bound_definition"]
        && row["logical_id"] == row["bound_logical"]
        && row["source_id"] == row["dispatch_source"],
      "causal_integrity", "The retained automatic admission disagrees with its exact run binding.")
    let node = AutomationCausalNode(
      runID: runID, definitionID: row["definition_id"]!.text,
      logicalID: row["logical_id"]!.text, depth: row["depth"]!.int!,
      sourceID: row["source_id"]!.text,
      roots: roots, parents: parents, independentInputs: independent)
    let invocation = try db.execute(
      "SELECT category,kind,CASE WHEN length(CAST(data AS BLOB))<=1048576 THEN data END AS data FROM items WHERE id=?",
      [row["invocation"]!], maxRows: 1, maxBytes: 1_049_000
    ).first
    try require(
      invocation?["data"] != nil && invocation?["data"] != .null, "causal_integrity",
      "The exact automatic invocation exceeds its inspection bound.")
    let data = try Value.parse(invocation!["data"]!.text)
    let origin = data["origin"]
    try require(
      invocation?["category"] == .string("source")
        && invocation?["kind"] == .string("application_invocation")
        && data["workflowRunID"] == .string(runID)
        && data["definitionID"] == row["workflow_definition"]
        && data["policy"] == .string("automation-drafts-v1") && origin["causality"] == node.context
        && origin["automationID"] == row["definition_id"]
        && origin["activationID"] == row["activation_id"]
        && origin["occurrenceID"] == row["occurrence_id"]
        && origin["candidateID"] == row["candidate_id"]
        && origin["generation"] == row["generation"]
        && origin["authorizationSourceID"] == row["authorization_source"]
        && origin["dispatchSourceID"] == row["source_id"],
      "causal_integrity", "The invocation lost its exact retained automatic-origin context.")
    for parent in parents {
      try require(
        try db.scalar(
          "SELECT EXISTS(SELECT 1 FROM workflow_runs p JOIN lineage l ON l.parent=p.source_id WHERE p.id=? AND l.child=? AND l.relation='derives-from' AND (l.roles & 4)<>0)",
          [.string(parent), row["invocation"]!]
        ).int == 1,
        "causal_integrity", "An automatic parent lost its exact invocation lineage.")
    }
    for source in independent {
      try require(
        try db.scalar(
          "SELECT EXISTS(SELECT 1 FROM lineage WHERE child=? AND parent=? AND relation='derives-from' AND (roles & 1)<>0)",
          [row["invocation"]!, .string(source)]
        ).int == 1,
        "causal_integrity", "An independent cause lost its exact invocation input lineage.")
    }
    return node
  }

  private func validateCalendarCausalRoot(_ node: AutomationCausalNode) throws {
    guard
      let root = try db.execute(
        "SELECT r.*,a.run_id,a.dispatch_source FROM automatic_roots r JOIN automation_runs a ON a.occurrence_id=r.occurrence_id WHERE r.id=?",
        [.string(node.roots[0])], maxRows: 1, maxBytes: 65_536
      ).first
    else {
      throw SevraError("causal_integrity", "An automatic root lost its exact calendar occurrence.")
    }
    try require(
      root["kind"] == .string("calendar") && root["commit_id"] == .null
        && root["run_id"] == .string(node.runID) && root["source_id"] == .string(node.sourceID)
        && root["source_id"] == root["dispatch_source"]
        && root["policy"] == .string(AutomationCausalPlan.policy)
        && root["id"]
          == .string(try AutomationCausalPlan.calendarRoot(root["occurrence_id"]!.text)),
      "causal_integrity", "The initial automatic run disagrees with its exact calendar root.")
  }

  func verifyAutomationCausality() throws {
    try require(
      try db.scalar(
        "SELECT EXISTS(SELECT 1 FROM automation_runs a LEFT JOIN automatic_admissions c ON c.run_id=a.run_id WHERE c.run_id IS NULL)"
      ).int == 0,
      "causal_integrity", "An automatic workflow lost its retained origin admission.")
    try require(
      try db.scalar(
        "SELECT EXISTS(SELECT 1 FROM automatic_roots r LEFT JOIN automatic_root_members m ON m.root_id=r.id WHERE m.run_id IS NULL)"
      ).int == 0,
      "causal_integrity", "An automatic root has no admitted work.")
    var after = ""
    while true {
      let rows = try db.execute(
        "SELECT run_id FROM automatic_admissions WHERE run_id>? ORDER BY run_id LIMIT 100",
        [.string(after)])
      if rows.isEmpty { break }
      for row in rows {
        after = row["run_id"]!.text
        _ = try automationCausalGraph([after])
      }
    }
  }
}
