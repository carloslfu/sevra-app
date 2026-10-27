import Foundation
import SevraCore
import SwiftUI

/// One preview owns one cancellable verification. Neither late results nor
/// progress from a superseded file may change the currently displayed preview.
@MainActor public final class AssetPreviewSession: ObservableObject {
  @Published public private(set) var file: URL?
  @Published public private(set) var failure: String?
  @Published public private(set) var loading = false
  @Published public private(set) var checkedBytes: Int64 = 0
  @Published public private(set) var totalBytes: Int64 = 0
  private var request = UUID()
  private var cancellation: Cancellation?

  public init() {}

  @discardableResult public func load(
    resolve:
      @escaping @Sendable (
        Cancellation, @escaping @Sendable (Int64, Int64) -> Void
      ) async throws -> URL
  ) async -> Bool {
    guard !Task.isCancelled else { return false }
    cancel()
    let identity = UUID()
    let token = Cancellation()
    request = identity
    cancellation = token
    failure = nil
    loading = true
    let relay = PreviewProgressRelay { [weak self] bytes, total in
      Task { @MainActor [weak self] in
        guard let self, self.request == identity, self.loading, !token.isCancelled else { return }
        self.checkedBytes = max(self.checkedBytes, bytes)
        self.totalBytes = max(0, total)
      }
    }
    defer {
      if request == identity {
        loading = false
        cancellation = nil
      }
    }
    do {
      let result = try await withTaskCancellationHandler {
        try token.check()
        return try await resolve(token) { relay.send($0, $1) }
      } onCancel: {
        token.cancel()
      }
      try Task.checkCancellation()
      try token.check()
      guard request == identity else { return false }
      file = result
      return true
    } catch {
      guard request == identity, !Task.isCancelled, !token.isCancelled else { return false }
      failure = error.localizedDescription
      return false
    }
  }

  public func cancel() {
    request = UUID()
    cancellation?.cancel()
    cancellation = nil
    file = nil
    failure = nil
    loading = false
    checkedBytes = 0
    totalBytes = 0
  }

  public func stop() {
    cancel()
    failure = "Preview stopped. You can retry when you are ready."
  }
}

/// Hashing reports each bounded chunk, but UI delivery stays bounded too.
private final class PreviewProgressRelay: @unchecked Sendable {
  private let lock = NSLock()
  private var last = -Double.infinity
  private let receive: @Sendable (Int64, Int64) -> Void
  init(receive: @escaping @Sendable (Int64, Int64) -> Void) { self.receive = receive }
  func send(_ bytes: Int64, _ total: Int64) {
    lock.lock()
    let now = ProcessInfo.processInfo.systemUptime
    let deliver = now - last >= 0.1
    if deliver { last = now }
    lock.unlock()
    if deliver { receive(bytes, total) }
  }
}
