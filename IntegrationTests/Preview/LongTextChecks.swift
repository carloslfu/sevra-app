import AppKit
import Foundation
import SevraCore
import SevraPreviewUI
import SwiftUI

private func textView(in view: NSView) -> NSTextView? {
  (view as? NSTextView) ?? view.subviews.lazy.compactMap(textView).first
}

/// Real views in an offscreen window: the same layout a viewer does, without the app.
@MainActor func checkLongText() throws {
  func expect(_ condition: Bool, _ message: String) throws {
    try require(condition, "long_text", message)
  }
  func shown<V: View>(_ root: V, dark: Bool = false) -> (NSWindow, NSHostingView<V>) {
    let host = NSHostingView(rootView: root)
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    return (window, host)
  }
  func copied(_ view: NSTextView) -> String? {
    let board = NSPasteboard(name: .init("sevra-long-text-check"))
    board.clearContents()
    return view.writeSelection(to: board, types: view.writablePasteboardTypes)
      ? board.string(forType: .string) : nil
  }
  let line = String(repeating: "x", count: 79) + "\n"
  let file = String(repeating: line, count: 12_500)
  var began = ProcessInfo.processInfo.systemUptime
  let (window, host) = shown(TextFileView(text: file), dark: true)
  host.displayIfNeeded()
  // The SwiftUI text it replaced took over a minute here.
  try expect(ProcessInfo.processInfo.systemUptime - began < 5, "A 1 MB file held the main thread")
  guard let view = textView(in: host), let scroll = view.enclosingScrollView else {
    throw SevraError("long_text", "No text view")
  }
  try expect(view.string == file, "The file text changed")
  try expect(!view.isEditable && view.isSelectable, "The preview is not read-only and selectable")
  try expect(view.textColor == .labelColor && !view.drawsBackground, "The colors changed")
  try expect(view.font?.isFixedPitch == true, "The preview lost its fixed-width font")
  try expect(view.effectiveAppearance.name == .darkAqua, "The window appearance was not followed")
  try expect(scroll.hasVerticalScroller && !scroll.drawsBackground, "The scroll view changed")
  view.setSelectedRange(NSRange(location: 80, length: 79))
  try expect(copied(view) == String(repeating: "x", count: 79), "A selection did not copy")
  view.selectAll(nil)
  try expect(copied(view) == file, "Select All did not copy the whole file")
  view.scrollRangeToVisible(NSRange(location: view.string.utf16.count, length: 0))
  try expect(view.visibleRect.minY > 0, "The end of the file could not be reached")
  host.rootView = TextFileView(text: "Short")
  host.layoutSubtreeIfNeeded()
  try expect(view.string == "Short" && view.visibleRect.minY == 0, "A new file kept the old place")
  withExtendedLifetime(window) {}

  var opened: [URL] = []
  let link = URL(string: "sevra-ref://body/a/b/c")!
  let body = String(repeating: "A plain sentence of ordinary words. ", count: 2_000)
  let linked = NSMutableAttributedString(attributedString: LongReadingText.plain(body))
  linked.addAttribute(.link, value: link, range: NSRange(location: 0, length: 7))
  began = ProcessInfo.processInfo.systemUptime
  let page = ScrollView {
    VStack(alignment: .leading) {
      Text("Title")
      LongReadingText(identity: "v1", text: { linked }) { opened.append($0) }
      Text("After")
    }.padding(24)
  }
  let (pageWindow, pageHost) = shown(page)
  pageHost.layoutSubtreeIfNeeded()
  try expect(ProcessInfo.processInfo.systemUptime - began < 5, "A long body held the main thread")
  guard let reading = textView(in: pageHost) else { throw SevraError("long_text", "No text view") }
  try expect(reading.frame.height > 600, "A long body did not get its whole height")
  try expect(reading.frame.width > 700, "A long body did not fill the page width")
  try expect(reading.string == body, "The body text changed")
  try expect(
    reading.attributedString().attribute(.link, at: 0, effectiveRange: nil) as? URL == link,
    "A saved link was dropped")
  _ = reading.delegate?.textView?(reading, clickedOnLink: link, at: 0)
  try expect(opened == [link], "A link click did not reach the document")
  try expect(
    reading.delegate?.textView?(reading, clickedOnLink: "text", at: 0) == false,
    "Something other than a URL was handled")
  reading.setSelectedRange(NSRange(location: 8, length: 8))
  try expect(copied(reading) == "sentence", "Selection in a long body did not copy")
  withExtendedLifetime(pageWindow) {}
  print("PASS long text: 1 MB file and long body lay out natively, select, copy and keep links")
}
