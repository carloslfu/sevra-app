import Foundation

/// Trusted native primitives. Definition text never adds capabilities.
public enum ActionRegistry {
  static let documentID = "records.draftDocument"
  /// Runs one of the workbook's saved tools, named by the action's `tool` binding, with the
  /// tool's own inputs as the primitive's parameters. It runs through the same path as a
  /// view's button: the change is recorded at once and one Undo takes it back.
  public static let toolID = "tools.run"
  static let documentParameters: [Value] = [
    field("title", "Document title", "text"), field("body", "Text", "text"),
    field("evidence", "Evidence", "item"),
    .object([
      "id": .string("meaning"), "label": .string("Meaning"), "type": .string("choice"),
      "required": .bool(true),
      "choices": .array(
        ["actual", "estimate", "plan", "commitment", "assumption", "rule"].map(Value.string)),
    ]),
    field("scenario", "Scenario", "text"),
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
      id == documentID && version == 1, "action_primitive",
      "Unknown registered action version. The registered actions are records.draftDocument and tools.run, version 1.")
    return try DefinitionDescriptor(
      .object([
        "kind": .string("action"),
        "title": .string("Draft document"),
        "description": .string("Prepare local drafts for separate review."),
        "parameters": .array(documentParameters),
        "payload": .object([:]),
      ]))
  }
  public static let resultSchema: Value = .object([
    "type": .string("object"), "additionalProperties": .bool(false),
    "required": .array(
      [
        "workbookID", "definitionID", "sourceID", "proposals", "state", "resolvedDefinitions",
        "fingerprint",
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
  /// The primitive's inputs for one saved tool version: exactly that tool's inputs.
  static func toolDescriptor(_ tool: ApplicationDefinition) throws -> DefinitionDescriptor {
    let saved = try DefinitionTool(DefinitionDescriptor(tool.content))
    try require(
      !saved.retired, "tool", "The tool \(saved.name) was removed. Choose a saved tool.")
    return try DefinitionDescriptor(
      .object([
        "kind": .string("action"), "title": .string("Run " + saved.name),
        "description": .string("Run the saved tool " + saved.name + "."),
        "parameters": tool.parameters, "payload": .object([:]),
      ]))
  }
  public static let toolResultSchema: Value = .object([
    "type": .string("object"), "additionalProperties": .bool(false),
    "required": .array(
      ["workbookID", "definitionID", "sourceID", "tool", "state", "resolvedDefinitions", "fingerprint"]
        .map(Value.string)),
    "properties": .object([
      "workbookID": .object(["type": .string("string"), "format": .string("uuid")]),
      "definitionID": .object(["type": .string("string"), "format": .string("uuid")]),
      "sourceID": .object(["type": .string("string"), "format": .string("uuid")]),
      "tool": .object(["type": .string("string")]),
      "state": .object(["const": .string("applied")]),
      "summary": .object(["type": .string("string")]),
      "undo": .object(["type": .string("string")]),
      "changes": .object(["type": .string("array")]),
      "results": .object(["type": .string("array")]),
      "resolvedDefinitions": .object(["type": .string("array")]),
      "fingerprint": .object(["type": .string("string"), "pattern": .string("^[0-9a-f]{64}$")]),
    ]),
  ])
  public static func actions() -> Value {
    .array(
      [
        .object([
          "id": .string(toolID), "version": .number(1),
          "title": .string("Run a saved tool"),
          "parameters": .string(
            "the saved tool's own inputs, with the same ids and types. Name the tool in payload.tool: {mode: live, logicalID} or {mode: exact, versionID} of a saved tool definition."
          ),
          "resultSchema": toolResultSchema,
          "effectCategory": .string("recorded_change"),
          "deadlineSeconds": .number(30),
          "effect": .string(
            "runs the tool's statements or script. Its table changes are saved at once and recorded, and one Undo takes them back"
          ),
          "capabilities": .array([.string("workbook.run_tool")]),
          "cancellation": .string("a run saves all of its changes or none"),
          "retry": .string("exact token/arguments return the original receipt"),
          "units": .string("the tool's input types: text, decimal, boolean or date"),
        ]),
        .object([
          "id": .string(documentID), "version": .number(1),
          "title": .string("Draft document"),
          "parameters": .array(documentParameters),
          "resultSchema": resultSchema,
          "effectCategory": .string("local_proposal"),
          "deadlineSeconds": .number(3),
          "effect": .string(
            "local draft document from new prose; no acceptance or original-copy fidelity claim"),
          "capabilities": .array([.string("workbook.draft_document")]),
          "cancellation": .string(
            "bounded atomic transaction; cancellation rolls back before commit"),
          "retry": .string("exact token/arguments return the original receipt"),
          "units": .string("bounded prose; explicit meaning and scenario"),
        ])
      ])
  }
  /// A saved action that drafts one document through the document primitive, with every
  /// primitive input as a parameter of its own.
  public static func documentDefinition(title: String, description: String) -> Value {
    .object([
      "kind": .string("action"), "title": .string(title), "description": .string(description),
      "parameters": .array(documentParameters),
      "payload": .object([
        "primitive": .object(["id": .string(documentID), "version": .number(1)]),
        "arguments": .object(
          Dictionary(
            uniqueKeysWithValues: documentParameters.map {
              ($0["id"].text, .object(["parameter": $0["id"]]))
            })),
      ]),
    ])
  }
  /// A saved action that runs one saved tool, with every tool input as a parameter of its own.
  /// A live binding follows the tool's current version. A workflow needs an exact one.
  public static func toolActionDefinition(
    tool: ApplicationDefinition, title: String? = nil, exact: Bool = false
  ) -> Value {
    .object([
      "kind": .string("action"), "title": .string(title ?? tool.title),
      "description": .string(tool.description.isEmpty ? "Run " + tool.title : tool.description),
      "parameters": tool.parameters,
      "payload": .object([
        "primitive": .object(["id": .string(toolID), "version": .number(1)]),
        "tool": exact
          ? .object(["mode": .string("exact"), "versionID": .string(tool.id)])
          : .object(["mode": .string("live"), "logicalID": .string(tool.logicalID)]),
        "arguments": .object(
          Dictionary(
            uniqueKeysWithValues: tool.parameters.array.map {
              ($0["id"].text, .object(["parameter": $0["id"]]))
            })),
      ]),
    ])
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
          target.parameters.array.map { .object(["parameter": $0["id"]]) }),
      ]),
    ])
  }
}

