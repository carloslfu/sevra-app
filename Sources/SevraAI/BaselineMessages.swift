import CoreFoundation
import Foundation
import SevraCore
import Slotstream

extension LocalModel {
  package static func baselineMessages(_ messages: [InferenceMessage]) throws -> [ChatMessage] {
    func convert(_ value: Any) throws -> JSONValue {
      switch value {
      case let value as NSNumber:
        if CFGetTypeID(value) == CFBooleanGetTypeID() { return .bool(value.boolValue) }
        if let integer = Int(exactly: value) { return .int(integer) }
        try require(value.doubleValue.isFinite, "model_format", "Non-finite tool history.")
        return .double(value.doubleValue)
      case let value as String: return .string(value)
      case let value as [Any]: return .array(try value.map(convert))
      case let value as [String: Any]: return .object(try value.mapValues(convert))
      case is NSNull: return .null
      default: throw SevraError("model_format", "Invalid tool history.")
      }
    }
    return try messages.map { message in
      let calls: [ParsedToolCall] = try message.toolCalls.map { call in
        let json = try JSONSerialization.jsonObject(with: Data(call.inputJSON.utf8))
        guard let arguments = json as? [String: Any] else {
          throw SevraError("model_format", "Tool history requires object arguments.")
        }
        return ParsedToolCall(
          id: call.id, name: call.name, arguments: try arguments.mapValues(convert))
      }
      return ChatMessage(
        role: message.role, content: message.content, toolCalls: calls,
        toolCallId: message.toolCallId, toolName: message.toolName)
    }
  }
}

extension NativeTools {
  /// The same maintained declarations feed both backend boundaries.
  package static func serializedDefinitions(finishOnly: Bool = false) throws -> Data {
    let definitions = finishOnly ? definitions.filter { $0.name == "finish" } : definitions
    let values: [[String: Any]] = try definitions.map {
      [
        "type": "function",
        "function": [
          "name": $0.name, "description": $0.description,
          "parameters": try JSONSerialization.jsonObject(with: Data($0.parameters.jsonText.utf8)),
        ],
      ]
    }
    return try JSONSerialization.data(
      withJSONObject: values, options: [.sortedKeys, .withoutEscapingSlashes])
  }
}
