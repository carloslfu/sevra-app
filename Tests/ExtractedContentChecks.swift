import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation

@testable import SevraCore

func checkExtractedContent(at root: URL) {
  func file(_ name: String, _ data: Data) throws -> URL {
    let url = root.appendingPathComponent(name)
    try data.write(to: url)
    return url
  }
  func text(_ result: ExtractionResult) -> String { result.chunks.map(\.text).joined() }
  check("text reads as what it is, stating a guess and refusing what is not text") {
    // Byte 8,000,000 falls inside a character, which used to send all of it to UTF-16.
    let cut = try Extractor.extract(
      file("cut.txt", Data(("a" + String(repeating: "é", count: 4_000_100)).utf8)))
    try expect(cut.state == "partial" && cut.detail == "Only the first 8 MB were indexed.")
    try expect(text(cut).hasPrefix("aéé") && text(cut).hasSuffix("é"))
    let marked = Data([0xFF, 0xFE]) + "Añejo €5".data(using: .utf16LittleEndian)!
    let wide = try Extractor.extract(file("wide.txt", marked))
    try expect(wide.state == "ready" && text(wide) == "Añejo €5")
    // An even byte count also decodes as UTF-16, into characters nobody wrote.
    let latin = try Extractor.extract(file("latin.txt", "Café".data(using: .isoLatin1)!))
    try expect(latin.state == "partial" && text(latin) == "Café")
    try expect(latin.detail.contains("Windows-1252"))
    // RTF names its own encoding, so its raw bytes are no guess.
    let rtf = try Extractor.extract(
      file("raw.rtf", "{\\rtf1\\ansi\\ansicpg1252 Café}".data(using: .isoLatin1)!))
    try expect(rtf.state == "ready" && text(rtf) == "Café")
    // A binary block is neither UTF-8 nor Windows-1252, and the parser reads past it.
    let binary = try Extractor.extract(
      file("binary.rtf", Data("{\\rtf1\\ansi Before \\bin2 ".utf8) + Data([0, 0xFF]) + Data(" after}".utf8)))
    try expect(text(binary).contains("Before") && text(binary).contains("after"), text(binary))
    try refuses("encoding") { _ = try Extractor.extract(file("binary.txt", Data([0xFF, 0, 0xE9]))) }
    let cutWide = Extractor.decodedText(marked + Data([0x3D, 0xD8, 0x00]), cut: true)
    try expect(cutWide?.text == "Añejo €5" && cutWide?.guessed == false)
  }
  check("HTML entities decode once, after tags, and unknown ones stay as written") {
    let page = "<p>Bogot&aacute; &amp;lt; R&amp;D &#241;&#xF1; &yuml;&szlig; &bogus; &#0; &lt;b&gt;</p>"
    let result = try Extractor.extract(file("entities.html", Data(page.utf8)))
    try expect(
      text(result).trimmingCharacters(in: .whitespaces)
        == "Bogotá &lt; R&D ññ ÿß &bogus; &#0; <b>")
  }
  check("Word text keeps words whole and leaves out deletions, moved text and field codes") {
    func docx(_ name: String, body: String?) throws -> URL {
      let url = root.appendingPathComponent(name)
      let archive = try Archive(url: url, accessMode: .create)
      let contents = Data((body ?? "<Types/>").utf8)
      try archive.addEntry(
        with: body == nil ? "[Content_Types].xml" : "word/document.xml", type: .file,
        uncompressedSize: Int64(contents.count), compressionMethod: .none
      ) { position, size in contents.subdata(in: Int(position)..<Int(position) + size) }
      return url
    }
    let body = """
      <w:document xmlns:w="w"><w:body>
        <w:p><w:r><w:t>Inv</w:t></w:r>
          <w:r><w:t>oice</w:t></w:r><w:r><w:tab/><w:t>total</w:t></w:r></w:p>
        <w:p><w:del><w:r><w:delText>gone</w:delText></w:r></w:del>
          <w:r><w:instrText>PAGE</w:instrText></w:r>
          <w:moveFrom><w:r><w:t>away</w:t></w:r></w:moveFrom><w:r><w:t>kept</w:t></w:r></w:p>
      </w:body></w:document>
      """
    let result = try Extractor.extract(docx("word.docx", body: body))
    try expect(result.state == "ready" && text(result) == "Invoice total\nkept\n")
    let empty = try Extractor.extract(docx("empty.docx", body: nil))
    try expect(empty.state == "partial" && empty.detail.contains("No text was found"))
  }
  check("page limits and empty pages report partial instead of ready") {
    func page(_ words: String, _ font: String = "Helvetica") -> CGImage {
      let bitmap = CGContext(
        data: nil, width: 1000, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
      bitmap.fill(CGRect(x: 0, y: 0, width: 1000, height: 300))
      bitmap.textPosition = CGPoint(x: 40, y: 150)
      CTLineDraw(
        CTLineCreateWithAttributedString(
          NSAttributedString(
            string: words,
            attributes: [
              NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                font as CFString, 72, nil),
              NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                gray: 0, alpha: 1),
            ])), bitmap)
      return bitmap.makeImage()!
    }
    func image(_ name: String, _ type: UTType, _ pages: [CGImage]) throws -> URL {
      let url = root.appendingPathComponent(name)
      let target = CGImageDestinationCreateWithURL(
        url as CFURL, type.identifier as CFString, pages.count, nil)!
      for page in pages { CGImageDestinationAddImage(target, page, nil) }
      try expect(CGImageDestinationFinalize(target))
      return url
    }
    let both = try Extractor.extract(
      image("two.tiff", .tiff, [page("ATLAS 1042"), page("CEDAR 2048")]))
    try expect(both.state == "partial" && both.detail.contains("first of 2 pages"))
    let blank = try Extractor.extract(image("blank.png", .png, [page("")]))
    try expect(blank.state == "partial" && blank.detail == "No text was found in this image.")
    let chinese = try Extractor.extract(
      image("chinese.png", .png, [page("合同编号", "PingFangSC-Regular")]))
    try expect(chinese.state == "ready" && text(chinese).contains("合同"))

    let pdf = root.appendingPathComponent("pages.pdf")
    var box = CGRect(x: 0, y: 0, width: 500, height: 200)
    let context = CGContext(pdf as CFURL, mediaBox: &box, nil)!
    for words in ["ATLAS 1042", "CEDAR 2048"] {
      context.beginPDFPage(nil)
      context.textPosition = CGPoint(x: 40, y: 100)
      CTLineDraw(
        CTLineCreateWithAttributedString(
          NSAttributedString(
            string: words,
            attributes: [
              NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                "Helvetica" as CFString, 24, nil)
            ])), context)
      context.endPDFPage()
    }
    context.closePDF()
    let stopped = try Extractor.extractInProcess(pdf, cancellation: .init(), timeBudget: 0)
    try expect(stopped.state == "partial" && stopped.chunks.count == 1)
    try expect(stopped.detail == "Time limit reached before page 2 of 2.")
    let whole = try Extractor.extractInProcess(pdf, cancellation: .init())
    try expect(whole.state == "ready" && whole.chunks.count == 2)
    let empty = root.appendingPathComponent("empty.pdf")
    let nothing = CGContext(empty as CFURL, mediaBox: &box, nil)!
    nothing.beginPDFPage(nil)
    nothing.endPDFPage()
    nothing.closePDF()
    let none = try Extractor.extractInProcess(empty, cancellation: .init())
    try expect(none.state == "partial" && none.detail == "No text was found in this PDF.")
  }
}
