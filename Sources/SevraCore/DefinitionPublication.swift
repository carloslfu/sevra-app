import Foundation

extension Workbook {
  /// Publication recomputes under the canonical write lock; a client-supplied
  /// evaluation can select an exact preview, but cannot supply new result values.
  @discardableResult public func publishApplicationResult(
    _ id: String, arguments: Value, evaluation: Value, title: String,
    meaning: String, scenario: String = "actual", inputs: [String] = [], token: String,
    readOnly: Bool = false, actor: ChangeActor? = nil, requestRunID: String? = nil,
    requestSourceID: String? = nil, cancellation: Cancellation = .init()
  ) throws -> Item {
    try require(!readOnly, "read_only_request", "Inspection does not permit result publication.")
    try require(
      !token.isEmpty && token.utf8.count <= 256 && inputs.count <= 128
        && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && title.utf8.count <= 500 && !scenario.isEmpty && scenario.utf8.count <= 256
        && ["actual", "estimate", "plan", "commitment", "assumption", "rule"].contains(meaning),
      "definition_publication", "Use a bounded title, explicit meaning/scenario and retry identity."
    )
    let actual =
      actor ?? ChangeAttribution.actor ?? .programmatic("SevraCore.publishApplicationResult")
    let request: Value = .object([
      "id": .string(id), "arguments": arguments, "evaluation": evaluation, "title": .string(title),
      "meaning": .string(meaning), "scenario": .string(scenario),
      "inputs": .array(inputs.map(Value.string)),
      "requestRunID": requestRunID.map(Value.string) ?? .null,
      "requestSourceID": requestSourceID.map(Value.string) ?? .null,
    ])
    try require(
      try request.json().utf8.count <= 1_048_576, "definition_limit",
      "Result publication request exceeds 1 MiB. Select a smaller result.")
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    let saved = try mutation(
      "publish_application_result", token: token, request: request, cancellation: control,
      actor: actual
    ) {
      if let requestRunID {
        try validateApplicationToolRun(requestRunID, requestSourceID: requestSourceID)
      }
      let fresh = try evaluateApplicationDefinition(id, arguments: arguments, cancellation: control)
      func comparable(_ value: Value) -> Value {
        var fields = value.object
        if value["kind"] == .string("query") {
          var query = value["result"].object
          // Conversation/presentation writes can advance revision without changing
          // the captured definition/data family snapshots or any returned value.
          query.removeValue(forKey: "revision")
          fields["result"] = .object(query)
        }
        return .object(fields)
      }
      try require(
        comparable(evaluation) == comparable(fresh), "stale_evaluation",
        "The evaluation no longer matches this workbook snapshot. Refresh it before publishing.")
      try require(
        fresh["nextCursor"] == .null && fresh["result"]["hasMore"] != .bool(true),
        "partial_evaluation", "Publish a complete bounded query result; this page has more rows.")
      var parents = Set(inputs)
      var controls = Set<String>()
      if let requestSourceID { parents.insert(requestSourceID) }
      for input in parents {
        try require(
          try item(input).id == input, "definition_input", "Publication inputs need exact versions."
        )
      }
      for resolved in fresh["resolvedDefinitions"].array {
        controls.insert(resolved["sourceID"].text)
      }
      var population: [Value] = []
      if fresh["kind"] == .string("query") {
        population = try definitionQueryPopulation(fresh, cancellation: control)
        for source in population {
          controls.insert(source["sourceID"].text)
          for row in source["rows"].array { parents.insert(row["versionID"].text) }
        }
      }
      let descriptor = try DefinitionDescriptor(
        applicationDefinition(fresh["definitionID"].text).content)
      func itemArguments(_ parameters: [DefinitionParameter], _ supplied: Value) {
        for parameter in parameters {
          let value = supplied[parameter.id]
          if parameter.type == "item", let id = value.string { parents.insert(id) }
          if parameter.type == "entries" {
            for row in value.array { itemArguments(parameter.fields, row) }
          }
        }
      }
      itemArguments(descriptor.parameters, fresh["arguments"])
      let data: Value = .object([
        "evaluation": fresh, "inputPopulation": .array(population),
        "captured": .string(timestamp()),
        "populationScope": .string(
          "Exact scoped input population at publication; may include candidates removed by filters or joins. Not per-group membership."
        ),
        "submittedInputs": .array(inputs.map(Value.string)),
      ])
      try require(
        try data.json().utf8.count <= 524_288, "definition_limit",
        "The published values and provenance exceed 512 KiB. Narrow the result.")
      try control.check()
      let invocation = try insertItem(
        category: "source", kind: "application_invocation", title: "Published " + title,
        text: actual.label + " supplied these arguments and requested a draft calculation result.",
        data: .object([
          "definitionID": fresh["definitionID"], "arguments": arguments,
          "resolvedDefinitions": fresh["resolvedDefinitions"],
          "producerPolicy": .string("application-result-v1"),
          "actor": try encoded(actual), "meaning": .string(meaning), "scenario": .string(scenario),
          "inputs": .array(inputs.map(Value.string)),
        ]),
        meaning: "actual", status: "accepted", scenario: "actual", inputs: parents.sorted(),
        transformation: "application-result-request-v1", controlInputs: controls.sorted())
      let result = try insertItem(
        category: "record", kind: "calculation", title: title,
        text: title + "\n" + meaning + " · " + scenario + "\n" + definitionResultText(fresh),
        data: data, meaning: meaning, status: "draft", scenario: scenario, inputs: parents.sorted(),
        transformation: "application-result-v1; exact definition=" + fresh["definitionID"].text,
        controlInputs: controls.sorted(), producerInputs: [invocation])
      try control.check()
      return .string(result)
    }
    return try item(saved.text)
  }

