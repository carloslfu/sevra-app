import Foundation

/// The short automation shapes chat writes, bound behind the scenes to saved definitions.
///
/// A saved automation always names an exact workflow, its arguments and one trigger. Chat may
/// instead say what it does in one of three ways: `alert`, one sentence drafted for review at
/// each start through the shared Alert workflow; `tool`, a saved tool run directly through a
/// one-step workflow; or `workflow` for several steps. The trigger is `schedule` with policy
/// `calendar-v1` or `check` with policy `check-v1`. A check or a tool can be named by name.
extension Workbook {
  /// The shapes chat can use, for refusals that say exactly what to send.
  static let automationShapes =
    "Use {policy: calendar-v1, schedule, alert: \"one sentence\"} to remind on a schedule, {policy: check-v1, check: {name: a saved check}, alert} to alert when the check finds rows, tool: {name: a saved tool} with arguments in place of alert to run that tool, or workflow: {mode: exact, versionID} with arguments for several steps."

  /// The canonical content for an automation chat saved in a short shape. Content already in
  /// the canonical shape comes back with only its missing `arguments` filled in.
  package func boundAutomation(
    _ content: Value, token: String, requestRunID: String?, requestSourceID: String?,
    cancellation: Cancellation
  ) throws -> Value {
    var bound = content.object
    let payload = content["payload"].object
    let allowed: Set<String> = [
      "policy", "schedule", "check", "workflow", "arguments", "alert", "tool",
    ]
    let unknown = Set(payload.keys).subtracting(allowed).sorted()
    try require(
      unknown.isEmpty, "automation_definition",
      "An automation's payload has no " + unknown.joined(separator: ", ") + ". "
        + Self.automationShapes)
    if bound["parameters"] == nil { bound["parameters"] = .array([]) }
    try require(
      bound["parameters"]!.array.isEmpty, "automation_definition",
      "An automation takes no parameters: set parameters to []. Give the values it uses in arguments."
    )
    let policy = payload["policy"]?.string ?? ""
    try require(
      [DefinitionAutomation.calendarPolicy, DefinitionAutomation.checkPolicy].contains(policy),
      "automation_definition",
      "Set policy to calendar-v1 to start on a schedule, or check-v1 to start when a saved check finds rows. "
        + Self.automationShapes)
    let calendar = policy == DefinitionAutomation.calendarPolicy
    if calendar {
      try require(
        payload["schedule"] != nil && payload["check"] == nil, "automation_definition",
        "A calendar-v1 automation needs schedule: {policy: native-calendar-v1, timeZone, hour, minute, recurrence}, and no check.")
      let text = [content["title"], content["description"], payload["alert"] ?? .null]
        .compactMap(\.string).joined(separator: " ")
      if let conflict = try NativeCalendarSchedule(payload["schedule"]!).weekdayConflict(text) {
        throw SevraError("schedule", conflict)
      }
    } else {
      try require(
        payload["check"] != nil && payload["schedule"] == nil, "automation_definition",
        "A check-v1 automation needs check: {name: the saved check's name} or {mode: live, logicalID}, and no schedule.")
    }
    let does = ["alert", "tool", "workflow"].filter { payload[$0] != nil }
    try require(
      does.count == 1, "automation_definition",
      (does.isEmpty
        ? "Say what it does when it starts. "
        : "Use one of alert, tool or workflow, not " + does.joined(separator: " and ") + ". ")
        + Self.automationShapes)
    var next = payload
    if !calendar { next["check"] = try checkBinding(payload["check"]!) }
    switch does[0] {
    case "alert":
      try require(
        payload["arguments"] == nil, "automation_definition",
        "An alert takes no arguments: its sentence is the alert.")
      let alert = payload["alert"]!.text.trimmingCharacters(in: .whitespacesAndNewlines)
      try require(
        !alert.isEmpty && alert.utf8.count <= 2_000, "automation_definition",
        "Write the alert as one sentence of at most 2,000 bytes.")
      if let slot = alert.range(of: #"\{[A-Za-z_][A-Za-z0-9_ ]*\}"#, options: .regularExpression) {
        throw SevraError(
          "automation_definition",
          "An alert is fixed text, so " + alert[slot]
            + " would show as written. Write one plain sentence without placeholders, such as \"A contract ends within 30 days.\" The check shows which rows.")
      }
      let evidence: Item
      if calendar {
        evidence = try synchronized { try reminderEvidence(requestSourceID) }
      } else {
        let check = try DefinitionBinding(next["check"]!)
        evidence = try synchronized { try checkAlertEvidence(resolveDefinition(check)) }
      }
      let workflow = try sharedAlertWorkflow(
        token: token, requestRunID: requestRunID, requestSourceID: requestSourceID,
        cancellation: cancellation)
      next["alert"] = nil
      next["workflow"] = .object(["mode": .string("exact"), "versionID": .string(workflow.id)])
      next["arguments"] = .object([
        "title": .string((calendar ? "Reminder: " : "Alert: ") + content["title"].text),
        "body": .string(alert), "evidence": .string(evidence.id),
        "meaning": .string(Item.meanings.contains(evidence.meaning) ? evidence.meaning : "plan"),
        "scenario": .string(evidence.scenario),
      ])
    case "tool":
      let tool = try synchronized { try automationTool(payload["tool"]!) }
      let workflow = try toolWorkflow(
        tool, token: token, requestRunID: requestRunID, requestSourceID: requestSourceID,
        cancellation: cancellation)
      next["tool"] = nil
      next["workflow"] = .object(["mode": .string("exact"), "versionID": .string(workflow.id)])
      next["arguments"] = payload["arguments"] ?? .object([:])
    default:
      let binding = payload["workflow"]!
      let saved = try? synchronized { try resolveDefinition(DefinitionBinding(binding)) }
      try require(
        binding["mode"] == .string("exact") && saved?.kind == "workflow", "automation_binding",
        "workflow is {mode: exact, versionID} of a saved workflow"
          + (saved == nil ? ", and no saved workflow has that versionID" : "")
          + ". For a reminder or an alert use alert: \"one sentence\", and to run one saved tool use tool: {name}.")
      next["arguments"] = payload["arguments"] ?? .object([:])
    }
    bound["payload"] = .object(next)
    return .object(bound)
  }

