import Foundation
import Markdown

/// The Markdown parser recurses once per level of quotes, lists and inline spans, and a few hundred
/// levels can overflow a worker thread's stack. Each block level has a marker to the right of its
/// parent's, so a marker's column bounds its depth. An inline level needs a delimiter that can open
/// and, after every opener inside it, one that can close, so a block cannot nest past the limit
/// without more than the limit of each, in that order. Raw bytes include delimiters in code, which
/// only overcounts. The one exception is a plain pair such as **Total**, which opens and closes one
/// level with nothing between that could hide either run, so long tables and lists are not deep.
public enum MarkdownNesting {
  static let limit = 100
  public static func isReadable(_ text: String) -> Bool {
    let bytes = Array(text.utf8)
    func isSpace(_ byte: UInt8) -> Bool { byte == 32 || byte == 9 || byte == 10 || byte == 13 }
    func isWord(_ byte: UInt8) -> Bool {
      (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
    }
    func isPunctuation(_ byte: UInt8) -> Bool {
      (33...126).contains(byte) && !isWord(byte)
    }
    // A delimiter run faces `inner` and turns its back on `outer`, as in CommonMark's flanking
    // rules. Bytes outside ASCII count as neither space nor punctuation, again overcounting.
    func flanks(_ delimiter: UInt8, inner: UInt8, outer: UInt8) -> Bool {
      !isSpace(inner)
        && !(isWord(outer) && (delimiter == UInt8(ascii: "_") || isPunctuation(inner)))
    }
    var opened = 0
    var closed = 0
    var plainOpener: (byte: UInt8, count: Int)?
    var column = 0
    var inPrefix = true
    var blank = true
    var bullet = false
    // cmark drops a leading byte order mark before it reads the first line's markers.
    var index = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
    while index < bytes.count {
      let byte = bytes[index]
      if byte == 10 || byte == 13 {
        if blank {
          opened = 0
          closed = 0
        }
        plainOpener = nil
        column = 0
        inPrefix = true
        blank = true
        bullet = false
        index += byte == 13 && index + 1 < bytes.count && bytes[index + 1] == 10 ? 2 : 1
        continue
      }
      if byte != 32 && byte != 9 && byte != UInt8(ascii: ">") { blank = false }
      let next = index + 1 < bytes.count ? bytes[index + 1] : 10
      if inPrefix {
        switch byte {
        case 32: column += 1
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
          column += 1
          // A list number runs straight into its delimiter.
          let number =
            (48...57).contains(next) || next == UInt8(ascii: ".") || next == UInt8(ascii: ")")
          if !number { inPrefix = false }
        case 9: column += 4 - column % 4
        case UInt8(ascii: ">"):
          if column >= limit { return false }
          column += 1
        case UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: "*"), UInt8(ascii: "."),
          UInt8(ascii: ")"):
          if isSpace(next) {
            if column >= limit { return false }
            // A bullet with text always ends the paragraph before it. A number need not.
            if column < 4 && byte != UInt8(ascii: ".") && byte != UInt8(ascii: ")") {
              bullet = true
            }
            column += 1
          } else {
            inPrefix = false
          }
        default: inPrefix = false
        }
        if bullet && !inPrefix {
          opened = 0
          closed = 0
        }
      }
      switch byte {
      case UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "~"):
        var end = index + 1
        while end < bytes.count && bytes[end] == byte { end += 1 }
        let previous = index > 0 ? bytes[index - 1] : 10
        let following = end < bytes.count ? bytes[end] : 10
        let count = end - index
        let opens = flanks(byte, inner: following, outer: previous)
        let closes = flanks(byte, inner: previous, outer: following)
        // Outside ASCII a run's flanking is unknown, so only the rule above decides.
        if closes && !opens, previous < 0x80, following < 0x80, let opener = plainOpener,
          opener.byte == byte, opener.count == count
        {
          opened -= count
          plainOpener = nil
        } else {
          if opens { opened += count }
          if opened > limit && closes { closed += count }
          let plain = opens && !closes && isWord(following) && previous != UInt8(ascii: "\\")
          plainOpener = plain ? (byte, count) : nil
        }
        index = end - 1
      case UInt8(ascii: "!") where next == UInt8(ascii: "["): opened += 1
      case UInt8(ascii: "]") where opened > limit:
        closed += 1
        plainOpener = nil
      // Code spans, HTML, link parts and escapes can hide a run from the parser.
      case UInt8(ascii: "`"), UInt8(ascii: "<"), UInt8(ascii: ">"), UInt8(ascii: "["),
        UInt8(ascii: "]"), UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "\\"):
        plainOpener = nil
      default: break
      }
      if closed > limit { return false }
      index += 1
    }
    return true
  }
}

