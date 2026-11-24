import Foundation
import os

public struct VisualDiagram: Codable, Equatable, Sendable {
  public let title: String
  public let nodes: Value
  public let edges: Value
  public let key: String
  public let label: String
  public let from: String
  public let to: String
  public let positions: [String: DiagramGeometry.Position]?

  static func parse(_ value: Value) throws -> Self {
    _ = try queryObject(
      value, keys: ["title", "nodes", "edges", "key", "label", "from", "to", "positions"])
    let diagram = try decodeDescriptor(Self.self, from: value, named: "diagram")
    try diagram.validate()
    return diagram
  }

  func validate(appAliases: Set<String>? = nil) throws {
    let nodeQuery = try visualQuery(nodes, appAliases: appAliases)
    let edgeQuery = try visualQuery(edges, appAliases: appAliases)
    try require(
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.utf8.count <= 200
        && key != label && from != to
        && nodeQuery.limit <= 100 && edgeQuery.limit <= 200
        && !nodeQuery.grouped && !edgeQuery.grouped
        && nodeQuery.sources.count == 1 && edgeQuery.sources.count == 1
        && Set(nodeQuery.selections.map(\.id)) == [key, label]
        && Set(edgeQuery.selections.map(\.id)) == [from, to],
      "visual_diagram", "Choose two exact row queries for up to 100 records and 200 relationships.")
    if let positions {
      try require(
        positions.count <= 100
          && positions.allSatisfy { key, point in
            !key.isEmpty && key.utf8.count <= 160 && (12...31_800).contains(point.x)
              && (12...31_800).contains(point.y)
          }, "visual_diagram", "Use exact node keys and positions within the diagram canvas.")
    }
  }
}

