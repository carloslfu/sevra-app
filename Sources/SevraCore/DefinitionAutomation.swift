import Foundation

/// A saved automation: what starts it, and the exact workflow it runs.
///
/// Two triggers: `calendar-v1` starts on a calendar schedule, and `check-v1` starts when a
/// saved check, a read-only SQL tool, starts finding rows. Either one runs only while the app is
/// open on a Mac where the person enabled it. The workflow can draft for review or run saved
/// tools, whose changes apply at once with an Undo. The enable step names those tools.
struct DefinitionAutomation {
  static let calendarPolicy = "calendar-v1"
  static let checkPolicy = "check-v1"
  let policy: String
  let workflow: DefinitionBinding
  let arguments: Value
  private let calendar: NativeCalendarSchedule?
  /// The saved check a check automation watches, by its logical ID: the check's latest version,
  /// like a saved filter. Each evaluation records the exact version that ran.
  let check: DefinitionBinding?
  var schedule: NativeCalendarSchedule {
    get throws {
      guard let calendar else {
        throw SevraError(
          "automation_trigger", "This automation starts when its check finds rows, not on a schedule.")
      }
      return calendar
    }
  }
  /// The definitions it depends on: its workflow, then its check.
  var bindings: [DefinitionBinding] { [workflow] + (check.map { [$0] } ?? []) }
  init(_ descriptor: DefinitionDescriptor) throws {
    let policy = descriptor.payload["policy"].text
    let isCalendar = policy == Self.calendarPolicy
    try require(
      descriptor.kind == "automation" && descriptor.parameters.isEmpty
        && [Self.calendarPolicy, Self.checkPolicy].contains(policy)
        && Set(descriptor.payload.object.keys)
          == ["policy", "workflow", "arguments", isCalendar ? "schedule" : "check"],
      "automation_definition",
      "A saved automation has parameters [] and payload {policy, workflow, arguments} with schedule for calendar-v1 or check for check-v1. "
        + Workbook.automationShapes
    )
    self.policy = policy
    workflow = try DefinitionBinding(descriptor.payload["workflow"])
    try require(
      workflow.mode == "exact", "automation_binding", "Pin an exact saved workflow version.")
    arguments = descriptor.payload["arguments"]
    if isCalendar {
      calendar = try NativeCalendarSchedule(descriptor.payload["schedule"])
      check = nil
    } else {
      calendar = nil
      let binding = try DefinitionBinding(descriptor.payload["check"])
      try require(
        binding.mode == "live", "automation_binding",
        "Choose the check by its logical ID, {mode: live, logicalID}, so the automation follows edits to the check.")
      check = binding
    }
  }
}

extension Workbook {
  func validateAutomationDefinition(_ descriptor: DefinitionDescriptor, historical: Bool = false)
    throws -> (workflow: ApplicationDefinition, arguments: Value, inputs: [String])
  {
    let automation = try DefinitionAutomation(descriptor)
    let target = try resolveDefinition(automation.workflow)
    try require(
      target.kind == "workflow", "automation_binding", "An automation must target a saved workflow."
    )
    let workflow = try DefinitionDescriptor(target.content)
    try validateWorkflowDefinition(workflow, historical: historical)
    if let check = automation.check {
      let current = try resolveDefinition(check)
      // The check follows its latest version, which may since have changed into something that
      // cannot be a check. An evaluation refuses that. History only needs it to be a tool.
      if historical {
        try require(current.kind == "tool", "automation_check", "A check is a saved SQL tool.")
      } else {
        _ = try automationCheck(current)
      }
    }
    let normalized = Value.object(try definitionArguments(workflow, automation.arguments))
    var inputs: Set<String> = []
    func collect(_ parameters: [DefinitionParameter], _ values: Value) {
      for parameter in parameters {
        let value = values[parameter.id]
        if parameter.type == "item", let id = value.string { inputs.insert(id) }
        if parameter.type == "entries" {
          for row in value.array { collect(parameter.fields, row) }
        }
      }
    }
    collect(workflow.parameters, normalized)
    try require(
      inputs.count <= 256, "definition_limit",
      "An automation can retain at most 256 distinct argument item versions.")
    return (target, normalized, inputs.sorted())
  }

