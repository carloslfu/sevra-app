import Foundation

public struct ApplicationDefinition: Codable, Identifiable, Sendable {
  public let id: String
  public let logicalID: String
  public let version: Int
  public let previousID: String?
  public let kind: String
  public let title: String
  public let description: String
  public let parameters: Value
  public let payload: Value
  public let sourceID: String
  public let created: String

  public var content: Value {
    .object([
      "kind": .string(kind), "title": .string(title), "description": .string(description),
      "parameters": parameters, "payload": payload,
    ])
  }
  init(_ row: [String: Value]) throws {
    guard let id = row["id"]?.string, UUID(uuidString: id) != nil,
      let logical = row["logical_id"]?.string, UUID(uuidString: logical) != nil,
      let version = row["version"]?.int, (1...1_000_000_000).contains(version),
      row["version"] == .number(Double(version)),
      row["previous_id"] == .null
        || row["previous_id"]?.string.flatMap(UUID.init(uuidString:)) != nil,
      let kind = row["kind"]?.string,
      ["function", "query", "action", "form", "workflow"].contains(kind),
      let title = row["title"]?.string, let description = row["description"]?.string,
      let parameters = row["parameters"]?.string, let payload = row["payload"]?.string,
      let source = row["source_id"]?.string, UUID(uuidString: source) != nil,
      let created = row["created"]?.string
    else {
      throw SevraError("definition_integrity", "The saved application definition is malformed.")
    }
    self.id = id
    logicalID = logical
    self.version = version
    previousID = row["previous_id"]?.string
    self.kind = kind
    self.title = title
    self.description = description
    self.parameters = try Value.parse(parameters)
    self.payload = try Value.parse(payload)
    sourceID = source
    self.created = created
    _ = try DefinitionDescriptor(content)
  }
}

func definitionObject(_ value: Value, keys: Set<String>) throws -> [String: Value] {
  guard case .object(let object) = value, Set(object.keys).isSubset(of: keys) else {
    throw SevraError("definition", "Use a typed application definition with known fields.")
  }
  return object
}

struct DefinitionParameter {
  let id: String
  let label: String
  let type: String
  let required: Bool
  let unit: String?
  let defaultValue: Value?
  let choices: [String]
  let minimum: Decimal?
  let maximum: Decimal?
  let fields: [DefinitionParameter]
  let maxEntries: Int?

  init(_ value: Value, depth: Int = 0) throws {
    try require(depth <= 1, "definition_parameter", "Nested repeating entries are unsupported.")
    let o = try definitionObject(
      value,
      keys: [
        "id", "label", "type", "required", "unit", "default", "choices", "min", "max", "fields",
        "maxEntries",
      ])
    guard let id = o["id"]?.string,
      id.range(of: "^[A-Za-z_][A-Za-z0-9_]{0,63}\\z", options: .regularExpression) != nil,
      !id.hasPrefix("_sevra_"), let label = o["label"]?.string,
      !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, label.utf8.count <= 256,
      let type = o["type"]?.string,
      ["text", "decimal", "boolean", "date", "item", "choice", "entries"].contains(type),
      case .bool(let required) = o["required"]
    else {
      throw SevraError(
        "definition_parameter", "A parameter needs an ID, label, type and required flag.")
    }
    if let unit = o["unit"] {
      try require(
        type == "decimal" && unit.string != nil && !unit.text.isEmpty
          && unit.text.utf8.count <= 100,
        "definition_unit", "Only decimal parameters take a nonempty unit.")
    }
    self.id = id
    self.label = label
    self.type = type
    self.required = required
    unit = o["unit"]?.string
    defaultValue = o["default"]
    if type == "entries" {
      guard depth == 0, case .array(let rawFields) = o["fields"],
        (1...12).contains(rawFields.count), let maxEntries = o["maxEntries"]?.int,
        o["maxEntries"] == .number(Double(maxEntries)), (1...50).contains(maxEntries)
      else {
        throw SevraError(
          "definition_parameter", "Declare 1 to 12 entry fields and a limit from 1 to 50.")
      }
      fields = try rawFields.map { try DefinitionParameter($0, depth: depth + 1) }
      try require(
        Set(fields.map(\.id)).count == fields.count,
        "definition_parameter", "Entry field IDs must be distinct.")
      self.maxEntries = maxEntries
    } else {
      try require(
        o["fields"] == nil && o["maxEntries"] == nil,
        "definition_parameter", "Only repeating entries declare fields and a limit.")
      fields = []
      maxEntries = nil
    }
    if let raw = o["choices"] {
      guard type == "choice", case .array(let list) = raw,
        (1...100).contains(list.count),
        list.allSatisfy({ $0.string != nil && !$0.text.isEmpty && $0.text.utf8.count <= 256 }),
        Set(list.map(\.text)).count == list.count
      else {
        throw SevraError("definition_parameter", "A choice needs 1 to 100 distinct text options.")
      }
      choices = list.map(\.text)
    } else {
      try require(type != "choice", "definition_parameter", "Declare the available choices.")
      choices = []
    }
    func bound(_ key: String) throws -> Decimal? {
      guard let value = o[key] else { return nil }
      try require(
        type == "decimal" && value.string != nil, "definition_parameter",
        "Bounds are decimal strings.")
      return try Numbers.decimal(value.text)
    }
    minimum = try bound("min")
    maximum = try bound("max")
    if let minimum, let maximum {
      try require(minimum <= maximum, "definition_parameter", "Minimum exceeds maximum.")
    }
    if let defaultValue { _ = try normalize(defaultValue) }
  }

