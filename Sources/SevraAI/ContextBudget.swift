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
  }
  package struct Allowance: Sendable {
    package let outputTokens: Int
    package let maintenanceRecommended: Bool
  }
  package let profile: Profile
  package var contextTokens: Int { profile.rawValue }
  package let maximumOutputTokens = 1800
  package let minimumOutputTokens = 256
  // Provisional instrumentation for C04. The maintenance controller must use
  // these before dispatch; this budget alone does not compact any history.
  package let nextToolResultReserve = 2048
  package let recoveryReserve = 256
  /// Owner-selected policy, not a qualification of any context capacity.
  /// Integer arithmetic preserves floor(0.75 * capacity) without overflow.
  package static func maintenanceThreshold(capacity: Int) -> Int {
    guard capacity > 0 else { return 0 }
    let selected = (capacity / 4) * 3 + (capacity % 4) * 3 / 4
    return max(0, min(selected, capacity - 1800 - 2048 - 256))
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
      for call in message.toolCalls {
        try account(call.id)
        try account(call.name)
        try account(call.inputJSON)
      }
    }
  }

  package func allowance(promptTokens: Int) throws -> Allowance {
    try require(
      promptTokens > 0 && promptTokens <= contextTokens, "context_limit",
      "The rendered prompt is outside the configured context budget.")
    let output = min(maximumOutputTokens, contextTokens - promptTokens)
    try require(
      output >= minimumOutputTokens, "context_limit",
      "This exploration reached its context budget. Completed changes are saved.")
    return Allowance(
      outputTokens: output, maintenanceRecommended: promptTokens >= maintenanceThreshold)
  }
}
