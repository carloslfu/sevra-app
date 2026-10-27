import Foundation
import SevraCore
import SevraSearchUI

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  if !condition() { throw SevraError("search_ui_check", message) }
}

actor ReadGate {
  private var result: CheckedContinuation<SearchPage, Error>?
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private var started = false
  func read() async throws -> SearchPage {
    try await withCheckedThrowingContinuation { continuation in
      result = continuation
      started = true
      for continuation in waiting { continuation.resume() }
      waiting = []
    }
  }
  func waitForRead() async {
    if started { return }
    await withCheckedContinuation { waiting.append($0) }
  }
  func finish(_ page: SearchPage) {
    result?.resume(returning: page)
    result = nil
  }
  func fail() {
    result?.resume(throwing: SevraError("old", "Old query failed"))
    result = nil
  }
}

@main struct Checks {
  @MainActor static func main() async {
    do {
      try await run()
      print(
        "PASS search pages/Back, typed query invalidation, stale successes/errors, clear/cancel and next-page retry"
      )
    } catch {
      fputs("\(error)\n", stderr)
      exit(1)
    }
  }

  @MainActor static func run() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sevra-search-ui-" + identifier())
    defer { try? FileManager.default.removeItem(at: url) }
    let book = try Workbook.create(at: url, title: "Search state")
    for index in 1...5 {
      _ = try book.addItem(
        category: "source", kind: "note", title: "Amber \(index)", text: "Amber evidence")
    }
    _ = try book.addItem(category: "source", kind: "note", title: "Violet", text: "Violet evidence")
    let revision = try book.revision()
    let amber = SearchQuery(workbook: url, revision: revision, text: "amber")
    let violet = SearchQuery(workbook: url, revision: revision, text: "violet")
    let empty = SearchQuery(workbook: url, revision: revision, text: "  \n")
    let first = try book.search("amber", limit: 3)
    let second = try book.search("amber", limit: 3, cursor: first.nextCursor)
    let other = try book.search("violet")
    let session = SearchSession()
    await session.load(amber) { _ in first }
    await session.load(amber, more: true) { cursor in
      try expect(cursor == first.nextCursor, "Next page must use the exact saved cursor")
      return second
    }
    let allIDs = (first.hits + second.hits).map(\.itemID)
    session.anchor = allIDs.last
    await session.load(amber) { _ in
      throw SevraError("unexpected", "Back must not read page one again")
    }
    try expect(
      session.hits.map(\.itemID) == allIDs && session.anchor == allIDs.last
        && session.failure == nil && session.nextCursor == nil, "Back lost the last page or anchor")

    let cancelledBeforeStart = Task {
      await session.load(violet) { _ in other }
    }
    cancelledBeforeStart.cancel()
    await cancelledBeforeStart.value
    try expect(
      session.loadedQuery == amber && session.hits.map(\.itemID) == allIDs
        && session.anchor == allIDs.last, "A task cancelled before entry cleared current results")

    // Query identity must not conflate workbooks, filters or separator-bearing text.
    for changed in [
      SearchQuery(workbook: url.appendingPathComponent("other"), revision: revision, text: "amber"),
      SearchQuery(workbook: url, revision: revision + 1, text: "amber"),
      SearchQuery(workbook: url, revision: revision, text: "amber", historical: true),
      SearchQuery(workbook: url, revision: revision, text: "amber", kind: "note"),
      SearchQuery(workbook: url, revision: revision, text: "amber", meaning: "actual"),
      SearchQuery(workbook: url, revision: revision, text: "amber", status: "accepted"),
      SearchQuery(workbook: url, revision: revision, text: "amber", scenario: "base"),
    ] { try expect(changed != amber, "A search input is missing from identity") }

