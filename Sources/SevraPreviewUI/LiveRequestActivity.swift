import Foundation
import SevraCore

/// Window-local progress. Durable steps are reconstructed from tool receipts.
/// Token updates contain counts and phases only, never private reasoning text.
public struct LiveRequestActivity: Sendable {
  public private(set) var conversation: String
  public let started: Date
  public private(set) var requestID: String?
  public private(set) var runID: String?
  public private(set) var status = "Preparing local AI"
  public private(set) var stopping = false
  public var title: String {
    for phase in ["Processing context", "Reasoning", "Preparing a response"]
    where status.hasPrefix(phase + " · ") { return phase }
    return status
  }
  public init(conversation: String, started: Date = Date()) {
    self.conversation = conversation
    self.started = started
  }
  public mutating func attach(_ request: AgentRequest, conversation: String) {
    guard !stopping else { return }
    self.conversation = conversation
    requestID = request.messageID
    runID = request.runID
  }
  public mutating func update(_ value: String) {
    guard !stopping else { return }
    status = String(value.prefix(500))
  }
  public mutating func stop() {
    stopping = true
    status = "Stopping…"
  }
}
