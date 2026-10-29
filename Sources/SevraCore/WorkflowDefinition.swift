import Foundation

struct DefinitionWorkflow {
  struct Step {
    let id: String
    let kind: String
    let binding: DefinitionBinding?
    let arguments: [String: Value]
    let review: String?
  }
  let steps: [Step]

  init(_ descriptor: DefinitionDescriptor) throws {
    let payload = try definitionObject(descriptor.payload, keys: ["steps", "readPolicy"])
    guard payload["readPolicy"] == .string("latest-at-step"),
      case .array(let raw) = payload["steps"], (1...16).contains(raw.count)
    else {
      throw SevraError("workflow_definition", "Declare 1 to 16 steps and latest-at-step reads.")
    }
    var seen: [String: String] = [:]
    var reviews = Set<String>()
    var result: [Step] = []
    for value in raw {
      let o = try definitionObject(value, keys: ["id", "kind", "binding", "arguments", "review"])
      guard let id = o["id"]?.string,
        id.range(of: "^[A-Za-z_][A-Za-z0-9_]{0,63}\\z", options: .regularExpression) != nil,
        !id.hasPrefix("_sevra_"), seen[id] == nil,
        let kind = o["kind"]?.string, ["evaluate", "action", "review"].contains(kind)
      else {
        throw SevraError("workflow_definition", "Use distinct named evaluate/action/review steps.")
      }
      if kind == "review" {
        guard let from = o["review"]?.string, seen[from] == "action",
          reviews.insert(from).inserted, o["binding"] == nil, o["arguments"] == nil
        else {
          throw SevraError("workflow_definition", "Review one preceding action exactly once.")
        }
        result.append(.init(id: id, kind: kind, binding: nil, arguments: [:], review: from))
      } else {
        guard let rawBinding = o["binding"], case .object(let mappings) = o["arguments"],
          mappings.count <= 32, o["review"] == nil
        else {
          throw SevraError(
            "workflow_definition", "A step needs a binding and explicit argument mappings.")
        }
        let binding = try DefinitionBinding(rawBinding)
        try require(
          binding.mode == "exact", "workflow_binding",
          "Workflow steps require exact definition versions.")
        for mapping in mappings.values where mapping.object["step"] != nil {
          _ = try definitionObject(mapping, keys: ["step", "unit"])
          try require(
            mapping["step"].string != nil && seen[mapping["step"].text] == "evaluate",
            "workflow_mapping", "A result mapping must name a preceding evaluation step.")
        }
        result.append(.init(id: id, kind: kind, binding: binding, arguments: mappings, review: nil))
      }
      seen[id] = kind
    }
    try require(
      Set(seen.filter { $0.value == "action" }.keys) == reviews,
      "workflow_definition", "Each draft action needs a subsequent review step.")
    steps = result
  }
}

extension Workbook {
  func validateWorkflowDefinition(_ descriptor: DefinitionDescriptor, historical: Bool = false)
    throws
  {
    let workflow = try DefinitionWorkflow(descriptor)
    var previous: [String: ApplicationDefinition] = [:]
    var visited = Set<String>()
    func exactClosure(_ target: ApplicationDefinition, depth: Int) throws {
      try require(
        depth <= 8 && visited.count <= 128, "workflow_limit", "Workflow dependency limit exceeded.")
      guard visited.insert(target.id).inserted else { return }
      try require(visited.count <= 128, "workflow_limit", "Workflow dependency limit exceeded.")
      for binding in try definitionBindings(DefinitionDescriptor(target.content)) {
        try require(
          binding.mode == "exact", "workflow_binding",
          "All workflow dependencies must use exact versions.")
        try exactClosure(resolveDefinition(binding), depth: depth + 1)
      }
    }
    for step in workflow.steps {
      guard let binding = step.binding else { continue }
      let target = try resolveDefinition(binding)
      try require(
        (step.kind == "evaluate" ? ["function", "query"] : ["action", "form"]).contains(
          target.kind),
        "workflow_binding", "The workflow step targets the wrong definition kind.")
      if !historical {
        try validateDefinitionGraph(target, state: DefinitionEvaluation(.init()), depth: 0)
      }
      try exactClosure(target, depth: 0)
      let targetDescriptor = try DefinitionDescriptor(target.content)
      var plain = step.arguments
      for (name, mapping) in step.arguments where mapping.object["step"] != nil {
        guard let source = previous[mapping["step"].text], source.kind == "function",
          let parameter = targetDescriptor.parameters.first(where: { $0.id == name }),
          parameter.type == "decimal",
          (try DefinitionFunction(DefinitionDescriptor(source.content))).unit == parameter.unit,
          mapping.object["unit"] == parameter.unit.map(Value.string)
        else {
          throw SevraError(
            "workflow_mapping", "Map only a prior scalar function with the same decimal unit.")
        }
        var literal: [String: Value] = ["literal": parameter.sample]
        if let unit = parameter.unit { literal["unit"] = .string(unit) }
        plain[name] = .object(literal)
      }
      let call = DefinitionFunction.Call(alias: step.id, binding: binding, arguments: plain)
      _ = try mapDefinitionCall(
        call, caller: descriptor, target: targetDescriptor,
        arguments: nil, validateOnly: true)
      previous[step.id] = target
    }
  }

  func workflowArguments(
    _ step: DefinitionWorkflow.Step, descriptor: DefinitionDescriptor,
    supplied: Value, outputs: [String: Value]
  ) throws -> Value {
    guard let binding = step.binding else { return .object([:]) }
    var mappings = step.arguments
    for (name, mapping) in step.arguments where mapping.object["step"] != nil {
      guard let output = outputs[mapping["step"].text], output["result"].string != nil else {
        throw SevraError("workflow_mapping", "The prior scalar result is not complete.")
      }
      var literal: [String: Value] = ["literal": output["result"]]
      if let unit = mapping.object["unit"] { literal["unit"] = unit }
      mappings[name] = .object(literal)
    }
    let target = try resolveDefinition(binding)
    let result = try mapDefinitionCall(
      .init(alias: step.id, binding: binding, arguments: mappings),
      caller: descriptor, target: DefinitionDescriptor(target.content), arguments: supplied.object)
    return .object(result)
  }
}
