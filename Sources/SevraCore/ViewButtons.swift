import Foundation

/// A view's button runs one of the workbook's saved tools when a person presses it. The tool
/// is the action: rows added, changed or removed, a calculation or a script, with typed
/// inputs. The button can fix some inputs in its `arguments`, and the person fills in the
/// rest beside it. A press runs through the same path as the chat's `sql tool=` and
/// `run tool=`, so it is recorded and can be undone like any other change.
public struct ViewButton: Sendable, Equatable {
  /// The saved tool's name.
  public let tool: String
  /// The inputs the button sets itself.
  public let fixed: [String: Value]

  public init(_ component: Component) throws {
    guard case .object(let binding)? = component.definitionBinding, Set(binding.keys) == ["tool"],
      let name = binding["tool"]?.string, DefinitionTool.isName(name)
    else {
      throw SevraError(
        "view",
        "Component \(component.id) (button) needs definitionBinding: {tool: \"name\"}, with the name of the saved tool it runs. Write a button's fields in this order: id, type, title, size, definitionBinding, arguments. A field you have passed cannot be written later."
      )
    }
    switch component.arguments {
    case nil, .null?: fixed = [:]
    // A null is an input left for the person to fill in when pressing, as if left out.
    case .object(let values)?: fixed = values.filter { $0.value != .null }
    default:
      throw SevraError(
        "view", "A button's arguments are an object: a value for each tool input it sets itself.")
    }
    tool = name
  }

  /// The inputs the person fills in before pressing.
  public func open(_ tool: Workbook.SavedTool) -> [(name: String, type: String, required: Bool)] {
    tool.inputs.filter { fixed[$0.name] == nil }
  }
}

extension Workbook {
  /// A button as a view saves it: its tool exists and its fixed values fit that tool's inputs.
  /// A tool that is not enabled on this Mac is still a valid binding. The button says so.
  func checkButton(_ button: ViewButton) throws {
    let tools = try savedTools()
    guard let tool = tools.first(where: { $0.name == button.tool }) else {
      throw SevraError(
        "view",
        "No saved tool is named \(button.tool). Save the tool first with save {tool}, then add the button."
          + (tools.isEmpty
            ? ""
            : " Saved tools: " + tools.map(\.signature).joined(separator: ", ") + "."))
    }
    // arguments holds values the button always uses. An input the person picks each time is
    // left out, and the button shows a field for it; a placeholder would be sent as the value.
    let placeholders = button.fixed.filter { $0.value.text.hasPrefix(":") }.keys.sorted()
    try require(
      placeholders.isEmpty, "view",
      "arguments holds values the button always uses. Leave " + placeholders.joined(separator: " and ")
        + " out of arguments: the button shows a field for each input it leaves out, and the person fills it in when pressing.")
    _ = try toolValues(tool, button.fixed, complete: false)
  }

  /// Runs a view's button with the values the person filled in. The result is the tool's
  /// own, with its undo value when it changed something.
  @discardableResult public func pressButton(
    spaceID: String, componentID: String, values: [String: Value] = [:],
    token: String = identifier(), cancellation: Cancellation = .init(),
    actor: ChangeActor? = nil
  ) throws -> Value {
    let button = try synchronized { () throws -> ViewButton in
      guard let component = try space(spaceID).definition.component(componentID),
        component.type == "button"
      else { throw SevraError("view", "Choose a button on a saved view.") }
      return try ViewButton(component)
    }
    let overlap = Set(values.keys).intersection(button.fixed.keys).sorted()
    try require(
      overlap.isEmpty, "tool_inputs",
      "The button sets " + overlap.joined(separator: " and ") + " itself.")
    // An input the button leaves open is the person's to fill in before pressing.
    let tool = try synchronized { try savedTools().first { $0.name == button.tool } }
    if let tool {
      let missing = button.open(tool).filter { input in
        input.required && (values[input.name].map { $0 == .null || $0.text.isEmpty } ?? true)
      }.map(\.name)
      try require(
        missing.isEmpty, "tool_inputs",
        "Fill in " + missing.joined(separator: " and ") + " before pressing this button. Nothing ran.")
    }
    return try ChangeAttribution.$actor.withValue(actor ?? ChangeAttribution.actor) {
      try WorkbookTools(self, cancellation: cancellation, conversation: "").runSavedTool(
        button.tool, values: button.fixed.merging(values) { fixed, _ in fixed },
        readOnly: false, token: token)
    }
  }

  /// Takes back one press, by the undo value its result carried.
  @discardableResult public func undoButtonPress(
    _ undo: String, cancellation: Cancellation = .init(), actor: ChangeActor? = nil
  ) throws -> Value {
    try chatSQLUndo(undo, actor: actor, cancellation: cancellation)
  }

  /// What a script's queued actions did not do. A press has no chat, so an action that needs
  /// the app does not run, and an action that failed says why.
  public static func runProblem(_ result: Value) -> String? {
    let actions = result["actions"].array
    let failed = actions.compactMap { $0["error"].string }
    let waiting = actions.filter { $0["result"]["hostAction"] != .null }.count
    var problems: [String] = []
    if let first = failed.first {
      problems.append(
        (failed.count == 1 ? "1 action" : "\(failed.count) actions") + " could not finish: " + first)
    }
    if waiting > 0 {
      problems.append(
        (waiting == 1 ? "1 action needs" : "\(waiting) actions need") + " the chat and did not run.")
    }
    return problems.isEmpty ? nil : problems.joined(separator: " ")
  }

