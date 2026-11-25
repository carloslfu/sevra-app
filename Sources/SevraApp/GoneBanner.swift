import SevraCore
import SwiftUI

/// What every screen shows when the thing it shows left the workbook, however it left: a button,
/// a menu, chat, Undo or another window. It says what happened and, when it can, brings it back.
struct GoneBanner: View {
  let presence: Presence
  /// What it is, in words: "document", "view", "form".
  let noun: String
  @ObservedObject var workspace: WorkspaceState
  /// An older version is open: the current one may still be worth reading.
  var openCurrent: (() -> Void)? = nil

  static func message(_ presence: Presence, noun: String) -> String {
    switch presence.state {
    case "removed", "retired": return "This " + noun + " was removed from the workbook. History keeps it."
    case "archived": return "This " + noun + " was removed. Its data and history are kept."
    case "withdrawn": return "This " + noun + " was withdrawn. It no longer counts in the workbook."
    default: return "This " + noun + " is no longer in the workbook."
    }
  }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: presence.state == "withdrawn" ? "arrow.uturn.backward.circle" : "tray")
        .foregroundStyle(.secondary).accessibilityHidden(true)
      Text(Self.message(presence, noun: noun)).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      if let openCurrent { Button("Open current version", action: openCurrent) }
      if presence.restorable, let target = presence.target {
        Button("Restore") { workspace.removeOrRestore(target.id, removing: false) }
          .disabled(workspace.busy).help("Bring it back into the workbook as it was.")
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    .accessibilityElement(children: .contain)
  }
}

/// A route whose view, app or table is no longer listed: say why, instead of a blank pane.
struct GoneRouteView: View {
  let id: String
  let noun: String
  @ObservedObject var workspace: WorkspaceState
  @State private var presence: Presence?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let presence {
        GoneBanner(
          presence: presence.gone
            ? presence : Presence(state: "missing", target: nil, currentVersion: nil),
          noun: presence.target?.type ?? noun, workspace: workspace)
        Button("Go to Home") { workspace.navigate(.space("home")) }
      } else {
        ProgressView()
      }
      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(maxWidth: 760, alignment: .leading)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: id + ":" + String(workspace.revision)) {
      guard let book = workspace.workbook else { return }
      let found = await Task.detached { try? book.presence(id) }.value
      guard !Task.isCancelled else { return }
      presence = found ?? Presence(state: "missing", target: nil, currentVersion: nil)
    }
  }
}

/// Shows a definition's component, or the banner when that definition was removed. A view keeps
/// its place for it, so Restore puts it back where it was.
struct DefinitionPresenceGate<Content: View>: View {
  let binding: Value?
  let noun: String
  @ObservedObject var workspace: WorkspaceState
  @ViewBuilder let content: () -> Content
  @State private var presence: Presence?

  private var id: String? { binding?["logicalID"].string ?? binding?["versionID"].string }

  var body: some View {
    Group {
      if let presence, presence.gone {
        GoneBanner(presence: presence, noun: noun, workspace: workspace)
      } else {
        content()
      }
    }
    .task(id: (id ?? "") + ":" + String(workspace.revision)) {
      guard let book = workspace.workbook, let id else { return }
      let found = await Task.detached { try? book.presence(id) }.value
      guard !Task.isCancelled else { return }
      presence = found
    }
  }
}
