import Foundation

/// Serialize and bound ephemeral preview delivery across retries.
/// No preview is written to the workbook or treated as a completed answer.
final class AnswerPreviewDelivery: @unchecked Sendable {
  private let lock = NSLock()
  private var sequence = 0
  private let receive: @Sendable (AnswerPreview) -> Void
  init(_ receive: @escaping @Sendable (AnswerPreview) -> Void) { self.receive = receive }
  func update(_ text: String?) {
    lock.lock()
    defer { lock.unlock() }
    sequence += 1
    receive(.init(sequence: sequence, text: text.map { String($0.prefix(16_000)) }))
  }
  func clear() { update(nil) }
}
