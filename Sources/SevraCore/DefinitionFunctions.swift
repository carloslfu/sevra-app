import Foundation

struct DefinitionBinding {
  let mode: String
  let target: String
  init(_ value: Value) throws {
    let o = try definitionObject(value, keys: ["mode", "logicalID", "versionID"])
    guard let mode = o["mode"]?.string, ["live", "exact"].contains(mode),
      let target = o[mode == "live" ? "logicalID" : "versionID"]?.string,
      UUID(uuidString: target) != nil,
      o[mode == "live" ? "versionID" : "logicalID"] == nil
    else {
      throw SevraError("definition_binding", "Choose one live logical ID or exact version ID.")
    }
    self.mode = mode
    self.target = target
  }
}

struct DefinitionFunction {
  struct Call {
    let alias: String
    let binding: DefinitionBinding
    let arguments: [String: Value]
  }
  let expression: Expression
  let calls: [Call]
  let unit: String?
  let rounding: Int?

  init(_ descriptor: DefinitionDescriptor) throws {
    let o = try definitionObject(
      descriptor.payload, keys: ["expression", "calls", "unit", "rounding"])
    guard let formula = o["expression"]?.string else {
      throw SevraError("definition_function", "Declare a bounded Decimal expression.")
    }
    if let raw = o["unit"] {
      try require(
        raw.string != nil && !raw.text.isEmpty && raw.text.utf8.count <= 100,
        "definition_unit", "Declare a nonempty output unit or omit it.")
    }
    unit = o["unit"]?.string
    if let raw = o["rounding"] {
      guard let places = raw.int, raw == .number(Double(places)), (-28...28).contains(places) else {
        throw SevraError("definition_function", "Rounding supports integer places from -28 to 28.")
      }
      rounding = places
    } else {
      rounding = nil
    }
    if let raw = o["calls"] {
      guard case .array(let list) = raw, list.count <= 16 else {
        throw SevraError("definition_limit", "A function supports at most 16 declared calls.")
      }
      calls = try list.map { value in
        let c = try definitionObject(value, keys: ["alias", "binding", "arguments"])
        guard let alias = c["alias"]?.string,
          alias.range(of: "^[A-Za-z_][A-Za-z0-9_]{0,63}\\z", options: .regularExpression) != nil,
          !alias.hasPrefix("_sevra_"), let binding = c["binding"], let arguments = c["arguments"],
          case .object(let mappings) = arguments, mappings.count <= 32
        else {
          throw SevraError(
            "definition_function", "A call needs an alias, binding and argument mappings.")
        }
        return try Call(alias: alias, binding: DefinitionBinding(binding), arguments: mappings)
      }
    } else {
      calls = []
    }
    let parameterIDs = Set(descriptor.parameters.map(\.id))
    try require(
      Set(calls.map(\.alias)).count == calls.count
        && parameterIDs.isDisjoint(with: calls.map(\.alias)),
      "definition_function", "Call aliases must be distinct from parameters and each other.")
    var parser = try Formula(formula)
    expression = try parser.parse()
    try validate(
      expression,
      names: Set(
        descriptor.parameters.filter { ["decimal", "boolean"].contains($0.type) }.map(\.id)
      ).union(calls.map(\.alias)))
  }

  /// A long sum parses in a loop but evaluates to its depth, so refuse here what can never run.
  private func validate(_ node: Expression, names: Set<String>, depth: Int = 0) throws {
    try require(depth < 64, "formula_limit", "This formula exceeds its evaluation depth budget.")
    switch node {
    case .number: break
    case .name(let name):
      try require(
        names.contains(name), "definition_function", "Unknown numeric parameter or call: " + name)
    case .range:
      throw SevraError(
        "definition_function", "A reusable function cannot read ambient table ranges.")
    case .negate(let child): try validate(child, names: names, depth: depth + 1)
    case .binary(_, let a, let b):
      try validate(a, names: names, depth: depth + 1)
      try validate(b, names: names, depth: depth + 1)
    case .call(let name, let args):
      let valid: Bool
      switch name {
      case "IF": valid = args.count == 3
      case "ROUND": valid = args.count == 2
      case "COUNT": valid = args.count <= 64
      case "SUM", "AVERAGE", "MIN", "MAX": valid = (1...64).contains(args.count)
      default: valid = false
      }
      try require(
        valid, "definition_function", "Unknown function or invalid argument count: " + name)
      for argument in args { try validate(argument, names: names, depth: depth + 1) }
    }
  }
}

final class DefinitionEvaluation {
  var resolved: [String: ApplicationDefinition] = [:]
  var active: Set<String> = []
  var work = 0
  let cancellation: Cancellation
  init(_ cancellation: Cancellation) { self.cancellation = cancellation }
  func enter(_ definition: ApplicationDefinition, depth: Int) throws {
    try cancellation.check()
    work += 1
    try require(
      depth < 16 && work <= 128, "definition_limit",
      "Definition evaluation exceeds its depth or work budget.")
    try require(
      active.insert(definition.id).inserted, "definition_cycle",
      "The effective definition graph contains a cycle.")
    resolved[definition.id] = definition
  }
}

