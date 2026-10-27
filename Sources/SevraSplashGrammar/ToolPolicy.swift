import CoreFoundation
import Foundation
import SevraSplash
import SevraSplashText

/// Sevra's bounded, app-owned tool schema dialect. It preserves JSON Schema's
/// default open objects explicitly before Splash strict normalization. Workbook
/// rows and record data must not silently become empty closed objects.
/// Grammar layout follows pinned Splash server/tool_schema.py; see its retained
/// Apache-2.0 license in integration/licenses. Unsupported keywords fail setup.
public final class SplashToolPolicy {
  public enum Choice {
    case auto, required
    case named(String)
  }
  private let schemas: [String: [String: Any]]
  public let toolsJSON: Data
  public let grammar: String
  public let outputTools: [SplashOutputTool]
  private static let types: Set<String> = [
    "string", "integer", "number", "boolean", "object", "array", "null",
  ]
  private static let whitespace = #"[ \t\n\r]{0,64}"#

  public init(toolsJSON: Data, choice: Choice = .required, thinking: Bool = false) throws {
    guard toolsJSON.count <= 2 * 1024 * 1024,
      let input = try JSONSerialization.jsonObject(with: toolsJSON) as? [[String: Any]],
      !input.isEmpty, input.count <= 128
    else { throw SplashError("Invalid workbook tool declarations") }
    var normalized: [[String: Any]] = []
    var schemas: [String: [String: Any]] = [:]
    var nodes = 0
    for tool in input {
      guard tool["type"] as? String == "function",
        let function = tool["function"] as? [String: Any],
        let name = function["name"] as? String, Self.validName(name), schemas[name] == nil,
        let description = function["description"] as? String,
        let schema = try Self.normalize(function["parameters"] as Any, depth: 0, nodes: &nodes)
          as? [String: Any],
        schema["type"] as? String == "object",
        let properties = schema["properties"] as? [String: Any],
        properties.count <= 128, properties.keys.allSatisfy(Self.validName),
        (schema["additionalProperties"] as? NSNumber).map({
          CFGetTypeID($0) == CFBooleanGetTypeID() && !$0.boolValue
        }) == true
      else { throw SplashError("Workbook tools require named closed root objects") }
      schemas[name] = schema
      normalized.append([
        "type": "function",
        "function": [
          "name": name, "description": description,
          "parameters": schema, "strict": true,
        ],
      ])
    }
    self.toolsJSON = try Self.json(normalized)
    let selected: [String]
    switch choice {
    case .named(let name):
      guard schemas[name] != nil else { throw SplashError("Required tool is unavailable") }
      selected = [name]
    default: selected = normalized.map { ($0["function"] as! [String: Any])["name"] as! String }
    }
    self.schemas = schemas.filter { selected.contains($0.key) }
    outputTools = try selected.map { name in
      let properties = schemas[name]!["properties"] as! [String: Any]
      var parameters: [String: Set<String>] = [:]
      for (key, schema) in properties {
        guard let node = schema as? [String: Any], let types = Self.typeNames(node), !types.isEmpty
        else {
          throw SplashError("Workbook parameters need explicit types")
        }
        parameters[key] = types
      }
      return SplashOutputTool(name: name, parameters: parameters)
    }
    var side: [[String: String]] = []
    var calls: [String] = []
    for (index, name) in selected.enumerated() {
      side.append([
        "name": "arguments_\(index)", "lark_grammar": try Self.arguments(schemas[name]!),
      ])
      calls.append(
        "call_\(index): <tool_call> \(try Self.quote("\n<function=\(name)>\n")) @arguments_\(index) \(try Self.quote("</function>\n")) </tool_call>"
      )
    }
    let alternatives = "(" + selected.indices.map { "call_\($0)" }.joined(separator: " | ") + ")"
    let body: String
    if case .auto = choice {
      body = "TEXT (\(alternatives) WS)?"
    } else {
      body = "WS \(alternatives) WS"
    }
    var main = ["%llguidance {}", "start: \(thinking ? "think " : "")\(body)"]
    if thinking { main.append("think: TEXT <[248069]>") }
    main += calls
    main += [
      "WS: /\(Self.whitespace)/", #"TEXT: /(?s:.*)/ & ~/(?s:.*)(<tool_call>|<\/think>)(?s:.*)/"#,
    ]
    side.insert(
      ["name": "tool_output", "lark_grammar": main.joined(separator: "\n") + "\n"], at: 0)
    let encoded = try Self.json(["grammars": side])
    guard encoded.count <= 8 * 1024 * 1024 else {
      throw SplashError("Workbook tool grammar exceeds its limit")
    }
    grammar = String(decoding: encoded, as: UTF8.self)
  }

