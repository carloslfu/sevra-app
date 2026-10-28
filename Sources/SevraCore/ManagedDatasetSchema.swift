import CryptoKit
import Foundation

/// Only bounded logical metadata reaches this DDL generator. Saved payloads never
/// supply SQL, table names or executable clauses.
struct ManagedDatasetSchema: Equatable {
  let datasetID: String
  let version: Int
  let columns: [Column]
  var table: String {
    "sevra_data_"
      + SHA256.hash(data: Data(datasetID.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  var stored: [Column] { columns.filter { $0.formula == nil } }
  static let metadata = [
    "_sevra_row", "_sevra_ordinal", "_sevra_logical", "_sevra_item", "_sevra_cells",
  ]
  func field(_ id: String) -> String {
    "c_" + SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  var fields: [String] { Self.metadata + stored.map { field($0.id) } }
  static func validateColumns(_ columns: [Column]) throws {
    try require(
      !columns.isEmpty && columns.count <= 500 && Set(columns.map(\.id)).count == columns.count,
      "columns", "Use between 1 and 500 unique columns.")
    for column in columns {
      try require(
        !column.id.isEmpty && column.id.utf8.count <= 100 && !column.id.contains("\"")
          && !column.id.lowercased().hasPrefix("_sevra_")
          && !column.id.contains("\0")
          && ["text", "decimal", "boolean", "date"].contains(column.type),
        "columns", "Invalid or reserved column identifier or type.")
      try require(
        (column.unit?.utf8.count ?? 0) <= 40, "unit", "Unit labels are limited to 40 bytes.")
      try require(
        (column.formula?.utf8.count ?? 0) <= 4096, "formula_limit", "Formula is too long.")
    }
    try require(
      Set(columns.map { $0.id.lowercased() }).count == columns.count,
      "columns", "SQLite column identifiers must also be unique without case.")
  }
  func validate() throws {
    try require(
      !datasetID.isEmpty && datasetID.utf8.count <= 256 && (1...1_000_000_000).contains(version),
      "managed_schema", "Invalid dataset storage identity or version.")
    try Self.validateColumns(columns)
  }
  var sql: String {
    let quote = ChangeFormat.quote
    let data = stored.map { column in
      let type = column.type == "boolean" ? "INTEGER" : "TEXT"
      let collation = column.type == "decimal" ? " COLLATE SEVRA_DECIMAL" : ""
      let name = field(column.id)
      let check =
        column.type == "boolean"
        ? " CHECK(\(quote(name)) IS NULL OR \(quote(name)) IN (0,1,''))" : ""
      return quote(name) + " " + type + collation + check
    }
    return "CREATE TABLE " + quote(table) + "("
      + ([
        (quote("_sevra_row") + " TEXT PRIMARY KEY"),
        quote("_sevra_ordinal") + " INTEGER NOT NULL CHECK(\(quote("_sevra_ordinal"))>=0)",
        quote("_sevra_logical") + " TEXT NOT NULL UNIQUE REFERENCES heads(logical_id)",
        quote("_sevra_item") + " TEXT NOT NULL REFERENCES items(id)",
        quote("_sevra_cells") + " TEXT NOT NULL",
      ] + data).joined(separator: ",")
      + ");\nCREATE INDEX " + quote(table + "_order") + " ON " + quote(table)
      + "(" + quote("_sevra_ordinal") + "," + quote("_sevra_row") + ");"
  }
  static func decode(_ row: [String: Value]) throws -> Self {
    guard let id = row["id"]?.string, let version = row["storage_version"]?.int,
      let raw = row["columns"]?.string
    else { throw SevraError("managed_schema", "Missing registered dataset schema.") }
    let schema = Self(
      datasetID: id, version: version,
      columns: try JSONDecoder().decode([Column].self, from: Data(raw.utf8)))
    try schema.validate()
    try require(
      row["storage_table"]?.text == schema.table, "managed_schema",
      "The dataset storage name does not match its stable identity.")
    return schema
  }
  static func decode(_ row: ChangeRow?) throws -> Self? {
    guard let row else { return nil }
    try require(row.values.count == 6, "managed_schema", "Invalid saved dataset schema fields.")
    guard let id = row.values[0].string, let columns = row.values[2].string,
      let table = row.values[4].string, case .integer(let version) = row.values[5],
      let number = Int(version)
    else { throw SevraError("managed_schema", "Invalid saved dataset schema values.") }
    return try decode([
      "id": .string(id), "columns": .string(columns), "storage_table": .string(table),
      "storage_version": .number(Double(number)),
    ])
  }
}

extension Database {
  func managedSchemas() throws -> [ManagedDatasetSchema] {
    try execute("SELECT * FROM datasets ORDER BY id").map(ManagedDatasetSchema.decode)
  }
  func durableTables() throws -> Set<String> {
    try ChangeFormat.tables.union(managedSchemas().map(\.table))
  }
  func isDurableTable(_ table: String) throws -> Bool {
    if ChangeFormat.tables.contains(table) { return true }
    return try scalar(
      "SELECT EXISTS(SELECT 1 FROM datasets WHERE storage_table=?)", [.string(table)]
    ).int == 1
  }
  func managedSchema(_ dataset: String) throws -> ManagedDatasetSchema {
    guard let row = try execute("SELECT * FROM datasets WHERE id=?", [.string(dataset)]).first
    else {
      throw SevraError("dataset", "Table not found.")
    }
    return try ManagedDatasetSchema.decode(row)
  }
  func validateCanonicalSchema() throws {
    let reference = try Database(URL(fileURLWithPath: "/:memory:"), create: true)
    try reference.script(Schema.sql)
    let query =
      "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name"
    let core = try reference.execute(query)
    let actual = try execute(query)
    let names = Set(core.compactMap { $0["name"]?.string })
    try require(
      actual.filter { names.contains($0["name"]?.text ?? "") } == core,
      "schema", "Unrecognized core workbook schema.")
    for schema in try managedSchemas() { try reference.script(schema.sql) }
    try require(
      actual == reference.execute(query), "schema",
      "Unregistered or altered workbook objects. Preserve this document for recovery.")
  }
}
