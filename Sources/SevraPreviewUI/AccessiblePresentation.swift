import Foundation
import SevraCore

public struct FormFieldPresentation {
  public let title: String
  public let path: [Value]
  public let issues: [String]
  public let accessibleTitle: String
  public let help: String
  public init(
    parameter: Value, label: String? = nil, help: String? = nil,
    context: String? = nil, issues: [Value] = [], path: [Value] = []
  ) {
    title = label ?? parameter["label"].text
    let resolvedPath = path.isEmpty ? [.string(parameter["id"].text)] : path
    self.path = resolvedPath
    self.issues = issues.filter { $0["path"].array == resolvedPath }.map { $0["message"].text }
    accessibleTitle = [
      context, title, parameter["required"] == .bool(true) ? "Required" : nil,
      parameter["unit"].string,
    ].compactMap { $0 }.joined(separator: ", ")
    var parts = [help].compactMap { $0 }.filter { !$0.isEmpty }
    if parameter["type"] == .string("date") {
      parts.append("Date in year-month-day format, YYYY-MM-DD.")
    }
    if parameter["min"] != .null { parts.append("Minimum: " + parameter["min"].text) }
    if parameter["max"] != .null { parts.append("Maximum: " + parameter["max"].text) }
    if let limit = parameter["maxEntries"].int { parts.append("Up to \(limit) lines.") }
    parts += self.issues.map { "Error: " + $0 }
    self.help = parts.joined(separator: " ")
  }
}

extension PreviewTableContent {
  public static func evidence(
    headings: [String], rows: [[Value]], rowIDs: [String], sources: [[Link]]
  ) -> Self {
    let hasSources = sources.contains { !$0.isEmpty }
    return .init(
      headings: headings + (hasSources ? ["Sources"] : []),
      rows: rows.enumerated().map { index, row in
        row.map { value in
          value == .null
            ? "Unknown"
            : value == .string("") ? "Empty" : StructuredPresentation.scalar(value) ?? value.text
        }
          + (hasSources
            ? [
              sources.indices.contains(index)
                ? sources[index].map(\.title).joined(separator: "; ") : "No individual source"
            ] : [])
      }, rowIDs: rowIDs, rowSources: sources, sourceColumn: hasSources ? headings.count : nil)
  }
  public static func source(_ id: String, title: String) -> Link? {
    var parts = URLComponents()
    parts.scheme = "sevra"
    parts.host = "item"
    parts.path = "/" + id
    guard !id.isEmpty, !id.contains("/"), let url = parts.url else { return nil }
    return .init(title: title, url: url)
  }
}

public struct ChartReadingPresentation {
  public struct Point: Identifiable {
    public let id: String
    public let label: String
    public let value: Double
  }
  public let xTitle: String
  public let yTitle: String
  public let points: [Point]
  public let summary: String
  public init(_ data: ComponentSnapshot, x: String?, y: String?, unitOverride: String? = nil) {
    xTitle = data.columns.first { $0.id == x }?.title ?? "Category"
    let yColumn = data.columns.first { $0.id == y }
    yTitle = (yColumn?.title ?? "Value") + ((unitOverride ?? yColumn?.unit).map { " " + $0 } ?? "")
    points = data.rows.compactMap { row in
      guard let value = Double(row.values[y ?? ""]?.text ?? ""), value.isFinite else { return nil }
      return Point(id: row.id, label: row.values[x ?? ""]?.text ?? "", value: value)
    }
    summary = "\(points.count) plotted rows of \(data.totalRows). " + yTitle
  }
}

/// Immutable cell actions. Native accessibility, keyboard and pointer routes share these decisions.
public struct PreviewCellActions {
  public struct Action: Equatable {
    public let title: String
    public let destination: URL?
    public let row: Int
  }
  private let snapshot: PreviewTableContent
  public let actions: [Action]
  public let singleSource: Bool
  public init(content: PreviewTableContent, row: Int, column: Int) {
    snapshot = content
    guard content.rows.indices.contains(row), content.rows[row].indices.contains(column),
      content.headings.indices.contains(column)
    else {
      actions = []
      singleSource = false
      return
    }
    let links = content.links(row: row, column: column)
    let context = ", row \(row + 1), " + content.plain(content.headings[column])
    singleSource = links.count == 1
    actions =
      links.map { .init(title: "Open " + $0.title + context, destination: $0.url, row: row) }
      + [.init(title: "Read full row \(row + 1)", destination: nil, row: row)]
  }
  @discardableResult public func perform(
    _ index: Int, current: PreviewTableContent,
    open: (URL) -> Void, inspect: (Int) -> Void
  ) -> Bool {
    guard current == snapshot, actions.indices.contains(index) else { return false }
    let action = actions[index]
    if let url = action.destination { open(url) } else { inspect(action.row) }
    return true
  }
  public var primaryIndex: Int? { actions.isEmpty ? nil : singleSource ? 0 : actions.count - 1 }
  public static func opensOnClick(markdown: Bool, clicks: Int, extendingSelection: Bool) -> Bool {
    !extendingSelection && (markdown || clicks >= 2)
  }
}
