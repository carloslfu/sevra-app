import Foundation
import SevraCore

/// Which ordinary chat tools and instructions this process offers while the general chat
/// tools are built beside today's. Host configuration alone selects it: the model's
/// configuration, which a developer sets through `SEVRA_TOOL_PROFILE`. No request, model
/// output or tool result carries it.
package enum ToolProfile: String, CaseIterable, Sendable {
  /// Today's tools and instructions, byte for byte.
  case current
  /// The general chat tools. Offers today's until its own are built.
  case general

  package static let environmentKey = "SEVRA_TOOL_PROFILE"

  /// Unset selects `current`. An unknown name is refused, never read as a default.
  package static func host(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> ToolProfile {
    guard let name = environment[environmentKey], !name.isEmpty else { return .current }
    guard let profile = ToolProfile(rawValue: name) else {
      throw SevraError(
        "tool_profile", environmentKey + " must be current or general, not " + name + ".")
    }
    return profile
  }

  /// The shared chat instructions. `general` keeps today's text until its own is written.
  package func instructions(current: String) -> String {
    switch self {
    case .current: return current
    case .general:
      // Today's text names the tools sql replaces. Point those sentences at sql.
      return Self.sqlRewording.reduce(current) {
        $0.replacingOccurrences(of: $1.0, with: $1.1)
      } + "\n" + Self.sqlInstructions
    }
  }

  package static let sqlRewording: [(String, String)] = [
    ("discover existing tables with datasets, even if unnamed.",
      "discover existing tables with sql, even if unnamed."),
    ("inspect datasets/spaces as relevant", "inspect tables with sql and spaces as relevant"),
    ("For arithmetic always use calculate or computed table rows.",
      "For arithmetic always use sql or computed table rows."),
    ("Read relevant rows or use compare_rows.", "Read relevant rows with sql."),
    ("Use compare_rows for supplier comparisons.", "Use sql for supplier comparisons."),
    ("Use proposals when the user requests a draft or review before applying.",
      "When the user requests a draft or review before a row change is applied, use sql with draft=true."),
    ("For ordinary tables without an app, workspace_action table.change_rows makes explicitly requested row edits.",
      "For ordinary tables without an app, sql makes explicitly requested row edits."),
  ]

  /// What the general profile adds while `sql` stands beside today's other tools.
  package static let sqlInstructions = """
    Tables: use sql for every table read, count, comparison, total and calculation. The request lists every table and column name under Tables for sql; use those exact names. Let SQL do the arithmetic and report its results; do not calculate in your head. Use round(x, 2) for money and percentages. To add, change or remove rows the user asked for, use sql INSERT, UPDATE or DELETE. Take each value from the request or from a document the request names. If a value a row needs is in neither, do not search or guess: ask the user for it with finish, basis=general. It saves at once with one Undo. When the user asks for a draft or review first, send the UPDATE with draft=true: it saves a proposal for them and changes nothing. Arithmetic on numbers from the request also goes through sql, such as SELECT round(10 * 2.60, 2). Other tools that need a table's id, version or definition_id find them in SELECT * FROM tables. The host attaches the rows a query read to your answer, so finish.citations can stay empty for an answer that rests only on sql results.
    """
}

/// Host-selected scope, never inferred from untrusted retrieved content.
package enum InferenceToolScope: String, CaseIterable, Sendable {
  /// Specialized phases keep today's tools under every tool profile.
  package var specialized: Bool {
    switch self {
    case .movementDirection, .actionDirection, .nativeAppReview, .nativeActionReview, .excelPlan,
      .excelBuild, .excelCalculation, .excelInterface, .workflowAnswer:
      return true
    default: return false
    }
  }

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
    // sql is offered only under the general profile. Outside `.all` the host runs it read-only.
    case .inspection: return WorkbookTools.readOnlyTools.contains(tool) || tool == "sql"
    case .answer:
      return tool == "finish" || WorkbookTools.readOnlyTools.contains(tool) || tool == "sql"
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
  /// The saved conversation, rendered append-only so the next turn's prompt extends it.
  package var conversationHistory = false
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
  /// Fixed when the host configures the model.
  var toolProfile: ToolProfile { get }
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
  package var toolProfile: ToolProfile { .current }
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
