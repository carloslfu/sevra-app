import AppKit
import SevraCore
import SwiftUI

final class GridTable: NSTableView {
  var copyAction: (() -> Void)?, pasteAction: (() -> Void)?, selectionAction: (() -> Void)?
  var undoAction: (() -> Void)?, redoAction: (() -> Void)?
  var rowIdentities: [String] = []
  var activeRowID: String?
  var activeColumnID: String?
  var activeColumn: Int {
    get { tableColumns.firstIndex { $0.identifier.rawValue == activeColumnID } ?? 0 }
    set {
      activeColumnID =
        tableColumns.indices.contains(newValue)
        ? tableColumns[newValue].identifier.rawValue : nil
      needsDisplay = true
    }
  }
  var activeRow: Int {
    if let id = activeRowID, let row = rowIdentities.firstIndex(of: id), isRowSelected(row) {
      return row
    }
    return selectedRow
  }
  func focusCell(row: Int, column: Int) {
    guard rowIdentities.indices.contains(row), tableColumns.indices.contains(column) else { return }
    activeRowID = rowIdentities[row]
    activeColumn = column
    if !isRowSelected(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    selectionAction?()
    scrollRowToVisible(row)
    scrollColumnToVisible(column)
    needsDisplay = true
  }
  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let r = row(at: point)
    let c = column(at: point)
    if c >= 0 { activeColumn = c }
    if rowIdentities.indices.contains(r) { activeRowID = rowIdentities[r] }
    super.mouseDown(with: event)
    selectionAction?()
    needsDisplay = true
    if event.clickCount == 2 { beginCellEditing() }
  }
  func beginCellEditing() {
    let row = activeRow
    guard row >= 0,
      let field = view(atColumn: activeColumn, row: row, makeIfNecessary: true) as? NSTextField,
      field.isEditable
    else { return }
    focusCell(row: row, column: activeColumn)
    window?.makeFirstResponder(field)
    field.selectText(nil)
  }
  /// Arrows choose a column; Tab visits editable cells and leaves the grid at its boundary.
  @discardableResult func moveCell(_ delta: Int, editableOnly: Bool) -> Bool {
    guard numberOfRows > 0, numberOfColumns > 0 else { return false }
    let row = max(0, activeRow)
    if !editableOnly {
      if activeRow < 0 {
        focusCell(row: 0, column: activeColumn)
        return true
      }
      let column = activeColumn + delta
      guard tableColumns.indices.contains(column) else { return false }
      focusCell(row: row, column: column)
      return true
    }
    var next =
      activeRow < 0
      ? (delta > 0 ? 0 : numberOfRows * numberOfColumns - 1)
      : row * numberOfColumns + activeColumn + delta
    while (0..<(numberOfRows * numberOfColumns)).contains(next) {
      let r = next / numberOfColumns
      let c = next % numberOfColumns
      if let field = view(atColumn: c, row: r, makeIfNecessary: true) as? NSTextField,
        field.isEditable
      {
        selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
        focusCell(row: r, column: c)
        beginCellEditing()
        return true
      }
      next += delta
    }
    return false
  }
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard window?.firstResponder === self, activeRow >= 0, numberOfColumns > 0 else { return }
    NSColor.keyboardFocusIndicatorColor.setStroke()
    let ring = NSBezierPath(
      rect: frameOfCell(atColumn: activeColumn, row: activeRow).insetBy(dx: 1, dy: 1))
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
  @objc func copy(_ sender: Any?) { copyAction?() }
  @objc func paste(_ sender: Any?) { pasteAction?() }
  @objc func undo(_ sender: Any?) { undoAction?() }
  @objc func redo(_ sender: Any?) { redoAction?() }
  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
      if event.modifierFlags.contains(.shift) { redoAction?() } else { undoAction?() }
      return
    }
    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
      copyAction?()
      return
    }
    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
      pasteAction?()
      return
    }
    if event.keyCode == 36 || event.keyCode == 76 {
      beginCellEditing()
      return
    }
    let modifiers = event.modifierFlags.intersection([.command, .control, .option])
    if modifiers.isEmpty {
      if event.keyCode == 123 || event.keyCode == 124 {
        _ = moveCell(event.keyCode == 123 ? -1 : 1, editableOnly: false)
        return
      }
      if event.keyCode == 48,
        moveCell(event.modifierFlags.contains(.shift) ? -1 : 1, editableOnly: true)
      {
        return
      }
    }
    super.keyDown(with: event)
  }
}
public struct NativeTable: NSViewRepresentable {
  let page: TablePage
  let onEdit: (RowEdit, Int) -> Void
  let onSelect: ([Item], Int) -> Void
  let onSort: (String, Bool) -> Void
  let onCopy: () -> Void, onPaste: () -> Void
  let onUndo: (() -> Void)?, onRedo: (() -> Void)?
  let editable: Bool
  @AppStorage(ReadingStyle.preference) private var textScale = 1.0

