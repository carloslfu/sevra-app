import Foundation
import SevraCore

/// Host-selected scope, never inferred from untrusted retrieved content.
package enum InferenceToolScope: String, CaseIterable, Sendable {
  // Tool scopes retain the public tool names as their raw values.
  // swift-format-ignore: AlwaysUseLowerCamelCase
  case all, finish, inspection, movementDirection, actionDirection, nativeAppReview,
    nativeActionReview, excelPlan,
    excelBuild, excelCalculation, excelInterface, workflowAnswer,
    answer, conversationAnswer,
    boundedAnswer, boundedConversationAnswer, draft,
    save_space, save_native_app,
    edit_space,
    restore_space, propose_movement,
    propose_record,
    propose_table, propose_table_edit

  package var workspaceOperations: [ChatOperations.Operation] {
    switch self {
    case .all: return ChatOperations.operations
    case .conversationAnswer, .boundedConversationAnswer:
      return ChatOperations.operations.filter {
        $0.readOnly
          && (!$0.host
            || [
              "visual.open_source", "visual.image_view", "visual.app_capture", "visual.app_sources",
              "visual.open_current", "visual.expand", "visual.app_preset_info",
              "visual.app_diagram_positions", "app.inspect", "app.browse",
            ].contains($0.name))
      }
    default: return []
    }
  }

  package func allows(_ tool: String, conversationInput: Bool = false) -> Bool {
    if tool == "request_input" {
      guard conversationInput else { return false }
      switch self {
      case .all, .finish, .answer, .boundedAnswer, .conversationAnswer, .boundedConversationAnswer,
        .draft, .save_space, .save_native_app,
        .edit_space, .restore_space, .propose_movement, .propose_record, .propose_table,
        .propose_table_edit:
        return true
      default:
        return false
      }
    }
    switch self {
    case .all:
      // The host commits a preview itself, after prepare_action reviews every direction.
      return ![
        "review_movement_direction", "review_action_directions", "prepare_workflow_answer",
        "commit_action_preview", "review_native_app", "describe_excel_workflow",
        "inspect_excel_rows", "inspect_excel_evidence", "compare_excel_behavior",
      ].contains(tool)
    case .workflowAnswer: return Self.answer.allows(tool) || tool == "prepare_workflow_answer"
    case .movementDirection: return tool == "review_movement_direction"
    case .actionDirection: return tool == "review_action_directions"
    case .nativeAppReview, .nativeActionReview: return tool == "review_native_app"
    case .excelPlan:
      return ["describe_excel_workflow", "inspect_excel_rows", "inspect_excel_evidence"].contains(
        tool)
    case .excelBuild:
      return [
        "native_app_sdk", "read_native_app", "datasets", "rows", "calculate", "save_native_app",
        "inspect_excel_evidence", "compare_excel_behavior", "tool_result",
      ].contains(tool)
    case .excelCalculation:
      return [
        "native_app_sdk", "datasets", "rows", "calculate",
        "inspect_excel_evidence", "compare_excel_behavior", "tool_result",
      ].contains(tool)
    case .excelInterface:
      return [
        "native_app_sdk", "read_native_app", "datasets", "rows", "calculate",
        "save_native_app", "inspect_excel_evidence", "tool_result",
        "compare_excel_behavior",
      ].contains(tool)
    case .finish: return tool == "finish"
    case .inspection: return WorkbookTools.readOnlyTools.contains(tool)
    case .answer:
      return tool == "finish" || WorkbookTools.readOnlyTools.contains(tool)
    case .conversationAnswer:
      return Self.answer.allows(tool) || tool == "workspace_action"
    case .boundedAnswer:
      return Self.answer.allows(tool) && !["search", "history_search"].contains(tool)
    case .boundedConversationAnswer:
      return Self.boundedAnswer.allows(tool) || tool == "workspace_action"
    case .propose_movement:
      // Saved inventory actions still pass the complete movement review. A
      // future primitive without movements refuses there before submission.
      return Self.answer.allows(tool) || tool == rawValue || tool == "prepare_action"
    case .propose_record:
      return Self.answer.allows(tool) || tool == rawValue || tool == "publish_result"
    case .draft, .save_space, .save_native_app, .edit_space, .restore_space,
      .propose_table,
      .propose_table_edit:
      return Self.answer.allows(tool) || tool == rawValue
    }
  }
}

