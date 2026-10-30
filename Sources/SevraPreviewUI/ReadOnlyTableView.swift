import AppKit
import SevraCore
import SevraTableUI
import SwiftUI

@MainActor public struct ReadOnlyTableView: View {
  let content: PreviewTableContent
  let label: String
  let inline: Bool
  let open: (URL) -> Void
  let pasteboard: NSPasteboard
  @State private var error: String?
  public init(
    content: PreviewTableContent, label: String, inline: Bool = false,
    open: @escaping (URL) -> Void = { _ in }, pasteboard: NSPasteboard = .general
  ) {
    self.content = content
    self.label = label
    self.inline = inline
    self.open = open
    self.pasteboard = pasteboard
  }
  public var body: some View {
    ReadOnlyGrid(
      content: content, label: label, inline: inline, open: open, pasteboard: pasteboard,
      failure: { error = $0 }
    )
    .frame(
      minHeight: inline ? nil : 160,
      maxHeight: inline ? 320 : .infinity
    )
    .fixedSize(horizontal: false, vertical: inline)
    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator.opacity(0.6)))
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .alert(
      "Could not copy",
      isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    ) {
      Button("OK") { error = nil }
    } message: {
      Text(error ?? "")
    }
  }
}

private final class PreviewGrid: NSTableView {
  var copyRows: ((Bool, Bool) -> Void)?
  var menuRows: (() -> NSMenu)?
  @objc func copy(_ sender: Any?) { copyRows?(false, false) }
  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
      copy(nil)
      return
    }
    super.keyDown(with: event)
  }
  override func menu(for event: NSEvent) -> NSMenu? {
    let clicked = row(at: convert(event.locationInWindow, from: nil))
    if clicked >= 0 && !selectedRowIndexes.contains(clicked) {
      selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
    }
    return menuRows?()
  }
}

