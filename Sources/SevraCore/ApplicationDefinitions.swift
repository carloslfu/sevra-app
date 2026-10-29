import Foundation

extension Workbook {
  public func boundApplicationDefinition(_ binding: Value) throws -> ApplicationDefinition {
    try synchronized { try resolveDefinition(DefinitionBinding(binding)) }
  }
  public func applicationDefinition(_ id: String) throws -> ApplicationDefinition {
    try synchronized {
      guard
        let row = try db.execute(
          "SELECT * FROM app_definitions WHERE id=? OR id=(SELECT definition_id FROM app_definition_heads WHERE logical_id=?) LIMIT 1",
          [.string(id), .string(id)]
        ).first
      else { throw SevraError("definition_not_found", "The application definition was not found.") }
      return try ApplicationDefinition(row)
    }
  }

  public func applicationDefinitionHistory(
    _ logicalID: String, beforeVersion: Int? = nil, limit: Int = 20
  ) throws -> [ApplicationDefinition] {
    try require(
      (1...50).contains(limit) && (beforeVersion == nil || beforeVersion! > 0), "definition_limit",
      "Use a positive history version and a limit from 1 to 50.")
    return try synchronized {
      try db.execute(
        "SELECT * FROM app_definitions WHERE logical_id=? AND version<? ORDER BY version DESC LIMIT ?",
        [
          .string(logicalID), .number(Double(beforeVersion ?? 1_000_000_001)),
          .number(Double(limit)),
        ]
      )
      .map(ApplicationDefinition.init)
    }
  }

  public func applicationDefinitionDependencies(_ versionID: String) throws -> [Value] {
    try synchronized {
      try require(
        try applicationDefinition(versionID).id == versionID, "definition_binding",
        "Inspect dependencies with an exact version ID.")
      return try db.execute(
        "SELECT * FROM app_definition_dependencies WHERE definition_id=? ORDER BY ordinal LIMIT 20",
        [.string(versionID)]
      ).map(Value.object)
    }
  }

  @discardableResult public func saveApplicationDefinition(
    logicalID: String, content: Value, expectedDefinitionID: String? = nil,
    inputs: [String] = [], token: String = identifier(), actor: ChangeActor? = nil,
    requestRunID: String? = nil, requestSourceID: String? = nil,
    cancellation: Cancellation = .init()
  ) throws -> ApplicationDefinition {
    try require(
      UUID(uuidString: logicalID) != nil && inputs.count <= 32,
      "definition", "Use a UUID logical identity and at most 32 authoring inputs.")
    let actual =
      actor ?? ChangeAttribution.actor ?? .programmatic("SevraCore.applicationDefinition")
    let request: Value = .object([
      "logicalID": .string(logicalID), "content": content,
      "base": expectedDefinitionID.map(Value.string) ?? .null,
      "inputs": .array(inputs.map(Value.string)),
      "requestRunID": requestRunID.map(Value.string) ?? .null,
      "requestSourceID": requestSourceID.map(Value.string) ?? .null,
    ])
    let result = try mutation(
      "save_application_definition", token: token, request: request,
      cancellation: cancellation, actor: actual
    ) {
      if let requestRunID {
        try validateApplicationToolRun(requestRunID, requestSourceID: requestSourceID)
      }
      let descriptor = try DefinitionDescriptor(content)
      try require(
        try db.scalar("SELECT count(*) FROM app_definitions WHERE id=?", [.string(logicalID)]).int
          == 0,
        "definition_identity", "Logical and exact definition identities must be distinct.")
      let currentID = try db.scalar(
        "SELECT definition_id FROM app_definition_heads WHERE logical_id=?", [.string(logicalID)]
      ).string
      try require(
        currentID == expectedDefinitionID, "stale_definition",
        "The definition changed. Keep your draft and inspect its current version.")
      let previous = try currentID.map(applicationDefinition)
      try require(
        previous == nil || previous?.kind == descriptor.kind, "definition_kind",
        "An edit must preserve its definition kind.")
      try require(
        (previous?.version ?? 0) < 1_000_000_000, "definition_limit",
        "Definition version limit reached.")
      for id in inputs {
        try require(
          try item(id).id == id, "definition_input",
          "Authoring evidence needs exact local item versions.")
      }
      let id = identifier()
      try require(
        try db.scalar("SELECT count(*) FROM app_definition_heads WHERE logical_id=?", [.string(id)])
          .int == 0,
        "definition_identity", "Logical and exact definition identities must be distinct.")
      let automationInputs =
        descriptor.kind == "automation" ? try validateAutomationDefinition(descriptor).inputs : []
      let sourceInputs = inputs + (previous.map { [$0.sourceID] } ?? [])
      let source = try insertItem(
        category: "source", kind: "application_definition", title: "Define " + descriptor.title,
        text: actual.label + " saved a reusable " + descriptor.kind
          + ". Execution and business acceptance are separate decisions.",
        data: .object(["submitted": request, "actor": try encoded(actual)]), meaning: "actual",
        status: "accepted", scenario: "actual",
        inputs: descriptor.kind == "automation"
          ? Array(Set(sourceInputs + automationInputs)).sorted() : sourceInputs,
        transformation: "application-definition-authoring-v1")
      try db.execute(
        "INSERT INTO app_definitions VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
        [
          .string(id), .string(logicalID), .number(Double((previous?.version ?? 0) + 1)),
          currentID.map(Value.string) ?? .null, .string(descriptor.kind), .string(descriptor.title),
          .string(descriptor.description), .string(try content["parameters"].json()),
          .string(try descriptor.payload.json()),
          .string(descriptor.parameters.map { $0.id + " " + $0.label }.joined(separator: " ")),
          .string(source), .string(timestamp()),
        ])
      try db.execute(
        "INSERT INTO app_definition_heads VALUES(?,?) ON CONFLICT(logical_id) DO UPDATE SET definition_id=excluded.definition_id",
        [.string(logicalID), .string(id)])
      let saved = try applicationDefinition(id)
      let state = DefinitionEvaluation(cancellation)
      try validateDefinitionGraph(saved, state: state, depth: 0)
      var ordinal = 0
      func dependency(
        _ kind: String, mode: String, logical: String? = nil, version: String? = nil,
        dataset: String? = nil, schema: String? = nil, input: String
      ) throws {
        try db.execute(
          "INSERT INTO app_definition_dependencies VALUES(?,?,?,?,?,?,?,?)",
          [
            .string(id), .number(Double(ordinal)), .string(kind), .string(mode),
            logical.map(Value.string) ?? .null, version.map(Value.string) ?? .null,
            dataset.map(Value.string) ?? .null, schema.map(Value.string) ?? .null,
          ])
        ordinal += 1
        try insertDefinitionDerivation(
          source, parent: input, transformation: "application-definition-authoring-v1")
      }
      if descriptor.kind == "intake" {
        let intake = try DefinitionIntake(descriptor)
        let target = try savedDatasetDefinition(intake.datasetID, definitionID: intake.definitionID)
        try dependency(
          "dataset", mode: "exact", dataset: target.datasetID, schema: target.id,
          input: target.sourceID)
      } else if descriptor.kind != "query" {
        for binding in try definitionBindings(descriptor) {
          let target = try resolveDefinition(binding)
          try dependency(
            "definition", mode: binding.mode, logical: target.logicalID, version: target.id,
            input: target.sourceID)
        }
      } else {
        for source in descriptor.payload["query"]["sources"].array {
          let target = try savedDatasetDefinition(
            source["datasetID"].text, definitionID: source["definitionID"].text)
          try dependency(
            "dataset", mode: descriptor.payload["dataMode"].text, dataset: target.datasetID,
            schema: target.id, input: target.sourceID)
        }
      }
      try sealNewDefinitionDerivation(source)
      return .string(id)
    }
    return try applicationDefinition(result.text)
  }

