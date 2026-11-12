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
  @State private var selection: Int?
  @State private var detail: Int?
  @State private var copied: String?
  @AppStorage(ReadingStyle.preference) private var textScale = 1.0
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
    VStack(alignment: .leading, spacing: 6) {
      ReadOnlyGrid(
        content: content, label: label, inline: inline, open: open, pasteboard: pasteboard,
        failure: { error = $0 }, selected: { selection = $0 }, inspect: { detail = $0 },
        copied: { copied = $0 }, textScale: textScale)
      HStack {
        Button("Read selected row") { detail = selection }
          .disabled(selection == nil)
          .accessibilityLabel("Read full values in the selected row of " + label)
        if let copied { Text(copied).readingFont(.caption).foregroundStyle(.secondary) }
      }
    }
    .announceStatus(copied)
    .sheet(isPresented: Binding(get: { detail != nil }, set: { if !$0 { detail = nil } })) {
      VStack(alignment: .leading, spacing: 14) {
        Text(label).readingFont(.title2).accessibilityAddTraits(.isHeader)
        if let row = detail, content.rows.indices.contains(row) {
          Text("Row \(row + 1)").readingFont(.headline).accessibilityAddTraits(.isHeader)
          ScrollView {
            VStack(alignment: .leading, spacing: 14) {
              ForEach(content.headings.indices, id: \.self) { column in
                if content.rows[row].indices.contains(column) {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(content.plain(content.headings[column])).readingFont(.headline)
                      .accessibilityAddTraits(.isHeader)
                    let value = content.plain(content.rows[row][column])
                    if value.utf8.count > LongReadingText.thresholdBytes {
                      LongReadingText(
                        identity: content.rowIDs[row] + String(column) + value,
                        text: { LongReadingText.plain(value) })
                    } else {
                      Text(value).textSelection(.enabled)
                    }
                    ForEach(
                      Array(content.links(row: row, column: column).enumerated()), id: \.offset
                    ) { _, link in
                      Button("Open " + link.title) {
                        detail = nil
                        open(link.url)
                      }.buttonStyle(.link)
                    }
                  }.accessibilityElement(children: .contain)
                }
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }
        } else {
          Text("This row is no longer displayed. Close and select a current row.")
        }
        Button("Done") { detail = nil }.keyboardShortcut(.cancelAction)
      }.padding(20).readingFont(.body)
        .frame(minWidth: 360, idealWidth: 560, minHeight: 300, idealHeight: 500)
    }
    .onChange(of: content) { _, _ in detail = nil }

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
  var openCell: ((Int, Int) -> Void)?
  var activeColumn = 0
  override func mouseDown(with event: NSEvent) {
    let column = column(at: convert(event.locationInWindow, from: nil))
    if column >= 0 { activeColumn = column }
    super.mouseDown(with: event)
    needsDisplay = true
  }
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard window?.firstResponder === self, selectedRow >= 0, numberOfColumns > 0 else { return }
    NSColor.keyboardFocusIndicatorColor.setStroke()
    let ring = NSBezierPath(
      rect: frameOfCell(atColumn: activeColumn, row: selectedRow).insetBy(dx: 1, dy: 1))
    ring.lineWidth = 2
    ring.stroke()
  }
  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    needsDisplay = true
    return accepted
  }
  override func resignFirstResponder() -> Bool {
    needsDisplay = true
    return super.resignFirstResponder()
  }
  @objc func copy(_ sender: Any?) { copyRows?(false, false) }
  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
      copy(nil)
      return
    }
    if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
      if event.keyCode == 123 || event.keyCode == 124 {
        activeColumn = min(
          max(0, activeColumn + (event.keyCode == 123 ? -1 : 1)), max(0, numberOfColumns - 1))
        scrollColumnToVisible(activeColumn)
        if selectedRow >= 0,
          let cell = view(atColumn: activeColumn, row: selectedRow, makeIfNecessary: true)
            as? NSTableCellView
        {
          cell.textField?.setAccessibilityFocused(true)
        }
        needsDisplay = true
        return
      }
      if event.keyCode == 36 || event.keyCode == 76 {
        openCell?(selectedRow, activeColumn)
        return
      }
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

