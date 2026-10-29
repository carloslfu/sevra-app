import AppKit
import SevraCore

@testable import SevraTableUI

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
  if try !condition() { throw SevraError("table_ui_check", message) }
}

actor ReadGate {
  private var result: CheckedContinuation<TablePage, Error>?
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private var started = false
  func read() async throws -> TablePage {
    try await withCheckedThrowingContinuation { continuation in
      result = continuation
      started = true
      for waiter in waiting { waiter.resume() }
      waiting = []
    }
  }
  func waitForRead() async {
    if started { return }
    await withCheckedContinuation { waiting.append($0) }
  }
  func finish(_ page: TablePage) {
    result?.resume(returning: page)
    result = nil
  }
  func fail() {
    result?.resume(throwing: SevraError("old", "Old query failed"))
    result = nil
  }
}

@main struct Checks {
  @MainActor static func main() async {
    do {
      try await run()
      print("PASS all native table checks")
      exit(0)
    } catch {
      fputs("\(error)\n", stderr)
      exit(1)
    }
  }
  @MainActor static func run() async throws {
    _ = NSApplication.shared
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sevra-table-ui-" + identifier() + ".sevra")
    defer { try? FileManager.default.removeItem(at: url) }
    let demo = try Demo.create(at: url)
    let book = try Workbook(url)
    let id = demo["datasetID"].text
    let firstPage = try book.tablePage(id)
    let sortedPage = try book.tablePage(id, sort: "supplier")
    try expect(
      firstPage.rows.map(\.id) == sortedPage.rows.reversed().map(\.id), "Fixture must reorder rows")
    var submissions: [String] = []
    var failures: [String] = []
    var selected: [String] = []
    var selectedColumn = -1
    func view(_ page: TablePage) -> NativeTable {
      NativeTable(
        page: page,
        onEdit: { edit, revision in
          submissions.append(edit.id)
          do { _ = try book.editRows(id, edits: [edit], expectedRevision: revision) } catch {
            failures.append(error.localizedDescription)
          }
        },
        onSelect: { rows, c in
          selected = rows.map(\.logicalID)
          selectedColumn = c
        },
        onSort: { _, _ in }, onCopy: {}, onPaste: {})
    }
    let initial = view(firstPage)
    let coordinator = initial.makeCoordinator()
    let table = GridTable()
    table.allowsMultipleSelection = true
    table.delegate = coordinator
    table.dataSource = coordinator
    initial.update(table, coordinator: coordinator)
    table.selectRowIndexes([0], byExtendingSelection: false)
    table.activeColumn = 2
    table.selectionAction?()
    try expect(
      selectedColumn == 2, "Clicking a different column in the same row lost the paste target")
    let originalCell =
      coordinator.tableView(table, viewFor: table.tableColumns[1], row: 0) as! NSTextField
    coordinator.controlTextDidBeginEditing(
      Notification(name: NSControl.textDidBeginEditingNotification, object: originalCell))
    view(sortedPage).update(table, coordinator: coordinator)
    try expect(table.selectedRow == 1, "Sorting moved the logical selection")
    originalCell.stringValue = "99"
    coordinator.controlTextDidEndEditing(
      Notification(name: NSControl.textDidEndEditingNotification, object: originalCell))
    try expect(
      submissions == [firstPage.rows[0].id] && failures.isEmpty, "Edit was redirected after sorting"
    )
    let updated = try book.item(firstPage.rows[0].logicalID)
    try expect(updated.data["quantity"].text == "99", "Intended row was not edited")
    try expect(
      try book.item(firstPage.rows[1].logicalID) == firstPage.rows[1], "Neighbor row was changed")
    coordinator.controlTextDidEndEditing(
      Notification(name: NSControl.textDidEndEditingNotification, object: originalCell))
    try expect(submissions.count == 1, "Duplicate AppKit end notification resubmitted an edit")
    print(
      "PASS sort preserves logical selection and original edit version; repeated end notification is harmless"
    )

    let current = try book.tablePage(id)
    view(current).update(table, coordinator: coordinator)
    try expect(table.selectedRow == 0, "Correction lost logical selection")
    let staleCell =
      coordinator.tableView(table, viewFor: table.tableColumns[1], row: 0) as! NSTextField
    let other = try Workbook(url)
    var values = current.rows[0].data.object
    values["quantity"] = .string("7")
    _ = try other.editRow(current.rows[0].id, values: values)
    let external = try book.tablePage(id)
    view(external).update(table, coordinator: coordinator)
    let revisionBefore = try book.revision()
    let itemsBefore = try book.items()
    staleCell.stringValue = "42"
    coordinator.controlTextDidEndEditing(
      Notification(name: NSControl.textDidEndEditingNotification, object: staleCell))
    try expect(
      failures.count == 1 && failures[0].contains("changed"), "Stale edit was not reported")
    try expect(
      try book.revision() == revisionBefore && book.items() == itemsBefore,
      "Stale edit mutated evidence")
    try expect(
      try book.item(current.rows[0].logicalID).data["quantity"].text == "7",
      "Concurrent correction lost")
    print(
      "PASS refresh keeps logical selection; concurrent edits refuse the captured stale revision without changing data"
    )

    let cancelCell =
      coordinator.tableView(table, viewFor: table.tableColumns[1], row: 0) as! NSTextField
    cancelCell.stringValue = "23"
    coordinator.controlTextDidEndEditing(
      Notification(
        name: NSControl.textDidEndEditingNotification,
        object: cancelCell, userInfo: ["NSTextMovement": NSTextMovement.cancel.rawValue]))
    try expect(
      submissions.count == 2 && cancelCell.stringValue == "7", "Escape committed a cell edit")
    let filtered = try book.tablePage(id, query: "Cedar")
    view(filtered).update(table, coordinator: coordinator)
    try expect(table.selectedRow == -1, "Filtering selected a neighboring record")
    coordinator.publishSelection(table)
    try expect(selected.isEmpty, "Filtered selection remained in the conversation context")
    print("PASS cancelled editing does not write and filtered-out selection clears")

    var columns = external.dataset.columns
    columns[3].formula = "C2"
    try book.setColumns(id, columns: columns)
    let formulaPage = try book.tablePage(id)
    view(formulaPage).update(table, coordinator: coordinator)
    let unchangedRowID = formulaPage.rows[0].id
    var neighborValues = formulaPage.rows[1].data.object
    neighborValues["unit_cost"] = .string("3.10")
    _ = try other.editRow(formulaPage.rows[1].id, values: neighborValues)
    let formulaChanged = try book.tablePage(id)
    try expect(
      formulaChanged.rows[0].id == unchangedRowID
        && formulaChanged.values[0]["total"]?.text == "3.1",
      "Formula snapshot did not include a referenced-row change")
    view(formulaChanged).update(table, coordinator: coordinator)
    let formulaCell =
      coordinator.tableView(table, viewFor: table.tableColumns[3], row: 0) as! NSTextField
    try expect(
      formulaCell.stringValue == "3.1" && !formulaCell.isEditable, "Calculated cell did not refresh"
    )
    table.activeColumn = 1
    try book.setColumns(id, columns: [columns[1], columns[0], columns[2], columns[3]])
    view(try book.tablePage(id)).update(table, coordinator: coordinator)
    try expect(table.activeColumn == 0, "Active column followed a screen slot instead of its ID")
    print(
      "PASS referenced-row formulas refresh without changing the visible row version; active column retains identity"
    )

    func query(
      sort: String? = nil, descending: Bool = false, revision: Int = 1,
      offset: Int = 0, filter: String = "", workbook: URL = url, dataset: String = id
    ) -> TableQuery {
      TableQuery(
        workbook: workbook, dataset: dataset, revision: revision, offset: offset,
        filter: filter, sort: sort, descending: descending)
    }
    try expect(
      Set([
        query(), query(sort: "supplier"), query(descending: true), query(revision: 2),
        query(offset: 200), query(filter: "Oak"),
        query(workbook: url.appendingPathComponent("other")),
        query(dataset: "other"),
      ]).count == 8, "A query-changing input was omitted from task identity")
    let loader = TablePageLoader()
    let oldGate = ReadGate()
    let old = Task { await loader.load(query()) { try await oldGate.read() } }
    await oldGate.waitForRead()
    try expect(loader.loading, "An in-flight table read did not show loading")
    await loader.load(query(sort: "supplier")) { sortedPage }
    await oldGate.finish(firstPage)
    await old.value
    try expect(
      loader.page?.rows == sortedPage.rows && loader.loadedQuery == query(sort: "supplier"),
      "Old slow query replaced latest sort")
    try expect(!loader.loading, "Completed table read left a spinner")
    let failureGate = ReadGate()
    let failed = Task { await loader.load(query()) { try await failureGate.read() } }
    await failureGate.waitForRead()
    await loader.load(query(sort: "supplier")) { sortedPage }
    await failureGate.fail()
    await failed.value
    try expect(
      loader.failure == nil && loader.page?.rows == sortedPage.rows,
      "Old error replaced current success")
    let cancelledGate = ReadGate()
    let cancelled = Task { await loader.load(query()) { try await cancelledGate.read() } }
    await cancelledGate.waitForRead()
    cancelled.cancel()
    await cancelledGate.finish(firstPage)
    await cancelled.value
    try expect(
      loader.page?.rows == sortedPage.rows && loader.failure == nil,
      "Cancelled read published a result")
    await loader.load(query()) { throw SevraError("current", "Current query failed") }
    try expect(
      loader.failure?.contains("Current query failed") == true, "Latest failure was hidden")
    await loader.load(query(dataset: "different-table")) {
      throw SevraError("missing", "Missing table")
    }
    try expect(
      loader.page == nil && loader.loadedQuery == nil,
      "Failed table navigation retained another table's data")
    try expect(!loader.loading && loader.failure != nil, "Failed table read did not settle")
    await loader.load(query()) { firstPage }
    try expect(
      loader.page?.rows == firstPage.rows && loader.failure == nil, "Retry did not recover")
    let detachedGate = ReadGate()
    let detached = Task {
      await loader.load(query(sort: "supplier")) { try await detachedGate.read() }
    }
    await detachedGate.waitForRead()
    loader.cancel()
    try expect(!loader.loading, "Leaving the table left its loading state active")
    await detachedGate.finish(sortedPage)
    await detached.value
    try expect(
      loader.page?.rows == firstPage.rows, "Read after detachment replaced the retained page")
    print(
      "PASS deterministic out-of-order reads, stale errors and cancellation cannot replace the latest page"
    )
    try expect(try book.verify()["ok"] == .bool(true), "Workbook integrity failed")
    try await checkTableUpdateSession()
    try checkTableClipboard()
  }
}
