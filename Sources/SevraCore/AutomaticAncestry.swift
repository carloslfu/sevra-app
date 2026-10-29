import Foundation

/// Inspects retained derivation provenance. This is not a minimal causal slice,
/// a device grant or an admission decision for another automatic run.
extension Workbook {
  public func automaticDerivationAncestry(
    inputs: [String], cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      (1...16).contains(inputs.count)
        && inputs.allSatisfy { !$0.isEmpty && $0.utf8.count <= 256 },
      "ancestry_input", "Inspect 1 to 16 exact item versions, each up to 256 UTF-8 bytes.")
    return try readBusinessFeed(cancellation: cancellation) {
      var graph = DerivationInspectionGraph()
      var queue = Array(Set(inputs)).sorted()
      var discovered = Set(queue)
      var index = 0
      while index < queue.count {
        try cancellation.check()
        let id = queue[index]
        index += 1
        guard
          let item = try db.execute(
            "SELECT id,category,kind,supersedes FROM items WHERE id=?", [.string(id)],
            maxRows: 1, maxBytes: 65_536
          ).first
        else { throw SevraError("ancestry_item", "An exact input or ancestor version is missing.") }
        if let binding = try automaticAncestryBinding(item) {
          graph.runs.append(binding)
        }
        let remaining = 4096 - graph.edges.count
        let parents = try db.execute(
          "SELECT child,parent,relation,transformation,roles FROM lineage WHERE child=? ORDER BY parent,relation LIMIT ?",
          [.string(id), .number(Double(remaining + 1))], maxRows: remaining + 1,
          maxBytes: 2_097_152)
        try require(
          parents.count <= remaining, "ancestry_limit",
          "The derivation exceeds 4,096 edges. No partial ancestry was returned.")
        if let previous = item["supersedes"]?.string {
          try require(
            parents.contains {
              $0["parent"] == .string(previous) && $0["relation"] == .string("supersedes")
            }, "ancestry_integrity", "A revision is missing its retained supersession edge.")
        }
        graph.parents[id] = Set(parents.map { $0["parent"]!.text })
        for edge in parents {
          try cancellation.check()
          try require(
            ["derives-from", "supersedes", "definition-input"].contains(edge["relation"]!.text),
            "ancestry_integrity", "The derivation contains an unsupported lineage relation.")
          graph.edges.append(try ItemDerivation.publicEdge(edge))
          let parent = edge["parent"]!.text
          if discovered.insert(parent).inserted {
            try require(
              discovered.count <= 1024, "ancestry_limit",
              "The derivation exceeds 1,024 item versions. No partial ancestry was returned.")
            queue.append(parent)
          }
        }
      }
      let depth = try graph.depth(cancellation: cancellation)
      let result: Value = .object([
        "workbookID": .string(self.id), "policy": .string("automatic-derivation-ancestry-v1"),
        "inputs": .array(Set(inputs).sorted().map(Value.string)),
        "itemCount": .number(Double(graph.parents.count)),
        "edgeCount": .number(Double(graph.edges.count)),
        "maximumLineageDepth": .number(Double(depth)),
        "automaticRuns": .array(graph.runs.sorted { $0["runID"].text < $1["runID"].text }),
        "automationLogicalIDs": .array(
          Set(graph.runs.map { $0["automationLogicalID"].text }).sorted().map(Value.string)),
        "edges": .array(graph.edges), "coverage": .string("retained-derivation-graph"),
        "minimalCausalSlice": .bool(false), "dispatchEligibility": .string("not-evaluated"),
        "execution": .string("none"), "enabled": .bool(false),
      ])
      try boundedBusinessOutput(result)
      return result
    }
  }

  func automaticAncestryBinding(_ item: [String: Value]) throws -> Value? {
    let source = item["id"]!.text
    let registered = try db.execute(
      "SELECT w.id,w.source_id,w.policy,w.definition_id,a.run_id,a.occurrence_id,a.activation_id,a.definition_id AS automation_id,a.authorization_source,a.dispatch_source,a.generation,d.logical_id,d.kind FROM workflow_runs w LEFT JOIN automation_runs a ON a.run_id=w.id LEFT JOIN app_definitions d ON d.id=a.definition_id WHERE w.source_id=?",
      [.string(source)], maxRows: 1, maxBytes: 65_536
    ).first
    if item["kind"] != .string("application_invocation") && registered == nil { return nil }
    try require(
      item["category"] == .string("source") && item["kind"] == .string("application_invocation"),
      "ancestry_integrity", "A saved workflow source has inconsistent invocation identity.")
    let raw = try db.scalar(
      "SELECT CASE WHEN length(CAST(data AS BLOB))<=1048576 THEN data END FROM items WHERE id=?",
      [.string(source)])
    try require(
      raw != .null, "ancestry_limit",
      "An invocation exceeds the 1 MiB inspection bound. No partial ancestry was returned.")
    let data = try Value.parse(raw.text)
    guard let run = registered else {
      try require(
        data["workflowRunID"] == .null && data["policy"] != .string("automation-drafts-v1"),
        "ancestry_integrity", "An invocation claims a workflow without its exact saved binding.")
      return nil
    }
    let runID = run["id"]!.text
    try require(
      run["id"] == data["workflowRunID"] && run["policy"] == data["policy"]
        && run["definition_id"] == data["definitionID"],
      "ancestry_integrity", "The invocation does not match its exact saved workflow run.")
    if run["policy"] == .string("manual-drafts-v1") {
      try require(
        run["run_id"] == .null, "ancestry_integrity",
        "A manual workflow has an inconsistent automatic binding.")
      return nil
    }
    let origin = data["origin"]
    try require(
      run["policy"] == .string("automation-drafts-v1") && run["kind"] == .string("automation")
        && run["run_id"] == .string(runID) && origin["automationID"] == run["automation_id"]
        && origin["occurrenceID"] == run["occurrence_id"]
        && origin["activationID"] == run["activation_id"]
        && origin["authorizationSourceID"] == run["authorization_source"]
        && origin["dispatchSourceID"] == run["dispatch_source"]
        && origin["generation"] == run["generation"],
      "ancestry_integrity",
      "The automatic invocation is missing or disagrees with its saved binding.")
    return .object([
      "runID": .string(runID), "invocationSourceID": .string(source),
      "workflowDefinitionID": run["definition_id"]!,
      "automationDefinitionID": run["automation_id"]!,
      "automationLogicalID": run["logical_id"]!, "occurrenceID": run["occurrence_id"]!,
      "activationID": run["activation_id"]!, "authorizationSourceID": run["authorization_source"]!,
      "dispatchSourceID": run["dispatch_source"]!, "generation": run["generation"]!,
    ])
  }
}

