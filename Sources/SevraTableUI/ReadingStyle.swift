import AppKit
import SwiftUI

/// App-local reading size. It never changes a macOS accessibility preference.
public enum ReadingStyle {
  public static let preference = "readingTextScale"
  public static func scale(_ value: Double) -> CGFloat {
    value.isFinite ? CGFloat(min(2, max(1, value))) : 1
  }
  public static func size(_ style: Font.TextStyle) -> CGFloat {
    let native: NSFont.TextStyle
    switch style {
    case .largeTitle: native = .largeTitle
    case .title: native = .title1
    case .title2: native = .title2
    case .title3: native = .title3
    case .headline: native = .headline
    case .subheadline: native = .subheadline
    case .callout: native = .callout
    case .footnote: native = .footnote
    case .caption: native = .caption1
    case .caption2: native = .caption2
    default: native = .body
    }
    return NSFont.preferredFont(forTextStyle: native, options: [:]).pointSize
  }
}

private struct ReadingFont: ViewModifier {
  let size: CGFloat
  let weight: Font.Weight
  let design: Font.Design
  @AppStorage(ReadingStyle.preference) private var scale = 1.0
  func body(content: Content) -> some View {
    content.font(.system(size: size * ReadingStyle.scale(scale), weight: weight, design: design))
  }
}

extension View {
  public func readingFont(
    _ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design = .default
  ) -> some View {
    modifier(
      ReadingFont(
        size: ReadingStyle.size(style),
        weight: weight ?? (style == .headline ? .semibold : .regular),
        design: design))
  }
  public func readingFont(
    size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default
  )
    -> some View
  {
    modifier(ReadingFont(size: size, weight: weight, design: design))
  }

  /// Only a changed, nonempty terminal status is announced, in its own active window.
  /// Initial display, background refresh, timers and token streams do not speak.
  public func announceStatus(_ message: String?) -> some View {
    background(
      StatusAnnouncement(message: message).frame(width: 0, height: 0)
        .accessibilityHidden(true))
  }
}

private struct StatusAnnouncement: NSViewRepresentable {
  let message: String?
  final class Coordinator {
    var initialized = false
    var generation = 0
    var message: String?
  }
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> NSView { NSView() }
  func updateNSView(_ view: NSView, context: Context) {
    let owner = context.coordinator
    let changed = owner.initialized && owner.message != message
    if owner.message != message { owner.generation += 1 }
    let generation = owner.generation
    owner.initialized = true
    owner.message = message
    guard changed, let message, !message.isEmpty else { return }
    DispatchQueue.main.async { [weak view, weak owner] in
      guard owner?.generation == generation, owner?.message == message, let window = view?.window,
        window.isKeyWindow,
        NSApp.isActive
      else { return }
      NSAccessibility.post(
        element: NSApp!, notification: .announcementRequested,
        userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.low.rawValue])
    }
  }
}
