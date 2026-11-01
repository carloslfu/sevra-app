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
  /// `timeBudget` stops page work early enough to report what was read before the 60 second limit.
  static func extractInProcess(
    _ url: URL, cancellation: Cancellation, timeBudget: TimeInterval = 45
  ) throws -> ExtractionResult {
    try cancellation.check()
    let stop = ProcessInfo.processInfo.systemUptime + timeBudget
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
        if n > 0, ProcessInfo.processInfo.systemUptime >= stop {
          return .init(
            chunks: chunks, state: "partial",
            detail: "Time limit reached before page \(n+1) of \(pdf.pageCount)."
              + (usedOCR ? " OCR may contain errors." : ""))
        }
        // Rendered pages pile up in the pool, and a long scan would reach the memory limit.
        let read: String? = try autoreleasepool {
          guard let page = pdf.page(at: n) else { return nil }
          var text = page.string ?? ""
          if !hasText(text) {
            usedOCR = true
            let image = page.thumbnail(of: NSSize(width: 1600, height: 2000), for: .mediaBox)
            var rect = CGRect(origin: .zero, size: image.size)
            if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
              text = try recognize(cg, cancellation: cancellation)
            }
          }
          return text
        }
        guard let text = read else { continue }
        chars += text.utf8.count
        if chars > 8_000_000 {
          return .init(
            chunks: chunks, state: "partial", detail: "Text limit reached before page \(n+1).")
        }
        chunks.append(Chunk(text, locator: "page=\(n+1)"))
      }
      guard chunks.contains(where: { hasText($0.text) }) else {
        return .init(chunks: chunks, state: "partial", detail: "No text was found in this PDF.")
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
      let text = try recognize(image, cancellation: cancellation)
      let pages = CGImageSourceGetCount(source)
      guard hasText(text) else {
        return .init(
          chunks: [Chunk(text, locator: "image")], state: "partial",
          detail: "No text was found in this image.")
      }
      return .init(
        chunks: [Chunk(text, locator: "image")], state: pages > 1 ? "partial" : "ready",
        detail: "On-device OCR; check the original for accuracy."
          + (pages > 1 ? " Only the first of \(pages) pages was read." : ""))
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
    if ext == "docx" { return try office(url, cancellation: cancellation) }
    if [
      "txt", "md", "markdown", "csv", "tsv", "json", "html", "htm", "xml", "log", "rtf", "swift",
      "py",
    ].contains(ext) {
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      let data = try handle.read(upToCount: 8_000_000) ?? Data()
      let cut = bytes > data.count
      guard let decoded = decodedText(data, cut: cut) else {
        throw SevraError("encoding", "Text encoding could not be read.")
      }
      var text = decoded.text
      if ext == "html" || ext == "htm" {
        text = decodedEntities(
          text.replacingOccurrences(
            of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>", with: "", options: .regularExpression
          ).replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
      }
      if ext == "rtf",
        let attributed = try? NSAttributedString(
          data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
          documentAttributes: nil)
      {
        text = attributed.string
      }
      let notes = [
        cut ? "Only the first 8 MB were indexed." : nil,
        decoded.guessed
          ? "This file is not UTF-8, so it was read as Windows-1252. Check the original if characters look wrong."
          : nil,
      ].compactMap { $0 }
      return .init(
        chunks: [Chunk(text)], state: notes.isEmpty ? "ready" : "partial",
        detail: notes.isEmpty ? "Text indexed." : notes.joined(separator: " "))
    }
    return .init(
      chunks: [], state: "unsupported",
      detail: unsupportedDetail
    )
  }
  private static func hasText(_ text: String) -> Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  /// UTF-8 first, allowing for a character the 8 MB read cut in half. UTF-16 needs its byte order
  /// mark, because any bytes decode as UTF-16 without one. Anything else with no NUL is a guess.
  static func decodedText(_ data: Data, cut: Bool) -> (text: String, guessed: Bool)? {
    let little = data.starts(with: [0xFF, 0xFE])
    if little || data.starts(with: [0xFE, 0xFF]) {
      var units = data.prefix(data.count & ~1)
      // A read that stops between the two halves of a surrogate pair leaves the first alone.
      if cut, units.count >= 4, (0xD8...0xDB).contains(units[units.endIndex - (little ? 1 : 2)]) {
        units = units.dropLast(2)
      }
      if let text = String(data: units, encoding: .utf16) { return (text, false) }
    }
    for trailing in 0...(cut ? 3 : 0) {
      if let text = String(data: data.dropLast(trailing), encoding: .utf8) { return (text, false) }
    }
    guard !data.contains(0), let text = String(data: data, encoding: .windowsCP1252) else {
      return nil
    }
    return (text, true)
  }
  /// HTML 4's Latin-1 names in code point order from U+00A0, then the rest that pages commonly use.
  private static let htmlEntities: [String: String] = {
    let latin = """
      nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not shy reg macr deg plusmn \
      sup2 sup3 acute micro para middot cedil sup1 ordm raquo frac14 frac12 frac34 iquest Agrave \
      Aacute Acirc Atilde Auml Aring AElig Ccedil Egrave Eacute Ecirc Euml Igrave Iacute Icirc \
      Iuml ETH Ntilde Ograve Oacute Ocirc Otilde Ouml times Oslash Ugrave Uacute Ucirc Uuml \
      Yacute THORN szlig agrave aacute acirc atilde auml aring aelig ccedil egrave eacute ecirc \
      euml igrave iacute icirc iuml eth ntilde ograve oacute ocirc otilde ouml divide oslash \
      ugrave uacute ucirc uuml yacute thorn yuml
      """.split(separator: " ")
    var names: [String: String] = [
      "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "ndash": "\u{2013}",
      "mdash": "\u{2014}", "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}",
      "rdquo": "\u{201D}", "hellip": "\u{2026}", "bull": "\u{2022}", "euro": "\u{20AC}",
      "trade": "\u{2122}",
    ]
    for (offset, name) in latin.enumerated() {
      names[String(name)] = String(UnicodeScalar(UInt8(0xA0 + offset)))
    }
    return names
  }()
  /// One pass, so "&amp;lt;" stays the text "&lt;". An unknown name stays as written.
  static func decodedEntities(_ text: String) -> String {
    let source = text as NSString
    let pattern = try! NSRegularExpression(
      pattern: "&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{1,7});")
    var result = ""
    var cursor = 0
    for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
      let name = source.substring(with: match.range(at: 1))
      let decoded: String?
      if name.hasPrefix("#") {
        let hex = name.dropFirst().first.map { $0 == "x" || $0 == "X" } ?? false
        let number = UInt32(name.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10) ?? 0
        decoded =
          number >= 32 || [9, 10, 13].contains(number)
          ? Unicode.Scalar(number).map(String.init) : nil
      } else {
        decoded = htmlEntities[name]
      }
      guard let decoded else { continue }
      result += source.substring(
        with: NSRange(location: cursor, length: match.range.location - cursor))
      result += decoded
      cursor = match.range.location + match.range.length
    }
    return result + source.substring(from: cursor)
  }
  static func recognize(_ image: CGImage, cancellation: Cancellation) throws -> String {
    try cancellation.check()
    let request = VNRecognizeTextRequest()
    // The default reads English alone and finds nothing on a Chinese or Japanese scan.
    request.automaticallyDetectsLanguage = true
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
  static func office(_ url: URL, cancellation: Cancellation) throws -> ExtractionResult {
    let archive = try Archive(url: url, accessMode: .read)
    var chunks: [Chunk] = []
    var expanded: UInt64 = 0
    var entries = 0
    for entry in archive {
      try cancellation.check()
      entries += 1
      try require(entries <= 10000, "archive_limit", "Office document has too many entries.")
      guard entry.path == "word/document.xml" else { continue }
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
    guard chunks.contains(where: { hasText($0.text) }) else {
      return .init(
        chunks: chunks, state: "partial", detail: "No text was found in this document's body.")
    }
    return .init(
      chunks: chunks, state: "ready",
      detail: "Document body indexed; embedded objects and images are not extracted.")
  }
}
/// Word splits a sentence into as many runs as its formatting needs, so a word ends only where a
/// paragraph, tab or line break does. Visible text is w:t, which leaves out field codes and
/// deletions. Text a tracked change moved away is still w:t, under w:moveFrom.
final class XMLTextCollector: NSObject, XMLParserDelegate {
  var text = ""
  private var visible = 0
  private var moved = 0
  let cancellation: Cancellation
  init(cancellation: Cancellation) { self.cancellation = cancellation }
  private func local(_ name: String) -> Substring { name.split(separator: ":").last ?? "" }
  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
  ) {
    switch local(elementName) {
    case "t": visible += 1
    case "moveFrom": moved += 1
    case "tab", "br", "cr": text += " "
    default: break
    }
  }
  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if (try? cancellation.check()) == nil {
      parser.abortParsing()
      return
    }
    if visible > 0 && moved == 0 { text += string }
  }
  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    switch local(elementName) {
    case "t": visible -= 1
    case "moveFrom": moved -= 1
    case "p": text += "\n"
    default: break
    }
  }
}
extension Workbook {
  public func extract(
    _ id: String, cancellation: Cancellation = .init(), worker: ExtractionWorker = .init()
  ) throws {
    let record = try item(id)
    guard let assetID = record.assetID else { return }
    let bounded = Cancellation(parent: cancellation, deadlineAfterSeconds: 60)
    let previous = try extractionStatus(id)
    // Extraction cannot read speech, so choosing a use for a recording keeps its transcript.
    if previous["parser"].text.hasPrefix("apple-speech") { return }
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
      // A linked original is hashed once, afterwards, so the check covers the bytes just read.
      let result = try worker.extract(resolvedAsset(assetID).1, cancellation: bounded)
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
