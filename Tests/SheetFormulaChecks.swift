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
    try expect(try value("ROUND(1.5,0.5)") == .error("#NUM!"))
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
      sheets: [.init(name: "A", dataset: "a", rows: [], logical: [])],
      cells: (1...100_001).map { .init(sheet: 0, cell: "A\($0)", formula: "1", reason: nil) })
    plan.capList()
    try expect(plan.cells.count == 200 && plan.unlisted == [99_801])
    try expect(plan.cells.allSatisfy { $0.reason?.contains("too many") == true })
  }
}