  /// A check named by name, or bound by its logical ID.
  private func checkBinding(_ value: Value) throws -> Value {
    guard let name = value["name"].string else { return value }
    try require(
      value.object.count == 1, "automation_check", "Name the check alone: check: {name}.")
    guard let tool = try synchronized({ try savedTools().first { $0.name == name } }) else {
      throw SevraError(
        "automation_check",
        "No saved tool is named \(name). Save the check first with save tool: one SELECT of the rows to watch, with no inputs.")
    }
    return .object(["mode": .string("live"), "logicalID": .string(tool.logicalID)])
  }

  /// The saved tool an automation runs, by `{name}` or by `{id}`, its definition or logical ID.
  private func automationTool(_ value: Value) throws -> ApplicationDefinition {
    let tools = try savedTools()
    let found: SavedTool?
    if let name = value["name"].string, value.object.count == 1 {
      found = tools.first { $0.name == name }
    } else if let id = value["id"].string, value.object.count == 1 {
      found = tools.first { $0.definitionID == id || $0.logicalID == id }
    } else {
      throw SevraError(
        "automation_tool", "Name the tool as tool: {name: the saved tool's name}.")
    }
    guard let found else {
      let names = tools.prefix(12).map(\.name).joined(separator: ", ")
      throw SevraError(
        "automation_tool",
        "No saved tool is " + (value["name"].string ?? value["id"].text) + ". "
          + (names.isEmpty
            ? "The workbook has no saved tools: save one first with save tool."
            : "Saved tools: " + names + "."))
    }
    return try applicationDefinition(found.definitionID)
  }

  /// What a reminder cites: the person's own request that asked for it, as the host received it.
  private func reminderEvidence(_ requestSourceID: String?) throws -> Item {
    guard let requestSourceID,
      try db.scalar(
        "SELECT EXISTS(SELECT 1 FROM business_inputs WHERE source_id=? AND kind='request')",
        [.string(requestSourceID)]
      ).int == 1
    else {
      throw SevraError(
        "automation_definition",
        "A reminder cites the request that asks for it, so save it from a chat request. Elsewhere, use workflow with arguments."
      )
    }
    return try item(requestSourceID)
  }

