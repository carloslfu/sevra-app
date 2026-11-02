import AppKit

/// Preserve SwiftUI's delegate behavior while refusing close after an unsaved
/// document error. Forward every other optional AppKit delegate message.
@MainActor public final class DocumentCloseGuard: NSObject, NSWindowDelegate {
  private weak var previous: (any NSWindowDelegate)?
  private weak var window: NSWindow?
  private let flush: () -> Bool
  private let asyncFlush: (() async -> Bool)?
  private let closed: ((NSWindow) -> Void)?
  private var closing = false
  private var permitted = false
  public init(flush: @escaping () -> Bool) {
    self.flush = flush
    asyncFlush = nil
    closed = nil
  }
  /// `closed` runs as the window closes. SwiftUI can take the window's views down before a
  /// notification observer among them hears it, so the delegate is the reliable place.
  public init(asyncFlush: @escaping () async -> Bool, closed: ((NSWindow) -> Void)? = nil) {
    flush = { true }
    self.asyncFlush = asyncFlush
    self.closed = closed
  }
  public func attach(to window: NSWindow) {
    if self.window !== window {
      if self.window?.delegate === self { self.window?.delegate = previous }
      self.window = window
    }
    if window.delegate !== self {
      previous = window.delegate
      window.delegate = self
    }
  }
  public func windowShouldClose(_ sender: NSWindow) -> Bool {
    if let asyncFlush, !permitted {
      guard !closing else { return false }
      closing = true
      Task { [weak self, weak sender] in
        let saved = await asyncFlush()
        guard let self, let sender else { return }
        closing = false
        if saved {
          permitted = true
          sender.performClose(nil)
          permitted = false
        }
      }
      return false
    }
    guard flush() else { return false }
    return previous?.windowShouldClose?(sender) ?? true
  }
  public func windowWillClose(_ notification: Notification) {
    if let window = notification.object as? NSWindow { closed?(window) }
    previous?.windowWillClose?(notification)
  }
  public override func responds(to selector: Selector!) -> Bool {
    super.responds(to: selector) || previous?.responds(to: selector) == true
  }
  public override func forwardingTarget(for selector: Selector!) -> Any? {
    if previous?.responds(to: selector) == true { return previous }
    return super.forwardingTarget(for: selector)
  }
}
