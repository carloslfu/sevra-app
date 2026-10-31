import Foundation
import Markdown
import SevraCore

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
  /// Supported links as UTF-16 ranges of `plain(cell)`.
  public func linkRanges(_ cell: String) -> [NSRange] {
    guard markdown else { return [] }
    let text = ConversationPresentation(cell).text
    return text.runs.compactMap { run in run.link == nil ? nil : NSRange(run.range, in: text) }
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
    guard MarkdownNesting.isReadable(source) else { return [.text(source)] }
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
    // Cells keep their source, so escapes and a literal ^ survive to the one place that reads them.
    func text(_ cell: Markdown.Table.Cell) -> String {
      guard let range = cell.range, let start = offset(range.lowerBound),
        let stop = offset(range.upperBound), stop >= start
      else { return cell.children.map { $0.format() }.joined() }
      return String(decoding: bytes[start..<stop], as: UTF8.self)
        .trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\|", with: "|")
    }
    var blocks: [ConversationBlock] = []
    var end = 0
    for child in document.children {
      guard let table = child as? Markdown.Table, let range = table.range,
        let stop = offset(range.upperBound)
      else { continue }
      // A paragraph with no blank line before the table shares its range, so start at the heading.
      let heading = range.upperBound.line - table.body.childCount - 2
      guard lineStarts.indices.contains(heading), lineStarts[heading] >= end,
        stop >= lineStarts[heading]
      else { continue }
      let start = lineStarts[heading]
      if start > end {
        blocks.append(.text(String(decoding: bytes[end..<start], as: UTF8.self)))
      }
      blocks.append(
        .table(
          .init(
            headings: table.head.cells.map(text), rows: table.body.rows.map { $0.cells.map(text) },
            markdown: true)))
      end = stop
    }
    if end < bytes.count { blocks.append(.text(String(decoding: bytes[end...], as: UTF8.self))) }
    return blocks.isEmpty ? [.text(source)] : blocks
  }
}
