import SwiftUI

/// Both panes share one geometry, including when the conversation has threads.
struct PaneHeader<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    HStack(spacing: 8) {
      content
    }.padding(.horizontal, 20).frame(height: 56)
      .controlSize(.regular)
  }
}