  @discardableResult public func restoreApplicationDefinition(
    _ logicalID: String, versionID: String, expectedDefinitionID: String,
    token: String = identifier(), actor: ChangeActor? = nil, cancellation: Cancellation = .init()
  ) throws -> ApplicationDefinition {
    let saved = try applicationDefinition(versionID)
    try require(
      saved.id == versionID && saved.logicalID == logicalID, "definition_binding",
      "Restore an exact version from this definition's own history.")
    return try saveApplicationDefinition(
      logicalID: logicalID, content: saved.content, expectedDefinitionID: expectedDefinitionID,
      inputs: [saved.sourceID], token: token, actor: actor, cancellation: cancellation)
  }

  func validateDefinitionGraph(
    _ definition: ApplicationDefinition, state: DefinitionEvaluation, depth: Int
  ) throws {
    try state.enter(definition, depth: depth)
    defer { state.active.remove(definition.id) }
    let descriptor = try DefinitionDescriptor(definition.content)
    for parameter in descriptor.parameters {
      if let value = parameter.defaultValue, value != .null {
        try validateDefinitionItemReferences(parameter, value)
      }
    }
    if descriptor.kind == "automation" {
      _ = try validateAutomationDefinition(descriptor)
    } else if descriptor.kind == "intake" {
      try validateIntakeDefinition(descriptor)
    } else if descriptor.kind == "extraction" {
      _ = try DefinitionExtraction(descriptor)
    } else if descriptor.kind == "interpretation" {
      _ = try DefinitionInterpretation(descriptor)
    } else if descriptor.kind == "workflow" {
      try validateWorkflowDefinition(descriptor)
    } else if descriptor.kind == "query" {
      _ = try resolvedDefinitionQuery(descriptor, arguments: [:], samples: true)
    } else if descriptor.kind == "form" {
      let form = try DefinitionForm(descriptor)
      let target = try resolveDefinition(form.binding)
      try validateForm(form, descriptor: descriptor, action: target)
      try validateDefinitionGraph(target, state: state, depth: depth + 1)
    } else if descriptor.kind == "action" {
      _ = try validateActionMapping(
        DefinitionAction(descriptor), caller: descriptor,
        state: state, arguments: nil, depth: depth)
    } else {
      for call in try DefinitionFunction(descriptor).calls {
        let target = try resolveDefinition(call.binding)
        try require(
          target.kind == "function", "definition_kind", "Function calls may target functions only.")
        _ = try mapDefinitionCall(
          call, caller: descriptor, target: DefinitionDescriptor(target.content), arguments: nil,
          validateOnly: true)
        try validateDefinitionGraph(target, state: state, depth: depth + 1)
      }
    }
  }
}
