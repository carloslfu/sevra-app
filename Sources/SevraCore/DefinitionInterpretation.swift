import Foundation

/// Structured interpretation is data, never executable authority. Model adapters
/// receive this host-owned schema without workbook tools.
struct DefinitionInterpretation {
  let instruction: String
  let evidence: [String]
  let outputs: [DefinitionParameter]
  let rawOutputs: Value
  let meaning: String
  let scenario: String

  init(_ descriptor: DefinitionDescriptor) throws {
    let p = try definitionObject(
      descriptor.payload, keys: ["instruction", "evidence", "outputs", "meaning", "scenario"])
    guard let instruction = p["instruction"]?.string,
      !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      instruction.utf8.count <= 8192,
      case .array(let evidence) = p["evidence"], (1...8).contains(evidence.count),
      evidence.allSatisfy({ $0.string != nil }), Set(evidence.map(\.text)).count == evidence.count,
      case .array(let raw) = p["outputs"], (1...32).contains(raw.count),
      let meaning = p["meaning"]?.string,
      ["actual", "estimate", "plan", "commitment", "rule", "assumption"].contains(meaning),
      let scenario = p["scenario"]?.string, !scenario.isEmpty, scenario.utf8.count <= 256
    else {
      throw SevraError(
        "interpretation_definition",
        "Declare instruction, exact evidence parameters, typed outputs, meaning and scenario.")
    }
    for value in evidence {
      try require(
        descriptor.parameters.contains { $0.id == value.text && $0.type == "item" && $0.required },
        "interpretation_definition", "Evidence must name a required item parameter.")
    }
    let outputs = try raw.map { try DefinitionParameter($0) }
    try require(
      Set(outputs.map(\.id)).count == outputs.count, "interpretation_definition",
      "Output names must be distinct.")
    for output in outputs {
      try require(
        output.defaultValue == nil && output.fields.allSatisfy { $0.defaultValue == nil },
        "interpretation_definition", "Interpretations cannot default missing facts.")
    }
    self.instruction = instruction
    self.evidence = evidence.map(\.text)
    self.outputs = outputs
    rawOutputs = .array(raw)
    self.meaning = meaning
    self.scenario = scenario
  }

  func responseSchema(itemIDs: [String]) -> Value {
    func object(_ properties: [String: Value], required: [String]) -> Value {
      .object([
        "type": .string("object"), "properties": .object(properties),
        "required": .array(required.map(Value.string)), "additionalProperties": .bool(false),
      ])
    }
    func field(_ parameter: DefinitionParameter) -> Value {
      var s: [String: Value]
      switch parameter.type {
      case "entries":
        s = [
          "type": .string("array"), "minItems": .number(1),
          "maxItems": .number(Double(parameter.maxEntries!)),
          "items": object(
            Dictionary(uniqueKeysWithValues: parameter.fields.map { ($0.id, field($0)) }),
            required: parameter.fields.filter(\.required).map(\.id)),
        ]
      case "boolean": s = ["type": .string("boolean")]
      case "choice":
        s = ["type": .string("string"), "enum": .array(parameter.choices.map(Value.string))]
      case "item": s = ["type": .string("string"), "enum": .array(itemIDs.map(Value.string))]
      case "decimal":
        s = [
          "type": .string("string"), "minLength": .number(1), "maxLength": .number(128),
          "description": .string(
            "Exact decimal string such as 5 or -2.50, using a period, no units or other punctuation."
              + (parameter.unit.map { " Unit: " + $0 + "." } ?? "")),
        ]
      case "date":
        s = [
          "type": .string("string"), "minLength": .number(10), "maxLength": .number(128),
          "description": .string("Valid ISO 8601 date or explicit date-time."),
        ]
      default: s = ["type": .string("string"), "maxLength": .number(16_384)]
      }
      if !parameter.required {
        s["type"] = .array([s["type"]!, .string("null")])
        if let choices = s["enum"] { s["enum"] = .array(choices.array + [.null]) }
      }
      return .object(s)
    }
    return object(
      [
        "state": .object([
          "type": .string("string"), "enum": .array([.string("ready"), .string("needs_input")]),
        ]),
        "values": object(
          Dictionary(uniqueKeysWithValues: outputs.map { ($0.id, field($0)) }), required: []),
        "citations": .object([
          "type": .string("array"), "maxItems": .number(32),
          "items": object(
            [
              "field": .object([
                "type": .string("string"), "enum": .array(outputs.map { .string($0.id) }),
              ]),
              "itemID": .object([
                "type": .string("string"), "enum": .array(itemIDs.map(Value.string)),
              ]),
              "quote": .object([
                "type": .string("string"), "minLength": .number(1), "maxLength": .number(4096),
              ]),
            ], required: ["field", "itemID", "quote"]),
        ]),
        "issues": .object([
          "type": .string("array"), "maxItems": .number(16),
          "items": .object([
            "type": .string("string"), "minLength": .number(1), "maxLength": .number(2048),
          ]),
        ]),
      ], required: ["state", "values", "citations", "issues"])
  }

