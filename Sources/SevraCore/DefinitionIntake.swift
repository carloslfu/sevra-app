import Foundation

/// One explicit reusable CSV/TSV mapping over an exact managed-table schema.
/// The invocation supplies an included original; no path or parser is inferred.
struct DefinitionIntake {
  let file: String
  let datasetID: String
  let definitionID: String
  let mode: TableUpdateMode
  let mapping: [IntakeColumnMapping]
  let keys: [String]
  let headerRow: Int
  let meaning: String
  let scenario: String

  init(_ descriptor: DefinitionDescriptor) throws {
    let p = try definitionObject(
      descriptor.payload,
      keys: [
        "parser", "file", "datasetID", "definitionID", "mode", "mapping", "keys", "headerRow",
        "newRowMeaning", "newRowScenario",
      ])
    guard p["parser"] == .string(DefinitionExtraction.parser), let file = p["file"]?.string,
      descriptor.parameters.count == 1, let parameter = descriptor.parameters.first,
      parameter.id == file && parameter.type == "item" && parameter.required
        && parameter.defaultValue == nil && parameter.unit == nil,
      let dataset = p["datasetID"]?.string, UUID(uuidString: dataset) != nil,
      let definition = p["definitionID"]?.string, UUID(uuidString: definition) != nil,
      let mode = p["mode"]?.string.flatMap(TableUpdateMode.init(rawValue:)),
      case .array(let rawMapping) = p["mapping"], (1...2000).contains(rawMapping.count),
      case .array(let keys) = p["keys"], keys.allSatisfy({ $0.string != nil }),
      let header = p["headerRow"]?.int, p["headerRow"] == .number(Double(header)),
      (1...1001).contains(header), let meaning = p["newRowMeaning"]?.string,
      ["actual", "estimate", "plan", "commitment", "assumption", "rule"].contains(meaning),
      let scenario = p["newRowScenario"]?.string,
      !scenario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      scenario.utf8.count <= 256
    else {
      throw SevraError(
        "intake_definition",
        "Declare native-v1, one required file item parameter, an exact dataset/schema, append/replace/merge, full mappings, keys, header row and incoming-row meaning/scenario."
      )
    }
    let mapping = try rawMapping.map { value -> IntakeColumnMapping in
      let o = try definitionObject(value, keys: ["position", "target"])
      guard let position = o["position"]?.int,
        o["position"] == .number(Double(position)), (0..<2000).contains(position),
        o["target"] == .null || o["target"]?.string != nil
      else { throw SevraError("update_mapping", "Map or explicitly ignore each input position.") }
      return .init(position: position, target: o["target"]?.string)
    }
    let targets = mapping.compactMap(\.target)
    try require(
      Set(mapping.map(\.position)) == Set(0..<mapping.count)
        && Set(targets).count == targets.count,
      "update_mapping", "Map each consecutive input position and target at most once.")
    self.file = file
    datasetID = dataset
    definitionID = definition
    self.mode = mode
    self.mapping = mapping
    self.keys = keys.map(\.text)
    headerRow = header
    self.meaning = meaning
    self.scenario = scenario
    try require(
      Set(self.keys).count == self.keys.count
        && (mode == .merge ? !self.keys.isEmpty : self.keys.isEmpty)
        && Set(self.keys).isSubset(of: Set(targets)),
      "update_keys", "Merge needs explicit unique mapped keys; append/replace take no keys.")
  }
}

extension Workbook {
  func validateIntakeDefinition(_ descriptor: DefinitionDescriptor, historical: Bool = false) throws
  {
    let intake = try DefinitionIntake(descriptor)
    let schema = try savedDatasetDefinition(intake.datasetID, definitionID: intake.definitionID)
    try require(
      Set(intake.mapping.compactMap(\.target))
        == Set(schema.columns.filter { $0.formula == nil }.map(\.id)),
      "update_mapping", "Map every stored target column; calculated columns cannot be imported.")
    if !historical {
      let table = try dataset(intake.datasetID)
      try require(
        !table.archived && table.definitionID == schema.id, "stale_schema",
        "The intake's target schema changed. Review a new mapping explicitly.")
    }
  }
}
