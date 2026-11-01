import CoreFoundation
import Foundation
import SevraAI
import SevraCore
import Slotstream

extension LocalModel {
  /// The added tokens of the pinned model packs. The engine renders message text
  /// as the native frontend does, and its tokenizer matches these anywhere in the
  /// result, so a document could otherwise close its turn and open a system one.
  private static let addedLiterals = [
    "<|endoftext|>", "<|im_start|>", "<|im_end|>", "<|object_ref_start|>", "<|object_ref_end|>",
    "<|box_start|>", "<|box_end|>", "<|quad_start|>", "<|quad_end|>", "<|vision_start|>",
    "<|vision_end|>", "<|vision_pad|>", "<|image_pad|>", "<|video_pad|>", "<tool_call>",
    "</tool_call>", "<|fim_prefix|>", "<|fim_middle|>", "<|fim_suffix|>", "<|fim_pad|>",
    "<|repo_name|>", "<|file_sep|>", "<tool_response>", "</tool_response>", "<think>", "</think>",
    "<|audio_start|>", "<|audio_end|>", "<tts_pad>", "<tts_text_bos>", "<tts_text_eod>",
    "<tts_text_bos_single>", "<|audio_pad|>",
  ]
  private static func withoutAddedLiterals(_ text: String) -> String {
    guard text.utf8.contains(UInt8(ascii: "<")) else { return text }
    return addedLiterals.reduce(text) {
      $0.replacingOccurrences(of: $1, with: "< " + $1.dropFirst(), options: .literal)
    }
  }
  /// The template closes tool and parameter names with its own ">".
  private static func nameWithoutAddedLiterals(_ name: String) -> String {
    var scalars = withoutAddedLiterals(name + ">").unicodeScalars
    scalars.removeLast()
    return String(scalars)
  }

  package static func baselineDefinitions(
    itemReferenceIDs: [String] = [], conversationActions: [String]? = nil,
    toolScope: InferenceToolScope = .all, documentCopyIDs: [String]? = nil
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
      itemReferenceIDs: itemReferenceIDs, conversationActions: conversationActions,
      toolScope: toolScope, documentCopyIDs: documentCopyIDs
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
      case let value as String: return .string(withoutAddedLiterals(value))
      case let value as [Any]: return .array(try value.map(convert))
      case let value as [String: Any]: return .object(try object(value))
      case is NSNull: return .null
      default: throw SevraError("model_format", "Invalid tool history.")
      }
    }
    // Sorted so keys that collide here resolve the same way on every render.
    func object(_ value: [String: Any]) throws -> [String: JSONValue] {
      var result: [String: JSONValue] = [:]
      for (key, child) in value.sorted(by: { $0.key < $1.key }) {
        let name = nameWithoutAddedLiterals(key)
        if result[name] == nil { result[name] = try convert(child) }
      }
      return result
    }
    return try messages.map { message in
      let calls: [ParsedToolCall] = try message.toolCalls.map { call in
        let json = try JSONSerialization.jsonObject(with: Data(call.inputJSON.utf8))
        guard let arguments = json as? [String: Any] else {
          throw SevraError("model_format", "Tool history requires object arguments.")
        }
        return ParsedToolCall(
          id: call.id, name: nameWithoutAddedLiterals(call.name), arguments: try object(arguments))
      }
      return ChatMessage(
        role: message.role, content: withoutAddedLiterals(message.content), toolCalls: calls,
        toolCallId: message.toolCallId, toolName: message.toolName)
    }
  }
}