  func validateResponse(_ response: Value, evidence: [Value]) throws -> Value {
    let o = try definitionObject(response, keys: ["state", "values", "citations", "issues"])
    guard Set(o.keys) == Set(["state", "values", "citations", "issues"]),
      ["ready", "needs_input"].contains(response["state"].text),
      case .object(let raw) = response["values"],
      Set(raw.keys).isSubset(of: outputs.map(\.id)),
      case .array(let citations) = response["citations"], citations.count <= 32,
      case .array(let issues) = response["issues"], issues.count <= 16,
      issues.allSatisfy({ $0.string != nil && !$0.text.isEmpty && $0.text.utf8.count <= 2048 }),
      try response.json().utf8.count <= 65_536
    else {
      throw SevraError("interpretation_output", "Invalid structured interpretation response.")
    }
    let unresolved = response["state"] == .string("needs_input")
    if unresolved {
      try require(
        raw.isEmpty && !issues.isEmpty, "interpretation_output",
        "Unresolved interpretations must state issues without invented values.")
    }
    var normalized: [String: Value] = [:]
    for output in outputs where !unresolved {
      guard let value = raw[output.id] else {
        try require(
          !output.required, "interpretation_output",
          "Missing required interpretation output: " + output.label)
        continue
      }
      normalized[output.id] = try output.normalize(value)
    }
    var cited = Set<String>()
    for citation in citations {
      let c = try definitionObject(citation, keys: ["field", "itemID", "quote"])
      guard c.count == 3, let field = c["field"]?.string,
        unresolved ? outputs.contains(where: { $0.id == field }) : normalized[field] != nil,
        let id = c["itemID"]?.string, let quote = c["quote"]?.string,
        !quote.isEmpty, quote.utf8.count <= 4096,
        let original = evidence.first(where: { $0["id"] == .string(id) }),
        original["content"].text.contains(quote)
      else {
        throw SevraError(
          "interpretation_citation",
          "Cite an exact quotation from this request's retained evidence.")
      }
      cited.insert(field)
    }
    try require(
      unresolved || Set(normalized.keys) == cited, "interpretation_citation",
      "Every returned field needs an original evidence quotation.")
    func checkItems(_ parameter: DefinitionParameter, _ value: Value) throws {
      if parameter.type == "item", value != .null {
        try require(
          evidence.contains { $0["id"] == value }, "interpretation_output",
          "Item outputs must refer to the supplied evidence.")
      }
      if parameter.type == "entries" {
        for row in value.array {
          for field in parameter.fields { try checkItems(field, row[field.id]) }
        }
      }
    }
    for output in outputs { try checkItems(output, normalized[output.id] ?? .null) }
    var result = response.object
    result["values"] = .object(normalized)
    return .object(result)
  }
}
