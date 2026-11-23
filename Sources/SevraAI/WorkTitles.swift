import Foundation
import SevraCore

/// The model's names for a chat and its workbook. Either may be empty: the work is not clear yet.
package struct WorkTitlesReply: Sendable, Equatable {
  package let chat: String
  package let workbook: String
  package static let maximumOutputTokens = 96
  package static let schema: String = {
    let title: Value = .object([
      "type": .string("string"), "minLength": .number(0), "maxLength": .number(60),
    ])
    let value: Value = .object([
      "type": .string("object"), "additionalProperties": .bool(false),
      "required": .array([.string("chat"), .string("workbook")]),
      "properties": .object(["chat": title, "workbook": title]),
    ])
    return try! value.json()
  }()
  package init(chat: String, workbook: String) {
    self.chat = chat
    self.workbook = workbook
  }
  package init?(json: String) {
    guard let value = try? Value.parse(json), let chat = value["chat"].string,
      let workbook = value["workbook"].string
    else { return nil }
    self.init(chat: chat, workbook: workbook)
  }
}

/// Sevra names the work it can see: a chat still called "New chat" or titled from its first
/// message, and a workbook still named by Sevra. A stand-in name gets a real one after any reply;
/// a name Sevra gave may improve after each of the first three replies. It never touches a name
/// the person gave.
package enum WorkTitles {
  /// What to name and from what, or nil when nothing needs a name now.
  package struct Plan: Sendable {
    package let chat: String
    package let namesChat: Bool
    package let namesWorkbook: Bool
    package let messages: [InferenceMessage]
  }

  /// After this many finished replies in a chat. A greeting first still leaves a reply to name
  /// the work from; later replies keep the name, so it does not keep changing under the person.
  package static let namingReplies: Set<Int> = [1, 2, 3]

  package static func plan(_ book: Workbook, conversation: String) throws -> Plan? {
    let history = try book.messages(conversation: conversation, limit: 60)
    let replies = history.filter { $0.role == "assistant" && $0.state == "complete" }.count
    guard replies > 0 else { return nil }
    let early = namingReplies.contains(replies)
    let namesChat =
      try book.chatTitleIsAutomatic(conversation)
      && (early || book.chatTitleIsPlaceholder(conversation))
    let namesWorkbook = book.titleIsAutomatic && (early || book.titleIsPlaceholder)
    guard namesChat || namesWorkbook else { return nil }
    let talk = history.filter { ["user", "assistant"].contains($0.role) }
    guard talk.contains(where: { $0.role == "user" }) else { return nil }
    // The first request says what the work is; the latest say where it went.
    var chosen = Array(talk.suffix(6))
    if let first = talk.first(where: { $0.role == "user" }), !chosen.contains(where: { $0.id == first.id })
    {
      chosen.insert(first, at: 0)
    }
    let files = try book.recentItemSummaries(limit: 30).filter { $0.assetID != nil }.prefix(8)
      .map(\.title)
    var lines = ["Conversation:"]
    for message in chosen {
      lines.append(
        (message.role == "user" ? "Person: " : "Sevra: ") + excerpt(message.body))
    }
    if !files.isEmpty { lines.append("Files in the workbook: " + files.joined(separator: "; ")) }
    lines.append("Current chat title: " + (try book.chats().first { $0.id == conversation }?.title ?? ""))
    lines.append("Current workbook name: " + book.title)
    return Plan(
      chat: conversation, namesChat: namesChat, namesWorkbook: namesWorkbook,
      messages: [
        InferenceMessage(role: "system", content: instructions),
        InferenceMessage(role: "user", content: lines.joined(separator: "\n")),
      ])
  }

  static let instructions = """
    You name work for a person's files. Read the conversation and answer with JSON.
    "chat": a title for this conversation, 2 to 6 words, like a document title.
    "workbook": a name for the whole workbook, 2 to 5 words, about what the work is for.
    Use the person's own terms and language. Capitalize only the first word and names. No quotes, no ending period, no dates unless they matter, no words like "chat", "conversation", "question" or "help".
    When a current title or name already fits the work, repeat it exactly.
    If the conversation does not yet say what the work is, such as a greeting or a test, use "" for both.
    """

  private static func excerpt(_ text: String) -> String {
    let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
    return flat.count > 500 ? String(flat.prefix(500)) + "…" : flat
  }

  /// A usable name, or nil: one line, no wrapping quotes or ending period, at most 60 characters,
  /// and never a placeholder.
  package static func clean(_ text: String) -> String? {
    var name = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
    name = name.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'“”‘’`")))
    while let last = name.last, ".,;:".contains(last) { name.removeLast() }
    name = name.trimmingCharacters(in: .whitespaces)
    // Titles start with a capital, whatever the model wrote; the rest keeps its case.
    if let first = name.first, first.isLowercase { name = first.uppercased() + name.dropFirst() }
    guard !name.isEmpty, name.count <= 60,
      ![Workbook.newChatTitle, WorkbookLibrary.untitled].contains(where: {
        $0.caseInsensitiveCompare(name) == .orderedSame
      })
    else { return nil }
    return name
  }

  /// Applies what the model wrote, to the names that are still Sevra's. Returns whether either
  /// changed.
  @discardableResult package static func apply(
    _ reply: WorkTitlesReply, plan: Plan, to book: Workbook
  ) throws -> Bool {
    var changed = false
    if plan.namesChat, let title = clean(reply.chat),
      try book.chats().first(where: { $0.id == plan.chat })?.title != title
    {
      changed = try book.setAutomaticChatTitle(plan.chat, title: title) || changed
    }
    if plan.namesWorkbook, let name = clean(reply.workbook), name != book.title {
      changed = try book.setAutomaticTitle(name) || changed
    }
    return changed
  }
}
