import Foundation

public struct Component: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var type: String
  public var title: String
  public var datasetID: String?
  public var itemID: String?
  public var query: String?
  public var x: String?
  public var y: String?
  public var text: String?
  public var chartStyle: String?
  public var aggregation: String?
  public var unit: String?
  public var children: [Component]?
  public var snapshot: ComponentSnapshot?
  public init(
    id: String = identifier(), type: String, title: String, datasetID: String? = nil,
    itemID: String? = nil, query: String? = nil, x: String? = nil, y: String? = nil,
    text: String? = nil, chartStyle: String? = nil, aggregation: String? = nil,
    unit: String? = nil, children: [Component]? = nil, snapshot: ComponentSnapshot? = nil
  ) {
    self.id = id
    self.type = type
    self.title = title
    self.datasetID = datasetID
    self.itemID = itemID
    self.query = query
    self.x = x
    self.y = y
    self.text = text
    self.chartStyle = chartStyle
    self.aggregation = aggregation
    self.unit = unit
    self.children = children
    self.snapshot = snapshot
  }
}
public struct SpaceDefinition: Codable, Equatable, Sendable {
  public var version: Int = 1
  public var components: [Component]
  public init(components: [Component]) { self.components = components }
}
public struct Space: Codable, Identifiable, Sendable {
  public let id: String
  public let title: String
  public let definition: SpaceDefinition
  public let version: Int
}
public struct Message: Codable, Identifiable, Sendable {
  public let id: String
  public let role: String
  public let body: String
  public let state: String
  public let created: String
}
extension Workbook {
  public func spaces() throws -> [Space] {
    try synchronized {
      try db.execute("SELECT * FROM spaces ORDER BY CASE WHEN id='home' THEN 0 ELSE 1 END,title")
        .map { row in
          guard let version = row["version"]?.int, version > 0 else {
            throw SevraError("integrity", "Invalid space version.")
          }
          return Space(
            id: row["id"]!.text, title: row["title"]!.text,
            definition: try JSONDecoder().decode(
              SpaceDefinition.self, from: Data(row["definition"]!.text.utf8)),
            version: version)
        }
    }
  }
  @discardableResult public func saveSpace(
    id: String = identifier(), title: String, definition: SpaceDefinition,
    token: String = identifier()
  ) throws -> String {
    try require(
      definition.version == 1 && definition.components.count <= 16, "view",
      "Unsupported view version or too many components.")
    try require(
      Set(definition.components.map(\.id)).count == definition.components.count, "view",
      "Component identifiers must be unique.")
    var componentCount = 0
    var ids = Set<String>()
    func validate(_ c: Component, depth: Int) throws {
      componentCount += 1
      try require(
        componentCount <= 16 && depth <= 3 && ids.insert(c.id).inserted, "view",
        "Use at most 16 uniquely named components and three levels.")
      try require(
        ["table", "chart", "metric", "comparison", "document", "asset", "search", "text"].contains(
          c.type), "view", "Unknown native component: \(c.type)")
      if ["table", "chart", "metric"].contains(c.type) {
        guard let id = c.datasetID else {
          throw SevraError("view", "Component \(c.id) (\(c.type)) requires its own datasetID.")
        }
        let table = try dataset(id)
        if ["chart", "metric"].contains(c.type) {
          try require(
            table.columns.contains { $0.id == c.y }, "view", "Choose an existing value column.")
        }
        if c.type == "chart" {
          try require(
            table.columns.contains { $0.id == c.x }
              && ["bar", "line"].contains(c.chartStyle ?? "bar"), "view",
            "Choose valid chart columns and bar or line style.")
        }
        if c.type == "metric" {
          try require(
            ["SUM", "AVERAGE", "MIN", "MAX", "COUNT"].contains(c.aggregation ?? "SUM"), "view",
            "Choose a supported metric aggregation.")
        }
      }
      if ["document", "asset"].contains(c.type) {
        guard let id = c.itemID else { throw SevraError("view", "Item binding is required.") }
        _ = try item(id)
      }
      if c.type == "comparison" {
        try require(
          (2...3).contains(c.children?.count ?? 0), "view", "A comparison has two or three columns."
        )
      } else {
        try require(c.children == nil, "view", "Only comparisons contain child components.")
      }
      try require(
        (c.text?.utf8.count ?? 0) <= 64_000 && (c.unit?.utf8.count ?? 0) <= 40, "view",
        "Component text is too large.")
      if let snapshot = c.snapshot {
        try require(
          snapshot.rows.count <= 1000 && snapshot.totalRows == snapshot.rows.count, "view",
          "A pinned component must contain a complete bounded result.")
        for row in snapshot.rows { _ = try item(row.id) }
      }
      for child in c.children ?? [] { try validate(child, depth: depth + 1) }
    }
    for component in definition.components { try validate(component, depth: 1) }
    let data = try encoded(definition).json()
    _ = try mutation(
      "space", token: token,
      request: .object(["id": .string(id), "title": .string(title), "definition": .string(data)])
    ) {
      let version =
        (try db.scalar("SELECT version FROM spaces WHERE id=?", [.string(id)]).int ?? 0) + 1
      try db.execute(
        "INSERT INTO spaces VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,definition=excluded.definition,version=excluded.version,updated=excluded.updated",
        [
          .string(id), .string(title), .string(data), .number(Double(version)),
          .string(timestamp()),
        ])
      try db.execute(
        "INSERT INTO space_versions VALUES(?,?,?,?,?)",
        [
          .string(id), .number(Double(version)), .string(title), .string(data),
          .string(timestamp()),
        ])
      return .string(id)
    }
    return id
  }
  @discardableResult public func addMessage(
    _ body: String, role: String, conversation: String = "main", state: String = "complete",
    payload: Value = .null
  ) throws -> String {
    try require(body.utf8.count <= 128_000, "message_limit", "Message is too long.")
    let metadata = payload == .null ? nil : try payload.json()
    try require(
      (metadata?.utf8.count ?? 0) <= 128_000, "message_limit", "Message receipt is too long.")
    let id = identifier()
    _ = try mutation("message", request: .string(id)) {
      try db.execute(
        "INSERT INTO messages VALUES(?,?,?,?,?,?)",
        [
          .string(id), .string(conversation), .string(role), .string(body), .string(state),
          .string(timestamp()),
        ])
      if let metadata {
        try db.execute(
          "INSERT INTO message_payloads VALUES(?,?)", [.string(id), .string(metadata)])
      }
      return .string(id)
    }
    return id
  }
  public func messages(conversation: String = "main", limit: Int = 100) throws -> [Message] {
    try synchronized {
      try db.execute(
        "SELECT * FROM (SELECT rowid,* FROM messages WHERE conversation_id=? ORDER BY rowid DESC LIMIT ?) ORDER BY rowid",
        [.string(conversation), .number(Double(min(max(limit, 1), 500)))]
      ).map {
        Message(
          id: $0["id"]!.text, role: $0["role"]!.text, body: $0["body"]!.text,
          state: $0["state"]!.text, created: $0["created"]!.text)
      }
    }
  }
  public func conversations() throws -> [Value] {
    try synchronized { try db.execute("SELECT * FROM conversations").map(Value.object) }
  }
  @discardableResult public func tangent(title: String, parentMessage: String) throws -> String {
    let id = identifier()
    _ = try mutation("tangent", request: .string(title)) {
      try require(
        try db.scalar("SELECT count(*) FROM messages WHERE id=?", [.string(parentMessage)]).int
          == 1, "not_found", "The tangent needs an existing conversation message.")
      try db.execute(
        "INSERT INTO conversations VALUES(?,?,?)",
        [.string(id), .string(title), .string(parentMessage)])
      return .string(id)
    }
    return id
  }
  public func chapter(title: String, message: String, bookmark: Bool = false) throws {
    _ = try mutation(bookmark ? "bookmark" : "chapter", request: .string(title)) {
      try db.execute(
        "INSERT INTO \(bookmark ? "bookmarks" : "chapters") VALUES(?,?,?)",
        [.string(identifier()), .string(title), .string(message)])
      return .string(message)
    }
  }
  public func chapters(bookmarks: Bool = false) throws -> [Value] {
    try synchronized {
      try db.execute("SELECT * FROM \(bookmarks ? "bookmarks" : "chapters")").map(Value.object)
    }
  }
}

