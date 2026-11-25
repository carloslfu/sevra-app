import Foundation

/// Host-owned sections participate in the same layout as bound business views.
extension SpaceDefinition {
  public static var defaultHome: Self {
    .init(components: [
      .init(id: "attention", type: "attention", title: "Needs attention"),
      .init(id: "continue", type: "continue", title: "Continue working"),
      .init(id: "shortcuts", type: "shortcuts", title: "Pinned spaces"),
    ])
  }
  public static let contentTypes: Set<String> = [
    "table", "chart", "metric", "comparison", "document", "asset", "search", "text",
    "form", "calculation", "query", "app", "image", "visual", "button",
  ]
  /// The components a size changes: how tall a table or chart is, how large a number or text
  /// is drawn, and how large a button is. A visual takes it only when it is a chart. Medium
  /// when absent.
  public static let sizedTypes = ["table", "chart", "visual", "metric", "text", "button"]
  public static let sizes = ["small", "medium", "large"]
  /// The order a model writes a component's fields in, each only when its type uses it. It is
  /// the grammar's order for the component schema, and the agent checks hold the two equal.
  public static let componentFieldOrder = [
    "id", "type", "title", "definitionBinding", "datasetID", "aggregation", "arguments",
    "chartStyle", "children", "itemID", "presentationID", "query", "spaceID", "text", "unit",
    "viewID", "viewVersion", "visual", "x", "y", "size",
  ]
  public static let sectionTypes: Set<String> = [
    "input", "reviews", "shortcuts", "tables", "intake", "recent", "attention", "continue",
  ]
  public func containsComponent(_ type: String) -> Bool {
    func contains(_ components: [Component]) -> Bool {
      components.contains { $0.type == type || contains($0.children ?? []) }
    }
    return contains(components)
  }
  /// Pending work remains reachable even after its section was removed.
  public func homeComponents(pendingReview: Bool, pendingAttention: Bool = false) -> [Component] {
    let needsAttention = pendingAttention && !containsComponent("attention")
    let needsReviews =
      pendingReview && !containsComponent("attention") && !containsComponent("reviews")
    guard needsAttention || needsReviews else { return components }
    func ids(_ components: [Component]) -> [String] {
      components.flatMap { [$0.id] + ids($0.children ?? []) }
    }
    let occupied = Set(ids(components))
    var id = "home-attention"
    while occupied.contains(id) { id += "-" }
    return [
      Component(
        id: id, type: needsAttention ? "attention" : "reviews",
        title: needsAttention ? "Needs attention" : "Drafts to review")
    ] + components
  }

}

public struct SpaceEdit: Codable, Equatable, Sendable {
  public var operation: String
  public var componentID: String?
  public var beforeID: String?
  public var at: String?
  public var component: Component?
  public var title: String?
  public var text: String?
  public init(
    operation: String, componentID: String? = nil, beforeID: String? = nil, at: String? = nil,
    component: Component? = nil, title: String? = nil, text: String? = nil
  ) {
    self.operation = operation
    self.componentID = componentID
    self.beforeID = beforeID
    self.at = at
    self.component = component
    self.title = title
    self.text = text
  }
}

public struct SpaceRevision: Codable, Sendable, Identifiable {
  public var id: Int { version }
  public let version: Int
  public let title: String
  public let definition: SpaceDefinition
  public let recorded: String
}

