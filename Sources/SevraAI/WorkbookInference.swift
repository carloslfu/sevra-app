import Foundation
import SevraCore

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
  package let toolCalls: [InferenceCall]
  package let toolCallId: String?
  package let toolName: String?
  package init(
    role: String, content: String, toolCalls: [InferenceCall] = [],
    toolCallId: String? = nil, toolName: String? = nil
  ) {
    self.role = role
    self.content = content
    self.toolCalls = toolCalls
    self.toolCallId = toolCallId
    self.toolName = toolName
  }
}

package struct NativeReply: Sendable {
  package let text: String
  package let calls: [InferenceCall]
  package init(text: String, calls: [InferenceCall]) {
    self.text = text
    self.calls = calls
  }
}

package protocol WorkbookInference: Actor {
  var identity: String { get }
  var lastMetrics: Value { get }
  func beginRun() throws
  func endRun() async
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, finishOnly: Bool, citationIDs: [String]
  ) async throws -> NativeReply
}
