import Foundation
import SevraCore
import SevraPreviewUI

private actor DefinitionPageGate {
  var ready = false
  var continuation: CheckedContinuation<Value, Error>?
  func read() async throws -> Value {
    try await withCheckedThrowingContinuation {
      ready = true
      continuation = $0
    }
  }
  func finish(_ value: Value) {
    continuation?.resume(returning: value)
    continuation = nil
  }
  func fail() {
    continuation?.resume(throwing: SevraError("stale_query", "Changed input"))
    continuation = nil
  }
}

private func definitionTestPage(_ result: String, next: String? = nil) -> Value {
  .object(["result": .string(result), "nextCursor": next.map(Value.string) ?? .null])
}

@MainActor func checkDefinitionResultSession() async throws {
  func expect(_ value: @autoclosure () -> Bool) throws {
    try require(
      value(), "result_session_check", "A stale native computation changed its current result.")
  }
  let session = DefinitionResultSession()
  let old = DefinitionPageGate()
  let first = Task { await session.load(scope: "workbookA/args1") { _, _ in try await old.read() } }
  while !(await old.ready) { await Task.yield() }
  await session.load(scope: "workbookB/args2") { _, _ in definitionTestPage("new", next: "page2") }
  await old.finish(definitionTestPage("obsolete"))
  await first.value
  try expect(session.evaluation?["result"] == .string("new") && session.hasNext)
  await session.load(scope: "workbookB/args2", direction: 1) { cursor, _ in
    try require(cursor == "page2", "test", "Continuation changed")
    return definitionTestPage("second")
  }
  try expect(session.pageNumber == 2 && session.hasPrevious && !session.hasNext)
  await session.load(scope: "workbookB/args2", direction: -1) { cursor, _ in
    try require(cursor == nil, "test", "Back did not restore first page")
    return definitionTestPage("new", next: "page2")
  }
  try expect(session.pageNumber == 1 && !session.hasPrevious)
  let errorGate = DefinitionPageGate()
  let errorTask = Task {
    await session.load(scope: "old-error") { _, _ in try await errorGate.read() }
  }
  while !(await errorGate.ready) { await Task.yield() }
  await session.load(scope: "new-error") { _, _ in definitionTestPage("current") }
  await errorGate.fail()
  await errorTask.value
  try expect(session.failure == nil && session.evaluation?["result"] == .string("current"))
  let cancelGate = DefinitionPageGate()
  let cancelTask = Task {
    await session.load(scope: "cancelled") { _, _ in try await cancelGate.read() }
  }
  while !(await cancelGate.ready) { await Task.yield() }
  session.cancel()
  await cancelGate.finish(definitionTestPage("cancelled values"))
  await cancelTask.value
  try expect(session.evaluation == nil && !session.loading)
  await session.load(scope: "retry") { _, _ in throw SevraError("test", "Visible failure") }
  try expect(session.failure != nil && session.evaluation == nil)
  await session.load(scope: "retry", force: true) { _, _ in definitionTestPage("recovered") }
  try expect(session.failure == nil && session.evaluation?["result"] == .string("recovered"))
  print(
    "PASS native computation pages reject stale successes/errors, preserve page cursors and cancel/retry"
  )
}
