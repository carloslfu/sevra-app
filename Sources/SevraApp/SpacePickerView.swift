import SevraCore
import SevraPreviewUI
import SwiftUI

struct SpacePickerView: View {
  @ObservedObject var state: WorkspaceState
  let dismiss: () -> Void
  @State private var search = ""
  @FocusState private var searchFocused: Bool
  private var sections: SpacePickerSections {
    SpacePickerSections(
      spaces: state.spaces, navigation: state.spaceNavigation.state, query: search)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      TextField("Find a space", text: $search).textFieldStyle(.roundedBorder)
        .focused($searchFocused)
        .onSubmit {
          let matches = sections.home + sections.pinned + sections.recent + sections.others
          if let first = matches.first { open(first) }
        }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
          rows(sections.home)
          section("Pinned spaces", sections.pinned)
          section("Recent spaces", sections.recent)
          section(search.isEmpty ? "Other spaces" : "Matching spaces", sections.others)
          if sections.isEmpty {
            Text("No spaces match “\(search)”.").foregroundStyle(.secondary).padding(.vertical, 12)
          }
        }
      }
      Divider()
      Button("Create a space…") {
        if state.prompt.isEmpty { state.prompt = "Create a space for " }
        state.composerFocusRequest = UUID()
        dismiss()
      }
    }.padding(16).frame(width: 320, height: min(400, 130 + CGFloat(state.spaces.count) * 60))
      .onAppear { searchFocused = true }
  }
  @ViewBuilder private func section(_ title: String, _ spaces: [Space]) -> some View {
    if !spaces.isEmpty {
      Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.top, 8)
      rows(spaces)
    }
  }
  private func rows(_ spaces: [Space]) -> some View {
    ForEach(spaces) { space in
      SpaceShortcutRow(space: space, state: state) { open(space) }
    }
  }
  private func open(_ space: Space) {
    state.navigate(.space(space.id))
    if state.route == .space(space.id) { dismiss() }
  }
}

struct SpaceShortcutRow: View {
  let space: Space
  @ObservedObject var state: WorkspaceState
  let open: () -> Void
  private var pinned: Bool { state.spaceNavigation.state.pinned.contains(space.id) }
  var body: some View {
    HStack(spacing: 10) {
      Button(action: open) {
        HStack(spacing: 10) {
          Image(systemName: space.id == "home" ? "house" : "rectangle.split.2x2")
            .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 2) {
            Text(space.title).lineLimit(2)
            if let captured = space.definition.pinnedAt {
              Text("Snapshot · " + DisplayText.date(captured)).font(.caption).foregroundStyle(
                .secondary)
            } else if space.id != "home" {
              Text("Live view").font(.caption).foregroundStyle(.secondary)
            }
          }
          Spacer(minLength: 0)
          if state.route == .space(space.id) {
            Image(systemName: "checkmark").font(.caption).accessibilityLabel("Current space")
          }
        }.contentShape(Rectangle()).padding(.vertical, 7)
      }.buttonStyle(.plain)
      if space.id != "home" {
        Button {
          state.spaceNavigation.pin(space.id, selected: !pinned)
        } label: {
          Image(systemName: pinned ? "pin.fill" : "pin")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel((pinned ? "Unpin " : "Pin ") + space.title)
        .help(
          pinned
            ? "Remove this shortcut from pinned spaces"
            : "Keep this space easy to find; its data stays unchanged"
        )
        .disabled(state.spaceNavigation.isSaving)
      }
    }
  }
}
