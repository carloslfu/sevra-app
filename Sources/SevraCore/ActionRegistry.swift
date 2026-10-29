import Foundation

/// Trusted native primitives. Definition text never adds capabilities.
public enum ActionRegistry {
  static let receivingID = "inventory.receiveDelivery"
  static let receivingParameters: [Value] = [
    field("delivery", "Delivery identity", "text"),
    field("effective", "Effective date", "date"),
    field("evidence", "Evidence", "item"),
    .object([
      "id": .string("lines"), "label": .string("Delivery lines"), "type": .string("entries"),
      "required": .bool(true), "maxEntries": .number(50),
      "fields": .array([
        field("line", "Line identity", "text"), field("subject", "Inventory subject", "text"),
        field("quantity", "Item count", "decimal", unit: "items"),
      ]),
    ]),
  ]
  static let movementID = "inventory.proposeMovement"
  static let documentID = "records.draftDocument"
  static let documentParameters: [Value] = [
    field("title", "Document title", "text"), field("body", "New prose", "text"),
    field("evidence", "Evidence", "item"),
    .object([
      "id": .string("meaning"), "label": .string("Meaning"), "type": .string("choice"),
      "required": .bool(true),
      "choices": .array(
        ["actual", "estimate", "plan", "commitment", "assumption", "rule"].map(Value.string)),
    ]),
    field("scenario", "Scenario", "text"),
  ]
  private static func title(_ id: String) -> String {
    id == documentID
      ? "Draft document"
      : id == receivingID ? "Receive delivery" : "Propose inventory movement"
  }
  private static func parameters(_ id: String) -> [Value] {
    id == documentID
      ? documentParameters : id == receivingID ? receivingParameters : movementParameters
  }
  static let movementParameters: [Value] = [
    field("subject", "Inventory subject", "text"),
    field("quantity", "Signed item count", "decimal", unit: "items"),
    field("occurrence", "Business occurrence identity", "text"),
    field("effective", "Effective date", "date"),
    field("evidence", "Evidence", "item"),
    .object([
      "id": .string("meaning"), "label": .string("Meaning"), "type": .string("choice"),
      "required": .bool(true),
      "choices": .array(
        ["actual", "estimate", "plan", "commitment", "assumption"].map(Value.string)),
      "default": .string("actual"),
    ]),
    .object([
      "id": .string("supersedes"), "label": .string("Corrected movement"), "type": .string("item"),
      "required": .bool(false),
    ]),
  ]
  static func field(_ id: String, _ label: String, _ type: String, unit: String? = nil) -> Value {
    var value: [String: Value] = [
      "id": .string(id), "label": .string(label), "type": .string(type), "required": .bool(true),
    ]
    if let unit { value["unit"] = .string(unit) }
    return .object(value)
  }
  static func descriptor(_ id: String, version: Int) throws -> DefinitionDescriptor {
    try require(
      [receivingID, movementID, documentID].contains(id) && version == 1, "action_primitive",
      "Unknown registered action version.")
    return try DefinitionDescriptor(
      .object([
        "kind": .string("action"),
        "title": .string(title(id)),
        "description": .string("Prepare local drafts for separate review."),
        "parameters": .array(parameters(id)),
        "payload": .object([:]),
      ]))
  }
  public static let resultSchema: Value = .object([
    "type": .string("object"), "additionalProperties": .bool(false),
    "required": .array(
      [
        "workbookID", "definitionID", "sourceID", "proposals", "state", "acceptedBalanceChanged",
        "resolvedDefinitions", "fingerprint",
      ].map(Value.string)),
    "properties": .object([
      "workbookID": .object(["type": .string("string"), "format": .string("uuid")]),
      "definitionID": .object(["type": .string("string"), "format": .string("uuid")]),
      "sourceID": .object(["type": .string("string"), "format": .string("uuid")]),
      "proposals": .object([
        "type": .string("array"), "minItems": .number(1), "maxItems": .number(50),
        "uniqueItems": .bool(true),
        "items": .object(["type": .string("string"), "format": .string("uuid")]),
      ]),
      "state": .object(["const": .string("draft")]),
      "acceptedBalanceChanged": .object(["const": .bool(false)]),
      "resolvedDefinitions": .object([
        "type": .string("array"), "minItems": .number(1), "maxItems": .number(128),
        "items": .object([
          "type": .string("object"), "additionalProperties": .bool(false),
          "required": .array(["id", "logicalID", "sourceID"].map(Value.string)),
          "properties": .object(
            Dictionary(
              uniqueKeysWithValues: ["id", "logicalID", "sourceID"].map {
                ($0, .object(["type": .string("string"), "format": .string("uuid")]))
              })),
        ]),
      ]),
      "fingerprint": .object(["type": .string("string"), "pattern": .string("^[0-9a-f]{64}$")]),
    ]),
  ])
  public static func actions() -> Value {
    .array(
      [receivingID, movementID, documentID].map { id in
        .object([
          "id": .string(id), "version": .number(1),
          "title": .string(title(id)),
          "parameters": .array(parameters(id)),
          "resultSchema": resultSchema,
          "effectCategory": .string("local_proposal"),
          "deadlineSeconds": .number(3),
          "effect": .string(
            id == documentID
              ? "local draft document from new prose; no acceptance or original-copy fidelity claim"
              : "local draft inventory proposals; no accepted balance change"),
          "capabilities": .array([
            .string(id == documentID ? "workbook.draft_document" : "workbook.propose_inventory")
          ]),
          "cancellation": .string(
            "bounded atomic transaction; cancellation rolls back before commit"),
          "retry": .string("exact token/arguments return the original receipt"),
          "units": .string(
            id == documentID
              ? "bounded prose; explicit meaning and scenario"
              : "discrete items only; no conversion or inferred units"),
        ])
      })
  }
  /// A reusable starter is ordinary versioned user data, not an implicit installed rule.
  public static func formDefinition(target: ApplicationDefinition) -> Value {
    .object([
      "kind": .string("form"), "title": .string(target.title),
      "description": .string(target.description),
      "parameters": target.parameters,
      "payload": .object([
        (target.kind == "workflow" ? "workflow" : "action"): .object([
          "mode": .string("live"), "logicalID": .string(target.logicalID),
        ]),
        "fields": .array(
          target.parameters.array.map { parameter in
            var field: [String: Value] = ["parameter": parameter["id"]]
            if parameter["id"].text == "delivery" {
              field["label"] = .string("Delivery or receipt number")
              field["help"] = .string(
                "Use the identity on your evidence so the same delivery cannot be recorded twice.")
            }
            if parameter["id"].text == "lines" {
              field["help"] = .string(
                "Use the line numbers and item counts on the receipt. This form counts discrete items."
              )
            }
            return .object(field)
          }),
      ]),
    ])
  }
  public static func receivingDefinition() -> Value {
    .object([
      "kind": .string("action"), "title": .string("Receive delivery"),
      "description": .string(
        "Create draft actual inventory movements from exact delivery evidence. Review before acceptance."
      ),
      "parameters": .array(receivingParameters),
      "payload": .object([
        "primitive": .object(["id": .string(receivingID), "version": .number(1)]),
        "arguments": .object(
          Dictionary(
            uniqueKeysWithValues: receivingParameters.map {
              ($0["id"].text, .object(["parameter": $0["id"]]))
            })),
      ]),
    ])
  }
}

