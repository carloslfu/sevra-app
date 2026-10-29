import Foundation
import SevraCore
import SevraPreviewUI

private actor HistoryGate {
  var ready = false
  var continuation: CheckedContinuation<Value, Never>?
  func read() async -> Value {
    await withCheckedContinuation {
      ready = true
      continuation = $0
    }
  }
  func finish(_ value: Value) {
    continuation?.resume(returning: value)
    continuation = nil
  }
}
private func page(_ id: String, next: String? = nil) -> Value {
  .object([
    "hits": .array([.object(["id": .string(id)])]), "nextCursor": next.map(Value.string) ?? .null,
  ])
}

@MainActor func checkHistorySearch() async throws {
  let session = ConversationHistorySearch()
  let gate = HistoryGate()
  let old = Task { await session.load(scope: "main", query: "old") { _, _ in await gate.read() } }
  while !(await gate.ready) { await Task.yield() }
  await session.load(scope: "thread", query: "supplier") { _, _ in page("thread", next: "page2") }
  await gate.finish(page("old-main"))
  await old.value
  try require(
    session.hits.first?["id"].text == "thread", "history_search_check",
    "Old search replaced another thread")
  await session.load(scope: "thread", query: "supplier", direction: 1) { _, _ in
    throw SevraError("fixture", "Read failed")
  }
  try require(
    session.failure != nil && session.hits.first?["id"].text == "thread"
      && session.nextCursor == "page2",
    "history_search_check", "Failed next page lost results or retry cursor")
  await session.load(
    scope: "thread", query: "supplier", direction: session.failedDirection, force: true
  ) { cursor, _ in
    try require(cursor == "page2", "history_search_check", "Wrong next cursor")
    return page("second")
  }
  try require(
    session.pageNumber == 2 && session.hasPrevious && session.hits.count == 1,
    "history_search_check", "Search appended unbounded results or lost Previous")
  await session.load(scope: "thread", query: "supplier", direction: -1) { cursor, _ in
    try require(cursor == nil, "history_search_check", "Wrong previous cursor")
    return page("thread", next: "page2")
  }
  try require(
    session.pageNumber == 1 && !session.hasPrevious, "history_search_check",
    "Previous did not return to first page")
  let closing = HistoryGate()
  let pending = Task {
    await session.load(scope: "thread", query: "pending") { _, _ in await closing.read() }
  }
  while !(await closing.ready) { await Task.yield() }
  session.reset()
  await closing.finish(page("closed"))
  await pending.value
  try require(
    session.hits.isEmpty && session.query.isEmpty && !session.loading && session.failure == nil,
    "history_search_check", "Closed search published a late result")
  print("PASS scoped history search, stale results, bounded next/previous pages, retry and close")
}
