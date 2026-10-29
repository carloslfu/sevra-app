import Foundation
import SevraCore
import SwiftUI

public struct ReferenceBrowserQuery: Equatable, Sendable {
  public let origin: String
  public let revision: Int
  public let historical: Bool
  public let exact: Bool
  public init(origin: String, revision: Int, historical: Bool = false, exact: Bool = false) {
    self.origin = origin
    self.revision = revision
    self.historical = historical
    self.exact = exact
  }
}

/// A single bounded page. A failed next page keeps the last visible results;
/// changing a query cancels the prior request and starts its keyset afresh.
@MainActor public final class ReferenceBrowserSession: ObservableObject {
  @Published public private(set) var hits: [Value] = []
  @Published public private(set) var nextCursor: String?
  @Published public private(set) var loading = false
  @Published public private(set) var failure: String?
  @Published public private(set) var page = 1
  @Published public private(set) var loadedQuery: ReferenceBrowserQuery?
  private var previous: [String?] = []
  private var currentCursor: String?
  private var request = UUID()
  private var cancellation: Cancellation?
  public var canGoBack: Bool { !previous.isEmpty }
  public init() {}
  public func cancel() {
    request = UUID()
    cancellation?.cancel()
    cancellation = nil
    loading = false
  }
  public func load(_ query: ReferenceBrowserQuery, workbook: Workbook, step: Int = 0) async {
    await load(query, step: step) { cursor, cancel in
      try await Task.detached(priority: .userInitiated) {
        try workbook.referenceLinks(
          query.origin, direction: .incoming,
          targetScope: query.exact ? .exact : .logical, historicalOrigins: query.historical,
          limit: 20, cursor: cursor, cancellation: cancel)
      }.value
    }
  }
  public func load(
    _ query: ReferenceBrowserQuery, step: Int = 0,
    read: @escaping @Sendable (String?, Cancellation) async throws -> Value
  ) async {
    guard !Task.isCancelled, step >= -1, step <= 1 else { return }
    let same = loadedQuery == query
    if step != 0 {
      guard same, !loading, step > 0 ? nextCursor != nil : !previous.isEmpty else { return }
    }
    let cursor = step > 0 ? nextCursor : (step < 0 ? previous.last! : nil)
    cancel()
    if !same {
      hits = []
      nextCursor = nil
      loadedQuery = nil
      previous = []
      page = 1
    }
    failure = nil
    let identity = UUID()
    let control = Cancellation(deadlineAfterSeconds: 3)
    request = identity
    cancellation = control
    loading = true
    defer {
      if request == identity {
        loading = false
        cancellation = nil
      }
    }
    do {
      let result = try await withTaskCancellationHandler {
        let value = try await read(cursor, control)
        try Task.checkCancellation()
        try control.check()
        return value
      } onCancel: {
        control.cancel()
      }
      guard request == identity else { return }
      if step > 0 {
        previous.append(currentCursor)
        if previous.count > 100 { previous.removeFirst() }
        page += 1
      } else if step < 0 {
        previous.removeLast()
        page -= 1
      } else {
        previous = []
        page = 1
      }
      currentCursor = cursor
      hits = result["hits"].array
      nextCursor = result["nextCursor"].string
      loadedQuery = query
    } catch {
      guard request == identity, !Task.isCancelled, !control.isCancelled else { return }
      failure = error.localizedDescription
    }
  }
}
