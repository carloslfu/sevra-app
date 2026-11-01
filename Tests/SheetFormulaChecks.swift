import Foundation

@testable import SevraCore

func checkSheetFormulas(at root: URL) {
  func value(_ formula: String, _ cells: [String: SheetValue] = [:]) throws -> SheetValue {
    try SheetFormula.parse(formula).evaluate { cells[$0.name] ?? .blank }
  }
  func number(_ text: String) -> SheetValue { .number(Decimal(string: text)!) }
  check("the declared Excel subset follows Excel's blank, text and error rules") {
    try expect(try value("1+2*3") == number("7") && value("(1+2)*3") == number("9"))
    try expect(try value("-2+5") == number("3") && value("50%*200") == number("100"))
    try expect(try value("$A$1+A$1+$A1+A1", ["A1": number("2")]) == number("8"))
    try expect(try value("A1+1") == number("1"))
    try expect(try value("A1+1", ["A1": .text("x")]) == .error("#VALUE!"))
    try expect(try value("1/0") == .error("#DIV/0!") && value("1/A1") == .error("#DIV/0!"))
    let mixed: [String: SheetValue] = ["A1": number("1"), "A2": .text("x"), "A3": number("2")]
    try expect(try value("SUM(A1:A4)", mixed) == number("3"))
    try expect(try value("SUM(A2,A3,4)", mixed) == number("6"))
    try expect(try value("COUNT(A1:A4)", mixed) == number("2"))
    try expect(try value("AVERAGE(A1:A4)", mixed) == number("1.5"))
    try expect(try value("MIN(A1:A4)", mixed) == number("1") && value("MAX(A1:A4)", mixed) == number("2"))
    try expect(try value("AVERAGE(B1:B2)") == .error("#DIV/0!") && value("MAX(B1:B2)") == number("0"))
    let broken: [String: SheetValue] = ["A1": .error("#REF!"), "A2": number("1")]
    try expect(try value("SUM(A1:A2)", broken) == .error("#REF!"))
    try expect(try value("COUNT(A1:A2)", broken) == number("1"))
    try expect(try value("A1+1/0", broken) == .error("#REF!"))
    try expect(try value("IF(A1>1,B1,1/0)", ["A1": number("2"), "B1": number("7")]) == number("7"))
    try expect(try value("IF(A1,1,2)") == number("2") && value("IF(A1<>0,1,2)") == number("2"))
    let compared: [String: SheetValue] = ["A1": .text("n/a"), "A2": .text("N/A"), "A3": number("9")]
    try expect(try value("IF(A1>A3,1,0)", compared) == number("1"))
    try expect(try value("IF(A1=A3,1,0)", compared) == number("0"))
    try expect(try value("IF(A1=A2,1,0)", compared) == number("1"))
    try expect(try value("IF(B1=0,1,0)", compared) == number("1"))
    try expect(try value("IF(A1<>B1,1,0)", compared) == number("1"))
    try expect(try value("IF(A1>1/0,1,0)", compared) == .error("#DIV/0!"))
    try expect(try value("IF(A1,1,0)", compared) == .error("#VALUE!"))
    try expect(try value("ROUND(2.345,2)") == number("2.35"))
    try expect(try value("ROUND(-2.345,2)") == number("-2.35"))
    try expect(try value("ROUND(1250,-2)") == number("1300"))
    // Excel drops the fraction of the digits and takes any count of them.
    try expect(try value("ROUND(1.234,2.5)") == number("1.23") && value("ROUND(1.5,0.5)") == number("2"))
    try expect(try value("ROUND(1.2345,30)") == number("1.2345") && value("ROUND(5,-30)") == number("0"))
    try expect(try value("ROUND(1.23456,10/3)") == number("1.235"))
    try expect(try value("ROUND(1234.5678,-10/3)") == number("1000"))
    try expect(try value("ROUND(1234.5678,-1/3)") == number("1235"))
    try expect(try value("COUNT(1/A1,5)") == number("1"))
    // A value too small to divide is an error, never a number that cannot be written.
    let tiny: [String: SheetValue] = ["A1": number("1E-128")]
    try expect(try value("A1%", tiny) == .error("#NUM!"))
    try expect(try value("AVERAGE(A1,B1)", tiny.merging(["B1": number("0")]) { a, _ in a }) == .error("#NUM!"))
    do {
      _ = try SheetFormula.parse("1E-999")
      throw SevraError("test", "Accepted a number past the decimal range")
    } catch is SheetFormulaGap {}
  }
  check("sheet references keep quoted names and ranges share their sheet") {
    let quoted = try SheetFormula.parse("'It''s here'!B2+Other!C3").references
    try expect(quoted.map(\.sheet) == ["It's here", "Other"] && quoted.map(\.name) == ["B2", "C3"])
    let range = try SheetFormula.parse("SUM(Other!A1:B2)").references
    try expect(range.count == 4 && range.allSatisfy { $0.sheet == "Other" })
  }
  check("formulas outside the subset say what they use") {
    let gaps = [
      "VLOOKUP(A1,B1:C2,2,FALSE)": "Uses VLOOKUP,", "_xlfn.XLOOKUP(A1,B1:B2,C1:C2)": "Uses XLOOKUP,",
      "\"a\"&B1": "text values", "A1^2": "powers", "A1&B1": "joined text",
      "SUM(A:A)": "whole-column", "SUM(Sheet2!A:A)": "whole-column", "TRUE": "TRUE and FALSE",
      "A1>B1": "TRUE and FALSE", "Rate*2": "the name Rate", "A1:B2": "outside a function",
      "IF(A1,1)": "without both results", "[1]Sheet1!A1": "another file",
      "'[1]Other sheet'!A1": "another file", "#REF!+1": "missing",
      "SUM(A1:A6000,B1:B6000)": "more than", "SUM(C1:A1)": "a range it cannot read",
    ]
    for (formula, expected) in gaps {
      do {
        _ = try SheetFormula.parse(formula)
        throw SevraError("test", "Accepted " + formula)
      } catch let gap as SheetFormulaGap {
        try expect(gap.reason.contains(expected), formula + ": " + gap.reason)
      }
    }
    do {
      _ = try SheetFormula.parse(String(repeating: "(", count: 40) + "1")
      throw SevraError("test", "Accepted deep nesting")
    } catch let gap as SheetFormulaGap {
      try expect(gap.reason.contains("nested"))
    }
  }
  check("a shared formula moves relative parts only") {
    try expect(SheetFormula.shifted("$A2*B$1+C3", columns: 1, rows: 2) == "$A4*C$1+D5")
    try expect(SheetFormula.shifted("'A1'!B2&\"C3\"", columns: 1, rows: 1) == "'A1'!C3&\"C3\"")
    try expect(SheetFormula.shifted("LOG10(A1)", columns: 0, rows: 1) == "LOG10(A2)")
    try expect(SheetFormula.shifted("A1", columns: 0, rows: -1) == "#REF!")
  }
  check("recalculated numbers keep Excel's 15 digits and ignore binary noise") {
    try expect(SheetFormula.text(Decimal(1) / Decimal(3)) == "0.333333333333333")
    try expect(SheetFormula.text(Decimal(string: "1234567890123456789")!) == "1234567890123460000")
    try expect(SheetFormula.same(number("0.3"), as: "0.30000000000000004"))
    try expect(!SheetFormula.same(number("0.3"), as: "0.31"))
    try expect(SheetFormula.same(.text("Bolts"), as: "Bolts"))
    try expect(SheetFormula.same(.error("#DIV/0!"), as: "#DIV/0!"))
  }
  check("saved numbers can carry an exponent, as spreadsheets write very large and small ones") {
    try expect(SheetFormula.same(number("-0.0000405000033210003"), as: "-4.05000033210003E-005"))
    try expect(SheetFormula.same(number("100000000000000000000"), as: "1E+20"))
    try expect(SheetValue(stored: "1.5E-5") == number("0.000015"))
    try expect(SheetValue(stored: "1E5x") == .text("1E5x"))
    try expect(SheetValue(stored: "E5") == .text("E5"))
    try expect(SheetValue(stored: "1E+999") == .text("1E+999"))
    // Text that only looks like a number keeps its saved form instead of recalculating.
    try expect(!SheetFormula.same(number("123"), as: "00123") && !SheetFormula.same(number("7.2"), as: "7.20"))
    // Noise never moves a saved cell at import, and any digit Excel would show moves it later.
    try expect(!SheetFormula.moved(number("20000000000000"), from: "20000000000000"))
    try expect(SheetFormula.moved(number("20000000000001"), from: "20000000000000"))
    try expect(SheetFormula.moved(number("1000000.00000001"), from: "1000000"))
    try expect(!SheetFormula.moved(number("0.3"), from: "0.30000000000000004"))
    try expect(!SheetFormula.moved(number("7.2"), from: "7.20"))
  }
  check("an edit and its recalculated cells are one row version, and Undo restores both") {
    let book = try Workbook.create(at: root.appendingPathComponent("Formulas.sevra"), title: "Lines")
    let source = try book.addItem(category: "source", kind: "note", title: "Budget.xlsx")
    let table = try book.createDataset(
      title: "Lines",
      columns: ["c1", "c2", "c3"].map { Column(id: $0, title: $0) },
      rows: [
        ["c1": .string("2"), "c2": .string("3"), "c3": .string("6")],
        ["c1": .string(""), "c2": .string(""), "c3": .string("6")],
      ], sourceID: source.id)
    let sheet = ImportedSheet(
      name: "Lines", rows: [["2", "3", "6"], ["", "", "6"]], rowNumbers: [1, 2], notes: [],
      formulas: ["C1": "A1*B1", "C2": "SUM(C1:C1)"])
    try book.recordSheetFormulas(sourceID: source.id, sheets: [sheet], tables: [table])
    let first = try book.rows(table.id)[0]
    var values = first.data.object
    values["c1"] = .string("4")
    let change = try book.editRows(table.id, edits: [RowEdit(id: first.id, values: values)])
    var rows = try book.rows(table.id)
    try expect(rows[0].version == 2 && rows[0].data["c3"].text == "12")
    try expect(rows[1].data["c3"].text == "12" && change.items[0].id == rows[0].id)
    try refuses("calculated_cell") {
      var typed = rows[0].data.object
      typed["c3"] = .string("1")
      _ = try book.editRows(table.id, edits: [RowEdit(id: rows[0].id, values: typed)])
    }
    _ = try book.undoTableChange(change.id)
    rows = try book.rows(table.id)
    try expect(rows[0].data["c1"].text == "2" && rows[0].data["c3"].text == "6")
    try expect(rows[1].data["c3"].text == "6")
    try expect(try book.verify()["ok"] == .bool(true))
  }
  func imported(_ name: String, _ rows: [[String]], _ formulas: [String: String]) throws
    -> (book: Workbook, table: Dataset)
  {
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    let source = try book.addItem(category: "source", kind: "note", title: name + ".xlsx")
    let ids = rows[0].indices.map { "c\($0 + 1)" }
    let table = try book.createDataset(
      title: name, columns: ids.map { Column(id: $0, title: $0) },
      rows: rows.map { row in Dictionary(uniqueKeysWithValues: zip(ids, row.map(Value.string))) },
      sourceID: source.id)
    let sheet = ImportedSheet(
      name: name, rows: rows, rowNumbers: Array(1...rows.count), notes: [], formulas: formulas)
    try book.recordSheetFormulas(sourceID: source.id, sheets: [sheet], tables: [table])
    return (book, table)
  }
  func edit(_ book: Workbook, _ table: Dataset, row: Int, _ cells: [String: String]) throws {
    let current = try book.rows(table.id)[row]
    var values = current.data.object
    for (column, text) in cells { values[column] = .string(text) }
    _ = try book.editRows(table.id, edits: [RowEdit(id: current.id, values: values)])
  }
  check("a Unique column does not hide the edited row from recalculation") {
    let (book, table) = try imported(
      "Unique", [["a", "2", "4"], ["b", "3", "6"], ["t", "", "10"]],
      ["C1": "B1*2", "C2": "B2*2", "C3": "SUM(C1:C2)"])
    var columns = table.columns
    columns[0].unique = true
    try book.setColumns(table.id, columns: columns)
    try edit(book, table, row: 0, ["c2": "5"])
    let rows = try book.rows(table.id)
    try expect(rows[0].data["c3"].text == "10" && rows[2].data["c3"].text == "16")
  }
  check("a reference past the sheet stays blank and a removed formula column writes nothing") {
    let (book, table) = try imported(
      "Removed", [["2", "4", "5", "note"], ["3", "6", "7", "note"]],
      ["B1": "A1*2", "B2": "A2*2", "C1": "B1+1+Z1", "C2": "SUM(E2:F2)+B2+1"])
    try expect(try book.rows(table.id)[0].version == 1 && book.sheetFormulaReport(table.id)?.saved == 0)
    try edit(book, table, row: 0, ["c1": "5"])
    try expect(try book.rows(table.id)[0].data["c3"].text == "11")
    try expect(try book.rows(table.id)[1].data["c3"].text == "7")
    try book.setColumns(table.id, columns: table.columns.filter { $0.id != "c2" })
    var rows = try book.rows(table.id)
    try expect(rows[0].data["c3"].text == "#REF!" && rows[1].data["c3"].text == "#REF!")
    let versions = rows.map(\.version)
    // The row stays editable, and an edit elsewhere rewrites nothing that did not move.
    var values = Workbook.activeValues(rows[1].data.object, columns: try book.dataset(table.id).columns)
    values["c4"] = .string("other")
    _ = try book.editRows(table.id, edits: [RowEdit(id: rows[1].id, values: values)])
    rows = try book.rows(table.id)
    try expect(rows[0].version == versions[0] && rows[1].version == versions[1] + 1)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("a reviewed table change respects formula cells from draft to Undo") {
    let (book, table) = try imported(
      "Reviewed", [["2", "4"], ["", "4"]], ["B1": "A1*2", "B2": "SUM(B1:B1)"])
    let row = try book.rows(table.id)[0]
    try refuses("calculated_cell") {
      _ = try book.proposeTableEdit(table.id, edits: [RowEdit(id: row.id, values: ["c2": .string("9")])])
    }
    let proposal = try book.proposeTableEdit(
      table.id, edits: [RowEdit(id: row.id, values: ["c1": .string("5")])])
    let accepted = try book.accept(proposal.id)
    try expect(try book.rows(table.id).map { $0.data["c2"].text } == ["10", "10"])
    _ = try book.undoItem(accepted.id, actor: .human("Owner"))
    try expect(try book.rows(table.id).map { $0.data["c2"].text } == ["4", "4"])
  }
  check("an edited row keeps lineage to the formula plan that recalculated it") {
    let (book, table) = try imported("Lineage", [["2", "4"]], ["B1": "A1*2"])
    try edit(book, table, row: 0, ["c1": "3"])
    let row = try book.rows(table.id)[0]
    try expect(row.data["c2"].text == "6")
    try expect(
      try book.db.scalar(
        "SELECT count(*) FROM lineage l JOIN items i ON i.id=l.parent WHERE l.child=? AND i.kind=?",
        [.string(row.id), .string(Workbook.sheetFormulaKind)]
      ).int == 1)
  }
  check("a saved date keeps formulas that read it on their saved value") {
    let (book, table) = try imported(
      "Dates", [["2024-01-01T00:00:00Z", "1", "3"], ["3", "", "6"]],
      ["B1": "IF(A1>45000,1,0)", "C1": "A2*1", "C2": "A2*2"])
    let report = try book.sheetFormulaReport(table.id)
    try expect(report?.recalculating == 2 && report?.saved == 1)
    try expect(report?.savedCells.first?.reason?.contains("the date in A1") == true)
  }
  check("a fill too large to list keeps every formula in the file on its saved value") {
    let book = try Workbook.create(at: root.appendingPathComponent("Fills.sevra"), title: "Fills")
    let source = try book.addItem(category: "source", kind: "note", title: "Budget.xlsx")
    let table = try book.createDataset(
      title: "Lines", columns: ["c1", "c2"].map { Column(id: $0, title: $0) },
      rows: [["c1": .string("2"), "c2": .string("4")]], sourceID: source.id)
    let sheet = ImportedSheet(
      name: "Lines", rows: [["2", "4"]], rowNumbers: [1], notes: [],
      formulas: ["B1": "A1*2"], formulaKinds: ["*": "array"])
    try book.recordSheetFormulas(sourceID: source.id, sheets: [sheet], tables: [table])
    let report = try book.sheetFormulaReport(table.id)
    try expect(report?.recalculating == 0 && report?.saved == 1)
    try expect(report?.savedCells.first?.reason?.contains("too large to follow") == true)
    try expect(!(try book.hasRecalculatingFormulas(table.id)))
  }
  check("a formula list past its bound keeps a sample and the exact count") {
    var plan = SheetFormulaPlan(
      sheets: [.init(name: "A", dataset: "a", width: 1, rows: [], logical: [])],
      cells: (1...100_001).map { .init(sheet: 0, cell: "A\($0)", formula: "1", reason: nil) })
    plan.capList()
    try expect(plan.cells.count == 200 && plan.unlisted == [99_801])
    try expect(plan.cells.allSatisfy { $0.reason?.contains("too many") == true })
  }
}
