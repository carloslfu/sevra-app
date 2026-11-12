import SevraCore
import SevraPreviewUI
import SwiftUI

/// All readonly business tables retain the same headers, exact values and source actions.
struct EvidenceTable: View {
  let title: String
  let headings: [String]
  let rows: [[Value]]
  let rowIDs: [String]
  let sources: [[PreviewTableContent.Link]]
  let open: (URL) -> Void

  var body: some View {
    let hasSources = sources.contains { !$0.isEmpty }
    ReadOnlyTableView(
      content: .init(
        headings: headings + (hasSources ? ["Sources"] : []),
        rows: rows.enumerated().map { index, row in
          row.map { value in
            value == .null
              ? "Unknown"
              : value == .string("")
                ? "Empty"
                : StructuredPresentation.scalar(value) ?? value.text
          }
            + (hasSources
              ? [
                sources.indices.contains(index)
                  ? sources[index].map(\.title).joined(separator: "; ") : "No individual source"
              ] : [])
        }, rowIDs: rowIDs, rowSources: sources,
        sourceColumn: hasSources ? headings.count : nil),
      label: title, open: open
    ).frame(minHeight: 180, idealHeight: 280, maxHeight: 320)
  }

  static func source(_ id: String, title: String) -> PreviewTableContent.Link? {
    var parts = URLComponents()
    parts.scheme = "sevra"
    parts.host = "item"
    parts.path = "/" + id
    guard !id.isEmpty, !id.contains("/"), let url = parts.url else { return nil }
    return .init(title: title, url: url)
  }
}