public struct ReferenceParseResult: Sendable {
  public let selections: [ReferenceSelection]
  public let state: String
  public let detail: String
  public let unsupportedTokens: Int
  public let syntax: [ReferenceSyntaxSpan]

  init(
    selections: [ReferenceSelection], state: String, detail: String, unsupportedTokens: Int,
    syntax: [ReferenceSyntaxSpan] = []
  ) {
    self.selections = selections
    self.state = state
    self.detail = detail
    self.unsupportedTokens = unsupportedTokens
    self.syntax = syntax
  }
}

/// Presentation boundaries only. Destinations always come from saved bindings.
public struct ReferenceSyntaxSpan: Sendable {
  public let startScalar: Int
  public let scalarCount: Int
  public let labelStartScalar: Int
  public let labelScalarCount: Int
}

/// Versioned, deterministic source parsing. Names remain lookup hints, not IDs.
/// Markdown supplies code/image/HTML boundaries; raw scalar spans preserve bytes.
public enum InlineReferenceParser {
  public static let identity = "inline-links-v1-markdown-0.9.0"
  // One whole definition: a plain label, a destination, an optional title, then the line's end.
  // Bracketed text that happens to precede a colon is an ordinary paragraph.
  private static let referenceDefinition =
    #"\A {0,3}\[(?:[^\[\]\\]|\\.)+\]:[ \t]*(?:\R[ \t]*)?(?:<[^<>\r\n]*>|[^\s<]\S*)"#
    + #"(?:\s+(?:"[^"]*"|'[^']*'|\([^()]*\)))?[ \t]*(?:\R|\z)"#

  public static func target(_ route: String) -> ReferenceTarget? {
    guard route.utf8.count <= 1024 else { return nil }
    let parts = route.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard parts.count >= 4, parts[0].lowercased() == "sevra:", parts[1].isEmpty else { return nil }
    let mode: ReferenceTargetMode
    let identity: String
    let workbook: String?
    if parts.count == 4 {
      guard ["item", "logical"].contains(parts[2].lowercased()) else { return nil }
      mode = parts[2].lowercased() == "item" ? .pinned : .live
      identity = parts[3]
      workbook = nil
    } else if parts.count == 6 && parts[2].lowercased() == "workbook" {
      guard ["item", "logical"].contains(parts[4].lowercased()) else { return nil }
      mode = parts[4].lowercased() == "item" ? .pinned : .live
      identity = parts[5]
      workbook = parts[3]
    } else {
      return nil
    }
    guard (try? Workbook.validateReferenceIdentity(identity)) != nil,
      workbook.map({ (try? Workbook.validateReferenceIdentity($0)) != nil }) ?? true
    else { return nil }
    return ReferenceTarget(mode: mode, identity: identity, workbookID: workbook)
  }