  func normalize(_ value: Value) throws -> Value {
    if value == .null {
      try require(!required, "definition_input", "Enter a value for " + label + ".")
      return .null
    }
    switch type {
    case "entries":
      guard case .array(let rows) = value, (1...(maxEntries ?? 0)).contains(rows.count) else {
        throw SevraError(
          "definition_input", label + " needs at least one entry within its declared limit.")
      }
      return .array(
        try rows.enumerated().map { index, row in
          guard case .object(let raw) = row, Set(raw.keys).isSubset(of: fields.map(\.id)) else {
            throw SevraError(
              "definition_input", label + " entry \(index + 1) has undeclared fields.")
          }
          var normalized: [String: Value] = [:]
          for field in fields {
            guard let supplied = raw[field.id] ?? field.defaultValue else {
              try require(
                !field.required, "definition_input",
                label + " entry \(index + 1) needs " + field.label + ".")
              continue
            }
            normalized[field.id] = try field.normalize(supplied)
          }
          return .object(normalized)
        })
    case "decimal":
      try require(value.string != nil, "definition_input", label + " needs a decimal string.")
      let number = try Numbers.decimal(value.text)
      try require(
        minimum.map { number >= $0 } ?? true, "definition_input", label + " is below its minimum.")
      try require(
        maximum.map { number <= $0 } ?? true, "definition_input", label + " exceeds its maximum.")
      return .string(Numbers.string(number))
    case "boolean":
      guard case .bool = value else {
        throw SevraError("definition_input", label + " needs true or false.")
      }
    case "date":
      try require(value.string != nil, "definition_input", label + " needs an ISO date.")
      // Same explicit date semantics as managed stored columns.
      return .string(try BusinessTime.normalized(value.text))
    case "choice":
      try require(
        value.string != nil && choices.contains(value.text), "definition_input",
        "Choose an option for " + label + ".")
    case "item":
      try require(
        value.string.flatMap(UUID.init(uuidString:)) != nil, "definition_input",
        label + " needs an exact local item version.")
    default:
      try require(
        value.string != nil && value.text.utf8.count <= 16_384, "definition_input",
        label + " needs text of at most 16 KiB.")
    }
    return value
  }
  var sample: Value {
    if let defaultValue, defaultValue != .null { return defaultValue }
    switch type {
    case "decimal": return .string(Numbers.string(minimum ?? maximum ?? 1))
    case "entries":
      return .array([.object(Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.sample) }))])
    case "boolean": return .bool(false)
    case "date": return .string("2026-01-01T00:00:00.000Z")
    case "choice": return .string(choices[0])
    default: return .string("")
    }
  }
}

struct DefinitionDescriptor {
  let value: Value
  let kind: String
  let title: String
  let description: String
  let parameters: [DefinitionParameter]
  let payload: Value
  init(_ value: Value) throws {
    try require(
      try value.json().utf8.count <= 64_000, "definition_limit", "Definition exceeds 64,000 bytes.")
    let o = try definitionObject(
      value, keys: ["kind", "title", "description", "parameters", "payload"])
    guard let kind = o["kind"]?.string,
      ["function", "query", "action", "form", "workflow"].contains(kind),
      let title = o["title"]?.string,
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      title.utf8.count <= 2048, let description = o["description"]?.string,
      description.utf8.count <= 8192, case .array(let raw) = o["parameters"], raw.count <= 32,
      let payload = o["payload"]
    else {
      throw SevraError(
        "definition",
        "Declare a function, query, action, form or workflow, title, description, parameters and payload."
      )
    }
    self.value = value
    self.kind = kind
    self.title = title
    self.description = description
    parameters = try raw.map { try DefinitionParameter($0) }
    try require(
      Set(parameters.map(\.id)).count == parameters.count, "definition_parameter",
      "Parameter IDs must be distinct.")
    self.payload = payload
  }
}
