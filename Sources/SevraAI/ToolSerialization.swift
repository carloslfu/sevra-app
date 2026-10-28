import Foundation
import SevraCore

extension NativeTools {
  package static func referenceDefinitions(
    itemReferenceIDs: [String] = [], conversationActions: [String]? = nil,
    toolScope: InferenceToolScope = .all, documentCopyIDs: [String]? = nil
  ) throws
    -> [WorkbookToolDefinition]
  {
    if toolScope == .movementDirection { return [MovementDirectionReview.definition] }
    let ids = try ItemReferenceCandidates.normalized(itemReferenceIDs)
    let copies = try documentCopyIDs.map(DocumentCopyCandidates.normalized)
    if let conversationActions {
      try require(
        Set(conversationActions).isSubset(of: Set(WorkbookTools.conversationTools.values)),
        "tool_schema", "Invalid conversation capability.")
    }
    return try definitions.compactMap { definition in
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
      guard !ids.isEmpty else { return definition }
      guard ["read", "lineage"].contains(definition.name) else { return definition }
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
    conversationActions: [String]? = nil, documentCopyIDs: [String]? = nil
  ) throws -> Data {
    let definitions = try referenceDefinitions(
      itemReferenceIDs: itemReferenceIDs, conversationActions: conversationActions,
      toolScope: toolScope, documentCopyIDs: documentCopyIDs
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
