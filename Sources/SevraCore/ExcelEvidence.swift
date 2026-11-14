import CryptoKit
import Foundation
import ZIPFoundation

/// Inert source evidence. IDs are archive locators, never paths to read on the host.
public struct ExcelEvidence: Codable, Sendable {
  public let id: String
  public let kind: String
  public let text: String
  public let complete: Bool
  public let sha256: String
}

extension ExcelEvidence {
  static func readInProcess(_ url: URL, cancellation: Cancellation) throws -> [ExcelEvidence] {
    let archive = try Archive(url: url, accessMode: .read)
    var names = Set<String>()
    var budget: UInt64 = 0
    var result: [ExcelEvidence] = []
    for entry in archive {
      try cancellation.check()
      try require(
        names.count < 10_000 && names.insert(entry.path).inserted,
        "excel_evidence", "Duplicate or excessive workbook parts.")
      let path = entry.path
      guard path.hasPrefix("xl/") || path.hasPrefix("customUI/") else { continue }
      try require(
        !path.split(separator: "/").contains("..") && !path.contains("\\"),
        "excel_evidence", "Invalid workbook evidence path.")
      let lower = path.lowercased()
      guard
        lower.hasSuffix(".xml") || lower.hasSuffix(".rels")
          || lower.hasSuffix("vbaproject.bin") || lower.hasPrefix("xl/embeddings/")
          || (lower.hasPrefix("xl/activex/") && lower.hasSuffix(".bin"))
      else { continue }
      guard result.count < 256 else {
        throw SevraError("excel_evidence_limit", "This workbook has too many evidence parts.")
      }
      try require(
        entry.type == .file && entry.uncompressedSize <= 32_000_000
          && budget + entry.uncompressedSize <= 64_000_000,
        "excel_evidence_limit", "Workbook evidence exceeds its expansion budget.")
      budget += entry.uncompressedSize
      var bytes = Data()
      let crc = try archive.extract(entry) { part in
        try cancellation.check()
        try require(
          bytes.count + part.count <= 32_000_000, "excel_evidence_limit", "Oversized part.")
        bytes.append(part)
      }
      try require(crc == entry.checksum, "checksum", "Workbook evidence checksum failed.")
      let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
      if lower.hasSuffix("vbaproject.bin") {
        do {
          for (name, source) in try VBASource.modules(bytes, cancellation: cancellation) {
            result.append(
              .init(
                id: path + "/" + name, kind: "vba", text: source,
                complete: true, sha256: hash))
          }
        } catch {
          result.append(
            .init(
              id: path, kind: "unreadable_vba", text: error.localizedDescription,
              complete: false, sha256: hash))
        }
      } else if !lower.hasSuffix(".xml") && !lower.hasSuffix(".rels") {
        result.append(
          .init(
            id: path, kind: "unreadable_binary",
            text:
              "Embedded binary content is preserved in the original. Its executable or object behavior could not be extracted as readable source.",
            complete: false, sha256: hash))
      } else {
        guard
          let text = String(data: bytes, encoding: .utf8)
            ?? String(data: bytes, encoding: .utf16)
        else {
          result.append(
            .init(
              id: path, kind: "unreadable_xml", text: "XML encoding could not be read.",
              complete: false, sha256: hash))
          continue
        }
        try require(
          !text.localizedCaseInsensitiveContains("<!DOCTYPE"),
          "excel_evidence", "Workbook XML document types are refused.")
        // Raw XML retains layout, validation, names, formulas, pivots and connection details.
        // It is paged to the model, never interpreted as instructions or executed.
        result.append(.init(id: path, kind: "xml", text: text, complete: true, sha256: hash))
      }
    }
    try require(
      result.count <= 256 && result.reduce(0) { $0 + $1.text.utf8.count } <= 32_000_000,
      "excel_evidence_limit", "Expanded workbook evidence exceeds 32 MB.")
    return result
  }
}
