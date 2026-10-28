import Foundation

/// Physical values are typed columns. This small sidecar preserves only omitted
/// cells, original lexical forms and formula seeds that have no stored column.
struct ManagedCells: Codable, Equatable {
  var omitted: [String] = []
  var originals: [String: Value] = [:]
}

extension ManagedDatasetSchema {
  func scalar(_ value: Value, column: Column) throws -> Value {
    if value == .null { return .null }
    if value.text.isEmpty { return .string("") }
    switch column.type {
    case "boolean": return .number(value.text.lowercased() == "true" ? 1 : 0)
    case "date": return .string(try BusinessTime.normalized(value.text))
    default: return .string(value.text)
    }
  }
  func value(_ scalar: Value, column: Column) -> Value {
    if column.type == "boolean", scalar != .null, scalar != .string("") {
      return .bool(scalar.int == 1)
    }
    return scalar
  }
  func projected(_ values: [String: Value]) throws -> [Value] {
    var metadata = ManagedCells()
    var scalars: [Value] = []
    for column in columns {
      guard column.formula == nil else {
        if let original = values[column.id] { metadata.originals[column.id] = original }
        continue
      }
      guard let original = values[column.id] else {
        metadata.omitted.append(column.id)
        scalars.append(.null)
        continue
      }
      let cell = try scalar(original, column: column)
      scalars.append(cell)
      if value(cell, column: column) != original { metadata.originals[column.id] = original }
    }
    return [.string(try ChangeFormat.encode(metadata))] + scalars
  }
  func values(_ row: [String: Value]) throws -> [String: Value] {
    guard let raw = row["_sevra_cells"]?.string else {
      throw SevraError("managed_projection", "Missing native row metadata.")
    }
    let metadata = try JSONDecoder().decode(ManagedCells.self, from: Data(raw.utf8))
    try require(
      Set(metadata.omitted).isSubset(of: Set(stored.map(\.id)))
        && Set(metadata.originals.keys).isSubset(of: Set(columns.map(\.id))),
      "managed_projection", "Invalid native cell metadata.")
    var result: [String: Value] = [:]
    for column in stored where !metadata.omitted.contains(column.id) {
      guard let scalar = row[field(column.id)] else {
        throw SevraError("managed_projection", "Missing native column.")
      }
      result[column.id] = value(scalar, column: column)
    }
    result.merge(metadata.originals) { _, original in original }
    return result
  }
}

extension Database {
  func validateManagedHistory(_ schema: ManagedDatasetSchema) throws {
    let history = try execute(
      "SELECT max(version) AS latest,min(version) AS first,count(*) AS count FROM column_versions WHERE dataset_id=?",
      [.string(schema.datasetID)]
    ).first!
    let registry = try execute("SELECT * FROM datasets WHERE id=?", [.string(schema.datasetID)])
      .first!
    let definition = try execute(
      "SELECT * FROM column_versions WHERE dataset_id=? AND id=?",
      [.string(schema.datasetID), registry["definition_id"]!]
    ).first
    let broken = try scalar(
      "SELECT count(*) FROM column_versions v LEFT JOIN column_versions p ON p.id=v.previous_id JOIN items s ON s.id=v.source_id WHERE v.dataset_id=? AND (typeof(v.version)!='integer' OR s.category!='source' OR (v.version=1 AND v.previous_id IS NOT NULL) OR (v.version>1 AND (p.id IS NULL OR p.dataset_id!=v.dataset_id OR p.version!=v.version-1)))",
      [.string(schema.datasetID)]
    ).int
    try require(
      history["first"]?.int == 1 && history["latest"]?.int == schema.version
        && history["count"]?.int == schema.version
        && definition?["version"]?.int == schema.version
        && definition?["columns"] == registry["columns"]
        && definition?["title"] == registry["title"]
        && definition?["archived"] == registry["archived"] && broken == 0,
      "managed_schema",
      "The saved definition history for table \(schema.datasetID) is incomplete or inconsistent."
    )
  }
  /// Only this host-generated schema is executable. A journal contains logical
  /// descriptors, never executable DDL. Old rows must precede a shape change.
  func materializeManagedSchema(before: ManagedDatasetSchema?, after: ManagedDatasetSchema?) throws
  {
    guard before?.sql != after?.sql else { return }
    if let before {
      try require(
        try scalar("SELECT count(*) FROM " + ChangeFormat.quote(before.table)).int == 0,
        "managed_schema", "A native shape change must first preserve and remove its old projection."
      )
      try script("DROP TABLE " + ChangeFormat.quote(before.table))
      changeColumns[before.table] = nil
      changes?.tables.remove(before.table)
    }
    if let after {
      try after.validate()
      try script(after.sql)
      try installCaptureTable(after.table)
    }
    changes?.schemaCookie = try scalar("PRAGMA main.schema_version").int
  }
}

