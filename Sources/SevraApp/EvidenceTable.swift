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
    ReadOnlyTableView(
      content: .evidence(headings: headings, rows: rows, rowIDs: rowIDs, sources: sources),
      label: title, open: open
    ).frame(minHeight: 180, idealHeight: 280, maxHeight: 320)
  }

  static func source(_ id: String, title: String) -> PreviewTableContent.Link? {
    PreviewTableContent.source(id, title: title)
  }
}
