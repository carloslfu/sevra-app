import Foundation

/// Disposable, host-generated access paths. Descriptor identities are hashes of
/// stable logical keys. No saved SQL or independent index ledger is executable.
struct DatasetPerformanceIndex {
  let schema: ManagedDatasetSchema
  let columns: [String]
  let sparse: Bool
  var name: String {
    "sevra_perf_"
      + ChangeFormat.hash(
        schema.datasetID + "\0" + columns.joined(separator: "\0") + "\0" + String(sparse))
  }
  var sql: String {
    let quote = ChangeFormat.quote
    return "CREATE INDEX " + quote(name) + " ON " + quote(schema.table) + "("
      + columns.map { quote(schema.field($0)) }.joined(separator: ",") + ")"
      + (sparse ? " WHERE " + quote(schema.field(columns[0])) + "<>''" : "")
  }
}

extension Database {
  func performanceIndexes(_ schemas: [ManagedDatasetSchema]? = nil) throws
    -> [DatasetPerformanceIndex]
  {
    let objects = try execute(
      "SELECT name,tbl_name,sql FROM sqlite_master WHERE type='index' AND substr(name,1,11)='sevra_perf_' ORDER BY name"
    )
    try require(objects.count <= 64, "schema", "Too many local dataset performance indexes.")
    guard !objects.isEmpty else { return [] }
    let schemas = try schemas ?? managedSchemas()
    var result: [DatasetPerformanceIndex] = []
    for object in objects {
      guard let schema = schemas.first(where: { $0.table == object["tbl_name"]?.text }) else {
        throw SevraError("schema", "A performance index does not belong to a registered dataset.")
      }
      let keys = try execute("PRAGMA index_xinfo(" + ChangeFormat.quote(object["name"]!.text) + ")")
        .filter { $0["key"]?.int == 1 }
      try require((1...3).contains(keys.count), "schema", "Invalid performance index key count.")
      let columns = try keys.map { key -> Column in
        guard let column = schema.stored.first(where: { schema.field($0.id) == key["name"]?.text }),
          key["desc"]?.int == 0,
          key["coll"]?.text == (column.type == "decimal" ? "SEVRA_DECIMAL" : "BINARY")
        else { throw SevraError("schema", "Unrecognized performance index key or collation.") }
        return column
      }
      try require(Set(columns.map(\.id)).count == columns.count, "schema", "Duplicate index keys.")
      let full = DatasetPerformanceIndex(schema: schema, columns: columns.map(\.id), sparse: false)
      let partial = DatasetPerformanceIndex(
        schema: schema, columns: columns.map(\.id), sparse: true)
      let index: DatasetPerformanceIndex
      if object["name"]?.text == full.name && object["sql"]?.text == full.sql {
        index = full
      } else if columns[0].type != "text", object["name"]?.text == partial.name,
        object["sql"]?.text == partial.sql
      {
        index = partial
      } else {
        throw SevraError("schema", "Altered or unrecognized performance index definition.")
      }
      result.append(index)
    }
    for schema in schemas {
      let indexes = result.filter { $0.schema.datasetID == schema.datasetID }
      try require(
        indexes.count <= 4 && indexes.reduce(0, { $0 + $1.columns.count }) <= 12,
        "schema", "Dataset performance indexes exceed the write-cost policy.")
    }
    return result
  }

  func performanceIndexBytes() throws -> [String: Int] {
    do {
      return Dictionary(
        uniqueKeysWithValues: try execute(
          "SELECT name,sum(pgsize) AS bytes FROM dbstat WHERE substr(name,1,11)='sevra_perf_' GROUP BY name"
        ).map { ($0["name"]!.text, $0["bytes"]!.int!) })
    } catch {
      throw SevraError(
        "index_accounting", "This SQLite build cannot account for local index storage.")
    }
  }

  /// Called after canonical row writes, before the same transaction publishes.
  /// Index growth never silently consumes unbounded local storage.
  func trimPerformanceIndexes() throws {
    let indexes = try performanceIndexes()
    guard !indexes.isEmpty else { return }
    let sizes: [String: Int]
    do {
      sizes = try performanceIndexBytes()
    } catch let error as SevraError where error.code == "index_accounting" {
      // A copied workbook may reach a system SQLite without DBSTAT. Optional
      // optimizer choices must not prevent canonical user edits on that device.
      for index in indexes { try script("DROP INDEX " + ChangeFormat.quote(index.name)) }
      changes?.schemaCookie = try scalar("PRAGMA main.schema_version").int
      return
    }
    var kept = 0
    for index in indexes {
      let size = sizes[index.name] ?? 0
      if size > 8_388_608 || kept + size > 33_554_432 {
        try script("DROP INDEX " + ChangeFormat.quote(index.name))
      } else {
        kept += size
      }
    }
    changes?.schemaCookie = try scalar("PRAGMA main.schema_version").int
  }
}

