import Foundation

/// A saved automation: what starts it, and the exact draft workflow it runs.
///
/// Two triggers: `calendar-drafts-v1` starts on a calendar schedule, and `check-drafts-v1`
/// starts when a saved check, a read-only SQL tool, starts finding rows. Either one runs only
/// while the app is open on a Mac where the person enabled it.
struct DefinitionAutomation {
  static let calendarPolicy = "calendar-drafts-v1"
  static let checkPolicy = "check-drafts-v1"
  let policy: String
  let workflow: DefinitionBinding
  let arguments: Value
  private let calendar: NativeCalendarSchedule?
  /// The exact saved check version a check automation watches.
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
      "Use an exact workflow, arguments and one trigger, without parameters: schedule with policy calendar-drafts-v1, or check with policy check-drafts-v1."
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
        binding.mode == "exact", "automation_binding", "Pin an exact saved check version.")
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
    // An automation prepares drafts for review. A step that changes tables at once does not.
    for step in try DefinitionWorkflow(workflow).steps where step.kind == "action" {
      try require(
        !(try actionRunsTool(resolveDefinition(step.binding!))), "automation_binding",
        "An automation's workflow prepares drafts for review. Its step \(step.id) runs a saved tool, which changes tables at once, so an automation cannot run this workflow."
      )
    }
    if let check = automation.check {
      _ = try automationCheck(resolveDefinition(check), historical: historical)
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
    guard let check = automation.check else {
      return [
        "calendar": try automation.schedule.preview(
          after: after, count: count, horizonDays: horizonDays, cancellation: cancellation)
      ]
    }
    let tool = try applicationDefinition(check.target)
    return [
      "check": .object([
        "definitionID": .string(tool.id),
        "name": .string(try DefinitionTool(DefinitionDescriptor(tool.content)).name),
        "fires": .string("when the check starts finding rows"),
      ])
    ]
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
          && dependencies[1]["mode"] == .string("exact")
          && dependencies[1]["target_version"] == .string(check.target),
        "definition_integrity", "The automation lost its exact check dependency.")
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
