import Foundation
import SevraCore

extension NativeTools {
  package static func referenceDefinitions(
    itemReferenceIDs: [String] = [], conversationActions: [String]? = nil
  ) throws
    -> [WorkbookToolDefinition]
  {
    let ids = try ItemReferenceCandidates.normalized(itemReferenceIDs)
    return try definitions.compactMap { definition in
      if definition.name == "conversation_action", let conversationActions {
        guard !conversationActions.isEmpty else { return nil }
        try require(
          Set(conversationActions).isSubset(of: [
            "start_thread", "rename_thread", "return_to_main", "review_summary",
          ]),
          "tool_schema", "Invalid conversation capability.")
        var parameters = definition.parameters.object
        var properties = definition.parameters["properties"].object
        var action = properties["action"]!.object
        action["enum"] = .array(conversationActions.map(Value.string))
        properties["action"] = .object(action)
        parameters["properties"] = .object(properties)
        return WorkbookToolDefinition(
          name: definition.name,
          description: definition.description
            + " Available here: " + conversationActions.joined(separator: ", ")
            + ". Missing actions are unavailable, not invitations to create a new thread. Use finish to clarify an unavailable target.",
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
    conversationActions: [String]? = nil
  ) throws -> Data {
    let definitions = try referenceDefinitions(
      itemReferenceIDs: itemReferenceIDs, conversationActions: conversationActions
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
