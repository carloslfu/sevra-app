import AppKit
import SevraCore
import SwiftUI

final class GridTable: NSTableView {
  var copyAction: (() -> Void)?, pasteAction: (() -> Void)?, selectionAction: (() -> Void)?
  var undoAction: (() -> Void)?, redoAction: (() -> Void)?
  var activeColumn = 0
  override func mouseDown(with event: NSEvent) {
    let c = column(at: convert(event.locationInWindow, from: nil))
    if c >= 0 { activeColumn = c }
    super.mouseDown(with: event)
    selectionAction?()
    if event.clickCount == 2 { beginCellEditing() }
  }
  /// A click on a read-only cell's text in a selected row goes to the cell, not `mouseDown`.
  override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?)
    -> Bool
  {
    if let event, event.type == .leftMouseDown {
      let point = convert(event.locationInWindow, from: nil)
      let c = column(at: point)
      if c >= 0, c != activeColumn, isRowSelected(row(at: point)) {
        activeColumn = c
        selectionAction?()
      }
    }
    return super.validateProposedFirstResponder(responder, for: event)
  }
  func beginCellEditing() {
    guard selectedRow >= 0,
      let field = view(atColumn: activeColumn, row: selectedRow, makeIfNecessary: true)
        as? NSTextField,
      field.isEditable
    else { return }
    window?.makeFirstResponder(field)
    field.selectText(nil)
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
    table.rowHeight = 30
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
      "Select rows with Shift or Command. Command-C copies selected rows on this page. Double-click an editable cell or press Return to edit. Paste starts in the last clicked column."
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
      || coordinator.parent.editable != editable
    coordinator.parent = self
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
    for (index, column) in table.tableColumns.enumerated() {
      column.isEditable = editable && columns[index].formula == nil && !page.dataset.archived
    }
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
      cell.isBordered = false
      cell.backgroundColor = .clear
      cell.font = .systemFont(ofSize: 13)
      cell.isEditable =
        parent.editable && c.formula == nil && !parent.page.dataset.archived && !recalculates
      cell.isSelectable = true
      cell.delegate = self
      cell.identifier = .init(c.id)
      cell.stringValue = value
      cell.setAccessibilityLabel(
        c.title + ", row \(parent.page.offset+row+1)"
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
      selectionGeneration += 1
      parent.onSelect([cell.row], c)
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
      selectionGeneration += 1
      let generation = selectionGeneration
      let selected = table.selectedRowIndexes.compactMap { index in
        parent.page.rows.indices.contains(index) ? parent.page.rows[index] : nil
      }
      let column = table.activeColumn
      if deferred {
        Task { @MainActor [weak self] in
          guard let self, self.selectionGeneration == generation else { return }
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
  init(row: Item, column: String, revision: Int, value: String) {
    self.row = row
    self.column = column
    self.revision = revision
    self.originalValue = value
    super.init(frame: .zero)
  }
  required init?(coder: NSCoder) { fatalError("Bound cells are created from a table snapshot.") }
}