struct DefinitionAction {
  let primitiveID: String
  let primitiveVersion: Int
  let arguments: [String: Value]
  let target: DefinitionDescriptor
  init(_ descriptor: DefinitionDescriptor) throws {
    let raw = try definitionObject(descriptor.payload, keys: ["primitive", "arguments"])
    let primitive = try definitionObject(raw["primitive"] ?? .null, keys: ["id", "version"])
    guard let id = primitive["id"]?.string, let version = primitive["version"]?.int,
      primitive["version"] == .number(Double(version)),
      case .object(let arguments) = raw["arguments"],
      arguments.count <= 32
    else {
      throw SevraError(
        "definition_action", "Declare a registered primitive version and argument mappings.")
    }
    primitiveID = id
    primitiveVersion = version
    self.arguments = arguments
    target = try ActionRegistry.descriptor(id, version: version)
  }
  var calls: [DefinitionFunction.Call] {
    get throws {
      try arguments.keys.sorted().compactMap { key in
        guard let raw = arguments[key], raw.object["function"] != nil else { return nil }
        let o = try definitionObject(raw, keys: ["function", "arguments"])
        guard let binding = o["function"], case .object(let mappings) = o["arguments"],
          mappings.count <= 32
        else {
          throw SevraError(
            "definition_action",
            "A computed argument needs a function binding and explicit arguments.")
        }
        return try .init(alias: key, binding: DefinitionBinding(binding), arguments: mappings)
      }
    }
  }
}

