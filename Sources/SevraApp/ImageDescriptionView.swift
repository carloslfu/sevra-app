import SevraCore
import SevraTableUI
import SwiftUI

struct ImageDescriptionView: View {
  let item: Item
  let workbook: Workbook
  @State private var saved: Value?
  @State private var text = ""
  @State private var busy = false
  @State private var failure: String?
  @State private var notice: String?
  @State private var request = UUID()
  @State private var token = UUID().uuidString
  @State private var expanded = false

  var body: some View {
    DisclosureGroup("User description", isExpanded: $expanded) {
      VStack(alignment: .leading, spacing: 8) {
        Text(
          "Optional words you write about this image. Saved with this exact file version, separately from OCR and the original."
        )
        .foregroundStyle(.secondary)
        TextEditor(text: $text).readingFont(.body).frame(
          minHeight: 80, idealHeight: 120, maxHeight: 180
        )
        .accessibilityLabel("Description of " + item.title)
        .accessibilityHint("Optional, at most 8,000 UTF-8 bytes. Save explicitly.")
        .disabled(busy || saved == nil)
        .onChange(of: text) { _, _ in
          token = UUID().uuidString
          notice = nil
        }
        if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
        if let notice { Text(notice).textSelection(.enabled) }
        HStack {
          Button("Save description") { save() }
            .disabled(
              busy || saved == nil || text == saved?["body"].text || text.utf8.count > 8_000)
          Button("Reload saved description") { request = UUID() }.disabled(busy)
            .help("Replaces these unsaved words with the saved description.")
          if busy { ProgressView().controlSize(.small) }
        }
      }.padding(.top, 8)
    }.padding(12).announceStatus(failure ?? notice)
      .task(id: request) { await load() }
  }

  private func load() async {
    busy = true
    failure = nil
    defer { busy = false }
    let control = Cancellation()
    do {
      let result = try await withTaskCancellationHandler {
        try await Task.detached { try workbook.imageDescription(item.id, cancellation: control) }
          .value
      } onCancel: {
        control.cancel()
      }
      guard !Task.isCancelled else { return }
      saved = result
      text = result["body"].text
    } catch {
      guard !Task.isCancelled else { return }
      failure = error.localizedDescription
    }
  }

  private func save() {
    guard !busy, let saved, let revision = saved["revision"].int else { return }
    let input = text
    let previous = saved["id"].string
    let operation = token
    busy = true
    failure = nil
    notice = nil
    Task {
      defer { busy = false }
      do {
        let committed = try await Task.detached {
          try workbook.saveImageDescription(
            item.id, text: input, previousID: previous,
            expectedRevision: revision, token: operation)
        }.value
        // Do not discard the user's input if rereading after a successful save fails.
        notice = "Description saved for this file version."
        let loaded = try await Task.detached { try workbook.imageDescription(item.id) }.value
        guard loaded["id"].string == committed.id else {
          self.saved = nil
          failure =
            "Another description was saved meanwhile. Reload it before making further changes. Your words remain here."
          return
        }
        self.saved = loaded
      } catch {
        if notice != nil { self.saved = nil }
        failure = error.localizedDescription
      }
    }
  }
}
