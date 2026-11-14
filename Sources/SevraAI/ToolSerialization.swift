import Foundation
import SevraCore

extension NativeTools {
  package static func referenceDefinitions(
    itemReferenceIDs: [String] = [], conversationActions: [String]? = nil,
    toolScope: InferenceToolScope = .all, documentCopyIDs: [String]? = nil,
    historyReferenceIDs: [String]? = nil, nativeAppAuthoring: Bool = true
  ) throws
    -> [WorkbookToolDefinition]
  {
    if toolScope == .movementDirection { return [MovementDirectionReview.definition] }
    if toolScope == .actionDirection { return [ActionDirectionReview.definition] }
    if toolScope == .nativeAppReview { return [NativeAppReview.definition] }
    if toolScope == .excelPlan {
      return [
        ExcelConversionAgent.readDefinition, NativeTools.excelEvidenceDefinition,
        ExcelConversionAgent.definition,
      ]
    }
    let ids = try ItemReferenceCandidates.normalized(itemReferenceIDs)
    let copies = try documentCopyIDs.map(DocumentCopyCandidates.normalized)
    if let conversationActions {
      try require(
        Set(conversationActions).isSubset(of: Set(WorkbookTools.conversationTools.values)),
        "tool_schema", "Invalid conversation capability.")
    }
    let available =
      definitions
      + (toolScope == .excelBuild ? [excelEvidenceDefinition, excelBehaviorDefinition] : [])
    return try available.compactMap { definition in
      if definition.name == "save_native_app", !nativeAppAuthoring { return nil }
      if definition.name == "save_native_app", toolScope == .excelBuild {
        var parameters = definition.parameters.object
        var properties = definition.parameters["properties"].object
        properties.removeValue(forKey: "id")
        properties.removeValue(forKey: "expectedVersion")
        var package = properties["package"]!.object
        var fields = package["properties"]!.object
        fields["excelBehavior"] = excelBehaviorSchema
        fields["datasets"] = .object([
          "type": .string("object"),
          "additionalProperties": NativeTools.object(
            ["writable": .object(["type": .string("boolean")])], required: ["writable"]),
          "description": .string(
            "Use every supplied short alias (sheet1, sheet2, …), each with only writable:true or false. The HOST fills in datasetID, title and exact columns. Do not supply them."
          ),
        ])
        package["properties"] = .object(fields)
        properties["package"] = .object(package)
        parameters["properties"] = .object(properties)
        return .init(
          name: definition.name,
          description:
            "Save this Excel conversion's native workspace. The host supplies app identity, version and exact table bindings. package.datasets is only {sheet1:{writable:true/false},...}. Use all supplied aliases; do not supply datasetID/title/columns inside bindings or id/expectedVersion. Tests use synthetic fixtures, never imported rows. Include fixture rows before selecting/editing them. Failed checks save no app; fix the error and resubmit.",
          parameters: .object(parameters))
      }
      if let action = WorkbookTools.conversationTools[definition.name], let conversationActions {
        guard conversationActions.contains(action) else { return nil }
      }
      if definition.name == "draft", let copies {
        var parameters = definition.parameters.object
        var properties = definition.parameters["properties"].object
        var parts = properties["parts"]!.object
        var item = parts["items"]!.object
        var fields = item["properties"]!.object
        if copies.isEmpty {
          fields.removeValue(forKey: "copy")
        } else {
          var copy = fields["copy"]!.object
          copy["enum"] = .array(copies.map(Value.string))
          fields["copy"] = .object(copy)
        }
        item["properties"] = .object(fields)
        parts["items"] = .object(item)
        properties["parts"] = .object(parts)
        parameters["properties"] = .object(properties)
        return .init(
          name: definition.name, description: definition.description,
          parameters: .object(parameters))
      }
      if definition.name == "history_read", let historyReferenceIDs {
        guard !historyReferenceIDs.isEmpty else { return nil }
        var parameters = definition.parameters.object
        var properties = definition.parameters["properties"].object
        var id = properties["id"]!.object
        id["enum"] = .array(historyReferenceIDs.map(Value.string))
        properties["id"] = .object(id)
        parameters["properties"] = .object(properties)
        return .init(
          name: definition.name, description: definition.description,
          parameters: .object(parameters))
      }
      guard !ids.isEmpty else { return definition }
      guard ["read", "lineage", "references"].contains(definition.name) else { return definition }
      var parameters = definition.parameters.object
      var properties = definition.parameters["properties"].object
      var id = properties["id"]?.object ?? [:]
      try require(id["type"] == .string("string"), "tool_schema", "The item lookup schema changed.")
      id["enum"] = .array(ids.map(Value.string))
      properties["id"] = .object(id)
      parameters["properties"] = .object(properties)
      return WorkbookToolDefinition(
        name: definition.name, description: definition.description, parameters: .object(parameters))
    }
  }

  /// The same maintained declarations feed both backend boundaries.
  package static func serializedDefinitions(
    toolScope: InferenceToolScope = .all, itemReferenceIDs: [String] = [],
    conversationActions: [String]? = nil, documentCopyIDs: [String]? = nil,
    historyReferenceIDs: [String]? = nil, nativeAppAuthoring: Bool = true
  ) throws -> Data {
    let definitions = try referenceDefinitions(
      itemReferenceIDs: itemReferenceIDs, conversationActions: conversationActions,
      toolScope: toolScope, documentCopyIDs: documentCopyIDs,
      historyReferenceIDs: historyReferenceIDs, nativeAppAuthoring: nativeAppAuthoring
    )
    .filter { toolScope.allows($0.name) }
    let values: [[String: Any]] = try definitions.map {
      [
        "type": "function",
        "function": [
          "name": $0.name, "description": $0.description,
          "parameters": try JSONSerialization.jsonObject(with: Data(try $0.parameters.json().utf8)),
        ],
      ]
    }
    return try JSONSerialization.data(
      withJSONObject: values, options: [.sortedKeys, .withoutEscapingSlashes])
  }
}