struct DefinitionForm {
  let binding: DefinitionBinding
  let fields: [Value]
  let targetKind: String
  init(_ descriptor: DefinitionDescriptor) throws {
    let raw = try definitionObject(descriptor.payload, keys: ["action", "workflow", "fields"])
    try require(
      (raw["action"] != nil) != (raw["workflow"] != nil), "definition_form",
      "A form targets one action or workflow.")
    targetKind = raw["workflow"] == nil ? "action" : "workflow"
    binding = try DefinitionBinding(raw[targetKind] ?? .null)
    guard case .array(let fields) = raw["fields"], fields.count == descriptor.parameters.count
    else {
      throw SevraError("definition_form", "Declare one presentation field for every parameter.")
    }
    var seen = Set<String>()
    for field in fields {
      let value = try definitionObject(field, keys: ["parameter", "label", "help"])
      guard let id = value["parameter"]?.string, seen.insert(id).inserted,
        descriptor.parameters.contains(where: { $0.id == id }),
        value["label"] == nil
          || (value["label"]?.string != nil && !value["label"]!.text.isEmpty
            && value["label"]!.text.utf8.count <= 256),
        value["help"] == nil
          || (value["help"]?.string != nil && value["help"]!.text.utf8.count <= 2048)
      else {
        throw SevraError(
          "definition_form", "Use distinct declared fields with bounded labels and help.")
      }
    }
    self.fields = fields
  }
}

extension DefinitionParameter {
  var signature: Value {
    .object([
      "type": .string(type), "unit": unit.map(Value.string) ?? .null,
      "choices": .array(choices.map(Value.string)),
      "fields": .array(fields.map { .object(["id": .string($0.id), "signature": $0.signature]) }),
      "maxEntries": maxEntries.map { .number(Double($0)) } ?? .null,
    ])
  }
}

extension Workbook {
  func definitionBindings(_ descriptor: DefinitionDescriptor) throws -> [DefinitionBinding] {
    switch descriptor.kind {
    case "function": return try DefinitionFunction(descriptor).calls.map(\.binding)
    case "action": return try DefinitionAction(descriptor).calls.map(\.binding)
    case "form": return [try DefinitionForm(descriptor).binding]
    case "workflow": return try DefinitionWorkflow(descriptor).steps.compactMap(\.binding)
    case "automation": return [try DefinitionAutomation(descriptor).workflow]
    default: return []
    }
  }

  func validateActionMapping(
    _ action: DefinitionAction, caller: DefinitionDescriptor, state: DefinitionEvaluation,
    arguments: [String: Value]?, depth: Int
  ) throws -> [String: Value] {
    let calls = try action.calls
    var plain = action.arguments.filter { $0.value.object["function"] == nil }
    let parameters = Dictionary(uniqueKeysWithValues: action.target.parameters.map { ($0.id, $0) })
    for call in calls {
      guard let parameter = parameters[call.alias], parameter.type == "decimal" else {
        throw SevraError(
          "definition_action", "Computed bindings require a declared decimal target.")
      }
      let target = try resolveDefinition(call.binding)
      try require(
        target.kind == "function", "definition_kind",
        "Computed bindings may call only pure functions.")
      let descriptor = try DefinitionDescriptor(target.content)
      let function = try DefinitionFunction(descriptor)
      try require(
        function.unit == parameter.unit, "definition_unit",
        "Function output and action input units must match.")
      let mapped = try mapDefinitionCall(
        call, caller: caller, target: descriptor, arguments: arguments,
        validateOnly: arguments == nil)
      let value: Value
      if arguments != nil {
        value = try evaluateFunction(
          target, arguments: .object(mapped), state: state, depth: depth + 1)
      } else {
        try validateDefinitionGraph(target, state: state, depth: depth + 1)
        value = parameter.sample
      }
      var literal: [String: Value] = ["literal": value]
      if let unit = parameter.unit { literal["unit"] = .string(unit) }
      plain[call.alias] = .object(literal)
    }
    let synthetic = DefinitionFunction.Call(
      alias: "primitive",
      binding: try DefinitionBinding(
        .object([
          "mode": .string("exact"), "versionID": .string("00000000-0000-0000-0000-000000000000"),
        ])), arguments: plain)
    let mapped = try mapDefinitionCall(
      synthetic, caller: caller, target: action.target, arguments: arguments,
      validateOnly: arguments == nil)
    return arguments == nil ? [:] : try definitionArguments(action.target, .object(mapped))
  }

  func validateForm(
    _ form: DefinitionForm, descriptor: DefinitionDescriptor, action: ApplicationDefinition
  ) throws {
    try require(
      action.kind == form.targetKind && action.parameters == descriptor.value["parameters"],
      "stale_form_definition",
      "The form and target parameter signatures differ. Keep the draft and reopen explicitly.")
  }
}