extension Workbook {
  func resolveDefinition(_ binding: DefinitionBinding) throws -> ApplicationDefinition {
    let resolved = try applicationDefinition(binding.target)
    try require(
      binding.mode == "live" ? resolved.logicalID == binding.target : resolved.id == binding.target,
      "definition_binding",
      "The binding does not identify the requested logical or exact definition.")
    return resolved
  }

  func validateDefinitionItemReferences(_ parameter: DefinitionParameter, _ value: Value) throws {
    if parameter.type == "entries", value != .null {
      for row in value.array {
        for field in parameter.fields {
          if let nested = row.object[field.id] {
            try validateDefinitionItemReferences(field, nested)
          }
        }
      }
    }
    if parameter.type == "item", value != .null {
      try require(
        try item(value.text).id == value.text, "definition_input", "Use exact local item versions.")
    }
  }
  func definitionArguments(_ descriptor: DefinitionDescriptor, _ value: Value) throws -> [String:
    Value]
  {
    guard case .object(let raw) = value else {
      throw SevraError("definition_input", "Arguments must be an object.")
    }
    try require(
      try value.json().utf8.count <= 64_000
        && Set(raw.keys).isSubset(of: descriptor.parameters.map(\.id)),
      "definition_input", "Arguments exceed limits or contain undeclared fields.")
    var result: [String: Value] = [:]
    for parameter in descriptor.parameters {
      guard let supplied = raw[parameter.id] ?? parameter.defaultValue else {
        try require(
          !parameter.required, "definition_input", "Enter a value for " + parameter.label + ".")
        continue
      }
      let normalized = try parameter.normalize(supplied)
      try validateDefinitionItemReferences(parameter, normalized)
      result[parameter.id] = normalized
    }
    return result
  }

  func mapDefinitionCall(
    _ call: DefinitionFunction.Call, caller: DefinitionDescriptor, target: DefinitionDescriptor,
    arguments: [String: Value]?, validateOnly: Bool = false
  ) throws -> [String: Value] {
    let parameters = Dictionary(uniqueKeysWithValues: target.parameters.map { ($0.id, $0) })
    try require(
      Set(call.arguments.keys).isSubset(of: parameters.keys), "definition_input",
      "A call maps an unknown target parameter.")
    var result: [String: Value] = [:]
    for (name, raw) in call.arguments {
      let o = try definitionObject(raw, keys: ["parameter", "literal", "unit"])
      let parameter = parameters[name]!
      let mapped: Value?
      if let from = o["parameter"]?.string {
        try require(
          o["literal"] == nil && o["unit"] == nil, "definition_input",
          "A parameter mapping inherits its declared unit.")
        guard let source = caller.parameters.first(where: { $0.id == from }) else {
          throw SevraError("definition_input", "A call maps an undeclared caller parameter.")
        }
        try require(
          source.type == parameter.type && source.unit == parameter.unit
            && (source.type != "entries" || source.signature == parameter.signature)
            && (source.type != "choice"
              || Set(source.choices).isSubset(of: Set(parameter.choices))),
          "definition_unit", "Caller and callee parameter types/units/choices must match.")
        mapped = validateOnly ? nil : arguments?[from]
      } else if let literal = o["literal"] {
        try require(
          o["parameter"] == nil && o["unit"] == parameter.unit.map(Value.string),
          "definition_unit", "A literal mapping must state the target unit exactly.")
        mapped = try parameter.normalize(literal)
        try validateDefinitionItemReferences(parameter, literal)
      } else {
        throw SevraError("definition_input", "Map a parameter or a literal explicitly.")
      }
      if let mapped { result[name] = mapped }
    }
    for parameter in target.parameters where parameter.required && parameter.defaultValue == nil {
      try require(
        call.arguments[parameter.id] != nil, "definition_input",
        "Map required call parameter " + parameter.label + ".")
    }
    return result
  }

  func evaluateFunction(
    _ definition: ApplicationDefinition, arguments: Value, state: DefinitionEvaluation, depth: Int
  ) throws -> Value {
    try state.enter(definition, depth: depth)
    defer { state.active.remove(definition.id) }
    let descriptor = try DefinitionDescriptor(definition.content)
    try require(
      descriptor.kind == "function", "definition_kind",
      "A function call cannot run a query or action.")
    let function = try DefinitionFunction(descriptor)
    let values = try definitionArguments(descriptor, arguments)
    let numeric = values.mapValues { value -> Value in
      if case .bool(let flag) = value { return .string(flag ? "1" : "0") }
      return value
    }
    var results: [String: Decimal] = [:]
    let number = try function.expression.evaluate(values: numeric) { alias in
      if let cached = results[alias] { return cached }
      guard let call = function.calls.first(where: { $0.alias == alias }) else {
        throw SevraError("missing_value", "No value for " + alias + ".")
      }
      let target = try self.resolveDefinition(call.binding)
      let targetDescriptor = try DefinitionDescriptor(target.content)
      let mapped = try self.mapDefinitionCall(
        call, caller: descriptor, target: targetDescriptor, arguments: values)
      let output = try self.evaluateFunction(
        target, arguments: .object(mapped), state: state, depth: depth + 1)
      let result = try Numbers.decimal(output.text)
      results[alias] = result
      return result
    }
    var output = number
    if let places = function.rounding {
      var input = output
      NSDecimalRound(&output, &input, places, .plain)
    }
    return .string(Numbers.string(output))
  }
}