  /// Values suitable for the exact maintained prompt template, sharing the same
  /// normalized schema the mask compiler and terminal validator use.
  public func promptTools() throws -> [[String: any Sendable]] {
    func sendable(_ value: Any) throws -> any Sendable {
      if let value = value as? String { return value }
      if let value = value as? NSNumber {
        if CFGetTypeID(value) == CFBooleanGetTypeID() { return value.boolValue }
        if ["f", "d"].contains(String(cString: value.objCType)) { return value.doubleValue }
        return value.int64Value
      }
      if value is NSNull { return NSNull() }
      if let value = value as? [String: Any] { return try value.mapValues(sendable) }
      if let value = value as? [Any] { return try value.map(sendable) }
      throw SplashError("Unsupported workbook schema value")
    }
    return try (JSONSerialization.jsonObject(with: toolsJSON) as! [[String: Any]]).map {
      try $0.mapValues(sendable)
    }
  }

  /// Checks the complete schema after successful native completion. This does
  /// not replace workbook evidence, domain or action-permission checks.
  public func validate(_ call: SplashToolCandidate) throws {
    guard let schema = schemas[call.name], call.arguments.count <= 256 * 1024,
      let arguments = try JSONSerialization.jsonObject(with: call.arguments) as? [String: Any]
    else {
      throw SplashError("Tool candidate is unavailable or malformed")
    }
    var nodes = 0
    try Self.validate(arguments, schema: schema, depth: 0, nodes: &nodes)
  }

