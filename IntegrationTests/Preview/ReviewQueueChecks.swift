import Foundation
import SevraCore
import SevraPreviewUI

private actor ReviewReadGate {
  var ready = false
  var continuation: CheckedContinuation<ReviewQueuePage, Never>?
  func read() async -> ReviewQueuePage {
    await withCheckedContinuation {
      ready = true
      continuation = $0
    }
  }
  func finish(_ page: ReviewQueuePage) {
    continuation?.resume(returning: page)
    continuation = nil
  }
}

@MainActor func checkReviewQueue() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-review-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root.appendingPathComponent("Queue.sevra"), title: "Review")
  func expect(_ value: @autoclosure () throws -> Bool) throws {
    try require(try value(), "review_queue_check", "Current draft discovery or paging changed.")
  }
  let source = try book.addItem(
    category: "source", kind: "observation", title: "Opening stock",
    text: "20 fittings", status: "accepted")
  try book.setOpeningBalance(
    subject: "fittings", quantity: "20", effective: "2026-01-01", sourceID: source.id)
  let move = try book.movement(
    subject: "fittings", quantity: "-2", occurrence: "sale-1",
    effective: "2026-01-02", input: source.id)
  var expected = Set([move.id])
  for index in 0..<24 {
    let item = try book.addItem(
      category: "record", kind: "analysis", title: "Draft \(index)",
      text: String(repeating: "Evidence remains in the original. ", count: 100),
      meaning: "estimate", inputs: [source.id])
    expected.insert(item.id)
  }
  for kind in ["row", "request"] {
    _ = try book.addItem(category: "source", kind: kind, title: "Not a standalone review")
  }
  for index in 0..<30 {
    _ = try book.addItem(
      category: "source", kind: "note", title: "Recent accepted \(index)", status: "accepted")
  }
  let before = try encoded(book.item(source.id))
  let first = try book.reviewQueue(limit: 20)
  try expect(first.items.count == 20 && first.nextCursor != nil)
  _ = try book.addMessage("Unrelated conversation activity", role: "user")
  try expect(try book.reviewQueue().revision == first.revision)
  let last = try book.reviewQueue(cursor: first.nextCursor, limit: 20)
  try expect(last.items.count == 5 && last.nextCursor == nil)
  try expect(Set((first.items + last.items).map(\.id)) == expected)
  try expect(Set(first.items.map(\.id)).isDisjoint(with: last.items.map(\.id)))
  let home = try book.workspaceSnapshot(conversation: "main")!.reviewQueue
  try expect(home.items.count == 5 && home.nextCursor != nil)
  try expect(try book.balance(subject: "fittings")["quantity"].text == "20")
  let declined = try book.withdrawDraft(move.id, token: "withdraw-once")
  try expect(try book.withdrawDraft(move.id, token: "withdraw-once").id == declined.id)
  try expect(try book.reviewQueue(limit: 100).items.count == 24)
  try expect(try book.balance(subject: "fittings")["quantity"].text == "20")
  try expect(try book.item(move.id).status == "draft")
  let restored = try book.undoItem(declined.id)
  try expect(restored.status == "draft")
  try expect(try book.reviewQueue(limit: 100).items.count == 25)
  do {
    _ = try book.withdrawDraft(move.id)
    throw SevraError("test", "An obsolete draft was withdrawn")
  } catch let error as SevraError where error.code == "stale_revision" {}
  let accepted = try book.accept(restored.id)
  expected.remove(move.id)
  try expect(try book.balance(subject: "fittings")["quantity"].text == "18")
  try expect(
    !book.reviewQueue(limit: 100).items.contains { $0.id == move.id || $0.id == accepted.id })
  do {
    _ = try book.reviewQueue(cursor: first.nextCursor)
    throw SevraError("test", "A stale review cursor was accepted")
  } catch let error as SevraError where error.code == "stale_review_page" {}
  do {
    _ = try book.withdrawDraft(accepted.id)
    throw SevraError("test", "An accepted change was withdrawn as an unapplied draft")
  } catch let error as SevraError where error.code == "not_draft" {}
  let withdrawn = try book.undoItem(accepted.id)
  try expect(try book.balance(subject: "fittings")["quantity"].text == "20")
  try expect(try book.reviewQueue(limit: 100).items.count == 24)
  let revised = try book.movement(
    subject: "fittings", quantity: "-3", occurrence: "sale-1",
    effective: "2026-01-02", input: source.id, supersedes: withdrawn.id)
  expected.insert(revised.id)
  try expect(Set(book.reviewQueue(limit: 100).items.map(\.id)) == expected)
  try expect(try encoded(book.item(source.id)) == before)
  try expect(try book.item(move.id).status == "draft")
  try expect(try Workbook(book.url).reviewQueue(limit: 100).items.count == 25)
  let token = Cancellation()
  token.cancel()
  for invalid in [true, false] {
    do {
      _ = try book.reviewQueue(
        cancellation: invalid ? token : .init(), deadlineSeconds: invalid ? 3 : 0)
      throw SevraError("test", "Cancelled/expired draft query ran")
    } catch let error as SevraError where ["cancelled", "deadline"].contains(error.code) {}
  }
  let other = try Workbook.create(at: root.appendingPathComponent("Other.sevra"), title: "Other")
  do {
    _ = try other.reviewQueue(cursor: book.reviewQueue().nextCursor)
    throw SevraError("test", "Foreign review cursor was accepted")
  } catch let error as SevraError where error.code == "review_cursor" {}
  let session = ReviewQueueSession()
  let read: @Sendable (String?, Cancellation) async throws -> ReviewQueuePage = { cursor, control in
    try await Task.detached { try book.reviewQueue(cursor: cursor, cancellation: control) }.value
  }
  let revision = try book.revision()
  await session.load(scope: "first", revision: revision, read: read)
  try expect(session.items.count == 20 && session.pageNumber == 1)
  await session.load(scope: "first", revision: revision, direction: 1, read: read)
  try expect(session.items.count == 5 && session.pageNumber == 2 && session.hasPrevious)
  await session.load(scope: "first", revision: revision, direction: -1, read: read)
  try expect(session.items.count == 20 && session.pageNumber == 1)
  await session.load(scope: "second", revision: 0) { _, _ in try other.reviewQueue() }
  try expect(session.items.isEmpty && !session.hasPrevious)
  let tableProposal = try WorkbookTools(book).execute(
    "propose_table",
    .object([
      "title": .string("Proposed orders"), "meaning": .string("plan"),
      "inputs": .array([.string(source.id)]),
      "columns": .array([
        .object([
          "id": .string("quantity"), "title": .string("Quantity"), "type": .string("decimal"),
        ])
      ]),
      "rows": .array([.object(["quantity": .string("2")])]),
    ]))
  let declinedTable = try book.withdrawDraft(tableProposal["id"].text)
  try expect(try book.datasets().isEmpty)
  let restoredTable = try book.undoItem(declinedTable.id)
  try expect(restoredTable.status == "draft" && book.datasets().isEmpty)
  _ = try book.withdrawDraft(restoredTable.id)
  let gate = ReviewReadGate()
  let late = Task {
    await session.load(scope: "old", revision: revision) { _, _ in await gate.read() }
  }
  while !(await gate.ready) { await Task.yield() }
  await session.load(scope: "new", revision: 0) { _, _ in try other.reviewQueue() }
  await gate.finish(first)
  await late.value
  try expect(session.items.isEmpty && !session.loading)
  await session.load(scope: "retry", revision: revision) { _, _ in
    throw SevraError("fixture", "Read failed")
  }
  try expect(session.failure != nil)
  await session.load(scope: "retry", revision: revision, force: true, read: read)
  try expect(session.failure == nil && session.items.count == 20)
  try expect(try book.verify()["ok"] == .bool(true))
  print(
    "PASS current draft queue beyond recent items, bounded paging, scope/stale refusal, acceptance/withdrawal/revision, preserved history and reopen"
  )
}
