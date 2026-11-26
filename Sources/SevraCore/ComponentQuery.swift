import Foundation

/// A table, chart or metric on a view can show the result of one read-only SELECT instead of
/// a whole table: the overdue invoices, this month's total, the last seven days. The query
/// runs on the same copy as chat's `sql`, with the same table names, dialect and local-time
/// date functions, each time the view is drawn, so what it shows follows the workbook. It is
/// checked when the view is saved, and a query that stops running later, say after a column
/// was renamed, says so on the view instead of showing old rows.
public struct ComponentQueryResult: Sendable {
  public let snapshot: ComponentSnapshot
  /// The ids of the workbook tables the query read.
  public let tableIDs: [String]
}

extension Workbook {
  /// The components that can show a query's result.
  public static let queryComponentTypes: Set<String> = ["table", "chart", "metric"]
  /// The rows a view shows of a query's result. A metric over more refuses, as over a table.
  static let componentQueryRows = 1_000

  /// Runs a view component's query. Its result columns are named as the SELECT names them,
  /// which is what a chart's x and y and a metric's y refer to. A result column named like a
  /// column of a table it read keeps that column's title, type and unit.
  public func componentQuery(_ query: String, cancellation: Cancellation = .init()) throws
    -> ComponentQueryResult
  {
    let statements = SQLScratch.split(query)
    try require(
      statements.count == 1 && query.utf8.count <= 8_000, "view_query",
      "A view's query is one SELECT of under 8,000 bytes, such as SELECT client, amount FROM invoices WHERE status = 'open'.")
    let statement = statements[0]
    let code = SQLScratch.pieces(statement).filter(\.code).map(\.text).joined()
    let first = code.trimmingCharacters(in: .whitespacesAndNewlines).prefix { $0.isLetter }
      .uppercased()
    try require(
      ["SELECT", "WITH"].contains(first), "view_query",
      "A view's query only reads: write one SELECT (WITH is fine). To change rows, use sql or a saved tool.")
    return try synchronized(cancellation: cancellation) {
      let session = try ChatSQLSession(self, readOnly: true, cancellation: cancellation)
      defer { session.close() }
      session.scratch.shownRows = Self.componentQueryRows
      session.scratch.shownBytes = 16_000_000
      let result: Value
      do {
        result = try session.run([statement])[0]
      } catch let error as SevraError {
        if error.code == "read_only_request" {
          throw SevraError(
            "view_query",
            "A view's query only reads: write one SELECT (WITH is fine). To change rows, use sql or a saved tool.")
        }
        var message = error.message
        if message.hasPrefix("Statement 1: ") { message.removeFirst("Statement 1: ".count) }
        throw SevraError(error.code == "sql_limit" ? "sql_limit" : "view_query", message)
      }
      let names = result["columns"].array.map(\.text)
      try require(
        !names.isEmpty, "view_query", "A view's query is a SELECT that returns columns.")
      let duplicates = Set(names.map { $0.lowercased() }.filter { name in
        names.filter { $0.lowercased() == name }.count > 1
      })
      try require(
        duplicates.isEmpty, "view_query",
        "The query returns two columns named " + duplicates.sorted().joined(separator: " and ")
          + ". Give each its own name with AS.")
      let read = session.scratch.readTables.map { session.scratch.table($0) }
      // The columns of the tables it read, by their sql names, first table first.
      var known: [String: Column] = [:]
      for table in read {
        for entry in SQLScratch.named([table]).first?.columns ?? []
        where known[entry.name.lowercased()] == nil {
          known[entry.name.lowercased()] = entry.column
        }
      }
      let rows = result["rows"].array.map(\.array)
      let columns = names.enumerated().map { index, name -> Column in
        let source = known[name.lowercased()]
        let values = rows.map { index < $0.count ? $0[index] : .null }
        let filled = values.filter { $0 != .null && !$0.text.isEmpty }
        let numeric =
          source.map { $0.type == "decimal" || $0.formula != nil }
          ?? (!filled.isEmpty && filled.allSatisfy { (try? Numbers.decimal($0.text)) != nil })
        return Column(
          id: name, title: source?.title ?? Self.queryColumnTitle(name),
          type: numeric ? "decimal" : (source?.type ?? "text"), unit: source?.unit)
      }
      let shown = rows.enumerated().map { offset, row in
        ComponentRow(
          id: "query-row-\(offset + 1)",
          values: Dictionary(
            uniqueKeysWithValues: names.enumerated().map { index, name in
              (name, index < row.count ? row[index] : .null)
            }))
      }
      return ComponentQueryResult(
        snapshot: ComponentSnapshot(
          columns: columns, rows: shown, totalRows: result["rowCount"].int ?? shown.count,
          captured: timestamp()),
        tableIDs: read.map(\.id))
    }
  }

  /// `days_late` reads as "Days late". A name with capitals or spaces is already a title.
  static func queryColumnTitle(_ name: String) -> String {
    let spaced = name.replacingOccurrences(of: "_", with: " ").trimmingCharacters(
      in: .whitespaces)
    guard spaced == spaced.lowercased(), let first = spaced.first else { return spaced }
    return first.uppercased() + spaced.dropFirst()
  }

  /// Whether a component shows a query's result rather than a whole table.
  public static func showsQuery(_ component: Component) -> Bool {
    component.query != nil && queryComponentTypes.contains(component.type)
  }
}