  /// Deterministic reading/search text complements typed retained values. Query
  /// cells must be discoverable without indexing unrelated candidate inputs.
  private func definitionResultText(_ evaluation: Value) -> String {
    if evaluation["kind"] == .string("function") {
      return evaluation["result"].text + (evaluation["unit"].string.map { " " + $0 } ?? "")
    }
    let columns = evaluation["result"]["columns"].array
    let rows = evaluation["result"]["rows"].array
    return "\(rows.count) query result rows.\n"
      + rows.enumerated().map { index, row in
        "\(index + 1). "
          + columns.map { column in
            let value = row["values"][column["id"].text]
            return column["title"].text + ": "
              + (value == .null ? "Unknown" : value.text.isEmpty ? "Empty" : value.text)
              + (column["unit"].string.map { " " + $0 } ?? "")
          }.joined(separator: "; ")
      }.joined(separator: "\n")
  }

  func definitionQueryPopulation(_ evaluation: Value, cancellation: Cancellation) throws
    -> [Value]
  {
    var count = 0
    return try evaluation["result"]["sources"].array.map { source in
      try cancellation.check()
      let dataset = source["datasetID"].text
      let schema = try db.managedSchema(dataset)
      let definition = try savedDatasetDefinition(
        dataset, definitionID: source["definitionID"].text)
      let scope = source["scope"].object
      try require(
        Set(scope.keys).isSubset(of: ["meaning", "status", "scenario"]), "query_scope",
        "Use declared business scopes.")
      var arguments: [Value] = []
      let filters = scope.keys.sorted().map { key -> String in
        arguments.append(scope[key]!)
        return "i." + ChangeFormat.quote(key) + "=?"
      }
      let rows = try db.execute(
        "SELECT n._sevra_row AS rowID,n._sevra_item AS versionID,i.logical_id AS logicalID,i.meaning,i.status,i.scenario FROM "
          + ChangeFormat.quote(schema.table) + " n JOIN items i ON i.id=n._sevra_item"
          + (filters.isEmpty ? "" : " WHERE " + filters.joined(separator: " AND "))
          + " ORDER BY n._sevra_ordinal,n._sevra_row LIMIT ?",
        arguments + [.number(Double(5001 - count))])
      count += rows.count
      try require(
        count <= 5000, "definition_limit",
        "Saved results retain at most 5,000 scoped input versions. Narrow the query scope.")
      return .object([
        "datasetID": .string(dataset), "definitionID": .string(definition.id),
        "sourceID": .string(definition.sourceID), "scope": .object(scope),
        "rows": .array(rows.map(Value.object)),
      ])
    }
  }
}
