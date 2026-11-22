import SwiftUI

/// Both panes share one geometry.
struct PaneHeader<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    HStack(spacing: 8) {
      content
    }.padding(.horizontal, 20).padding(.vertical, 12).frame(minHeight: 56)
      .controlSize(.regular)
  }
}
