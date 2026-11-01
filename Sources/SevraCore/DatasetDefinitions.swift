import Foundation

public struct DatasetDefinition: Codable, Identifiable, Sendable {
  public let id: String
  public let datasetID: String
  public let version: Int
  public let previousID: String?
  public let title: String
  public let columns: [Column]
  public let archived: Bool
  public let sourceID: String
  public let created: String

  init(_ row: [String: Value]) throws {
    guard let id = row["id"]?.string, UUID(uuidString: id) != nil,
      let datasetID = row["dataset_id"]?.string, UUID(uuidString: datasetID) != nil,
      let version = row["version"]?.int, (1...1_000_000_000).contains(version),
      row["version"] == .number(Double(version)), let title = row["title"]?.string,
      let raw = row["columns"]?.string, let sourceID = row["source_id"]?.string,
      UUID(uuidString: sourceID) != nil, let created = row["created"]?.string,
      row["archived"] == .number(0) || row["archived"] == .number(1),
      row["previous_id"] == .null
        || row["previous_id"]?.string.flatMap(UUID.init(uuidString:)) != nil
    else {
      throw SevraError(
        "managed_schema",
        "The saved table definition is malformed. Preserve this workbook for recovery.")
    }
    self.id = id
    self.datasetID = datasetID
    self.version = version
    previousID = row["previous_id"]?.string
    self.title = title
    columns = try JSONDecoder().decode([Column].self, from: Data(raw.utf8))
    try ManagedDatasetSchema.validateColumns(columns)
    archived = row["archived"]?.int == 1
    self.sourceID = sourceID
    self.created = created
  }
}

extension Workbook {
  public func datasetDefinition(_ id: String) throws -> DatasetDefinition {
    try synchronized {
      guard
        let row = try db.execute(
          "SELECT v.* FROM datasets d JOIN column_versions v ON v.id=d.definition_id WHERE d.id=?",
          [.string(id)]
        ).first
      else {
        throw SevraError("managed_schema", "The current table definition is missing.")
      }
      return try DatasetDefinition(row)
    }
  }
  public func datasetDefinitions(_ id: String, beforeVersion: Int? = nil, limit: Int = 20) throws
    -> [DatasetDefinition]
  {
    try require(
      beforeVersion == nil || beforeVersion! > 0, "history", "Choose a positive history version.")
    return try synchronized {
      _ = try dataset(id)
      return try db.execute(
        "SELECT * FROM column_versions WHERE dataset_id=? AND version<? ORDER BY version DESC LIMIT ?",
        [
          .string(id), .number(Double(beforeVersion ?? 1_000_000_001)),
          .number(Double(min(max(limit, 1), 50))),
        ]
      )
      .map(DatasetDefinition.init)
    }
  }
  @discardableResult public func updateDatasetDefinition(
    _ id: String, expectedVersion: Int, expectedDefinitionID: String,
    title: String? = nil, columns: [Column]? = nil, archived: Bool? = nil,
    token: String = identifier(), actor: ChangeActor? = nil, cancellation: Cancellation = .init()
  ) throws -> DatasetDefinition {
    try require(
      title != nil || columns != nil || archived != nil,
      "dataset_definition", "Choose a table definition change.")
    let request: Value = .object([
      "datasetID": .string(id), "baseVersion": .number(Double(expectedVersion)),
      "baseDefinitionID": .string(expectedDefinitionID), "title": title.map(Value.string) ?? .null,
      "columns": try columns.map { try encoded($0) } ?? .null,
      "archived": archived.map(Value.bool) ?? .null,
    ])
    return try mutation(
      "dataset_definition", token: token, request: request,
      cancellation: cancellation,
      actor: actor ?? ChangeAttribution.actor ?? .programmatic("SevraCore.datasetDefinition"),
      deadlineSeconds: 30,
      reading: { try savedDatasetDefinition(id, definitionID: $0.text) }
    ) {
      try checkDatasetBase(id, version: expectedVersion, definitionID: expectedDefinitionID)
      return .string(
        try applyDatasetDefinition(
          id, title: title, columns: columns,
          archived: archived, request: request, cancellation: cancellation))
    }
  }
  @discardableResult public func restoreDatasetDefinition(
    _ id: String, definitionID: String, expectedVersion: Int, expectedDefinitionID: String,
    token: String = identifier(), actor: ChangeActor? = nil, cancellation: Cancellation = .init()
  ) throws -> DatasetDefinition {
    let request: Value = .object([
      "datasetID": .string(id), "restoreDefinitionID": .string(definitionID),
      "baseVersion": .number(Double(expectedVersion)),
      "baseDefinitionID": .string(expectedDefinitionID),
    ])
    return try mutation(
      "restore_dataset_definition", token: token, request: request,
      cancellation: cancellation,
      actor: actor ?? ChangeAttribution.actor ?? .programmatic("SevraCore.datasetDefinition"),
      deadlineSeconds: 30,
      reading: { try savedDatasetDefinition(id, definitionID: $0.text) }
    ) {
      try checkDatasetBase(id, version: expectedVersion, definitionID: expectedDefinitionID)
      let saved = try savedDatasetDefinition(id, definitionID: definitionID)
      return .string(
        try applyDatasetDefinition(
          id, title: saved.title, columns: saved.columns,
          archived: saved.archived, request: request, cancellation: cancellation,
          restoring: saved.id))
    }
  }
  func checkDatasetBase(_ id: String, version: Int, definitionID: String) throws {
    let current = try datasetDefinition(id)
    try require(
      current.version == version && current.id == definitionID,
      "stale_schema",
      "This table definition has changed. Your draft is retained; review the current definition before saving."
    )
  }
  func savedDatasetDefinition(_ id: String, definitionID: String) throws -> DatasetDefinition {
    guard
      let row = try db.execute(
        "SELECT * FROM column_versions WHERE dataset_id=? AND id=?",
        [.string(id), .string(definitionID)]
      ).first
    else {
      throw SevraError("history", "The saved table definition was not found.")
    }
    return try DatasetDefinition(row)
  }
  @discardableResult func applyDatasetDefinition(
    _ id: String, title: String?, columns: [Column]?, archived: Bool?, request: Value,
    cancellation: Cancellation = .init(), restoring: String? = nil
  ) throws -> String {
    try validateDecisionActor(db.changes?.actor ?? .programmatic("SevraCore.datasetDefinition"))
    let old = try datasetDefinition(id)
    let title = title ?? old.title
    let columns = columns ?? old.columns
    let archived = archived ?? old.archived
    try require(
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && title.utf8.count <= 4096, "title", "Use a table title of up to 4,096 bytes.")
    try validateColumns(columns)
    // An explicit restoration already identifies the intended historical bindings.
    if restoring == nil { try Self.validateFormulaBindings(before: old.columns, after: columns) }
    var offset = 0
    while true {
      let rows = try db.execute(
        "SELECT i.data FROM dataset_rows r JOIN heads h ON h.logical_id=r.logical_id JOIN items i ON i.id=h.item_id WHERE r.dataset_id=? ORDER BY r.ordinal,r.row_id LIMIT 500 OFFSET ?",
        [.string(id), .number(Double(offset))])
      for row in rows {
        try cancellation.check()
        try validateValues(
          Self.activeValues(try Value.parse(row["data"]!.text).object, columns: columns),
          columns: columns)
      }
      if rows.count < 500 { break }
      offset += rows.count
    }
    let evidence = try insertItem(
      category: "source", kind: "decision",
      title: "Update table definition: " + String(title.prefix(500)),
      text: (db.changes?.actor.label ?? "The calling program")
        + " changed the saved table definition.",
      data: try decisionData(
        nil,
        additional: request.object.merging(["previousDefinitionID": .string(old.id)]) { _, new in
          new
        }),
      meaning: "actual", status: "accepted", scenario: "actual",
      inputs: [old.sourceID] + decisionInputs()
        + (try restoring.map { [try savedDatasetDefinition(id, definitionID: $0).sourceID] } ?? []),
      transformation: "decision-dataset-definition-v1")
    let before = ManagedDatasetSchema(datasetID: id, version: old.version, columns: old.columns)
    let after = ManagedDatasetSchema(datasetID: id, version: old.version + 1, columns: columns)
    try after.validate()
    if before.sql != after.sql { try db.execute("DELETE FROM " + ChangeFormat.quote(before.table)) }
    let next = identifier()
    let raw = try encoded(columns).json()
    try db.execute(
      "INSERT INTO column_versions VALUES(?,?,?,?,?,?,?,?,?)",
      [
        .string(next), .string(id), .number(Double(after.version)), .string(old.id), .string(title),
        .string(raw), .bool(archived), .string(evidence), .string(timestamp()),
      ])
    try db.execute(
      "UPDATE datasets SET title=?,columns=?,storage_version=?,archived=?,definition_id=? WHERE id=?",
      [
        .string(title), .string(raw), .number(Double(after.version)), .bool(archived),
        .string(next), .string(id),
      ])
    try db.materializeManagedSchema(before: before, after: after)
    if old.columns != columns { try populateManagedDataset(id, cancellation: cancellation) }
    return next
  }
  static func activeValues(_ values: [String: Value], columns: [Column]) -> [String: Value] {
    let active = Set(columns.map(\.id))
    return values.filter { active.contains($0.key) }
  }
}

