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
        "Component \(component.id) (button) needs definitionBinding: {tool: the name of a saved tool}. Write a button's fields in this order: id, type, title, definitionBinding, arguments, size. A field you have passed cannot be written later."
      )
    }
    switch component.arguments {
    case nil, .null?: fixed = [:]
    case .object(let values)?: fixed = values
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
        "No saved tool is named \(button.tool)."
          + (tools.isEmpty
            ? " Save the tool first with save tool, then the view."
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
