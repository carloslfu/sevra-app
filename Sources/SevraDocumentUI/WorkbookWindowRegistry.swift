import AppKit

/// Which windows hold a workbook and which show the start page. The start page is only a way into a
/// workbook: once one is in front, it closes, and closing the last workbook brings it back.
@MainActor public enum WorkbookWindowRegistry {
  private static let owners = NSMapTable<NSString, NSWindow>.strongToWeakObjects()
  private static let starts = NSHashTable<NSWindow>.weakObjects()
  private static var startRequested: TimeInterval?
  /// Set while the app quits, so the windows closing then bring nothing back.
  public static var quitting = false

  /// One spelling per workbook, so one reached through a symlink, `/private`, `..` or other letter
  /// case is still the same open workbook. A path that does not exist is only tidied.
  nonisolated public static func canonical(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else {
      return URL(fileURLWithPath: path).standardizedFileURL.path
    }
    defer { free(resolved) }
    return String(cString: resolved)
  }

  public static func owner(of path: String) -> NSWindow? {
    owners.object(forKey: canonical(path) as NSString)
  }

  /// One window per workbook. False when another window has it, which then comes forward.
  public static func claim(_ path: String, by window: NSWindow) -> Bool {
    if let owner = owner(of: path), owner !== window {
      bringForward(owner)
      return false
    }
    starts.remove(window)
    owners.setObject(window, forKey: canonical(path) as NSString)
    return true
  }

  /// Called as a window closes or gives up its workbook.
  public static func release(_ window: NSWindow) {
    for case let path as NSString in owners.keyEnumerator().allObjects
    where owners.object(forKey: path) === window {
      owners.removeObject(forKey: path)
    }
    starts.remove(window)
  }

  /// Records whether the window shows the start page now.
  public static func showsStart(_ window: NSWindow, _ showing: Bool) {
    guard showing else {
      starts.remove(window)
      return
    }
    starts.add(window)
    startRequested = nil
  }

  public static var start: NSWindow? { starts.allObjects.first }

  /// A workbook is in front, so no start page is needed behind it.
  public static func closeStarts(except kept: NSWindow? = nil) {
    for window in starts.allObjects where window !== kept {
      starts.remove(window)
      window.close()
    }
  }

  /// Shows a workbook that is already open, from a minimized window too.
  public static func bringForward(_ window: NSWindow) {
    if window.isMiniaturized { window.deminiaturize(nil) }
    window.makeKeyAndOrderFront(nil)
    closeStarts(except: window)
  }

  /// Whether a workbook or start page window other than `window` is still open.
  public static func hasWindows(besides window: NSWindow? = nil) -> Bool {
    owners.objectEnumerator()?.allObjects.contains { ($0 as AnyObject) !== window } == true
      || starts.allObjects.contains { $0 !== window }
  }

  /// True once when the last window has closed and a start page should open. A request counts for
  /// a few seconds, so windows closing together open one start page between them.
  public static func shouldOpenStart(now: TimeInterval = ProcessInfo.processInfo.systemUptime)
    -> Bool
  {
    guard !quitting, !hasWindows() else { return false }
    if let startRequested, now - startRequested < 3 { return false }
    startRequested = now
    return true
  }
}
