import AppKit

@testable import SevraCore
@testable import SevraTableUI

/// A cell that recalculates reads normally and takes no typing. A saved value reads quieter
/// and says why, on the cell itself and to accessibility.
@MainActor func checkExcelFormulaCells() throws {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-excel-cells-" + identifier() + ".sevra")
  defer { try? FileManager.default.removeItem(at: url) }
  let book = try Workbook.create(at: url, title: "Cells")
  let source = try book.addItem(category: "source", kind: "note", title: "Budget.xlsx")
  let table = try book.createDataset(
    title: "Lines", columns: ["c1", "c2", "c3", "c4"].map { Column(id: $0, title: $0) },
    rows: [["c1": .string("2"), "c2": .string("3"), "c3": .string("6"), "c4": .string("3")]],
    sourceID: source.id)
  try book.recordSheetFormulas(
    sourceID: source.id,
    sheets: [
      ImportedSheet(
        name: "Lines", rows: [["2", "3", "6", "3"]], rowNumbers: [1], notes: [],
        formulas: ["C1": "A1*B1", "D1": "VLOOKUP(A1,A1:B1,2,FALSE)"])
    ], tables: [table])
  let page = try book.tablePage(table.id)
  let view = NativeTable(
    page: page, onEdit: { _, _ in }, onSelect: { _, _ in }, onSort: { _, _ in }, onCopy: {},
    onPaste: {})
  let coordinator = view.makeCoordinator()
  let grid = GridTable()
  grid.delegate = coordinator
  grid.dataSource = coordinator
  view.update(grid, coordinator: coordinator)
  func cell(_ column: Int) -> NSTextField {
    coordinator.tableView(grid, viewFor: grid.tableColumns[column], row: 0) as! NSTextField
  }
  try expect(cell(0).isEditable && cell(0).toolTip == nil, "An input cell changed.")
  try expect(
    !cell(2).isEditable && cell(2).toolTip == "=A1*B1"
      && cell(2).accessibilityHelp() == "Calculated from =A1*B1",
    "A recalculating cell accepted typing or lost its formula.")
  try expect(
    cell(3).isEditable && cell(3).textColor == .secondaryLabelColor
      && cell(3).toolTip?.contains("Uses VLOOKUP") == true
      && cell(3).accessibilityHelp()?.contains("not recalculated") == true,
    "A saved value did not say so.")
  try expect(
    page.formulaReport?.recalculating == 1 && page.formulaReport?.saved == 1,
    "The page lost its formula summary.")

  // Clicking a read-only cell's text in the selected row still moves the selected cell.
  var selected: [Int] = []
  let tracked = NativeTable(
    page: page, onEdit: { _, _ in }, onSelect: { _, column in selected.append(column) },
    onSort: { _, _ in }, onCopy: {}, onPaste: {})
  let selection = tracked.makeCoordinator()
  let clicked = GridTable(frame: NSRect(x: 0, y: 0, width: 800, height: 200))
  clicked.delegate = selection
  clicked.dataSource = selection
  tracked.update(clicked, coordinator: selection)
  clicked.selectRowIndexes([0], byExtendingSelection: false)
  let target = NSPoint(x: clicked.rect(ofColumn: 2).midX, y: clicked.rect(ofRow: 0).midY)
  let click = NSEvent.mouseEvent(
    with: .leftMouseDown, location: clicked.convert(target, to: nil), modifierFlags: [],
    timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
  _ = clicked.validateProposedFirstResponder(
    selection.tableView(clicked, viewFor: clicked.tableColumns[2], row: 0) as! NSTextField,
    for: click)
  try expect(selected.last == 2, "A click on a read-only cell left another column selected.")
}
