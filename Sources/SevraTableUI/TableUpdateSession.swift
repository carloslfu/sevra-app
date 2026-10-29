import Foundation
import SevraCore
import SwiftUI

/// Cancels obsolete work and rejects late callbacks when the user changes the review or leaves.
@MainActor public final class TableUpdateSession: ObservableObject {
  @Published public private(set) var source: TableUpdateSource?
  @Published public private(set) var preview: TableUpdatePreview?
  @Published public private(set) var busy = false
  @Published public private(set) var failure: String?
  private var identity = UUID()
  private var control: Cancellation?
  private var publicationToken = UUID().uuidString
  public init() {}

  public func invalidate(clearSource: Bool = false) {
    identity = UUID()
    control?.cancel()
    control = nil
    busy = false
    preview = nil
    if clearSource { source = nil }
    failure = nil
    publicationToken = UUID().uuidString
  }

  public func stop() {
    identity = UUID()
    control?.cancel()
    control = nil
    busy = false
    // Keep a completed preview and its publication token for an exact retry.
    failure = "Stopped. Any completed draft remains in Drafts to review."
  }

  public func inspect(
    read: @escaping @Sendable (Cancellation) async throws -> TableUpdateSource
  ) async {
    invalidate(clearSource: true)
    let (request, cancel) = begin()
    do {
      let value = try await read(cancel)
      guard finish(request) else { return }
      source = value
    } catch { fail(error, request: request) }
  }

  public func inspectChanges(
    read: @escaping @Sendable (Cancellation) async throws -> TableUpdatePreview
  ) async {
    invalidate()
    let (request, cancel) = begin()
    do {
      let value = try await read(cancel)
      guard finish(request) else { return }
      preview = value
    } catch { fail(error, request: request) }
  }

  public func publish(
    write: @escaping @Sendable (String, Cancellation) async throws -> Item
  ) async -> Item? {
    guard !busy, preview != nil else { return nil }
    let token = publicationToken
    let (request, cancel) = begin()
    do {
      let value = try await write(token, cancel)
      guard finish(request) else { return nil }
      return value
    } catch {
      fail(error, request: request)
      return nil
    }
  }

  private func begin() -> (UUID, Cancellation) {
    identity = UUID()
    control?.cancel()
    let cancel = Cancellation()
    control = cancel
    busy = true
    failure = nil
    return (identity, cancel)
  }
  private func finish(_ request: UUID) -> Bool {
    guard request == identity else { return false }
    let publish = !Task.isCancelled && control?.isCancelled == false
    if !publish { control?.cancel() }
    busy = false
    control = nil
    return publish
  }
  private func fail(_ error: Error, request: UUID) {
    guard request == identity else { return }
    busy = false
    if Task.isCancelled { control?.cancel() }
    control = nil
    if !Task.isCancelled { failure = error.localizedDescription }
  }
}