  /// Portable definition metadata never enables a schedule or authorizes execution.
  public func previewAutomation(
    _ exactID: String, after: Date, count: Int = 5, horizonDays: Int = 3660,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try synchronized(cancellation: cancellation) {
      try db.readTransaction {
        let saved = try applicationDefinition(exactID)
        try require(
          saved.id == exactID && saved.kind == "automation", "automation_binding",
          "Preview an exact saved automation version.")
        let descriptor = try DefinitionDescriptor(saved.content)
        let retained = try validateAutomationDefinition(descriptor, historical: true)
        return .object([
          "automationID": .string(saved.id), "logicalID": .string(saved.logicalID),
          "version": .number(Double(saved.version)), "sourceID": .string(saved.sourceID),
          "workflowID": .string(retained.workflow.id), "arguments": retained.arguments,
          "execution": .string("inert"), "enabled": .bool(false),
        ].merging(
          try triggerPreview(
            DefinitionAutomation(descriptor), after: after, count: count,
            horizonDays: horizonDays, cancellation: cancellation)
        ) { $1 })
      }
    }
  }

  /// Validates unsaved typed intent without creating a definition or permission.
  public func previewAutomationDraft(
    _ content: Value, after: Date, cancellation: Cancellation = .init()
  ) throws -> Value {
    try readBusinessFeed(cancellation: cancellation) {
      let descriptor = try DefinitionDescriptor(content)
      let retained = try validateAutomationDefinition(descriptor)
      return .object([
        "workflowID": .string(retained.workflow.id), "arguments": retained.arguments,
        "enabled": .bool(false), "execution": .string("inert"),
      ].merging(
        try triggerPreview(DefinitionAutomation(descriptor), after: after, cancellation: cancellation)
      ) { $1 })
    }
  }

  /// What a preview says about the trigger: the next calendar times, or the saved check.
  private func triggerPreview(
    _ automation: DefinitionAutomation, after: Date, count: Int = 5, horizonDays: Int = 3660,
    cancellation: Cancellation
  ) throws -> [String: Value] {
    let tools = try automationTools(automation)
    let drafts = try DefinitionWorkflow(
      DefinitionDescriptor(resolveDefinition(automation.workflow).content)
    ).steps.contains { $0.kind == "review" }
    var preview: [String: Value] = ["tools": .array(tools.map(Value.string))]
    guard let check = automation.check else {
      preview["calendar"] = try automation.schedule.preview(
        after: after, count: count, horizonDays: horizonDays, cancellation: cancellation)
      preview["notice"] = .string(Self.automationNotice(check: nil, tools: tools, drafts: drafts))
      return preview
    }
    let tool = try resolveDefinition(check)
    let name = try DefinitionTool(DefinitionDescriptor(tool.content)).name
    preview["check"] = .object([
      "logicalID": .string(tool.logicalID), "definitionID": .string(tool.id),
      "name": .string(name), "description": .string(tool.description),
      "fires": .string("when the check starts finding rows"),
    ])
    preview["notice"] = .string(Self.automationNotice(check: name, tools: tools, drafts: drafts))
    return preview
  }

  /// The names of the saved tools the automation's workflow runs, in step order.
  func automationTools(_ automation: DefinitionAutomation) throws -> [String] {
    let workflow = try DefinitionDescriptor(resolveDefinition(automation.workflow).content)
    var names: [String] = []
    for step in try DefinitionWorkflow(workflow).steps where step.kind == "action" {
      let target = try resolveDefinition(step.binding!)
      guard try actionRunsTool(target, historical: true),
        let binding = try toolAction(target).tool
      else { continue }
      let name = try DefinitionTool(DefinitionDescriptor(resolveDefinition(binding).content)).name
      if !names.contains(name) { names.append(name) }
    }
    return names
  }

