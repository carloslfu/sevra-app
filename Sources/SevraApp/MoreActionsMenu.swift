import SevraTableUI
import SwiftUI

/// An ellipsis already communicates a menu. Keep the native menu and keyboard
/// behavior, without adding a second disclosure glyph or shrinking its target.
struct MoreActionsMenu<Content: View>: View {
  @AppStorage(ReadingStyle.preference) private var textScale = 1.0
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
      Label(title, systemImage: "ellipsis").labelStyle(.iconOnly)
        .frame(
          width: 28 * ReadingStyle.scale(textScale), height: 28 * ReadingStyle.scale(textScale)
        )
        .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .frame(width: 28 * ReadingStyle.scale(textScale), height: 28 * ReadingStyle.scale(textScale))
    .accessibilityLabel(title)
    .help(help)
  }
}
