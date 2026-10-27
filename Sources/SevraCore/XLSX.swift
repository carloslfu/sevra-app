import Foundation
import ZIPFoundation

public struct ImportedSheet: Sendable {
  public let name: String
  public let rows: [[String]]
  public let rowNumbers: [Int]
  public let notes: [String]
  public let formulas: [String: String]
}
public enum XLSX {
  public static func read(_ url: URL, cancellation: Cancellation = .init()) throws
    -> [ImportedSheet]
  {
    let archive = try Archive(url: url, accessMode: .read)
    var entries: [String: Entry] = [:]
    var budget: UInt64 = 0
    for entry in archive {
      try cancellation.check()
      try require(
        entries.count < 10_000 && entries[entry.path] == nil, "xlsx",
        "Office package has too many or duplicate entries.")
      entries[entry.path] = entry
    }
    func data(_ path: String) throws -> Data? {
      guard let entry = entries[path] else { return nil }
      try require(
        entry.type == .file && entry.uncompressedSize <= 32_000_000
          && budget + entry.uncompressedSize <= 64_000_000, "xlsx_limit",
        "Worksheet exceeds the 64 MB expanded import budget.")
      budget += entry.uncompressedSize
      var data = Data()
      let checksum = try archive.extract(entry) { part in
        try cancellation.check()
        data.append(part)
        try require(
          data.count <= 32_000_000, "xlsx_limit", "Office entry exceeds its declared limit.")
      }
      try require(
        checksum == entry.checksum, "checksum", "The worksheet failed its checksum check.")
      return data
    }
    func parse(_ path: String, _ delegate: XMLParserDelegate) throws {
      guard let bytes = try data(path) else {
        throw SevraError("xlsx", "Missing Office part: " + path)
      }
      try require(
        String(decoding: bytes.filter { $0 != 0 }, as: UTF8.self).range(
          of: "<!DOCTYPE", options: .caseInsensitive)
          == nil, "xlsx", "Office XML document types and entity declarations are not supported.")
      let parser = XMLParser(data: bytes)
      parser.delegate = delegate
      parser.shouldResolveExternalEntities = false
      let parsed = parser.parse()
      try cancellation.check()
      if let sheet = delegate as? SheetXML, let error = sheet.failure { throw error }
      try require(parsed, "xlsx", "Invalid worksheet XML: " + path)
    }
    let metadata = WorkbookXML()
    try parse("xl/workbook.xml", metadata)
    let relationships = RelationshipsXML()
    try parse("xl/_rels/workbook.xml.rels", relationships)
    let shared = SharedStringsXML()
    if entries["xl/sharedStrings.xml"] != nil { try parse("xl/sharedStrings.xml", shared) }
    let styles = StylesXML()
    if entries["xl/styles.xml"] != nil { try parse("xl/styles.xml", styles) }
    var result: [ImportedSheet] = []
    try require(
      metadata.sheets.count <= 100, "xlsx_limit", "At most 100 worksheets can be imported together."
    )
    for (name, rid) in metadata.sheets {
      try cancellation.check()
      guard let target = relationships.paths[rid] else {
        throw SevraError("xlsx", "Missing internal worksheet relationship.")
      }
      let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
      try require(
        !path.split(separator: "/").contains("..") && path.hasPrefix("xl/worksheets/"), "xlsx_path",
        "Unsafe worksheet relationship.")
      let sheet = SheetXML(
        shared: shared.values, styles: styles, epoch1904: metadata.epoch1904,
        cancellation: cancellation)
      try parse(path, sheet)
      if let error = sheet.failure { throw error }
      result.append(
        .init(
          name: name, rows: sheet.rows, rowNumbers: sheet.rowNumbers,
          notes: Array(sheet.notes).sorted(), formulas: sheet.formulas))
    }
    return result
  }
}
private final class WorkbookXML: NSObject, XMLParserDelegate {
  var sheets: [(String, String)] = [], epoch1904 = false
  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
    qualifiedName: String?, attributes a: [String: String]
  ) {
    if name == "sheet", let title = a["name"], let rid = a["r:id"] { sheets.append((title, rid)) }
    if name == "workbookPr" { epoch1904 = ["true", "1"].contains(a["date1904"] ?? "") }
  }
}
private final class RelationshipsXML: NSObject, XMLParserDelegate {
  var paths: [String: String] = [:]
  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
    qualifiedName: String?, attributes a: [String: String]
  ) {
    if name == "Relationship", a["TargetMode"] != "External", let id = a["Id"],
      let target = a["Target"], a["Type"]?.hasSuffix("/worksheet") == true
    {
      paths[id] = target
    }
  }
}
private final class SharedStringsXML: NSObject, XMLParserDelegate {
  var values: [String] = [], value = "", inText = false
  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    if name == "si" { value = "" }
    if name == "t" { inText = true }
  }
  func parser(_ parser: XMLParser, foundCharacters text: String) { if inText { value += text } }
  func parser(
    _ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?
  ) {
    if name == "t" { inText = false }
    if name == "si" { values.append(value) }
  }
}
private final class StylesXML: NSObject, XMLParserDelegate {
  var formats: [Int: String] = [:], styleIDs: [Int] = [], inCell = false
  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
    qualifiedName: String?, attributes a: [String: String]
  ) {
    if name == "numFmt", let id = Int(a["numFmtId"] ?? ""), let format = a["formatCode"] {
      formats[id] = format
    }
    if name == "cellXfs" { inCell = true }
    if name == "xf", inCell { styleIDs.append(Int(a["numFmtId"] ?? "") ?? 0) }
  }
  func parser(
    _ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?
  ) { if name == "cellXfs" { inCell = false } }
  func isDate(_ style: Int) -> Bool {
    guard styleIDs.indices.contains(style) else { return false }
    let id = styleIDs[style]
    if (14...22).contains(id) || (45...47).contains(id) { return true }
    let format = (formats[id] ?? "").lowercased().replacingOccurrences(
      of: "\"[^\"]*\"|\\\\.", with: "", options: .regularExpression)
    return format.contains("yy") || format.contains("dd") || format.contains("hh")
  }
}
private final class SheetXML: NSObject, XMLParserDelegate {
  let shared: [String], styles: StylesXML, epoch1904: Bool, cancellation: Cancellation
  var rows: [[String]] = [], rowNumbers: [Int] = [], notes = Set<String>(),
    formulas: [String: String] = [:], failure: Error?
  var current: [Int: String] = [:], number = 0, column = 0, reference = "", type = "", style = 0,
    value = "", formula = "", reading = "", count = 0
  init(shared: [String], styles: StylesXML, epoch1904: Bool, cancellation: Cancellation) {
    self.shared = shared
    self.styles = styles
    self.epoch1904 = epoch1904
    self.cancellation = cancellation
  }
  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
    qualifiedName: String?, attributes a: [String: String]
  ) {
    if cancellation.isCancelled {
      failure = SevraError("cancelled", "Worksheet import cancelled.")
      parser.abortParsing()
      return
    }
    if name == "row" {
      current = [:]
      number = Int(a["r"] ?? "") ?? number + 1
    }
    if name == "c" {
      reference = a["r"] ?? ""
      column = 0
      for char in reference.uppercased().unicodeScalars where (65...90).contains(Int(char.value)) {
        column = column * 26 + Int(char.value) - 64
      }
      column = max(1, column)
      type = a["t"] ?? ""
      style = Int(a["s"] ?? "") ?? 0
      value = ""
      formula = ""
      count += 1
      if column > 500 || rows.count >= 100_000 || count > 1_000_000 {
        failure = SevraError(
          "xlsx_limit", "Worksheet exceeds 500 columns, 100,000 rows or one million cells.")
        parser.abortParsing()
      }
    }
    if ["v", "t", "f"].contains(name) { reading = name }
  }
  func parser(_ parser: XMLParser, foundCharacters text: String) {
    if reading == "f" { formula += text } else if reading == "v" || reading == "t" { value += text }
  }
  func parser(
    _ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?
  ) {
    if ["v", "t", "f"].contains(name) { reading = "" }
    if name == "c" {
      var text = value
      if type == "s" {
        if let index = Int(value), shared.indices.contains(index) {
          text = shared[index]
        } else {
          failure = SevraError("xlsx", "Invalid shared string reference at " + reference)
          parser.abortParsing()
          return
        }
      } else if type == "b" {
        text = value == "1" ? "true" : "false"
      } else if type == "e" {
        notes.insert("Error cells remain explicit error strings.")
      } else if styles.isDate(style), let serial = Double(value), serial.isFinite,
        abs(serial) < 3_000_000
      {
        if !epoch1904 && serial >= 60 && serial < 61 {
          text = "1900-02-29 (Excel-only date)"
          notes.insert("Excel's nonexistent February 29, 1900 was preserved as text.")
        } else {
          let formatter = ISO8601DateFormatter()
          formatter.formatOptions = [.withInternetDateTime]
          formatter.timeZone = TimeZone(secondsFromGMT: 0)
          let base = formatter.date(
            from: epoch1904 ? "1904-01-01T00:00:00Z" : "1899-12-31T00:00:00Z")!
          text = formatter.string(
            from: base.addingTimeInterval((serial - (!epoch1904 && serial >= 61 ? 1 : 0)) * 86400))
        }
      }
      if !formula.isEmpty {
        formulas[reference] = formula
        notes.insert(
          "Formula cells use saved values; formulas are preserved as evidence and are not recalculated."
        )
        if value.isEmpty { text = "#NO_CACHED_VALUE" }
      }
      current[column - 1] = text
    }
    if name == "row", let last = current.keys.max() {
      rows.append((0...last).map { current[$0] ?? "" })
      rowNumbers.append(number)
    }
  }
}
extension Workbook {
  @discardableResult public func importXLSX(
    _ sourceID: String, cancellation: Cancellation = .init()
  ) throws -> [Dataset] {
    let source = try item(sourceID)
    guard let asset = source.assetID else {
      throw SevraError("xlsx", "Workbook source has no asset.")
    }
    let sheets = try XLSX.read(
      assetURL(asset, cancellation: cancellation), cancellation: cancellation)
    var tables: [Dataset] = []
    for sheet in sheets where !sheet.rows.isEmpty {
      try cancellation.check()
      let width = sheet.rows.map(\.count).max() ?? 0
      let columns = (0..<width).map { Column(id: "c\($0+1)", title: Self.spreadsheetColumn($0)) }
      let evidence = try addItem(
        category: "record", kind: "worksheet", title: source.title + " · " + sheet.name,
        text: sheet.notes.joined(separator: "\n"),
        data: .object([
          "originalRows": .array(sheet.rowNumbers.map { .number(Double($0)) }),
          "formulas": .object(sheet.formulas.mapValues(Value.string)),
        ]), meaning: "actual", status: "accepted", inputs: [source.id],
        transformation: "xlsx-cached-values-v1", token: "xlsx-sheet-" + sourceID + "-" + sheet.name)
      let rows = sheet.rows.map { row in
        Dictionary(
          uniqueKeysWithValues: columns.enumerated().map { i, c in
            (c.id, i < row.count && !row[i].isEmpty ? Value.string(row[i]) : .null)
          })
      }
      tables.append(
        try importDataset(
          title: source.title + " · " + sheet.name, columns: columns, rows: rows,
          sourceID: evidence.id, cancellation: cancellation))
    }
    return tables
  }
  public static func spreadsheetColumn(_ zero: Int) -> String {
    var n = zero + 1
    var s = ""
    while n > 0 {
      n -= 1
      s = String(UnicodeScalar(65 + n % 26)!) + s
      n /= 26
    }
    return s
  }
}