extension Workbook {
  public func messageLocation(_ id: String) throws -> Value {
    try synchronized {
      guard
        let row = try db.execute(
          "SELECT conversation_id,rowid FROM messages WHERE id=?", [.string(id)]
        ).first
      else { throw SevraError("message", "This conversation message is missing.") }
      return .object(row)
    }
  }
  public func messages(around id: String) throws -> [Message] {
    try synchronized {
      let location = try messageLocation(id)
      return try db.execute(
        "SELECT * FROM messages WHERE conversation_id=? AND rowid BETWEEN ? AND ? ORDER BY rowid",
        [
          location["conversation_id"], .number(Double((location["rowid"].int ?? 0) - 50)),
          .number(Double((location["rowid"].int ?? 0) + 50)),
        ]
      ).map {
        Message(
          id: $0["id"]!.text, role: $0["role"]!.text, body: $0["body"]!.text,
          state: $0["state"]!.text, created: $0["created"]!.text)
      }
    }
  }
  public func parentContext(conversation: String) throws -> [Message] {
    try synchronized {
      let parent = try db.scalar(
        "SELECT parent_message FROM conversations WHERE id=?", [.string(conversation)]
      ).text
      guard !parent.isEmpty else { return [] }
      let location = try messageLocation(parent)
      return try db.execute(
        "SELECT * FROM (SELECT rowid,* FROM messages WHERE conversation_id=? AND rowid<=? AND role IN ('user','assistant') ORDER BY rowid DESC LIMIT 6) ORDER BY rowid",
        [location["conversation_id"], location["rowid"]]
      ).map {
        Message(
          id: $0["id"]!.text, role: $0["role"]!.text, body: $0["body"]!.text,
          state: $0["state"]!.text, created: $0["created"]!.text)
      }
    }
  }
  @discardableResult public func bringToMain(message id: String) throws -> String {
    let message = try synchronized {
      try db.execute("SELECT * FROM messages WHERE id=?", [.string(id)]).first
    }
    guard let message else { throw SevraError("message", "No message to bring back.") }
    try require(
      message["conversation_id"]?.text != "main", "conversation",
      "This exchange is already in the main conversation.")
    let source = message["conversation_id"]!.text
    return try addMessage(
      "From a tangent:\n\n" + message["body"]!.text
        + "\n\n[Open original exchange](sevra://conversation/\(source)?message=\(id))",
      role: "user", conversation: "main")
  }
}
