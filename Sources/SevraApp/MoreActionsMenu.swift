import SwiftUI

/// An ellipsis already communicates a menu. Keep the native menu and keyboard
/// behavior, without adding a second disclosure glyph or shrinking its target.
struct MoreActionsMenu<Content: View>: View {
  let title: String
  let help: String
  @ViewBuilder let content: Content

  init(_ title: String, help: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.help = help ?? title
    self.content = content()
  }

  var body: some View {
    Menu {
      content
    } label: {
      Image(systemName: "ellipsis")
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .frame(width: 28, height: 28)
    .accessibilityLabel(title)
    .help(help)
  }
}
