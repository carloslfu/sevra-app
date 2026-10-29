import AppKit
import Foundation
import PDFKit
import Vision
import ZIPFoundation

public struct ExtractionResult: Codable, Sendable {
  public let chunks: [Chunk]
  public let state: String
  public let detail: String
}
public enum Extractor {
  private static let unsupportedDetail =
    "Content search is unavailable for this format; filename search and native preview remain available."
  private static let pdfLimitDetail =
    "Automatic PDF text extraction is limited to 512 MB. Use a smaller excerpt for content search."

  /// Extraction describes searchable content, never asset ownership. Normalize
  /// the two older native messages on read without rewriting stored history.
  static func displayStatus(_ row: [String: Value]) -> Value {
    guard row["parser"]?.text == "native-v1", let original = row["detail"]?.string else {
      return .object(row)
    }
    let prefix = "Previous index retained. Retry failed: "
    let retained = original.hasPrefix(prefix)
    let detail = retained ? String(original.dropFirst(prefix.count)) : original
    let corrected: String
    switch detail {
    case "File included. " + unsupportedDetail: corrected = unsupportedDetail
    case "The PDF is included, but automatic extraction is limited to 512 MB. Use a smaller excerpt for content search.":
      corrected = pdfLimitDetail
    default: return .object(row)
    }
    var result = row
    result["detail"] = .string((retained ? prefix : "") + corrected)
    return .object(result)
  }

