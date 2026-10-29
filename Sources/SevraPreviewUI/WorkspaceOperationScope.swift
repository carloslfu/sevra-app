import Foundation
import SevraCore

public struct WorkspaceOperation: Sendable {
  fileprivate let id = UUID()
  public let cancellation = Cancellation()
}

/// UI ownership is separate from durable completion. Closing a workspace cancels
/// cooperative work and invalidates callbacks, without undoing committed changes.
@MainActor public final class WorkspaceOperationScope {
  private var active: WorkspaceOperation?
  public init() {}

  public func begin() -> WorkspaceOperation? {
    guard active == nil else { return nil }
    let operation = WorkspaceOperation()
    active = operation
    return operation
  }

  public func owns(_ operation: WorkspaceOperation) -> Bool { active?.id == operation.id }

  public func acceptsProgress(_ operation: WorkspaceOperation) -> Bool {
    owns(operation) && !operation.cancellation.isCancelled
  }

  public func cancel() { active?.cancellation.cancel() }

  @discardableResult public func finish(_ operation: WorkspaceOperation) -> Bool {
    guard owns(operation) else { return false }
    active = nil
    return true
  }

  public func invalidate() {
    cancel()
    active = nil
  }
}