extension Workbook {
  func decodedSpaceDefinition(_ row: [String: Value]) throws -> SpaceDefinition {
    // Components hold components, so a copied workbook can nest them past the stack.
    try Value.requireDepth(row["definition"]!.text)
    let saved = try JSONDecoder().decode(
      SpaceDefinition.self, from: Data(row["definition"]!.text.utf8))
    do { try saved.validateStructure() } catch {
      throw SevraError("integrity", "The saved layout has invalid component identities or bounds.")
    }
    // The declared initial Home has no authored layout. Its stable default is a
    // projection; an explicitly emptied later version stays empty.
    if row["id"]?.text == "home", row["version"]?.int == 1, saved.components.isEmpty {
      return .defaultHome
    }
    return saved
  }
  func spaceIfPresent(_ id: String) throws -> Space? {
    guard let row = try db.execute("SELECT * FROM spaces WHERE id=?", [.string(id)]).first
    else { return nil }
    guard let version = row["version"]?.int, (1...1_000_000_000).contains(version) else {
      throw SevraError("integrity", "Invalid space version.")
    }
    return .init(
      id: id, title: row["title"]!.text, definition: try decodedSpaceDefinition(row),
      version: version)
  }
  public func space(_ id: String) throws -> Space {
    try synchronized {
      guard let space = try spaceIfPresent(id) else {
        throw SevraError("view", "Space not found.")
      }
      return space
    }
  }
  func checkSpaceBase(_ current: Space?, expectedVersion: Int?) throws {
    try require(
      current.map { $0.version == expectedVersion } ?? (expectedVersion == nil),
      "space_conflict",
      "This space changed or needs an exact base version. Read it again before editing; no layout was replaced."
    )
  }
  func preservePinnedBindings(_ previous: SpaceDefinition, next: SpaceDefinition) throws {
    try require(
      previous.pinnedAt == next.pinnedAt, "space_snapshot",
      "Keep this space's live or snapshot mode. Create a separate copy to change it.")
    guard previous.pinnedAt != nil else { return }
    func flatten(_ components: [Component]) -> [Component] {
      components.flatMap { [$0] + flatten($0.children ?? []) }
    }
    let prior = Dictionary(uniqueKeysWithValues: flatten(previous.components).map { ($0.id, $0) })
    for component in flatten(next.components) {
      guard let old = prior[component.id] else {
        throw SevraError("space_snapshot", "A snapshot can rearrange or remove saved components.")
      }
      var compared = component
      compared.title = old.title
      compared.text = old.text
      compared.children = old.children
      try require(
        compared == old, "space_snapshot", "A snapshot binding or saved value cannot become live.")
    }
  }
  func publishSpace(id: String, title: String, definition: SpaceDefinition, current: Space?) throws
  {
    try require(
      !id.isEmpty && id.utf8.count <= 256
        && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && title.utf8.count <= 500, "view", "Use a space ID and a title of up to 500 bytes.")
    try refuseAuthoredEvaluationSnapshots(definition, current: current)
    try validateSpaceDefinition(definition, replacing: current?.definition.components ?? [])
    if let current {
      try require(current.version < 1_000_000_000, "view_limit", "Space version limit reached.")
      let saved = try db.execute(
        "SELECT * FROM space_versions WHERE id=? AND version=?",
        [
          .string(id), .number(Double(current.version)),
        ]
      ).first
      if let saved {
        try require(
          saved["title"]?.text == current.title
            && decodedSpaceDefinition(saved) == current.definition,
          "integrity", "The current layout differs from its retained version.")
      } else {
        try require(
          id == "home" && current.version == 1, "integrity",
          "The current layout has no retained version. Preserve this workbook for recovery.")
      }
      // Retain the declared initial version too. All later saves already have it.
      try db.execute(
        "INSERT OR IGNORE INTO space_versions VALUES(?,?,?,?,?)",
        [
          .string(id), .number(Double(current.version)), .string(current.title),
          .string(try encoded(current.definition).json()), .string(""),
        ])
    }
    let version = (current?.version ?? 0) + 1
    let now = timestamp()
    let data = try encoded(definition).json()
    try db.execute(
      "INSERT INTO spaces VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,definition=excluded.definition,version=excluded.version,updated=excluded.updated",
      [.string(id), .string(title), .string(data), .number(Double(version)), .string(now)])
    try db.execute(
      "INSERT INTO space_versions VALUES(?,?,?,?,?)",
      [.string(id), .number(Double(version)), .string(title), .string(data), .string(now)])
  }
  public func editSpace(
    _ id: String, expectedVersion: Int, edits: [SpaceEdit], token: String = identifier(),
    actor: ChangeActor? = nil, commitGuard: (() throws -> Void)? = nil
  ) throws -> Space {
    try require((1...64).contains(edits.count), "view", "Use one to 64 layout edits.")
    let result = try mutation(
      "edit_space", token: token,
      request: .object([
        "id": .string(id), "expectedVersion": .number(Double(expectedVersion)),
        "edits": try encoded(edits),
      ]), actor: actor, commitGuard: commitGuard
    ) {
      let current = try space(id)
      try checkSpaceBase(current, expectedVersion: expectedVersion)
      var definition = current.definition
      var title = current.title
      for edit in edits {
        try validateSpaceEdit(edit)
        if edit.operation == "reset" {
          try require(id == "home", "view", "Reset is only available for Home.")
          definition = .defaultHome
          title = "Home"
        } else if edit.operation == "rename" {
          try require(edit.title != nil, "view", "A rename needs a title.")
          title = edit.title!
        } else if edit.operation == "insert" {
          guard let component = edit.component else {
            throw SevraError("view", "An insertion needs a component.")
          }
          let index = try insertionIndex(edit, in: definition.components)
          definition.components.insert(component, at: index)
        } else {
          // A replacement keeps the component's ID, so the component names its own target.
          guard
            let identity = edit.componentID
              ?? (edit.operation == "replace" ? edit.component?.id : nil),
            try alterComponent(identity, in: &definition.components, edit: edit)
          else { throw SevraError("view", "The selected component no longer exists.") }
        }
      }
      try preservePinnedBindings(current.definition, next: definition)
      try publishSpace(id: id, title: title, definition: definition, current: current)
      return try encoded(space(id))
    }
    return try JSONDecoder().decode(Space.self, from: Data(result.json().utf8))
  }
  /// The order a model's grammar writes an edit's fields in. A model that writes the component
  /// first cannot go back for the position, so an error names this order.
  package static let editFieldOrder = [
    "operation", "componentID", "at", "beforeID", "component", "text", "title",
  ]
  private func validateSpaceEdit(_ edit: SpaceEdit) throws {
    // After the component the grammar offers only text and title, and a model reaching for
    // a field it already passed writes one of them empty. An empty one says nothing.
    let emptyTitle = edit.title == "" && !["rename", "title"].contains(edit.operation)
    let emptyText = edit.text == "" && edit.operation != "text"
    let fields: Set<String> = Set(
      [
        edit.componentID == nil ? nil : "componentID", edit.beforeID == nil ? nil : "beforeID",
        edit.at == nil ? nil : "at", edit.component == nil ? nil : "component",
        edit.title == nil || emptyTitle ? nil : "title",
        edit.text == nil || emptyText ? nil : "text",
      ].compactMap { $0 })
    let allowed: Set<String>
    switch edit.operation {
    case "reset": allowed = []
    case "rename": allowed = ["title"]
    case "insert": allowed = ["component", "beforeID", "at"]
    case "remove": allowed = ["componentID"]
    case "move": allowed = ["componentID", "beforeID", "at"]
    case "title": allowed = ["componentID", "title"]
    case "text": allowed = ["componentID", "text"]
    case "replace": allowed = ["componentID", "component"]
    default: throw SevraError("view", "Unknown layout edit.")
    }
    try require(
      fields.isSubset(of: allowed), "view",
      "Unexpected " + edit.operation + " fields: "
        + fields.subtracting(allowed).sorted().joined(separator: ", ")
        + ". Allowed fields: " + allowed.sorted().joined(separator: ", ")
        + ". Write an edit's fields in this order: "
        + Self.editFieldOrder.filter { $0 == "operation" || allowed.contains($0) }
        .joined(separator: ", ") + ".")
    // An insertion with no position goes last. A move has to say where.
    let unplaced = edit.beforeID == nil && edit.at == nil
    if edit.operation == "move" || (edit.operation == "insert" && !unplaced) {
      try require(
        (edit.beforeID != nil && edit.at == nil)
          || (edit.beforeID == nil && ["first", "last"].contains(edit.at ?? "")),
        "view", "Choose at:first, at:last, or beforeID for each move or insertion.")
    }
  }
  private func insertionIndex(_ edit: SpaceEdit, in components: [Component]) throws -> Int {
    if edit.at == "first" { return 0 }
    if edit.at == "last" { return components.count }
    if edit.operation == "insert", edit.beforeID == nil { return components.count }
    guard let before = edit.beforeID else {
      throw SevraError("view", "Choose an explicit layout position.")
    }
    guard let index = components.firstIndex(where: { $0.id == before }) else {
      throw SevraError("view", "Move before a component in the same group.")
    }
    return index
  }
  private func alterComponent(_ id: String, in components: inout [Component], edit: SpaceEdit)
    throws -> Bool
  {
    if let index = components.firstIndex(where: { $0.id == id }) {
      switch edit.operation {
      case "remove": components.remove(at: index)
      case "move":
        if edit.beforeID == id { return true }
        let component = components.remove(at: index)
        let destination = try insertionIndex(edit, in: components)
        components.insert(component, at: destination)
      case "title":
        guard let title = edit.title else { throw SevraError("view", "A label needs text.") }
        components[index].title = title
      case "text":
        try require(
          components[index].type == "text" && edit.text != nil, "view",
          "Only a text component accepts text edits.")
        components[index].text = edit.text
      case "replace":
        guard let component = edit.component, component.id == id else {
          throw SevraError("view", "A replacement preserves the selected component ID.")
        }
        components[index] = component
      default: throw SevraError("view", "Unknown layout edit.")
      }
      return true
    }
    for index in components.indices where components[index].children != nil {
      if try alterComponent(id, in: &components[index].children!, edit: edit) { return true }
    }
    return false
  }
  public func spaceHistory(_ id: String, before: Int? = nil, limit: Int = 20) throws
    -> [SpaceRevision]
  {
    try require((1...50).contains(limit), "limit", "Inspect one to 50 space versions at a time.")
    return try synchronized {
      _ = try space(id)
      let rows = try db.execute(
        "SELECT * FROM space_versions WHERE id=? AND version<? ORDER BY version DESC LIMIT ?",
        [.string(id), .number(Double(before ?? Int.max)), .number(Double(limit))])
      if rows.isEmpty, id == "home", try space(id).version == 1, (before ?? 2) > 1 {
        return [.init(version: 1, title: "Home", definition: .defaultHome, recorded: "")]
      }
      return try rows.map {
        guard let version = $0["version"]?.int, (1...1_000_000_000).contains(version) else {
          throw SevraError("integrity", "Invalid saved space version.")
        }
        return .init(
          version: version, title: $0["title"]!.text,
          definition: try decodedSpaceDefinition($0), recorded: $0["updated"]!.text)
      }
    }
  }
  public func restoreSpace(
    _ id: String, version: Int, expectedVersion: Int, token: String = identifier(),
    actor: ChangeActor? = nil
  ) throws -> Space {
    try require(version > 0 && version < Int.max, "view", "Choose a valid saved version.")
    let result = try mutation(
      "restore_space", token: token,
      request: .object([
        "id": .string(id), "version": .number(Double(version)),
        "expectedVersion": .number(Double(expectedVersion)),
      ]), actor: actor
    ) {
      let current = try space(id)
      try checkSpaceBase(current, expectedVersion: expectedVersion)
      guard let selected = try spaceHistory(id, before: version + 1, limit: 1).first,
        selected.version == version
      else { throw SevraError("view", "The saved space version is unavailable.") }
      try publishSpace(
        id: id, title: selected.title, definition: selected.definition, current: current)
      return try encoded(space(id))
    }
    return try JSONDecoder().decode(Space.self, from: Data(result.json().utf8))
  }
  func verifySpaces() throws {
    try require(
      try db.scalar(
        "SELECT EXISTS(SELECT 1 FROM space_versions v LEFT JOIN spaces s ON s.id=v.id WHERE s.id IS NULL)"
      ).int == 0,
      "integrity", "Saved layout history has no current space.")
    for row in try db.execute("SELECT * FROM spaces") {
      let id = row["id"]!.text
      let current = try space(id)
      let history = try db.execute(
        "SELECT count(*) AS total,min(version) AS first,max(version) AS last FROM space_versions WHERE id=?",
        [.string(id)])[0]
      if id == "home", current.version == 1, history["total"]?.int == 0 {
        try require(
          current.title == "Home" && current.definition == .defaultHome, "integrity",
          "The initial Home layout was changed without history.")
        continue
      }
      try require(
        history["total"]?.int == current.version && history["first"]?.int == 1
          && history["last"]?.int == current.version,
        "integrity", "Layout history is missing a saved version.")
      guard
        let saved = try db.execute(
          "SELECT * FROM space_versions WHERE id=? AND version=?",
          [.string(id), .number(Double(current.version))]
        ).first
      else {
        throw SevraError("integrity", "The current layout version is missing.")
      }
      try require(
        saved["title"] == row["title"] && saved["definition"] == row["definition"],
        "integrity", "The current layout differs from its retained version.")
    }
  }

}
