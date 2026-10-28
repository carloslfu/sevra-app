import Foundation

struct QueryColumn: Hashable {
  let source: Int
  let column: String
  init(_ value: Value) throws {
    let object = try queryObject(value, keys: ["source", "column"])
    guard let source = object["source"]?.int, object["source"] == .number(Double(source)),
      (0...2).contains(source), let column = object["column"]?.string
    else { throw SevraError("query", "A column needs a source number and stable column ID.") }
    self.source = source
    self.column = column
  }
}
struct QuerySelection {
  let id: String
  let column: QueryColumn?
  let aggregate: String?
}
struct QueryFilter {
  let column: QueryColumn
  let op: String
  let value: Value?
}
struct QueryJoin {
  let kind: String
  let left: QueryColumn
  let right: String
}
struct QuerySort {
  let field: String
  let descending: Bool
}
struct DatasetQuery {
  let value: Value
  let sources: [(dataset: String, definition: String, scope: [String: String])]
  let joins: [QueryJoin]
  let selections: [QuerySelection]
  let filters: [QueryFilter]
  let groups: [QueryColumn]
  let sorts: [QuerySort]
  let limit: Int
  var grouped: Bool { !groups.isEmpty || selections.contains { $0.aggregate != nil } }
  var hash: String { ChangeFormat.hash((try? value.json()) ?? "") }

  init(_ value: Value) throws {
    try require(try value.json().utf8.count <= 64_000, "query", "Query exceeds 64,000 bytes.")
    let object = try queryObject(
      value, keys: ["sources", "joins", "select", "filters", "groupBy", "sort", "limit"])
    func array(_ key: String, maximum: Int, required: Bool = false) throws -> [Value] {
      guard let raw = object[key] else {
        try require(!required, "query", "Missing query field: " + key)
        return []
      }
      guard case .array(let values) = raw else {
        throw SevraError("query", key + " must be an array.")
      }
      try require(values.count <= maximum, "query", "Too many entries in " + key + ".")
      return values
    }
    self.value = value
    sources = try array("sources", maximum: 3, required: true).map {
      let object = try queryObject($0, keys: ["datasetID", "definitionID", "scope"])
      guard let dataset = object["datasetID"]?.string,
        let definition = object["definitionID"]?.string,
        dataset.utf8.count <= 256, definition.utf8.count <= 256
      else { throw SevraError("query", "Sources need exact dataset and definition IDs.") }
      let scope = try queryObject(
        object["scope"] ?? .object([:]), keys: ["meaning", "status", "scenario"])
      var fields: [String: String] = [:]
      for (key, value) in scope {
        guard let text = value.string, !text.isEmpty, text.utf8.count <= 100 else {
          throw SevraError(
            "query_scope", "Use nonempty text for meaning, status and scenario scope.")
        }
        fields[key] = text
      }
      return (dataset, definition, fields)
    }
    joins = try array("joins", maximum: 2).map {
      let object = try queryObject($0, keys: ["kind", "left", "right"])
      guard let kind = object["kind"]?.string, ["inner", "left"].contains(kind),
        let left = object["left"], let right = object["right"]?.string
      else { throw SevraError("query", "Use an inner or left equality join with stable keys.") }
      return try QueryJoin(kind: kind, left: QueryColumn(left), right: right)
    }
    selections = try array("select", maximum: 50, required: true).map {
      let object = try queryObject($0, keys: ["id", "column", "aggregate"])
      guard let id = object["id"]?.string, !id.isEmpty, id.utf8.count <= 100,
        !id.hasPrefix("_sevra_")
      else { throw SevraError("query", "Each output needs a distinct nonreserved ID.") }
      let aggregate = object["aggregate"]?.string
      if object["aggregate"] != nil {
        try require(
          aggregate.map { ["countRows", "count", "sum", "average", "min", "max"].contains($0) }
            == true, "query", "Unknown aggregate.")
      }
      let column = try object["column"].map(QueryColumn.init)
      try require(
        (aggregate == "countRows" && column == nil) || (aggregate != "countRows" && column != nil),
        "query", "Select a column, or use countRows without a column.")
      return QuerySelection(id: id, column: column, aggregate: aggregate)
    }
    filters = try array("filters", maximum: 24).map {
      let object = try queryObject($0, keys: ["column", "op", "value"])
      guard let op = object["op"]?.string, let column = object["column"],
        ["eq", "ne", "lt", "lte", "gt", "gte", "contains", "isNull", "isEmpty"].contains(op)
      else { throw SevraError("query", "Unknown typed filter.") }
      try require(
        ["isNull", "isEmpty"].contains(op) ? object["value"] == nil : object["value"] != nil,
        "query", "Only comparisons take a value. Use isNull for unknown values.")
      return try QueryFilter(column: QueryColumn(column), op: op, value: object["value"])
    }
    groups = try array("groupBy", maximum: 8).map(QueryColumn.init)
    sorts = try array("sort", maximum: 8).map {
      let object = try queryObject($0, keys: ["field", "descending"])
      guard let field = object["field"]?.string else {
        throw SevraError("query", "Sort by an output field ID.")
      }
      if let descending = object["descending"] {
        guard case .bool = descending else { throw SevraError("query", "Descending is a boolean.") }
      }
      return QuerySort(field: field, descending: object["descending"] == .bool(true))
    }
    if let raw = object["limit"] {
      guard let count = raw.int, raw == .number(Double(count)), (1...1000).contains(count) else {
        throw SevraError("query", "Use a page limit of 1 to 1,000 rows.")
      }
      limit = count
    } else {
      limit = 200
    }
    try require(
      !sources.isEmpty && joins.count == sources.count - 1 && !selections.isEmpty
        && Set(selections.map(\.id)).count == selections.count
        && Set(groups).count == groups.count && Set(sorts.map(\.field)).count == sorts.count,
      "query", "Use one join per additional source, distinct fields and nonempty selections.")
    if grouped {
      try require(
        Set(selections.filter { $0.aggregate == nil }.compactMap(\.column)) == Set(groups),
        "query", "Select each grouping column and aggregate every other field.")
    }
    try require(
      sorts.allSatisfy { sort in selections.contains { $0.id == sort.field } }, "query",
      "Sort fields must be selected outputs.")
  }
}

func queryObject(_ value: Value, keys: Set<String>) throws -> [String: Value] {
  guard case .object(let object) = value, Set(object.keys).isSubset(of: keys) else {
    throw SevraError("query", "Use a typed query object with known fields. SQL is not accepted.")
  }
  return object
}

struct CompiledDatasetQuery {
  let request: DatasetQuery
  let schemas: [ManagedDatasetSchema]
  let columns: [Column]
  let sql: String
  let arguments: [Value]
  func plan(_ db: Database) throws -> [String] {
    let automatic = try db.scalar("PRAGMA automatic_index").int == 1
    try db.execute("PRAGMA automatic_index=OFF")
    defer { _ = try? db.execute("PRAGMA automatic_index=" + (automatic ? "ON" : "OFF")) }
    return try db.execute("EXPLAIN QUERY PLAN " + sql, arguments).compactMap {
      $0["detail"]?.string
    }
  }
}
