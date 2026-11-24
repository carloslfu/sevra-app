import SevraCore
import SwiftUI

/// What was taken out of the workbook, newest first. History keeps each one, and Restore brings
/// it back as it was. An app or automation comes back turned off.
struct RemovedView: View {
  @ObservedObject var workspace: WorkspaceState
  @State private var entries: [Value] = []
  @State private var loaded = false
  @State private var failure: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        "Documents, tables, views, apps and saved definitions taken out of this workbook. Nothing here is erased: Restore brings it back as it was."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      if let failure { Text(failure).foregroundStyle(.red) }
      if !loaded {
        ProgressView("Reading what was removed")
      } else if entries.isEmpty {
        ContentUnavailableView(
          "Nothing removed", systemImage: "tray",
          description: Text("What you remove, here or in chat, waits here until you restore it."))
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(entries, id: \.["id"].text) { entry in
              RemovedRow(
                entry: entry, busy: workspace.busy,
                open: entry["type"] == .string("table")
                  ? { workspace.navigate(.table(entry["id"].text)) }
                  : entry["type"] == .string("item")
                    ? { workspace.navigate(.item(entry["id"].text)) } : nil,
                restore: { workspace.removeOrRestore(entry["id"].text, removing: false) })
              Divider()
            }
          }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(maxWidth: 760, alignment: .leading)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: workspace.revision) { await load() }
  }

  private func load() async {
    guard let book = workspace.workbook else { return }
    do {
      entries = try await Task.detached { try book.removedThings() }.value
      failure = nil
    } catch {
      failure = error.localizedDescription
    }
    loaded = true
  }
}

private struct RemovedRow: View {
  let entry: Value
  let busy: Bool
  let open: (() -> Void)?
  let restore: () -> Void

  private var kind: String {
    switch entry["type"].text {
    case "item": return entry["kind"].string == "document" ? "Document" : "Record"
    case "table": return "Table"
    case "view": return "View"
    case "app": return "App"
    case "tool": return "Saved tool"
    default: return (entry["kind"].string ?? "Definition").capitalized
    }
  }
  private var when: String? {
    guard let text = entry["removed"].string,
      let date = ISO8601DateFormatter().date(from: text)
    else { return nil }
    return date.formatted(date: .abbreviated, time: .shortened)
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(entry["title"].text).lineLimit(2)
        Text([kind, when.map { "removed " + $0 }].compactMap { $0 }.joined(separator: " · "))
          .font(.callout).foregroundStyle(.secondary)
      }
      .layoutPriority(1)
      Spacer(minLength: 12)
      if let open { Button("Open", action: open) }
      Button("Restore", action: restore).disabled(busy)
    }
    .padding(.vertical, 10)
    .accessibilityElement(children: .contain)
  }
}
