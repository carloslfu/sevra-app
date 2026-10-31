import Foundation
import SevraCore

/// Host-selected scope, never inferred from untrusted retrieved content.
package enum InferenceToolScope: String, Sendable {
  // Tool scopes retain the public tool names as their raw values.
  // swift-format-ignore: AlwaysUseLowerCamelCase
  case all, finish, inspection, movementDirection, actionDirection, workflowAnswer, answer,
    boundedAnswer, draft,
    save_space,
    edit_space,
    restore_space, propose_movement,
    propose_record,
    propose_table, propose_table_edit

  package func allows(_ tool: String) -> Bool {
    switch self {
    case .all:
      return !["review_movement_direction", "review_action_directions", "prepare_workflow_answer"]
        .contains(tool)
    case .workflowAnswer: return Self.answer.allows(tool) || tool == "prepare_workflow_answer"
    case .movementDirection: return tool == "review_movement_direction"
    case .actionDirection: return tool == "review_action_directions"
    case .finish: return tool == "finish"
    case .inspection: return WorkbookTools.readOnlyTools.contains(tool)
    case .answer: return tool == "finish" || WorkbookTools.readOnlyTools.contains(tool)
    case .boundedAnswer:
      return Self.answer.allows(tool) && !["search", "history_search"].contains(tool)
    case .propose_movement:
      // Saved inventory actions still pass the complete movement review. A
      // future primitive without movements refuses there before submission.
      return Self.answer.allows(tool) || tool == rawValue || tool == "prepare_action"
    case .propose_record:
      return Self.answer.allows(tool) || tool == rawValue || tool == "publish_result"
    case .draft, .save_space, .edit_space, .restore_space,
      .propose_table,
      .propose_table_edit:
      return Self.answer.allows(tool) || tool == rawValue
    }
  }
}

/// App-owned conversation values. The candidate and preserved baseline use the
/// same workbook loop; this internal seam is not a provider catalog or user API.
package struct InferenceCall: Sendable {
  package let id: String
  package let name: String
  package let inputJSON: String
  package init(id: String, name: String, inputJSON: String) {
    self.id = id
    self.name = name
    self.inputJSON = inputJSON
  }
}

package struct InferenceMessage: Sendable {
  package let role: String
  package let content: String
  /// Ephemeral model state within this request, never evidence or saved history.
  package let reasoning: String
  package let toolCalls: [InferenceCall]
  package let toolCallId: String?
  package let toolName: String?
  /// Verified host-owned lookup choices, not model text or citation authority.
  package let itemReferences: [String]
  /// Exact original passages supplied by a read or host continuation projection.
  package let documentCopyIDs: [String]
  /// Host capabilities for this live conversation, never parsed from content.
  package let conversationActions: [String]?
  package init(
    role: String, content: String, toolCalls: [InferenceCall] = [],
    toolCallId: String? = nil, toolName: String? = nil, reasoning: String = "",
    itemReferences: [String] = [], conversationActions: [String]? = nil,
    documentCopyIDs: [String] = []
  ) {
    self.role = role
    self.content = content
    self.reasoning = reasoning
    self.toolCalls = toolCalls
    self.toolCallId = toolCallId
    self.toolName = toolName
    self.itemReferences = itemReferences
    self.documentCopyIDs = documentCopyIDs
    self.conversationActions = conversationActions
  }
}

package struct NativeReply: Sendable {
  package let text: String
  package let reasoning: String
  package let calls: [InferenceCall]
  package init(text: String, calls: [InferenceCall], reasoning: String = "") {
    self.text = text
    self.reasoning = reasoning
    self.calls = calls
  }
}

package protocol WorkbookInference: Actor {
  var identity: String { get }
  var lastMetrics: Value { get }
  var supportsCompaction: Bool { get }
  func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, citationIDs: [String], progress: @escaping @Sendable (String) -> Void
  ) async throws -> ContextMeasurement
  func summarize(
    messages: [InferenceMessage], allowedMessageIDs: [String], directory: URL,
    cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) async throws -> String
  func beginRun() async throws
  func endRun() async
  func releaseResources() async -> Bool
  func interpret(
    request: Value, directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void
  ) async throws -> Value
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply
}

// Synthetic inference fixtures must explicitly opt in to context maintenance.
extension WorkbookInference {
  package func interpret(
    request: Value, directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void
  ) async throws -> Value {
    throw SevraError(
      "workflow_model", "This model build does not support structured workflow interpretation.")
  }
  // Synthetic fixtures without a resident engine have nothing to release.
  package func releaseResources() async -> Bool { true }
  package var supportsCompaction: Bool { false }
  package func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, citationIDs: [String], progress: @escaping @Sendable (String) -> Void
  ) async throws -> ContextMeasurement {
    throw SevraError("context_capability", "This inference fixture has no context measurement.")
  }
  package func summarize(
    messages: [InferenceMessage], allowedMessageIDs: [String], directory: URL,
    cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) async throws -> String {
    throw SevraError(
      "context_capability", "This inference fixture has no summarization capability.")
  }
}