extension Workbook {
  static func validateFormulaBindings(before: [Column], after: [Column]) throws {
    let oldIDs = Set(before.map(\.id))
    let newIDs = Set(after.map(\.id))
    func checkName(_ name: String) throws {
      if oldIDs.contains(name) {
        try require(
          newIDs.contains(name), "formula_dependency",
          "A retained formula references the removed column “\(name)”. Update its formula in the same change."
        )
      } else if let (x, _) = try? CellReference.parse(name), x < before.count {
        try require(
          !newIDs.contains(name) && x < after.count && before[x].id == after[x].id,
          "formula_dependency",
          "A retained cell reference would point to a different column. Update its formula in the same change."
        )
      } else {
        try require(
          !newIDs.contains(name), "formula_dependency",
          "A new column would change a retained formula binding. Update its formula in the same change."
        )
      }
    }
    func inspect(_ node: Expression) throws {
      switch node {
      case .number: break
      case .name(let name): try checkName(name)
      case .range(let first, let last):
        let (x1, y1) = try CellReference.parse(first)
        let (x2, y2) = try CellReference.parse(last)
        try require(
          x2 >= x1 && y2 >= y1 && (x2 - x1 + 1) * (y2 - y1 + 1) <= 10_000,
          "range", "Use a forward range of at most 10,000 cells.")
        for y in y1...y2 {
          for x in x1...x2 {
            try checkName(Workbook.spreadsheetColumn(x) + String(y + 1))
          }
        }
      case .negate(let node): try inspect(node)
      case .binary(_, let a, let b):
        try inspect(a)
        try inspect(b)
      case .call(_, let nodes): for node in nodes { try inspect(node) }
      }
    }
    for column in after where column.formula != nil {
      guard before.first(where: { $0.id == column.id })?.formula == column.formula else { continue }
      // Existing malformed formulas remain visible calculation errors. A schema
      // edit must not erase them or turn their parse failure into a crash.
      guard var parser = try? Formula(column.formula!), let tree = try? parser.parse() else {
        continue
      }
      try inspect(tree)
    }
  }
}
