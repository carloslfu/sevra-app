import AppKit
import SwiftUI

/// SwiftUI `Text` measures its whole string on the main thread: 64 KB took 0.75 s, 200 KB 6.5 s
/// and 1 MB over a minute. These views keep selection and copy, and use the same label color on
/// the window background, so long text looks the same and cannot freeze the app.
private func prepareReadingView(_ view: NSTextView) {
  view.isEditable = false
  view.isSelectable = true
  view.isRichText = false
  view.allowsUndo = false
  view.usesFontPanel = false
  view.drawsBackground = false
  view.textColor = .labelColor
}

/// A text file: one scrolling view that lays out only what is on screen.
public struct TextFileView: NSViewRepresentable {
  public let text: String
  public init(text: String) { self.text = text }

  public final class Coordinator { fileprivate var shown: String? }
  public func makeCoordinator() -> Coordinator { Coordinator() }

  public func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    let view = NSTextView(usingTextLayoutManager: false)
    prepareReadingView(view)
    view.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    view.textContainerInset = NSSize(width: 20, height: 20)
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    view.autoresizingMask = [.width]
    view.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    view.textContainer?.widthTracksTextView = true
    view.layoutManager?.allowsNonContiguousLayout = true
    scroll.documentView = view
    return scroll
  }

  public func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard context.coordinator.shown != text, let view = scroll.documentView as? NSTextView
    else { return }
    context.coordinator.shown = text
    view.string = text
    view.scroll(.zero)
  }
}

/// A long document body inside a page that scrolls. The page needs its whole height, so this lays
/// out the whole text, once per width, at about 0.2 s per MB.
public struct LongReadingText: NSViewRepresentable {
  /// Up to here `Text` stays quick, about 0.1 s, and keeps its native link handling.
  public static let thresholdBytes = 16_000
  public let identity: String
  public let text: () -> NSAttributedString
  public let open: (URL) -> Void
  public init(
    identity: String, text: @escaping () -> NSAttributedString,
    open: @escaping (URL) -> Void = { _ in }
  ) {
    self.identity = identity
    self.text = text
    self.open = open
  }

  public final class Coordinator: NSObject, NSTextViewDelegate {
    fileprivate var open: (URL) -> Void = { _ in }
    fileprivate var shown: String?
    fileprivate var width: CGFloat = -1
    fileprivate var height: CGFloat = 0
    public func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool
    {
      guard let url = link as? URL else { return false }
      open(url)
      return true
    }
  }
  public func makeCoordinator() -> Coordinator { Coordinator() }

  public func makeNSView(context: Context) -> NSTextView {
    let view = NSTextView(usingTextLayoutManager: false)
    prepareReadingView(view)
    view.isRichText = true
    view.isVerticallyResizable = false
    view.textContainerInset = .zero
    view.textContainer?.lineFragmentPadding = 0
    view.textContainer?.widthTracksTextView = false
    view.linkTextAttributes = [
      .cursor: NSCursor.pointingHand, .underlineStyle: NSUnderlineStyle.single.rawValue,
    ]
    view.delegate = context.coordinator
    return view
  }

  public func updateNSView(_ view: NSTextView, context: Context) {
    context.coordinator.open = open
    guard context.coordinator.shown != identity else { return }
    context.coordinator.shown = identity
    context.coordinator.width = -1
    view.textStorage?.setAttributedString(text())
  }

  public func sizeThatFits(
    _ proposal: ProposedViewSize, nsView view: NSTextView, context: Context
  ) -> CGSize? {
    let coordinator = context.coordinator
    let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? view.bounds.width
    let width = offered > 0 ? offered : 480
    if width != coordinator.width, let manager = view.layoutManager,
      let container = view.textContainer
    {
      container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
      manager.ensureLayout(for: container)
      coordinator.width = width
      coordinator.height = ceil(manager.usedRect(for: container).height)
    }
    return CGSize(width: width, height: coordinator.height)
  }

  /// Body text with the same font and color as the `Text` it stands in for.
  public static func plain(_ text: String) -> NSAttributedString {
    NSAttributedString(
      string: text,
      attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        .foregroundColor: NSColor.labelColor,
      ])
  }
}
