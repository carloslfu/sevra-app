import Foundation
import Markdown

/// A native read-only presentation. No displayed row becomes a saved Record.
public struct PreviewTableContent: Equatable {
  public let headings: [String]
  public let rows: [[String]]
  public let markdown: Bool
  public init(headings: [String], rows: [[String]], markdown: Bool = false) {
    self.headings = headings
    self.rows = rows
    self.markdown = markdown
  }
  public func plain(_ cell: String) -> String {
    markdown ? String(ConversationPresentation(cell).text.characters) : cell
  }
  public func cells(selected: IndexSet, headings includeHeadings: Bool) -> [[String]] {
    let indexes = selected.isEmpty ? IndexSet(rows.indices) : selected
    var cells = indexes.filter { rows.indices.contains($0) }.map { rows[$0].map(plain) }
    if includeHeadings { cells.insert(headings.map(plain), at: 0) }
    return cells
  }
}

public enum ConversationBlock: Equatable {
  case text(String)
  case table(PreviewTableContent)

  static func parse(_ source: String) -> [ConversationBlock] {
    // Source positions keep prose, code and links outside tables byte-identical.
    // The existing CommonMark parser handles escaped pipes and fenced examples.
    let document = Document(parsing: source, options: [.disableSmartOpts])
    let bytes = Array(source.utf8)
    var lineStarts = [0]
    for (offset, byte) in bytes.enumerated() where byte == 10 { lineStarts.append(offset + 1) }
    func offset(_ position: SourceLocation) -> Int? {
      guard position.line > 0, position.line <= lineStarts.count else { return nil }
      let value = lineStarts[position.line - 1] + position.column - 1
      return (0...bytes.count).contains(value) ? value : nil
    }
    var blocks: [ConversationBlock] = []
    var end = 0
    for child in document.children {
      guard let table = child as? Markdown.Table, let range = table.range,
        let start = offset(range.lowerBound), let stop = offset(range.upperBound),
        start >= end, stop >= start
      else { continue }
      if start > end {
        blocks.append(.text(String(decoding: bytes[end..<start], as: UTF8.self)))
      }
      blocks.append(
        .table(
          .init(
            headings: table.head.cells.map { $0.children.map { $0.format() }.joined() },
            rows: table.body.rows.map { $0.cells.map { $0.children.map { $0.format() }.joined() } },
            markdown: true)))
      end = stop
    }
    if end < bytes.count { blocks.append(.text(String(decoding: bytes[end...], as: UTF8.self))) }
    return blocks.isEmpty ? [.text(source)] : blocks
  }
}