private struct ReadOnlyGrid: NSViewRepresentable {
  let content: PreviewTableContent
  let label: String
  let inline: Bool
  let open: (URL) -> Void
  let pasteboard: NSPasteboard
  let failure: (String) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let grid = PreviewGrid()
    grid.delegate = context.coordinator
    grid.dataSource = context.coordinator
    grid.allowsMultipleSelection = true
    grid.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    grid.gridStyleMask = [.solidHorizontalGridLineMask]
    grid.headerView = NSTableHeaderView()
    grid.rowHeight = 34
    grid.usesAlternatingRowBackgroundColors = false
    let scroll = NSScrollView()
    scroll.hasHorizontalScroller = true
    scroll.hasVerticalScroller = true
    scroll.documentView = grid
    context.coordinator.grid = grid
    updateNSView(scroll, context: context)
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let grid = scroll.documentView as? PreviewGrid else { return }
    let coordinator = context.coordinator
    let changed =
      coordinator.parent.content != content || grid.tableColumns.count != content.headings.count
    coordinator.parent = self
    grid.setAccessibilityLabel(label)
    grid.setAccessibilityHelp(
      "Read only. Select rows with Shift or Command. Command-C copies selected rows as cells. Right-click for headings, CSV or source links. With no selection, Copy includes the whole displayed table."
    )
    grid.copyRows = { [weak coordinator] headings, csv in
      coordinator?.copy(headings: headings, csv: csv)
    }
    grid.menuRows = { [weak coordinator] in coordinator?.menu() ?? NSMenu() }
    guard changed else { return }
    let oldSelection = grid.selectedRowIndexes
    if grid.tableColumns.count != content.headings.count || coordinator.headings != content.headings
    {
      for column in grid.tableColumns { grid.removeTableColumn(column) }
      for (index, heading) in content.headings.enumerated() {
        let column = NSTableColumn(identifier: .init(String(index)))
        column.title = content.plain(heading)
        column.isEditable = false
        column.width = index == 0 ? 180 : 150
        column.minWidth = 70
        grid.addTableColumn(column)
      }
      coordinator.headings = content.headings
    }
    grid.reloadData()
    grid.selectRowIndexes(
      oldSelection.intersection(IndexSet(content.rows.indices)), byExtendingSelection: false)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context)
    -> CGSize?
  {
    guard inline, let grid = scroll.documentView as? PreviewGrid else { return nil }
    let width = proposal.width ?? 380
    if abs(grid.frame.width - width) > 1 {
      grid.setFrameSize(NSSize(width: width, height: grid.frame.height))
      grid.sizeToFit()
    }
    var height: CGFloat = grid.headerView?.frame.height ?? 24
    for row in content.rows.indices {
      height += context.coordinator.tableView(grid, heightOfRow: row) + grid.intercellSpacing.height
      if height >= 300 { break }
    }
    let horizontal = grid.tableColumns.reduce(0) { $0 + $1.width } > width ? 17.0 : 0
    return .init(width: width, height: min(320, max(70, height + horizontal + 4)))
  }
  @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var parent: ReadOnlyGrid
    weak var grid: PreviewGrid?
    var headings: [String] = []
    var actions: [Int: () -> Void] = [:]
    init(_ parent: ReadOnlyGrid) { self.parent = parent }
    func numberOfRows(in tableView: NSTableView) -> Int { parent.content.rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      guard let column = tableColumn.flatMap({ Int($0.identifier.rawValue) }),
        parent.content.rows.indices.contains(row), parent.content.rows[row].indices.contains(column)
      else { return nil }
      let identifier = NSUserInterfaceItemIdentifier("preview-cell")
      let field =
        tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
        ?? NSTextField(wrappingLabelWithString: "")
      field.identifier = identifier
      field.isEditable = false
      field.isSelectable = false
      field.font = .systemFont(ofSize: 13)
      field.textColor = .labelColor
      let value = parent.content.rows[row][column]
      field.stringValue = parent.content.plain(value)
      field.toolTip = String(parent.content.plain(value).prefix(4000))
      field.setAccessibilityElement(true)
      field.setAccessibilityRole(.staticText)
      field.setAccessibilityLabel(
        (tableColumn?.title.isEmpty == false ? tableColumn!.title : "Value") + ", row \(row + 1)")
      field.setAccessibilityValue(parent.content.plain(value))
      return field
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
      guard parent.content.rows.indices.contains(row) else { return 34 }
      var height: CGFloat = 34
      for (index, value) in parent.content.rows[row].enumerated()
      where index < tableView.tableColumns.count {
        let size = (String(parent.content.plain(value).prefix(1024)) as NSString).boundingRect(
          with: NSSize(width: max(40, tableView.tableColumns[index].width - 14), height: 110),
          options: [.usesLineFragmentOrigin, .usesFontLeading],
          attributes: [.font: NSFont.systemFont(ofSize: 13)])
        height = max(height, min(120, ceil(size.height) + 14))
      }
      return height
    }
    func tableViewColumnDidResize(_ notification: Notification) {
      guard let grid else { return }
      grid.noteHeightOfRows(withIndexesChanged: IndexSet(parent.content.rows.indices))
    }
    func copy(headings: Bool, csv: Bool) {
      guard let grid else { return }
      do {
        let cells = parent.content.cells(selected: grid.selectedRowIndexes, headings: headings)
        let copied = try TableClipboard(cells: cells.map { $0.map(Value.string) })
        if csv {
          let text = CSV.encode(cells)
          try require(
            text.utf8.count <= TableClipboard.maximumTextBytes, "copy_limit",
            "Select fewer rows to copy as CSV.")
          let item = NSPasteboardItem()
          item.setString(text, forType: .string)
          item.setString(text, forType: .init("public.comma-separated-values-text"))
          parent.pasteboard.clearContents()
          try require(
            parent.pasteboard.writeObjects([item]), "clipboard", "Could not copy these rows.")
        } else {
          try copied.write(to: parent.pasteboard)
        }
      } catch { parent.failure(error.localizedDescription) }
    }
    @objc func performMenu(_ item: NSMenuItem) { actions[item.tag]?() }
    func menu() -> NSMenu {
      actions = [:]
      let menu = NSMenu()
      func add(_ title: String, _ action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(performMenu), keyEquivalent: "")
        item.tag = actions.count
        item.target = self
        actions[item.tag] = action
        menu.addItem(item)
      }
      add("Copy") { [weak self] in self?.copy(headings: false, csv: false) }
      add("Copy with headings") { [weak self] in self?.copy(headings: true, csv: false) }
      add("Copy as CSV") { [weak self] in self?.copy(headings: false, csv: true) }
      if parent.content.markdown, let selected = grid?.selectedRowIndexes, !selected.isEmpty {
        let cells = parent.content.cells(selected: selected, headings: false)
        // Discover links from original markup rather than the copied plain labels.
        let raw = selected.filter { parent.content.rows.indices.contains($0) }
          .flatMap { parent.content.rows[$0] }.joined(separator: "\n")
        let links = ConversationPresentation(raw).links
        if !cells.isEmpty && !links.isEmpty { menu.addItem(.separator()) }
        for link in links { add(link.actionTitle) { [weak self] in self?.parent.open(link.url) } }
      }
      return menu
    }
  }
}
