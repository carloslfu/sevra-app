import Foundation
import Markdown
import SevraCore

/// The same parsed text supplies inline links and discoverable message actions.
/// Preserve exact destinations and merge adjacent formatting runs within a link.
public struct ConversationPresentation {
  public struct Link: Identifiable, Equatable {
    public let url: URL
    public let title: String
    public var id: String { url.absoluteString }
    public var actionTitle: String {
      title.lowercased().hasPrefix("open ") ? title : "Open " + title
    }
  }
  public let text: AttributedString
  public let links: [Link]
  public var blocks: [ConversationBlock] { ConversationBlock.parse(markdown) }
  private let markdown: String

  public init(_ markdown: String) {
    self.markdown = markdown
    var text =
      (try? AttributedString(
        markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(markdown)
    var links: [Link] = []
    var seen = Set<URL>()
    var destination: URL?
    var label = ""
    func flush() {
      guard let destination, seen.insert(destination).inserted else { return }
      let title = label.trimmingCharacters(in: .whitespacesAndNewlines)
      links.append(
        Link(url: destination, title: title.isEmpty ? destination.absoluteString : title))
    }
    // Snapshot runs before removing unsupported attributes from the copy.
    for run in Array(text.runs) {
      let url = run.link.flatMap { ConversationLinkTarget($0) == nil ? nil : $0 }
      if url != destination {
        flush()
        label = ""
        destination = url
      }
      if url != nil { label += String(text[run.range].characters) }
      if run.link != nil && url == nil { text[run.range].link = nil }
    }
    flush()
    self.text = text
    self.links = links
  }
}

/// What one conversation row draws, parsed once from the message body.
public struct ConversationMessageContent: Sendable {
  public enum Block: Sendable {
    case text(AttributedString)
    case table(PreviewTableContent)
  }
  public let presentation: ConversationPresentation
  public let blocks: [Block]

  public init(_ body: String) {
    presentation = ConversationPresentation(body)
    blocks = presentation.blocks.compactMap { block in
      switch block {
      case .text(let text):
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .text(ConversationPresentation(text.trimmingCharacters(in: .newlines)).text)
      case .table(let table): return .table(table)
      }
    }
  }
}

/// Parsing is too slow to repeat on every window update, so each message parses once, off the
/// main thread. An entry keeps the text it came from, so a changed body can never show an old parse.
public final class ConversationContentCache: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String: (body: String, content: ConversationMessageContent)] = [:]
  private var parses = 0
  public init() {}

  public var parseCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return parses
  }

  public func content(id: String, body: String) -> ConversationMessageContent {
    lock.lock()
    let saved = entries[id]
    lock.unlock()
    if let saved, saved.body == body { return saved.content }
    let content = ConversationMessageContent(body)
    lock.lock()
    entries[id] = (body, content)
    parses += 1
    lock.unlock()
    return content
  }

  /// Call off the main thread with the messages about to be shown.
  public func prepare(_ messages: [Message], cancellation: Cancellation) throws {
    for message in messages {
      try cancellation.check()
      _ = content(id: message.id, body: message.body)
    }
  }

  /// The window that is now on screen. Everything else is forgotten.
  public func retain(_ messages: [Message]) {
    let shown = Set(messages.map(\.id))
    lock.lock()
    entries = entries.filter { shown.contains($0.key) }
    lock.unlock()
  }
}

/// Workbook links navigate within the current workbook. Ordinary web/mail links
/// use the system handler; arbitrary application/file schemes are not chat actions.
public enum ConversationLinkTarget: Equatable {
  case evidence(id: String, locator: String?)
  case message(id: String)
  case external(URL)

  public init?(_ url: URL) {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = parts.scheme?.lowercased()
    else { return nil }
    if ["http", "https"].contains(scheme), !(parts.host ?? "").isEmpty {
      self = .external(url)
      return
    }
    if scheme == "mailto", !parts.path.isEmpty {
      self = .external(url)
      return
    }
    guard scheme == "sevra", parts.user == nil, parts.password == nil, parts.port == nil,
      parts.fragment == nil, url.pathComponents.count == 2,
      let id = url.pathComponents.last, !id.isEmpty, ![".", ".."].contains(id),
      !id.contains("/")
    else { return nil }
    let query = parts.queryItems ?? []
    switch parts.host {
    case "item":
      guard query.count <= 1, query.allSatisfy({ $0.name == "locator" }) else { return nil }
      self = .evidence(id: id, locator: query.first?.value)
    case "conversation":
      guard query.count == 1, query[0].name == "message",
        let message = query[0].value, !message.isEmpty
      else { return nil }
      self = .message(id: message)
    default: return nil
    }
  }
}
