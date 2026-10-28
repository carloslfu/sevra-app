import Foundation
import Markdown

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
    func offset(_ location: SourceLocation) -> Int? {
      guard location.line > 0, location.line <= lines.count, location.column > 0 else { return nil }
      let start = lines[location.line - 1]
      guard location.column - 1 <= bytes.count - start else { return nil }
      let byte = start + location.column - 1
      var low = 0
      var high = byteOffsets.count
      while low < high {
        let middle = (low + high) / 2
        if byteOffsets[middle] < byte { low = middle + 1 } else { high = middle }
      }
      return low < byteOffsets.count && byteOffsets[low] == byte ? low : nil
    }
    func range(_ node: Markup) -> Range<Int>? {
      guard let r = node.range, let start = offset(r.lowerBound), let end = offset(r.upperBound),
        start <= end
      else { return nil }
      return start..<end
    }
    func string(_ r: Range<Int>) -> String { String(String.UnicodeScalarView(scalars[r])) }
    var blocked = [UInt8](repeating: 0, count: scalars.count)
    func block(_ r: Range<Int>) { for i in r { blocked[i] = 1 } }
    var found: [(selection: ReferenceSelection, syntax: ReferenceSyntaxSpan)] = []
    var unsupported = 0
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
      // cmark 0.9 can assign inline positions to a removed leading reference
      // definition. Refuse that paragraph's ambiguous coordinate system rather
      // than attach a real destination to bytes from the definition.
      if node is Paragraph, let r = range(node),
        string(r).range(of: #"\A {0,3}\[[^\r\n]*\]:"#, options: .regularExpression) != nil
      {
        return ReferenceParseResult(
          selections: [], state: "partial",
          detail:
            "A paragraph combines a leading reference definition and content with ambiguous Markdown positions. Separate them with a blank line. Original text is retained.",
          unsupportedTokens: 1)
      }
      if node is CodeBlock || node is InlineCode || node is Image || node is HTMLBlock {
        guard let r = range(node) else {
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
          return ReferenceParseResult(
            selections: [], state: "partial",
            detail: "An HTML source location could not be preserved. Original text is retained.",
            unsupportedTokens: 1)
        }
        block(r)
        let html = string(r).lowercased()
        if ["<code", "<pre", "<script", "<style"].contains(where: { html.hasPrefix($0) }) {
          if htmlCodeStart == nil { htmlCodeStart = r.lowerBound }
        } else if htmlCodeStart != nil
          && ["</code>", "</pre>", "</script>", "</style>"].contains(html)
        {
          block(htmlCodeStart!..<r.upperBound)
          htmlCodeStart = nil
        }
        continue
      }
      if let link = node as? Link {
        guard let r = range(node) else {
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
        if r.count >= 2 && scalars[r.lowerBound] == "<" {
          label = (r.lowerBound + 1)..<(r.upperBound - 1)
        } else if r.count >= 2 && scalars[r.lowerBound] == "[" {
          var depth = 1
          var i = r.lowerBound + 1
          while i < r.upperBound {
            if scalars[i] == "\\" {
              i += 2
              continue
            }
            if scalars[i] == "[" { depth += 1 }
            if scalars[i] == "]" { depth -= 1 }
            if depth == 0 {
              label = (r.lowerBound + 1)..<i
              break
            }
            i += 1
          }
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
