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

/// A one-icon header action with the same target size as the actions menu beside it.
struct HeaderIconButton: View {
  @AppStorage(ReadingStyle.preference) private var textScale = 1.0
  let title: String
  let systemImage: String
  let action: () -> Void

  init(_ title: String, systemImage: String, action: @escaping () -> Void) {
    self.title = title
    self.systemImage = systemImage
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: systemImage).labelStyle(.iconOnly)
        .frame(
          width: 28 * ReadingStyle.scale(textScale), height: 28 * ReadingStyle.scale(textScale)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(title)
    .help(title)
  }
}
