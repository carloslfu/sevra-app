import Foundation
import SevraCore

extension NativeTools {
  package static func referenceDefinitions(itemReferenceIDs: [String] = []) throws
    -> [WorkbookToolDefinition]
  {
    let ids = try ItemReferenceCandidates.normalized(itemReferenceIDs)
    guard !ids.isEmpty else { return definitions }
    return try definitions.map { definition in
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
    toolScope: InferenceToolScope = .all, itemReferenceIDs: [String] = []
  ) throws -> Data {
    let definitions = try referenceDefinitions(itemReferenceIDs: itemReferenceIDs)
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
