import Foundation
import ZIPFoundation

public struct ImportedSheet: Codable, Sendable {
  public let name: String
  public let rows: [[String]]
  public let rowNumbers: [Int]
  public let notes: [String]
  public let formulas: [String: String]
  /// Cells, by reference, whose saved text is not a settled value: "error",
  /// "uncached" (a formula with no saved result) or "format" (a number Excel shows
  /// differently, such as 14 under the format 0000).
  public let unsettled: [String: String]
  /// Cells only Excel can recalculate: "array", "dataTable" or "shared" for a shared
  /// formula whose first cell is missing. "*" stands for an area too large to list.
  public let formulaKinds: [String: String]
  public init(
    name: String, rows: [[String]], rowNumbers: [Int], notes: [String],
    formulas: [String: String], unsettled: [String: String] = [:],
    formulaKinds: [String: String] = [:]
  ) {
    self.name = name
    self.rows = rows
    self.rowNumbers = rowNumbers
    self.notes = notes
    self.formulas = formulas
    self.unsettled = unsettled
    self.formulaKinds = formulaKinds
  }
}
public enum XLSX {
  /// The A1 name of a zero-based column position in a worksheet row.
  static func cellName(column: Int, row: Int) -> String {
    var name = ""
    var index = column + 1
    while index > 0 {
      name = String(UnicodeScalar(UInt8(65 + (index - 1) % 26))) + name
      index = (index - 1) / 26
    }
    return name + String(row)
  }
  public static func read(_ url: URL, cancellation: Cancellation = .init()) throws
    -> [ImportedSheet]
  {
    try ExtractionWorker().readTable(url, format: .xlsx, cancellation: cancellation).sheets
  }
  static func readInProcess(_ url: URL, cancellation: Cancellation) throws -> [ImportedSheet] {
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
          notes: Array(sheet.notes).sorted(), formulas: sheet.formulas,
          unsettled: sheet.unsettled, formulaKinds: sheet.formulaKinds))
    }
    try StructuredResult(sheets: result).validate()
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
  /// A format such as 0000 shows 14 as 0014, but only 14 is saved.
  func padsZeros(_ style: Int, _ saved: String) -> Bool {
    guard styleIDs.indices.contains(style), let format = formats[styleIDs[style]] else {
      return false
    }
    let section = format.split(separator: ";", omittingEmptySubsequences: false).first ?? ""
    let plain = String(section).replacingOccurrences(
      of: "\"[^\"]*\"|\\\\.|\\[[^\\]]*\\]", with: "", options: .regularExpression)
    let zeros = plain.prefix { "0#,?".contains($0) }.filter { $0 == "0" }.count
    let digits = saved.prefix { $0 != "." }.filter(\.isNumber).drop { $0 == "0" }.count
    return zeros > 1 && digits < zeros
  }
}
private final class SheetXML: NSObject, XMLParserDelegate {
  let shared: [String], styles: StylesXML, epoch1904: Bool, cancellation: Cancellation
  var rows: [[String]] = [], rowNumbers: [Int] = [], notes = Set<String>(),
    formulas: [String: String] = [:], unsettled: [String: String] = [:],
    formulaKinds: [String: String] = [:], failure: Error?
  var current: [Int: String] = [:], number = 0, column = 0, reference = "", type = "", style = 0,
    value = "", formula = "", reading = "", count = 0
  var formulaType = "", formulaGroup = "", formulaRange = ""
  var sharedFormulas: [String: (text: String, column: Int, row: Int)] = [:]
  /// A short file can expand into far more text than it holds, so count what it expands to.
  var expandedFormulaBytes = 0, filledCells = 0
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
      column = 0
      let next = a["r"].map { Int($0) } ?? (number < 1_048_576 ? number + 1 : nil)
      guard let next, (1...1_048_576).contains(next) else {
        failure = SevraError(
          "xlsx_limit", "Worksheet row reference is outside the supported range.")
        parser.abortParsing()
        return
      }
      number = next
    }
    if name == "c" {
      reference = a["r"] ?? ""
      // A cell may omit its reference and follow the previous cell in the row.
      let following = column + 1
      column = 0
      for char in reference.uppercased().unicodeScalars where (65...90).contains(Int(char.value)) {
        // Check while parsing, before an adversarial reference can overflow Int.
        column = column * 26 + Int(char.value) - 64
        if column > 500 {
          failure = SevraError("xlsx_limit", "Worksheet exceeds 500 columns.")
          parser.abortParsing()
          return
        }
      }
      column = column > 0 ? column : following
      if reference.isEmpty, column <= 500 {
        reference = XLSX.cellName(column: column - 1, row: number)
      }
      type = a["t"] ?? ""
      style = Int(a["s"] ?? "") ?? 0
      value = ""
      formula = ""
      formulaType = ""
      formulaGroup = ""
      formulaRange = ""
      count += 1
      if column > 500 || rows.count >= 100_000 || count > 1_000_000 {
        failure = SevraError(
          "xlsx_limit", "Worksheet exceeds 500 columns, 100,000 rows or one million cells.")
        parser.abortParsing()
      }
    }
    if ["v", "t", "f"].contains(name) { reading = name }
    if name == "f" {
      formulaType = a["t"] ?? ""
      formulaGroup = a["si"] ?? ""
      formulaRange = a["ref"] ?? ""
    }
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
        unsettled[reference] = "error"
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
      } else if type.isEmpty || type == "n" {
        if styles.padsZeros(style, value) || value.lowercased().contains("e") {
          unsettled[reference] = "format"
        }
        let settled = Self.settled(value)
        if settled != value {
          text = settled
          notes.insert("Numbers use the 15 significant digits Excel shows.")
        }
      }
      if formulaType == "shared" {
        // Excel writes a filled formula once, on its first cell.
        if !formula.isEmpty {
          sharedFormulas[formulaGroup] = (formula, column - 1, number)
        } else if let first = sharedFormulas[formulaGroup] {
          expandedFormulaBytes += first.text.utf8.count
          if expandedFormulaBytes > 32_000_000 {
            failure = SevraError("xlsx_limit", "Shared formulas expand past the 32 MB import limit.")
            parser.abortParsing()
            return
          }
          formula = SheetFormula.shifted(
            first.text, columns: column - 1 - first.column, rows: number - first.row)
        } else {
          formulaKinds[reference] = "shared"
        }
      } else if formulaType == "array" || formulaType == "dataTable" {
        recordFilledCells()
      }
      if !formula.isEmpty {
        formulas[reference] = formula
        notes.insert("Formula cells start from the values Excel saved.")
        if value.isEmpty {
          text = "#NO_CACHED_VALUE"
          unsettled[reference] = "uncached"
        }
      }
      current[column - 1] = text
    }
    if name == "row", let last = current.keys.max() {
      rows.append((0...last).map { current[$0] ?? "" })
      rowNumbers.append(number)
    }
  }
  private func recordFilledCells() {
    let ends = formulaRange.split(separator: ":").compactMap { SheetFormulaToken.address(String($0)) }
    guard let first = ends.first, let last = ends.last, first.row <= last.row,
      first.column <= last.column
    else {
      formulaKinds[reference] = formulaType
      return
    }
    let size = (last.row - first.row + 1) * (last.column - first.column + 1)
    filledCells += size
    guard size <= SheetFormula.rangeLimit, filledCells <= 1_000_000 else {
      formulaKinds["*"] = formulaType
      return
    }
    for row in first.row...last.row {
      for column in first.column...last.column {
        formulaKinds[XLSX.cellName(column: column, row: row)] = formulaType
      }
    }
  }
  /// Excel writes binary doubles with up to 17 digits, so a cell showing 1.15 can
  /// save 1.1499999999999999. Fractions keep the 15 digits Excel shows.
  private static func settled(_ saved: String) -> String {
    guard saved.contains("."), !saved.lowercased().contains("e"),
      saved.filter(\.isNumber).drop(while: { $0 == "0" }).count > 15, let number = Double(saved)
    else { return saved }
    let rounded = String(format: "%.15g", number)
    return rounded.contains("e") ? saved : rounded
  }
}
extension Workbook {
  @discardableResult public func importXLSX(
    _ sourceID: String, cancellation: Cancellation = .init(), worker: ExtractionWorker = .init(),
    progress: (Int, Int) -> Void = { _, _ in }
  ) throws -> [Dataset] {
    try trackStructuredIntake(sourceID, cancellation: cancellation) {
      try importXLSXSheets(
        sourceID, cancellation: cancellation, worker: worker, progress: progress)
    }
  }
  private func importXLSXSheets(
    _ sourceID: String, cancellation: Cancellation, worker: ExtractionWorker,
    progress: (Int, Int) -> Void
  ) throws -> [Dataset] {
    let source = try item(sourceID)
    guard let asset = source.assetID else {
      throw SevraError("xlsx", "Workbook source has no asset.")
    }
    let sheets = try worker.readTable(
      assetURL(asset, verify: true, cancellation: cancellation), format: .xlsx,
      cancellation: cancellation
    ).sheets
    // Recheck linked/included original bytes after parsing and before publication.
    _ = try assetURL(asset, verify: true, cancellation: cancellation)
    var tables: [Dataset] = []
    var imported: [ImportedSheet] = []
    let total = sheets.reduce(0) { $0 + $1.rows.count }
    var finished = 0
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
          sourceID: evidence.id, cancellation: cancellation,
          progress: { done, _ in progress(finished + done, total) }))
      imported.append(sheet)
      finished += sheet.rows.count
    }
    try recordSheetFormulas(sourceID: sourceID, sheets: imported, tables: tables)
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
