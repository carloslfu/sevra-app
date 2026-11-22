import Darwin
import Foundation
import SevraCore
import SevraPreviewUI

private func draftCheck(_ value: Bool, _ code: String, _ message: String) throws {
  try require(value, code, message)
}

@MainActor func checkConversationState() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-conversation-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root.appendingPathComponent("Drafts.sevra"), title: "Drafts")
  let first = try book.addMessage("Original question", role: "user")
  let thread = try book.createChat()
  let other = try book.addMessage("Scenario answer", role: "assistant", conversation: thread)
  let counts = try book.counts()
  let stale = ConversationSession()
  try draftCheck(
    await stale.open(book, conversation: "gone") && stale.conversation == thread
      && stale.failure == nil, "draft_check",
    "A missing remembered chat did not open the most recent one")
  try ComposerInput.admit(String(repeating: "é", count: 8_000))
  do {
    try ComposerInput.admit(String(repeating: "é", count: 8_000) + "x")
    throw SevraError("draft_check", "An over-limit message was admitted")
  } catch let error as SevraError {
    try draftCheck(error.code == "prompt_limit", "draft_check", "Wrong refusal: " + error.code)
  }
  try draftCheck(
    ComposerInput.restored("Sent", over: "") == "Sent"
      && ComposerInput.restored("Sent", over: "Typed after") == "Sent\n\nTyped after",
    "draft_check", "A returned message replaced what was typed after it")
  try ComposerInput.keep("Unsent in a closed window", conversation: thread, in: book)
  try ComposerInput.keep("Second unsent", conversation: thread, in: book)
  try draftCheck(
    try book.conversationViewState(thread).draft
      == "Second unsent\n\nUnsent in a closed window",
    "draft_check", "A message for a closed composer was not kept")
  _ = try book.saveConversationViewState(
    thread, draft: "", reading: .init(), expectedDraft: book.conversationViewState(thread).draft)
  let session = ConversationSession()
  try draftCheck(await session.open(book, conversation: book.startChat), "draft_check", "Could not open draft session")
  session.updateDraft("Unsent main draft 🐈 café")
  session.updateReading(.init(message: first, fraction: 0.37))
  try draftCheck(await session.select(thread), "draft_check", "Switch failed")
  try draftCheck(
    session.state.draft.isEmpty && session.state.reading.message == nil,
    "draft_check", "A draft moved into another chat")
  session.updateDraft("Unsent scenario")
  session.updateReading(.init(message: other, fraction: 0.63))
  try draftCheck(await session.select(book.startChat), "draft_check", "Return failed")
  try draftCheck(
    session.state.draft == "Unsent main draft 🐈 café" && session.state.reading.fraction == 0.37,
    "draft_check", "Return lost the exact draft or reading position")
  session.updateDraft("First edit")
  let flush = Task { await session.flush() }
  await Task.yield()
  session.updateDraft("Final edit with 日本語")
  let saved = await session.flush()
  try draftCheck(await flush.value && saved, "draft_check", "Concurrent flush failed")
  try draftCheck(
    try book.conversationViewState(book.startChat).draft == "Final edit with 日本語",
    "draft_check", "An in-flight save lost a later keystroke")
  let reopened = try Workbook(book.url)
  let window = ConversationSession()
  try draftCheck(await window.open(reopened, conversation: thread), "draft_check", "Reopen failed")
  try draftCheck(
    window.state.draft == "Unsent scenario" && window.state.reading.message == other,
    "draft_check", "Reopen lost the other chat's state")
  try draftCheck(
    try book.counts() == counts, "draft_check", "Presentation writes changed business state/history"
  )
  try draftCheck(
    try book.messages().count == 1 && book.messages(conversation: thread).count == 1,
    "draft_check", "An unsent draft was submitted as a message")
  try draftCheck(await window.select(book.startChat), "draft_check", "Second window switch failed")
  session.updateDraft("Window one")
  try draftCheck(await session.flush(), "draft_check", "First writer failed")
  window.updateDraft("Window two")
  try draftCheck(
    !(await window.flush()) && window.conflict && window.state.draft == "Window two",
    "draft_check", "Competing draft was silently overwritten")
  try draftCheck(
    !(await window.select(thread)) && window.conversation == book.startChat,
    "draft_check", "Unsaved conflict allowed navigation")
  try draftCheck(await window.keepBoth(), "draft_check", "Keep both failed")
  let preserved = try reopened.conversationViewState(reopened.startChat)
  try draftCheck(
    preserved.draft == "Window two" && preserved.savedDrafts.map(\.text) == ["Window one"],
    "draft_check", "Keep both did not preserve both exact texts")
  try draftCheck(
    await window.restoreSaved(preserved.savedDrafts[0].id), "draft_check", "Restore failed")
  try draftCheck(
    window.state.draft == "Window one" && window.state.savedDrafts.map(\.text) == ["Window two"],
    "draft_check", "Restoring another draft lost the current one")
  try draftCheck(
    await window.discardSaved(window.state.savedDrafts[0].id), "draft_check", "Remove failed")
  try draftCheck(window.state.savedDrafts.isEmpty, "draft_check", "Removal was not durable")
  // Scrolling an unchanged composer must not overwrite a newer external draft
  // or ask for a conflict decision when the user has made no competing edit.
  let reader = ConversationSession()
  try draftCheck(await reader.open(book, conversation: book.startChat), "draft_check", "Reader open failed")
  window.updateDraft("New text from another window")
  try draftCheck(await window.flush(), "draft_check", "External edit failed")
  var restoredText: String?
  reader.restoredDraft = { restoredText = $0 }
  reader.updateReading(.init(message: first, fraction: 0.8))
  try draftCheck(await reader.flush(), "draft_check", "Reading-only save conflicted")
  try draftCheck(
    reader.state.draft == "New text from another window" && restoredText == reader.state.draft,
    "draft_check", "Reading-only save overwrote or failed to expose newer text")
  let fd = Darwin.open(book.url.appendingPathComponent(".write-lock").path, O_RDWR)
  try draftCheck(fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0, "draft_check", "Fixture lock failed")
  window.updateDraft("Retained while busy")
  let began = ProcessInfo.processInfo.systemUptime
  let blocked = Task { await window.flush() }
  try await Task.sleep(nanoseconds: 50_000_000)
  try draftCheck(window.state.draft == "Retained while busy", "draft_check", "UI actor was blocked")
  let result = await blocked.value
  flock(fd, LOCK_UN)
  Darwin.close(fd)
  try draftCheck(
    !result && ProcessInfo.processInfo.systemUptime - began < 4.5 && window.dirty,
    "draft_check", "Busy save did not stop or retained text was lost")
  try draftCheck(await window.flush(), "draft_check", "Retry after lock release failed")
  for (draft, reading, code) in [
    (String(repeating: "é", count: 64_001), ConversationReadingPosition(), "draft_limit"),
    ("Bad scope", ConversationReadingPosition(message: other), "history_scope"),
    (
      "Bad fraction", ConversationReadingPosition(message: first, fraction: .infinity),
      "reading_position"
    ),
  ] {
    do {
      _ = try book.saveConversationViewState(
        book.startChat, draft: draft, reading: reading, expectedDraft: "Retained while busy")
      throw SevraError("draft_check", "Invalid state accepted")
    } catch let error as SevraError {
      try draftCheck(error.code == code, "draft_check", "Wrong refusal: " + error.code)
    }
    try draftCheck(
      try book.conversationViewState(book.startChat).draft == "Retained while busy",
      "draft_check", "Rejected state changed the saved draft")
  }
  try draftCheck(
    try book.verify()["ok"] == .bool(true), "draft_check", "Draft writes damaged the package")
  try draftCheck(
    try book.search("Retained").hits.isEmpty, "draft_check",
    "An unsent draft entered evidence search")
  let archive = root.appendingPathComponent("Drafts.sevraz")
  try book.export(to: archive)
  let portable = try Workbook.openArchive(
    archive, at: root.appendingPathComponent("Portable.sevra"))
  try draftCheck(
    try portable.conversationViewState(portable.startChat) == book.conversationViewState(book.startChat),
    "draft_check", "A portable workbook lost saved presentation state")
  // Keeping a ninth distinct draft refuses without losing either text. Removing
  // an explicitly selected old alternative makes room for the pending save.
  let full = ConversationSession()
  try draftCheck(await full.open(book, conversation: book.startChat), "draft_check", "Full-draft session failed")
  for n in 0..<8 {
    full.updateDraft("Alternative \(n)")
    try draftCheck(await full.keepBoth(), "draft_check", "Could not retain an alternative")
  }
  full.updateDraft("Ninth alternative")
  try draftCheck(
    !(await full.keepBoth()) && full.state.savedDrafts.count == 8 && full.dirty,
    "draft_check", "Alternative limit discarded text")
  try draftCheck(
    await full.discardSaved(full.state.savedDrafts[0].id), "draft_check",
    "Full draft list could not recover")
  try draftCheck(
    full.state.draft == "Ninth alternative" && full.state.savedDrafts.count == 8 && !full.dirty,
    "draft_check", "Limit recovery lost the pending draft or another alternative")
  print(
    "PASS scoped drafts, fractional reading state, concurrent flush, reopen, conflict/keep-both/restore, bounded busy retry and rollback"
  )
}