extension Workbook {
  /// The query, not a model's DDL, determines eligible access paths. Each retained
  /// candidate must fit actual byte/key budgets and appear in its query plan.
  public func optimizeDatasetQuery(_ value: Value, cancellation: Cancellation = .init()) throws
    -> Value
  {
    try localProjectionMutation(cancellation: cancellation) {
      let query = try DatasetQuery(value)
      let compiled = try compileDatasetQuery(query)
      var existing = try db.performanceIndexes()
      let before = try compiled.plan(db)
      var decisions: [Value] = []
      for (source, schema) in compiled.schemas.enumerated() {
        var keys: [String] = []
        func append(_ id: String) {
          if keys.count < 3 && !keys.contains(id) && schema.stored.contains(where: { $0.id == id })
          {
            keys.append(id)
          }
        }
        for filter in query.filters where filter.column.source == source && filter.op == "eq" {
          append(filter.column.column)
        }
        if source > 0 { append(query.joins[source - 1].right) }
        for filter in query.filters
        where filter.column.source == source && ["gt", "gte", "lt", "lte"].contains(filter.op) {
          append(filter.column.column)
        }
        for group in query.groups where group.source == source { append(group.column) }
        for sort in query.sorts {
          if let selection = query.selections.first(where: {
            $0.id == sort.field && $0.aggregate == nil
          }),
            let column = selection.column, column.source == source
          {
            append(column.column)
          }
        }
        guard let first = keys.first else { continue }
        let sparse =
          schema.stored.first { $0.id == first }?.type != "text"
          && query.filters.contains {
            $0.column.source == source && $0.column.column == first
              && ["eq", "ne", "lt", "lte", "gt", "gte"].contains($0.op)
          }
        let candidate = DatasetPerformanceIndex(schema: schema, columns: keys, sparse: sparse)
        let owned = existing.filter { $0.schema.datasetID == schema.datasetID }
        if owned.contains(where: { $0.name == candidate.name }) {
          decisions.append(
            .object([
              "datasetID": .string(schema.datasetID), "state": .string("existing"),
              "index": .string(candidate.name),
            ]))
          continue
        }
        try require(
          owned.count < 4 && existing.count < 64, "index_limit", "Local index-count budget is full."
        )
        // An upper-bound entry estimate avoids building obviously oversized keys.
        let lengths = keys.map {
          "coalesce(length(CAST(" + ChangeFormat.quote(schema.field($0)) + " AS BLOB)),0)"
        }
        let estimate =
          try db.scalar(
            "SELECT coalesce(sum(64+" + lengths.joined(separator: "+") + "),0) FROM "
              + ChangeFormat.quote(schema.table)
          ).int ?? Int.max
        try require(
          estimate <= 8_388_608, "index_limit", "Candidate index exceeds its key-byte budget.")
        _ = try db.performanceIndexBytes()  // Size accounting must work before DDL.
        try db.script(candidate.sql)
        let after = try compiled.plan(db)
        let sizes = try db.performanceIndexBytes()
        let size = sizes[candidate.name] ?? Int.max
        let used = after.contains { $0.contains(candidate.name) }
        if !used || size > 8_388_608 || sizes.values.reduce(0, +) > 33_554_432 {
          try db.script("DROP INDEX " + ChangeFormat.quote(candidate.name))
          decisions.append(
            .object([
              "datasetID": .string(schema.datasetID), "state": .string("declined"),
              "reason": .string(used ? "storage budget" : "query planner did not use candidate"),
            ]))
        } else {
          existing.append(candidate)
          decisions.append(
            .object([
              "datasetID": .string(schema.datasetID), "state": .string("created"),
              "index": .string(candidate.name), "columns": .array(keys.map(Value.string)),
              "sparse": .bool(sparse), "bytes": .number(Double(size)),
            ]))
        }
      }
      try db.validateCanonicalSchema()
      db.changes?.schemaCookie = try db.scalar("PRAGMA main.schema_version").int
      return .object([
        "queryHash": .string(query.hash), "beforePlan": .array(before.map(Value.string)),
        "afterPlan": .array(try compiled.plan(db).map(Value.string)),
        "decisions": .array(decisions),
      ])
    }
  }

  public func removeDatasetQueryIndexes(_ datasetID: String, cancellation: Cancellation = .init())
    throws -> Value
  {
    try localProjectionMutation(cancellation: cancellation) {
      _ = try db.managedSchema(datasetID)
      let indexes = try db.performanceIndexes().filter { $0.schema.datasetID == datasetID }
      for index in indexes { try db.script("DROP INDEX " + ChangeFormat.quote(index.name)) }
      db.changes?.schemaCookie = try db.scalar("PRAGMA main.schema_version").int
      return .object(["removed": .number(Double(indexes.count))])
    }
  }
}
