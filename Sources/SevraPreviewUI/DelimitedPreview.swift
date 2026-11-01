import Foundation
import SevraCore

public struct DelimitedPreview {
  public let table: PreviewTableContent
  public let detail: String
  public static let byteLimit = 1_000_000
  public static let rowLimit = 1_000

  public static func load(_ url: URL, cancellation: Cancellation = .init()) throws -> Self {
    try cancellation.check()
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let data = try file.read(upToCount: byteLimit + 1) ?? Data()
    var truncated = data.count > byteLimit
    var bytes = Data(data.prefix(byteLimit))
    // Finish at a complete record, never at a quoted multiline newline. A megabyte of short rows
    // holds more records than the parser takes, so the scan also stops short of that bound.
    var quoted = false
    var complete = 0
    var lines = 0
    for (index, byte) in bytes.enumerated() {
      if byte == 34 { quoted.toggle() }
      if (byte == 10 || byte == 13) && !quoted {
        complete = index + 1
        lines += 1
        if lines >= 90_000 {
          truncated = true
          break
        }
      }
    }
    if truncated {
      bytes = bytes.prefix(complete)
      try require(
        !bytes.isEmpty, "preview_limit",
        "The first complete row exceeds the 1 MB preview limit. Open a copy to inspect the original."
      )
    }
    guard let text = String(data: bytes, encoding: .utf8) else {
      throw SevraError(
        "preview_encoding", "This table is not UTF-8 text. Open a copy to inspect the original.")
    }
    let records = try CSV.parse(
      text, delimiter: url.pathExtension.lowercased() == "tsv" ? "\t" : CSV.delimiter(of: text),
      cancellation: cancellation)
    let width = records.map(\.count).max() ?? 0
    let first = records.first ?? []
    let headings = (0..<width).map { index in
      index < first.count && !first[index].isEmpty ? first[index] : "Column \(index + 1)"
    }
    let rows = records.dropFirst().prefix(rowLimit).map { row in
      row + Array(repeating: "", count: width - row.count)
    }
    let limits =
      truncated || records.count - 1 > rowLimit
      ? " Showing the first \(rows.count) data rows\(truncated ? " within 1 MB" : " of \(records.count - 1)"). The original is unchanged."
      : ""
    return .init(
      table: .init(headings: headings, rows: Array(rows)),
      detail: "Original values, read only. First row shown as headings." + limits)
  }
}
