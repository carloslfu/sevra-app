import Foundation
import SevraCore

/// Serialize and bound ephemeral preview delivery across retries.
/// No preview is written to the workbook or treated as a completed answer. Each update
/// carries the whole picture, so a newer one replaces an older one that arrives late.
final class AnswerPreviewDelivery: @unchecked Sendable {
  private let lock = NSLock()
  private var sequence = 0
  private var text: String?
  private var reasoning: String?
  private var thoughts: [ActivityThought] = []
  private let receive: @Sendable (AnswerPreview) -> Void
  init(_ receive: @escaping @Sendable (AnswerPreview) -> Void) { self.receive = receive }
  /// The answer written so far.
  func update(_ text: String?) {
    change { $0.text = text.map { String($0.prefix(16_000)) } }
  }
  /// The current call's reasoning so far.
  func reasoning(_ text: String?) {
    change { $0.reasoning = text.map { String($0.prefix(ActivityThought.limit)) } }
  }
  /// The run's finished thoughts. The current call's reasoning is now one of them.
  func thoughts(_ value: [ActivityThought]) {
    change {
      $0.thoughts = value
      $0.reasoning = nil
    }
  }
  /// What the current call reasoned before it failed, when it returned nothing.
  var currentReasoning: String? {
    lock.lock()
    defer { lock.unlock() }
    return reasoning
  }
  /// Ends the current call's answer and reasoning. Finished thoughts stay.
  func clear() {
    change {
      $0.text = nil
      $0.reasoning = nil
    }
  }
  private func change(_ edit: (AnswerPreviewDelivery) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    edit(self)
    sequence += 1
    receive(.init(sequence: sequence, text: text, reasoning: reasoning, thoughts: thoughts))
  }
}
