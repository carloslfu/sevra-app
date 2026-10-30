import Foundation
import Markdown

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