public struct VisualDiagramData: Codable, Equatable, Sendable {
  public struct Node: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let source: String
  }
  public struct Edge: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let from: String
    public let to: String
    public let source: String
  }
  public let nodes: [Node]
  public let edges: [Edge]
  public let snapshot: String

  init(_ results: [Value], diagram: VisualDiagram) throws {
    try require(
      results.count == 2 && results.allSatisfy { $0["hasMore"] == .bool(false) }
        && results[0]["snapshot"] == results[1]["snapshot"], "visual_diagram_coverage",
      "Filter the diagram to show a complete set within 100 records and 200 relationships.")
    func version(_ row: Value) throws -> String {
      guard let id = row["inputs"].array.first?["versionID"].string else {
        throw SevraError("visual_diagram", "Each record and relationship needs an exact source.")
      }
      return id
    }
    nodes = try results[0]["rows"].array.map { row in
      try Node(
        id: row["values"][diagram.key].text, label: row["values"][diagram.label].text,
        source: version(row))
    }
    edges = try results[1]["rows"].array.map { row in
      let source = try version(row)
      return Edge(
        id: source, from: row["values"][diagram.from].text,
        to: row["values"][diagram.to].text, source: source)
    }
    snapshot = results[0]["snapshot"].text
    try validate()
  }

  func validate() throws {
    let ids = Set(nodes.map(\.id))
    try require(
      nodes.count <= 100 && edges.count <= 200 && ids.count == nodes.count
        && Set(edges.map(\.id)).count == edges.count && snapshot.utf8.count <= 128
        && nodes.allSatisfy {
          !$0.id.isEmpty && $0.id.utf8.count <= 160 && !$0.label.isEmpty
            && $0.label.utf8.count <= 200 && $0.source.utf8.count <= 128
        }
        && edges.allSatisfy {
          ids.contains($0.from) && ids.contains($0.to)
            && $0.source.utf8.count <= 128
        },
      "visual_diagram", "Use unique record keys and relationships between records in the diagram.")
  }

  public var cyclicNodes: Set<String> {
    let outgoing = Dictionary(grouping: edges, by: \.from)
    return Set(
      nodes.compactMap { node in
        var visited: Set<String> = []
        var stack = outgoing[node.id, default: []].map(\.to)
        while let target = stack.popLast() {
          if target == node.id { return node.id }
          if visited.insert(target).inserted { stack += outgoing[target, default: []].map(\.to) }
        }
        return nil
      })
  }

  public var componentCount: Int {
    var neighbors: [String: [String]] = [:]
    for edge in edges {
      neighbors[edge.from, default: []].append(edge.to)
      neighbors[edge.to, default: []].append(edge.from)
    }
    var visited: Set<String> = []
    var count = 0
    for node in nodes where !visited.contains(node.id) {
      count += 1
      var queue = [node.id]
      while let id = queue.popLast() {
        if visited.insert(id).inserted { queue += neighbors[id, default: []] }
      }
    }
    return count
  }

  public func layout(
    positions: [String: DiagramGeometry.Position]? = nil, cancellation: Cancellation = .init()
  ) throws -> DiagramGeometry {
    try cancellation.check()
    try validate()
    // The helper receives anonymous ordinal identifiers and measured boxes only.
    // It never receives record names, keys, source references or an app grant.
    let ids = Dictionary(
      uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, $0.offset) })
    let input: Value = .object([
      "nodes": .number(Double(nodes.count)),
      "edges": .array(
        edges.map { edge in
          .array([.number(Double(ids[edge.from]!)), .number(Double(ids[edge.to]!))])
        }),
    ])
    let key = try input.json()
    let geometry: DiagramGeometry
    if let cached = DiagramGeometryCache.value(for: key) {
      geometry = cached
    } else {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "sevra-layout-" + identifier())
      try FileManager.default.createDirectory(
        at: root, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      defer { try? FileManager.default.removeItem(at: root) }
      let file = root.appendingPathComponent("graph.json")
      try Data(key.utf8).write(to: file)
      let worker = ExtractionWorker(timeout: 2, maximumMemoryBytes: 192 * 1024 * 1024)
      geometry = try worker.run(file, mode: ["--diagram-layout"], cancellation: cancellation)
      try geometry.validate(nodes: nodes.count, edges: edges.count)
      DiagramGeometryCache.store(geometry, for: key)
    }
    try cancellation.check()
    guard let positions, !positions.isEmpty else { return geometry }
    return try geometry.applying(
      positions, ids: ids, endpoints: edges.map { (ids[$0.from]!, ids[$0.to]!) })
  }

  package func positionPage(
    _ positions: [String: DiagramGeometry.Position]?, offset: Int, cancellation: Cancellation
  ) throws -> Value {
    try require((0...100).contains(offset), "visual_diagram", "Use a valid diagram page.")
    let geometry: DiagramGeometry
    do {
      geometry = try layout(positions: positions, cancellation: cancellation)
    } catch {
      try cancellation.check()
      var fallback = try inspection(node: nil, offset: offset).object
      fallback["layout"] = .string("unavailable")
      fallback["notice"] = .string(String(error.localizedDescription.prefix(300)))
      return .object(fallback)
    }
    let indices = nodes.indices.dropFirst(offset).prefix(12)
    return .object([
      "snapshot": .string(snapshot), "nodeCount": .number(Double(nodes.count)),
      "positions": .array(
        try indices.map { index in
          let node = nodes[index]
          return .object([
            "key": .string(node.id), "label": .string(node.label),
            "position": try encoded(geometry.nodes[index]),
          ])
        }),
      "nextOffset": offset + indices.count < nodes.count
        ? .number(Double(offset + indices.count)) : .null,
    ])
  }
}

private enum DiagramGeometryCache {
  private static let entries = OSAllocatedUnfairLock(initialState: [(String, DiagramGeometry)]())

  static func value(for key: String) -> DiagramGeometry? {
    entries.withLock { values in values.first { $0.0 == key }?.1 }
  }

  static func store(_ geometry: DiagramGeometry, for key: String) {
    entries.withLock { values in
      if values.contains(where: { $0.0 == key }) { return }
      // Each entry has at most 6,400 points, and contains only anonymous topology.
      if values.count == 16 { values.removeFirst() }
      values.append((key, geometry))
    }
  }
}

