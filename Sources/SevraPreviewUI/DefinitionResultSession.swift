import Foundation
import SevraCore
import SwiftUI

/// One bounded page at a time. Cancelled/late reads cannot cross workbook,
/// component-argument or definition revisions.
@MainActor public final class DefinitionResultSession: ObservableObject {
  @Published public private(set) var evaluation: Value?
  @Published public private(set) var loading = false
  @Published public private(set) var failure: String?
  @Published public private(set) var pageNumber = 1
  public var hasPrevious: Bool { !previous.isEmpty }
  public var hasNext: Bool { evaluation?["nextCursor"].string != nil }
  private var previous: [String?] = []
  private var currentCursor: String?
  private var scope = ""
  private var request = UUID()
  private var control: Cancellation?
  public init() {}
  public func cancel() {
    control?.cancel()
    control = nil
    request = UUID()
    loading = false
  }
  public func load(
    scope: String, direction: Int = 0, force: Bool = false,
    read: @escaping @Sendable (String?, Cancellation) async throws -> Value
  ) async {
    guard !Task.isCancelled else { return }
    let same = self.scope == scope
    if direction == 0 && same && evaluation != nil && !force { return }
    if direction != 0 && (!same || loading) { return }
    let cursor: String?
    if direction > 0 {
      guard let next = evaluation?["nextCursor"].string else { return }
      cursor = next
    } else if direction < 0 {
      guard let last = previous.last else { return }
      cursor = last
    } else {
      cursor = nil
    }
    cancel()
    let identity = UUID()
    let cancellation = Cancellation()
    request = identity
    control = cancellation
    self.scope = scope
    failure = nil
    if direction == 0 {
      evaluation = nil
      previous = []
      currentCursor = nil
      pageNumber = 1
    }
    loading = true
    defer {
      if request == identity {
        loading = false
        control = nil
      }
    }
    do {
      let value = try await withTaskCancellationHandler {
        try cancellation.check()
        let result = try await read(cursor, cancellation)
        try Task.checkCancellation()
        try cancellation.check()
        return result
      } onCancel: {
        cancellation.cancel()
      }
      guard request == identity else { return }
      if direction > 0 {
        previous.append(currentCursor)
        if previous.count > 100 { previous.removeFirst() }
        pageNumber += 1
      } else if direction < 0 {
        previous.removeLast()
        pageNumber -= 1
      }
      evaluation = value
      currentCursor = cursor
    } catch is CancellationError {
    } catch {
      guard request == identity, !Task.isCancelled, !cancellation.isCancelled else { return }
      failure = error.localizedDescription
    }
  }
}