  public init(
    page: TablePage, onEdit: @escaping (RowEdit, Int) -> Void,
    onSelect: @escaping ([Item], Int) -> Void, onSort: @escaping (String, Bool) -> Void,
    onCopy: @escaping () -> Void, onPaste: @escaping () -> Void,
    onUndo: (() -> Void)? = nil, onRedo: (() -> Void)? = nil, editable: Bool = true
  ) {
    self.page = page
    self.onEdit = onEdit
    self.onSelect = onSelect
    self.onSort = onSort
    self.onCopy = onCopy
    self.onPaste = onPaste
    self.onUndo = onUndo
    self.onRedo = onRedo
    self.editable = editable
  }
  public func makeCoordinator() -> Coordinator { Coordinator(self) }
  public func makeNSView(context: Context) -> NSScrollView {
    let table = GridTable()
    table.delegate = context.coordinator
    table.dataSource = context.coordinator
    table.rowHeight = 30 * ReadingStyle.scale(textScale)
    // Empty space must not resemble additional records in a full-height table.
    table.usesAlternatingRowBackgroundColors = false
    table.allowsMultipleSelection = true
    // Copy, paste and the active column all count in the table's own column order.
    table.allowsColumnReordering = false
    table.columnAutoresizingStyle = .noColumnAutoresizing
    table.headerView = NSTableHeaderView()
    table.gridStyleMask = [.solidHorizontalGridLineMask]
    table.setAccessibilityLabel("Working table")
    table.setAccessibilityHelp(
      "Select rows with Shift or Command. Command-C copies selected rows on this page. Left and Right choose a column. Return edits that cell. Tab and Shift-Tab visit editable cells. Paste starts in the active column shown below the table."
    )
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.documentView = table
    return scroll
  }
  public func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let table = scroll.documentView as? GridTable else { return }
    update(table, coordinator: context.coordinator)
  }
  func update(_ table: GridTable, coordinator: Coordinator) {
    let selectedIDs = Set(
      table.selectedRowIndexes.compactMap { index in
        coordinator.parent.page.rows.indices.contains(index)
          ? coordinator.parent.page.rows[index].logicalID : nil
      })
    let activeColumnID =
      table.tableColumns.indices.contains(table.activeColumn)
      ? table.tableColumns[table.activeColumn].identifier.rawValue : nil
    let columns = page.dataset.columns
    let columnsChanged = coordinator.columns != columns
    let rowsChanged = coordinator.rowIDs != page.rows.map(\.id)
    let changed =
      columnsChanged || rowsChanged || coordinator.revision != page.revision
      || coordinator.parent.editable != editable || coordinator.textScale != textScale
    coordinator.parent = self
    coordinator.textScale = textScale
    table.rowHeight = 30 * ReadingStyle.scale(textScale)
    table.copyAction = onCopy
    table.pasteAction = onPaste
    table.undoAction = onUndo
    table.redoAction = onRedo
    table.selectionAction = { [weak coordinator, weak table] in
      guard let coordinator, let table else { return }
      coordinator.publishSelection(table)
    }
    guard changed else { return }
    coordinator.updating = true
    defer { coordinator.updating = false }
    if columnsChanged {
      for column in table.tableColumns { table.removeTableColumn(column) }
      for c in columns {
        let column = NSTableColumn(identifier: .init(c.id))
        column.title = c.title
        column.headerToolTip = c.title
        column.isEditable = editable && c.formula == nil && !page.dataset.archived
        column.width = 160
        column.minWidth = 80
        if c.formula == nil {
          column.sortDescriptorPrototype = NSSortDescriptor(key: c.id, ascending: true)
        }
        table.addTableColumn(column)
      }
      table.activeColumn = columns.firstIndex { $0.id == activeColumnID } ?? 0
      coordinator.columns = columns
    }
    table.headerView?.frame.size.height = 24 * ReadingStyle.scale(textScale)
    for (index, column) in table.tableColumns.enumerated() {
      column.headerCell.font = .systemFont(ofSize: 11 * ReadingStyle.scale(textScale))
      column.isEditable = editable && columns[index].formula == nil && !page.dataset.archived
    }
    table.rowIdentities = page.rows.map(\.logicalID)
    if !table.rowIdentities.contains(table.activeRowID ?? "") { table.activeRowID = nil }
    coordinator.rowIDs = page.rows.map(\.id)
    coordinator.revision = page.revision
    table.reloadData()
    let selected = IndexSet(
      page.rows.indices.filter { selectedIDs.contains(page.rows[$0].logicalID) })
    table.selectRowIndexes(selected, byExtendingSelection: false)
    // NSViewRepresentable updates must not synchronously publish SwiftUI state.
    if !selectedIDs.isEmpty { coordinator.publishSelection(table, deferred: true) }
  }

  public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate
  {
    var parent: NativeTable
    var columns: [Column] = []
    var rowIDs: [String] = []
    var revision: Int?
    var textScale = 1.0
    var updating = false
    var selectionGeneration = 0
    init(_ parent: NativeTable) { self.parent = parent }
    public func numberOfRows(in tableView: NSTableView) -> Int { parent.page.rows.count }
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      guard let column = tableColumn,
        let c = parent.page.dataset.columns.first(where: { $0.id == column.identifier.rawValue }),
        parent.page.rows.indices.contains(row), parent.page.values.indices.contains(row)
      else { return nil }
      let value = parent.page.values[row][c.id]?.text ?? ""
      let formula = parent.page.formulas[parent.page.rows[row].logicalID]?[c.id]
      let recalculates = formula != nil && formula?.reason == nil
      let cell = BoundTableCell(
        row: parent.page.rows[row], column: c.id,
        revision: parent.page.revision, value: value)
      cell.focusChanged = { [weak self, weak tableView, weak cell] in
        guard let self, !self.updating, let table = tableView as? GridTable, let cell,
          let current = self.parent.page.rows.firstIndex(where: { $0.id == cell.row.id }),
          self.parent.page.revision == cell.revision,
          let column = self.parent.page.dataset.columns.firstIndex(where: { $0.id == cell.column })
        else { return }
        table.focusCell(row: current, column: column)
      }
      cell.isBordered = false
      cell.backgroundColor = .clear
      cell.font = .systemFont(ofSize: 13 * ReadingStyle.scale(textScale))
      cell.isEditable =
        parent.editable && c.formula == nil && !parent.page.dataset.archived && !recalculates
      cell.isSelectable = true
      cell.delegate = self
      cell.identifier = .init(c.id)
      cell.stringValue = value
      cell.setAccessibilityLabel(
        c.title + (c.unit.map { " (" + $0 + ")" } ?? "") + ", row \(parent.page.offset+row+1)"
          + (c.formula == nil ? "" : ": " + cell.stringValue))
      cell.setAccessibilityElement(true)
      if c.formula != nil {
        cell.setAccessibilityRole(.staticText)
        cell.setAccessibilityValue(cell.stringValue)
        cell.setAccessibilityHelp("Calculated from " + (c.formula ?? ""))
      } else if recalculates, let formula {
        cell.setAccessibilityRole(.staticText)
        cell.setAccessibilityValue(cell.stringValue)
        cell.setAccessibilityHelp("Calculated from =" + formula.formula)
        cell.toolTip = "=" + formula.formula
      } else if let reason = formula?.reason {
        // A saved value reads quieter than a current one, wherever it appears.
        cell.textColor = .secondaryLabelColor
        cell.setAccessibilityRole(.textField)
        cell.setAccessibilityHelp("Saved by Excel, not recalculated. " + reason)
        cell.toolTip = "Saved by Excel, not recalculated. " + reason
      } else {
        cell.setAccessibilityRole(.textField)
        cell.setAccessibilityHelp(
          parent.page.dataset.archived
            ? "Archived table, read only"
            : parent.editable
              ? "Double-click or press Return to edit"
              : "Read only while the table updates or another task runs")
      }
      return cell
    }
    public func controlTextDidBeginEditing(_ notification: Notification) {
      guard let cell = notification.object as? BoundTableCell,
        let c = parent.page.dataset.columns.firstIndex(where: { $0.id == cell.column })
      else { return }
      guard let table = cell.enclosingScrollView?.documentView as? GridTable,
        let row = parent.page.rows.firstIndex(where: { $0.id == cell.row.id }),
        parent.page.revision == cell.revision
      else { return }
      table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      table.focusCell(row: row, column: c)
    }
    public func control(
      _ control: NSControl, textView: NSTextView, doCommandBy command: Selector
    ) -> Bool {
      guard
        command == #selector(NSResponder.insertTab(_:))
          || command == #selector(NSResponder.insertBacktab(_:)),
        let cell = control as? BoundTableCell,
        let table = cell.enclosingScrollView?.documentView as? GridTable
      else { return false }
      let backwards = command == #selector(NSResponder.insertBacktab(_:))
      guard table.window?.makeFirstResponder(table) == true else { return true }
      if !table.moveCell(backwards ? -1 : 1, editableOnly: true) {
        if backwards {
          table.window?.selectPreviousKeyView(table)
        } else {
          table.window?.selectNextKeyView(table)
        }
      }
      return true
    }
    public func controlTextDidEndEditing(_ notification: Notification) {
      guard let cell = notification.object as? BoundTableCell else { return }
      if notification.userInfo?["NSTextMovement"] as? Int == NSTextMovement.cancel.rawValue {
        cell.stringValue = cell.originalValue
        return
      }
      guard !cell.submissionSent, cell.stringValue != cell.originalValue else { return }
      cell.submissionSent = true
      // Keep the version and revision that the user actually edited. A refresh
      // never redirects an edit to the row that now occupies the same screen slot.
      var values = cell.row.data.object
      values[cell.column] = cell.stringValue.isEmpty ? .null : .string(cell.stringValue)
      let edit = RowEdit(id: cell.row.id, values: values)
      let submit = parent.onEdit
      let revision = cell.revision
      if updating {
        Task { @MainActor in submit(edit, revision) }
      } else {
        submit(edit, revision)
      }
    }
    func publishSelection(_ table: GridTable, deferred: Bool = false) {
      guard !updating || deferred else { return }
      table.needsDisplay = true
      selectionGeneration += 1
      let generation = selectionGeneration
      let selected = table.selectedRowIndexes.compactMap { index in
        parent.page.rows.indices.contains(index) ? parent.page.rows[index] : nil
      }
      let column = table.activeColumn
      let revision = parent.page.revision
      let rowIDs = parent.page.rows.map(\.id)
      if deferred {
        Task { @MainActor [weak self] in
          guard let self, self.selectionGeneration == generation,
            self.parent.page.revision == revision, self.parent.page.rows.map(\.id) == rowIDs
          else { return }
          self.parent.onSelect(selected, column)
        }
      } else {
        parent.onSelect(selected, column)
      }
    }
    public func tableViewSelectionDidChange(_ notification: Notification) {
      guard !updating, let table = notification.object as? GridTable else { return }
      publishSelection(table)
    }
    public func tableView(
      _ tableView: NSTableView,
      sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
    ) {
      guard !updating else { return }
      if let sort = tableView.sortDescriptors.first, let key = sort.key {
        parent.onSort(key, !sort.ascending)
      }
    }
  }
}

/// AppKit may deliver an editing notification after a reload. Retain the
/// immutable binding on the field itself, independently of the current page.
final class BoundTableCell: NSTextField {
  let row: Item
  let column: String
  let revision: Int
  let originalValue: String
  var submissionSent = false
  var focusChanged: (() -> Void)?
  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { focusChanged?() }
    return accepted
  }
  override func setAccessibilityFocused(_ focused: Bool) {
    super.setAccessibilityFocused(focused)
    if focused { focusChanged?() }
  }
  init(row: Item, column: String, revision: Int, value: String) {
    self.row = row
    self.column = column
    self.revision = revision
    self.originalValue = value
    super.init(frame: .zero)
  }
  required init?(coder: NSCoder) { fatalError("Bound cells are created from a table snapshot.") }
}