  static func validName(_ name: String) -> Bool {
    !name.isEmpty && name.utf8.count <= 256
      && name.utf8.allSatisfy {
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
          || [45, 46, 95].contains($0)
      }
  }
  private static func json(_ value: Any) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
  }
  private static func quote(_ string: String) throws -> String {
    String(decoding: try json(string), as: UTF8.self)
  }

  /// LLGuidance fixes JSON property order to the schema's insertion order.
  /// Put identity/type fields before optional metadata so choosing `id` does
  /// not irreversibly exclude a later formula. The reference receives this same
  /// app-owned ordering; no grammar-library behavior is changed or weakened.
  private static func nestedSchemaJSON(_ value: Any) throws -> String {
    if let object = value as? [String: Any] {
      let fields = try object.keys.sorted().map { key -> String in
        let body: String
        if key == "properties", let properties = object[key] as? [String: Any] {
          let required = (object["required"] as? [String] ?? []).filter { properties[$0] != nil }
          let names = required + properties.keys.filter { !required.contains($0) }.sorted()
          body =
            "{"
            + (try names.map { try quote($0) + ":" + nestedSchemaJSON(properties[$0]!) }).joined(
              separator: ",") + "}"
        } else {
          body = try nestedSchemaJSON(object[key]!)
        }
        return try quote(key) + ":" + body
      }
      return "{" + fields.joined(separator: ",") + "}"
    }
    if let array = value as? [Any] {
      return "[" + (try array.map(nestedSchemaJSON)).joined(separator: ",") + "]"
    }
    return String(decoding: try json(value), as: UTF8.self)
  }
  private static func typeNames(_ node: [String: Any]) -> Set<String>? {
    if let type = node["type"] as? String { return [type] }
    if let types = node["type"] as? [String] { return Set(types) }
    return nil
  }
  private static func normalize(_ schema: Any, depth: Int, nodes: inout Int) throws -> Any {
    nodes += 1
    guard depth <= 24, nodes <= 32768 else {
      throw SplashError("Workbook schema exceeds its structure limit")
    }
    if let value = schema as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() {
      return value.boolValue
    }
    guard var node = schema as? [String: Any] else {
      throw SplashError("Workbook schema is not an object")
    }
    let keywords: Set<String> = [
      "type", "description", "title", "properties", "required", "additionalProperties", "items",
      "minItems", "maxItems", "minLength", "maxLength", "minimum", "maximum", "exclusiveMinimum",
      "exclusiveMaximum", "enum", "const",
    ]
    guard Set(node.keys).isSubset(of: keywords) else {
      throw SplashError("Unsupported workbook schema keyword")
    }
    if let names = typeNames(node) {
      guard !names.isEmpty, names.isSubset(of: types) else {
        throw SplashError("Unsupported workbook schema type")
      }
    } else if node["type"] != nil {
      throw SplashError("Malformed workbook schema type")
    }
    for key in ["description", "title"] where node[key] != nil {
      guard node[key] is String else { throw SplashError("Malformed schema annotation") }
    }
    if let properties = node["properties"] {
      guard let properties = properties as? [String: Any], properties.count <= 128 else {
        throw SplashError("Malformed schema properties")
      }
      node["properties"] = try properties.mapValues {
        try normalize($0, depth: depth + 1, nodes: &nodes)
      }
    }
    if let required = node["required"] {
      guard let required = required as? [String], Set(required).count == required.count,
        required.allSatisfy({ (node["properties"] as? [String: Any])?[$0] != nil })
      else { throw SplashError("Malformed required schema fields") }
    }
    if let additional = node["additionalProperties"] {
      node["additionalProperties"] = try normalize(additional, depth: depth + 1, nodes: &nodes)
    } else if typeNames(node)?.contains("object") == true || node["properties"] != nil {
      node["additionalProperties"] = true
    }
    if let items = node["items"] {
      node["items"] = try normalize(items, depth: depth + 1, nodes: &nodes)
    } else if typeNames(node)?.contains("array") == true {
      node["items"] = true
    }
    for key in [
      "minItems", "maxItems", "minLength", "maxLength", "minimum", "maximum", "exclusiveMinimum",
      "exclusiveMaximum",
    ] {
      if let value = node[key] {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite
        else {
          throw SplashError("Malformed schema numeric bound")
        }
        if key.hasSuffix("Items") || key.hasSuffix("Length") {
          guard number.doubleValue >= 0, number.doubleValue <= 1_000_000,
            number.doubleValue.rounded() == number.doubleValue
          else {
            throw SplashError("Unsupported schema size bound")
          }
        }
      }
    }
    for (minimum, maximum) in [
      ("minItems", "maxItems"), ("minLength", "maxLength"), ("minimum", "maximum"),
    ] {
      if let a = node[minimum] as? NSNumber, let b = node[maximum] as? NSNumber,
        a.compare(b) == .orderedDescending
      {
        throw SplashError("Contradictory schema bounds")
      }
    }
    if let values = node["enum"] {
      guard let values = values as? [Any], !values.isEmpty, values.count <= 256 else {
        throw SplashError("Malformed schema enumeration")
      }
    }
    return node
  }

  private static func arguments(_ schema: [String: Any]) throws -> String {
    let properties = schema["properties"] as! [String: Any]
    let required = Set(schema["required"] as? [String] ?? [])
    var sequence: [String] = []
    var rules: [String] = []
    for (index, name) in properties.keys.sorted().enumerated() {
      guard let value = properties[name] as? [String: Any] else {
        throw SplashError("Tool field schema needs explicit types")
      }
      let rule = "parameter_\(index)"
      let prefix = "\(try quote("<parameter=")) \(try quote(name)) \(try quote(">\n"))"
      var literals: [Any]?
      if let constant = value["const"] {
        literals = [constant]
      } else if let values = value["enum"] as? [Any] {
        literals = values
      } else if typeNames(value) == ["boolean"] {
        literals = [true, false]
      } else if typeNames(value) == ["null"] {
        literals = [NSNull()]
      }
      if let literals {
        var choices: [String] = []
        for literal in literals {
          let text = try literal as? String ?? String(decoding: json(literal), as: UTF8.self)
          guard !text.contains("\n</parameter>\n") else {
            throw SplashError("Tool enumeration conflicts with its XML framing")
          }
          if text.isEmpty {
            let empty = "\(rule)_empty_\(choices.count)"
            rules.append("\(empty):")
            choices.append(empty)
          } else {
            choices.append(try quote(text))
          }
        }
        rules.append(
          "\(rule): \(prefix) (\(choices.joined(separator: " | "))) \(try quote("\n</parameter>\n"))"
        )
      } else if typeNames(value)?.contains("string") == true {
        rules += [
          "\(rule): \(prefix) \(rule)_value",
          "\(rule)_value[suffix=\(try quote("\n</parameter>\n"))]: /(?s:.*)/",
        ]
      } else {
        var compatible = value
        compatible["x-guidance"] = ["lenient": true, "whitespace_pattern": whitespace]
        let json = try nestedSchemaJSON(compatible)
        rules.append("\(rule): \(prefix) (%json \(json)) \(try quote("\n</parameter>\n"))")
      }
      sequence.append(rule + (required.contains(name) ? "" : "?"))
    }
    return "%llguidance {}\nstart:" + sequence.map { " " + $0 }.joined() + "\n"
      + rules.joined(separator: "\n") + "\n"
  }

  private static func validate(_ value: Any, schema: Any, depth: Int, nodes: inout Int) throws {
    nodes += 1
    guard depth <= 32, nodes <= 65536 else {
      throw SplashError("Tool arguments exceed the structure limit")
    }
    if let allowed = schema as? NSNumber, CFGetTypeID(allowed) == CFBooleanGetTypeID() {
      guard allowed.boolValue else { throw SplashError("Tool argument is not allowed") }
      // Even an unconstrained field still obeys the data bounds below.
      try validate(value, schema: [String: Any](), depth: depth, nodes: &nodes)
      return
    }
    let schema = schema as! [String: Any]
    let kind: String
    if value is String {
      kind = "string"
    } else if value is NSNull {
      kind = "null"
    } else if value is [String: Any] {
      kind = "object"
    } else if value is [Any] {
      kind = "array"
    } else if let number = value as? NSNumber {
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        kind = "boolean"
      } else {
        guard number.doubleValue.isFinite else { throw SplashError("Non-finite tool argument") }
        if !["f", "d"].contains(String(cString: number.objCType)),
          number.compare(NSNumber(value: Int64(9_007_199_254_740_991))) == .orderedDescending
            || number.compare(NSNumber(value: Int64(-9_007_199_254_740_991))) == .orderedAscending
        {
          throw SplashError("Tool integer exceeds the workbook's exact range; use a string")
        }
        kind = number.doubleValue.rounded() == number.doubleValue ? "integer" : "number"
      }
    } else {
      throw SplashError("Unsupported tool argument value")
    }
    if let expected = typeNames(schema),
      !expected.contains(kind) && !(kind == "integer" && expected.contains("number"))
    {
      throw SplashError("Tool argument has the wrong type")
    }
    if let constant = schema["const"], !equal(value, constant) {
      throw SplashError("Tool argument differs from its required value")
    }
    if let values = schema["enum"] as? [Any], !values.contains(where: { equal(value, $0) }) {
      throw SplashError("Tool argument is outside its enumeration")
    }
    if let object = value as? [String: Any] {
      let properties = schema["properties"] as? [String: Any] ?? [:]
      guard (schema["required"] as? [String] ?? []).allSatisfy({ object[$0] != nil }) else {
        throw SplashError("Required tool argument is missing")
      }
      for (key, child) in object {
        try validate(
          child, schema: properties[key] ?? schema["additionalProperties"] ?? true,
          depth: depth + 1, nodes: &nodes)
      }
    } else if let array = value as? [Any] {
      try checkSize(array.count, schema: schema, minimum: "minItems", maximum: "maxItems")
      for child in array {
        try validate(child, schema: schema["items"] ?? true, depth: depth + 1, nodes: &nodes)
      }
    } else if let string = value as? String {
      try checkSize(
        string.unicodeScalars.count, schema: schema, minimum: "minLength", maximum: "maxLength")
    } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
      for key in ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"] {
        if let bound = schema[key] as? NSNumber {
          let comparison = number.compare(bound)
          let failed =
            (key == "minimum" && comparison == .orderedAscending)
            || (key == "maximum" && comparison == .orderedDescending)
            || (key == "exclusiveMinimum" && comparison != .orderedDescending)
            || (key == "exclusiveMaximum" && comparison != .orderedAscending)
          if failed { throw SplashError("Tool number is outside its bounds") }
        }
      }
    }
  }
  private static func checkSize(
    _ count: Int, schema: [String: Any], minimum: String, maximum: String
  ) throws {
    if let bound = schema[minimum] as? NSNumber, count < bound.intValue {
      throw SplashError("Tool value is too short")
    }
    if let bound = schema[maximum] as? NSNumber, count > bound.intValue {
      throw SplashError("Tool value is too long")
    }
  }
  private static func equal(_ lhs: Any, _ rhs: Any) -> Bool {
    if let a = lhs as? NSNumber, let b = rhs as? NSNumber {
      return (CFGetTypeID(a) == CFBooleanGetTypeID()) == (CFGetTypeID(b) == CFBooleanGetTypeID())
        && a.compare(b) == .orderedSame
    }
    return (try? json(lhs)) == (try? json(rhs))
  }
}
