import AppKit
import SevraCore

/// One copied range, with interoperable presentations and a typed local round trip.
/// No formulas, row identities or workbook authority are transferred.
public struct TableClipboard {
  public static let maximumTextBytes = 4_000_000
  public static let valuesType = NSPasteboard.PasteboardType("com.sevra.workbooks.table-values")
  public let cells: [[Value]]
  public let text: String
  public let html: String
  private let typed: Data

  private struct Payload: Codable {
    let version: Int
    let text: String
    let cells: [[Value]]
  }

  public init(cells: [[Value]]) throws {
    try Self.validate(cells)
    let strings = cells.map { $0.map(\.text) }
    let text = strings.map { row in
      row.map { value in
        value.isEmpty || value.contains("\t") || value.contains("\n")
          || value.contains("\r") || value.contains("\"")
          ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
      }.joined(separator: "\t")
    }.joined(separator: "\n")
    try require(
      text.utf8.count <= Self.maximumTextBytes, "copy_limit",
      "Copy up to 4 MB at a time. Select fewer rows or export the table as CSV.")
    self.cells = cells
    self.text = text
    var widths = [Int](repeating: 80, count: strings.map(\.count).max() ?? 0)
    for row in strings {
      for (column, value) in row.enumerated() {
        let longest = value.split(whereSeparator: \.isNewline).map(\.count).max() ?? 0
        widths[column] = max(widths[column], min(320, longest * 8 + 16))
      }
    }
    html =
      "<meta charset=\"utf-8\"><table border=\"1\" cellpadding=\"6\" cellspacing=\"0\" style=\"border-collapse:collapse\"><tbody>"
      + strings.map { row in
        "<tr>"
          + row.enumerated().map { column, value in
            "<td width=\"\(widths[column])\" style=\"white-space:pre-wrap;border:1px solid #b8b8b8;padding:6px\">"
              + Self.escape(value) + "</td>"
          }
          .joined() + "</tr>"
      }.joined() + "</tbody></table>"
    typed = try JSONEncoder().encode(Payload(version: 1, text: text, cells: cells))
  }

  public init(page: TablePage, selection: Set<String>, headings: Bool = false) throws {
    var cells = page.rows.indices.filter { selection.contains(page.rows[$0].logicalID) }.map { n in
      page.dataset.columns.map { page.values[n][$0.id] ?? .null }
    }
    try require(!cells.isEmpty, "copy_selection", "Select rows to copy.")
    if headings { cells.insert(page.dataset.columns.map { .string($0.title) }, at: 0) }
    try self.init(cells: cells)
  }

  /// Construct and validate everything before replacing the user's clipboard.
  @MainActor public func write(to pasteboard: NSPasteboard = .general) throws {
    let item = NSPasteboardItem()
    item.setString(text, forType: .string)
    item.setString(text, forType: .tabularText)
    item.setString(html, forType: .html)
    item.setData(typed, forType: Self.valuesType)
    pasteboard.clearContents()
    try require(
      pasteboard.writeObjects([item]), "clipboard", "Could not copy these rows. Try again.")
  }

  @MainActor public static func read(from pasteboard: NSPasteboard = .general) throws -> [[Value]] {
    let text = pasteboard.string(forType: .tabularText) ?? pasteboard.string(forType: .string)
    guard let text else {
      throw SevraError("paste_text", "Copy cells or tab-separated text before pasting.")
    }
    try require(
      text.utf8.count <= maximumTextBytes, "paste_limit", "Paste at most 4 MB at a time.")
    if let data = pasteboard.data(forType: valuesType) {
      try require(data.count <= 32_000_000, "paste_limit", "The copied range is too large.")
      let payload = try JSONDecoder().decode(Payload.self, from: data)
      try require(
        payload.version == 1 && payload.text == text, "paste_format",
        "This copied range could not be read. Copy it again before pasting.")
      try require(
        try TableClipboard(cells: payload.cells).text == text, "paste_format",
        "This copied range does not match its text. Copy it again before pasting.")
      return payload.cells
    }
    // Ordinary text is never guessed to be comma-separated. A comma can be a
    // decimal separator or part of one cell. CSV has an explicit import path.
    let cells = try CSV.parse(text, delimiter: "\t").map { row in
      row.map { $0.isEmpty ? Value.null : .string($0) }
    }
    try validate(cells)
    return cells
  }

  public static func edits(
    cells: [[Value]], page: TablePage, selection: Set<String>, column: Int
  ) throws -> [RowEdit] {
    try validate(cells)
    try require(!page.dataset.archived, "archived_table", "Restore this table before editing.")
    let indexes = page.rows.indices.filter { selection.contains(page.rows[$0].logicalID) }
    guard let start = indexes.first else {
      throw SevraError("paste_selection", "Select the row and column where the paste should start.")
    }
    try require(
      indexes == Array(start..<(start + indexes.count)), "paste_selection",
      "Select one row or consecutive rows before pasting. Separate selections are kept unchanged.")
    try require(
      start + cells.count <= page.rows.count, "paste_range",
      "The paste exceeds this page of rows. Use Add files to include a larger table.")
    var edits: [RowEdit] = []
    for (r, values) in cells.enumerated() {
      try require(
        column >= 0 && column + values.count <= page.dataset.columns.count, "paste_range",
        "The paste exceeds the table columns.")
      var data = page.rows[start + r].data.object
      for (c, value) in values.enumerated() {
        let target = page.dataset.columns[column + c]
        try require(
          target.formula == nil, "calculated_cell",
          "This paste includes a calculated column. Select an editable column or paste fewer columns."
        )
        data[target.id] = value
      }
      edits.append(.init(id: page.rows[start + r].id, values: data))
    }
    return edits
  }

  private static func validate(_ cells: [[Value]]) throws {
    try require(
      !cells.isEmpty && cells.count <= 100_000
        && cells.allSatisfy { !$0.isEmpty && $0.count <= 500 }
        && cells.reduce(0, { $0 + $1.count }) <= 100_000,
      "paste_range", "Copy a nonempty range of up to 100,000 cells.")
    var bytes = 0
    for row in cells {
      for cell in row {
        bytes += cell.text.utf8.count + 1
        try require(bytes <= maximumTextBytes, "paste_limit", "Copy or paste up to 4 MB at a time.")
      }
    }
  }
  private static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(of: "\n", with: "<br>")
  }
}

public struct TableSelectionPresentation {
  public let label: String
  public let context: String
  public init(page: TablePage, selected: [Item], column: Int) {
    let ids = Set(selected.map(\.logicalID))
    let indexes = page.rows.indices.filter { ids.contains(page.rows[$0].logicalID) }
    guard let first = indexes.first else {
      label = ""
      context = ""
      return
    }
    let prefix = String(page.dataset.title.prefix(160))
    let field = page.dataset.columns.indices.contains(column) ? page.dataset.columns[column] : nil
    if indexes.count > 1 {
      label = "\(prefix), \(indexes.count) selected rows on this page"
      context =
        label + ". Read these exact row versions for values: "
        + indexes.map { page.rows[$0].id }.joined(separator: ", ")
    } else {
      let value = field.flatMap { page.values[first][$0.id] }
      label =
        "\(prefix), row \(page.offset + first + 1)"
        + (field.map { " · " + String($0.title.prefix(80)) + ": " } ?? "")
        + (value.map {
          $0 == .null ? "Unknown" : $0.text.isEmpty ? "Empty" : String($0.text.prefix(160))
        }
          ?? "")
      context = label + ". Exact row version: " + page.rows[first].id
    }
  }
}