  private func savedDefinition(
    _ logicalID: String, _ content: Value, kind: String, token: String, requestRunID: String?,
    requestSourceID: String?, cancellation: Cancellation
  ) throws -> ApplicationDefinition {
    let current = try? applicationDefinition(logicalID)
    if let current {
      try require(
        current.kind == kind, "definition_kind",
        "The workbook's shared \(kind) for automations is not a \(kind).")
      if current.content == content { return current }
    }
    return try saveApplicationDefinition(
      logicalID: logicalID, content: content, expectedDefinitionID: current?.id,
      token: token, requestRunID: requestRunID, requestSourceID: requestSourceID,
      cancellation: cancellation)
  }

  /// The shared Alert workflow every alert and reminder runs, saved with the first one.
  func sharedAlertWorkflow(
    token: String, requestRunID: String?, requestSourceID: String?, cancellation: Cancellation
  ) throws -> ApplicationDefinition {
    let action = try savedDefinition(
      Self.checkAlertActionID,
      ActionRegistry.documentDefinition(
        title: "Draft an alert", description: "Draft an alert for review."),
      kind: "action", token: token + "-alert-action", requestRunID: requestRunID,
      requestSourceID: requestSourceID, cancellation: cancellation)
    var wanted = try synchronized { try db.readTransaction { try workflowTemplate(action.id) } }
      .object
    wanted["title"] = .string("Alert")
    wanted["description"] = .string(
      "Draft an alert or reminder for review. Automations that alert or remind run it.")
    return try savedDefinition(
      Self.checkAlertWorkflowID, .object(wanted), kind: "workflow",
      token: token + "-alert-workflow", requestRunID: requestRunID,
      requestSourceID: requestSourceID, cancellation: cancellation)
  }

  /// The one-step workflow that runs one saved tool's current version, shared by every
  /// automation of that tool. A changed tool gets a new version of it; saved automations keep
  /// the exact version they were saved with.
  private func toolWorkflow(
    _ tool: ApplicationDefinition, token: String, requestRunID: String?, requestSourceID: String?,
    cancellation: Cancellation
  ) throws -> ApplicationDefinition {
    let name = try DefinitionTool(DefinitionDescriptor(tool.content)).name
    let action = try savedDefinition(
      Self.derivedIdentity("tool-automation-action:" + tool.logicalID),
      ActionRegistry.toolActionDefinition(tool: tool, title: "Run " + name, exact: true),
      kind: "action", token: token + "-tool-action", requestRunID: requestRunID,
      requestSourceID: requestSourceID, cancellation: cancellation)
    var wanted = try synchronized { try db.readTransaction { try workflowTemplate(action.id) } }
      .object
    wanted["title"] = .string("Run " + name)
    wanted["description"] = .string("Runs the saved tool " + name + ".")
    return try savedDefinition(
      Self.derivedIdentity("tool-automation-workflow:" + tool.logicalID), .object(wanted),
      kind: "workflow", token: token + "-tool-workflow", requestRunID: requestRunID,
      requestSourceID: requestSourceID, cancellation: cancellation)
  }

  /// A logical identity the host derives from a seed, so each tool has one shared workflow.
  static func derivedIdentity(_ seed: String) -> String {
    var hex = Array(ChangeFormat.hash("sevra-derived:" + seed).prefix(32))
    hex[12] = "8"
    hex[16] = ["8", "9", "a", "b"][Int(String(hex[16]), radix: 16)! % 4]
    let text = String(hex)
    let cut = [8, 4, 4, 4, 12]
    var parts: [String] = []
    var start = text.startIndex
    for length in cut {
      let end = text.index(start, offsetBy: length)
      parts.append(String(text[start..<end]))
      start = end
    }
    return parts.joined(separator: "-")
  }

  /// The saved tool a workflow runs when it is one step that runs a tool, as a workflow the
  /// automation shape `tool` saves is. Nil for any other workflow.
  public func singleToolName(ofWorkflow id: String) throws -> String? {
    try synchronized {
      let saved = try applicationDefinition(id)
      guard saved.kind == "workflow" else { return nil }
      let steps = try DefinitionWorkflow(DefinitionDescriptor(saved.content)).steps
      guard steps.count == 1, steps[0].kind == "action", let binding = steps[0].binding else {
        return nil
      }
      let target = try resolveDefinition(binding)
      guard try actionRunsTool(target, historical: true), let tool = try toolAction(target).tool
      else { return nil }
      return try DefinitionTool(DefinitionDescriptor(resolveDefinition(tool).content)).name
    }
  }
}
