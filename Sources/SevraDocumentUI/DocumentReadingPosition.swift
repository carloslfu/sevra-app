import AppKit
import SwiftUI

public struct DocumentReadingPosition: Equatable, Sendable {
  public let offset: Double
  public let scrollable: Double
  public let width: Double
  public init(offset: Double = 0, scrollable: Double = 0, width: Double = 0) {
    self.scrollable = scrollable.isFinite ? max(0, scrollable) : 0
    self.offset = offset.isFinite ? min(max(0, offset), self.scrollable) : 0
    self.width = width.isFinite ? max(0, width) : 0
  }
  public func restoredOffset(width: Double, scrollable: Double) -> Double {
    guard width.isFinite, scrollable.isFinite, scrollable > 0 else { return 0 }
    let y =
      abs(width - self.width) < 1 && abs(scrollable - self.scrollable) < 1
      ? offset : (self.scrollable > 0 ? offset / self.scrollable * scrollable : 0)
    return min(max(0, y), scrollable)
  }
}

/// Observe the native clip view. Back restores the same geometry exactly and a
/// proportional position after reflow; no keystrokes or scroll events are consumed.
public struct DocumentScrollObserver: NSViewRepresentable {
  public let position: DocumentReadingPosition
  public let changed: (DocumentReadingPosition) -> Void
  public init(
    position: DocumentReadingPosition, changed: @escaping (DocumentReadingPosition) -> Void
  ) {
    self.position = position
    self.changed = changed
  }
  public func makeNSView(context: Context) -> Observer { Observer() }
  public func updateNSView(_ view: Observer, context: Context) {
    view.configuration = self
    view.schedule()
  }
  public static func dismantleNSView(_ view: Observer, coordinator: ()) { view.detach() }
  public final class Observer: NSView {
    fileprivate var configuration: DocumentScrollObserver? {
      didSet {
        // A new caller position is deliberate navigation. Ordinary layout
        // updates may still carry the old value while its callback is pending.
        if oldValue?.position != configuration?.position {
          retainedPosition = configuration?.position
          applied = false
        }
      }
    }
    private var retainedPosition: DocumentReadingPosition?
    private weak var scroll: NSScrollView?
    private var token: NSObjectProtocol?
    private var scheduled = false
    private var applied = false
    private var geometry = CGSize.zero
    private var restoring = false
    public override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      schedule()
    }
    public override func layout() {
      super.layout()
      schedule()
    }
    fileprivate func schedule() {
      guard !scheduled else { return }
      scheduled = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.scheduled = false
        self.restore()
      }
    }
    fileprivate func detach() {
      if let token { NotificationCenter.default.removeObserver(token) }
      token = nil
      scroll = nil
      configuration = nil
    }
    private func restore() {
      guard let configuration, let enclosing = enclosingScrollView,
        let document = enclosing.documentView
      else { return }
      if scroll !== enclosing {
        if let token { NotificationCenter.default.removeObserver(token) }
        scroll = enclosing
        applied = false
        enclosing.contentView.postsBoundsChangedNotifications = true
        token = NotificationCenter.default.addObserver(
          forName: NSView.boundsDidChangeNotification,
          object: enclosing.contentView, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.report() }
        }
      }
      let clip = enclosing.contentView
      let height = max(0, document.bounds.height - clip.bounds.height)
      let currentGeometry = CGSize(width: clip.bounds.width, height: height)
      guard !applied || geometry != currentGeometry else { return }
      let position = retainedPosition ?? configuration.position
      guard height > 0 || position.offset == 0 else { return }
      restoring = true
      let y = position.restoredOffset(width: clip.bounds.width, scrollable: height)
      clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
      enclosing.reflectScrolledClipView(clip)
      restoring = false
      applied = true
      geometry = currentGeometry
      retainedPosition = .init(offset: y, scrollable: height, width: clip.bounds.width)
    }
    private func report() {
      guard !restoring, applied, let configuration, let scroll, let document = scroll.documentView
      else { return }
      let currentGeometry = CGSize(
        width: scroll.contentView.bounds.width,
        height: max(0, document.bounds.height - scroll.contentView.bounds.height))
      guard currentGeometry == geometry else {
        schedule()
        return
      }
      let position = DocumentReadingPosition(
        offset: scroll.contentView.bounds.minY,
        scrollable: currentGeometry.height, width: currentGeometry.width)
      retainedPosition = position
      configuration.changed(position)
    }
    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
  }
}
