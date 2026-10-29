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
        let kind = o["kind"]?.string, ["evaluate", "action", "review", "interpret"].contains(kind)
      else {
        throw SevraError(
          "workflow_definition", "Use distinct named evaluate/action/review/interpret steps.")
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
          _ = try definitionObject(mapping, keys: ["step", "field", "unit"])
          try require(
            mapping["step"].string != nil
              && ["evaluate", "interpret"].contains(seen[mapping["step"].text] ?? ""),
            "workflow_mapping",
            "A result mapping must name a preceding evaluation or interpretation.")
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
        (step.kind == "evaluate"
          ? ["function", "query"]
          : step.kind == "interpret" ? ["interpretation"] : ["action", "form"]).contains(
            target.kind),
        "workflow_binding", "The workflow step targets the wrong definition kind.")
      if target.kind == "form" {
        try require(
          try DefinitionForm(DefinitionDescriptor(target.content)).targetKind == "action",
          "workflow_binding",
          "A workflow action step cannot launch another workflow through a form.")
      }
      if !historical {
        try validateDefinitionGraph(target, state: DefinitionEvaluation(.init()), depth: 0)
      }
      try exactClosure(target, depth: 0)
      let targetDescriptor = try DefinitionDescriptor(target.content)
      var plain = step.arguments
      for (name, mapping) in step.arguments where mapping.object["step"] != nil {
        guard let source = previous[mapping["step"].text],
          let parameter = targetDescriptor.parameters.first(where: { $0.id == name }),
          mapping.object["unit"] == parameter.unit.map(Value.string)
        else {
          throw SevraError(
            "workflow_mapping", "Map an existing prior output with its declared unit.")
        }
        if source.kind == "interpretation" {
          let interpretation = try DefinitionInterpretation(DefinitionDescriptor(source.content))
          guard let field = mapping["field"].string,
            let output = interpretation.outputs.first(where: { $0.id == field }),
            output.type == parameter.type && output.unit == parameter.unit,
            !parameter.required || output.required,
            output.type != "entries" || output.signature == parameter.signature,
            output.type != "choice" || Set(output.choices).isSubset(of: parameter.choices)
          else {
            throw SevraError(
              "workflow_mapping",
              "Interpretation fields must match target types, units and required signatures.")
          }
        } else {
          try require(
            source.kind == "function" && parameter.type == "decimal"
              && mapping.object["field"] == nil
              && (try DefinitionFunction(DefinitionDescriptor(source.content))).unit
                == parameter.unit,
            "workflow_mapping", "Map only a prior scalar function with the same decimal unit.")
        }
        plain.removeValue(forKey: name)
      }
      var remaining = target.content.object
      remaining["parameters"] = .array(
        target.parameters.array.filter { step.arguments[$0["id"].text]?.object["step"] == nil })
      let call = DefinitionFunction.Call(alias: step.id, binding: binding, arguments: plain)
      _ = try mapDefinitionCall(
        call, caller: descriptor, target: DefinitionDescriptor(.object(remaining)),
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
      guard let output = outputs[mapping["step"].text] else {
        throw SevraError("workflow_mapping", "The prior result is not complete.")
      }
      let value: Value
      if let field = mapping["field"].string {
        try require(
          output["kind"] == .string("interpretation")
            && output["response"]["state"] == .string("ready")
            && output["response"]["values"].object[field] != nil, "workflow_mapping",
          "The prior interpretation field is unresolved.")
        value = output["response"]["values"][field]
      } else {
        try require(
          output["result"].string != nil, "workflow_mapping",
          "The prior scalar result is incomplete.")
        value = output["result"]
      }
      var literal: [String: Value] = ["literal": value]
      if let unit = mapping.object["unit"] { literal["unit"] = unit }
      mappings[name] = .object(literal)
    }
    let target = try resolveDefinition(binding)
    let result = try mapDefinitionCall(
      .init(alias: step.id, binding: binding, arguments: mappings),
      caller: descriptor, target: DefinitionDescriptor(target.content), arguments: supplied.object)
    return .object(result)
  }

  /// Scalar calculations cannot erase the semantic provenance of model-derived
  /// inputs before a later business proposal.
  func workflowInterpretationInputs(
    _ step: DefinitionWorkflow.Step, workflow: DefinitionWorkflow, outputs: [String: Value]
  ) throws -> [Item] {
    var visited = Set<String>()
    var records: [Item] = []
    func visit(_ current: DefinitionWorkflow.Step) throws {
      for mapping in current.arguments.values {
        guard let previousID = mapping["step"].string, visited.insert(previousID).inserted,
          let previous = workflow.steps.first(where: { $0.id == previousID })
        else { continue }
        if previous.kind == "interpret", let recordID = outputs[previousID]?["recordID"].string {
          records.append(try item(recordID))
        }
        try visit(previous)
      }
    }
    try visit(step)
    return records.sorted { $0.id < $1.id }
  }
}
