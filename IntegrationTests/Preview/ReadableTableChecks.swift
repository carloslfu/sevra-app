import AppKit
import Foundation
import SevraCore
import SevraPreviewUI
import SwiftUI

@MainActor func checkReadableTables() throws {
  func expect(_ condition: Bool, line: Int = #line) throws {
    try require(
      condition, "readable_tables", "Read-only table presentation or copy changed at line \(line).")
  }
  let source = """
    Café **before**.

    | Detail | Atlas | Brio |
    |:---|---:|---:|
    | SKU | 0014 | 0014 |
    | Notes | a\\|b | **tax excluded** |
    | Source | [CSV](sevra://item/a) | [PDF](sevra://item/b?locator=page%3D1) |

    After [evidence](sevra://item/b).
    """
  // A paragraph right above a table stays on screen.
  let attached = ConversationPresentation("Results:\nnext line:\n| A | B |\n|---|---|\n| 1 | 2 |\n").blocks
  guard case .text(let lead) = attached.first, case .table = attached.dropFirst().first else {
    throw SevraError("readable_tables", "The lead-in was lost")
  }
  try expect(lead == "Results:\nnext line:\n")
  // A cell shows exactly its text.
  let exact = "| A | B |\n|---|---|\n| 2\\*3\\*4 | \\*\\*plain\\*\\* |\n| \\[a\\](http://b.example) | a\\|b |\n| ^ | xor |\n"
  guard case .table(let cells) = ConversationPresentation(exact).blocks.first else {
    throw SevraError("readable_tables", "Missing table")
  }
  try expect(
    cells.cells(selected: [], headings: false)
      == [["2*3*4", "**plain**"], ["[a](http://b.example)", "a|b"], ["^", "xor"]])
  // A message too deep to parse stays plain text and never reaches the recursive parser.
  let deep = String(repeating: ">", count: 12_000) + " x"
  try expect(ConversationPresentation(deep).blocks == [.text(deep)])
  let shallow = "> > quoted\n\n| A |\n|---|\n| 1 |\n"
  try expect(ConversationPresentation(shallow).blocks.count == 3)
  let blocks = ConversationPresentation(source).blocks
  try expect(blocks.count == 3)
  guard case .text(let before) = blocks[0], case .table(let table) = blocks[1],
    case .text(let after) = blocks[2]
  else { throw SevraError("readable_tables", "Missing table blocks") }
  try expect(before == "Café **before**.\n\n")
  try expect(after.contains("After [evidence](sevra://item/b)."))
  try expect(table.headings.map(table.plain) == ["Detail", "Atlas", "Brio"])
  try expect(table.rows[0].map(table.plain) == ["SKU", "0014", "0014"])
  try expect(table.rows[1].map(table.plain) == ["Notes", "a|b", "tax excluded"])
  try expect(table.rows[2].map(table.plain) == ["Source", "CSV", "PDF"])
  try expect(ConversationPresentation(source).links.count == 3)
  try expect(table.linkRanges(table.rows[2][1]) == [NSRange(location: 0, length: 3)])
  try expect(table.linkRanges("[script](file:///tmp/x)").isEmpty)
  try expect(PreviewTableContent(headings: [], rows: []).linkRanges("[CSV](sevra://item/a)").isEmpty)
  try expect(table.cells(selected: IndexSet([0, 2]), headings: false).count == 2)
  try expect(table.cells(selected: [], headings: true).count == 4)
  for literal in ["a | b\nnot a table", "```text\n| a | b |\n|---|---|\n|1|2|\n```"] {
    try expect(
      !ConversationPresentation(literal).blocks.contains {
        if case .table = $0 { return true }
        return false
      })
  }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-readable-tables-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let csv = root.appendingPathComponent("Quotes.csv")
  try Data("\u{feff}SKU,Notes\r\n0014,\"quoted, note\nsecond line\"\r\n=2+2,\"a\"\"b\"\r\n".utf8)
    .write(to: csv)
  let preview = try DelimitedPreview.load(csv)
  try expect(preview.table.headings == ["SKU", "Notes"])
  try expect(preview.table.rows == [["0014", "quoted, note\nsecond line"], ["=2+2", "a\"b"]])
  let tsv = root.appendingPathComponent("Quotes.tsv")
  try Data("Code\tPrice\n0014\t1,20\n0007\t3,40\textra".utf8).write(to: tsv)
  let tab = try DelimitedPreview.load(tsv)
  try expect(tab.table.headings == ["Code", "Price", "Column 3"])
  try expect(tab.table.rows == [["0014", "1,20", ""], ["0007", "3,40", "extra"]])
  let large = root.appendingPathComponent("Large.csv")
  try Data(
    ("Code,Notes\n" + String(repeating: "0014,\"line one\nline two\"\n", count: 60_000)).utf8
  ).write(to: large)
  let bounded = try DelimitedPreview.load(large)
  try expect(bounded.table.rows.count == DelimitedPreview.rowLimit)
  try expect(bounded.table.rows.last == ["0014", "line one\nline two"])
  try expect(bounded.detail.contains("within 1 MB"))
  try Data(("Code,Notes\n" + String(repeating: "0014,valid\n", count: 2_000)).utf8).write(to: large)
  try expect(try DelimitedPreview.load(large).detail.contains("of 2000"))
  // A megabyte of very short rows holds more records than the parser takes.
  try Data(("n\n" + String(repeating: "1\n", count: 490_000)).utf8).write(to: large)
  try expect(try DelimitedPreview.load(large).table.rows.count == DelimitedPreview.rowLimit)
  let cancelled = Cancellation()
  cancelled.cancel()
  do {
    _ = try DelimitedPreview.load(csv, cancellation: cancelled)
    try expect(false)
  } catch let error as SevraError { try expect(error.code == "cancelled") }
  try Data("Code,Notes\n0014,\"unclosed".utf8).write(to: csv)
  do {
    _ = try DelimitedPreview.load(csv)
    try expect(false)
  } catch let error as SevraError { try expect(error.code == "csv") }
  let clipboard = NSPasteboard.withUniqueName()
  defer { clipboard.releaseGlobally() }
  let host = NSHostingView(
    rootView: ReadOnlyTableView(
      content: table, label: "Test comparison", inline: true, pasteboard: clipboard))
  host.frame = NSRect(x: 0, y: 0, width: 380, height: 220)
  host.layoutSubtreeIfNeeded()
  func find(_ view: NSView) -> NSTableView? {
    if let table = view as? NSTableView { return table }
    return view.subviews.lazy.compactMap { find($0) }.first
  }
  guard let grid = find(host) else {
    throw SevraError("readable_tables", "Native table was not created")
  }
  try expect(grid.numberOfRows == 3 && grid.numberOfColumns == 3)
  try expect(grid.tableColumns.allSatisfy { !$0.isEditable })
  grid.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
  grid.perform(NSSelectorFromString("copy:"), with: nil)
  try expect(clipboard.string(forType: .string) == "SKU\t0014\t0014\nSource\tCSV\tPDF")
  try expect(clipboard.string(forType: .html)?.contains("<table") == true)
  try expect(clipboard.string(forType: .tabularText) == clipboard.string(forType: .string))
  if let field = (grid.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)?
    .textField
  {
    try expect(field.isAccessibilityElement())
    try expect(field.accessibilityValue() == "SKU")
  } else {
    try expect(false)
  }
  let event = NSEvent.mouseEvent(
    with: .rightMouseDown, location: .init(x: -10, y: -10),
    modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1,
    pressure: 1)!
  let menu = grid.menu(for: event)!
  let csvAction = menu.items.first { $0.title == "Copy as CSV" }!
  (csvAction.target as? NSObject)?.perform(csvAction.action!, with: csvAction)
  try expect(
    clipboard.string(forType: .string)
      == CSV.encode([["SKU", "0014", "0014"], ["Source", "CSV", "PDF"]]))
  let headingsAction = menu.items.first { $0.title == "Copy with headings" }!
  (headingsAction.target as? NSObject)?.perform(headingsAction.action!, with: headingsAction)
  try expect(clipboard.string(forType: .string)?.hasPrefix("Detail\tAtlas\tBrio\n") == true)
  try expect(menu.items.contains { $0.title == "Open CSV" })
  try expect(menu.items.contains { $0.title == "Open PDF" })
  try checkTableSizing()
  print(
    "PASS native Markdown/CSV/TSV tables, exact text and links, multiline/large preview bounds, read-only multi-row cell copy and rich clipboard, content-aware sizing, shared wheel scrolling, cell links"
  )
}

