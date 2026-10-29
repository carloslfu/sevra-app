import Foundation
import SevraCore
import SwiftUI

/// Bounded current-draft pages. A changed workbook restarts at current data;
/// cancelled or late reads cannot replace another workbook's list.
@MainActor public final class ReviewQueueSession: ObservableObject {
  @Published public private(set) var items: [ItemSummary] = []
  @Published public private(set) var loading = false
  @Published public private(set) var failure: String?
  @Published public private(set) var pageNumber = 1
  public private(set) var nextCursor: String?
  public var hasPrevious: Bool { !previous.isEmpty }
  private var previous: [String?] = []
  private var currentCursor: String?
  private var scope = ""
  private var revision = -1
  private var request = UUID()
  private var control: Cancellation?
  private var completed = false
  public init() {}
  public func cancel() {
    control?.cancel()
    control = nil
    request = UUID()
    loading = false
  }
  public func reset() {
    cancel()
    items = []
    previous = []
    nextCursor = nil
    currentCursor = nil
    pageNumber = 1
    scope = ""
    revision = -1
    failure = nil
    completed = false
  }
  public func load(
    scope: String, revision: Int, direction: Int = 0, force: Bool = false,
    read: @escaping @Sendable (String?, Cancellation) async throws -> ReviewQueuePage
  ) async {
    guard !Task.isCancelled else { return }
    let same = self.scope == scope && self.revision == revision
    if direction == 0 && same && completed && !force { return }
    if direction != 0 && (!same || loading) { return }
    let cursor: String?
    if direction > 0 {
      guard let nextCursor else { return }
      cursor = nextCursor
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
    self.revision = revision
    failure = nil
    if direction == 0 {
      items = []
      previous = []
      nextCursor = nil
      currentCursor = nil
      pageNumber = 1
      completed = false
    }
    loading = true
    defer {
      if request == identity {
        loading = false
        control = nil
      }
    }
    do {
      let page = try await withTaskCancellationHandler {
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
      items = page.items
      currentCursor = cursor
      nextCursor = page.nextCursor
      completed = true
    } catch {
      guard request == identity, !Task.isCancelled, !cancellation.isCancelled else { return }
      failure = error.localizedDescription
    }
  }
}
