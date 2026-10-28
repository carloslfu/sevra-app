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
/// The visible first page and its coverage limits are frozen together. A pinned
/// search never reruns its query or resolves an old hit to the current item head.
public struct ComponentSearchSnapshot: Codable, Sendable, Equatable {
  public let query: String
  public let hits: [SearchHit]
  public let incomplete: Int
  public let hasMore: Bool
  public let revision: Int
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
  /// Pin values, exact item versions and bounded search results in one transaction.
  @discardableResult public func pinSpace(
    _ id: String, title: String? = nil, token: String = identifier(),
    cancellation: Cancellation = .init()
  ) throws -> String {
    try cancellation.check()
    let result = try mutation(
      "pin_space", token: token,
      request: .object(["id": .string(id), "title": title.map(Value.string) ?? .null])
    ) {
      guard let space = try spaces().first(where: { $0.id == id }) else {
        throw SevraError("view", "Space not found.")
      }
      let captured = space.definition.pinnedAt ?? timestamp()
      let revision = try revision()
      func pin(_ component: Component) throws -> Component {
        try cancellation.check()
        try require(
          !SpaceDefinition.sectionTypes.contains(component.type) && component.type != "form",
          "view_limit",
          "Live workbook sections and forms cannot be frozen. Snapshot a space containing bound business views."
        )
        var copy = component
        if ["calculation", "query"].contains(component.type), component.evaluationSnapshot == nil {
          let evaluation = try componentDefinitionResult(component, cancellation: cancellation)
          copy.definitionBinding = .object([
            "mode": .string("exact"), "versionID": evaluation["definitionID"],
          ])
          copy.evaluationSnapshot = .init(
            evaluation: evaluation, captured: captured,
            inputPopulation: component.type == "query"
              ? try definitionQueryPopulation(evaluation, cancellation: cancellation) : nil)
          try validateDefinitionComponent(copy, pinned: true)
        }
        if component.datasetID != nil {
          let snapshot = try componentData(component)
          try require(
            snapshot.totalRows == snapshot.rows.count, "view_limit",
            "Pinning currently supports complete tables of up to 1,000 rows.")
          copy.snapshot = snapshot
        }
        if ["document", "asset"].contains(component.type), let id = component.itemID {
          copy.itemID = try item(id).id
        }
        if component.type == "search", component.searchSnapshot == nil {
          let query = component.query ?? ""
          let page = try search(query, limit: 8, cancellation: cancellation)
          copy.searchSnapshot = ComponentSearchSnapshot(
            query: query, hits: page.hits, incomplete: page.incomplete,
            hasMore: page.nextCursor != nil, revision: revision, captured: captured)
        }
        copy.children = try component.children?.map(pin)
        try cancellation.check()
        return copy
      }
      let definition = SpaceDefinition(
        components: try space.definition.components.map(pin), pinnedAt: captured)
      let data = try encoded(definition).json()
      try cancellation.check()
      let saved = identifier()
      let date = timestamp()
      let name = title ?? space.title + " · " + timestamp()
      let values: [Value] = [
        .string(saved), .string(name), .string(data), .number(1), .string(date),
      ]
      try db.execute("INSERT INTO spaces VALUES(?,?,?,?,?)", values)
      try db.execute(
        "INSERT INTO space_versions VALUES(?,?,?,?,?)",
        [.string(saved), .number(1), .string(name), .string(data), .string(date)])
      return .string(saved)
    }
    return result.text
  }
  public func columnHistory(_ id: String) throws -> [Value] {
    try datasetDefinitions(id).map { try encoded($0) }
  }
  public func restoreColumns(_ id: String, version: Int) throws {
    let saved = try synchronized {
      try db.scalar(
        "SELECT id FROM column_versions WHERE dataset_id=? AND version=?",
        [.string(id), .number(Double(version))]
      ).text
    }
    let base = try datasetDefinition(id)
    _ = try restoreDatasetDefinition(
      id, definitionID: saved, expectedVersion: base.version,
      expectedDefinitionID: base.id)
  }
}
