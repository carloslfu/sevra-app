import Darwin
import Foundation
import SevraCore

func checkConversationNavigation(at root: URL) {
  check("A thread branches from a reply waiting on review, and only a complete one is shared") {
    let b = try Workbook.create(
      at: root.appendingPathComponent("Review reply.sevra"), title: "Review reply")
    _ = try b.addMessage("Propose a plan.", role: "user")
    let reply = try b.addMessage("Ready to review.", role: "assistant", state: "needs_review")
    let request = try b.startAgentRequest("Branch here", conversation: "main", model: "fixture")
    func action(_ fields: [String: Value], conversation: String = "main", requestID: String)
      throws -> ConversationActionResult
    {
      try b.conversationAction(
        .object(fields), conversation: conversation, requestMessage: requestID,
        expectedTitle: "Main", token: identifier())
    }
    let branched = try action(
      ["action": .string("start_thread")], requestID: request.messageID)
    try expect(branched.message == reply)
    try expect(
      try action(
        ["action": .string("start_thread"), "message": .string(reply)],
        requestID: request.messageID
      ).message == reply)
    let asked = try b.addMessage("Share it.", role: "user", conversation: branched.conversation)
    try refuses("history_scope") {
      _ = try action(
        ["action": .string("review_summary"), "message": .string(asked)],
        conversation: branched.conversation, requestID: asked)
    }
  }
  check("Immediate threads keep exact parent context, retry identity and editable titles") {
    let b = try Workbook.create(
      at: root.appendingPathComponent("Thread navigation.sevra"), title: "Threads")
    let original = try b.addMessage(
      "Compare **supplier quotes**\nfor delivery next week.", role: "user")
    let first = try b.startThread(parentMessage: original, token: "thread-once")
    try expect(try b.startThread(parentMessage: original, token: "thread-once") == first)
    let second = try b.startThread(parentMessage: original)
    var chats = try b.conversations()
    let firstTitle = chats.first { $0["id"].text == first }!["title"].text
    try expect(firstTitle == "Compare supplier quotes for delivery next week.")
    try expect(chats.first { $0["id"].text == second }?["title"].text == firstTitle + " (2)")
    try expect(try b.parentContext(conversation: first).map(\.id) == [original])
    try expect(try b.messages(conversation: first).isEmpty)
    try b.renameThread(
      first, title: "Supplier scenario", expectedTitle: firstTitle, token: "rename-once")
    try b.renameThread(
      first, title: "Supplier scenario", expectedTitle: firstTitle, token: "rename-once")
    try refuses("thread_changed") {
      try b.renameThread(first, title: "Overwrite", expectedTitle: firstTitle)
    }
    try refuses("conversation") { try b.renameThread("main", title: "Other") }
    try refuses("thread_title") { try b.renameThread(first, title: "Two\nlines") }
    try refuses("thread_title") { _ = try b.startThread(parentMessage: original, title: " ") }
    try refuses("thread_title") { try b.renameThread(first, title: "Two\u{2028}lines") }
    try refuses("thread_title") { try b.renameThread(first, title: "Bell\u{7}") }
    // Joiners spell these words and emoji, so neither path may refuse or strip them.
    let joined = "می\u{200C}خواهم 👨\u{200D}👩\u{200D}👧"
    try expect(Workbook.threadTitle(from: joined) == joined)
    let spelled = try b.startThread(parentMessage: original, title: joined)
    try expect(try b.conversationIdentity(spelled)["title"].text == joined)
    chats = try Workbook(b.url).conversations()
    try expect(chats.first { $0["id"].text == first }?["title"].text == "Supplier scenario")
    try expect(chats.first { $0["id"].text == first }?["parent_message"].text == original)
    try expect(try b.messages().map(\.id) == [original])
    let fd = Darwin.open(b.url.appendingPathComponent(".write-lock").path, O_RDWR)
    try expect(fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0)
    let started = ProcessInfo.processInfo.systemUptime
    try refuses("deadline") { _ = try b.startThread(parentMessage: original) }
    try expect(ProcessInfo.processInfo.systemUptime - started < 4.5)
    flock(fd, LOCK_UN)
    Darwin.close(fd)
    try expect(try b.conversations().count == 4)
    _ = try b.startThread(parentMessage: original, title: "After lock release")
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses("cancelled") {
      try b.renameThread(first, title: "Must not rename", cancellation: cancelled)
    }
    try expect(try b.conversationIdentity(first)["title"].text == "Supplier scenario")
  }
  check("History windows use scoped keysets with interleaved threads, bounded bodies and no gaps") {
    let b = try Workbook.create(
      at: root.appendingPathComponent("History windows.sevra"), title: "History")
    let parent = try b.addMessage("Anchor", role: "user")
    let thread = try b.startThread(parentMessage: parent)
    var ids = [parent]
    for n in 1..<240 {
      ids.append(try b.addMessage("Window needle \(n)", role: n % 2 == 0 ? "user" : "assistant"))
      _ = try b.addMessage("Window needle sibling \(n)", role: "user", conversation: thread)
      _ = try b.addMessage("Window needle receipt \(n)", role: "tool")
    }
    let latest = try b.conversationWindow(conversation: "main")
    try expect(
      latest.messages.map(\.id) == Array(ids.suffix(100)) && latest.hasEarlier && !latest.hasLater)
    let center = try b.conversationWindow(conversation: "main", around: ids[120])
    try expect(
      center.messages.map(\.id) == Array(ids[70..<170]) && center.hasEarlier && center.hasLater)
    var page = latest
    var visited = Set(page.messages.map(\.id))
    for _ in 0..<8 where page.hasEarlier {
      page = try b.conversationWindow(conversation: "main", around: page.messages.first!.id)
      visited.formUnion(page.messages.map(\.id))
    }
    try expect(!page.hasEarlier && visited == Set(ids), "Earlier windows skipped messages")
    for _ in 0..<8 where page.hasLater {
      page = try b.conversationWindow(conversation: "main", around: page.messages.last!.id)
    }
    try expect(!page.hasLater && page.messages.last?.id == ids.last)
    try refuses("history_scope") {
      _ = try b.conversationWindow(conversation: thread, around: ids[120])
    }
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses("cancelled") {
      _ = try b.conversationWindow(conversation: "main", cancellation: cancelled)
    }
    let search = try b.searchHistory("needle", limit: 20, visibleOnly: true)
    try expect(
      search["hits"].array.count == 20
        && search["hits"].array.allSatisfy { $0["role"].text != "tool" })
    let cursor = search["nextCursor"].text
    try refuses("stale_cursor") { _ = try b.searchHistory("needle", cursor: cursor) }
    try refuses("stale_cursor") {
      _ = try b.searchHistory("needle", conversation: thread, cursor: cursor, visibleOnly: true)
    }
    let next = try b.searchHistory("needle", cursor: cursor, limit: 20, visibleOnly: true)
    try expect(
      Set(search["hits"].array.map { $0["id"].text }).isDisjoint(
        with: next["hits"].array.map { $0["id"].text }))
    let longThread = try b.startThread(parentMessage: parent, title: "Large messages")
    var large: [String] = []
    for _ in 0..<40 {
      large.append(
        try b.addMessage(
          String(repeating: "x", count: 120_000), role: "user", conversation: longThread))
    }
    let bounded = try b.conversationWindow(conversation: longThread, around: large[20])
    try expect(bounded.messages.contains { $0.id == large[20] })
    try expect(bounded.messages.reduce(0) { $0 + $1.body.utf8.count } <= 2 * 1024 * 1024)
    let indexes = bounded.messages.map { large.firstIndex(of: $0.id)! }
    try expect(indexes == Array(indexes.first!...indexes.last!), "Byte bound left hidden gaps")
    try expect(bounded.hasEarlier && bounded.hasLater && (try b.verify()["ok"] == .bool(true)))
  }
}
