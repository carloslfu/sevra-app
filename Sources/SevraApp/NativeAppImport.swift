import AppKit
import SevraCore
import SwiftUI

extension WorkspaceState {
  func importNativeApp(replacing space: Space? = nil) {
    guard let book = workbook else { return }
    let panel = NSOpenPanel()
    panel.title = space == nil ? "Add a native app" : "Update native app"
    panel.allowedContentTypes = [.json, .data]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    Task {
      do {
        let saved = try await Task.detached(priority: .userInitiated) {
          let package = try NativeAppPackage.load(from: url)
          return try book.installNativeApp(
            package, spaceID: space?.id ?? identifier(), expectedVersion: space?.version)
        }.value
        guard workbook?.url == book.url else { return }
        refresh()
        navigate(.space(saved.id))
      } catch {
        let alert = NSAlert()
        alert.messageText = "Cannot add app"
        alert.informativeText = error.localizedDescription
        alert.runModal()
      }
    }
  }
}

struct NativeAppHistoryView: View {
  let space: Space
  @ObservedObject var state: WorkspaceState
  @Environment(\.dismiss) private var dismiss
  @State private var revisions: [SpaceRevision] = []
  @State private var failure: String?
  @State private var loading = false
  @State private var hasMore = true
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("App history").font(.title2)
      Text(
        "Restoring code creates a new app version. Business records stay as they are, and you review access again before it runs."
      )
      if let failure { Text(failure).foregroundStyle(.red) }
      List(revisions) { revision in
        HStack {
          Text("Version \(revision.version) · \(revision.title)")
          Spacer()
          Button("Restore") { restore(revision) }.disabled(revision.version == space.version)
        }
      }
      HStack {
        if hasMore {
          Button(revisions.isEmpty ? "Load history" : "Earlier versions") {
            Task { await loadMore() }
          }
          .disabled(loading)
        }
        if loading { ProgressView().controlSize(.small) }
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
    }.padding().frame(width: 540, height: 390)
      .task { await loadMore() }
  }
  private func loadMore() async {
    guard !loading, hasMore, let book = state.workbook else { return }
    loading = true
    defer { loading = false }
    let before = revisions.last?.version
    do {
      let page = try await Task.detached {
        try book.spaceHistory(space.id, before: before, limit: 50)
      }.value
      guard state.workbook?.url == book.url else { return }
      revisions.append(contentsOf: page)
      hasMore = page.count == 50
      failure = nil
    } catch { failure = error.localizedDescription }
  }
  private func restore(_ revision: SpaceRevision) {
    guard let book = state.workbook else { return }
    Task {
      do {
        _ = try await Task.detached {
          try book.restoreSpace(space.id, version: revision.version, expectedVersion: space.version)
        }.value
        state.refresh()
        dismiss()
      } catch { failure = error.localizedDescription }
    }
  }
}