  public static func parse(_ text: String, cancellation: Cancellation = .init()) throws
    -> ReferenceParseResult
  {
    try cancellation.check()
    guard text.utf8.count <= Workbook.referenceBodyLimit else {
      return ReferenceParseResult(
        selections: [], state: "unsupported",
        detail: "The body exceeds the bounded link-parser size. Original text is retained.",
        unsupportedTokens: 0)
    }
    // Plain bodies need no AST allocation. Their empty parse is still recorded.
    guard text.contains("[") || text.contains("<") else {
      return ReferenceParseResult(
        selections: [], state: "ready", detail: "Item body checked for supported links.",
        unsupportedTokens: 0)
    }
    let scalars = Array(text.unicodeScalars)
    // CommonMark replaces NUL with U+FFFD before assigning byte columns. Keep
    // that parser coordinate system while mapping back to original scalars.
    let parserText = text.replacingOccurrences(of: "\0", with: "\u{FFFD}")
    var byteOffsets = [0]
    for scalar in scalars {
      byteOffsets.append(byteOffsets.last! + (scalar.value == 0 ? 3 : scalar.utf8.count))
    }
    let bytes = Array(parserText.utf8)
    var lines = [0]
    var position = 0
    while position < bytes.count {
      if bytes[position] == 13 {
        if position + 1 < bytes.count && bytes[position + 1] == 10 { position += 1 }
        lines.append(position + 1)
      } else if bytes[position] == 10 {
        lines.append(position + 1)
      }
      position += 1
    }
    // cmark 0.9 numbers an inline on a paragraph's later line from the paragraph's first column,
    // after dropping that line's own indent and quote markers.
    var paragraphStart: SourceLocation?
    func offset(_ location: SourceLocation, firstColumn: Int? = nil) -> Int? {
      guard location.line > 0, location.line <= lines.count, location.column > 0 else { return nil }
      var start = lines[location.line - 1]
      var column = location.column
      if let paragraphStart, location.line > paragraphStart.line {
        while start < bytes.count, [32, 9, UInt8(ascii: ">")].contains(bytes[start]) { start += 1 }
        column += 1 - (firstColumn ?? paragraphStart.column)
      }
      guard column > 0, column - 1 <= bytes.count - start else { return nil }
      let byte = start + column - 1
      var low = 0
      var high = byteOffsets.count
      while low < high {
        let middle = (low + high) / 2
        if byteOffsets[middle] < byte { low = middle + 1 } else { high = middle }
      }
      return low < byteOffsets.count && byteOffsets[low] == byte ? low : nil
    }
    func range(_ node: Markup) -> Range<Int>? {
      // A code span or tag over several lines numbers its end from that line's own text instead,
      // and a tag's end stops short of its `>`.
      guard let r = node.range else { return nil }
      let spansLines = r.lowerBound.line != r.upperBound.line
      let firstColumn = !spansLines ? nil : node is InlineCode ? 1 : node is InlineHTML ? 0 : nil
      guard let start = offset(r.lowerBound),
        let end = offset(r.upperBound, firstColumn: firstColumn), start <= end
      else { return nil }
      // Some positions stay wrong, such as after a backslash line break or an escaped table pipe.
      // Every delimited inline must find its own delimiters at the bytes it names.
      let delimiters: (opening: String, closing: String)
      switch node {
      case is InlineCode: delimiters = ("`", "`")
      case is InlineHTML: delimiters = ("<", ">")
      case is Image: delimiters = ("!", ")]")
      case is Link: delimiters = ("[<", ")]>")
      default: return start..<end
      }
      guard start < end, delimiters.opening.unicodeScalars.contains(scalars[start]),
        delimiters.closing.unicodeScalars.contains(scalars[end - 1])
      else { return nil }
      return start..<end
    }
    func string(_ r: Range<Int>) -> String { String(String.UnicodeScalarView(scalars[r])) }
    var blocked = [UInt8](repeating: 0, count: scalars.count)
    func block(_ r: Range<Int>) { for i in r { blocked[i] = 1 } }
    var found: [(selection: ReferenceSelection, syntax: ReferenceSyntaxSpan)] = []
    var unsupported = 0
    // cmark loses count of a line at a backslash break or a link destination on its own line, and
    // of a column at an escaped table pipe. Every later position in that paragraph or cell is off,
    // so it stays plain text and the rest of the body still reads.
    var paragraph: Range<Int>?
    var abandoned = false
    func abandonParagraph() -> Bool {
      guard let paragraph else { return false }
      block(paragraph)
      unsupported += 1
      abandoned = true
      return true
    }
    guard MarkdownNesting.isReadable(parserText) else {
      return ReferenceParseResult(
        selections: [], state: "partial",
        detail: "This document nests too deeply to read its links.", unsupportedTokens: 0)
    }
    let document = Document(parsing: parserText)
    try cancellation.check()
    var pending: [Markup] = [document]
    var visited = 0
    var htmlCodeStart: Int?
    while let node = pending.popLast() {
      visited += 1
      if visited > 50_000 {
        return ReferenceParseResult(
          selections: [], state: "partial",
          detail:
            "Link parsing reached its structural bound. No incomplete edge set was published.",
          unsupportedTokens: 0)
      }
      if visited % 128 == 0 { try cancellation.check() }
      if node is BlockMarkup || node is Markdown.Table.Cell {
        paragraphStart = nil
        paragraph = nil
        abandoned = false
      } else if abandoned {
        continue
      }
      // cmark 0.9 can assign inline positions to a removed leading reference
      // definition. Refuse that paragraph's ambiguous coordinate system rather
      // than attach a real destination to bytes from the definition.
      if node is Paragraph, let r = range(node),
        string(r).range(of: referenceDefinition, options: .regularExpression) != nil
      {
        return ReferenceParseResult(
          selections: [], state: "partial",
          detail:
            "A paragraph combines a leading reference definition and content with ambiguous Markdown positions. Separate them with a blank line. Original text is retained.",
          unsupportedTokens: 1)
      }
      if node is Markdown.Table.Cell {
        paragraph = range(node)
      } else if node is Paragraph || node is Heading {
        paragraph = range(node)
        paragraphStart = node.range?.lowerBound
      }
      if node is CodeBlock || node is InlineCode || node is Image || node is HTMLBlock {
        guard let r = range(node) else {
          if abandonParagraph() { continue }
          return ReferenceParseResult(
            selections: [], state: "partial",
            detail: "A Markdown source location could not be preserved. Original text is retained.",
            unsupportedTokens: 1)
        }
        block(r)
        continue
      }
      if node is InlineHTML {
        guard let r = range(node) else {
          if abandonParagraph() { continue }
          return ReferenceParseResult(
            selections: [], state: "partial",
            detail: "An HTML source location could not be preserved. Original text is retained.",
            unsupportedTokens: 1)
        }
        block(r)
        let html = string(r).lowercased()
        let closing = html.hasPrefix("</")
        let tag = html.dropFirst(closing ? 2 : 1).prefix { $0.isLetter || $0.isNumber || $0 == "-" }
        if ["code", "pre", "script", "style"].contains(String(tag)) {
          if !closing {
            if htmlCodeStart == nil && !html.hasSuffix("/>") { htmlCodeStart = r.lowerBound }
          } else if let start = htmlCodeStart {
            block(start..<r.upperBound)
            htmlCodeStart = nil
          }
        }
        continue
      }
      if let link = node as? Link {
        guard let r = range(node) else {
          if abandonParagraph() { continue }
          return ReferenceParseResult(
            selections: [], state: "partial",
            detail: "A Markdown link location could not be preserved. Original text is retained.",
            unsupportedTokens: 1)
        }
        block(r)
        guard htmlCodeStart == nil, let destination = link.destination,
          destination.lowercased().hasPrefix("sevra:")
        else { continue }
        guard let target = target(destination) else {
          unsupported += 1
          continue
        }
        var label: Range<Int>?
        if scalars[r.lowerBound] == "<" {
          label = (r.lowerBound + 1)..<(r.upperBound - 1)
        } else if let last = Array(link.children).reversed().lazy.compactMap(range).first {
          // The label ends where its last inline does: a `]` in a code span is not the bracket.
          var end = last.upperBound
          while end < r.upperBound && scalars[end].properties.isWhitespace { end += 1 }
          guard end < r.upperBound, scalars[end] == "]" else {
            if abandonParagraph() { continue }
            return ReferenceParseResult(
              selections: [], state: "partial",
              detail: "A Markdown link location could not be preserved. Original text is retained.",
              unsupportedTokens: 1)
          }
          label = (r.lowerBound + 1)..<end
        }
        if let label, !label.isEmpty, label.count <= 1024, string(label).utf8.count <= 1024 {
          found.append(
            (
              .init(
                startScalar: label.lowerBound, scalarCount: label.count, target: target,
                lookup: destination),
              .init(
                startScalar: r.lowerBound, scalarCount: r.count,
                labelStartScalar: label.lowerBound, labelScalarCount: label.count)
            ))
        } else {
          unsupported += 1
        }
        continue
      }
      pending.append(contentsOf: Array(node.children).reversed())
    }
    if let start = htmlCodeStart { block(start..<scalars.count) }
    var i = 0
    while i < scalars.count {
      if i % 1024 == 0 { try cancellation.check() }
      if blocked[i] != 0 {
        i += 1
        continue
      }
      if scalars[i] == "\\" {
        i += 2
        continue
      }
      guard scalars[i] == "[", i + 1 < scalars.count, scalars[i + 1] == "[" else {
        i += 1
        continue
      }
      let start = i
      i += 2
      var end = i
      var pipe: Int?
      while end + 1 < scalars.count && end - start <= 4096 && blocked[end] == 0
        && scalars[end] != "\n" && scalars[end] != "\r"
      {
        if scalars[end] == "\\" {
          end += 2
          continue
        }
        if scalars[end] == "|" {
          if pipe != nil { break }
          pipe = end
        }
        if scalars[end] == "]" && scalars[end + 1] == "]" { break }
        if scalars[end] == "[" { break }
        end += 1
      }
      guard end + 1 < scalars.count, scalars[end] == "]", scalars[end + 1] == "]" else {
        unsupported += 1
        // Recover at the closing delimiter or line boundary. Do not interpret
        // nested fragments of one malformed token as independent wiki links.
        while end + 1 < scalars.count && end - start <= 4096 && scalars[end] != "\n"
          && scalars[end] != "\r"
        {
          if scalars[end] == "]" && scalars[end + 1] == "]" {
            end += 2
            break
          }
          end += 1
        }
        i = max(i, end)
        continue
      }
      let lookup = string((start + 2)..<(pipe ?? end)).trimmingCharacters(in: .whitespaces)
      var label = (pipe.map { $0 + 1 } ?? (start + 2))..<end
      while !label.isEmpty && scalars[label.lowerBound].properties.isWhitespace {
        label = (label.lowerBound + 1)..<label.upperBound
      }
      while !label.isEmpty && scalars[label.upperBound - 1].properties.isWhitespace {
        label = label.lowerBound..<(label.upperBound - 1)
      }
      i = end + 2
      guard !lookup.isEmpty, lookup.utf8.count <= 1024, !label.isEmpty, label.count <= 1024,
        string(label).utf8.count <= 1024
      else {
        unsupported += 1
        continue
      }
      let selectedTarget = target(lookup)
      if lookup.lowercased().hasPrefix("sevra:") && selectedTarget == nil {
        unsupported += 1
        continue
      }
      found.append(
        (
          .init(
            startScalar: label.lowerBound, scalarCount: label.count, target: selectedTarget,
            lookup: lookup),
          .init(
            startScalar: start, scalarCount: end + 2 - start,
            labelStartScalar: label.lowerBound, labelScalarCount: label.count)
        ))
    }
    found.sort { $0.selection.startScalar < $1.selection.startScalar }
    let limited = found.count > Workbook.referenceLimit
    return ReferenceParseResult(
      selections: found.prefix(Workbook.referenceLimit).map(\.selection),
      state: limited || unsupported > 0 ? "partial" : "ready",
      detail: limited
        ? "The body contains more links than one annotation snapshot supports. Listed links are partial."
        : unsupported > 0
          ? "Supported body links were parsed; some unsupported tokens remain plain text."
          : "Item body checked for supported links. Names remain unresolved until selected.",
      unsupportedTokens: unsupported,
      syntax: found.prefix(Workbook.referenceLimit).map(\.syntax))
  }
}
