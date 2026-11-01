import Foundation

public struct DefinitionResultSnapshot: Codable, Equatable, Sendable {
  public let evaluation: Value
  public let captured: String
  public let inputPopulation: [Value]?
}

extension Item {
  /// A presentation of retained Record data, never a request to rerun it. The
  /// normal component reader validates its exact workbook/dependency bindings.
  var applicationResultComponent: Component? {
    let evaluation = data["evaluation"]
    guard category == "record", kind == "calculation",
      ["function", "query"].contains(evaluation["kind"].text),
      let definitionID = evaluation["definitionID"].string,
      case .object = evaluation["submittedArguments"]
    else { return nil }
    return Component(
      id: id, type: evaluation["kind"] == .string("function") ? "calculation" : "query",
      title: title,
      definitionBinding: .object(["mode": .string("exact"), "versionID": .string(definitionID)]),
      arguments: evaluation["submittedArguments"],
      evaluationSnapshot: .init(
        evaluation: evaluation, captured: data["captured"].string ?? created,
        inputPopulation: evaluation["kind"] == .string("query")
          ? data["inputPopulation"].array : nil))
  }
}

extension Workbook {
  /// Only a host-published result, or a review version preserving its data, gets
  /// the retained-computation presentation. A model-authored calculation claim
  /// cannot obtain that presentation by copying evaluation-shaped JSON.
  public func publishedApplicationResultComponent(
    _ id: String, cancellation: Cancellation = .init()
  ) throws -> Component? {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.readTransaction {
        let result = try item(id)
        guard let component = result.applicationResultComponent else { return nil }
        var origin = result
        for _ in 0..<256 {
          try control.check()
          guard origin.data == result.data else { return nil }
          let published = try db.scalar(
            "SELECT EXISTS(SELECT 1 FROM lineage WHERE child=? AND transformation=?)",
            [
              .string(origin.id),
              .string(
                "application-result-v1; exact definition="
                  + result.data["evaluation"]["definitionID"].text),
            ])
          if published.int == 1 { return component }
          guard let previous = origin.supersedes else { return nil }
          origin = try item(previous)
        }
        throw SevraError("definition_limit", "The result review history exceeds 256 versions.")
      }
    }
  }

  public func componentDefinitionResult(
    _ component: Component, cursor: String? = nil, cancellation: Cancellation = .init()
  ) throws -> Value {
    try synchronized(cancellation: cancellation) {
      try db.readTransaction {
        try validateDefinitionComponent(component, pinned: component.evaluationSnapshot != nil)
        if let saved = component.evaluationSnapshot {
          try require(
            cursor == nil, "view_snapshot", "A saved query page cannot load current rows.")
          return saved.evaluation
        }
        let target = try resolveDefinition(DefinitionBinding(component.definitionBinding!))
        return try evaluateApplicationDefinition(
          target.id, arguments: component.arguments!, cursor: cursor, cancellation: cancellation)
      }
    }
  }

  func validateDefinitionComponent(
    _ component: Component, pinned: Bool, checkArguments: Bool = true
  ) throws {
    try require(
      ["calculation", "query"].contains(component.type)
        && component.datasetID == nil && component.itemID == nil && component.snapshot == nil
        && component.searchSnapshot == nil && component.query == nil && component.x == nil
        && component.y == nil && component.chartStyle == nil && component.aggregation == nil
        && component.unit == nil,
      "view",
      "Copy read_definition.nativeComponent and fill its arguments from declared parameters. Keep definitionBinding; remove x,y,query,unit,datasetID,itemID and snapshots. x/y are chart data columns, never layout coordinates."
    )
    guard let raw = component.definitionBinding, let arguments = component.arguments,
      case .object = arguments
    else {
      throw SevraError(
        "view",
        "Keep nativeComponent.definitionBinding and fill arguments with its typed parameters.")
    }
    let binding = try DefinitionBinding(raw)
    let target = try resolveDefinition(binding)
    try require(
      target.kind == (component.type == "calculation" ? "function" : "query"), "view",
      "The component and definition kinds must agree.")
    if checkArguments { _ = try definitionArguments(DefinitionDescriptor(target.content), arguments) }
    guard let saved = component.evaluationSnapshot else {
      try require(!pinned, "view", "A pinned computation needs its saved evaluation.")
      return
    }
    let result = saved.evaluation
    try require(
      pinned && binding.mode == "exact" && result["workbookID"] == .string(id)
        && result["definitionID"] == .string(target.id) && result["kind"] == .string(target.kind)
        && result["submittedArguments"] == arguments && result["readOnly"] == .bool(true)
        && ISO8601DateFormatter().date(from: saved.captured) != nil
        && ((try? encoded(saved).json().utf8.count) ?? Int.max) <= 524_288,
      "view_snapshot", "The saved evaluation must retain its exact definition, inputs and values.")
    for resolved in result["resolvedDefinitions"].array {
      let definition = try applicationDefinition(resolved["id"].text)
      try require(
        definition.id == resolved["id"].text && definition.sourceID == resolved["sourceID"].text,
        "view_snapshot", "A saved evaluation needs exact retained definition evidence.")
    }
    if target.kind == "query" {
      try require(
        saved.inputPopulation != nil, "view_snapshot",
        "A saved query retains its scoped input population.")
      var count = 0
      for source in saved.inputPopulation ?? [] {
        let definition = try savedDatasetDefinition(
          source["datasetID"].text, definitionID: source["definitionID"].text)
        try require(
          source["sourceID"] == .string(definition.sourceID), "view_snapshot",
          "The query schema evidence changed.")
        for row in source["rows"].array {
          count += 1
          try require(
            count <= 5000 && (try item(row["versionID"].text)).id == row["versionID"].text,
            "view_snapshot", "A saved query needs bounded exact input versions.")
        }
      }
    }
    for row in result["result"]["rows"].array {
      for input in row["inputs"].array where input != .null {
        try require(
          try item(input["versionID"].text).id == input["versionID"].text,
          "view_snapshot", "A saved query needs exact retained input versions.")
      }
    }
  }

  func refuseAuthoredEvaluationSnapshots(_ definition: SpaceDefinition, current: Space?) throws {
    func contains(_ components: [Component]) -> Bool {
      components.contains { $0.evaluationSnapshot != nil || contains($0.children ?? []) }
    }
    if contains(definition.components) {
      try require(
        current?.definition.pinnedAt != nil, "view_snapshot",
        "Create saved computation values through Pin space, not an authored layout.")
    }
  }
}