  /// What a tool run changed, as one short sentence for the status line.
  public static func describeRun(_ result: Value) -> String {
    var added = 0
    var changed = 0
    var removed = 0
    for change in result["changes"].array {
      added += change["inserted"].int ?? 0
      changed += change["updated"].int ?? 0
      removed += change["deleted"].int ?? 0
    }
    func rows(_ count: Int) -> String { count == 1 ? "1 row" : "\(count) rows" }
    var parts: [String] = []
    if added > 0 { parts.append("added " + rows(added)) }
    if changed > 0 { parts.append("changed " + rows(changed)) }
    if removed > 0 { parts.append("removed " + rows(removed)) }
    guard let last = parts.last else {
      return result["shape"].array.isEmpty && result["undo"] == .null
        ? "Done. Nothing changed." : "Done."
    }
    let sentence = parts.count == 1 ? last : parts.dropLast().joined(separator: ", ") + " and " + last
    return sentence.prefix(1).uppercased() + sentence.dropFirst() + "."
  }
}

extension Workbook {
  /// A note for whoever saved `definition` when a button's SQL tool changes a table that no
  /// table, chart or metric on the view shows. A button shows only what its last press
  /// returned, so a counter or a log with nothing beside it looks like it did nothing. A
  /// script's tables are read from the SQL text it passes to sql(). nil when every such table
  /// is in view.
  func unshownButtonTablesNotice(_ definition: SpaceDefinition, spaceID: String, version: Int)
    throws -> String?
  {
    func flatten(_ components: [Component]) -> [Component] {
      components.flatMap { [$0] + flatten($0.children ?? []) }
    }
    let components = flatten(definition.components)
    let buttons = components.filter { $0.type == "button" }.compactMap { try? ViewButton($0) }
    guard !buttons.isEmpty else { return nil }
    let shown = Set(
      components.filter { ["table", "chart", "metric"].contains($0.type) }.flatMap { component in
        // A query shows the tables it reads.
        [component.datasetID].compactMap { $0 }
          + (component.query.flatMap { try? componentQuery($0).tableIDs } ?? [])
      })
    let tools = try savedTools()
    let tables = SQLScratch.named(try datasets())
    var missing: [(tool: String, dataset: Dataset, onlyInserts: Bool)] = []
    for button in buttons {
      guard let tool = tools.first(where: { $0.name == button.tool }) else { continue }
      let text = tool.language == "sql" ? tool.statements : [tool.source]
      let onlyInserts = text.allSatisfy {
        $0.range(of: #"(?i)\b(update|delete)\b"#, options: .regularExpression) == nil
      }
      for name in Self.writtenTables(text) {
        guard let table = tables.first(where: { $0.name == name }),
          !shown.contains(table.dataset.id),
          !missing.contains(where: { $0.dataset.id == table.dataset.id })
        else { continue }
        missing.append((tool.name, table.dataset, onlyInserts))
      }
    }
    guard let first = missing.first else { return nil }
    let list = missing.map { "\($0.dataset.title), which \($0.tool) changes" }
      .joined(separator: "; ")
    return
      "Saved. Nothing on this view shows \(list). A button shows only what its last press returned, so the person cannot see what pressing it records. Unless they asked for the button alone, run view.edit {id: \"\(spaceID)\", expectedVersion: \(version), edits: [{operation: \"insert\", at: \"first\", component: \(Self.suggestedComponent(first.dataset, onlyInserts: first.onlyInserts))}]}, with that component as written, and say in the reply what you added."
  }

  /// A component that shows what a button records in `dataset`: the count of its rows when a
  /// press only adds rows, the total of its one number column when a press changes a value,
  /// and otherwise the table itself. Its fields are in the grammar's order.
  static func suggestedComponent(_ dataset: Dataset, onlyInserts: Bool) -> String {
    func quoted(_ text: String) -> String {
      String(decoding: (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8), as: UTF8.self)
    }
    let numbers = dataset.columns.filter { $0.type == "decimal" && $0.id.lowercased() != "id" }
    let head =
      "{id: \"shown_total\", type: \"metric\", title: \(quoted(dataset.title)), size: \"large\", datasetID: \(quoted(dataset.id)), "
    if onlyInserts { return head + "aggregation: \"COUNT\"}" }
    if numbers.count == 1 {
      return head + "aggregation: \"SUM\", y: \(quoted(numbers[0].id))}"
    }
    return
      "{id: \"shown_table\", type: \"table\", title: \(quoted(dataset.title)), datasetID: \(quoted(dataset.id))}"
  }

  /// The tables SQL text inserts into, updates or deletes from, by their sql names.
  static func writtenTables(_ statements: [String]) -> [String] {
    let pattern =
      #"(?i)\b(?:insert(?:\s+or\s+\w+)?\s+into|replace\s+into|update(?:\s+or\s+\w+)?|delete\s+from)\s+["`\[]?([A-Za-z_][A-Za-z0-9_]*)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    var names: [String] = []
    for statement in statements {
      let range = NSRange(statement.startIndex..., in: statement)
      for match in regex.matches(in: statement, range: range) {
        if let r = Range(match.range(at: 1), in: statement) {
          let name = statement[r].lowercased()
          if !names.contains(name) { names.append(name) }
        }
      }
    }
    return names
  }
}
