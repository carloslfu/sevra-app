import Foundation
import SevraCore
import SevraPreviewUI

func checkRequestActivity() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "activity-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(
    at: root.appendingPathComponent("Activity.sevra"), title: "Activity")
  let request = try book.startAgentRequest(
    "Find supplier evidence", conversation: book.startChat, model: "Synthetic model")
  let call = try book.prepareToolCall(
    runID: request.runID, callID: "search", tool: "search",
    arguments: .object(["query": .string("Brio")]))
  var activity = try book.requestActivities(messageIDs: [request.messageID], conversation: book.startChat)
  try require(
    activity.count == 1 && activity[0].steps[0].state == "prepared", "activity_check",
    "Prepared work disappeared")
  try require(
    activity[0].steps[0].detail.contains("incomplete"), "activity_check",
    "Unfinished work claimed success")
  _ = try book.completeToolCall(
    call, result: .object(["hits": .array([]), "nextCursor": .string("more")]))
  let failed = try book.prepareToolCall(
    runID: request.runID, callID: "failed", tool: "read",
    arguments: .object(["id": .string("missing")]))
  _ = try book.completeToolCall(
    failed, result: .object(["error": .string("Original unavailable")]), failed: true)
  let large = try book.prepareToolCall(
    runID: request.runID, callID: "large", tool: "read",
    arguments: .object(["id": .string("large")]))
  _ = try book.completeToolCall(
    large, result: .object(["text": .string(String(repeating: "x", count: 30_000))]))
  try book.finishAgentRun(request.runID, status: "cancelled", steps: 3, metrics: .array([]))
  let reopened = try Workbook(book.url)
  activity = try reopened.requestActivities(messageIDs: [request.messageID], conversation: reopened.startChat)
  try require(
    activity[0].state == "cancelled" && activity[0].steps.count == 3, "activity_check",
    "Reopen lost cancellation or saved steps")
  try require(
    activity[0].steps[0].detail.contains("0 document")
      && activity[0].steps[0].detail.contains("more pages"), "activity_check",
    "Empty page lost its scope")
  try require(
    activity[0].steps[1].state == "failed" && activity[0].steps[1].detail == "Original unavailable",
    "activity_check", "Failure looked successful")
  try require(
    activity[0].steps[2].result == nil, "activity_check", "Large result was eagerly loaded")
  let page = try reopened.toolResultPage(large)
  try require(
    page["receiptID"] == .string(large), "activity_check", "Large result is not inspectable")
  let savedPath = page["entries"].array.first?["value"]["path"].array.compactMap(\.string) ?? []
  let nested = try reopened.toolResultPage(large, path: savedPath)
  try require(
    savedPath == ["text"] && !nested["textSegment"].text.isEmpty
      && nested["nextOffset"].int == nested["textSegment"].text.unicodeScalars.count,
    "activity_check",
    "Omitted content could not be explored with its exact saved path")
  var current = nested
  var restored = ""
  while true {
    let segment = current["textSegment"].text
    try require(
      !segment.isEmpty && current["offset"].int == restored.unicodeScalars.count
        && current["total"].int == 30_000 && current.json().utf8.count <= 16_000,
      "activity_check", "Exploration lost its saved offset, length or response bound")
    restored += segment
    guard let next = current["nextOffset"].int else { break }
    try require(
      next == restored.unicodeScalars.count && next < 30_000, "activity_check",
      "Exploration repeated or skipped saved text")
    current = try reopened.toolResultPage(large, path: savedPath, offset: next)
  }
  try require(
    restored == String(repeating: "x", count: 30_000), "activity_check",
    "Exploration did not recover the complete saved result")
  let branch = try book.createChat()
  let foreign = try reopened.requestActivities(
    messageIDs: [request.messageID], conversation: branch)
  try require(foreign.isEmpty, "activity_check", "Activity leaked across chats")
  let snapshot = try reopened.workspaceSnapshot(conversation: reopened.startChat)!
  try require(
    snapshot.requestActivities.first?.id == request.runID, "activity_check",
    "Workspace omitted activity")
  let next = try book.startAgentRequest(
    "Inspect original", conversation: book.startChat, model: "Synthetic model")
  let original = try book.prepareToolCall(
    runID: next.runID, callID: "original", tool: "read",
    arguments: .object(["id": .string("synthetic-original")]))
  _ = try book.completeToolCall(
    original,
    result: .object([
      "item": .object(["id": .string("synthetic-original"), "title": .string("Quote.pdf")]),
      "chunks": .array([.object([:])]), "chunkPage": .object(["hasMore": .bool(true)]),
    ]))
  for index in 1...64 {
    _ = try book.prepareToolCall(
      runID: next.runID, callID: "pending-\(index)", tool: "read",
      arguments: .object(["id": .string("pending")]))
  }
  let bounded = try book.requestActivities(messageIDs: [next.messageID], conversation: book.startChat)[0]
  try require(
    bounded.steps.count == 64 && bounded.hasMoreSteps, "activity_check",
    "Activity did not bound long journals")
  try require(
    bounded.steps[0].originalID == "synthetic-original"
      && bounded.steps[0].title == "Read Quote.pdf"
      && bounded.steps[0].detail.contains("more available"), "activity_check",
    "Partial original inspection lost its identity or coverage")
  try book.finishAgentRun(next.runID, status: "interrupted", steps: 1, metrics: .array([]))
  do {
    _ = try reopened.requestActivities(
      messageIDs: Array(repeating: request.messageID, count: 201), conversation: reopened.startChat)
    throw SevraError("activity_check", "Unbounded activity query accepted")
  } catch let failure as SevraError where failure.code == "activity_limit" {}
  var live = LiveRequestActivity(conversation: reopened.startChat)
  live.attach(request, conversation: reopened.startChat)
  live.update("Reasoning · 25 tokens generated")
  try require(
    live.runID == request.runID && live.status.contains("25") && live.title == "Reasoning",
    "activity_check",
    "Live progress was not attached to its request")
  live.preview("An unfinished answer", sequence: 1)
  live.preview(nil, sequence: 3)
  live.preview("A delayed old answer", sequence: 2)
  try require(live.answerPreview == nil, "activity_check", "A retry clear was undone by late text")
  live.preview("New answer", sequence: 4)
  live.stop()
  live.update("Old generation callback")
  live.preview("Late answer", sequence: 5)
  try require(live.answerPreview == nil, "activity_check", "Late answer undid Stop")
  try require(
    live.stopping && live.status == "Stopping…", "activity_check", "Late progress undid Stop")
  // Thoughts arrive with every update: an older one never replaces newer thoughts, and Stop
  // ends the current reasoning but keeps what the model already thought.
  var thinking = LiveRequestActivity(conversation: book.startChat)
  let thought = ActivityThought(step: 1, callID: "a", tool: "search", text: "Search first.")
  thinking.show(nil, reasoning: "Now reading", thoughts: [thought], sequence: 2)
  thinking.show(nil, reasoning: "An older partial", thoughts: [], sequence: 1)
  try require(
    thinking.reasoning == "Now reading" && thinking.thoughts == [thought], "activity_check",
    "A late update replaced newer thoughts")
  thinking.preview("An answer", sequence: 3)
  try require(
    thinking.thoughts == [thought] && thinking.answerPreview == "An answer", "activity_check",
    "An answer update dropped the thoughts")
  thinking.stop()
  try require(
    thinking.reasoning == nil && thinking.thoughts == [thought], "activity_check",
    "Stop hid what the model already thought")
  var continuation = LiveRequestActivity(conversation: book.startChat)
  continuation.attach(next, conversation: branch)
  try require(
    continuation.conversation == branch && continuation.runID == next.runID, "activity_check",
    "Thread continuation kept the wrong progress owner")
  print(
    "PASS request activity: receipts, scopes, failures, cancellation, reopen, bounded results and late progress"
  )
}