/// Equal vertical padding; text that exceeds the row limit ends in an ellipsis.
/// The leading inset lines values up with their column headings.
private final class PreviewLinkField: NSTextField {
  var press: (() -> Bool)?
  var focusChanged: (() -> Void)?
  override func accessibilityPerformPress() -> Bool { press?() ?? false }
  override func setAccessibilityFocused(_ focused: Bool) {
    super.setAccessibilityFocused(focused)
    if focused { focusChanged?() }
  }
}

private final class PreviewCell: NSTableCellView {
  let field = PreviewLinkField(wrappingLabelWithString: "")
  private var links: [NSRange] = []
  init() {
    super.init(frame: .zero)
    field.isEditable = false
    field.isSelectable = false
    field.textColor = .labelColor
    field.cell?.truncatesLastVisibleLine = true
    field.setAccessibilityElement(true)
    field.setAccessibilityRole(.staticText)
    field.translatesAutoresizingMaskIntoConstraints = false
    addSubview(field)
    textField = field
    NSLayoutConstraint.activate([
      field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PreviewCell.leading),
      field.trailingAnchor.constraint(equalTo: trailingAnchor),
      field.topAnchor.constraint(equalTo: topAnchor, constant: PreviewCell.padding),
      field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -PreviewCell.padding),
    ])
  }
  required init?(coder: NSCoder) { nil }
  static let padding: CGFloat = 6
  static let leading: CGFloat = 2
  func show(_ text: String, links: [NSRange]) {
    self.links = links
    field.stringValue = text
    paint()
    window?.invalidateCursorRects(for: self)
  }
  override var backgroundStyle: NSView.BackgroundStyle { didSet { paint() } }
  override func resetCursorRects() {
    if !links.isEmpty { addCursorRect(field.frame, cursor: .pointingHand) }
  }
  /// Blue on the accent-colored selection would be unreadable, so a selected
  /// link uses the selected text color.
  private func paint() {
    guard !links.isEmpty else { return }
    let selected = backgroundStyle == .emphasized
    let text = NSMutableAttributedString(attributedString: field.attributedStringValue)
    text.addAttribute(
      .foregroundColor, value: selected ? NSColor.alternateSelectedControlTextColor : .labelColor,
      range: NSRange(location: 0, length: text.length))
    if !selected {
      for link in links {
        text.addAttribute(.foregroundColor, value: NSColor.linkColor, range: link)
      }
    }
    field.attributedStringValue = text
  }
}

/// Refits content-aware columns when the visible width changes. A table inside
/// a conversation keeps only the wheel gestures it can use, so the conversation
/// still scrolls with the pointer over a table that fits or has reached its end.
private final class PreviewScroll: NSScrollView {
  var refit: ((CGFloat) -> Void)?
  var sharesWheel = false
  private var forwarding = false
  override func layout() {
    super.layout()
    refit?(contentView.bounds.width)
  }
  override func scrollWheel(with event: NSEvent) {
    guard sharesWheel else { return super.scrollWheel(with: event) }
    // One owner per gesture, including its momentum.
    if event.phase == .began || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
      forwarding = !canScroll(event)
    }
    if forwarding {
      nextResponder?.scrollWheel(with: event)
    } else {
      super.scrollWheel(with: event)
    }
  }
  private func canScroll(_ event: NSEvent) -> Bool {
    let visible = documentVisibleRect
    let size = documentView?.frame.size ?? .zero
    let (x, y) = (event.scrollingDeltaX, event.scrollingDeltaY)
    if abs(x) > abs(y) { return x > 0 ? visible.minX > 0.5 : visible.maxX < size.width - 0.5 }
    // The visible rectangle starts above the document, behind the heading row.
    let top = -contentView.contentInsets.top
    return y > 0 ? visible.minY > top + 0.5 : visible.maxY < size.height - 0.5
  }
}

