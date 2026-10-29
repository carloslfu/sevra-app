import Foundation
import SevraCore
import SwiftUI

/// Every input that can change the visible page participates in task identity.
public struct TableQuery: Hashable, Sendable {
  public let workbook: URL?
  public let dataset: String
  public let revision: Int
  public let offset: Int
  public let filter: String
  public let sort: String?
  public let descending: Bool
  public init(
    workbook: URL?, dataset: String, revision: Int, offset: Int,
    filter: String, sort: String?, descending: Bool
  ) {
    self.workbook = workbook
    self.dataset = dataset
    self.revision = revision
    self.offset = offset
    self.filter = filter
    self.sort = sort
    self.descending = descending
  }
}

@MainActor public final class TablePageLoader: ObservableObject {
  @Published public private(set) var page: TablePage?
  @Published public private(set) var failure: String?
  @Published public private(set) var loading = false
  public private(set) var loadedQuery: TableQuery?
  private var request = UUID()
  public init() {}

  public func cancel() {
    request = UUID()
    loading = false
  }

  /// Old successes and failures are discarded even if the underlying read cannot cancel.
  public func load(
    _ query: TableQuery, debounce: Bool = false,
    read: @escaping @Sendable () async throws -> TablePage
  ) async {
    guard !Task.isCancelled else { return }
    let identity = UUID()
    request = identity
    loading = true
    failure = nil
    defer { if request == identity { loading = false } }
    if let loadedQuery,
      loadedQuery.workbook != query.workbook || loadedQuery.dataset != query.dataset
    {
      page = nil
      self.loadedQuery = nil
      failure = nil
    }
    do {
      if debounce { try await Task.sleep(nanoseconds: 180_000_000) }
      try Task.checkCancellation()
      let result = try await read()
      try Task.checkCancellation()
      guard request == identity else { return }
      loadedQuery = query
      page = result
      failure = nil
    } catch is CancellationError {
    } catch {
      guard request == identity, !Task.isCancelled else { return }
      failure = error.localizedDescription
    }
  }
}
