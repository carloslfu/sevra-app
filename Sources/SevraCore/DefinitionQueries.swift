import Foundation

extension Workbook {
  /// Resolve only declared filter parameters and current schema bindings. Exact
  /// schema mode still reads current rows; it is never a frozen business result.
  func resolvedDefinitionQuery(
    _ descriptor: DefinitionDescriptor, arguments: [String: Value], samples: Bool = false,
    verifyHistorical: Bool = false
  ) throws -> Value {
    let payload = try definitionObject(descriptor.payload, keys: ["query", "dataMode"])
    guard let raw = payload["query"], let mode = payload["dataMode"]?.string,
      ["live", "exact"].contains(mode)
    else {
      throw SevraError(
        "definition_query", "A query needs a managed query template and live/exact dataMode.")
    }
    var query = try queryObject(
      raw, keys: ["sources", "joins", "select", "filters", "groupBy", "sort", "limit"])
    guard case .array(let originalSources) = query["sources"],
      (1...3).contains(originalSources.count)
    else {
      throw SevraError("definition_query", "Declare one to three dataset sources.")
    }
    var referenced: Set<QueryColumn> = []
    // Parse after substitution, then compare all referenced schema meanings.
    if let rawFilters = query["filters"] {
      guard case .array(let filters) = rawFilters, filters.count <= 24 else {
        throw SevraError("definition_query", "Use at most 24 filters.")
      }
      query["filters"] = .array(
        try filters.map { raw in
          var filter = try queryObject(raw, keys: ["column", "op", "value"])
          if let value = filter["value"], case .object = value {
            let binding = try definitionObject(value, keys: ["parameter"])
            guard let name = binding["parameter"]?.string,
              let parameter = descriptor.parameters.first(where: { $0.id == name }),
              ["text", "decimal", "boolean", "date", "choice"].contains(parameter.type),
              let column = filter["column"]
            else {
              throw SevraError(
                "definition_query", "A query filter must bind a declared scalar parameter.")
            }
            let reference = try QueryColumn(column)
            try require(
              reference.source < originalSources.count, "definition_query", "Unknown filter source."
            )
            let source = originalSources[reference.source]
            let schema = try savedDatasetDefinition(
              source["datasetID"].text, definitionID: source["definitionID"].text)
            guard
              let field = schema.columns.first(where: {
                $0.id == reference.column && $0.formula == nil
              })
            else {
              throw SevraError(
                "query_column", "The query parameter targets an unavailable stored column.")
            }
            try require(
              field.type == (parameter.type == "choice" ? "text" : parameter.type)
                && field.unit == parameter.unit,
              "definition_unit", "Query filter parameter and column types/units must match.")
            guard let supplied = samples ? parameter.sample : arguments[name], supplied != .null
            else {
              throw SevraError(
                "definition_input", "This query needs filter parameter " + parameter.label + ".")
            }
            filter["value"] = supplied
          }
          return .object(filter)
        })
    }
    let parsed = try DatasetQuery(.object(query))
    referenced.formUnion(parsed.selections.compactMap(\.column))
    referenced.formUnion(parsed.filters.map(\.column))
    referenced.formUnion(parsed.groups)
    for (index, join) in parsed.joins.enumerated() {
      referenced.insert(join.left)
      referenced.insert(
        try QueryColumn(
          .object(["source": .number(Double(index + 1)), "column": .string(join.right)])))
    }
    query["sources"] = .array(
      try originalSources.enumerated().map { index, raw in
        var source = try queryObject(raw, keys: ["datasetID", "definitionID", "scope"])
        let saved = try savedDatasetDefinition(
          source["datasetID"]?.text ?? "", definitionID: source["definitionID"]?.text ?? "")
        let current = try datasetDefinition(saved.datasetID)
        if mode == "live" && !verifyHistorical {
          for reference in referenced where reference.source == index {
            guard let old = saved.columns.first(where: { $0.id == reference.column }),
              let fresh = current.columns.first(where: { $0.id == reference.column }),
              old.type == fresh.type && old.unit == fresh.unit && old.formula == fresh.formula
            else {
              throw SevraError(
                "definition_schema",
                "A live query column changed meaning. Review and save the query again.")
            }
          }
          source["definitionID"] = .string(current.id)
        }
        return .object(source)
      })
    let result = Value.object(query)
    _ = try compileDatasetQuery(DatasetQuery(result), historicalDefinitions: verifyHistorical)
    return result
  }
}