/// Waiting messages: the ten-message limit, the person's order, pause, put-back, saving with the
/// chat and reopening paused, and chats saved before the queue existed.
@MainActor func checkConversationQueue() async throws {
  var queue = ConversationQueue()
  for n in 1...ConversationQueue.limit {
    try queue.add("Message \(n)", id: "m\(n)", queued: "t")
  }
  do {
    try queue.add("Eleventh", id: "m11", queued: "t")
    throw SevraError("queue_check", "An eleventh message was queued")
  } catch let error as SevraError where error.code == "queue_full" {}
  queue.move("m3", by: -1)
  queue.move("m1", by: -5)
  queue.move("m10", before: "m1")
  queue.move("m2", before: nil)
  try draftCheck(
    queue.messages.map(\.id).prefix(4) == ["m10", "m1", "m3", "m4"]
      && queue.messages.last?.id == "m2",
    "queue_check", "Reordering gave " + queue.messages.map(\.id).joined(separator: ","))
  try queue.edit("m4", text: "  Edited  ")
  queue.remove("m5")
  try draftCheck(
    queue.messages[3].text == "Edited" && queue.messages.count == 9,
    "queue_check", "Edit or remove did not apply")
  do {
    try queue.edit("m4", text: "   ")
    throw SevraError("queue_check", "An empty edit was accepted")
  } catch let error as SevraError where error.code == "queue_empty" {}
  queue.paused = true
  try draftCheck(queue.takeNext() == nil, "queue_check", "A paused queue sent a message")
  queue.paused = false
  let first = queue.takeNext()
  try draftCheck(first?.id == "m10" && queue.messages.count == 8, "queue_check", "Wrong next message")
  try draftCheck(
    queue.putBack(first!) && queue.paused && queue.messages.first?.id == "m10",
    "queue_check", "A refused message did not return to the top, paused")

  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-queue-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root.appendingPathComponent("Queue.sevra"), title: "Queue")
  let chat = book.startChat
  let session = ConversationSession()
  try draftCheck(await session.open(book, conversation: chat), "queue_check", "Could not open chat")
  var saved = ConversationQueue()
  try saved.add("Then chart it", context: "Row 4", id: "a", queued: "t")
  try saved.add("Then summarize", id: "b", queued: "t")
  session.updateDraft("Still typing")
  session.updateQueue(saved)
  try draftCheck(await session.flush(), "queue_check", "Queue did not save")
  let reopened = ConversationSession()
  try draftCheck(await reopened.open(book, conversation: chat), "queue_check", "Reopen failed")
  try draftCheck(
    reopened.state.queue.messages == saved.messages && reopened.state.queue.paused
      && reopened.state.draft == "Still typing",
    "queue_check", "Reopened queue was not the same messages, paused, beside the draft")

  // A chat saved before the queue existed still opens, with an empty queue.
  let other = try book.createChat()
  _ = try book.saveConversationViewState(
    other, draft: "Old draft", reading: .init(), expectedDraft: "")
  let stored = try book.conversationViewState(other)
  let legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(stored)) as! [String: Any]
  let withoutQueue = legacy.filter { $0.key != "queue" }
  let decoded = try JSONDecoder().decode(
    ConversationViewState.self, from: JSONSerialization.data(withJSONObject: withoutQueue))
  try draftCheck(
    decoded.draft == "Old draft" && decoded.queue.isEmpty, "queue_check",
    "A chat without a saved queue did not decode")
  print("PASS waiting messages: limit, order, edit, pause, put-back, save, reopen paused, old chats")
}
