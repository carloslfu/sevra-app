import Foundation
import SevraCore

/// How a thought reads in a line, a window or a block.
public enum ThoughtText {
  /// The last words, on one line.
  public static func line(_ text: String) -> String {
    String(text.suffix(240)).split(whereSeparator: \.isNewline).joined(separator: " ")
  }

  /// The last part of a thought that is still being written, so the newest words show.
  public static func tail(_ text: String, limit: Int = 480) -> String {
    guard text.count > limit else { return text }
    let start = text.index(text.endIndex, offsetBy: -limit)
    let rest = text[start...]
    let word = rest.firstIndex(where: \.isWhitespace).map { rest.index(after: $0) } ?? start
    return "…" + rest[word...]
  }

  public static func isLong(_ text: String) -> Bool {
    text.count > 320 || text.filter(\.isNewline).count > 3
  }

  /// The run's thinking so far as one flowing passage: each finished thought on its own line,
  /// then the one being written, the newest words last. Only the end is kept, so a window that
  /// shows its last lines lays out a bounded text however long the run thinks.
  public static func stream(
    _ thoughts: [ActivityThought], reasoning: String?, limit: Int = 900
  ) -> String {
    var parts: [String] = []
    var count = 0
    for text in [reasoning ?? ""] + thoughts.reversed().map(\.text) where !text.isEmpty {
      let flat = String(text.suffix(limit * 2)).split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
      guard !flat.isEmpty else { continue }
      parts.append(flat)
      count += flat.count + 1
      if count >= limit { break }
    }
    let joined = parts.reversed().joined(separator: "\n")
    guard joined.count > limit else { return joined }
    let start = joined.index(joined.endIndex, offsetBy: -limit)
    let rest = joined[start...]
    let word = rest.firstIndex(where: \.isWhitespace).map { rest.index(after: $0) } ?? start
    return String(rest[word...])
  }
}

/// The answer as it can be shown while it is still being written. A table row waits for its line
/// to end and a table's header for the line that makes it a table, and bold or code left open
/// closes, so no raw syntax shows and then jumps into place when the rest arrives. Only the
/// preview uses this; the saved reply shows its text as written.
public enum StreamingMarkdown {
  public static func settled(_ text: String) -> String {
    var lines = text.components(separatedBy: "\n")
    // Inside an open code fence, everything shows as code already.
    let fences = lines.filter {
      let line = $0.trimmingCharacters(in: .whitespaces)
      return line.hasPrefix("```") || line.hasPrefix("~~~")
    }.count
    if fences % 2 == 1 { return text }
    // The line being written, when it is a table row.
    if let last = lines.last, isTableLine(last) { lines.removeLast() }
    // The table rows at the very end: shown once the line under the header makes them a table.
    var end = lines.count
    if lines.last == "" { end -= 1 }
    var start = end
    while start > 0, isTableLine(lines[start - 1]) { start -= 1 }
    if start < end, !(end - start >= 2 && isDelimiter(lines[start + 1])) {
      lines.removeSubrange(start..<end)
    }
    var result = lines.joined(separator: "\n")
    while result.last?.isWhitespace == true { result.removeLast() }
    // Bold and code close within their paragraph. Tables and code blocks are left as written.
    let paragraphStart =
      result.range(of: "\n\n", options: .backwards)?.upperBound ?? result.startIndex
    let paragraph = result[paragraphStart...]
    let lastLine = paragraph.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
    guard !paragraph.contains("```"), !paragraph.contains("~~~"), !isTableLine(String(lastLine))
    else { return result }
    func trimmed(_ text: String) -> String {
      var text = text
      while text.last?.isWhitespace == true { text.removeLast() }
      return text
    }
    if paragraph.filter({ $0 == "`" }).count % 2 == 1 {
      if result.hasSuffix("`") { return trimmed(String(result.dropLast())) }
      return result + "`"
    }
    var outside = ""
    var code = false
    for character in paragraph {
      if character == "`" {
        code.toggle()
      } else if !code {
        outside.append(character)
      }
    }
    if (outside.components(separatedBy: "**").count - 1) % 2 == 1 {
      return result.hasSuffix("**") ? trimmed(String(result.dropLast(2))) : result + "**"
    }
    // Most likely the first half of a bold marker.
    if result.hasSuffix("*"), !result.hasSuffix("**") { return trimmed(String(result.dropLast())) }
    return result
  }

  static func isTableLine(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).hasPrefix("|")
  }

  static func isDelimiter(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.contains("-") && trimmed.allSatisfy { "|-: ".contains($0) }
  }
}
