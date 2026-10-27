import Foundation
import SevraCore
import SevraPreviewUI

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  if !condition() { throw SevraError("preview_check", message) }
}

private actor ReadGate {
  var token: Cancellation?
  private var callback: (@Sendable (Int64, Int64) -> Void)?
  private var result: CheckedContinuation<URL, Error>?
  private var waiting: [CheckedContinuation<Void, Never>] = []
  func read(_ token: Cancellation, _ progress: @escaping @Sendable (Int64, Int64) -> Void)
    async throws -> URL
  {
    self.token = token
    callback = progress
    return try await withCheckedThrowingContinuation {
      result = $0
      for continuation in waiting { continuation.resume() }
      waiting = []
    }
  }
  func wait() async {
    if result != nil { return }
    await withCheckedContinuation { waiting.append($0) }
  }
  func progress(_ bytes: Int64) { callback?(bytes, 4096) }
  func finish(_ url: URL) {
    result?.resume(returning: url)
    result = nil
  }
  func fail() {
    result?.resume(throwing: SevraError("missing_asset", "File moved"))
    result = nil
  }
  func cancelled() -> Bool { token?.isCancelled == true }
}

@main private struct Checks {
  @MainActor static func main() async {
    do {
      if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--large-asset" {
        try await checkLargePreview(at: URL(fileURLWithPath: CommandLine.arguments[2]))
        return
      }
      try require(
        CommandLine.arguments.count == 1, "arguments",
        "Use --large-asset NEW_DIRECTORY or no arguments.")
      try await run()
      try await checkWorkspaceOperations()
      print(
        "PASS preview ownership, stale success/error/progress, stop/retry, and task cancellation")
    } catch {
      fputs("\(error)\n", stderr)
      exit(1)
    }
  }
  @MainActor static func run() async throws {
    let first = URL(fileURLWithPath: "/synthetic/first.pdf")
    let second = URL(fileURLWithPath: "/synthetic/second.pdf")
    let session = AssetPreviewSession()
    let old = ReadGate()
    let pending = Task { await session.load { try await old.read($0, $1) } }
    await old.wait()
    try expect(session.loading && session.file == nil, "Pending verification looked complete")
    await old.progress(1024)
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    while session.checkedBytes == 0 && ProcessInfo.processInfo.systemUptime < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    try expect(
      session.checkedBytes == 1024 && session.totalBytes == 4096,
      "Active verification did not publish progress")
    await session.load { _, _ in second }
    let oldCancelled = await old.cancelled()
    try expect(oldCancelled, "New preview did not cancel previous file verification")
    await old.progress(2048)
    await old.finish(first)
    await pending.value
    await Task.yield()
    try expect(
      session.file == second && session.failure == nil && session.checkedBytes == 0,
      "An old result or progress replaced the new preview")

    // This old request has not reported any progress yet, so its first late
    // callback cannot be hidden by the producer's update throttle.
    let lateProgress = ReadGate()
    let late = Task { await session.load { try await lateProgress.read($0, $1) } }
    await lateProgress.wait()
    await session.load { _, _ in second }
    await lateProgress.progress(3072)
    await lateProgress.finish(first)
    await late.value
    await Task.yield()
    try expect(
      session.checkedBytes == 0 && session.file == second,
      "Late progress from a replaced preview changed the new view")

    let error = ReadGate()
    let failed = Task { await session.load { try await error.read($0, $1) } }
    await error.wait()
    await session.load { _, _ in second }
    await error.fail()
    await failed.value
    try expect(
      session.file == second && session.failure == nil && !session.loading,
      "An old error hid the current preview")

    let stopped = ReadGate()
    let stopping = Task { await session.load { try await stopped.read($0, $1) } }
    await stopped.wait()
    session.stop()
    let stoppedToken = await stopped.cancelled()
    try expect(
      stoppedToken && !session.loading && session.file == nil && session.failure != nil,
      "Stop did not cancel work and show a retryable state")
    await stopped.progress(3072)
    await stopped.finish(first)
    await stopping.value
    await Task.yield()
    try expect(
      session.checkedBytes == 0 && session.file == nil && session.failure != nil,
      "Late progress or success replaced the stopped state")
    await session.load { _, _ in first }
    try expect(session.file == first && session.failure == nil, "Retry retained stopped state")

    let taskGate = ReadGate()
    let task = Task { await session.load { try await taskGate.read($0, $1) } }
    await taskGate.wait()
    task.cancel()
    let taskCancelled = await taskGate.cancelled()
    try expect(taskCancelled, "Task cancellation did not reach the file reader")
    await taskGate.finish(second)
    await task.value
    try expect(
      session.file == nil && session.failure == nil && !session.loading,
      "Cancelled task published a success or error")

    await session.load { _, _ in first }
    let beforeEntry = Task { await session.load { _, _ in second } }
    beforeEntry.cancel()
    await beforeEntry.value
    try expect(session.file == first, "A task cancelled before entry cleared the current file")

    let leaving = ReadGate()
    let leaveTask = Task { await session.load { try await leaving.read($0, $1) } }
    await leaving.wait()
    session.cancel()
    await leaving.fail()
    await leaveTask.value
    try expect(
      session.file == nil && session.failure == nil && !session.loading,
      "A closed preview received a late failure")

    await session.load { _, _ in throw SevraError("changed_asset", "Original changed") }
    try expect(
      session.file == nil && session.failure?.contains("Original changed") == true,
      "A changed original was presented as readable")
    await session.load { _, _ in second }
    try expect(
      session.file == second && session.failure == nil, "Failure prevented a successful retry")

    let reload = ReadGate()
    let reloading = Task { await session.load { try await reload.read($0, $1) } }
    await reload.wait()
    let originalID = session.reloadID
    session.retry()
    let cancelledByRetry = await reload.cancelled()
    try expect(
      cancelledByRetry && session.reloadID != originalID && !session.loading,
      "Retry waited for SwiftUI to cancel the obsolete file read")
    await reload.finish(first)
    await reloading.value
    try expect(session.file == nil, "The obsolete read published before the retry started")
    let previousID = session.reloadID
    session.reconnect(to: second)
    session.didResolve(previousID)
    try expect(
      session.originalURL == second && session.reloadID != previousID,
      "An old completion discarded a newly chosen original")
    session.didResolve(session.reloadID)
    try expect(session.originalURL == nil, "Successful reconnection kept a stale candidate")

    for input in ["Stop.", "cancel", "stop preview", "retry preview", "find the original file"] {
      try expect(
        WorkspaceControlCommand.allowsSubmission(input, busy: true),
        "An explicit shell control was blocked behind inference")
    }
    for input in [
      "", "  ", "don't stop", "stop buying bolts", "cancel invoice 27", "retry the payment",
    ] {
      try expect(
        !WorkspaceControlCommand.allowsSubmission(input, busy: true),
        "An unrelated or negated request bypassed the busy boundary")
    }
    try expect(
      WorkspaceControlCommand.allowsSubmission("Compare the suppliers", busy: false),
      "Ordinary model requests were disabled while idle")
  }
}