struct DefinitionAction {
  let primitiveID: String
  let primitiveVersion: Int
  let arguments: [String: Value]
  /// The saved tool a `tools.run` action runs. Nil for every other primitive.
  let tool: DefinitionBinding?
  let target: DefinitionDescriptor
  /// `tool` is the resolved version of the action's tool binding. `parseOnly` reads the
  /// mappings and bindings without it, for callers that need only those.
  init(_ descriptor: DefinitionDescriptor, tool resolved: ApplicationDefinition? = nil,
    parseOnly: Bool = false) throws
  {
    let raw = try definitionObject(descriptor.payload, keys: ["primitive", "arguments", "tool"])
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
    if id == ActionRegistry.toolID {
      try require(
        version == 1 && raw["tool"] != nil, "definition_action",
        "A tools.run action names its saved tool: payload.tool is {mode: live, logicalID} or {mode: exact, versionID}."
      )
      tool = try DefinitionBinding(raw["tool"]!)
      if let resolved {
        try require(resolved.kind == "tool", "definition_kind", "payload.tool must name a saved tool.")
        target = try ActionRegistry.toolDescriptor(resolved)
      } else {
        try require(parseOnly, "definition_action", "Resolve the action's saved tool first.")
        target = try DefinitionDescriptor(
          .object([
            "kind": .string("action"), "title": .string("Run a saved tool"),
            "description": .string(""), "parameters": .array([]), "payload": .object([:]),
          ]))
      }
    } else {
      try require(
        raw["tool"] == nil, "definition_action", "Only a tools.run action names a tool.")
      tool = nil
      target = try ActionRegistry.descriptor(id, version: version)
    }
  }
  /// The definitions this action depends on: its computed inputs, then its tool.
  var bindings: [DefinitionBinding] {
    get throws { try calls.map(\.binding) + (tool.map { [$0] } ?? []) }
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
    case "action": return try DefinitionAction(descriptor, parseOnly: true).bindings
    case "form": return [try DefinitionForm(descriptor).binding]
    case "workflow": return try DefinitionWorkflow(descriptor).steps.compactMap(\.binding)
    case "automation": return try DefinitionAutomation(descriptor).bindings
    default: return []
    }
  }

  /// An action with its tool resolved: the tool binding's version, or `toolVersion` when a
  /// retained dependency pins the version to check against.
  func definitionAction(_ descriptor: DefinitionDescriptor, toolVersion: String? = nil) throws
    -> DefinitionAction
  {
    let parsed = try DefinitionAction(descriptor, parseOnly: true)
    guard let binding = parsed.tool else { return parsed }
    let tool = try toolVersion.map { try applicationDefinition($0) } ?? resolveDefinition(binding)
    return try DefinitionAction(descriptor, tool: tool)
  }

  func validateActionMapping(
    _ action: DefinitionAction, caller: DefinitionDescriptor, state: DefinitionEvaluation,
    arguments: [String: Value]?, depth: Int
  ) throws -> [String: Value] {
    let calls = try action.calls
    if let binding = action.tool {
      // The tool is part of what the action resolves, so a changed tool makes a preview stale.
      let tool = try resolveDefinition(binding)
      try state.enter(tool, depth: depth + 1)
      state.active.remove(tool.id)
    }
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
