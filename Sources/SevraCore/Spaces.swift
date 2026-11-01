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
  public var searchSnapshot: ComponentSearchSnapshot?
  public var definitionBinding: Value?
  public var arguments: Value?
  public var evaluationSnapshot: DefinitionResultSnapshot?
  public init(
    id: String = identifier(), type: String, title: String, datasetID: String? = nil,
    itemID: String? = nil, query: String? = nil, x: String? = nil, y: String? = nil,
    text: String? = nil, chartStyle: String? = nil, aggregation: String? = nil,
    unit: String? = nil, children: [Component]? = nil, snapshot: ComponentSnapshot? = nil,
    searchSnapshot: ComponentSearchSnapshot? = nil, definitionBinding: Value? = nil,
    arguments: Value? = nil, evaluationSnapshot: DefinitionResultSnapshot? = nil
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
    self.searchSnapshot = searchSnapshot
    self.definitionBinding = definitionBinding
    self.arguments = arguments
    self.evaluationSnapshot = evaluationSnapshot
  }
}
public struct SpaceDefinition: Codable, Equatable, Sendable {
  public var version: Int = 1
  public var components: [Component]
  public var pinnedAt: String?
  public init(components: [Component], pinnedAt: String? = nil) {
    self.components = components
    self.pinnedAt = pinnedAt
  }
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
            definition: try decodedSpaceDefinition(row),
            version: version)
        }
    }
  }
  @discardableResult public func saveSpace(
    id: String = identifier(), title: String, definition: SpaceDefinition,
    expectedVersion: Int? = nil, token: String = identifier(), actor: ChangeActor? = nil
  ) throws -> String {
    let data = try encoded(definition).json()
    _ = try mutation(
      "space", token: token,
      request: .object([
        "id": .string(id), "title": .string(title), "definition": .string(data),
        "expectedVersion": expectedVersion.map { .number(Double($0)) } ?? .null,
      ]), actor: actor
    ) {
      let current = try spaceIfPresent(id)
      try checkSpaceBase(current, expectedVersion: expectedVersion)
      if let current { try preservePinnedBindings(current.definition, next: definition) }
      try refuseAuthoredEvaluationSnapshots(definition, current: current)
      try publishSpace(id: id, title: title, definition: definition, current: current)
      return .string(id)
    }
    return id
  }
  /// `saved` is the layout this replaces. A live table or function can change under a view that
  /// was saved earlier, and that must not block edits around it, so only new or changed views
  /// answer for their arguments and columns.
  func validateSpaceDefinition(_ definition: SpaceDefinition, replacing saved: [Component] = [])
    throws
  {
    func flatten(_ components: [Component]) -> [Component] {
      components.flatMap { [$0] + flatten($0.children ?? []) }
    }
    let unchanged = flatten(saved)
    try require(
      definition.version == 1 && definition.components.count <= 16, "view",
      "Unsupported view version or too many components.")
    try require(
      Set(definition.components.map(\.id)).count == definition.components.count, "view",
      "Component identifiers must be unique.")
    if let captured = definition.pinnedAt {
      try require(
        ISO8601DateFormatter().date(from: captured) != nil, "view", "Invalid pinned time.")
    }
    var componentCount = 0
    var ids = Set<String>()
    func validate(_ c: Component, depth: Int) throws {
      componentCount += 1
      try require(
        componentCount <= 16 && depth <= 3 && ids.insert(c.id).inserted, "view",
        "Use at most 16 uniquely named components and three levels.")
      try require(
        Set([
          "table", "chart", "metric", "comparison", "document", "asset", "search", "text", "form",
          "calculation", "query",
        ])
        .union(SpaceDefinition.sectionTypes).contains(c.type), "view",
        "Unknown native component: \(c.type)")
      try require(
        !c.id.isEmpty && c.id.utf8.count <= 256 && c.title.utf8.count <= 500, "view",
        "Use bounded component IDs and labels.")
      if ["calculation", "query"].contains(c.type) {
        try validateDefinitionComponent(
          c, pinned: definition.pinnedAt != nil, checkArguments: !unchanged.contains(c))
      } else if c.type == "form" {
        try require(
          definition.pinnedAt == nil && c.datasetID == nil && c.itemID == nil
            && c.snapshot == nil && c.searchSnapshot == nil && c.arguments == nil
            && c.evaluationSnapshot == nil, "view",
          "Forms are explicit live actions and cannot be frozen as results.")
        guard let binding = c.definitionBinding else {
          throw SevraError("view", "Choose a form definition.")
        }
        let target = try resolveDefinition(DefinitionBinding(binding))
        try require(target.kind == "form", "view", "Bind a form component to a form definition.")
      } else {
        try require(
          c.definitionBinding == nil && c.arguments == nil && c.evaluationSnapshot == nil, "view",
          "Only qualified forms and computation views take definition bindings.")
      }
      if SpaceDefinition.sectionTypes.contains(c.type) {
        try require(
          definition.pinnedAt == nil && c.datasetID == nil && c.itemID == nil
            && c.snapshot == nil && c.searchSnapshot == nil, "view",
          "Workbook sections are live host views and cannot carry snapshot or data bindings.")
      }
      if ["table", "chart", "metric"].contains(c.type) {
        guard let id = c.datasetID else {
          throw SevraError("view", "Component \(c.id) (\(c.type)) requires its own datasetID.")
        }
        let table = try dataset(id)
        // A snapshot answers for the columns it saved, whatever the table has become.
        let columns =
          definition.pinnedAt == nil ? table.columns : c.snapshot?.columns ?? table.columns
        if ["chart", "metric"].contains(c.type), !unchanged.contains(c) {
          try require(
            columns.contains { $0.id == c.y }, "view",
            "Set y to an existing dataset column ID, not a layout position. Inspect datasets for column IDs."
          )
        }
        if c.type == "chart", !unchanged.contains(c) {
          try require(
            columns.contains { $0.id == c.x }
              && ["bar", "line"].contains(c.chartStyle ?? "bar"), "view",
            "Set x to an existing dataset column ID, not a layout position; use bar or line style.")
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
      if c.type == "search" {
        _ = try Self.searchTerms(c.query ?? "")
      }
      if definition.pinnedAt != nil {
        if ["table", "chart", "metric"].contains(c.type) {
          try require(c.snapshot != nil, "view", "A pinned table needs saved values.")
        }
        if ["document", "asset"].contains(c.type), let id = c.itemID {
          try require(try item(id).id == id, "view", "A pinned item needs an exact version.")
        }
        if c.type == "search" {
          try require(c.searchSnapshot != nil, "view", "A pinned search needs saved results.")
        }
      }
      if let snapshot = c.searchSnapshot {
        try require(
          c.type == "search" && snapshot.query == (c.query ?? "")
            && snapshot.hits.count <= 8 && snapshot.incomplete >= 0 && snapshot.revision >= 0
            && Set(snapshot.hits.map(\.id)).count == snapshot.hits.count
            && Set(snapshot.hits.map(\.itemID)).count == snapshot.hits.count
            && ISO8601DateFormatter().date(from: snapshot.captured) != nil,
          "view", "Invalid pinned search result.")
        for hit in snapshot.hits {
          try require(
            try item(hit.itemID).id == hit.itemID, "view",
            "A pinned search result needs exact item versions.")
        }
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
  public func messages(
    conversation: String = "main", limit: Int = 100, beforeMessage: String? = nil
  ) throws -> [Message] {
    try synchronized {
      var boundary: Value = .null
      if let beforeMessage {
        boundary = try db.scalar(
          "SELECT rowid FROM messages WHERE id=? AND conversation_id=?",
          [.string(beforeMessage), .string(conversation)])
        try require(boundary != .null, "history_scope", "The message is not in this conversation.")
      }
      return try db.execute(
        "SELECT * FROM (SELECT rowid,* FROM messages WHERE conversation_id=? AND (? IS NULL OR rowid<?) ORDER BY rowid DESC LIMIT ?) ORDER BY rowid",
        [.string(conversation), boundary, boundary, .number(Double(min(max(limit, 1), 500)))]
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
          == 1, "not_found", "The thread needs an existing conversation message.")
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
      "From a thread:\n\n" + message["body"]!.text
        + "\n\n[Open original exchange](sevra://conversation/\(source)?message=\(id))",
      role: "user", conversation: "main")
  }

  /// Share only the user's selected text, retaining an exact origin. This does
  /// not accept business records, expand retrieval scope, or enqueue an AI turn.
  @discardableResult public func shareSummary(message id: String, text: String) throws -> String {
    let summary = text.trimmingCharacters(in: .whitespacesAndNewlines)
    try require(
      !summary.isEmpty && summary.utf8.count <= 64_000, "summary",
      "Enter a summary of at most 64,000 bytes.")
    return try synchronized {
      guard let message = try db.execute("SELECT * FROM messages WHERE id=?", [.string(id)]).first
      else { throw SevraError("message", "The original exchange is missing.") }
      let source = message["conversation_id"]!.text
      try require(source != "main", "conversation", "This exchange is already in the conversation.")
      try require(
        message["state"]?.text == "complete"
          && ["user", "assistant"].contains(message["role"]?.text ?? ""),
        "summary", "Choose a completed exchange to share.")
      return try addMessage(
        "Shared summary from a thread:\n\n" + summary
          + "\n\n[Open original exchange](sevra://conversation/\(source)?message=\(id))",
        role: "user", conversation: "main",
        payload: .object([
          "kind": .string("shared_summary"), "conversationID": .string(source),
          "messageID": .string(id), "referenceOnly": .bool(true),
        ]))
    }
  }
}