  public static func extract(_ url: URL, cancellation: Cancellation = .init()) throws
    -> ExtractionResult
  {
    try ExtractionWorker().extract(url, cancellation: cancellation)
  }
  static func extractInProcess(_ url: URL, cancellation: Cancellation) throws -> ExtractionResult {
    try cancellation.check()
    let ext = url.pathExtension.lowercased()
    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    if ext == "pdf" {
      try require(
        bytes <= 512_000_000, "pdf_limit",
        pdfLimitDetail
      )
      guard let pdf = PDFDocument(url: url) else { throw SevraError("pdf", "Cannot read PDF.") }
      try require(
        !pdf.isLocked, "encrypted", "Unlock this PDF in another app before importing its text.")
      var chunks: [Chunk] = []
      var chars = 0
      let maxPages = min(pdf.pageCount, 1000)
      var usedOCR = false
      for n in 0..<maxPages {
        try cancellation.check()
        guard let page = pdf.page(at: n) else { continue }
        var text = page.string ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          usedOCR = true
          let image = page.thumbnail(of: NSSize(width: 1600, height: 2000), for: .mediaBox)
          var rect = CGRect(origin: .zero, size: image.size)
          if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            text = try recognize(cg, cancellation: cancellation)
          }
        }
        chars += text.utf8.count
        if chars > 8_000_000 {
          return .init(
            chunks: chunks, state: "partial", detail: "Text limit reached before page \(n+1).")
        }
        chunks.append(Chunk(text, locator: "page=\(n+1)"))
      }
      let partial = maxPages < pdf.pageCount
      return .init(
        chunks: chunks, state: partial ? "partial" : "ready",
        detail: "\(maxPages) of \(pdf.pageCount) pages processed"
          + (usedOCR ? "; OCR may contain errors." : "."))
    }
    if ["png", "jpg", "jpeg", "heic", "tiff", "bmp", "webp"].contains(ext) {
      let options = [kCGImageSourceShouldCache: false] as CFDictionary
      guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
      else { throw SevraError("image", "Cannot decode this image.") }
      let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
      let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
      try require(
        width > 0 && height > 0 && Double(width) * Double(height) <= 100_000_000, "image_limit",
        "Image exceeds the OCR pixel limit.")
      guard
        let image = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 3000,
          ] as CFDictionary)
      else { throw SevraError("image", "Cannot render image for OCR.") }
      return .init(
        chunks: [Chunk(try recognize(image, cancellation: cancellation), locator: "image")],
        state: "ready", detail: "On-device OCR; check the original for accuracy.")
    }
    if ext == "xlsx" {
      let sheets = try XLSX.readInProcess(url, cancellation: cancellation)
      let chunks = sheets.flatMap { sheet in
        zip(sheet.rows, sheet.rowNumbers).map { row, n in
          Chunk(
            row.enumerated().map { "\(Workbook.spreadsheetColumn($0.offset))\(n): \($0.element)" }
              .joined(separator: "\n"), locator: "sheet=\(sheet.name); row=\(n)")
        }
      }
      return .init(
        chunks: chunks, state: "partial",
        detail:
          "Saved cell values indexed. Excel formulas, charts, external connections and macros are not evaluated."
      )
    }
    if ext == "docx" { return try office(url, ext: ext, cancellation: cancellation) }
    if [
      "txt", "md", "markdown", "csv", "tsv", "json", "html", "htm", "xml", "log", "rtf", "swift",
      "py",
    ].contains(ext) {
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      let data = try handle.read(upToCount: 8_000_000) ?? Data()
      var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
      try require(!text.isEmpty || bytes == 0, "encoding", "Text encoding could not be read.")
      if ext == "html" || ext == "htm" {
        text = text.replacingOccurrences(
          of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>", with: "", options: .regularExpression
        ).replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
      }
      if ext == "rtf",
        let attributed = try? NSAttributedString(
          data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
          documentAttributes: nil)
      {
        text = attributed.string
      }
      return .init(
        chunks: [Chunk(text)], state: bytes > data.count ? "partial" : "ready",
        detail: bytes > data.count ? "Only the first 8 MB were indexed." : "Text indexed.")
    }
    return .init(
      chunks: [], state: "unsupported",
      detail: unsupportedDetail
    )
  }
  static func recognize(_ image: CGImage, cancellation: Cancellation) throws -> String {
    try cancellation.check()
    let request = VNRecognizeTextRequest()
    let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    timer.schedule(deadline: .now(), repeating: .milliseconds(100))
    timer.setEventHandler {
      if cancellation.isCancelled || cancellation.isExpired { request.cancel() }
    }
    timer.resume()
    defer { timer.cancel() }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch {
      try cancellation.check()
      throw error
    }
    try cancellation.check()
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(
      separator: "\n")
  }
  static func office(_ url: URL, ext: String, cancellation: Cancellation) throws -> ExtractionResult
  {
    let archive = try Archive(url: url, accessMode: .read)
    var chunks: [Chunk] = []
    var expanded: UInt64 = 0
    var entries = 0
    for entry in archive {
      try cancellation.check()
      entries += 1
      try require(entries <= 10000, "archive_limit", "Office document has too many entries.")
      let eligible =
        ext == "docx"
        ? entry.path == "word/document.xml"
        : (entry.path == "xl/sharedStrings.xml" || entry.path.hasPrefix("xl/worksheets/sheet"))
      guard eligible else { continue }
      expanded += UInt64(entry.uncompressedSize)
      try require(
        expanded <= 16_000_000, "archive_limit", "Office document exceeds the extraction budget.")
      var data = Data()
      let checksum = try archive.extract(entry) { part in
        try cancellation.check()
        data.append(part)
        try require(
          data.count <= 16_000_000, "archive_limit", "Expanded content exceeds its limit.")
      }
      try require(checksum == entry.checksum, "checksum", "The document failed its checksum check.")
      let parser = XMLTextCollector(cancellation: cancellation)
      try require(
        String(decoding: data.filter { $0 != 0 }, as: UTF8.self).range(
          of: "<!DOCTYPE", options: .caseInsensitive)
          == nil, "xml", "Office XML document types and entity declarations are not supported.")
      let xml = XMLParser(data: data)
      xml.delegate = parser
      xml.shouldResolveExternalEntities = false
      guard xml.parse() else {
        try cancellation.check()
        throw SevraError("xml", "The Office document contains invalid XML.")
      }
      chunks.append(Chunk(parser.text, locator: entry.path))
    }
    return .init(
      chunks: chunks, state: ext == "xlsx" ? "partial" : "ready",
      detail: ext == "xlsx"
        ? "Worksheet XML and shared text indexed. Formatting, formula recalculation and full spreadsheet import require explicit conversion."
        : "Document body indexed; embedded objects and images are not extracted.")
  }
}
final class XMLTextCollector: NSObject, XMLParserDelegate {
  var text = ""
  let cancellation: Cancellation
  init(cancellation: Cancellation) { self.cancellation = cancellation }
  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if (try? cancellation.check()) == nil {
      parser.abortParsing()
      return
    }
    text += string
  }
  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) { text += " " }
}
extension Workbook {
  public func extract(
    _ id: String, cancellation: Cancellation = .init(), worker: ExtractionWorker = .init()
  ) throws {
    let record = try item(id)
    guard let assetID = record.assetID else { return }
    let bounded = Cancellation(parent: cancellation, deadlineAfterSeconds: 60)
    let previous = try extractionStatus(id)
    let attempt = identifier()
    _ = try mutation("extraction_start", request: .string(id)) {
      try db.execute(
        "INSERT INTO extraction_attempts VALUES(?,?) ON CONFLICT(item_id) DO UPDATE SET attempt_id=excluded.attempt_id",
        [.string(id), .string(attempt)])
      try db.execute(
        "INSERT INTO extraction VALUES(?,?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET state=excluded.state,detail=excluded.detail,updated=excluded.updated",
        [
          .string(id), .string("running"),
          .string("Indexing content; the previous index remains available."), .string("native-v1"),
          .string(timestamp()),
        ])
      return .string(id)
    }
    do {
      let result = try worker.extract(
        assetURL(assetID, cancellation: bounded), cancellation: bounded)
      try bounded.check()
      if try asset(assetID).mode == "linked" {
        _ = try assetURL(assetID, verify: true, cancellation: bounded)
      }
      try index(
        id, chunks: result.chunks, state: result.state, detail: result.detail,
        cancellation: bounded, expectedAttemptID: attempt)
    } catch {
      _ = try mutation("extraction_failure", request: .string(id)) {
        guard
          try db.scalar("SELECT attempt_id FROM extraction_attempts WHERE item_id=?", [.string(id)])
            .text == attempt
        else { return .bool(false) }
        let hadIndex = ["ready", "partial"].contains(previous["state"].text)
        let state = hadIndex ? "partial" : (cancellation.isCancelled ? "cancelled" : "failed")
        let detail =
          (hadIndex ? "Previous index retained. Retry failed: " : "") + error.localizedDescription
        try db.execute(
          "INSERT INTO extraction VALUES(?,?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET state=excluded.state,detail=excluded.detail,updated=excluded.updated",
          [
            .string(id), .string(state), .string(detail), .string("native-v1"),
            .string(timestamp()),
          ])
        return .string(id)
      }
      throw error
    }
  }
}
