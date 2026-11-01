import Foundation

@testable import SevraCore

func checkDatasetQueries(at root: URL) {
  func fixture(_ name: String, rows: [[String: Value]]? = nil) throws -> (Workbook, Dataset) {
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    let source = try book.addItem(category: "source", kind: "note", title: "Original values")
    let table = try book.createDataset(
      title: "Orders",
      columns: [
        .init(id: "sku", title: "SKU"), .init(id: "group", title: "Group"),
        .init(id: "cost", title: "Cost", type: "decimal", unit: "USD"),
        .init(id: "flag", title: "Flag", type: "boolean"),
        .init(id: "date", title: "Date", type: "date"),
        .init(id: "calculated", title: "Calculated", type: "decimal", formula: "cost*2"),
      ],
      rows: rows ?? [
        [
          "sku": .string("0012"), "group": .string("A"), "cost": .string("9007199254740993.01"),
          "flag": .bool(true), "date": .string("2026-01-02"),
        ],
        [
          "sku": .string("0013"), "group": .string("A"), "cost": .string("0.09"),
          "flag": .bool(false),
        ],
        ["sku": .string("0014"), "group": .string("B"), "cost": .null],
        ["sku": .string("0015"), "group": .string("B"), "cost": .string("")],
      ], sourceID: source.id)
    return (book, table)
  }
  func ref(_ name: String, _ source: Int = 0) -> Value {
    .object(["source": .number(Double(source)), "column": .string(name)])
  }
  func request(
    _ table: Dataset, select: [Value], filters: [Value] = [], groups: [Value] = [],
    sort: [Value] = [], limit: Int = 200
  ) -> Value {
    .object([
      "sources": .array([
        .object(["datasetID": .string(table.id), "definitionID": .string(table.definitionID)])
      ]),
      "select": .array(select), "filters": .array(filters), "groupBy": .array(groups),
      "sort": .array(sort), "limit": .number(Double(limit)),
    ])
  }
  func field(_ name: String, aggregate: String? = nil, source: Int = 0, id: String? = nil) -> Value
  {
    var object: [String: Value] = ["id": .string(id ?? name), "column": ref(name, source)]
    if let aggregate { object["aggregate"] = .string(aggregate) }
    return .object(object)
  }
  check("managed typed queries preserve exact decimals, unknowns, dates and row provenance") {
    let (book, table) = try fixture("QueryValues")
    let query = request(
      table, select: [field("sku"), field("cost"), field("flag"), field("date")],
      filters: [
        .object([
          "column": ref("cost"), "op": .string("gt"), "value": .string("9007199254740993.00"),
        ])
      ])
    let revision = try book.revision()
    let commits = try book.committedHistory(limit: 1000)
    let result = try book.queryDataset(query)
    try expect(result["rows"].array.count == 1)
    try expect(
      result["rows"].array[0]["values"]
        == .object([
          "sku": .string("0012"), "cost": .string("9007199254740993.01"), "flag": .bool(true),
          "date": .string("2026-01-02T00:00:00.000Z"),
        ]))
    let input = result["rows"].array[0]["inputs"].array[0]
    try expect(try book.item(input["versionID"].text).data["sku"] == .string("0012"))
    let all = try book.queryDataset(request(table, select: [field("cost")]))["rows"].array
    try expect(all[2]["values"]["cost"] == .null && all[3]["values"]["cost"] == .string(""))
    try expect(try book.revision() == revision && book.committedHistory(limit: 1000) == commits)
  }
  check("managed grouped aggregates avoid binary floats and count known versus joined values") {
    let (book, table) = try fixture("QueryGroups")
    let query = request(
      table,
      select: [
        field("group"), field("cost", aggregate: "sum", id: "sum"),
        field("cost", aggregate: "average", id: "average"),
        field("cost", aggregate: "min", id: "min"), field("cost", aggregate: "max", id: "max"),
        field("cost", aggregate: "count", id: "known"),
        .object(["id": .string("rows"), "aggregate": .string("countRows")]),
      ], groups: [ref("group")])
    let results = try book.queryDataset(query)["rows"].array
    try expect(results[0]["values"]["sum"] == .string("9007199254740993.1"))
    try expect(results[0]["values"]["average"] == .string("4503599627370496.55"))
    try expect(results[0]["values"]["min"] == .string("0.09"))
    try expect(results[0]["values"]["max"] == .string("9007199254740993.01"))
    try expect(
      results[1]["values"]["sum"] == .null && results[1]["values"]["known"] == .string("0"))
    try expect(results[1]["values"]["rows"] == .string("2") && results[0].object["inputs"] == nil)
    try expect(
      try book.queryDataset(
        request(
          table, select: [field("cost", aggregate: "sum")],
          filters: [
            .object(["column": ref("sku"), "op": .string("eq"), "value": .string("absent")])
          ]))["rows"].array[0]["values"]["cost"] == .null)
  }
  check("managed text queries preserve Unicode, NUL and case-sensitive identity") {
    let value = "Cafe\u{301} 👩🏽‍💻\0tail"
    let (book, table) = try fixture(
      "QueryUnicode",
      rows: [
        ["sku": .string(value), "cost": .string("1.00")],
        ["sku": .string("SKU"), "cost": .string("2")],
      ])
    let query = request(
      table, select: [field("sku")],
      filters: [
        .object(["column": ref("sku"), "op": .string("contains"), "value": .string("👩🏽‍💻\0tail")])
      ])
    try expect(try book.queryDataset(query)["rows"].array[0]["values"]["sku"] == .string(value))
    try expect(
      try book.queryDataset(
        request(
          table, select: [field("sku")],
          filters: [.object(["column": ref("sku"), "op": .string("eq"), "value": .string("sku")])]))[
          "rows"
        ].array.isEmpty)
  }
  check("managed query continuations bind exact commit, request and schema") {
    let (book, table) = try fixture("QueryCursor")
    let query = request(table, select: [field("sku")], limit: 1)
    let first = try book.queryDataset(query)
    let cursor = first["nextCursor"].text
    try expect(first["hasMore"] == .bool(true))
    try expect(
      try book.queryDataset(query, cursor: cursor)["rows"].array[0]["values"]["sku"]
        == .string("0013"))
    try refuses("query_cursor") {
      _ = try book.queryDataset(request(table, select: [field("cost")], limit: 1), cursor: cursor)
    }
    _ = try book.addItem(category: "source", kind: "note", title: "Concurrent input")
    try refuses("stale_query") { _ = try book.queryDataset(query, cursor: cursor) }
    _ = try book.updateDatasetDefinition(
      table.id, expectedVersion: 1, expectedDefinitionID: table.definitionID, title: "Renamed",
      token: "schema")
    try refuses("stale_schema") { _ = try book.queryDataset(query) }
  }
  check("managed query source scopes keep accepted estimates separate from actuals") {
    let (book, table) = try fixture("QueryMeaning")
    let first = try book.rows(table.id)[0]
    _ = try book.addHostOwnedItem(
      category: "record", kind: "row", title: "Accepted estimate", data: first.data,
      meaning: "estimate", status: "accepted", scenario: "forecast", inputs: [first.id],
      supersedes: first.id)
    var query = request(table, select: [field("sku")]).object
    var source = query["sources"]!.array[0].object
    source["scope"] = .object([
      "meaning": .string("estimate"), "status": .string("accepted"),
      "scenario": .string("forecast"),
    ])
    query["sources"] = .array([.object(source)])
    let result = try book.queryDataset(.object(query))
    try expect(
      result["rows"].array.count == 1
        && result["rows"].array[0]["inputs"].array[0]["meaning"] == .string("estimate"))
    try expect(result["rows"].array[0]["inputs"].array[0]["status"] == .string("accepted"))
    source["scope"] = .object([
      "meaning": .string("actual"), "status": .string("accepted"), "scenario": .string("actual"),
    ])
    query["sources"] = .array([.object(source)])
    query["select"] = .array([.object(["id": .string("count"), "aggregate": .string("countRows")])])
    try expect(
      try book.queryDataset(.object(query))["rows"].array[0]["values"]["count"] == .string("3"))
  }
  check("typed query syntax, calculated columns and malicious fields refuse") {
    let (book, table) = try fixture("QueryRefusals")
    var query = request(table, select: [field("sku")]).object
    query["sql"] = .string("DROP TABLE items")
    try refuses("query") { _ = try book.queryDataset(.object(query)) }
    try refuses("query_column") {
      _ = try book.queryDataset(request(table, select: [field("calculated")]))
    }
    try refuses("query_aggregate") {
      _ = try book.queryDataset(request(table, select: [field("sku", aggregate: "sum")]))
    }
    try refuses("query_value") {
      _ = try book.queryDataset(
        request(
          table, select: [field("sku")],
          filters: [.object(["column": ref("cost"), "op": .string("gt"), "value": .number(1)])]))
    }
    try refuses("query") {
      _ = try book.queryDataset(
        request(table, select: [field("group"), field("cost", aggregate: "sum")]))
    }
    let malicious = "'; DROP TABLE items; --"
    let result = try book.queryDataset(
      request(
        table, select: [field("sku")],
        filters: [
          .object(["column": ref("sku"), "op": .string("eq"), "value": .string(malicious)])
        ]))
    try expect(result["rows"] == .array([]) && book.verify()["ok"] == .bool(true))
  }
  check("managed left joins preserve unmatched provenance and actual multiplicity") {
    let (book, table) = try fixture("QueryJoins")
    let source = try book.addItem(category: "source", kind: "note", title: "Regions")
    let right = try book.createDataset(
      title: "Regions",
      columns: [.init(id: "group", title: "Group"), .init(id: "region", title: "Region")],
      rows: [
        ["group": .string("A"), "region": .string("North")],
        ["group": .string("A"), "region": .string("South")],
      ], sourceID: source.id)
    var query = request(table, select: [field("sku"), field("region", source: 1)]).object
    query["sources"] = .array(
      query["sources"]!.array + [
        .object(["datasetID": .string(right.id), "definitionID": .string(right.definitionID)])
      ])
    query["joins"] = .array([
      .object(["kind": .string("left"), "left": ref("group"), "right": .string("group")])
    ])
    let result = try book.queryDataset(.object(query))["rows"].array
    try expect(result.count == 6 && result.last!["inputs"].array[1] == .null)
    query["select"] = .array([.object(["id": .string("count"), "aggregate": .string("countRows")])])
    try expect(
      try book.queryDataset(.object(query))["rows"].array[0]["values"]["count"] == .string("6"))
    var rightScope = query["sources"]!.array[1].object
    rightScope["scope"] = .object(["scenario": .string("unmatched")])
    query["sources"] = .array([query["sources"]!.array[0], .object(rightScope)])
    query["select"] = .array([field("sku"), field("region", source: 1)])
    let scoped = try book.queryDataset(.object(query))["rows"].array
    try expect(scoped.count == 4 && scoped.allSatisfy { $0["inputs"].array[1] == .null })
    try expect(
      try book.datasetQueryPlan(.object(query))["plan"].array.allSatisfy {
        !$0.text.contains("MATERIALIZE") && !$0.text.contains("AUTOMATIC")
      })
  }
  check("managed query budgets and precision failure leave later queries usable") {
    let (book, table) = try fixture(
      "QueryBudgets", rows: (0..<500).map { _ in ["group": .string("same"), "cost": .string("1")] })
    let simple = request(table, select: [field("group")], limit: 1)
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses("cancelled") { _ = try book.queryDataset(simple, cancellation: cancelled) }
    try refuses("deadline") { _ = try book.queryDataset(simple, deadlineSeconds: 0) }
    var cross = request(
      table, select: [.object(["id": .string("count"), "aggregate": .string("countRows")])]
    ).object
    cross["sources"] = .array(cross["sources"]!.array + cross["sources"]!.array)
    cross["joins"] = .array([
      .object(["kind": .string("inner"), "left": ref("group"), "right": .string("group")])
    ])
    try refuses("query_input_limit") { _ = try book.queryDataset(.object(cross)) }
    try expect(try book.db.scalar("PRAGMA automatic_index").int == 1)
    try expect(try book.queryDataset(simple)["rows"].array.count == 1)
    let (precise, amounts) = try fixture(
      "QueryPrecision",
      rows: [["cost": .string("99999999999999999999999999999999999999")], ["cost": .string("0.1")]])
    try refuses("query_precision") {
      _ = try precise.queryDataset(request(amounts, select: [field("cost", aggregate: "sum")]))
    }
    try expect(
      try precise.queryDataset(request(amounts, select: [field("cost")]))["rows"].array.count == 2)
  }
  check("disposable query indexes use measured plans and preserve exact business history") {
    let (book, table) = try fixture(
      "QueryIndexes",
      rows: (0..<1000).map {
        [
          "sku": .string(String(format: "%04d", $0)), "cost": .string(String($0)),
          "group": .string($0 % 2 == 0 ? "A" : "B"),
        ]
      })
    let query = request(
      table, select: [field("sku"), field("cost")],
      filters: [.object(["column": ref("cost"), "op": .string("gte"), "value": .string("990")])],
      sort: [.object(["field": .string("cost"), "descending": .bool(true)])])
    let before = try book.queryDataset(query)
    let commits = try book.committedHistory(limit: 1000)
    let revision = try book.revision()
    let optimized = try book.optimizeDatasetQuery(query)
    try expect(optimized["decisions"].array[0]["state"] == .string("created"))
    try expect(
      optimized["afterPlan"].array.contains { $0.text.contains("USING INDEX sevra_perf_") })
    try expect(try book.queryDataset(query)["rows"] == before["rows"])
    try expect(try book.revision() == revision && book.committedHistory(limit: 1000) == commits)
    let opened = try Workbook(book.url)
    try expect(try opened.verify()["ok"] == .bool(true))
    let replayURL = root.appendingPathComponent("QueryIndexReplay.sevra")
    _ = try opened.reconstruct(to: replayURL)
    let replay = try Workbook(replayURL)
    try expect(
      try replay.db.performanceIndexes().isEmpty
        && replay.queryDataset(query)["rows"] == before["rows"])
    try expect(try book.removeDatasetQueryIndexes(table.id)["removed"].int == 1)
    try expect(
      try book.committedHistory(limit: 1000) == commits && book.verify()["ok"] == .bool(true))
  }
  check("managed query output byte limits refuse without a partial result") {
    let (book, table) = try fixture(
      "QueryOutput",
      rows: (0..<10).map {
        ["sku": .string(String($0)), "group": .string("same"), "cost": .string("1")]
      })
    var columns = table.columns
    columns.append(.init(id: "body", title: "Body"))
    try book.setColumns(table.id, columns: columns)
    let large = String(repeating: "x", count: 200_000)
    for row in try book.rows(table.id) {
      var values = row.data.object
      values["body"] = .string(large)
      _ = try book.editRow(row.id, values: values)
    }
    let current = try book.dataset(table.id)
    var query = request(current, select: [field("body")]).object
    query["sources"] = .array(query["sources"]!.array + query["sources"]!.array)
    query["joins"] = .array([
      .object(["kind": .string("inner"), "left": ref("group"), "right": .string("group")])
    ])
    try refuses("query_result_limit") { _ = try book.queryDataset(.object(query)) }
    try expect(
      try book.queryDataset(request(current, select: [field("sku")], limit: 1))["rows"].array.count
        == 1)
  }
  check("managed query grouping and joins compare exact decimal keys and reject unit mismatches") {
    let (book, table) = try fixture(
      "QueryDecimalKeys",
      rows: [["cost": .string("1.00")], ["cost": .string("1")], ["cost": .string("1.01")]])
    let groups = try book.queryDataset(
      request(
        table,
        select: [
          field("cost"), .object(["id": .string("count"), "aggregate": .string("countRows")]),
        ], groups: [ref("cost")]))["rows"].array
    try expect(
      groups.count == 2 && groups[0]["values"]["cost"] == .string("1")
        && groups[0]["values"]["count"] == .string("2"))
    var query = request(
      table, select: [.object(["id": .string("count"), "aggregate": .string("countRows")])]
    ).object
    query["sources"] = .array(query["sources"]!.array + query["sources"]!.array)
    query["joins"] = .array([
      .object(["kind": .string("inner"), "left": ref("cost"), "right": .string("cost")])
    ])
    try expect(
      try book.queryDataset(.object(query))["rows"].array[0]["values"]["count"] == .string("5"))
    let source = try book.addItem(category: "source", kind: "note", title: "Different currency")
    let other = try book.createDataset(
      title: "EUR", columns: [.init(id: "cost", title: "Cost", type: "decimal", unit: "EUR")],
      rows: [], sourceID: source.id)
    query["sources"] = .array([
      query["sources"]!.array[0],
      .object(["datasetID": .string(other.id), "definitionID": .string(other.definitionID)]),
    ])
    try refuses("query_join") { _ = try book.queryDataset(.object(query)) }
  }
  check("query indexes survive edits and repair, and schema rebuild discards them") {
    let (book, table) = try fixture("QueryIndexLifecycle")
    let query = request(
      table, select: [field("sku")],
      filters: [.object(["column": ref("sku"), "op": .string("eq"), "value": .string("0012")])])
    _ = try book.optimizeDatasetQuery(query)
    try expect(try book.db.performanceIndexes().count == 1)
    let first = try book.rows(table.id)[0]
    var values = first.data.object
    values["sku"] = .string("changed")
    _ = try book.editRow(first.id, values: values)
    try expect(try book.queryDataset(query)["rows"].array.isEmpty)
    try book.rebuildDataset(table.id, expectedRevision: book.revision())
    try expect(
      try book.db.performanceIndexes().count == 1 && book.queryDataset(query)["rows"].array.isEmpty)
    try book.setColumns(table.id, columns: table.columns + [.init(id: "new", title: "New")])
    try expect(try book.db.performanceIndexes().isEmpty && book.verify()["ok"] == .bool(true))
  }
  check("unregistered or altered query indexes refuse workbook opening") {
    let (book, table) = try fixture("QueryIndexTamper")
    let schema = try book.db.managedSchema(table.id)
    try book.db.script(
      "CREATE INDEX sevra_perf_forged ON " + ChangeFormat.quote(schema.table) + "("
        + ChangeFormat.quote(schema.field("sku")) + ")")
    try refuses("schema") { _ = try Workbook(book.url) }
    try refuses("schema") { _ = try book.queryDataset(request(table, select: [field("sku")])) }
  }
  check("index growth eviction and canonical publication share atomic rollback") {
    let (book, table) = try fixture("QueryIndexEviction")
    let query = request(
      table, select: [field("sku")],
      filters: [.object(["column": ref("sku"), "op": .string("eq"), "value": .string("0012")])])
    _ = try book.optimizeDatasetQuery(query)
    let index = try book.db.performanceIndexes()[0]
    // A connection-local accounting fault exercises the actual over-budget
    // branch without inflating every core run by nine MiB of synthetic keys.
    try book.db.script(
      "CREATE TEMP VIEW dbstat AS SELECT '" + index.name + "' AS name,9000000 AS pgsize")
    let original = try book.rows(table.id)[0]
    var values = original.data.object
    values["sku"] = .string("Changed")
    let commits = try book.committedHistory(limit: 1000)
    try book.db.script(
      "CREATE TEMP TRIGGER reject_indexed_edit BEFORE INSERT ON committed_changes BEGIN SELECT RAISE(ABORT,'publication fault'); END"
    )
    try refuses { _ = try book.editRow(original.id, values: values, token: "indexed-edit") }
    try expect(
      try book.db.performanceIndexes().count == 1 && book.rows(table.id)[0].id == original.id
        && book.committedHistory(limit: 1000) == commits)
    try book.db.script("DROP TRIGGER temp.reject_indexed_edit")
    _ = try book.editRow(original.id, values: values, token: "indexed-edit")
    try expect(
      try book.db.performanceIndexes().isEmpty
        && book.rows(table.id)[0].data["sku"] == .string("Changed"))
    try book.db.script("DROP VIEW temp.dbstat")
    try expect(try book.verify()["ok"] == .bool(true))
    _ = try book.optimizeDatasetQuery(query)
    try expect(try book.db.performanceIndexes().count == 1)
    try book.db.script(
      "CREATE TEMP VIEW dbstat AS SELECT absent_size_adapter() AS pgsize,'unavailable' AS name")
    let current = try book.rows(table.id)[0]
    values["sku"] = .string("Updated without optional accounting")
    _ = try book.editRow(current.id, values: values)
    try expect(
      try book.db.performanceIndexes().isEmpty
        && book.rows(table.id)[0].data["sku"] == values["sku"])
    try book.db.script("DROP VIEW temp.dbstat")
  }
}
