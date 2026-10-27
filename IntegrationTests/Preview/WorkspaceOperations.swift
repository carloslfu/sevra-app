import Foundation
import SevraCore
import SevraPreviewUI

private actor CompletionGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var listeners: [CheckedContinuation<Void, Never>] = []
  func wait() async {
    await withCheckedContinuation {
      continuation = $0
      for listener in listeners { listener.resume() }
      listeners = []
    }
  }
  func started() async {
    if continuation != nil { return }
    await withCheckedContinuation { listeners.append($0) }
  }
  func release() {
    continuation?.resume()
    continuation = nil
  }
}

@MainActor func checkWorkspaceOperations() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "workspace-owner-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let oldBook = try Workbook.create(at: root.appendingPathComponent("Old.sevra"), title: "Old")
  let newBook = try Workbook.create(at: root.appendingPathComponent("New.sevra"), title: "New")
  let scope = WorkspaceOperationScope()
  let first = scope.begin()!
  try require(scope.begin() == nil, "scope_check", "Overlapping work acquired the same window")
  let gate = CompletionGate()
  var route = "old"
  var progress = "old work"
  let pending = Task { @MainActor in
    // A successful mutation remains durable even if its UI callback arrives
    // after the workbook closes. It must never be moved or replayed in the new one.
    _ = try oldBook.addItem(category: "source", kind: "note", title: "Saved before close")
    await gate.wait()
    if scope.acceptsProgress(first) { progress = "late progress" }
    if scope.owns(first) { route = "old result" }
    return scope.finish(first)
  }
  await gate.started()
  scope.invalidate()
  let second = scope.begin()!
  route = "new"
  progress = "new work"
  await gate.release()
  let lateFinished = try await pending.value
  try require(
    first.cancellation.isCancelled && !lateFinished && scope.owns(second),
    "scope_check", "Closing work did not cancel or its late completion cleared the new owner")
  try require(
    route == "new" && progress == "new work", "scope_check", "Stale callbacks changed the window")
  try require(
    try oldBook.items().count == 1 && newBook.items().isEmpty,
    "scope_check", "Completed changes were lost or appeared in another workbook")

  scope.cancel()
  try require(
    second.cancellation.isCancelled && !scope.acceptsProgress(second) && scope.owns(second)
      && scope.begin() == nil, "scope_check",
    "Stop admitted overlapping work before cancellation completed")
  try require(scope.finish(second) && !scope.finish(second), "scope_check", "Completion ran twice")

  let permission = scope.begin()!
  scope.cancel()
  try require(
    scope.finish(permission), "scope_check", "Cancelled permission wait did not release its owner")
  let current = scope.begin()!
  var captureStarted = false
  // Simulate an OS permission response after Stop and a new operation.
  if scope.acceptsProgress(permission) { captureStarted = true }
  try require(
    !captureStarted && !scope.finish(permission) && scope.owns(current),
    "scope_check", "Late permission response captured or stopped newer work")
  scope.invalidate()
  try require(
    current.cancellation.isCancelled && !scope.owns(current),
    "scope_check", "Window close retained its active operation")
  try require(
    try oldBook.verify()["ok"] == .bool(true) && newBook.verify()["ok"] == .bool(true),
    "scope_check", "Workspace ownership damaged durable state")
  print(
    "PASS workspace close/reopen, late completion/progress, stop ownership and delayed permission")
}