  /// What enabling an automation means, in plain sentences. The editor, the automation's page
  /// and the chat confirmation all show it before the person enables it.
  public static func automationNotice(check: String?, tools: [String], drafts: Bool = false)
    -> String
  {
    var lines: [String] = []
    if let check {
      lines.append(
        "It starts when the check \(check) finds rows after finding none. If the check already finds rows when you enable it, it starts once right away. If you change the check, the changed check starts fresh, so rows it finds then start it once."
      )
    }
    if tools.isEmpty {
      lines.append(
        drafts
          ? "It drafts its changes for review. Your tables change only when you accept a draft."
          : "It does not change your tables.")
    } else {
      let list =
        tools.count == 1
        ? tools[0]
        : tools.dropLast().joined(separator: ", ") + " and " + tools.last!
      lines.append(
        "It runs the saved \(tools.count == 1 ? "tool" : "tools") \(list) without asking. \(tools.count == 1 ? "Its" : "Their") changes apply without review. Each run is saved in Workflow runs with an Undo."
      )
      if drafts { lines.append("Any drafts it makes wait for your review.") }
    }
    return lines.joined(separator: " ")
  }

  /// A saved check: a SQL tool with no inputs whose statements only read. Its rows are what
  /// the automation watches.
  func automationCheck(_ saved: ApplicationDefinition, historical: Bool = false) throws
    -> DefinitionTool
  {
    try require(saved.kind == "tool", "automation_check", "A check is a saved SQL tool.")
    let descriptor = try DefinitionDescriptor(saved.content)
    let tool = try DefinitionTool(descriptor)
    try require(
      historical || !tool.retired, "automation_check", "The check \(tool.name) was removed.")
    try require(
      tool.language == "sql", "automation_check",
      "A check is a saved SQL tool. \(tool.name) is a script.")
    try require(
      descriptor.parameters.isEmpty, "automation_check",
      "A check takes no inputs. \(tool.name) has inputs, so it cannot run on its own.")
    if !historical {
      let rehearsal = try SQLScratch(
        tables: datasets(), readOnly: true, draft: false, inputs: [:], cancellation: .init())
      defer { rehearsal.close() }
      do {
        _ = try rehearsal.rehearse(tool.statements)
      } catch let error as SevraError where error.code == "read_only_request" {
        throw SevraError(
          "automation_check",
          "A check only reads. \(tool.name) changes tables, so it cannot be a check. Save a tool whose statements are one SELECT."
        )
      }
      try require(
        tool.statements.last.map { $0.range(of: #"(?i)^\s*(select|with)\b"#, options: .regularExpression) != nil } == true,
        "automation_check", "A check's last statement is a SELECT. Its rows are what the automation watches.")
    }
    return tool
  }

  func verifyAutomationDefinition(_ saved: ApplicationDefinition, dependencies: [Value]) throws {
    let descriptor = try DefinitionDescriptor(saved.content)
    let retained = try validateAutomationDefinition(descriptor, historical: true)
    let automation = try DefinitionAutomation(descriptor)
    if let check = automation.check {
      try require(
        dependencies.count == 2 && dependencies[1]["ordinal"] == .number(1)
          && dependencies[1]["kind"] == .string("definition")
          && dependencies[1]["mode"] == .string("live")
          && dependencies[1]["target_logical"] == .string(check.target),
        "definition_integrity", "The automation lost its check dependency.")
    }
    try require(
      dependencies.count == automation.bindings.count && dependencies[0]["ordinal"] == .number(0)
        && dependencies[0]["kind"] == .string("definition")
        && dependencies[0]["mode"] == .string("exact")
        && dependencies[0]["target_version"] == .string(retained.workflow.id)
        && dependencies[0]["target_logical"] == .string(retained.workflow.logicalID),
      "definition_integrity", "The automation lost its exact workflow dependency.")
    for input in retained.inputs + [retained.workflow.sourceID] {
      try require(
        try db.scalar(
          "SELECT EXISTS(SELECT 1 FROM lineage WHERE child=? AND parent=?)",
          [.string(saved.sourceID), .string(input)]
        ).int == 1,
        "definition_integrity", "The automation lost exact workflow or argument evidence lineage.")
    }
  }
}
