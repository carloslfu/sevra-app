import CoreFoundation
import Foundation
import SevraAI
import SevraCore
import Slotstream

extension LocalModel {
  package static func baselineDefinitions(
    itemReferenceIDs: [String] = [], conversationActions: [String]? = nil
  ) throws -> [Slotstream
    .ToolDefinition]
  {
    func schemaValue(_ value: Value) -> JSONValue {
      switch value {
      case .string(let s): return .string(s)
      case .number(let n): return Int(exactly: n).map(JSONValue.int) ?? .double(n)
      case .bool(let b): return .bool(b)
      case .array(let values): return .array(values.map(schemaValue))
      case .object(let values): return .object(values.mapValues(schemaValue))
      case .null: return .null
      }
    }
    return try NativeTools.referenceDefinitions(
      itemReferenceIDs: itemReferenceIDs, conversationActions: conversationActions
    ).map {
      .init(name: $0.name, description: $0.description, parameters: schemaValue($0.parameters))
    }
  }
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