extension Workbook {
  public func datasetSchema(_ datasetID: String) throws -> Value {
    try synchronized {
      try db.readTransaction {
        let schema = try db.managedSchema(datasetID)
        return .object([
          "datasetID": .string(datasetID), "version": .number(Double(schema.version)),
          "columns": try encoded(schema.columns), "representation": .string("managed-native"),
          "definitionID": .string(try datasetDefinition(datasetID).id),
          "title": .string(try dataset(datasetID).title),
          "archived": .bool(try dataset(datasetID).archived),
        ])
      }
    }
  }
  func insertDatasetMember(
    _ datasetID: String, rowID: String = identifier(), ordinal: Int,
    logicalID: String
  ) throws {
    try db.execute(
      "INSERT INTO dataset_rows VALUES(?,?,?,?)",
      [
        .string(datasetID), .string(rowID), .number(Double(ordinal)), .string(logicalID),
      ])
    try refreshManagedRow(logicalID)
  }
  func clearDatasetMembers(_ datasetID: String) throws {
    let schema = try db.managedSchema(datasetID)
    try db.execute("DELETE FROM " + ChangeFormat.quote(schema.table))
    try db.execute("DELETE FROM dataset_rows WHERE dataset_id=?", [.string(datasetID)])
  }
  /// SQLite uniqueness is immediate. Release only the affected projections so a
  /// valid multi-row swap is checked against the final set, within one transaction.
  func prepareManagedRowEdits(_ datasetID: String, exactIDs: [String]) throws {
    let schema = try db.managedSchema(datasetID)
    guard schema.stored.contains(where: { $0.unique == true }) else { return }
    for id in exactIDs {
      try db.execute(
        "DELETE FROM " + ChangeFormat.quote(schema.table)
          + " WHERE _sevra_logical=(SELECT logical_id FROM items WHERE id=?)", [.string(id)])
    }
  }
  func refreshManagedRow(_ logicalID: String) throws {
    for member in try db.execute(
      "SELECT * FROM dataset_rows WHERE logical_id=?", [.string(logicalID)])
    {
      let schema = try db.managedSchema(member["dataset_id"]!.text)
      let current = try item(logicalID)
      try require(
        current.category == "record" && current.kind == "row",
        "managed_projection", "A dataset member must resolve an exact structured row version.")
      try validateValues(
        Self.activeValues(current.data.object, columns: schema.columns), columns: schema.columns)
      let args: [Value] =
        [member["row_id"]!, member["ordinal"]!, .string(logicalID), .string(current.id)]
        + (try schema.projected(current.data.object))
      let fields = schema.fields.map(ChangeFormat.quote)
      do {
        try db.execute(
          "INSERT INTO " + ChangeFormat.quote(schema.table) + "("
            + fields.joined(separator: ",") + ") VALUES("
            + Array(repeating: "?", count: fields.count).joined(separator: ",")
            + ") ON CONFLICT(\"_sevra_row\") DO UPDATE SET "
            + fields.dropFirst().map { $0 + "=excluded." + $0 }.joined(separator: ","), args)
      } catch let error as SevraError {
        if error.code == "database",
          let column = schema.stored.first(where: {
            $0.unique == true
              && error.message.contains(
                "UNIQUE constraint failed: " + schema.table + "." + schema.field($0.id))
          })
        {
          throw SevraError(
            "unique", column.title + " must contain distinct values. No changes were saved.")
        }
        throw error
      }
    }
  }
  func populateManagedDataset(_ datasetID: String, cancellation: Cancellation = .init()) throws {
    var offset = 0
    while true {
      let members = try db.execute(
        "SELECT logical_id FROM dataset_rows WHERE dataset_id=? ORDER BY ordinal,row_id LIMIT 500 OFFSET ?",
        [.string(datasetID), .number(Double(offset))])
      for row in members {
        try cancellation.check()
        try refreshManagedRow(row["logical_id"]!.text)
      }
      if members.count < 500 { break }
      offset += members.count
    }
  }
  /// Rebuilds from immutable versions, current heads and registered definitions.
  /// This never consults the existing native values or any model/extractor.
  public func rebuildDataset(
    _ datasetID: String, expectedRevision: Int,
    token: String = identifier(), cancellation: Cancellation = .init()
  ) throws {
    _ = try mutation(
      "rebuild_dataset", token: token,
      request: .object([
        "datasetID": .string(datasetID), "expectedRevision": .number(Double(expectedRevision)),
      ]),
      expected: expectedRevision, cancellation: cancellation
    ) {
      let schema = try db.managedSchema(datasetID)
      try db.validateManagedHistory(schema)
      try require(
        try db.execute("PRAGMA foreign_key_check").isEmpty,
        "integrity", "Missing canonical dependencies prevent rebuilding this dataset.")
      guard let capture = db.changes, capture.pending != nil else {
        throw SevraError(
          "change_transaction", "A projection rebuild requires complete change capture.")
      }
      capture.pending?.append(
        .init(table: schema.table, before: nil, after: nil, resetProjection: true))
      capture.resettingProjection = schema.table
      defer { capture.resettingProjection = nil }
      try db.execute("DELETE FROM " + ChangeFormat.quote(schema.table))
      try populateManagedDataset(datasetID, cancellation: cancellation)
      return .string(datasetID)
    }
  }
  func verifyManagedDatasets() throws {
    try db.validateCanonicalSchema()
    for schema in try db.managedSchemas() {
      try db.validateManagedHistory(schema)
      try require(
        try db.scalar("SELECT count(*) FROM " + ChangeFormat.quote(schema.table)).int
          == db.scalar(
            "SELECT count(*) FROM dataset_rows WHERE dataset_id=?", [.string(schema.datasetID)]
          ).int,
        "managed_projection", "Native dataset membership differs from its canonical membership.")
      var offset = 0
      while true {
        let batch = try db.execute(
          "SELECT n.*,r.row_id,r.ordinal,r.logical_id,h.item_id,i.data FROM "
            + ChangeFormat.quote(schema.table)
            + " n LEFT JOIN dataset_rows r ON r.dataset_id=? AND r.row_id=n.\"_sevra_row\""
            + " LEFT JOIN heads h ON h.logical_id=r.logical_id LEFT JOIN items i ON i.id=h.item_id"
            + " ORDER BY n.\"_sevra_ordinal\",n.\"_sevra_row\" LIMIT 500 OFFSET ?",
          [.string(schema.datasetID), .number(Double(offset))])
        for row in batch {
          let data = try Value.parse(row["data"]?.text ?? "null").object
          let actual = schema.fields.dropFirst(4).map { row[$0] ?? .null }
          try require(
            row["row_id"] == row["_sevra_row"] && row["ordinal"] == row["_sevra_ordinal"]
              && row["logical_id"] == row["_sevra_logical"] && row["item_id"] == row["_sevra_item"]
              && actual == schema.projected(data),
            "managed_projection", "Native values differ from their exact canonical row version.")
        }
        if batch.count < 500 { break }
        offset += batch.count
      }
    }
  }
}
