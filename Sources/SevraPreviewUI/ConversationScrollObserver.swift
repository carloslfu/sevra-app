import AppKit
import SevraCore
import SwiftUI

public struct ConversationRowFrames: PreferenceKey {
  public static var defaultValue: [String: CGRect] = [:]
  public static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

/// Observes the native clip view without intercepting scrolling or keyboard
/// input. A stable message plus an intra-message fraction survives width changes.
public struct ConversationScrollObserver: NSViewRepresentable {
  public var frames: [String: CGRect]
  public var position: ConversationReadingPosition
  public var request: UUID
  public var canFollowLatest: Bool
  public var changed: (ConversationReadingPosition) -> Void
  public init(
    frames: [String: CGRect], position: ConversationReadingPosition, request: UUID,
    canFollowLatest: Bool, changed: @escaping (ConversationReadingPosition) -> Void
  ) {
    self.frames = frames
    self.position = position
    self.request = request
    self.canFollowLatest = canFollowLatest
    self.changed = changed
  }
  public func makeNSView(context: Context) -> ObserverView { ObserverView() }
  public func updateNSView(_ view: ObserverView, context: Context) {
    view.configuration = self
    view.schedule()
  }
  public static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.detach() }

  public final class ObserverView: NSView {
    public override var isFlipped: Bool { true }
    fileprivate var configuration: ConversationScrollObserver?
    private var token: NSObjectProtocol?
    private weak var scroll: NSScrollView?
    private var applied: UUID?
    private var previousFrames: [String: CGRect] = [:]
    private var scheduled = false
    private var restoring = false
    public override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      schedule()
    }
    fileprivate func schedule() {
      guard !scheduled else { return }
      scheduled = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.scheduled = false
        self.update()
      }
    }
    fileprivate func detach() {
      if let token { NotificationCenter.default.removeObserver(token) }
      token = nil
      scroll = nil
      configuration = nil
    }
    private func update() {
      guard let config = configuration, let enclosing = enclosingScrollView,
        let document = enclosing.documentView
      else { return }
      if scroll !== enclosing {
        if let token { NotificationCenter.default.removeObserver(token) }
        scroll = enclosing
        enclosing.contentView.postsBoundsChangedNotifications = true
        token = NotificationCenter.default.addObserver(
          forName: NSView.boundsDidChangeNotification,
          object: enclosing.contentView, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.report() }
        }
      }
      guard !config.frames.isEmpty else { return }
      let layoutChanged = previousFrames != config.frames
      guard applied != config.request || layoutChanged else { return }
      let clip = enclosing.contentView
      let y: CGFloat
      if let id = config.position.message {
        guard let row = config.frames[id] else { return }
        y =
          convert(NSPoint(x: 0, y: row.minY + row.height * config.position.fraction), to: document)
          .y
      } else {
        y = document.bounds.height - clip.bounds.height
      }
      restoring = true
      clip.scroll(
        to: NSPoint(
          x: clip.bounds.minX,
          y: min(max(0, y), max(0, document.bounds.height - clip.bounds.height))))
      enclosing.reflectScrolledClipView(clip)
      restoring = false
      applied = config.request
      previousFrames = config.frames
    }
    private func report() {
      guard !restoring, let config = configuration, applied == config.request,
        let scroll, let document = scroll.documentView
      else { return }
      let clip = scroll.contentView
      if config.canFollowLatest && document.bounds.height - clip.bounds.maxY < 8 {
        config.changed(.init())
        return
      }
      let top = convert(clip.bounds.origin, from: document).y
      let ordered = config.frames.sorted { $0.value.minY < $1.value.minY }
      guard let row = ordered.first(where: { $0.value.maxY > top }) ?? ordered.last else { return }
      let fraction = min(1, max(0, (top - row.value.minY) / max(1, row.value.height)))
      config.changed(.init(message: row.key, fraction: fraction))
    }
    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
  }
}
