import Foundation
import SevraCore

/// Development/evaluation profiles, not a user setting or a qualified hardware
/// default. All accounting uses the fully rendered prompt's actual token count.
package struct ContextBudget: Sendable {
  package static let maximumMessageBytes = 1024 * 1024
  package enum Profile: Int, Sendable {
    case development8K = 8192
    case evaluation32K = 32768
    case evaluation64K = 65536
    case evaluation128K = 131072
    case evaluation256K = 262144
  }
  package struct Allowance: Sendable {
    package let outputTokens: Int
    package let maintenanceRecommended: Bool
  }
  package let profile: Profile
  package var contextTokens: Int { profile.rawValue }
  package let maximumOutputTokens = 1800
  package let minimumOutputTokens = 256
  // Reserved for the next bounded tool result and recovery framing.
  package let nextToolResultReserve = 2048
  package let recoveryReserve = 256
  /// Owner-selected policy, not a qualification of any context capacity.
  /// Integer arithmetic preserves floor(0.75 * capacity) without overflow.
  package static func maintenanceThreshold(
    capacity: Int, outputTokens: Int = 1800, toolResultTokens: Int = 2048
  ) -> Int {
    guard capacity > 0 else { return 0 }
    let selected = (capacity / 4) * 3 + (capacity % 4) * 3 / 4
    return max(0, min(selected, capacity - outputTokens - toolResultTokens - 256))
  }
  package var maintenanceThreshold: Int {
    Self.maintenanceThreshold(capacity: contextTokens)
  }
  package init(profile: Profile = .development8K) { self.profile = profile }

  /// Allocation safety bound, separate from each backend's exact token limit.
  /// Count call arguments too, without cutting any message or tool pair.
  package static func validateEnvelope(_ messages: [InferenceMessage]) throws {
    try require(
      !messages.isEmpty && messages.count <= 512, "context_structure",
      "The working conversation has too many messages.")
    var remaining = maximumMessageBytes
    func account(_ value: String) throws {
      let count = value.utf8.count
      try require(
        count <= remaining, "context_structure",
        "The working conversation exceeds its preparation limit. Completed changes are saved.")
      remaining -= count
    }
    for message in messages {
      try account(message.role)
      try account(message.content)
      try account(message.reasoning)
      try account(message.toolCallId ?? "")
      try account(message.toolName ?? "")
      for id in message.documentCopyIDs + message.itemReferences
        + (message.historyReferences ?? []) + (message.conversationActions ?? [])
      { try account(id) }
      try account(message.reviewContract.json())
      for id in message.visualCaptureIDs { try account(id) }
      if message.conversationInput { try account("request_input") }
      for call in message.toolCalls {
        try account(call.id)
        try account(call.name)
        try account(call.inputJSON)
      }
    }
  }

  package func allowance(
    promptTokens: Int, outputTokens: Int = 1800, capacity: Int? = nil,
    toolResultTokens: Int = 2048
  ) throws -> Allowance {
    let capacity = min(capacity ?? contextTokens, contextTokens)
    try require(
      outputTokens >= minimumOutputTokens && outputTokens <= 8192
        && toolResultTokens >= 0 && toolResultTokens <= 8192,
      "context_limit", "Invalid response or tool-result budget.")
    let maximumPrompt = capacity - outputTokens - toolResultTokens - recoveryReserve
    try require(
      promptTokens > 0 && promptTokens <= maximumPrompt, "context_limit",
      "This request has insufficient space for a complete response and recovery. Original input and completed changes are saved."
    )
    return Allowance(
      outputTokens: outputTokens,
      maintenanceRecommended: promptTokens
        >= Self.maintenanceThreshold(
          capacity: capacity, outputTokens: outputTokens, toolResultTokens: toolResultTokens))
  }
}