private struct ReadOnlyGrid: NSViewRepresentable {
  let content: PreviewTableContent
  let label: String
  let inline: Bool
  let open: (URL) -> Void
  let pasteboard: NSPasteboard
  let failure: (String) -> Void
  let selected: (Int?) -> Void
  let inspect: (Int) -> Void
  let copied: (String) -> Void
  let textScale: Double
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let grid = PreviewGrid()
    grid.delegate = context.coordinator
    grid.dataSource = context.coordinator
    grid.target = context.coordinator
    grid.action = #selector(Coordinator.openClickedLink)
    grid.doubleAction = #selector(Coordinator.openClickedLink)
    grid.allowsMultipleSelection = true
    // Links, widths and copied rows follow the data's column order.
    grid.allowsColumnReordering = false
    // The coordinator sizes columns from their contents and the visible width.
    grid.columnAutoresizingStyle = .noColumnAutoresizing
    grid.style = .inset
    grid.gridStyleMask = [.solidHorizontalGridLineMask]
    grid.headerView = NSTableHeaderView()
    grid.rowHeight = 30
    grid.usesAlternatingRowBackgroundColors = false
    let scroll = PreviewScroll()
    scroll.borderType = .noBorder
    scroll.hasHorizontalScroller = true
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.sharesWheel = inline
    scroll.documentView = grid
    scroll.refit = { [weak coordinator = context.coordinator] width in coordinator?.fit(width) }
    context.coordinator.grid = grid
    updateNSView(scroll, context: context)
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let grid = scroll.documentView as? PreviewGrid else { return }
    let coordinator = context.coordinator
    let changed =
      coordinator.parent.content != content || grid.tableColumns.count != content.headings.count
      || coordinator.parent.textScale != textScale
    let oldIDs = Set(
      grid.selectedRowIndexes.compactMap { index in
        coordinator.parent.content.rowIDs.indices.contains(index)
          ? coordinator.parent.content.rowIDs[index] : nil
      })
    coordinator.parent = self
    grid.setAccessibilityLabel(label)
    grid.setAccessibilityHelp(
      "Read only. Select rows with Shift or Command. Command-C copies selected rows as cells. Left and Right choose a column. Return opens its source or full row values. Read selected row shows all values and source buttons. Source actions are also available on each linked cell. With no selection, Copy includes the whole displayed table."
    )
    grid.copyRows = { [weak coordinator] headings, csv in
      coordinator?.copy(headings: headings, csv: csv)
    }
    grid.menuRows = { [weak coordinator] in coordinator?.menu() ?? NSMenu() }
    grid.openCell = { [weak coordinator] row, column in coordinator?.open(row: row, column: column)
    }
    guard changed else { return }
    grid.activeColumn = min(grid.activeColumn, max(0, content.headings.count - 1))
    if grid.tableColumns.count != content.headings.count || coordinator.headings != content.headings
    {
      for column in grid.tableColumns { grid.removeTableColumn(column) }
      for (index, heading) in content.headings.enumerated() {
        let column = NSTableColumn(identifier: .init(String(index)))
        column.title = content.plain(heading)
        column.headerToolTip = column.title
        column.isEditable = false
        column.minWidth = 40
        grid.addTableColumn(column)
      }
      coordinator.headings = content.headings
    }
    grid.headerView?.frame.size.height = 24 * ReadingStyle.scale(textScale)
    for column in grid.tableColumns {
      column.headerCell.font = .systemFont(ofSize: 11 * ReadingStyle.scale(textScale))
    }
    coordinator.measure()
    if scroll.window != nil { coordinator.fit(scroll.contentView.bounds.width) }
    grid.reloadData()
    grid.selectRowIndexes(
      IndexSet(content.rowIDs.indices.filter { oldIDs.contains(content.rowIDs[$0]) }),
      byExtendingSelection: false)
    coordinator.publishSelection()
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context)
    -> CGSize?
  {
    guard inline, let grid = scroll.documentView as? PreviewGrid else { return nil }
    let coordinator = context.coordinator
    let proposed = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    // Compact tables hug their contents; wider data keeps the pane width and scrolls.
    let widths = coordinator.widths(available: proposed ?? .greatestFiniteMagnitude)
    let needed = coordinator.contentWidth(widths)
    let width = min(proposed ?? needed, needed)
    // The inset style pads above the first row and below the last. Without both
    // a table that fits would still scroll a few points.
    let padding =
      content.rows.isEmpty
      ? 0
      : max(0, grid.rect(ofRow: 0).minY)
        + max(0, grid.intrinsicContentSize.height - grid.rect(ofRow: content.rows.count - 1).maxY)
    var height = (grid.headerView?.frame.height ?? 24) + padding
    for row in content.rows.indices {
      height += coordinator.rowHeight(row, widths: widths) + grid.intercellSpacing.height
      if height >= 300 { break }
    }
    let horizontal = needed > width + 1 ? 17.0 : 0
    return .init(width: width, height: min(320, max(70, height + horizontal)))
  }
  @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var parent: ReadOnlyGrid
    weak var grid: PreviewGrid?
    var headings: [String] = []
    var actions: [Int: () -> Void] = [:]
    private var ideal: [CGFloat] = []
    private var unwrapped: [CGFloat] = []
    private var minimum: [CGFloat] = []
    private var fittedWidth: CGFloat = -1
    private var applyingWidths = false
    private var userResized = false
    private var heights: [Int: CGFloat] = [:]
    private let measuring = NSTextField(wrappingLabelWithString: "")
    var font: NSFont { .systemFont(ofSize: 13 * ReadingStyle.scale(parent.textScale)) }
    static let maximumLines = 6
    init(_ parent: ReadOnlyGrid) { self.parent = parent }
    /// Natural widths avoid wrapping short values; minimum widths keep whole
    /// words and most of each heading visible before horizontal scrolling.
    /// Unwrapped widths give values priority over a long heading's full text.
    func measure() {
      let headingFont = grid?.tableColumns.first?.headerCell.font ?? .systemFont(ofSize: 11)
      func width(_ text: Substring, _ font: NSFont) -> CGFloat {
        ceil((String(text) as NSString).size(withAttributes: [.font: font]).width)
      }
      let content = parent.content
      ideal = []
      unwrapped = []
      minimum = []
      for (index, heading) in content.headings.enumerated() {
        var natural: CGFloat = 0
        var word: CGFloat = 0
        for row in content.rows.prefix(300) where row.indices.contains(index) {
          let text = content.plain(row[index]).prefix(1000)
          for line in text.split(whereSeparator: \.isNewline) {
            natural = max(natural, width(line, font))
          }
          for token in text.split(whereSeparator: \.isWhitespace) {
            word = max(word, width(token, font))
          }
        }
        let title = width(Substring(content.plain(heading)), headingFont) + 18
        let best = min(320, max(48, natural + 10, title))
        let floor = min(best, max(48, min(word + 10, 150), min(title, 96)))
        ideal.append(best)
        unwrapped.append(min(best, max(floor, natural + 10)))
        minimum.append(floor)
      }
      fittedWidth = -1
      userResized = false
      heights = [:]
    }
    /// Message tables hug their contents, then wrap toward whole-word minimums
    /// before scrolling. Original files fill the viewer, then keep natural widths
    /// and scroll like a spreadsheet instead of wrapping every column.
    func widths(available: CGFloat) -> [CGFloat] {
      let space = available - overhead()
      let total = ideal.reduce(0, +)
      if total <= space {
        guard !parent.inline, total > 0 else { return ideal }
        return ideal.map { $0 + ($0 / total) * (space - total) }
      }
      guard parent.inline else { return ideal }
      let values = unwrapped.reduce(0, +)
      let (upper, lower) = values <= space ? (ideal, unwrapped) : (unwrapped, minimum)
      let floor = lower.reduce(0, +)
      guard floor < space else { return lower }
      let flexible = zip(upper, lower).reduce(0) { $0 + $1.0 - $1.1 }
      return zip(upper, lower).map { $0.1 + ($0.0 - $0.1) / flexible * (space - floor) }
    }
    /// Inset rows add leading/trailing margins and spacing between columns.
    func overhead() -> CGFloat {
      guard let grid, grid.numberOfColumns > 0 else { return 0 }
      let columns = grid.tableColumns.reduce(0) { $0 + $1.width }
      return grid.rect(ofColumn: grid.numberOfColumns - 1).maxX - columns
        + grid.rect(ofColumn: 0).minX
    }
    func contentWidth(_ widths: [CGFloat]) -> CGFloat { ceil(widths.reduce(0, +) + overhead()) }
    func fit(_ available: CGFloat) {
      guard let grid, !userResized, abs(available - fittedWidth) > 0.5,
        grid.tableColumns.count == ideal.count
      else { return }
      fittedWidth = available
      var widths = widths(available: available).map { floor($0) }
      // Whole points can leave a remainder; give it to the widest column.
      let space = floor(available - overhead())
      if let widest = widths.indices.max(by: { widths[$0] < widths[$1] }),
        widths.reduce(0, +) < space, widths.reduce(0, +) > space - CGFloat(widths.count)
      {
        widths[widest] += space - widths.reduce(0, +)
      }
      applyingWidths = true
      for (column, width) in zip(grid.tableColumns, widths) { column.width = width }
      applyingWidths = false
      updateHeights()
    }
    /// Refitting must not animate rows through intermediate, truncated heights.
    func updateHeights() {
      guard let grid else { return }
      heights = [:]
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0
        grid.noteHeightOfRows(withIndexesChanged: IndexSet(parent.content.rows.indices))
      }
    }
    func rowHeight(_ row: Int, widths: [CGFloat]) -> CGFloat {
      guard parent.content.rows.indices.contains(row) else { return 30 }
      var height: CGFloat = 0
      measuring.font = font
      for (index, value) in parent.content.rows[row].enumerated() where index < widths.count {
        measuring.stringValue = String(parent.content.plain(value).prefix(1024))
        let size = measuring.cell!.cellSize(
          forBounds: NSRect(
            x: 0, y: 0, width: floor(widths[index]) - PreviewCell.leading, height: 10_000))
        height = max(height, size.height)
      }
      let line = ceil(font.ascender - font.descender + font.leading)
      let text = ceil(min(height, line * CGFloat(Self.maximumLines) + 4))
      return max(30, text + 2 * PreviewCell.padding)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { parent.content.rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      guard let column = tableColumn.flatMap({ Int($0.identifier.rawValue) }),
        parent.content.rows.indices.contains(row), parent.content.rows[row].indices.contains(column)
      else { return nil }
      let identifier = NSUserInterfaceItemIdentifier("preview-cell")
      let cell =
        tableView.makeView(withIdentifier: identifier, owner: self) as? PreviewCell
        ?? PreviewCell()
      cell.identifier = identifier
      let field = cell.field
      field.font = font
      let content = parent.content
      let value = content.rows[row][column]
      let destinations = content.links(row: row, column: column)
      let links = parent.content.linkRanges(value)
      cell.show(parent.content.plain(value), links: links)
      field.toolTip = String(parent.content.plain(value).prefix(4000))
      field.setAccessibilityLabel(
        (tableColumn?.title.isEmpty == false ? tableColumn!.title : "Value") + ", row \(row + 1)"
          + (destinations.isEmpty ? "" : ", source link"))
      field.setAccessibilityValue(parent.content.plain(value))
      let context = ", row \(row + 1), " + (tableColumn?.title ?? "Value")
      field.setAccessibilityRole(destinations.count == 1 ? .link : .staticText)
      field.setAccessibilityCustomActions(
        destinations.map { link in
          NSAccessibilityCustomAction(name: "Open " + link.title + context) { [weak self] in
            guard let self, self.parent.content == content else { return false }
            self.parent.open(link.url)
            return true
          }
        } + [
          NSAccessibilityCustomAction(name: "Read full row \(row + 1)") { [weak self] in
            guard let self, self.parent.content == content else { return false }
            self.parent.inspect(row)
            return true
          }
        ])
      field.press =
        destinations.count == 1
        ? { [weak self] in
          guard let self, self.parent.content == content else { return false }
          self.parent.open(destinations[0].url)
          return true
        } : nil
      field.focusChanged = { [weak self] in
        guard let self, self.parent.content == content, let grid = self.grid else { return }
        grid.activeColumn = column
        grid.needsDisplay = true
        if !grid.isRowSelected(row) {
          grid.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
      }
      return cell
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
      if let height = heights[row] { return height }
      let height = rowHeight(row, widths: tableView.tableColumns.map(\.width))
      heights[row] = height
      return height
    }
    func tableViewSelectionDidChange(_ notification: Notification) { publishSelection() }
    func publishSelection() {
      grid?.needsDisplay = true
      let snapshot = parent.content
      let selected = grid?.selectedRow ?? -1
      let value = parent.content.rows.indices.contains(selected) ? selected : nil
      // Selection notifications also occur inside SwiftUI updates.
      DispatchQueue.main.async { [weak self] in
        guard let self, self.parent.content == snapshot, (self.grid?.selectedRow ?? -1) == selected
        else { return }
        self.parent.selected(value)
      }
    }
    func open(row: Int, column: Int) {
      guard parent.content.rows.indices.contains(row) else { return }
      let links = parent.content.links(row: row, column: column)
      if links.count == 1 { parent.open(links[0].url) } else { parent.inspect(row) }
    }
    func tableViewColumnDidResize(_ notification: Notification) {
      guard !applyingWidths else { return }
      // A person's column width stays until the displayed content changes.
      userResized = true
      updateHeights()
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
        parent.copied(
          "Copied \(grid.selectedRowIndexes.isEmpty ? parent.content.rows.count : grid.selectedRowIndexes.count) rows"
        )
      } catch { parent.failure(error.localizedDescription) }
    }
    /// A cell's one link opens on click. Several stay in the context menu, and
    /// Shift or Command clicks only change the selection.
    @objc func openClickedLink() {
      guard let grid, parent.content.rows.indices.contains(grid.clickedRow),
        parent.content.rows[grid.clickedRow].indices.contains(grid.clickedColumn),
        NSApp.currentEvent?.modifierFlags.intersection([.shift, .command]).isEmpty ?? true,
        parent.content.markdown || (NSApp.currentEvent?.clickCount ?? 0) >= 2
      else { return }
      let links = parent.content.links(row: grid.clickedRow, column: grid.clickedColumn)
      if links.count == 1 { parent.open(links[0].url) }
    }
    @objc func performMenu(_ item: NSMenuItem) { actions[item.tag]?() }
    func menu() -> NSMenu {
      actions = [:]
      let snapshot = parent.content
      let menu = NSMenu()
      func add(_ title: String, _ action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(performMenu), keyEquivalent: "")
        item.tag = actions.count
        item.target = self
        actions[item.tag] = { [weak self] in
          guard self?.parent.content == snapshot else { return }
          action()
        }
        menu.addItem(item)
      }
      if let row = grid?.selectedRow, parent.content.rows.indices.contains(row) {
        add("Read full row \(row + 1)") { [weak self] in self?.parent.inspect(row) }
      }
      add("Copy") { [weak self] in self?.copy(headings: false, csv: false) }
      add("Copy with headings") { [weak self] in self?.copy(headings: true, csv: false) }
      add("Copy as CSV") { [weak self] in self?.copy(headings: false, csv: true) }
      if let selected = grid?.selectedRowIndexes, !selected.isEmpty {
        let cells = parent.content.cells(selected: selected, headings: false)
        // Discover links from original markup rather than the copied plain labels.
        let links = selected.filter { parent.content.rows.indices.contains($0) }.flatMap { row in
          parent.content.rows[row].indices.flatMap { parent.content.links(row: row, column: $0) }
        }
        if !cells.isEmpty && !links.isEmpty { menu.addItem(.separator()) }
        for link in links {
          add("Open " + link.title) { [weak self] in self?.parent.open(link.url) }
        }
      }
      return menu
    }
  }
}
