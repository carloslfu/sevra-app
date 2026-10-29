import Foundation

extension Workbook {
  func workflowLookupColumn(
    _ definition: ApplicationDefinition, field: String, historical: Bool
  ) throws -> Column {
    let raw = try resolvedDefinitionQuery(
      DefinitionDescriptor(definition.content), arguments: [:], samples: true,
      verifyHistorical: historical)
    let query = try DatasetQuery(raw)
    try require(
      query.sources.count == 1 && !query.grouped, "workflow_lookup",
      "A scalar lookup needs one ungrouped table, without joins or aggregates.")
    guard
      let column = try compileDatasetQuery(query, historicalDefinitions: historical).columns
        .first(where: { $0.id == field })
    else { throw SevraError("workflow_lookup", "Select an existing query output field.") }
    return column
  }

  /// Validate every consumer before saving a completed lookup. Missing/ambiguous
  /// matches remain unfinished, so explicit retry can reread a repaired catalog
  /// without rerunning the completed preparation or model prefix.
  func validateWorkflowLookupResult(
    _ output: Value, stepID: String, workflow: DefinitionWorkflow
  ) throws {
    var targets: [(String, DefinitionParameter)] = []
    for step in workflow.steps {
      for (name, mapping) in step.arguments where mapping["step"] == .string(stepID) {
        guard let field = mapping["field"].string, let binding = step.binding,
          let parameter = try DefinitionDescriptor(resolveDefinition(binding).content).parameters
            .first(where: { $0.id == name })
        else { throw SevraError("workflow_lookup", "The lookup consumer lost its typed field.") }
        targets.append((field, parameter))
      }
    }
    guard !targets.isEmpty else { return }
    let rows = output["result"]["rows"].array
    try require(
      output["kind"] == .string("query") && output["nextCursor"] == .null
        && output["result"]["hasMore"] == .bool(false) && rows.count == 1,
      "workflow_lookup",
      "Lookup needs exactly one complete match; found \(rows.count). Inspect the catalog and query, then explicitly retry. No row was selected."
    )
    for (field, parameter) in targets {
      guard let value = rows[0]["values"].object[field], value != .null,
        value.string.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true
      else {
        throw SevraError(
          "workflow_lookup",
          "Lookup field \(field) is unknown or empty. Resolve it before retrying.")
      }
      _ = try parameter.normalize(value)
    }
  }
}
