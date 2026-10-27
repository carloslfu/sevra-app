import Foundation
import SevraCore

public struct WorkspaceReadIdentity: Equatable, Sendable {
  public let workbook: ObjectIdentifier
  public let window: UUID
  public let conversation: String
  public let messageAnchor: String?

  public init(workbook: Workbook, window: UUID, conversation: String, messageAnchor: String?) {
    self.workbook = ObjectIdentifier(workbook)
    self.window = window
    self.conversation = conversation
    self.messageAnchor = messageAnchor
  }
}

/// One background read plus at most one pending refresh. Timer ticks cannot
/// accumulate waiters, and closing/switching the view invalidates late callbacks.
@MainActor public final class WorkspaceRefreshSession {
  private struct Request {
    let id = UUID()
    let read: @Sendable (Cancellation) throws -> WorkspaceSnapshot?
    let complete: @MainActor (Result<WorkspaceSnapshot?, Error>) -> Void
  }
  private var active: Cancellation?
  private var pending: Request?
  private var latest = UUID()
  public private(set) var identity: WorkspaceReadIdentity?
  public var isRefreshing: Bool { active != nil }
  public init() {}

  public func request(
    identity: WorkspaceReadIdentity, onlyWhenIdle: Bool = false,
    read: @escaping @Sendable (Cancellation) throws -> WorkspaceSnapshot?,
    complete: @escaping @MainActor (Result<WorkspaceSnapshot?, Error>) -> Void
  ) {
    if onlyWhenIdle && active != nil { return }
    self.identity = identity
    let request = Request(read: read, complete: complete)
    latest = request.id
    pending = request
    active?.cancel()
    launchNext()
  }

  public func reset() {
    latest = UUID()
    identity = nil
    pending = nil
    active?.cancel()
  }

  private func launchNext() {
    guard active == nil, let request = pending else { return }
    pending = nil
    let control = Cancellation()
    active = control
    Task {
      let outcome: Result<WorkspaceSnapshot?, Error>
      do {
        let snapshot = try await Task.detached(priority: .userInitiated) {
          try control.check()
          let snapshot = try request.read(control)
          try control.check()
          return snapshot
        }.value
        outcome = .success(snapshot)
      } catch { outcome = .failure(error) }
      // Clear the worker before calling application code, which may enqueue a
      // new refresh. Ownership is checked before publishing success or failure.
      active = nil
      if latest == request.id && !control.isCancelled { request.complete(outcome) }
      launchNext()
    }
  }
}
