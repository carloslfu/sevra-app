import Foundation
import SevraCore

/// Window-local progress. Durable steps are reconstructed from tool receipts, and saved
/// thoughts from the run. While the run lasts, its thoughts and the current call's reasoning
/// come from here, for the person to read.
public struct LiveRequestActivity: Sendable {
  public private(set) var conversation: String
  public let started: Date
  public private(set) var requestID: String?
  public private(set) var runID: String?
  public private(set) var status = "Preparing local AI"
  public private(set) var stopping = false
  public private(set) var answerPreview: String?
  /// The current call's reasoning so far.
  public private(set) var reasoning: String?
  /// The run's finished thoughts, in step order.
  public private(set) var thoughts: [ActivityThought] = []
  private var previewSequence = 0
  /// Whether the model is reasoning now, rather than writing a call or an answer.
  public var isReasoning: Bool { !stopping && status == ActivityThought.reasoningPhase }
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
  public mutating func preview(_ text: String?, sequence: Int) {
    show(text, reasoning: reasoning, thoughts: thoughts, sequence: sequence)
  }
  /// One whole update: a newer sequence replaces the answer, reasoning and thoughts together.
  public mutating func show(
    _ text: String?, reasoning: String?, thoughts: [ActivityThought], sequence: Int
  ) {
    guard !stopping, sequence > previewSequence else { return }
    previewSequence = sequence
    answerPreview = text.map { String($0.prefix(16_000)) }
    let current = reasoning?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.reasoning = current?.isEmpty == false ? String(current!.prefix(ActivityThought.limit)) : nil
    self.thoughts = thoughts
  }
  /// Stop keeps the thoughts already shown: they describe what happened.
  public mutating func stop() {
    stopping = true
    answerPreview = nil
    reasoning = nil
    status = "Stopping…"
  }
}
