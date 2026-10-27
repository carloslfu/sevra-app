import Foundation
import SevraCore
import SwiftUI

public struct SearchQuery: Hashable, Sendable {
  public let workbook: URL?
  public let revision: Int
  public let text: String
  public let historical: Bool
  public let kind: String?
  public let meaning: String?
  public let status: String?
  public let scenario: String?

  public init(
    workbook: URL?, revision: Int, text: String, historical: Bool = false,
    kind: String? = nil, meaning: String? = nil, status: String? = nil, scenario: String? = nil
  ) {
    self.workbook = workbook
    self.revision = revision
    self.text = text
    self.historical = historical
    self.kind = kind
    self.meaning = meaning
    self.status = status
    self.scenario = scenario
  }

  public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Owned by the workbook window so temporary viewers cannot discard loaded pages.
@MainActor public final class SearchSession: ObservableObject {
  @Published public private(set) var hits: [SearchHit] = []
  @Published public private(set) var nextCursor: String?
  @Published public private(set) var incomplete = 0
  @Published public private(set) var loading = false
  @Published public private(set) var failure: String?
  @Published public private(set) var query: SearchQuery?
  @Published public private(set) var loadedQuery: SearchQuery?
  @Published public var anchor: String?
  private var request = UUID()
  private var cancellation: Cancellation?
  public init() {}

  /// Leaving the view keeps completed pages for Back, but releases its reader.
  public func cancelRead() {
    cancellation?.cancel()
    cancellation = nil
    request = UUID()
    loading = false
  }

  public func reset() {
    cancelRead()
    query = nil
    loadedQuery = nil
    hits = []
    nextCursor = nil
    incomplete = 0
    anchor = nil
    failure = nil
    loading = false
  }

  public func load(
    _ query: SearchQuery, more: Bool = false, debounce: Bool = false,
    read: @escaping @Sendable (String?, Cancellation) async throws -> SearchPage
  ) async {
    // SwiftUI may cancel a superseded task before its actor entry runs.
    // That task must not claim ownership or clear a newer result set.
    guard !Task.isCancelled else { return }
    let cursor: String?
    if more {
      guard loadedQuery == query, !loading, let nextCursor else { return }
      cursor = nextCursor
    } else {
      // Returning from a preview preserves every loaded page, including a failed
      // next-page request that the user can explicitly retry.
      guard loadedQuery != query else { return }
      cursor = nil
    }
    cancellation?.cancel()
    let control = Cancellation()
    cancellation = control
    let identity = UUID()
    request = identity
    self.query = query
    failure = nil
    if !more {
      hits = []
      nextCursor = nil
      incomplete = 0
      anchor = nil
      loadedQuery = nil
    }
    defer {
      if request == identity {
        cancellation = nil
        loading = false
      }
    }
    guard !query.isEmpty else {
      loading = false
      loadedQuery = query
      return
    }
    loading = true
    do {
      let page = try await withTaskCancellationHandler {
        if debounce { try await Task.sleep(nanoseconds: 180_000_000) }
        try Task.checkCancellation()
        try control.check()
        let result = try await read(cursor, control)
        try Task.checkCancellation()
        try control.check()
        return result
      } onCancel: {
        control.cancel()
      }
      guard request == identity else { return }
      hits = more ? hits + page.hits : page.hits
      nextCursor = page.nextCursor
      incomplete = page.incomplete
      loadedQuery = query
    } catch is CancellationError {
    } catch {
      guard request == identity, !Task.isCancelled, !control.isCancelled else { return }
      failure = error.localizedDescription
    }
  }
}
