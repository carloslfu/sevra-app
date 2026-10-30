import AppKit
import Foundation
import SevraCore
import SevraPreviewUI
import SwiftUI

@MainActor func checkReadableTables() throws {
  func expect(_ condition: Bool) throws {
    try require(condition, "readable_tables", "Read-only table presentation or copy changed.")
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
  try checkTableSizing(expect)
  print(
    "PASS native Markdown/CSV/TSV tables, exact text and links, multiline/large preview bounds, read-only multi-row cell copy and rich clipboard, content-aware sizing"
  )
}

/// Compact comparisons fit narrow panes without wrapping or spare rows; wider
/// data keeps whole words and scrolls; original files fill the viewer; and a
/// person's column width survives a later pane resize.
@MainActor private func checkTableSizing(_ expect: (Bool) throws -> Void) throws {
  func host(_ content: PreviewTableContent, inline: Bool, width: CGFloat) -> (
    NSWindow, NSHostingView<AnyView>, NSTableView
  ) {
    let view = ReadOnlyTableView(content: content, label: "Sizing", inline: inline)
    let host = NSHostingView(
      rootView: AnyView(view.frame(width: width, height: inline ? nil : 300, alignment: .leading)))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: 400), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView = host
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
  try expect(compactScroll.frame.height == rows + (compact.headerView?.frame.height ?? 0) + 4)
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
  let font = NSFont.systemFont(ofSize: 13)
  for (column, value) in zip(scrolling.tableColumns, wide.rows[0]) {
    let longest = value.split(separator: " ").map {
      (String($0) as NSString).size(withAttributes: [.font: font]).width
    }.max()!
    try expect(column.width >= ceil(longest))
  }
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
}
