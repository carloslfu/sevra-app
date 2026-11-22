import Foundation

public struct VisualOrigin: Codable, Equatable, Sendable {
  public let messageID: String
  public let index: Int
  public let conversation: String

  public init(messageID: String, index: Int, conversation: String) {
    self.messageID = messageID
    self.index = index
    self.conversation = conversation
  }
}

public struct Component: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var type: String
  public var title: String
  public var datasetID: String?
  public var itemID: String?
  public var spaceID: String?
  public var visual: VisualDefinition?
  public var viewID: String?
  public var viewVersion: Int?
  public var presentationID: String?
  public var visualOrigin: VisualOrigin?
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
    arguments: Value? = nil, evaluationSnapshot: DefinitionResultSnapshot? = nil,
    spaceID: String? = nil, visual: VisualDefinition? = nil, viewID: String? = nil,
    viewVersion: Int? = nil, presentationID: String? = nil, visualOrigin: VisualOrigin? = nil
  ) {
    self.id = id
    self.type = type
    self.title = title
    self.datasetID = datasetID
    self.itemID = itemID
    self.spaceID = spaceID
    self.visual = visual
    self.viewID = viewID
    self.viewVersion = viewVersion
    self.presentationID = presentationID
    self.visualOrigin = visualOrigin
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
  public var app: NativeAppPackage?
  /// The actions this app version declared when its isolated check ran it, as
  /// `[{id, title, inputs}]`. They are listed without the app running; running one still needs
  /// the app enabled on this Mac.
  public var actions: Value?
  public init(components: [Component], pinnedAt: String? = nil) {
    self.components = components
    self.pinnedAt = pinnedAt
  }
  /// Check persisted identities before renderers or editors build keyed collections.
  /// Live bindings can become unavailable without making the layout unreadable.
  func validateStructure() throws {
    try require(version == 1, "view", "Unsupported view version.")
    var ids = Set<String>()
    func visit(_ component: Component, depth: Int) throws {
      try require(
        depth <= 3 && ids.count < 16 && ids.insert(component.id).inserted,
        "view", "Use at most 16 uniquely named components and three levels.")
      try require(
        !component.id.isEmpty && component.id.utf8.count <= 256
          && component.title.utf8.count <= 500,
        "view", "Use bounded component IDs and labels.")
      if let origin = component.visualOrigin {
        try require(
          (component.type == "visual" || component.type == "image")
            && (0...1).contains(origin.index) && !origin.messageID.isEmpty
            && !origin.conversation.isEmpty
            && origin.messageID.utf8.count <= 128 && origin.conversation.utf8.count <= 128,
          "visual", "Use an exact captured answer origin.")
      }
      for child in component.children ?? [] { try visit(child, depth: depth + 1) }
    }
    for component in components { try visit(component, depth: 1) }
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
          guard let version = row["version"]?.int, (1...1_000_000_000).contains(version) else {
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
    try definition.validateStructure()
    func flatten(_ components: [Component]) -> [Component] {
      components.flatMap { [$0] + flatten($0.children ?? []) }
    }
    if let app = definition.app {
      try require(
        definition.components.isEmpty && definition.pinnedAt == nil, "app_package",
        "An app space owns its native interface and cannot be pinned.")
      try validateNativeApp(app)
    }
    let unchanged = flatten(saved)
    if let captured = definition.pinnedAt {
      try require(
        ISO8601DateFormatter().date(from: captured) != nil, "view", "Invalid pinned time.")
    }
    func validate(_ c: Component, depth: Int) throws {
      try require(
        SpaceDefinition.contentTypes
          .union(SpaceDefinition.sectionTypes).contains(c.type), "view",
        "Unknown native component: \(c.type)")
      if c.type == "image" {
        guard let visual = c.visual, let image = visual.image else {
          throw SevraError("visual_image", "Choose an included image for this component.")
        }
        try require(
          c.itemID == nil && c.datasetID == nil && c.snapshot == nil && c.searchSnapshot == nil,
          "visual_image", "Use the image’s exact source binding.")
        try visual.validate()
        _ = try validateImageReference(image.reference)
      } else if c.type == "visual" {
        guard let visual = c.visual, visual.kind != .image else {
          throw SevraError("visual", "Choose a typed visual definition.")
        }
        try require(
          definition.pinnedAt == nil && c.itemID == nil && c.datasetID == nil
            && c.snapshot == nil && c.searchSnapshot == nil, "visual",
          "Use the visual’s typed queries in a live layout.")
        try visual.validate()
        if !unchanged.contains(c) {
          if let text = visual.text { try validateVisualTextSources(text) }
          let queries = visual.queries
          for query in queries { _ = try compileDatasetQuery(DatasetQuery(query)) }
          for reference in visual.work?.thumbnailAssets?.values.map({ $0 }) ?? [] {
            _ = try validateImageReference(reference)
          }
        }
      } else {
        try require(
          c.visual == nil, "visual", "This kind of component does not accept a visual definition.")
      }
      try require(
        (c.viewID == nil && c.viewVersion == nil && c.presentationID == nil)
          || (c.type == "app" && c.viewID != nil && c.viewVersion != nil),
        "visual", "A declared view requires an exact app version.")

      if c.type == "app" {
        try require(
          definition.pinnedAt == nil && c.datasetID == nil && c.itemID == nil
            && c.snapshot == nil && c.searchSnapshot == nil && c.evaluationSnapshot == nil
            && c.arguments == nil && c.definitionBinding == nil,
          "view", "A live app view binds only to its app space and cannot be a snapshot.")
        guard let id = c.spaceID, !id.isEmpty, id.utf8.count <= 256 else {
          throw SevraError("view", "Choose the exact app space ID from spaces.")
        }
        // Existing unavailable bindings remain removable and restorable.
        if !unchanged.contains(c) {
          let app = try space(id)
          guard let package = app.definition.app else {
            throw SevraError("view", "Choose a programmable app space.")
          }
          if let view = c.viewID {
            try require(
              package.views?[view] != nil && c.viewVersion == app.version, "view",
              "Choose a declared app view at its current app version.")
            if let preset = c.presentationID {
              let current = try item(preset)
              let state = try readVisualPreset(
                current, spaceID: app.id,
                version: app.version, digest: package.digest, view: view)
              try require(
                current.logicalID == preset && state.archived != true, "visual_preset",
                "Choose an active saved presentation ID.")
            }
          }
        }
      } else {
        try require(c.spaceID == nil, "view", "Only a live app component uses spaceID.")
      }
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
          throw SevraError(
            "view",
            "Component \(c.id) (\(c.type)) needs datasetID: the id of the existing table it draws from. It can be the same table another component shows. Do not create a table for it."
          )
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
    _ body: String, role: String, conversation: String, state: String = "complete",
    payload: Value = .null
  ) throws -> String {
    try require(body.utf8.count <= 128_000, "message_limit", "Message is too long.")
    let metadata = payload == .null ? nil : try payload.json()
    try require(
      (metadata?.utf8.count ?? 0) <= 128_000, "message_limit", "Message receipt is too long.")
    let id = identifier()
    _ = try mutation("message", request: .string(id)) {
      try requireLiveChat(conversation)
      if role == "user" { try nameNewChat(conversation, from: body) }
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
    conversation: String, limit: Int = 100, beforeMessage: String? = nil
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
}
