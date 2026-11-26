import Foundation
@testable import SevraCore

func checkChats(at root: URL) {
  check("Sevra names work only while the name is its own, and the file follows on the next open") {
    let folder = root.appendingPathComponent("Titles")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("Untitled.sevra")
    var book: Workbook? = try Workbook.create(at: url, title: "Untitled", automaticTitle: true)
    try expect(book!.titleIsAutomatic)
    try expect(try book!.setAutomaticTitle("Brass bolt quotes") && book!.title == "Brass bolt quotes")
    // The chat: "New chat", then the first message's title, then a better one, are all Sevra's.
    let chat = try book!.chats()[0].id
    try expect(try book!.chatTitleIsAutomatic(chat))
    _ = try book!.addMessage("compare the quotes for brass bolts", role: "user", conversation: chat)
    try expect(try book!.chatTitleIsAutomatic(chat))
    try expect(try book!.setAutomaticChatTitle(chat, title: "Brass bolt comparison"))
    try expect(try book!.chats()[0].title == "Brass bolt comparison")
    try expect(try book!.chatTitleIsAutomatic(chat))
    // A title the person gives ends it.
    try book!.renameChat(chat, title: "Bolts")
    try expect(try !book!.chatTitleIsAutomatic(chat))
    try expect(try !book!.setAutomaticChatTitle(chat, title: "Something else"))
    try expect(try book!.chats()[0].title == "Bolts")
    book = nil
    // Closed and opened again: the file takes the name, and a taken name gets a number.
    _ = try Workbook.create(at: folder.appendingPathComponent("Brass bolt quotes.sevra"), title: "Other")
    let moved = try WorkbookLibrary.fileMatchingAutomaticTitle(url)
    try expect(moved?.lastPathComponent == "Brass bolt quotes 2.sevra")
    try expect(try WorkbookLibrary.fileMatchingAutomaticTitle(moved!) == nil)
    try expect(WorkbookLibrary.displayName(moved!.path) == "Brass bolt quotes")
    // Renaming by the person makes the name theirs.
    let named = try WorkbookLibrary.rename(moved!, to: "Bolts 2026")
    let reopened = try Workbook(named)
    try expect(!reopened.titleIsAutomatic)
    try expect(try !reopened.setAutomaticTitle("Not this") && reopened.title == "Bolts 2026")
    // A workbook made before names were marked counts as Sevra's only while it is untitled.
    try expect(Workbook.automaticTitle(.object(["title": .string("Untitled 3")])))
    try expect(!Workbook.automaticTitle(.object(["title": .string("Quotes")])))
  }
  check("A new workbook gets a name and a place without a save panel, and can be renamed") {
    try expect(WorkbookLibrary.name(fromMessage: "hi") == "Untitled")
    try expect(WorkbookLibrary.name(fromMessage: "thanks a lot") == "Thanks a lot")
    try expect(
      WorkbookLibrary.name(fromMessage: "compare the **Oak** and Cedar quotes.")
        == "Compare the Oak and Cedar quotes")
    let long = WorkbookLibrary.name(fromMessage: String(repeating: "supplier ", count: 30))
    try expect(long.count <= 57 && long.hasSuffix("…"))
    try expect(WorkbookLibrary.name(from: "  a/b:c\n.d  ") == "a b c .d")
    try expect(WorkbookLibrary.name(from: "...") == "Untitled")
    try expect(
      WorkbookLibrary.name(fromFiles: [URL(fileURLWithPath: "/x/Q3 quotes.csv")]) == "Q3 quotes")
    let folder = root.appendingPathComponent("Library")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let first = WorkbookLibrary.available("Quotes", in: folder)
    try expect(first.lastPathComponent == "Quotes.sevra")
    let book: Workbook? = try Workbook.create(at: first, title: "Quotes")
    let second = WorkbookLibrary.available("Quotes", in: folder)
    try expect(second.lastPathComponent == "Quotes 2.sevra")
    _ = try Workbook.create(at: second, title: "Quotes 2")
    // A name in use is refused and nothing moves; a free one moves the file and its title.
    try refuses("exists") { try WorkbookLibrary.rename(first, to: "Quotes 2") }
    try expect(FileManager.default.fileExists(atPath: first.path))
    _ = book
    let renamed = try WorkbookLibrary.rename(first, to: "Oak / Cedar")
    try expect(renamed.lastPathComponent == "Oak Cedar.sevra")
    try expect(!FileManager.default.fileExists(atPath: first.path))
    try expect(try Workbook(renamed).title == "Oak Cedar")
  }
  check("A workbook keeps a plain list of chats: new, titled, renamed and deleted") {
    let b = try Workbook.create(at: root.appendingPathComponent("Chats.sevra"), title: "Chats")
    let first = try b.chats()
    try expect(first.count == 1 && first[0].title == "New chat" && first[0].messageCount == 0)
    try expect(
      try b.scalarForCheck("PRAGMA user_version") == .number(Double(Schema.version))
        && Schema.version == 35)
    let start = first[0].id

    // The first message a person sends names the chat; later ones and replies do not.
    _ = try b.addMessage("Welcome.", role: "assistant", conversation: start)
    _ = try b.addMessage(
      "Compare **Oak** and Cedar\nfor brass bolts", role: "user", conversation: start)
    _ = try b.addMessage("And their delivery dates?", role: "user", conversation: start)
    try expect(try b.chat(start).title == "Compare Oak and Cedar for brass bolts")
    try expect(Workbook.chatTitle(from: "  ") == "New chat")
    try expect(Workbook.chatTitle(from: "Compare the quotes.") == "Compare the quotes")
    try expect(Workbook.chatTitle(from: "Why is stock low?") == "Why is stock low?")
    try expect(Workbook.chatTitle(from: "...") == "New chat")
    // A shortened title fits the limits a rename checks, so it can be saved again unchanged.
    for text in [String(repeating: "word ", count: 80), String(repeating: "x", count: 200)] {
      let long = Workbook.chatTitle(from: text)
      try expect(long.count <= 120 && long.hasSuffix("…"))
      try b.renameChat(start, title: long)
    }
    try expect(Workbook.chatTitle(from: "Pay \u{202E}evil\u{200B} now") == "Pay evil now")
    try refuses("chat_title") { try b.renameChat(start, title: "a\u{202E}b") }
    try b.renameChat(start, title: "👨‍👩‍👧 orders")

    // A new chat starts empty and comes first; each chat holds only its own messages.
    let other = try b.createChat()
    try expect(try b.chats().map(\.id) == [other, start])
    _ = try b.addMessage("Draft a reorder rule", role: "user", conversation: other)
    try expect(try b.messages(conversation: other).map(\.body) == ["Draft a reorder rule"])
    try expect(try b.messages(conversation: start).count == 3)

    // A title the person chose, even before the first message, is kept; bad titles are refused.
    let named = try b.createChat()
    try b.renameChat(named, title: "Delivery dates")
    _ = try b.addMessage("When does Oak deliver?", role: "user", conversation: named)
    try expect(try b.chat(named).title == "Delivery dates")
    _ = try b.deleteChat(named)
    try b.renameChat(other, title: "  Reorder rules  ")
    try expect(try b.chat(other).title == "Reorder rules")
    try refuses("chat_title") { try b.renameChat(other, title: " ") }
    try refuses("chat_title") { try b.renameChat(other, title: "Two\nlines") }
    try refuses("chat_title") {
      try b.renameChat(other, title: String(repeating: "x", count: 121))
    }
    try refuses("chat") { try b.renameChat("missing", title: "Nope") }

    // Deleting a chat removes it from the list and its draft, and nothing writes to it again.
    _ = try b.saveConversationViewState(
      other, draft: "Unsent", reading: .init(), expectedDraft: "")
    let next = try b.deleteChat(other)
    try expect(next == start && (try b.chats().map(\.id)) == [start])
    try expect(
      try b.scalarForCheck(
        "SELECT count(*) FROM meta WHERE key=?", [.string("conversation-view:" + other)])
        == .number(0))
    try refuses("chat_deleted") { _ = try b.addMessage("Late", role: "user", conversation: other) }
    try refuses("chat_deleted") {
      _ = try b.startAgentRequest("Late", conversation: other, model: "fixture")
    }
    try refuses("chat_deleted") { _ = try b.conversationViewState(other) }
    try refuses("chat_deleted") { try b.renameChat(other, title: "Back") }
    try refuses("chat_deleted") { _ = try b.deleteChat(other) }
    try refuses("chat_deleted") { _ = try b.conversationWindow(conversation: other) }
    // The schema refuses a direct write into a deleted chat as well.
    try refuses {
      try b.synchronized {
        _ = try b.db.execute(
          "INSERT INTO messages VALUES(?,?,'user','Late','complete',?)",
          [.string(identifier()), .string(other), .string(timestamp())])
      }
    }

    // A chat with a running answer cannot be deleted until it stops. A window that knows no
    // answer of its own is running there closes a run a crash left behind, then deletes.
    let request = try b.startAgentRequest("Count bolts", conversation: start, model: "fixture")
    try refuses("chat_busy") { _ = try b.deleteChat(start) }

    // Deleting the last chat leaves a new empty one.
    let replacement = try b.deleteChat(start, closingUnfinishedRuns: true)
    try expect(try b.requestRunStatus(request.messageID) == "interrupted")
    let left = try b.chats()
    try expect(left.count == 1 && left[0].id == replacement && left[0].title == "New chat")

    // A rebuilt copy has the same chats, deleted ones included, and still verifies.
    let copy = try b.reconstruct(to: root.appendingPathComponent("Chats copy.sevra"))
    try expect(try copy.chats() == b.chats())
    try expect(
      try copy.scalarForCheck("SELECT count(*) FROM conversations WHERE deleted=1")
        == .number(3))
    try expect(try copy.verify()["ok"] == .bool(true))
  }
  check("History windows page one chat with another interleaved, with bounded bodies and no gaps") {
    let b = try Workbook.create(
      at: root.appendingPathComponent("History windows.sevra"), title: "History")
    let chat = b.startChat
    let sibling = try b.createChat()
    var ids: [String] = []
    for n in 0..<240 {
      ids.append(
        try b.addMessage(
          "Window needle \(n)", role: n % 2 == 0 ? "user" : "assistant", conversation: chat))
      _ = try b.addMessage("Window needle sibling \(n)", role: "user", conversation: sibling)
      _ = try b.addMessage("Window needle receipt \(n)", role: "tool", conversation: chat)
    }
    let latest = try b.conversationWindow(conversation: chat)
    try expect(
      latest.messages.map(\.id) == Array(ids.suffix(100)) && latest.hasEarlier && !latest.hasLater)
    let center = try b.conversationWindow(conversation: chat, around: ids[120])
    try expect(
      center.messages.map(\.id) == Array(ids[70..<170]) && center.hasEarlier && center.hasLater)
    var page = latest
    var visited = Set(page.messages.map(\.id))
    for _ in 0..<8 where page.hasEarlier {
      page = try b.conversationWindow(conversation: chat, around: page.messages.first!.id)
      visited.formUnion(page.messages.map(\.id))
    }
    try expect(!page.hasEarlier && visited == Set(ids), "Earlier windows skipped messages")
    for _ in 0..<8 where page.hasLater {
      page = try b.conversationWindow(conversation: chat, around: page.messages.last!.id)
    }
    try expect(!page.hasLater && page.messages.last?.id == ids.last)
    try refuses("history_scope") {
      _ = try b.conversationWindow(conversation: sibling, around: ids[120])
    }
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses("cancelled") {
      _ = try b.conversationWindow(conversation: chat, cancellation: cancelled)
    }
    // Search stays inside one chat.
    let search = try b.searchHistory("needle", conversation: chat, limit: 20, visibleOnly: true)
    try expect(
      search["hits"].array.count == 20
        && search["hits"].array.allSatisfy {
          $0["role"].text != "tool" && !$0["excerpt"].text.contains("sibling")
        })
    let cursor = search["nextCursor"].text
    try refuses("stale_cursor") {
      _ = try b.searchHistory("needle", conversation: chat, cursor: cursor)
    }
    try refuses("stale_cursor") {
      _ = try b.searchHistory("needle", conversation: sibling, cursor: cursor, visibleOnly: true)
    }
    let next = try b.searchHistory(
      "needle", conversation: chat, cursor: cursor, limit: 20, visibleOnly: true)
    try expect(
      Set(search["hits"].array.map { $0["id"].text }).isDisjoint(
        with: next["hits"].array.map { $0["id"].text }))
    let longChat = try b.createChat()
    var large: [String] = []
    for _ in 0..<40 {
      large.append(
        try b.addMessage(
          String(repeating: "x", count: 120_000), role: "user", conversation: longChat))
    }
    let bounded = try b.conversationWindow(conversation: longChat, around: large[20])
    try expect(bounded.messages.contains { $0.id == large[20] })
    try expect(bounded.messages.reduce(0) { $0 + $1.body.utf8.count } <= 2 * 1024 * 1024)
    let indexes = bounded.messages.map { large.firstIndex(of: $0.id)! }
    try expect(indexes == Array(indexes.first!...indexes.last!), "Byte bound left hidden gaps")
    try expect(bounded.hasEarlier && bounded.hasLater && (try b.verify()["ok"] == .bool(true)))
  }
}

extension Workbook {
  fileprivate func scalarForCheck(_ sql: String, _ values: [Value] = []) throws -> Value {
    try synchronized { try db.scalar(sql, values) }
  }
}
