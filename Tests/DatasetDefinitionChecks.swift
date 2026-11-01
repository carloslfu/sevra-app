import Foundation

@testable import SevraCore

func checkDatasetDefinitions(at root: URL) {
  func fixture(_ name: String, columns: [Column]? = nil, rows: [[String: Value]]? = nil) throws
    -> (Workbook, Dataset)
  {
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    let source = try book.addItem(category: "source", kind: "note", title: "Original input")
    return (
      book,
      try book.createDataset(
        title: "Orders",
        columns: columns ?? [
          .init(id: "sku", title: "SKU"), .init(id: "cost", title: "Cost", type: "decimal"),
        ], rows: rows ?? [["sku": .string("0012"), "cost": .string("2.40")]], sourceID: source.id)
    )
  }
  check("removed columns survive active row edits and exact definition restoration") {
    let (book, table) = try fixture("DefinitionRestore")
    let original = try book.rows(table.id)[0]
    let first = try book.datasetDefinition(table.id)
    let second = try book.updateDatasetDefinition(
      table.id, expectedVersion: first.version,
      expectedDefinitionID: first.id, title: "Current orders", columns: [table.columns[0]],
      actor: .human("Definition test"))
    try expect(try book.rows(table.id)[0].data == .object(["sku": .string("0012")]))
    let edit = try book.editRow(original.id, values: ["sku": .string("0013")])
    try expect(try book.lineage(edit.id).contains { $0["parent"].text == second.sourceID })
    try expect(edit.data["cost"].text == "2.40")
    let scoped = book.calculatedValues(
      edit,
      columns: [
        table.columns[0],
        .init(id: "unbound", title: "Unbound", type: "decimal", formula: "cost*2"),
      ])
    try expect(scoped["cost"] == nil && scoped["unbound"]?.text.hasPrefix("#ERROR:") == true)
    try expect(try book.item(original.id).data["sku"].text == "0012")
    let restored = try book.restoreDatasetDefinition(
      table.id, definitionID: first.id,
      expectedVersion: second.version, expectedDefinitionID: second.id,
      actor: .human("History test"))
    try expect(restored.id != first.id && restored.version == 3 && restored.previousID == second.id)
    try expect(restored.title == table.title && restored.columns == table.columns)
    try expect(
      try book.rows(table.id)[0].data == .object(["sku": .string("0013"), "cost": .string("2.40")]))
    let evidence = try book.item(restored.sourceID)
    try expect(
      evidence.category == "source" && evidence.data["attribution"]["kind"].text == "human")
    try expect(try book.lineage(evidence.id).contains { $0["parent"].text == second.sourceID })
    let replay = try book.reconstruct(
      to: root.appendingPathComponent("DefinitionRestoredReplay.sevra"))
    try expect(try replay.db.authorityDigest() == book.db.authorityDigest())
  }
  check("schema edits compare causal bases and exact retries return the saved definition") {
    let (book, table) = try fixture("DefinitionRetry")
    let other = try Workbook(book.url)
    let first = try book.datasetDefinition(table.id)
    let actor = ChangeActor.human("Editor")
    let second = try book.updateDatasetDefinition(
      table.id, expectedVersion: 1,
      expectedDefinitionID: first.id, title: "Changed", token: "definition-once", actor: actor)
    try expect(
      try other.updateDatasetDefinition(
        table.id, expectedVersion: 1,
        expectedDefinitionID: first.id, title: "Changed", token: "definition-once", actor: actor
      ).id == second.id)
    try refuses("stale_schema") {
      _ = try other.updateDatasetDefinition(
        table.id, expectedVersion: 1,
        expectedDefinitionID: first.id, title: "Losing draft")
    }
    try refuses("stale_schema") {
      _ = try other.updateDatasetDefinition(
        table.id, expectedVersion: 2,
        expectedDefinitionID: first.id, title: "Wrong identity")
    }
    try refuses("idempotency") {
      _ = try other.updateDatasetDefinition(
        table.id, expectedVersion: 1,
        expectedDefinitionID: first.id, title: "Changed", token: "definition-once",
        actor: .programmatic("Other"))
    }
    try refuses("idempotency") {
      _ = try other.updateDatasetDefinition(
        table.id, expectedVersion: 1,
        expectedDefinitionID: first.id, title: "Other", token: "definition-once", actor: actor)
    }
    try expect(try book.datasetDefinitions(table.id).map(\.id) == [second.id, first.id])
    try expect(try book.datasetDefinitions(table.id, beforeVersion: 2).map(\.id) == [first.id])
    try refuses("idempotency") {
      _ = try ChangeAttribution.$actor.withValue(.human("Different inherited actor")) {
        try other.updateDatasetDefinition(
          table.id, expectedVersion: 1,
          expectedDefinitionID: first.id, title: "Changed", token: "definition-once")
      }
    }
  }
  check("required and exact decimal uniqueness changes refuse atomically") {
    let (book, table) = try fixture(
      "DefinitionConstraints",
      rows: [
        ["sku": .string("A"), "cost": .string("1")],
        ["sku": .string("B"), "cost": .string("1.00")],
      ])
    let before = try book.db.authorityDigest()
    var columns = table.columns
    columns[1].unique = true
    try refuses("unique") { try book.setColumns(table.id, columns: columns) }
    try expect(try book.db.authorityDigest() == before)
    columns[1].unique = nil
    columns[0].required = true
    columns[0].unique = true
    try book.setColumns(table.id, columns: columns)
    let rows = try book.rows(table.id)
    let current = try book.db.authorityDigest()
    try refuses("required") { _ = try book.editRow(rows[0].id, values: ["sku": .null]) }
    try refuses("unique") { _ = try book.editRow(rows[0].id, values: ["sku": .string("B")]) }
    try expect(try book.db.authorityDigest() == current)
    let swap = try book.editRows(
      table.id,
      edits: [
        .init(id: rows[0].id, values: ["sku": .string("B"), "cost": .string("1")]),
        .init(id: rows[1].id, values: ["sku": .string("A"), "cost": .string("1.00")]),
      ])
    try expect(try book.rows(table.id).map { $0.data["sku"].text } == ["B", "A"])
    _ = try book.undoTableChange(swap.id)
    try expect(try book.rows(table.id).map { $0.data["sku"].text } == ["A", "B"])
    columns[1].formula = "1"
    columns[1].unique = true
    try refuses("column_constraint") { try book.setColumns(table.id, columns: columns) }
    let replay = try book.reconstruct(
      to: root.appendingPathComponent("DefinitionConstraintsReplay.sevra"))
    try expect(try replay.verify()["ok"] == .bool(true))
  }
  check("nullable unique columns preserve multiple unknowns and distinct exact values") {
    let (book, table) = try fixture(
      "DefinitionNullable",
      columns: [
        .init(id: "n", title: "Number", type: "decimal", unique: true)
      ],
      rows: [
        ["n": .null], [:], ["n": .string("9007199254740992")], ["n": .string("9007199254740993")],
      ])
    try expect(try book.rows(table.id).count == 4)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("archive hides discovery and blocks edits while retained views and restoration work") {
    let (book, table) = try fixture("DefinitionArchive")
    let first = try book.datasetDefinition(table.id)
    let archived = try book.updateDatasetDefinition(
      table.id, expectedVersion: 1,
      expectedDefinitionID: first.id, archived: true)
    try expect(try book.datasets().isEmpty && book.dataset(table.id).archived)
    let row = try book.rows(table.id)[0]
    try refuses("archived_dataset") { _ = try book.editRow(row.id, values: row.data.object) }
    try refuses("archived_dataset") {
      _ = try book.proposeTableEdit(
        table.id, edits: [.init(id: row.id, values: ["sku": .string("new")])])
    }
    _ = try book.restoreDatasetDefinition(
      table.id, definitionID: first.id,
      expectedVersion: archived.version, expectedDefinitionID: archived.id)
    try expect(try book.datasets().count == 1 && book.rows(table.id)[0].id == row.id)
  }
  check("a row edit changes the columns it names, and clearing one takes an explicit null") {
    let (book, table) = try fixture("PartialEdit")
    let row = try book.rows(table.id)[0]
    let changed = try book.editRow(row.id, values: ["cost": .string("3")])
    try expect(changed.data == .object(["sku": .string("0012"), "cost": .string("3")]))
    let cleared = try book.editRow(changed.id, values: ["cost": .null])
    try expect(try book.rows(table.id)[0].data["sku"].text == "0012" && cleared.data["cost"] == .null)
    try refuses("empty_edit") { _ = try book.editRow(cleared.id, values: [:]) }
    try refuses("column") { _ = try book.editRow(cleared.id, values: ["missing": .string("1")]) }
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("a table filter reads the cells, not the row titles and column IDs every row shares") {
    let (book, table) = try fixture(
      "RowFilter",
      rows: [
        ["sku": .string("Café-12"), "cost": .string("1")],
        ["sku": .string("beta"), "cost": .string("2")],
      ])
    for query in ["Orders", "row", "sku", "cost"] {
      try expect(try book.rows(table.id, query: query).isEmpty)
      try expect(try book.filteredRowCount(table.id, query: query) == 0)
    }
    try expect(try book.rows(table.id, query: "cafe 12").count == 1)
    try expect(try book.filteredRowCount(table.id, query: "BET") == 1)
    // A term of marks alone, such as an emoji's variation selector, asks for nothing.
    try expect(try book.filteredRowCount(table.id, query: "beta ⚠️") == 1)
    let base = try book.datasetDefinition(table.id)
    _ = try book.updateDatasetDefinition(
      table.id, expectedVersion: base.version, expectedDefinitionID: base.id,
      columns: [table.columns[1]])
    try expect(try book.rows(table.id, query: "beta").isEmpty)
  }
  check("an archived table refuses Undo of a row edit, as it refuses the edit") {
    let (book, table) = try fixture("ArchivedUndo")
    let edit = try book.editRow(try book.rows(table.id)[0].id, values: ["cost": .string("3")])
    let base = try book.datasetDefinition(table.id)
    let archived = try book.updateDatasetDefinition(
      table.id, expectedVersion: base.version, expectedDefinitionID: base.id, archived: true)
    try refuses("archived_dataset") { _ = try book.undoItem(edit.id) }
    _ = try book.restoreDatasetDefinition(
      table.id, definitionID: base.id, expectedVersion: archived.version,
      expectedDefinitionID: archived.id)
    try expect(try book.undoItem(edit.id).data["cost"].text == "2.40")
  }
  check("a quotient keeps 38 digits wherever it is read, and an exact result stays exact") {
    let (book, table) = try fixture(
      "Quotients",
      columns: [
        .init(id: "a", title: "A", type: "decimal"), .init(id: "b", title: "B", type: "decimal"),
        .init(id: "ratio", title: "Ratio", type: "decimal", formula: "a/b"),
        .init(id: "more", title: "More", type: "decimal", formula: "ratio+1000"),
        .init(id: "mean", title: "Mean", type: "decimal", formula: "AVERAGE(a,b,1)"),
      ],
      rows: [
        ["a": .string("22"), "b": .string("7")], ["a": .string("1"), "b": .string("8")],
      ])
    func cells(_ book: Workbook) throws -> [[String]] {
      try book.tablePage(table.id).values.map { row in
        ["ratio", "more", "mean"].map { row[$0]?.text ?? "" }
      }
    }
    let quotient = [
      "3.1428571428571428571428571428571428571", try cells(book)[0][1], "10",
    ]
    try expect(quotient[1].hasPrefix("1003.142857142857") && Numbers.decimal(quotient[1]) > 1003)
    try expect(
      try cells(book)
        == [quotient, ["0.125", "1000.125", "3.3333333333333333333333333333333333333"]])
    try expect(try book.cellValue(table.id, address: "C1") == quotient[0])
    try expect(try Numbers.calculate("10/4") == "2.5" && Numbers.calculate("2.5*2") == "5")
    try refuses("division_by_zero") { _ = try Numbers.calculate("1/0") }
    let row = try book.rows(table.id)[0]
    let edit = try book.editRows(table.id, edits: [.init(id: row.id, values: ["a": .string("5"), "b": .string("3")])])
    try expect(try cells(book)[0][0] == "1.6666666666666666666666666666666666667")
    _ = try book.undoTableChange(edit.id)
    try expect(try cells(book)[0] == quotient && cells(Workbook(book.url))[0] == quotient)
    let export = root.appendingPathComponent("Quotients.csv")
    try book.exportCSV(table.id, to: export)
    try expect(try String(contentsOf: export, encoding: .utf8).contains(quotient[1]))
  }
  check("a formula cannot add or compare two units, and a plain number takes the other's") {
    let (book, table) = try fixture(
      "Units",
      columns: [
        .init(id: "usd", title: "USD", type: "decimal", unit: "USD"),
        .init(id: "eur", title: "EUR", type: "decimal", unit: "EUR"),
        .init(id: "fee", title: "Fee", type: "decimal", unit: "USD"),
        .init(id: "same", title: "Same", type: "decimal", formula: "usd*2+fee+1", unit: "USD"),
        .init(id: "rate", title: "Rate", type: "decimal", formula: "usd/eur+1"),
        .init(id: "added", title: "Added", type: "decimal", formula: "usd+eur"),
        .init(id: "compared", title: "Compared", type: "decimal", formula: "IF(usd>eur,1,0)"),
        .init(id: "cells", title: "Cells", type: "decimal", formula: "SUM(A1:B1)"),
      ],
      rows: [["usd": .string("4"), "eur": .string("2"), "fee": .string("1")]])
    let row = try book.tablePage(table.id).values[0]
    try expect(row["same"]?.text == "10" && row["rate"]?.text == "3")
    for column in ["added", "compared", "cells"] {
      try expect(row[column]?.text.hasPrefix("#ERROR: This formula mixes") == true)
    }
    try refuses("unit_mismatch") { _ = try book.cellValue(table.id, address: "F1") }
  }
  check("retained formulas cannot silently bind to removed or reordered columns") {
    let (book, table) = try fixture(
      "DefinitionBindings",
      columns: [
        .init(id: "a", title: "A", type: "decimal"), .init(id: "b", title: "B", type: "decimal"),
        .init(id: "total", title: "Total", type: "decimal", formula: "IF(0,a,SUM(A1:B1))"),
      ], rows: [["a": .string("2"), "b": .string("3")]])
    let before = try book.db.authorityDigest()
    try refuses("formula_dependency") {
      try book.setColumns(
        table.id, columns: [table.columns[1], table.columns[0], table.columns[2]])
    }
    try refuses("formula_dependency") {
      try book.setColumns(table.id, columns: [table.columns[1], table.columns[2]])
    }
    try expect(try book.db.authorityDigest() == before)
    var total = table.columns[2]
    total.formula = "b*2"
    try book.setColumns(table.id, columns: [table.columns[1], total])
    try expect(
      try book.calculatedValues(book.rows(table.id)[0], columns: book.dataset(table.id).columns)[
        "total"]?.text == "6")
  }
  check("definition publication failures and cancelled attempts leave no partial history") {
    let (book, table) = try fixture("DefinitionFault")
    let first = try book.datasetDefinition(table.id)
    let before = try book.db.authorityDigest()
    _ = try faultSQL(
      book,
      "CREATE TRIGGER definition_fault BEFORE INSERT ON committed_changes BEGIN SELECT RAISE(ABORT,'definition rollback'); END;"
    )
    try refuses("database") {
      _ = try book.updateDatasetDefinition(
        table.id, expectedVersion: 1, expectedDefinitionID: first.id,
        columns: [table.columns[0]], token: "schema-retry")
    }
    try expect(try book.db.authorityDigest() == before)
    _ = try faultSQL(book, "DROP TRIGGER definition_fault;")
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses("cancelled") {
      _ = try book.updateDatasetDefinition(
        table.id, expectedVersion: 1, expectedDefinitionID: first.id,
        columns: [table.columns[0]], token: "schema-retry", cancellation: cancelled)
    }
    _ = try book.updateDatasetDefinition(
      table.id, expectedVersion: 1, expectedDefinitionID: first.id,
      columns: [table.columns[0]], token: "schema-retry")
    try expect(
      try book.datasetDefinitions(table.id).count == 2 && book.verify()["ok"] == .bool(true))
  }
  check("interrupted intake never resumes new rows into a changed definition") {
    let (book, _) = try fixture("DefinitionPartialImport")
    let source = try book.addItem(category: "source", kind: "note", title: "Large input")
    let columns = [Column(id: "n", title: "Number", type: "decimal")]
    let values = (0..<1001).map { ["n": Value.string(String($0))] }
    let cancel = Cancellation()
    try refuses("cancelled") {
      _ = try book.importDataset(
        title: "Partial", columns: columns, rows: values, sourceID: source.id,
        cancellation: cancel, progress: { _, _ in cancel.cancel() })
    }
    let table = try book.datasets().first { $0.title == "Partial" }!
    try expect(table.rowCount == 1000)
    try book.setColumns(table.id, columns: columns + [.init(id: "note", title: "Note")])
    let before = try book.db.authorityDigest()
    try refuses("import_changed") {
      _ = try book.importDataset(
        title: "Partial", columns: columns, rows: values, sourceID: source.id)
    }
    try expect(try book.db.authorityDigest() == before && book.dataset(table.id).rowCount == 1000)
  }
  check("malformed saved schema identities and fractional versions refuse without a decode trap") {
    let (book, table) = try fixture("DefinitionMalformed")
    let raw = try Database(book.url.appendingPathComponent("workbook.sqlite"))
    try raw.execute(
      "UPDATE column_versions SET version=1.5 WHERE dataset_id=?", [.string(table.id)])
    try refuses("managed_schema") { _ = try book.datasetDefinition(table.id) }
    try refuses("managed_schema") { _ = try book.verify() }
    try raw.execute("UPDATE datasets SET storage_version=1.5 WHERE id=?", [.string(table.id)])
    try refuses("managed_schema") { _ = try book.datasetSchema(table.id) }
  }
}