/// Counts wheel events on their way to the next responder.
private final class WheelRelay: NSResponder {
  var received = 0
  override func scrollWheel(with event: NSEvent) {
    received += 1
    nextResponder?.scrollWheel(with: event)
  }
}
private final class WheelSpy: NSView {
  var received = 0
  override func scrollWheel(with event: NSEvent) { received += 1 }
}

/// Compact comparisons fit narrow panes without wrapping, spare rows or their own
/// scrolling; wider data keeps whole words and scrolls; original files fill the
/// viewer; and a person's column width survives a later pane resize.
@MainActor private func checkTableSizing() throws {
  func expect(_ condition: Bool, line: Int = #line) throws {
    try require(condition, "readable_tables", "Table sizing or scrolling changed at line \(line).")
  }
  var retained: [NSWindow] = []
  defer { withExtendedLifetime(retained) {} }
  func host(
    _ content: PreviewTableContent, inline: Bool, width: CGFloat, open: @escaping (URL) -> Void = { _ in }
  ) -> (NSWindow, NSHostingView<AnyView>, NSTableView) {
    let view = ReadOnlyTableView(content: content, label: "Sizing", inline: inline, open: open)
    let host = NSHostingView(
      rootView: AnyView(view.frame(width: width, height: inline ? nil : 300, alignment: .leading)))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: 400), styleMask: [.borderless],
      backing: .buffered, defer: false)
    retained.append(window)
    let spy = WheelSpy(frame: NSRect(x: 0, y: 0, width: width, height: 400))
    host.frame = spy.bounds
    host.autoresizingMask = [.width, .height]
    spy.addSubview(host)
    window.contentView = spy
    for _ in 0..<3 {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    func grid(_ view: NSView) -> NSTableView? {
      (view as? NSTableView) ?? view.subviews.lazy.compactMap(grid).first
    }
    return (window, host, grid(host)!)
  }
  func extent(_ grid: NSTableView) -> CGFloat {
    grid.rect(ofColumn: grid.numberOfColumns - 1).maxX + grid.rect(ofColumn: 0).minX
  }
  let comparison = PreviewTableContent(
    headings: ["", "Atlas", "Brio"],
    rows: [
      ["Unit price", "1.20", "1.15"], ["Goods (100 × unit)", "120.00", "115.00"],
      ["Shipping", "10.00", "20.00"], ["**Goods + Shipping**", "**130.00**", "**135.00**"],
    ], markdown: true)
  let (_, _, compact) = host(comparison, inline: true, width: 340)
  let compactScroll = compact.enclosingScrollView!
  try expect(compactScroll.frame.width < 340)
  try expect(extent(compact) <= compactScroll.contentView.bounds.width + 0.5)
  try expect((0..<compact.numberOfRows).allSatisfy { compact.rect(ofRow: $0).height == 30 })
  let rows = (0..<compact.numberOfRows).reduce(0) { $0 + compact.rect(ofRow: $1).height }
  try expect(rows == 120)
  try expect(
    compactScroll.frame.height
      == compact.intrinsicContentSize.height + (compact.headerView?.frame.height ?? 0))
  try expect(compact.frame.height <= compactScroll.documentVisibleRect.maxY + 0.5)
  try expect(compactScroll.autohidesScrollers)
  // Only a table's own overflow keeps the wheel from the surrounding conversation.
  func wheel(x: Int32 = 0, y: Int32 = 0) -> NSEvent {
    NSEvent(
      cgEvent: CGEvent(
        scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x,
        wheel3: 0)!)!
  }
  func spy(_ grid: NSTableView) -> WheelSpy { grid.window!.contentView as! WheelSpy }
  compactScroll.scrollWheel(with: wheel(y: -40))
  compactScroll.scrollWheel(with: wheel(x: -40))
  try expect(spy(compact).received == 2)
  // The same gesture reaches a real conversation scroll view and moves it.
  let conversation = NSHostingView(
    rootView: ScrollView {
      VStack(spacing: 0) {
        Color.clear.frame(height: 300)
        ReadOnlyTableView(content: comparison, label: "Scrolling", inline: true)
        Color.clear.frame(height: 900)
      }
    }.frame(width: 340, height: 400))
  let conversationWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 340, height: 400), styleMask: [.borderless],
    backing: .buffered, defer: false)
  retained.append(conversationWindow)
  conversationWindow.contentView = conversation
  for _ in 0..<3 {
    conversation.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
  }
  func table(_ view: NSView) -> NSTableView? {
    (view as? NSTableView) ?? view.subviews.lazy.compactMap(table).first
  }
  let inner = table(conversation)!.enclosingScrollView!
  let outer = inner.superview!.enclosingScrollView!
  let before = outer.contentView.bounds.origin.y
  // Moving the view runs on the display link, so a sleeping screen only proves the gesture
  // arrives. The movement itself is checked whenever the display is awake.
  let relay = WheelRelay()
  var below: NSResponder = inner
  while let next = below.nextResponder, next !== outer { below = next }
  try expect(below.nextResponder === outer)
  relay.nextResponder = outer
  below.nextResponder = relay
  let awake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
  let deadline = Date().addingTimeInterval(3)
  repeat {
    inner.scrollWheel(with: wheel(y: -40))
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
  } while awake && outer.contentView.bounds.origin.y <= before && Date() < deadline
  try expect(relay.received > 0)
  try expect(!awake || outer.contentView.bounds.origin.y > before)
  let wide = PreviewTableContent(
    headings: ["Supplier", "Product", "Known goods-plus-shipping", "Delivery", "Tax", "Notes"],
    rows: [
      [
        "Cobalt Supply Cooperative", "Stainless M6 bolts with nylon insert lock nuts", "142.50",
        "2 to 3 weeks after deposit", "8% sales tax", "Leading zeros: 0014",
      ]
    ], markdown: true)
  let (_, _, scrolling) = host(wide, inline: true, width: 340)
  try expect(extent(scrolling) > scrolling.enclosingScrollView!.contentView.bounds.width)
  scrolling.enclosingScrollView!.scrollWheel(with: wheel(x: -40))
  try expect(spy(scrolling).received == 0)
  scrolling.enclosingScrollView!.scrollWheel(with: wheel(y: -40))
  try expect(spy(scrolling).received == 1)
  let long = PreviewTableContent(
    headings: ["Supplier", "Cost"],
    rows: [["[Quote](sevra://item/a)", "1.00"]] + (1..<200).map { ["Supplier \($0)", "\($0).00"] },
    markdown: true)
  let (_, _, tall) = host(long, inline: true, width: 340)
  let tallScroll = tall.enclosingScrollView!
  try expect(tallScroll.frame.height > 280 && tallScroll.frame.height <= 320)
  tallScroll.scrollWheel(with: wheel(y: -40))
  try expect(spy(tall).received == 0)
  tall.scrollRowToVisible(199)
  tall.layoutSubtreeIfNeeded()
  tallScroll.scrollWheel(with: wheel(y: -40))
  try expect(spy(tall).received == 1)
  tallScroll.scrollWheel(with: wheel(y: 40))
  try expect(spy(tall).received == 1)
  func color(_ grid: NSTableView, row: Int) -> NSColor? {
    let field = (grid.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField
    return field?.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil)
      as? NSColor
  }
  // Scrolling reuses cells; a former link cell must not stay blue.
  try expect(color(tall, row: 199) != .linkColor)
  let font = NSFont.systemFont(ofSize: 13)
  for (column, value) in zip(scrolling.tableColumns, wide.rows[0]) {
    let longest = value.split(separator: " ").map {
      (String($0) as NSString).size(withAttributes: [.font: font]).width
    }.max()!
    try expect(column.width >= ceil(longest))
  }
  // Short values stay on one line before a long heading gets its full width.
  let headed = PreviewTableContent(
    headings: ["Supplier", "Known goods-plus-shipping before tax"],
    rows: (1...3).map { ["Supplier \($0)", "\($0)00.00"] }, markdown: true)
  let (_, _, heading) = host(headed, inline: true, width: 240)
  try expect((0..<heading.numberOfRows).allSatisfy { heading.rect(ofRow: $0).height == 30 })
  try expect(extent(heading) <= heading.enclosingScrollView!.contentView.bounds.width + 0.5)
  let original = PreviewTableContent(headings: ["SKU", "Name"], rows: [["0014", "Brass bolts"]])
  let (window, viewer, filled) = host(original, inline: false, width: 600)
  let visible = filled.enclosingScrollView!.contentView.bounds.width
  try expect(abs(extent(filled) - visible) <= 1)
  filled.tableColumns[0].width += 40
  let chosen = filled.tableColumns[0].width
  window.setContentSize(NSSize(width: 700, height: 400))
  viewer.rootView = AnyView(
    ReadOnlyTableView(content: original, label: "Sizing").frame(width: 700, height: 300))
  for _ in 0..<3 {
    viewer.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
  }
  try expect(filled.tableColumns[0].width == chosen)
  var opened: [URL] = []
  let linked = PreviewTableContent(
    headings: ["Source", "Note"],
    rows: [
      ["[Quote](sevra://item/a)", "Plain"],
      ["[One](sevra://item/a) and [two](sevra://item/b)", "Several"],
    ], markdown: true)
  let (_, _, links) = host(linked, inline: true, width: 340) { opened.append($0) }
  func click(_ grid: NSTableView, row: Int, column: Int, flags: NSEvent.ModifierFlags = []) {
    let cell = grid.frameOfCell(atColumn: column, row: row)
    let point = grid.convert(NSPoint(x: cell.midX, y: cell.midY), to: nil)
    func event(_ type: NSEvent.EventType) -> NSEvent {
      NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: flags,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: grid.window!.windowNumber,
        context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
    grid.window!.postEvent(event(.leftMouseUp), atStart: false)
    grid.mouseDown(with: event(.leftMouseDown))
  }
  try expect(color(links, row: 0) == .linkColor)
  if let cell = links.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView {
    cell.backgroundStyle = .emphasized
    try expect(color(links, row: 0) == .alternateSelectedControlTextColor)
    cell.backgroundStyle = .normal
    try expect(color(links, row: 0) == .linkColor)
  } else {
    try expect(false)
  }
  click(links, row: 0, column: 0)
  try expect(opened == [URL(string: "sevra://item/a")!] && links.selectedRow == 0)
  opened = []
  click(links, row: 1, column: 1)
  try expect(opened.isEmpty && links.selectedRow == 1)
  click(links, row: 0, column: 1)
  try expect(opened.isEmpty && links.selectedRow == 0)
  click(links, row: 1, column: 0)
  try expect(opened.isEmpty && links.selectedRow == 1)
  click(links, row: 0, column: 0, flags: .shift)
  try expect(opened.isEmpty && links.selectedRowIndexes == [0, 1])
}
