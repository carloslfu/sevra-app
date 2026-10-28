import Foundation

extension Workbook {
  /// Read-only typed execution. No SQL, physical identifiers or model-provided
  /// expressions reach the database. Returned values are normalized scalars;
  /// exact original cell payloads remain available through contributing versions.
  public func queryDataset(
    _ request: Value, cursor: String? = nil, cancellation: Cancellation = .init(),
    deadlineSeconds: TimeInterval = 3
  ) throws -> Value {
    try require(
      deadlineSeconds.isFinite && deadlineSeconds >= 0, "query_budget",
      "Use a finite query deadline.")
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: min(3, deadlineSeconds))
    return try synchronized(cancellation: control) {
      try db.datasetQueryBudget(cancellation: control) { budget in
        try db.readTransaction {
          if db.changes?.schemaCookie != (try db.scalar("PRAGMA main.schema_version").int) {
            try db.validateCanonicalSchema()
          }
          let query = try DatasetQuery(request)
          let snapshot = try db.scalar(
            "SELECT id FROM committed_changes ORDER BY rowid DESC LIMIT 1"
          ).text
          var offset = 0
          if let cursor {
            guard cursor.utf8.count <= 8192, let data = Data(base64Encoded: cursor),
              let token = try? Value.parse(String(decoding: data, as: UTF8.self)),
              let skip = token["offset"].int, token["offset"] == .number(Double(skip)),
              (0...100_000).contains(skip)
            else { throw SevraError("query_cursor", "Invalid query continuation.") }
            try require(
              token["workbookID"] == .string(id) && token["queryHash"] == .string(query.hash),
              "query_cursor", "This continuation belongs to another workbook or query.")
            try require(
              token["snapshot"] == .string(snapshot), "stale_query",
              "The workbook changed. Run the query again.")
            offset = skip
          }
          let compiled = try compileDatasetQuery(query, offset: offset)
          let raw = try db.execute(
            compiled.sql, compiled.arguments, maxRows: query.limit + 1, maxBytes: 8_388_608)
          let more = raw.count > query.limit
          let rows = try raw.prefix(query.limit).map { row -> Value in
            var values: [String: Value] = [:]
            for (index, column) in compiled.columns.enumerated() {
              let scalar = row["v\(index)"] ?? .null
              if column.type == "decimal", scalar != .null, scalar.text != "" {
                values[column.id] = .string(Numbers.string(try Numbers.decimal(scalar.text)))
              } else if column.type == "boolean", scalar != .null, scalar != .string("") {
                values[column.id] = .bool(scalar.int == 1)
              } else {
                values[column.id] = scalar
              }
            }
            var result: [String: Value] = ["values": .object(values)]
            if !query.grouped {
              result["inputs"] = .array(
                query.sources.indices.map { index in
                  guard row["r\(index)"] != .null else { return .null }
                  return .object([
                    "datasetID": .string(query.sources[index].dataset),
                    "definitionID": .string(query.sources[index].definition),
                    "rowID": row["r\(index)"] ?? .null,
                    "logicalID": row["l\(index)"] ?? .null,
                    "versionID": row["i\(index)"] ?? .null,
                    "meaning": row["m\(index)_meaning"] ?? .null,
                    "status": row["m\(index)_status"] ?? .null,
                    "scenario": row["m\(index)_scenario"] ?? .null,
                  ])
                })
            }
            return .object(result)
          }
          var next: Value = .null
          if more {
            let skip = offset + query.limit
            try require(
              skip <= 100_000, "query_page_limit",
              "Narrow the query before paging beyond 100,000 rows.")
            let token: Value = .object([
              "workbookID": .string(id), "queryHash": .string(query.hash),
              "snapshot": .string(snapshot), "offset": .number(Double(skip)),
            ])
            next = .string(Data(try token.json().utf8).base64EncodedString())
          }
          try require(
            try Value.array(rows).json().utf8.count <= 8_388_608,
            "query_result_limit", "Encoded query output exceeds 8 MiB. Select fewer fields or rows."
          )
          return .object([
            "workbookID": .string(id), "snapshot": .string(snapshot),
            "revision": .number(Double(try revision())), "queryHash": .string(query.hash),
            "sources": request["sources"], "columns": try encoded(compiled.columns),
            "sourceScopes": .array(
              query.sources.map { source in
                .object([
                  "datasetID": .string(source.dataset),
                  "scope": .object(source.scope.mapValues(Value.string)),
                  "allCurrentMembers": .bool(source.scope.isEmpty),
                ])
              }),
            "rows": .array(rows), "hasMore": .bool(more), "nextCursor": next,
            "inputRows": .number(Double(budget.rows)), "inputBytes": .number(Double(budget.bytes)),
            "decimalArithmetic": .string(
              "exact Decimal sum; average uses Decimal plain rounding, up to 38 significant digits"),
          ])
        }
      }
    }
  }

  public func datasetQueryPlan(
    _ request: Value, cancellation: Cancellation = .init()
  ) throws -> Value {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction {
          if db.changes?.schemaCookie != (try db.scalar("PRAGMA main.schema_version").int) {
            try db.validateCanonicalSchema()
          }
          let query = try DatasetQuery(request)
          return .object([
            "queryHash": .string(query.hash),
            "plan": .array(try compileDatasetQuery(query).plan(db).map(Value.string)),
          ])
        }
      }
    }
  }
}