/// App-owned conversation values. The candidate and preserved baseline use the
/// same workbook loop; this internal seam is not a provider catalog or user API.
package struct InferenceCall: Encodable, Sendable {
  package let id: String
  package let name: String
  package let inputJSON: String
  package init(id: String, name: String, inputJSON: String) {
    self.id = id
    self.name = name
    self.inputJSON = inputJSON
  }
}

package struct InferenceMessage: Encodable, Sendable {
  /// Exact, host-authored part of the system message shared across ordinary workbook turns.
  package var cacheablePolicy: String?
  package var scopePolicy = ""
  package var visibleContext = ""
  package var countReceiptIDs: [String]?
  /// Only the first decision of a new, ordinary interactive request.
  package var initialChatDecision = false
  package var hasCalculationResult = false
  /// Host state, reattached after context maintenance; never inferred from model prose.
  package var nativeAppAuthoring = false
  package var conversationInput = false
  package var visualCaptureIDs: [String] = []
  /// Host-observed action contracts and worksheet columns for independent review.
  package var reviewContract: Value = .null
  package let role: String
  package var content: String
  /// Ephemeral model state within this request, never evidence or saved history.
  package let reasoning: String
  package let toolCalls: [InferenceCall]
  package let toolCallId: String?
  package let toolName: String?
  /// Verified host-owned lookup choices, not model text or citation authority.
  package var itemReferences: [String]
  /// Earlier messages named in this context. Nil leaves history_read unconstrained.
  package var historyReferences: [String]?
  /// Exact original passages supplied by a read or host continuation projection.
  package let documentCopyIDs: [String]
  /// Host capabilities for this live conversation, never parsed from content.
  package let conversationActions: [String]?
  package init(
    role: String, content: String, toolCalls: [InferenceCall] = [],
    toolCallId: String? = nil, toolName: String? = nil, reasoning: String = "",
    itemReferences: [String] = [], conversationActions: [String]? = nil,
    documentCopyIDs: [String] = [], historyReferences: [String]? = nil
  ) {
    self.role = role
    self.content = content
    self.reasoning = reasoning
    self.toolCalls = toolCalls
    self.toolCallId = toolCallId
    self.toolName = toolName
    self.itemReferences = itemReferences
    self.historyReferences = historyReferences
    self.documentCopyIDs = documentCopyIDs
    self.conversationActions = conversationActions
  }
}

package struct NativeReply: Sendable {
  package let text: String
  package let reasoning: String
  package let calls: [InferenceCall]
  /// Why a tool call the model wrote was dropped. The workbook loop tells the model.
  package let refusal: String?
  package init(
    text: String, calls: [InferenceCall], reasoning: String = "", refusal: String? = nil
  ) {
    self.text = text
    self.reasoning = reasoning
    self.calls = calls
    self.refusal = refusal
  }
}

package protocol WorkbookInference: Actor {
  var identity: String { get }
  var lastMetrics: Value { get }
  var supportsCompaction: Bool { get }
  func measureContext(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    summary: Bool, toolScope: InferenceToolScope, citationIDs: [String],
    progress: @escaping @Sendable (String) -> Void
  ) async throws -> ContextMeasurement
  func boundToolResult(
    _ value: Value, receiptID: String, directory: URL, cancellation: Cancellation,
    toolScope: InferenceToolScope, nativeAppAuthoring: Bool
  ) async throws -> Value
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
  func respondStreaming(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String], answerPreview: @escaping @Sendable (String) -> Void
  ) async throws -> NativeReply
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply
}

/// A provisional answer, never a saved result or action receipt. Sequence numbers
/// let UI delivery discard delayed updates after a retry or final clear.
public struct AnswerPreview: Sendable {
  public let sequence: Int
  public let text: String?
  public init(sequence: Int, text: String?) {
    self.sequence = sequence
    self.text = text
  }
}

// Synthetic inference fixtures must explicitly opt in to context maintenance.
extension WorkbookInference {
  package func respondStreaming(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String], answerPreview: @escaping @Sendable (String) -> Void
  ) async throws -> NativeReply {
    try await respond(
      messages: messages, directory: directory, cancellation: cancellation,
      progress: progress, toolScope: toolScope, citationIDs: citationIDs)
  }
  // CPU fixtures preserve their scripted presentation. Native inference applies
  // the actual selected tokenizer before any evidence is admitted.
  package func boundToolResult(
    _ value: Value, receiptID: String, directory: URL, cancellation: Cancellation,
    toolScope: InferenceToolScope, nativeAppAuthoring: Bool
  ) async throws -> Value { value }
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
    summary: Bool, toolScope: InferenceToolScope, citationIDs: [String],
    progress: @escaping @Sendable (String) -> Void
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
