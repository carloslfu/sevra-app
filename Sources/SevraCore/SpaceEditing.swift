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
  /// The component types each of these fields belongs to. A field on another type was once
  /// kept and ignored, so a table titled "Overdue invoices" with a query showed every row.
  static let fieldTypes: [(field: String, types: [String])] = [
    ("datasetID", ["table", "chart", "metric"]),
    ("query", ["table", "chart", "metric", "search"]),
    ("aggregation", ["metric"]), ("chartStyle", ["chart"]), ("itemID", ["document", "asset"]),
    ("text", ["text"]), ("unit", ["chart", "metric"]), ("x", ["chart"]), ("y", ["chart", "metric"]),
  ]
  /// Whether a field the type does not use can be left out without changing what the component
  /// shows. A table's x and y, a metric's chartStyle or a size on a document change nothing, so
  /// one of them on a component that is otherwise right should not cost the model a whole save:
  /// a retry tends to rewrite the view and lose a field that was right, such as a button's
  /// binding. A chart's aggregation other than SUM would mean another number than the chart
  /// draws, and datasetID, query, itemID and text say what the component should show, so their
  /// loss would hide intent and they are still refused.
  static func harmless(_ field: String, on c: Component) -> Bool {
    switch field {
    case "x", "y", "chartStyle", "unit": return true
    case "aggregation": return c.type != "chart" || c.aggregation?.uppercased() == "SUM"
    default: return false
    }
  }
  /// Whether a component takes a size: see `sizedTypes`.
  static func takesSize(_ c: Component) -> Bool {
    sizedTypes.contains(c.type) && (c.type != "visual" || c.visual?.chart != nil)
  }
  /// The components with fields their type does not use, and that change nothing, left out,
  /// with one short notice for each component that lost some, such as "Left out x, y on table1:
  /// a table does not use them." Children are checked too. Every other unused field stays, so
  /// the save refuses it and says why.
  public static func leavingOutUnusedFields(_ components: [Component]) -> (
    components: [Component], notices: [String]
  ) {
    var notices: [String] = []
    func clean(_ c: Component) -> Component {
      var c = c
      var dropped: [String] = []
      for (field, types) in fieldTypes where !types.contains(c.type) && harmless(field, on: c) {
        let present: Bool
        switch field {
        case "x": present = c.x != nil; c.x = nil
        case "y": present = c.y != nil; c.y = nil
        case "chartStyle": present = c.chartStyle != nil; c.chartStyle = nil
        case "unit": present = c.unit != nil; c.unit = nil
        default: present = c.aggregation != nil; c.aggregation = nil
        }
        if present { dropped.append(field) }
      }
      let sizeDropped = c.size != nil && !takesSize(c)
      if sizeDropped { c.size = nil }
      if !dropped.isEmpty {
        let article = "aeiou".contains(c.type.first ?? "x") ? "an " : "a "
        notices.append(
          "Left out " + dropped.joined(separator: ", ") + " on " + c.id + ": " + article + c.type
            + (c.type == "chart" && dropped == ["aggregation"]
              ? " adds up y for each x itself."
              : " does not use " + (dropped.count == 1 ? "it." : "them.")))
      }
      if sizeDropped {
        let article = "aeiou".contains(c.type.first ?? "x") ? "an " : "a "
        notices.append(
          "Left out size on " + c.id + ": " + article
            + (c.type == "visual" ? "visual that is not a chart" : c.type) + " has no size.")
      }
      c.children = c.children.map { $0.map(clean) }
      return c
    }
    let cleaned = components.map(clean)
    return (cleaned, notices)
  }
  /// Refuses a field the component's type does not use, saying what does use it. The types
  /// with fields of their own, such as apps, buttons, forms and visuals, check theirs.
  static func refuseUnusedFields(_ c: Component) throws {
    func present(_ field: String) -> Bool {
      switch field {
      case "datasetID": return c.datasetID != nil
      case "query": return c.query != nil
      case "aggregation": return c.aggregation != nil
      case "chartStyle": return c.chartStyle != nil
      case "itemID": return c.itemID != nil
      case "text": return c.text != nil
      case "unit": return c.unit != nil
      case "x": return c.x != nil
      default: return c.y != nil
      }
    }
    // An image binds its own source, and its check says so.
    let stray = fieldTypes.filter { present($0.field) && !$0.types.contains(c.type) }
      .filter { !(c.type == "image" && $0.field == "itemID") }
    guard !stray.isEmpty else { return }
    func list(_ types: [String]) -> String {
      types.count == 1
        ? "a " + types[0] : "a " + types.dropLast().joined(separator: ", ") + " or " + types.last!
    }
    throw SevraError(
      "view",
      "\(c.id) is a \(c.type), which does not use "
        + stray.map(\.field).joined(separator: ", ") + ". "
        + stray.map { $0.field + " belongs to " + list($0.types) }.joined(separator: "; ")
        + ". Leave "
        + (stray.count == 1 ? "it" : "them") + " out, or choose the type that uses "
        + (stray.count == 1 ? "it" : "them") + "."
        + (c.type == "chart" && stray.contains { $0.field == "aggregation" }
          ? " A chart adds up y for each x. For another number for each x, give it a query that works it out, such as SELECT region, avg(revenue) AS revenue FROM sales GROUP BY region."
          : "")
        + (stray.contains { $0.field == "query" }
          ? " To show only some rows, use a table, chart or metric with query: one SELECT."
          : ""))
  }
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
  /// The component fields a caller wrote, when it may have left some out, as a model does. A
  /// replace that keeps the component's type then keeps the saved value of every field not
  /// named here, and a field named with null is cleared. Without it, or when the type
  /// changes, the component given is the whole new component.
  public var fields: [String]?
  public init(
    operation: String, componentID: String? = nil, beforeID: String? = nil, at: String? = nil,
    component: Component? = nil, title: String? = nil, text: String? = nil,
    fields: [String]? = nil
  ) {
    self.operation = operation
    self.componentID = componentID
    self.beforeID = beforeID
    self.at = at
    self.component = component
    self.title = title
    self.text = text
    self.fields = fields
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
      for var edit in edits {
        try validateSpaceEdit(edit)
        if current.definition.pinnedAt == nil, let component = edit.component {
          edit.component = SpaceDefinition.leavingOutUnusedFields([component]).components[0]
        }
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
          // A model changing a component often inserts it again under the same id.
          func ids(_ components: [Component]) -> [String] {
            components.flatMap { [$0.id] + ids($0.children ?? []) }
          }
          try require(
            !ids(definition.components).contains(component.id), "view",
            "This view already has a component with id \(component.id). To change that component, replace it: {operation: \"replace\", componentID: \"\(component.id)\", component}, with the same id, type and title and the fields that change. To add another one, give it a new id.")
          if let before = edit.beforeID, edit.at == nil,
            !definition.components.contains(where: { $0.id == before })
          {
            try insertInComparison(component, before: before, in: &definition.components)
          } else {
            let index = try insertionIndex(edit, in: definition.components)
            definition.components.insert(component, at: index)
          }
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
    // componentID names a component already on the view, so an insert, which adds a new
    // one, places it by at or beforeID instead.
    if edit.operation == "insert", fields.contains("componentID") {
      throw SevraError(
        "view",
        "An insert has no componentID: it adds a new component, placed with at: \"first\" or \"last\", or with beforeID: the id of the component it goes before. Leave both out to add it last. componentID is for replace, remove, move, title and text. Write an insert's fields in this order: operation, at or beforeID, component, and keep every field of the component."
      )
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
  /// An insertion before a component inside a comparison joins that comparison's columns
  /// when it has room. A comparison holds two or three.
  private func insertInComparison(
    _ component: Component, before: String, in components: inout [Component]
  ) throws {
    guard try insertNested(component, before: before, in: &components) else {
      throw SevraError(
        "view",
        "No component is named \(before). Use beforeID with the id of a component in the view, or at first or last."
      )
    }
  }
  private func insertNested(
    _ component: Component, before: String, in components: inout [Component]
  ) throws -> Bool {
    for index in components.indices {
      guard var children = components[index].children else { continue }
      if let at = children.firstIndex(where: { $0.id == before }) {
        let group = components[index].id
        try require(
          children.count < 3, "view",
          "\(before) is inside comparison \(group), which already has three columns. Place the new component before \(group) or with at first or last, or replace \(group) to change its columns."
        )
        children.insert(component, at: at)
      } else if try !insertNested(component, before: before, in: &children) {
        continue
      }
      components[index].children = children
      return true
    }
    return false
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
        components[index] = try Self.merged(components[index], with: component, given: edit.fields)
      default: throw SevraError("view", "Unknown layout edit.")
      }
      return true
    }
    for index in components.indices where components[index].children != nil {
      if try alterComponent(id, in: &components[index].children!, edit: edit) { return true }
    }
    return false
  }
  /// A replacement of the same type keeps each saved field the caller did not write, so
  /// "make it a bar chart" can send the chart's id, type, title and chartStyle and keep its
  /// table, x and y. A field written as null is cleared. A new type is a new component, whole.
  static func merged(_ saved: Component, with given: Component, given fields: [String]?) throws
    -> Component
  {
    guard let fields, saved.type == given.type else { return given }
    let named = Set(fields)
    var merged = try encoded(given).object
    for (key, value) in try encoded(saved).object where !named.contains(key) {
      merged[key] = value
    }
    return try JSONDecoder().decode(Component.self, from: Data(Value.object(merged).json().utf8))
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
