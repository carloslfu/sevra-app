import SevraCore
import SevraPreviewUI
import SevraTableUI
import SwiftUI

struct ExtractedTextView: View {
  let item: Item
  let workbook: Workbook
  let openOriginal: (String?) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var page: Value?
  @State private var offset = 0
  @State private var revision: Int?
  @State private var failure: String?
  @State private var loading = false
  @State private var request = UUID()

  @ViewBuilder private var pageActions: some View {
    Button("Previous text page") {
      offset -= 8
      request = UUID()
    }.disabled(offset == 0 || loading || failure != nil)
    Button("Next text page") {
      offset += 8
      request = UUID()
    }
    .disabled(page?["hasMore"] != .bool(true) || loading || failure != nil)
    Button("Reload text") {
      offset = 0
      revision = nil
      page = nil
      request = UUID()
    }.disabled(loading)
    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Extracted text: " + item.title).readingFont(.title2).accessibilityAddTraits(.isHeader)
      Text(
        "Derived text may contain recognition errors. Reading order and non-text image content may be missing. The original remains authoritative."
      )
      .foregroundStyle(.secondary)
      if let page {
        let status = page["extraction"]
        Text(status["detail"].text).textSelection(.enabled)
        if status["state"].text != "ready" {
          Text(
            "Extraction is " + status["state"].text
              + ". Text may be partial or retained from an earlier attempt.")
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            ForEach(page["chunks"].array, id: \.text) { chunk in
              VStack(alignment: .leading, spacing: 6) {
                Text(DisplayText.location(chunk["locator"].text) ?? "Extracted passage")
                  .readingFont(.headline).accessibilityAddTraits(.isHeader)
                Text(
                  chunk["body"].text.isEmpty
                    ? "No readable text in this passage." : chunk["body"].text
                )
                .textSelection(.enabled)
                if chunk["truncated"].int == 1 {
                  Text(
                    "This unusually long passage is shortened to 4,000 characters. Open the original for the remainder."
                  )
                  .readingFont(.caption).foregroundStyle(.secondary)
                }
                Button("Show this passage in the original") {
                  openOriginal(chunk["locator"].string)
                  dismiss()
                }
              }.accessibilityElement(children: .contain)
            }
            if page["chunks"].array.isEmpty {
              Text("No extracted text is available for this file.")
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        Text(
          "Text page \((page["offset"].int ?? 0) / 8 + 1). "
            + (page["hasMore"] == .bool(true)
              ? "More indexed text is available."
              : "End of indexed text. This does not prove the entire original was extracted.")
            + " Adjacent passages can overlap."
        ).readingFont(.caption).foregroundStyle(.secondary)
        DisclosureGroup("Reading identity") {
          Text("File version: " + item.id).textSelection(.enabled)
          Text("Asset SHA-256: " + page["assetHash"].text).textSelection(.enabled)
          Text("Workbook revision: " + page["revision"].text).textSelection(.enabled)
          Text("Extraction: " + (page["extractionID"].string ?? "No retained extraction identity"))
            .textSelection(.enabled)
        }.readingFont(.caption)
      }
      if loading { ProgressView("Reading indexed text") }
      if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
      ViewThatFits(in: .horizontal) {
        HStack { pageActions }
        VStack(alignment: .leading, spacing: 8) { pageActions }
      }
    }.padding(20).readingFont(.body)
      .frame(minWidth: 420, idealWidth: 680, minHeight: 380, idealHeight: 640)
      .announceStatus(failure)
      .task(id: request) {
        let control = Cancellation()
        let position = offset
        let expected = revision
        loading = true
        failure = nil
        page = nil
        defer { loading = false }
        do {
          let loaded = try await withTaskCancellationHandler {
            try await Task.detached {
              try workbook.extractedTextPage(
                item.id, offset: position, expectedRevision: expected, cancellation: control)
            }.value
          } onCancel: {
            control.cancel()
          }
          guard !Task.isCancelled else { return }
          page = loaded
          revision = loaded["revision"].int
        } catch {
          guard !Task.isCancelled else { return }
          // Do not leave a previous page under the newly requested page number.
          page = nil
          failure = error.localizedDescription
        }
      }
  }
}
