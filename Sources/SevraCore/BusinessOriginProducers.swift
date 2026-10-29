import Foundation

extension Workbook {
  /// Validate producer metadata without reading unrelated bodies or running any
  /// workflow. Incoming producer links cannot be hidden by relabeling a Source.
  func businessOriginProducer(
    _ item: [String: Value], edges: [[String: Value]],
    admissions: inout [String: AutomationCausalNode], cancellation: Cancellation
  ) throws -> Value? {
    let id = item["id"]!.text
    let registered = try db.execute(
      "SELECT w.id,w.definition_id,w.policy,CASE WHEN length(CAST(w.arguments AS BLOB))<=1048576 THEN w.arguments END AS arguments,CASE WHEN length(CAST(w.actor AS BLOB))<=65536 THEN w.actor END AS actor,d.kind,d.source_id,CASE WHEN length(CAST(d.parameters AS BLOB))<=65536 THEN d.parameters END AS parameters FROM workflow_runs w LEFT JOIN app_definitions d ON d.id=w.definition_id WHERE w.source_id=?",
      [.string(id)], maxRows: 1, maxBytes: 1_200_000
    ).first
    let usedAsProducer =
      try db.scalar(
        "SELECT EXISTS(SELECT 1 FROM lineage WHERE parent=? AND (roles & 4)<>0)", [.string(id)]
      ).int == 1
    if item["kind"] != .string("application_invocation") && registered == nil && !usedAsProducer {
      return nil
    }
    try require(
      item["category"] == .string("source") && item["kind"] == .string("application_invocation"),
      "origin_producer", "A retained producer has inconsistent invocation identity.")
    let raw = try db.scalar(
      "SELECT CASE WHEN length(CAST(data AS BLOB))<=1048576 THEN data END FROM items WHERE id=?",
      [.string(id)])
    try require(raw != .null, "origin_limit", "Producer metadata exceeds 1 MiB.")
    guard let data = try? Value.parse(raw.text), case .object = data else {
      throw SevraError("origin_producer", "Producer metadata is malformed.")
    }
    let binding = try automaticAncestryBinding(item)
    if let registered {
      try validateBusinessWorkflowProducer(registered, data: data, edges: edges)
      if let binding {
        let runID = binding["runID"].text
        if admissions[runID] == nil {
          let graph = try automationCausalGraph([runID], cancellation: cancellation)
          admissions.merge(graph) { saved, _ in saved }
        }
        var result = binding.object
        result["admission"] = admissions[runID]!.context
        result["boundary"] = .string("authoritative-automatic-producer")
        return .object(result)
      }
      return nil
    }
    try require(
      binding == nil, "origin_producer", "An automatic producer lost its exact registration.")
    try validateDirectBusinessProducer(data, edges: edges)
    return nil
  }

  private func originRole(
    _ edges: [[String: Value]], parent: String, contains role: Int
  ) throws {
    try require(
      edges.contains {
        $0["parent"] == .string(parent) && $0["relation"] == .string("derives-from")
          && ($0["roles"]!.int! & role) == role
      }, "origin_producer", "A producer lost an exact declared input role.")
  }

  private func validateBusinessWorkflowProducer(
    _ run: [String: Value], data: Value, edges: [[String: Value]]
  ) throws {
    try require(
      run["arguments"] != .null && run["actor"] != .null && run["parameters"] != .null,
      "origin_limit", "Saved workflow producer metadata exceeds its inspection bound.")
    let arguments = try Value.parse(run["arguments"]!.text)
    let actor = try Value.parse(run["actor"]!.text)
    let rawParameters = try Value.parse(run["parameters"]!.text)
    try require(
      run["kind"] == .string("workflow") && data["workflowRunID"] == run["id"]
        && data["definitionID"] == run["definition_id"] && data["policy"] == run["policy"]
        && data["normalizedArguments"] == arguments && data["actor"] == actor,
      "origin_producer", "The invocation disagrees with its exact saved workflow producer.")
    try JSONDecoder().decode(ChangeActor.self, from: Data(actor.json().utf8)).validate()
    let normalized = try businessOriginArguments(
      rawParameters, submitted: data["arguments"], edges: edges)
    try require(
      arguments == normalized, "origin_producer", "The retained producer arguments changed.")
    try originRole(edges, parent: run["source_id"]!.text, contains: DerivationRole.control)
  }

