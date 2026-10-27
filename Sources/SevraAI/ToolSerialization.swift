import Foundation
import SevraCore

extension NativeTools {
  /// The same maintained declarations feed both backend boundaries.
  package static func serializedDefinitions(toolScope: InferenceToolScope = .all) throws -> Data {
    let definitions = definitions.filter { toolScope.allows($0.name) }
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
