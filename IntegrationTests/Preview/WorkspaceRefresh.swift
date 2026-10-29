import Foundation
import SevraCore
import SevraPreviewUI

private func requireRefresh(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
  try require(try condition(), "workspace_refresh_check", message)
}

/// Deliberately ignores cancellation until released, like a stalled external read.
/// The UI actor must remain usable and must not start an unbounded queue of readers.
private final class BlockedWorkspaceRead: @unchecked Sendable {
  private let lock = NSLock()
  private let gate = DispatchSemaphore(value: 0)
  private var entered = false
  private var onMain = false
  private var token: Cancellation?
  var started: Bool {
    lock.lock()
    defer { lock.unlock() }
    return entered
  }
  var usedMainThread: Bool {
    lock.lock()
    defer { lock.unlock() }
    return onMain
  }
  var cancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return token?.isCancelled == true
  }
  func read(_ cancellation: Cancellation, snapshot: WorkspaceSnapshot?, fail: Bool = false) throws
    -> WorkspaceSnapshot?
  {
    lock.lock()
    entered = true
    onMain = Thread.isMainThread
    token = cancellation
    lock.unlock()
    guard gate.wait(timeout: .now() + 5) == .success else {
      throw SevraError("test_timeout", "The background read was never released.")
    }
    if fail { throw SevraError("stale", "Old workbook failed") }
    return snapshot
  }
  func release() { gate.signal() }
}

@MainActor private func eventually(_ condition: () -> Bool) async throws {
  let end = ProcessInfo.processInfo.systemUptime + 3
  while !condition(), ProcessInfo.processInfo.systemUptime < end {
    try await Task.sleep(nanoseconds: 1_000_000)
  }
  try requireRefresh(condition(), "Refresh did not reach its expected state")
}

@MainActor func checkWorkspaceRefresh() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-refresh-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let book = try Workbook.create(at: root.appendingPathComponent("First.sevra"), title: "First")
  let message = try book.addMessage("Original message", role: "user")
  let branch = try book.tangent(title: "Branch", parentMessage: message)
  _ = try book.addMessage("Branch message", role: "user", conversation: branch)
  _ = try book.addItem(category: "source", kind: "note", title: "Evidence", text: "Original")
  try book.chapter(title: "Check", message: message)
  try book.chapter(title: "Saved", message: message, bookmark: true)
  let original = try book.workspaceSnapshot(conversation: "main")!
  try requireRefresh(original.revision == (try book.revision()), "Projection revision differs")
  try requireRefresh(
    original.chapters.count == 1 && original.bookmarks.count == 1,
    "Conversation navigation was not included in the snapshot")
  try requireRefresh(original.messages.map(\.id) == [message], "Wrong conversation messages")
  try requireRefresh(
    original.items.count == 1 && original.spaces.first?.id == "home", "Incomplete catalog")
  try requireRefresh(
    try book.workspaceSnapshot(conversation: "main", ifChangedFrom: original.revision) == nil,
    "Unchanged polling rebuilt the full projection")
  _ = try book.addMessage("New message", role: "user")
  let changed = try book.workspaceSnapshot(conversation: "main", ifChangedFrom: original.revision)!
  try requireRefresh(
    changed.messages.count == 2 && changed.revision > original.revision, "Polling lost a change")
  do {
    _ = try book.workspaceSnapshot(conversation: branch, messageAnchor: message)
    throw SevraError("workspace_refresh_check", "Foreign anchor was accepted")
  } catch let error as SevraError where error.code == "history_scope" {}
  let cancelled = Cancellation()
  cancelled.cancel()
  for (token, seconds, code) in [(cancelled, 3.0, "cancelled"), (Cancellation(), 0.0, "deadline")] {
    do {
      _ = try book.workspaceSnapshot(
        conversation: "main", cancellation: token, deadlineSeconds: seconds)
      throw SevraError("workspace_refresh_check", "Cancelled/expired read was accepted")
    } catch let error as SevraError where error.code == code {}
  }
  try requireRefresh(
    try book.workspaceSnapshot(conversation: "main")?.revision == changed.revision,
    "Cancelled read damaged the next snapshot")

  let window = UUID()
  let first = WorkspaceReadIdentity(
    workbook: book, window: window, conversation: "main", messageAnchor: nil)
  let other = WorkspaceReadIdentity(
    workbook: book, window: window, conversation: branch, messageAnchor: nil)
  let session = WorkspaceRefreshSession()
  let blocked = BlockedWorkspaceRead()
  var applied: [String] = []
  session.request(identity: first) {
    try blocked.read($0, snapshot: original)
  } complete: { _ in
    applied.append("obsolete")
  }
  try await eventually { blocked.started }
  try requireRefresh(!blocked.usedMainThread, "The database reader ran on the UI thread")
  // These would run after release if ticks were queued behind the active read.
  for _ in 0..<100 {
    session.request(identity: first, onlyWhenIdle: true) { _ in
      throw SevraError("unexpected", "Timer queued another read")
    } complete: { _ in
      applied.append("timer")
    }
  }
  for index in 0..<3 {
    session.request(identity: other) { control in
      try book.workspaceSnapshot(conversation: branch, cancellation: control)
    } complete: { result in
      if case .success(let snapshot) = result, snapshot?.messages.first?.body == "Branch message" {
        applied.append("branch-\(index)")
      } else {
        applied.append("bad-branch")
      }
    }
  }
  try requireRefresh(
    blocked.cancelled && applied.isEmpty, "Switch did not invalidate the pending read")
  blocked.release()
  try await eventually { !session.isRefreshing }
  try requireRefresh(
    applied == ["branch-2"], "Coalescing published stale results or queued multiple reads")

  // Reopening even the same package is a new owner. Close clears the pending
  // request and rejects an old error, while the new read remains eligible.
  let reopened = try Workbook(book.url)
  let replacement = WorkspaceReadIdentity(
    workbook: reopened, window: UUID(), conversation: "main", messageAnchor: nil)
  try requireRefresh(replacement != first, "Reopen reused the prior window/read identity")
  let failure = BlockedWorkspaceRead()
  session.request(identity: first) {
    try failure.read($0, snapshot: original, fail: true)
  } complete: { _ in
    applied.append("stale-error")
  }
  try await eventually { failure.started }
  session.request(identity: other) { _ in
    original
  } complete: { _ in
    applied.append("closed-pending")
  }
  session.reset()
  session.request(identity: replacement) { control in
    try reopened.workspaceSnapshot(conversation: "main", cancellation: control)
  } complete: { result in
    if case .success(let snapshot) = result, snapshot?.messages.count == 2 {
      applied.append("reopened")
    }
  }
  failure.release()
  try await eventually { !session.isRefreshing }
  try requireRefresh(
    applied == ["branch-2", "reopened"], "Closed window or old error altered the new view")
  try requireRefresh(try book.verify()["ok"] == .bool(true), "Refresh changed workbook integrity")
  print(
    "PASS background workspace snapshot, revision polling, scope, cancellation, coalescing and stale-window refusal"
  )
}