public struct DiagramGeometry: Codable, Sendable {
  public struct Position: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
  }
  public let width: Double
  public let height: Double
  public let nodes: [Position]
  public let edges: [[[Position]]]
  public static let nodeWidth = 168.0
  public static let nodeHeight = 48.0

  func applying(_ overrides: [String: Position], ids: [String: Int], endpoints: [(Int, Int)])
    throws -> Self
  {
    var moved = nodes
    var changed: Set<Int> = []
    for (id, position) in overrides {
      guard let index = ids[id] else {
        throw SevraError("visual_diagram", "A positioned record is missing from this diagram.")
      }
      moved[index] = position
      changed.insert(index)
    }
    let routes = endpoints.enumerated().map { index, edge in
      let (from, to) = edge
      guard changed.contains(from) || changed.contains(to) else { return edges[index] }
      let a = moved[from]
      let b = moved[to]
      if from == to {
        let side = a.x + Self.nodeWidth
        let center = a.y + Self.nodeHeight / 2
        return [
          [
            Position(x: side, y: center + 8), Position(x: side + 10, y: center + 8),
            Position(x: side + 10, y: center - 8), Position(x: side, y: center - 8),
          ]
        ]
      }
      if abs(a.x - b.x) >= Self.nodeWidth {
        return [
          [
            Position(x: a.x + (a.x < b.x ? Self.nodeWidth : 0), y: a.y + Self.nodeHeight / 2),
            Position(x: b.x + (a.x > b.x ? Self.nodeWidth : 0), y: b.y + Self.nodeHeight / 2),
          ]
        ]
      }
      return [
        [
          Position(x: a.x + Self.nodeWidth / 2, y: a.y + (a.y < b.y ? Self.nodeHeight : 0)),
          Position(x: b.x + Self.nodeWidth / 2, y: b.y + (a.y > b.y ? Self.nodeHeight : 0)),
        ]
      ]
    }
    let result = Self(
      width: max(width, (moved.map(\.x).max() ?? 0) + Self.nodeWidth + 12),
      height: max(height, (moved.map(\.y).max() ?? 0) + Self.nodeHeight + 12),
      nodes: moved, edges: routes)
    try result.validate(nodes: nodes.count, edges: edges.count)
    return result
  }

  func validate(nodes count: Int, edges edgeCount: Int) throws {
    func fits(_ position: Position) -> Bool {
      position.x.isFinite && position.y.isFinite
        && (0...width).contains(position.x) && (0...height).contains(position.y)
    }
    try require(
      width.isFinite && height.isFinite && (0...32_000).contains(width)
        && (0...32_000).contains(height)
        && nodes.count == count && edges.count == edgeCount
        && nodes.allSatisfy {
          fits($0) && $0.x + Self.nodeWidth <= width
            && $0.y + Self.nodeHeight <= height
        }
        && edges.allSatisfy {
          (1...6).contains($0.count)
            && $0.allSatisfy { (2...128).contains($0.count) && $0.allSatisfy(fits) }
        }
        && edges.flatMap({ $0 }).reduce(0, { $0 + $1.count }) <= 6_400,
      "diagram_geometry", "The diagram geometry exceeded its bounds. Inspect the relationship list."
    )
    for (index, position) in nodes.enumerated() {
      try require(
        nodes.suffix(from: index + 1).allSatisfy {
          abs(position.x - $0.x) >= Self.nodeWidth || abs(position.y - $0.y) >= Self.nodeHeight
        }, "diagram_geometry", "The layout overlaps records. Inspect the relationship list.")
    }
  }
}

extension Workbook {
  public func diagramData(_ diagram: VisualDiagram, cancellation: Cancellation = .init()) throws
    -> VisualDiagramData
  {
    try diagram.validate()
    return try VisualDiagramData(
      queryDatasetSet([diagram.nodes, diagram.edges], cancellation: cancellation), diagram: diagram)
  }
}

extension VisualDiagramData {
  func inspection(node: String?, offset: Int) throws -> Value {
    try require((0...200).contains(offset), "visual_diagram", "Use a valid diagram page.")
    if let node {
      try require(nodes.contains { $0.id == node }, "visual_diagram", "Choose a captured node key.")
    }
    let edges = edges.filter { edge in node == nil || edge.from == node || edge.to == node }
    let records = nodes.filter { node == nil || $0.id == node }
    return .object([
      "snapshot": .string(snapshot), "nodeCount": .number(Double(records.count)),
      "edgeCount": .number(Double(edges.count)),
      "nodes": try encoded(Array(records.dropFirst(offset).prefix(12))),
      "edges": try encoded(Array(edges.dropFirst(offset).prefix(12))),
      "nextOffset": offset + 12 < max(edges.count, records.count)
        ? .number(Double(offset + 12)) : .null,
    ])
  }
}
