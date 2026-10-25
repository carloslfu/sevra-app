import Foundation

public struct ComponentRow: Codable, Identifiable, Equatable, Sendable {
  public let id: String
  public let values: [String: Value]
}
public struct ComponentSnapshot: Codable, Sendable, Equatable {
  public let columns: [Column]
  public let rows: [ComponentRow]
  public let totalRows: Int
  public let captured: String

}
extension Workbook {
  public func componentData(_ component: Component) throws -> ComponentSnapshot {
    if let snapshot = component.snapshot { return snapshot }
    guard let id = component.datasetID else {
      throw SevraError("view", "This component has no table binding.")
    }
    return try synchronized {
      try db.readTransaction {
        let table = try dataset(id)
        let values = try rows(id, limit: 1000).map {
          ComponentRow(id: $0.id, values: calculatedValues($0, columns: table.columns))
        }
        return ComponentSnapshot(
          columns: table.columns, rows: values, totalRows: table.rowCount, captured: timestamp())
      }
    }
  }
  public func componentMetric(_ component: Component, data: ComponentSnapshot) throws -> String {
    try require(
      data.rows.count == data.totalRows, "view_limit",
      "This metric exceeds 1,000 rows. Create a smaller derived table first; a partial sum would be misleading."
    )
    let function = component.aggregation ?? "SUM"
    if function == "COUNT" { return String(data.rows.count) }
    guard let column = component.y else {
      throw SevraError("view", "A metric needs a value column.")
    }
    let numbers = try data.rows.map { try Numbers.decimal($0.values[column]?.text ?? "") }
    guard var result = numbers.first else {
      throw SevraError("missing_value", "This table has no values.")
    }
    for number in numbers.dropFirst() {
      switch function {
      case "MIN": result = min(result, number)
      case "MAX": result = max(result, number)
      case "SUM", "AVERAGE": result = try Numbers.binary(result, number, op: "+")
      default: throw SevraError("view", "Unsupported metric aggregation.")
      }
    }
    if function == "AVERAGE" {
      result = try Numbers.binary(result, Decimal(numbers.count), op: "/")
    }
    return Numbers.string(result)
  }
  /// Pin both values and exact input versions, including the complete table used by A1 formulas.
  @discardableResult public func pinSpace(
    _ id: String, title: String? = nil, token: String = identifier()
  ) throws -> String {
    let result = try mutation("pin_space", token: token, request: .object(["id": .string(id), "title": title.map(Value.string) ?? .null])) {
      guard let space = try spaces().first(where: { $0.id == id }) else { throw SevraError("view", "Space not found.") }
      func pin(_ component: Component) throws -> Component {
        var copy = component
        if component.datasetID != nil {
          let snapshot = try componentData(component)
          try require(snapshot.totalRows == snapshot.rows.count, "view_limit", "Pinning currently supports complete tables of up to 1,000 rows.")
          copy.snapshot = snapshot
        }
        copy.children = try component.children?.map(pin)
        return copy
      }
      let definition = SpaceDefinition(components: try space.definition.components.map(pin))
      let data = String(decoding: try JSONEncoder().encode(definition), as: UTF8.self)
      let saved = identifier(), date = timestamp(), name = title ?? space.title + " · " + timestamp()
      let values: [Value] = [.string(saved), .string(name), .string(data), .number(1), .string(date)]
      try db.execute("INSERT INTO spaces VALUES(?,?,?,?,?)", values)
      try db.execute("INSERT INTO space_versions VALUES(?,?,?,?,?)", [.string(saved), .number(1), .string(name), .string(data), .string(date)])
      return .string(saved)
    }
    return result.text
  }
  public func columnHistory(_ id: String) throws -> [Value] {
    try synchronized {
      try db.execute(
        "SELECT version,columns,created FROM column_versions WHERE dataset_id=? ORDER BY version DESC",
        [.string(id)]
      ).map(Value.object)
    }
  }
  public func restoreColumns(_ id: String, version: Int) throws {
    let data = try synchronized {
      try db.scalar(
        "SELECT columns FROM column_versions WHERE dataset_id=? AND version=?",
        [.string(id), .number(Double(version))]
      ).text
    }
    try require(!data.isEmpty, "history", "Column version not found.")
    var columns = try JSONDecoder().decode([Column].self, from: Data(data.utf8))
    let existing = try dataset(id).columns
    columns += existing.filter { old in !columns.contains { $0.id == old.id } }
    try setColumns(id, columns: columns)
  }
}
