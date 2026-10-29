import Foundation

struct DefinitionAutomation {
  let workflow: DefinitionBinding
  let arguments: Value
  let schedule: NativeCalendarSchedule

  init(_ descriptor: DefinitionDescriptor) throws {
    try require(
      descriptor.kind == "automation" && descriptor.parameters.isEmpty
        && Set(descriptor.payload.object.keys) == ["policy", "workflow", "arguments", "schedule"]
        && descriptor.payload["policy"] == .string("calendar-drafts-v1"),
      "automation_definition",
      "An inert calendar-drafts-v1 definition needs exact workflow, arguments and schedule, without parameters."
    )
    workflow = try DefinitionBinding(descriptor.payload["workflow"])
    try require(
      workflow.mode == "exact", "automation_binding", "Pin an exact saved workflow version.")
    arguments = descriptor.payload["arguments"]
    schedule = try NativeCalendarSchedule(descriptor.payload["schedule"])
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
          "calendar": try DefinitionAutomation(descriptor).schedule.preview(
            after: after, count: count, horizonDays: horizonDays, cancellation: cancellation),
        ])
      }
    }
  }

  func verifyAutomationDefinition(_ saved: ApplicationDefinition, dependencies: [Value]) throws {
    let descriptor = try DefinitionDescriptor(saved.content)
    let retained = try validateAutomationDefinition(descriptor, historical: true)
    try require(
      dependencies.count == 1 && dependencies[0]["ordinal"] == .number(0)
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
