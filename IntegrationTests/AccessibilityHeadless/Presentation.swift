import Foundation
import SevraCore
import SevraPreviewUI
import SevraTableUI

func presentationChecks(_ root: URL, _ suite: inout Suite) {
  suite.check("A1 focused paste edits exact row/column, rejects stale revision and preserves Undo")
  {
    let book = try Workbook.create(at: root.appendingPathComponent("Paste.sevra"), title: "Paste")
    let source = try book.addItem(category: "source", kind: "note", title: "Original")
    let table = try book.createDataset(
      title: "Costs",
      columns: [
        .init(id: "name", title: "Name"), .init(id: "cost", title: "Cost", type: "decimal"),
        .init(id: "twice", title: "Twice", type: "decimal", formula: "cost*2"),
      ],
      rows: [
        ["name": .string("Bolt"), "cost": .string("4")],
        ["name": .string("Nut"), "cost": .string("8")],
      ], sourceID: source.id)
    let page = try book.tablePage(table.id, sort: "name", descending: true)
    let selected = Set([page.rows[0].logicalID])
    let column = TableCellNavigation.column(
      identity: "cost", columns: page.dataset.columns.map(\.id))
    let edits = try TableClipboard.edits(
      cells: [[.string("12")]], page: page, selection: selected, column: column)
    try expect(
      edits[0].id == page.rows[0].id && edits[0].values["name"] == page.rows[0].data["name"],
      "Paste keeps exact sorted row and other cells")
    let changed = try book.editRows(table.id, edits: edits, expectedRevision: page.revision)
    let current = try book.tablePage(table.id, sort: "name", descending: true)
    try expect(
      current.values[0]["cost"] == .string("12") && current.values[0]["twice"]?.text == "24",
      "Pasted target recalculates")
    try refuses("stale_revision") {
      _ = try book.editRows(table.id, edits: edits, expectedRevision: page.revision)
    }
    try refuses("calculated_cell") {
      _ = try TableClipboard.edits(
        cells: [[.string("99")]], page: current, selection: selected, column: 2)
    }
    _ = try book.undoTableChange(changed.id)
    try expect(
      try book.tablePage(table.id, sort: "name", descending: true).values[0]["cost"]
        == page.values[0]["cost"], "Undo restores original value")
  }
  suite.check(
    "A2 shared table preserves exact decimals, empty/unknown/false/zero and original sources"
  ) {
    let first = PreviewTableContent.source("version-1", title: "Original row 1")!
    let table = PreviewTableContent.evidence(
      headings: ["Cost (USD)", "Empty", "Unknown", "Flag", "Zero"],
      rows: [[.string("9007199254740993.01"), .string(""), .null, .bool(false), .number(0)]],
      rowIDs: ["row-1"], sources: [[first]])
    try expect(
      table.headings == ["Cost (USD)", "Empty", "Unknown", "Flag", "Zero", "Sources"],
      "Headings and unit")
    try expect(
      table.rows[0] == ["9007199254740993.01", "Empty", "Unknown", "No", "0", "Original row 1"],
      "Exact scalar alternatives")
    try expect(
      table.rowIDs == ["row-1"] && table.links(row: 0, column: 5) == [first], "Exact source binding"
    )
    try expect(
      ConversationLinkTarget(first.url) == .evidence(id: "version-1", locator: nil),
      "Source resolves to exact item")
    try expect(PreviewTableContent.source("bad/id", title: "Bad") == nil, "Reject path injection")
  }
  suite.check("A2 row identities survive reorder; duplicate/ragged/aggregate results stay safe") {
    let a = PreviewTableContent(headings: ["Name"], rows: [["Bolt"], ["Nut"]])
    let b = PreviewTableContent(headings: ["Name"], rows: [["Nut"], ["Bolt"]])
    try expect(a.rowIDs[0] == b.rowIDs[1], "Data identity follows reordered row")
    let duplicates = PreviewTableContent(
      headings: ["Name"], rows: [["Bolt"], ["Bolt"]], rowIDs: ["same", "same"])
    try expect(Set(duplicates.rowIDs).count == 2, "Duplicate identities disambiguated")
    let table = PreviewTableContent.evidence(
      headings: ["Nested"], rows: [[.object(["quantity": .number(0)])], []],
      rowIDs: ["one", "two"], sources: [])
    try expect(
      table.sourceColumn == nil && table.rows[0][0].contains("quantity"),
      "Complex values remain readable without invented source")
    try expect(
      table.links(row: 1, column: 0).isEmpty && table.links(row: -1, column: 99).isEmpty,
      "Ragged/invalid access is bounded")
  }
  suite.check("A3 repeated fields include line, required/unit/constraints and only their own error")
  {
    let parameter: Value = .object([
      "id": .string("quantity"), "label": .string("Quantity"), "type": .string("decimal"),
      "required": .bool(true), "unit": .string("kg"), "min": .string("0.5"), "max": .string("20"),
    ])
    let path: [Value] = [.string("lines"), .number(1), .string("quantity")]
    let issue: Value = .object([
      "path": .array(path), "message": .string("Enter a positive quantity."),
    ])
    let own = FormFieldPresentation(
      parameter: parameter, help: "Net weight", context: "Delivery, Line 2", issues: [issue],
      path: path)
    try expect(
      own.accessibleTitle == "Delivery, Line 2, Quantity, Required, kg", "Complete control label")
    try expect(
      own.help.contains("Minimum: 0.5") && own.help.contains("Maximum: 20")
        && own.help.contains("Error: Enter a positive quantity."), "Constraint/error association")
    let other = FormFieldPresentation(
      parameter: parameter, context: "Delivery, Line 1", issues: [issue],
      path: [.string("lines"), .number(0), .string("quantity")])
    try expect(
      other.issues.isEmpty && !other.help.contains("Error:"),
      "Error must not leak to same-named other line")
    try expect(
      formFieldValue("0", parameter: parameter) == .string("0")
        && formFieldValue("", parameter: parameter) == .string(""), "Zero differs from empty")
    var optional = parameter.object
    optional["required"] = .bool(false)
    try expect(
      formFieldValue("", parameter: .object(optional)) == .null, "Empty optional number is missing")
  }
  suite.check("A3 actual workbook validation issues reach field presentation") {
    let book = try Workbook.create(at: root.appendingPathComponent("Form.sevra"), title: "Form")
    let quantity: Value = .object([
      "id": .string("q"), "label": .string("Quantity"), "type": .string("decimal"),
      "required": .bool(true), "min": .string("1"),
    ])
    let flag: Value = .object([
      "id": .string("flag"), "label": .string("Confirmed"), "type": .string("boolean"),
      "required": .bool(true),
    ])
    let definition = try book.saveApplicationDefinition(
      logicalID: UUID().uuidString,
      content: .object([
        "kind": .string("function"), "title": .string("Quantity"),
        "description": .string("Synthetic"), "parameters": .array([quantity, flag]),
        "payload": .object(["expression": .string("q*2"), "calls": .array([])]),
      ]))
    let issues = try book.applicationInputIssues(
      definition.id, arguments: .object(["q": .string("0"), "flag": .bool(false)]))
    let field = FormFieldPresentation(parameter: quantity, issues: issues)
    try expect(!field.issues.isEmpty && field.help.contains("Error:"), "Core issue is connected")
    try expect(
      FormFieldPresentation(parameter: flag, issues: issues).issues.isEmpty,
      "False is supplied, not missing")
    let date = FormFieldPresentation(
      parameter: .object(["id": .string("date"), "label": .string("Date"), "type": .string("date")])
    )
    try expect(
      date.help.contains("YYYY-MM-DD") && !date.accessibleTitle.contains("Required"),
      "Date format and optional state")
  }
  suite.check("A5 chart labels/scope, missing values and exact alternative agree") {
    let book = try Workbook.create(at: root.appendingPathComponent("Chart.sevra"), title: "Chart")
    let source = try book.addItem(category: "source", kind: "note", title: "Quotes")
    let table = try book.createDataset(
      title: "Quotes",
      columns: [
        .init(id: "name", title: "Supplier"),
        .init(id: "price", title: "Unit price", type: "decimal", unit: "USD"),
      ],
      rows: [
        ["name": .string("A"), "price": .string("9007199254740993.01")],
        ["name": .string("B"), "price": .null], ["name": .string("C"), "price": .string("0")],
      ], sourceID: source.id)
    let data = try book.componentData(
      .init(type: "chart", title: "Quote chart", datasetID: table.id, x: "name", y: "price"))
    let chart = ChartReadingPresentation(data, x: "name", y: "price")
    try expect(
      chart.xTitle == "Supplier" && chart.yTitle == "Unit price USD", "Actual columns and units")
    try expect(
      chart.points.count == 2 && chart.summary == "2 plotted rows of 3. Unit price USD",
      "Omitted unknowns and total scope")
    let exact = PreviewTableContent.evidence(
      headings: ["Price (USD)"], rows: data.rows.map { [$0.values["price"] ?? .null] },
      rowIDs: data.rows.map(\.id), sources: [])
    try expect(
      exact.rows.contains(["9007199254740993.01"]) && exact.rows.contains(["Unknown"]),
      "Alternative preserves decimals and missing values")
    let absent = ChartReadingPresentation(data, x: nil, y: "absent")
    try expect(
      absent.points.isEmpty && absent.yTitle == "Value", "Missing column never invents zero")
    try expect(
      ChartReadingPresentation(data, x: "name", y: "price", unitOverride: "COP").yTitle
        == "Unit price COP", "Explicit component unit retained")
  }
  suite.check(
    "A9 direct source action, keyboard default and full-row alternative call exact destinations"
  ) {
    let link = PreviewTableContent.Link(
      title: "Quote A", url: URL(string: "sevra://item/original-a")!)
    let content = PreviewTableContent.evidence(
      headings: ["Cost"], rows: [[.string("12")]], rowIDs: ["row-a"], sources: [[link]])
    let actions = PreviewCellActions(content: content, row: 0, column: 1)
    var opened: [URL] = []
    var inspected: [Int] = []
    try expect(
      actions.singleSource && actions.primaryIndex == 0, "Single source keyboard/press path")
    try expect(
      actions.actions[0].title == "Open Quote A, row 1, Sources",
      "Action contains source/row/column context")
    try expect(
      actions.perform(
        0, current: content, open: { opened.append($0) }, inspect: { inspected.append($0) }),
      "Direct action executes")
    try expect(opened == [link.url] && inspected.isEmpty, "Exact destination")
    try expect(
      actions.perform(
        1, current: content, open: { opened.append($0) }, inspect: { inspected.append($0) })
        && inspected == [0], "Full-row alternate action")
  }
  suite.check(
    "A9 multiple/hostile links, stale actions and row selection cannot open a wrong source"
  ) {
    let content = PreviewTableContent(
      headings: ["Sources"],
      rows: [["[A](sevra://item/a) [B](sevra://item/b) [unsafe](javascript:alert(1))"]],
      markdown: true)
    let actions = PreviewCellActions(content: content, row: 0, column: 0)
    try expect(
      !actions.singleSource && actions.actions.count == 3 && actions.primaryIndex == 2,
      "Multiple sources offer exact actions and row detail")
    var opened: [URL] = []
    var inspected: [Int] = []
    _ = actions.perform(
      actions.primaryIndex!, current: content, open: { opened.append($0) },
      inspect: { inspected.append($0) })
    try expect(opened.isEmpty && inspected == [0], "Return does not choose an arbitrary source")
    let changed = PreviewTableContent(
      headings: ["Sources"], rows: [["[Other](sevra://item/other)"]], markdown: true)
    try expect(
      !actions.perform(
        0, current: changed, open: { opened.append($0) }, inspect: { inspected.append($0) })
        && opened.isEmpty, "Captured old action refuses current content")
    try expect(
      !actions.perform(
        99, current: content, open: { opened.append($0) }, inspect: { inspected.append($0) }),
      "Invalid action refuses")
    try expect(
      !PreviewCellActions.opensOnClick(markdown: false, clicks: 1, extendingSelection: false),
      "Structured single click only selects")
    try expect(
      PreviewCellActions.opensOnClick(markdown: false, clicks: 2, extendingSelection: false),
      "Explicit double click opens")
    try expect(
      !PreviewCellActions.opensOnClick(markdown: true, clicks: 2, extendingSelection: true),
      "Extended selection never opens")
  }
}
