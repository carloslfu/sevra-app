import Foundation
import SevraCore
import SwiftUI

/// A bounded page of original visible messages. Search never changes the draft
/// or admits retrieved text as a new instruction. Late results cannot cross scope.
@MainActor public final class ConversationHistorySearch: ObservableObject {
  @Published public private(set) var hits: [Value] = []
  @Published public private(set) var loading = false
  @Published public private(set) var failure: String?
  public private(set) var failedDirection = 0
  @Published public private(set) var query = ""
  @Published public private(set) var nextCursor: String?
  @Published public private(set) var pageNumber = 1
  private var scope: String?
  private var currentCursor: String?
  private var previous: [String?] = []
  private var request = UUID()
  private var control: Cancellation?
  private var completed = false
  public var hasPrevious: Bool { !previous.isEmpty }
  public init() {}
  public func cancel() {
    control?.cancel()
    control = nil
    request = UUID()
    loading = false
  }
  public func reset() {
    cancel()
    hits = []
    query = ""
    scope = nil
    nextCursor = nil
    currentCursor = nil
    previous = []
    pageNumber = 1
    failure = nil
    failedDirection = 0
    completed = false
  }
  public func load(
    scope: String, query: String, direction: Int = 0, debounce: Bool = false, force: Bool = false,
    read: @escaping @Sendable (String?, Cancellation) async throws -> Value
  ) async {
    guard !Task.isCancelled else { return }
    let same = self.scope == scope && self.query == query
    if direction == 0 && same && completed && !force { return }
    if direction != 0 && (!same || loading) { return }
    let cursor: String?
    if direction > 0 {
      guard let nextCursor else { return }
      cursor = nextCursor
    } else if direction < 0 {
      guard let prior = previous.last else { return }
      cursor = prior
    } else {
      cursor = nil
    }
    cancel()
    let identity = UUID()
    let cancellation = Cancellation()
    request = identity
    control = cancellation
    self.scope = scope
    self.query = query
    failure = nil
    if direction == 0 {
      hits = []
      previous = []
      pageNumber = 1
      nextCursor = nil
      currentCursor = nil
      completed = false
    }
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      completed = true
      return
    }
    loading = true
    defer {
      if request == identity {
        control = nil
        loading = false
      }
    }
    do {
      let value = try await withTaskCancellationHandler {
        if debounce { try await Task.sleep(nanoseconds: 180_000_000) }
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
      }
      if direction < 0 {
        previous.removeLast()
        pageNumber -= 1
      }
      hits = value["hits"].array
      nextCursor = value["nextCursor"].string
      currentCursor = cursor
      completed = true
    } catch {
      guard request == identity, !Task.isCancelled, !cancellation.isCancelled else { return }
      failure = error.localizedDescription
      failedDirection = direction
    }
  }
}
