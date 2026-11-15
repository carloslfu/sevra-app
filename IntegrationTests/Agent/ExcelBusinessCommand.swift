import Foundation
import SevraAppUI
import SevraCore

extension NativeAppSession {
  /// These scenarios qualify business behavior and paging, not overload handling.
  /// Pace synthetic host commands below the production 16-transaction/second cap.
  /// A runaway action remains subject to the unchanged worker/session budgets.
  @MainActor func businessCommand(
    _ operation: String, arguments: Value = .object([:]),
    readOnly: Bool = false, cancellation: Cancellation = .init()
  ) async throws -> Value {
    try cancellation.check()
    try await Task.sleep(nanoseconds: 100_000_000)
    try cancellation.check()
    return try await converse(
      operation, arguments: arguments, readOnly: readOnly, cancellation: cancellation)
  }
}