struct DerivationInspectionGraph {
  var parents: [String: Set<String>] = [:]
  var edges: [Value] = []
  var runs: [Value] = []

  /// Topological traversal distinguishes shared DAG parents from a cycle and
  /// measures the longest path, including a node first reached by a shorter path.
  func depth(cancellation: Cancellation) throws -> Int {
    var remaining = parents.mapValues(\.count)
    var children: [String: [String]] = [:]
    for (child, values) in parents {
      for parent in values { children[parent, default: []].append(child) }
    }
    var queue = parents.keys.filter { remaining[$0] == 0 }.sorted()
    var distances: [String: Int] = [:]
    var index = 0
    var maximum = 0
    while index < queue.count {
      try cancellation.check()
      let current = queue[index]
      index += 1
      let distance = distances[current, default: 0]
      maximum = max(maximum, distance)
      try require(
        maximum <= 128, "ancestry_limit",
        "The derivation exceeds 128 lineage edges in depth. No partial ancestry was returned.")
      for child in children[current, default: []] {
        distances[child] = max(distances[child, default: 0], distance + 1)
        remaining[child, default: 0] -= 1
        if remaining[child] == 0 { queue.append(child) }
      }
    }
    try require(
      index == parents.count, "ancestry_cycle",
      "The retained derivation contains a cycle. No complete ancestry was returned.")
    return maximum
  }
}