  private func businessOriginArguments(
    _ raw: Value, submitted value: Value, edges: [[String: Value]]
  ) throws -> Value {
    guard case .array(let parameters) = raw, parameters.count <= 32,
      case .object(let submitted) = value
    else {
      throw SevraError("origin_producer", "The producer lost its declared arguments.")
    }
    let parsed = try parameters.map { try DefinitionParameter($0) }
    try require(
      Set(submitted.keys).isSubset(of: Set(parsed.map(\.id))), "origin_producer",
      "The producer has undeclared arguments.")
    var normalized: [String: Value] = [:]
    for parameter in parsed {
      if let value = submitted[parameter.id] ?? parameter.defaultValue {
        normalized[parameter.id] = try parameter.normalize(value)
      } else {
        try require(
          !parameter.required, "origin_producer", "A required producer argument is missing.")
      }
    }
    func items(_ parameters: [DefinitionParameter], _ values: Value) throws {
      for parameter in parameters {
        let value = values[parameter.id]
        if parameter.type == "item", let id = value.string {
          try originRole(edges, parent: id, contains: DerivationRole.data)
        }
        if parameter.type == "entries" {
          for row in value.array { try items(parameter.fields, row) }
        }
      }
    }
    try items(parsed, .object(normalized))
    return .object(normalized)
  }

  private func validateDirectBusinessProducer(_ data: Value, edges: [[String: Value]]) throws {
    try JSONDecoder().decode(ChangeActor.self, from: Data(data["actor"].json().utf8)).validate()
    let resolved: [Value]
    let root: String
    let submitted: Value
    let expected: Value?
    let kinds: Set<String>
    switch data["producerPolicy"].text {
    case "application-action-v1":
      var plan = data["plan"].object
      let fingerprint = plan.removeValue(forKey: "fingerprint")
      try require(
        !plan.isEmpty && fingerprint == .string(ChangeFormat.hash(try Value.object(plan).json())),
        "origin_producer", "The direct action lost its exact retained plan fingerprint.")
      resolved = data["plan"]["resolvedDefinitions"].array
      root = data["plan"]["definitionID"].text
      submitted = data["plan"]["submittedArguments"]
      expected = data["plan"]["arguments"]
      kinds = ["action", "form"]
      try require(
        data["plan"]["workbookID"] == .string(id)
          && data["submitted"]["arguments"] == submitted, "origin_producer",
        "The action submission disagrees with its retained plan.")
      try originRole(
        edges, parent: data["plan"]["primitiveArguments"]["evidence"].text,
        contains: DerivationRole.data)
    case "application-result-v1":
      resolved = data["resolvedDefinitions"].array
      root = data["definitionID"].text
      submitted = data["arguments"]
      expected = nil
      kinds = ["function", "query"]
      guard case .array(let inputs) = data["inputs"], inputs.count <= 128 else {
        throw SevraError("origin_producer", "The result producer lost its explicit input list.")
      }
      for input in inputs {
        try originRole(edges, parent: input.text, contains: DerivationRole.data)
      }
    default:
      throw SevraError("origin_producer", "The direct invocation has no supported producer policy.")
    }
    try require(
      !resolved.isEmpty && resolved.count <= 128 && resolved.contains { $0["id"] == .string(root) },
      "origin_producer", "The direct producer lost its exact resolved definitions.")
    guard
      let rootDefinition = try db.execute(
        "SELECT kind,CASE WHEN length(CAST(parameters AS BLOB))<=65536 THEN parameters END AS parameters FROM app_definitions WHERE id=?",
        [.string(root)], maxRows: 1, maxBytes: 65_536
      ).first
    else {
      throw SevraError("origin_producer", "The exact producer definition is missing.")
    }
    try require(
      kinds.contains(rootDefinition["kind"]!.text), "origin_producer",
      "The producer kind is inconsistent.")
    try require(
      rootDefinition["parameters"] != .null, "origin_limit", "Producer parameters exceed 64 KiB.")
    let normalized = try businessOriginArguments(
      Value.parse(rootDefinition["parameters"]!.text), submitted: submitted, edges: edges)
    if let expected {
      try require(expected == normalized, "origin_producer", "The producer arguments changed.")
    }
    for definition in resolved {
      let saved = try db.execute(
        "SELECT id,source_id FROM app_definitions WHERE id=?", [definition["id"]],
        maxRows: 1, maxBytes: 65_536
      ).first
      try require(
        saved?["source_id"] == definition["sourceID"], "origin_producer",
        "The direct producer disagrees with its exact definition Source.")
      try originRole(edges, parent: definition["sourceID"].text, contains: DerivationRole.control)
    }
  }
}
