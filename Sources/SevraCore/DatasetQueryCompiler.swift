import Foundation

extension Workbook {
  func compileDatasetQuery(_ request: DatasetQuery, offset: Int = 0) throws -> CompiledDatasetQuery
  {
    let schemas = try request.sources.map { source in
      let definition = try datasetDefinition(source.dataset)
      try require(
        definition.id == source.definition, "stale_schema",
        "A query's table definition changed. Refresh its fields and try again.")
      return try db.managedSchema(source.dataset)
    }
    let quote = ChangeFormat.quote
    func column(_ ref: QueryColumn) throws -> Column {
      guard schemas.indices.contains(ref.source),
        let column = schemas[ref.source].stored.first(where: { $0.id == ref.column })
      else {
        throw SevraError(
          "query_column",
          "Select a registered stored column. Calculated columns need a materialized result.")
      }
      return column
    }
    func field(_ ref: QueryColumn) throws -> String {
      _ = try column(ref)
      return "t\(ref.source)." + quote(schemas[ref.source].field(ref.column))
    }
    func known(_ ref: QueryColumn) throws -> String {
      let raw = try field(ref)
      return try column(ref).type == "text" ? raw : "NULLIF(" + raw + ",'')"
    }
    var arguments: [Value] = []
    func scopePredicate(_ source: Int) -> String? {
      let scope = request.sources[source].scope
      guard !scope.isEmpty else { return nil }
      let filters = scope.keys.sorted().map { key in
        arguments.append(.string(scope[key]!))
        return "im." + quote(key) + "=?"
      }
      // Correlated primary-key lookups avoid materializing a complete right-hand
      // table (including unselected large cells) before a LEFT JOIN's guard.
      return "EXISTS(SELECT 1 FROM items im WHERE im.id=t\(source)._sevra_item AND "
        + filters.joined(separator: " AND ") + ")"
    }
    var from = quote(schemas[0].table) + " t0"
    for (index, join) in request.joins.enumerated() {
      let right = try QueryColumn(
        .object(["source": .number(Double(index + 1)), "column": .string(join.right)]))
      let lhs = try column(join.left)
      let rhs = try column(right)
      try require(join.left.source <= index, "query_join", "Join to an earlier source.")
      try require(
        lhs.type == rhs.type && lhs.unit == rhs.unit, "query_join",
        "Join keys must have the same logical type and unit.")
      from +=
        " " + join.kind.uppercased() + " JOIN " + quote(schemas[index + 1].table)
        + " t\(index + 1) ON " + (try field(join.left)) + "=" + (try field(right))
      if lhs.type != "text" {
        from += " AND " + (try field(join.left)) + "<>'' AND " + (try field(right)) + "<>''"
      }
      if let predicate = scopePredicate(index + 1) { from += " AND " + predicate }
    }
    var predicates: [String] = []
    if let predicate = scopePredicate(0) { predicates.append(predicate) }
    for filter in request.filters {
      let definition = try column(filter.column)
      let name = try field(filter.column)
      if filter.op == "isNull" {
        predicates.append(name + " IS NULL")
        continue
      }
      if filter.op == "isEmpty" {
        predicates.append(name + "=''")
        continue
      }
      let value = filter.value!
      try require(value != .null, "query_value", "Use isNull instead of comparing null.")
      switch definition.type {
      case "decimal":
        try require(value.string != nil, "query_value", "Pass exact decimal query values as text.")
        _ = try Numbers.decimal(value.text)
      case "date":
        try require(value.string != nil && !value.text.isEmpty, "query_value", "Use an ISO date.")
      case "boolean":
        guard case .bool = value else { throw SevraError("query_value", "Use true or false.") }
      default: try require(value.string != nil, "query_value", "Use a text comparison value.")
      }
      try require(value.text.utf8.count <= 4096, "query_value", "Comparison value is too long.")
      let scalar = try schemas[filter.column.source].scalar(value, column: definition)
      if filter.op == "contains" {
        try require(definition.type == "text", "query_value", "Contains applies to text.")
        predicates.append("instr(" + name + ",?)>0")
      } else {
        let operators = ["eq": "=", "ne": "<>", "lt": "<", "lte": "<=", "gt": ">", "gte": ">="]
        predicates.append(name + operators[filter.op]! + "?")
        if definition.type != "text" { predicates.append(name + "<>''") }
      }
      arguments.append(scalar)
    }
    var selected: [String] = []
    var columns: [Column] = []
    for (index, selection) in request.selections.enumerated() {
      let original = try selection.column.map(column)
      var expression = try selection.column.map(field) ?? "*"
      if let aggregate = selection.aggregate {
        if ["sum", "average"].contains(aggregate) {
          try require(
            original?.type == "decimal", "query_aggregate", "Sum and average need decimals.")
          let sum = "SEVRA_DECIMAL_SUM(" + expression + ")"
          expression =
            aggregate == "sum"
            ? sum
            : "SEVRA_DECIMAL_DIVIDE(" + sum + ",COUNT(" + (try known(selection.column!)) + "))"
        } else if aggregate == "countRows" {
          expression = "COUNT(*)"
        } else {
          expression = try known(selection.column!)
          if original?.type == "decimal" { expression += " COLLATE SEVRA_DECIMAL" }
          expression = aggregate.uppercased() + "(" + expression + ")"
        }
      }
      let count = ["count", "countRows"].contains(selection.aggregate ?? "")
      columns.append(
        Column(
          id: selection.id, title: selection.id, type: count ? "decimal" : original!.type,
          unit: count ? nil : original?.unit))
      selected.append(expression + " AS " + quote("v\(index)"))
    }
    let refs = Set(
      request.selections.compactMap(\.column) + request.filters.map(\.column) + request.groups
        + request.joins.map(\.left)
        + (try request.joins.enumerated().map {
          try QueryColumn(
            .object(["source": .number(Double($0.offset + 1)), "column": .string($0.element.right)])
          )
        }))
    var guarded = try refs.sorted {
      $0.source == $1.source ? $0.column < $1.column : $0.source < $1.source
    }.map(field)
    for index in schemas.indices {
      // Every join must be resolved before charging its contributing row. This
      // also bounds countRows, which otherwise references no user value.
      guarded += ["t\(index)._sevra_row", "t\(index)._sevra_item"]
      if !request.grouped {
        selected += [
          "t\(index)._sevra_row AS r\(index)", "t\(index)._sevra_logical AS l\(index)",
          "t\(index)._sevra_item AS i\(index)",
        ]
        for key in ["meaning", "status", "scenario"] {
          selected.append(
            "(SELECT " + quote(key) + " FROM items im WHERE im.id=t\(index)._sevra_item) AS "
              + quote("m\(index)_" + key))
        }
      }
    }
    predicates.append("SEVRA_QUERY_GUARD(" + guarded.joined(separator: ",") + ")=1")
    var sql =
      "SELECT " + selected.joined(separator: ",") + " FROM " + from
      + " WHERE " + predicates.joined(separator: " AND ")
    if !request.groups.isEmpty {
      sql += " GROUP BY " + (try request.groups.map(field)).joined(separator: ",")
    }
    var order = request.sorts.map { sort -> String in
      let index = request.selections.firstIndex { $0.id == sort.field }!
      return quote("v\(index)") + (columns[index].type == "decimal" ? " COLLATE SEVRA_DECIMAL" : "")
        + (sort.descending ? " DESC" : " ASC")
    }
    if request.grouped {
      order += try request.groups.map(field)
    } else {
      for index in schemas.indices {
        order += ["t\(index)._sevra_ordinal", "t\(index)._sevra_row"]
      }
    }
    if !order.isEmpty { sql += " ORDER BY " + order.joined(separator: ",") }
    sql += " LIMIT ? OFFSET ?"
    arguments += [.number(Double(request.limit + 1)), .number(Double(offset))]
    return .init(
      request: request, schemas: schemas, columns: columns, sql: sql, arguments: arguments)
  }
}