    let old = ReadGate()
    let pending = Task { await session.load(violet) { _ in try await old.read() } }
    await old.waitForRead()
    try expect(
      session.hits.isEmpty && session.anchor == nil && session.loading,
      "New query retained old matches")
    await session.load(amber) { _ in first }
    await old.finish(other)
    await pending.value
    try expect(
      session.loadedQuery == amber && session.hits.map(\.itemID) == first.hits.map(\.itemID)
        && !session.loading, "An old successful read replaced the new query")

    let oldError = ReadGate()
    let failing = Task { await session.load(violet) { _ in try await oldError.read() } }
    await oldError.waitForRead()
    await session.load(amber) { _ in first }
    await oldError.fail()
    await failing.value
    try expect(
      session.failure == nil && session.loadedQuery == amber,
      "A stale error leaked into new results")

    let cancelled = ReadGate()
    let cancelling = Task { await session.load(violet) { _ in try await cancelled.read() } }
    await cancelled.waitForRead()
    cancelling.cancel()
    // Even the same query can have a newer read after view cancellation.
    await session.load(violet) { _ in other }
    await cancelled.fail()
    await cancelling.value
    try expect(
      session.failure == nil && session.loadedQuery == violet && !session.loading,
      "A cancelled same-query error replaced the current read")

    let clearing = ReadGate()
    let clearPending = Task { await session.load(amber) { _ in try await clearing.read() } }
    await clearing.waitForRead()
    await session.load(empty) { _ in throw SevraError("unexpected", "Empty query must not read") }
    await clearing.finish(first)
    await clearPending.value
    try expect(
      session.hits.isEmpty && session.nextCursor == nil && session.incomplete == 0
        && session.failure == nil && !session.loading, "Clear left stale content or loading state")

    await session.load(amber) { _ in first }
    let moreGate = ReadGate()
    let more = Task { await session.load(amber, more: true) { _ in try await moreGate.read() } }
    await moreGate.waitForRead()
    await session.load(amber, more: true) { _ in
      throw SevraError("duplicate", "Overlapping next page")
    }
    await moreGate.fail()
    await more.value
    try expect(
      session.hits.map(\.itemID) == first.hits.map(\.itemID)
        && session.nextCursor == first.nextCursor && session.failure != nil && !session.loading,
      "A failed page discarded current evidence or prevented retry")
    await session.load(amber, more: true) { _ in second }
    try expect(
      session.hits.map(\.itemID) == allIDs && session.failure == nil, "Next-page retry failed")

    let revised = SearchQuery(workbook: url, revision: revision + 1, text: "amber")
    session.anchor = allIDs.last
    await session.load(revised) { cursor in
      try expect(cursor == nil, "Revision change reused an old cursor")
      return first
    }
    try expect(
      session.hits.count == first.hits.count && session.anchor == nil,
      "A revision change kept old pages or selection")
    let stalePage = ReadGate()
    let paging = Task {
      await session.load(revised, more: true) { _ in try await stalePage.read() }
    }
    await stalePage.waitForRead()
    await session.load(violet) { _ in other }
    await stalePage.finish(second)
    await paging.value
    try expect(
      session.hits.map(\.itemID) == other.hits.map(\.itemID) && session.nextCursor == nil,
      "An old continuation page appended to another query")

    await session.load(amber) { _ in throw SevraError("expected", "Initial read failed") }
    try expect(
      session.hits.isEmpty && session.loadedQuery == nil && session.failure != nil,
      "Initial failure looked complete")
    await session.load(empty) { _ in other }
    try expect(session.failure == nil && !session.loading, "Empty query retained a previous error")

    let oldWorkbook = ReadGate()
    let switching = Task { await session.load(amber) { _ in try await oldWorkbook.read() } }
    await oldWorkbook.waitForRead()
    session.reset()
    await oldWorkbook.finish(first)
    await switching.value
    try expect(
      session.query == nil && session.loadedQuery == nil && session.hits.isEmpty
        && !session.loading && session.failure == nil,
      "An old workbook search repopulated results after reset")
  }
}
