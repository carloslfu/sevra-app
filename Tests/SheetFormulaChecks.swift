import Foundation

@testable import SevraCore

func checkSheetFormulas(at root: URL) {
  check("Excel input ledgers grow, recalculate, reopen and Undo without shifting coordinates") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Growing-ledger.sevra"), title: "Ledger")
    let source = try book.addItem(category: "source", kind: "note", title: "Synthetic ledger.xlsx")
    let ledger = try book.createDataset(
      title: "Ledger", columns: [.init(id: "c1", title: "Amount")],
      rows: [["c1": .string("Amount")], ["c1": .string("3")]], sourceID: source.id)
    let totals = try book.createDataset(
      title: "Totals", columns: [.init(id: "c1", title: "Total")],
      rows: [["c1": .string("3")]], sourceID: source.id)
    try book.recordSheetFormulas(
      sourceID: source.id,
      sheets: [
        .init(
          name: "Ledger", rows: [["Amount"], ["3"]], rowNumbers: [1, 2], notes: [], formulas: [:]),
        .init(
          name: "Totals", rows: [["3"]], rowNumbers: [1], notes: [],
          formulas: ["A1": "SUM(Ledger!A2:A100)"]),
      ], tables: [ledger, totals])
    func insert(_ value: String) throws -> Value {
      try book.chatTableTransaction(
        ledger.id, expectedDefinitionID: ledger.definitionID,
        operations: [.object(["op": .string("insert"), "values": .object(["c1": .string(value)])])])
    }
    let first = try insert("7")
    try expect(try book.rows(totals.id)[0].data["c1"] == .string("10"))
    try expect(try Workbook(book.url).rows(totals.id)[0].data["c1"] == .string("10"))
    _ = try book.chatTableTransaction(
      ledger.id, expectedDefinitionID: ledger.definitionID,
      operations: [], undo: first["token"].text)
    try expect(try book.rows(totals.id)[0].data["c1"] == .string("3"))
    _ = try insert("11")
    let mapped = try book.sheetFormulaPlan(ledger.id)!.plan.sheets[0]
    try expect(mapped.rows == [1, 2, 3, 4] && mapped.appended?.count == 2)
    try expect(try book.rows(totals.id)[0].data["c1"] == .string("14"))
    let revision = try book.revision()
    try refuses("excel_row_growth") {
      _ = try book.chatTableTransaction(
        totals.id, expectedDefinitionID: totals.definitionID,
        operations: [.object(["op": .string("insert"), "values": .object(["c1": .string("99")])])])
    }
    try expect(try book.revision() == revision && book.rows(totals.id).count == 1)
    try expect(try book.verify()["ok"] == .bool(true))
    // Imported/copied saved state is untrusted. Reject a shortened identity map
    // before the appended-row lookup can index it or report misleading results.
    let retained = try book.sheetFormulaPlan(ledger.id)!
    var shortened = retained.plan
    shortened.sheets[0].logical.removeLast()
    var overflow = retained.plan
    overflow.unlisted = [Int.max, 0]
    var invalidWidth = retained.plan
    let mappedSheet = invalidWidth.sheets[0]
    invalidWidth.sheets[0] = .init(
      name: mappedSheet.name, dataset: mappedSheet.dataset, width: -1,
      rows: mappedSheet.rows, logical: mappedSheet.logical, appended: mappedSheet.appended)
    var previous = retained.id
    for malformed in [shortened, overflow, invalidWidth] {
      previous = try book.mutation("synthetic_malformed_map", token: identifier()) {
        .string(
          try book.insertItem(
            category: "record", kind: Workbook.sheetFormulaKind,
            title: "Malformed synthetic map", text: "Synthetic refusal case",
            data: .object([
              "plan": .string(String(decoding: try JSONEncoder().encode(malformed), as: UTF8.self))
            ]), meaning: "actual", status: "accepted", scenario: "actual",
            inputs: [previous], transformation: "synthetic-map-v1", supersedes: previous))
      }.text
      try refuses("sheet_formulas") { _ = try book.sheetFormulaPlan(ledger.id) }
    }
  }
  func value(_ formula: String, _ cells: [String: SheetValue] = [:]) throws -> SheetValue {
    try SheetFormula.parse(formula).evaluate { cells[$0.name] ?? .blank }
  }
  func number(_ text: String) -> SheetValue { .number(Decimal(string: text)!) }
  check(
    "original job costing recalculates new time, rate changes, Undo and portable reconstruction"
  ) {
    for index in 0...2 {
      let book = try Workbook.create(
        at: root.appendingPathComponent("Original-jobs-\(index).sevra"), title: "Jobs")
      let file = URL(fileURLWithPath: "integration/fixtures/excel-business/jobs-\(index).xlsx")
      let job = try book.captureIntake(file, role: .values)
      try expect(try book.runIntake(job.id).state == "ready")
      let tables = try book.datasets()
      let jobs = tables.first { $0.title.hasSuffix(" · Jobs") }!
      let report = try book.sheetFormulaReport(jobs.id)!
      try expect(report.recalculating == 9 && report.saved == 0)
      if index != 0 { continue }  // all independently saved variants must import without gaps
      let time = tables.first { $0.title.hasSuffix(" · Time") }!
      let staff = tables.first { $0.title.hasSuffix(" · Staff") }!
      func totals(_ workbook: Workbook) throws -> [String: Value] {
        let rows = try workbook.rows(jobs.id)
        return rows.first { $0.data["c1"] == .string("J1") }!.data.object
      }
      let original = try totals(book)
      func appendTime() throws -> Value {
        try book.chatTableTransaction(
          time.id, expectedDefinitionID: time.definitionID,
          operations: [
            .object([
              "op": .string("insert"),
              "values": .object([
                "c1": .string("NEW"), "c2": .string("J1"), "c3": .string("E2"),
                "c4": .string("3.5"),
              ]),
            ])
          ])
      }
      let receipt = try appendTime()
      try expect(try totals(book)["c3"] == .string("13.5") && totals(book)["c4"] == .string("345"))
      _ = try book.chatTableTransaction(
        time.id, expectedDefinitionID: time.definitionID, operations: [],
        undo: receipt["token"].text)
      try expect(try totals(book) == original)
      _ = try appendTime()
      let employee = try book.rows(staff.id).first { $0.data["c1"] == .string("E2") }!
      _ = try book.editRow(employee.id, values: ["c3": .string("35")])
      try expect(
        try totals(book)["c4"] == .string("362.5") && totals(book)["c5"] == .string("637.5"))
      try expect(try totals(Workbook(book.url)) == totals(book))
      let copy = try book.reconstruct(to: root.appendingPathComponent("Original-jobs-copy.sevra"))
      try expect(try totals(copy) == totals(book) && copy.verify()["ok"] == .bool(true))
    }
  }
  check("SUMPRODUCT preserves array shape, arithmetic, logical coercion and error propagation") {
    let fixture = try Value.parse(
      String(contentsOfFile: "integration/fixtures/excel-product/cases.json", encoding: .utf8))
    var cells: [String: SheetValue] = [:]
    for (r, row) in fixture["rows"].array.enumerated() {
      for (c, item) in row.array.enumerated() {
        let key = XLSX.cellName(column: c, row: r + 1)
        if item == .null {
          cells[key] = .blank
        } else if case .number = item {
          cells[key] = number(item.text)
        } else if item.text == "=1/0" {
          cells[key] = .error("#DIV/0!")
        } else {
          cells[key] = .text(item.text)
        }
      }
    }
    // Calc coerces logical arrays in SUMPRODUCT; Excel requires explicit arithmetic
    // coercion. Preserve Calc's raw answers in the fixture instead of rewriting them.
    let excelLogicalResults: [Int: String] = [5: "0", 7: "0", 32: "0"]
    var differences: [String] = []
    for (i, formula) in fixture["formulas"].array.enumerated() {
      let actual = try value(formula.text, cells)
      let expected = excelLogicalResults[i] ?? fixture["expected"].array[i].text
      if !SheetFormula.same(actual, as: expected) {
        differences.append(formula.text + ": " + SheetFormula.text(actual) + " != " + expected)
      }
    }
    try expect(differences.isEmpty, differences.joined(separator: "\n"))
    let expression = try SheetFormula.parse("SUMPRODUCT((A1:A100=\"x\")*B1:B100)")
    try expect(expression.references.contains { $0.name == "B100" })
    try expect(
      expression.evaluate {
        $0.name == "A100" ? .text("x") : $0.name == "B100" ? number("7") : .blank
      } == number("7"))
    try expect(
      expression.evaluate {
        $0.name == "A101" ? .text("x") : $0.name == "B101" ? number("9") : .blank
      } == number("0"))
    try expect(expression.evaluate(budget: .init(limit: 40)) { _ in .blank } == .error("#CALC!"))
    let textProduct = try SheetFormula.parse("SUMPRODUCT(A1*2)")
    try expect(
      textProduct.evaluate(budget: .init(limit: 20)) { _ in
        .text(String(repeating: "9", count: 100))
      } == .error("#CALC!"))
    for invalid in [
      "SUMPRODUCT(A1:A5001,B1:B5001)", "SUMPRODUCT(IF(A1:A3=1,1,0))", "SUMPRODUCT(ROUND(A1:A3,2))",
    ] {
      do {
        _ = try SheetFormula.parse(invalid)
        throw SevraError("test", "Accepted " + invalid)
      } catch is SheetFormulaGap {}
    }
  }
  check(
    "conditional sums match independent spreadsheet calculations and preserve Excel criteria types"
  ) {
    let fixture = try Value.parse(
      String(
        contentsOfFile:
          "integration/fixtures/excel-conditional/cases.json", encoding: .utf8))
    var cells: [String: SheetValue] = [:]
    for (r, row) in fixture["rows"].array.enumerated() {
      for (c, item) in row.array.enumerated() {
        let key = XLSX.cellName(column: c, row: r + 1)
        if item == .null {
          cells[key] = .blank
        } else if case .number = item {
          cells[key] = number(item.text)
        } else if item.text == "=1/0" {
          cells[key] = .error("#DIV/0!")
        } else {
          cells[key] = .text(item.text)
        }
      }
    }
    // Calc differs from Excel for numeric-text criteria, text collation and wildcard/error matching.
    // Keep its actual results visible; do not rewrite an independent oracle to our implementation.
    let excelCriteria: [Int: String] = [
      4: "90", 7: "740", 18: "130", 19: "330", 22: "490", 30: "440",
    ]
    for (index, formula) in fixture["formulas"].array.enumerated() {
      let expected = excelCriteria[index] ?? fixture["expected"].array[index].text
      let actual = try value(formula.text, cells)
      try expect(
        SheetFormula.text(actual) == expected,
        formula.text + ": " + SheetFormula.text(actual) + " != " + expected)
    }
    try expect(
      try value(
        "SUMIF(A1:A3,\"x\",B1)",
        ["A1": .text("x"), "A3": .text("X"), "B1": number("2"), "B3": number("7")]) == number("9"))
    let references = try SheetFormula.parse("SUMIF(A1:A3,\"x\",B1)").references.map(\.name)
    try expect(references.contains("B3"))
    try expect(
      try SheetFormula.parse("SUMIF(A1:A2500,1,B1)+SUMIF(C1:C2500,1,D1)").referenceCount == 10_000)
    let costly = "SUMIF(A1,\"" + String(repeating: "?", count: 254) + "\",B1)"
    try expect(
      try value(
        costly,
        [
          "A1": .text(String(repeating: "a", count: 10_000)),
          "B1": number("1"),
        ]) == .error("#CALC!"))
    let budget = SheetFormulaBudget(limit: 12)
    let bounded = try SheetFormula.parse("SUMIF(A1,\"*\",B1)")
    let read: (SheetCell) -> SheetValue = { $0.name == "A1" ? .text("four") : number("7") }
    try expect(bounded.evaluate(budget: budget, read) == number("7"))
    try expect(bounded.evaluate(budget: budget, read) == number("7"))
    try expect(bounded.evaluate(budget: budget, read) == .error("#CALC!"))
    try expect(bounded.evaluate(read) == number("7"))  // a new pass receives a fresh budget
    for invalid in [
      "SUMIF(A1)", "SUMIF(1,2)", "SUMIFS(A1,A1)",
      "SUMIFS(A1,1,2)", "SUMIF(A1:A9999,1,B1)", "SUMIF(A1:A2,1,SF1048576)",
      "SUMIF(A1:A3000,1,B1)+SUMIF(C1:C3000,1,D1)",
    ] {
      do {
        _ = try SheetFormula.parse(invalid)
        throw SevraError("test", "Accepted " + invalid)
      } catch is SheetFormulaGap {}
    }
  }
  check("native PMT agrees with independently saved payments and rounding") {
    let cases = try Value.parse(
      String(contentsOfFile: "integration/fixtures/excel-pmt/results.json", encoding: .utf8)
    ).array
    try expect(cases.count == 24)
    for example in cases {
      var cells: [String: SheetValue] = [:]
      for (index, argument) in example["arguments"].array.enumerated() {
        let key = ["A1", "B1", "C1", "D1", "E1"][index]
        if argument == .null {
          cells[key] = .blank
        } else if case .number = argument {
          cells[key] = number(argument.text)
        } else {
          cells[key] = .text(argument.text)
        }
      }
      for (formula, expected) in [
        ("PMT(A1,B1,C1,D1,E1)", example["payment"].text),
        ("ROUND(-PMT(A1,B1,C1,D1,E1),2)", example["roundedNegated"].text),
      ] {
        let actual = try value(formula, cells)
        try expect(
          SheetFormula.same(actual, as: expected),
          example["name"].text + ": " + SheetFormula.text(actual) + " != " + expected)
      }
    }
    try expect(try value("ROUND(-PMT(0.01,12,10000),2)") == number("888.49"))
    try expect(try value("ROUND(-PMT(0.01,12,10000,500),2)") == number("927.91"))
    try expect(try value("PMT(0,12,100,20,1)") == number("-10"))
    try expect(try value("PMT(0,0,A1)", ["A1": .error("#REF!")]) == .error("#REF!"))
    try expect(try value("PMT(0,12,0,A1)", ["A1": .text("bad")]) == .error("#VALUE!"))
    try expect(try value("PMT(0,12,0,0,A1)", ["A1": .text("bad")]) == .error("#VALUE!"))
    try expect(try value("PMT(1E127,1E127,1)") == .error("#NUM!"))
    try expect(
      try SheetFormula.same(
        value("PMT(-0.99999999999999999,1,10000,0,1)"), as: "-10000"))
    for invalid in ["PMT(1,2)", "PMT(1,2,3,4,5,6)", "PMT(A1:A2,2,3)"] {
      do {
        _ = try SheetFormula.parse(invalid)
        throw SevraError("test", "Accepted " + invalid)
      } catch is SheetFormulaGap {}
    }
  }
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
    try expect(
      try value("MIN(A1:A4)", mixed) == number("1") && value("MAX(A1:A4)", mixed) == number("2"))
    try expect(
      try value("AVERAGE(B1:B2)") == .error("#DIV/0!") && value("MAX(B1:B2)") == number("0"))
    let broken: [String: SheetValue] = ["A1": .error("#REF!"), "A2": number("1")]
    try expect(try value("SUM(A1:A2)", broken) == .error("#REF!"))
    try expect(try value("COUNT(A1:A2)", broken) == number("1"))
    try expect(try value("A1+1/0", broken) == .error("#REF!"))
    try expect(try value("IF(A1>1,B1,1/0)", ["A1": number("2"), "B1": number("7")]) == number("7"))
    try expect(try value("IF(A1,1,2)") == number("2") && value("IF(A1<>0,1,2)") == number("2"))
    let compared: [String: SheetValue] = [
      "A1": .text("n/a"), "A2": .text("N/A"), "A3": number("9"),
    ]
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
    try expect(
      try value("ROUND(1.234,2.5)") == number("1.23") && value("ROUND(1.5,0.5)") == number("2"))
    try expect(
      try value("ROUND(1.2345,30)") == number("1.2345") && value("ROUND(5,-30)") == number("0"))
    try expect(try value("ROUND(1.23456,10/3)") == number("1.235"))
    try expect(try value("ROUND(1234.5678,-10/3)") == number("1000"))
    try expect(try value("ROUND(1234.5678,-1/3)") == number("1235"))
    try expect(try value("COUNT(1/A1,5)") == number("1"))
    // A value too small to divide is an error, never a number that cannot be written.
    let tiny: [String: SheetValue] = ["A1": number("1E-128")]
    try expect(try value("A1%", tiny) == .error("#NUM!"))
    try expect(
      try value("AVERAGE(A1,B1)", tiny.merging(["B1": number("0")]) { a, _ in a })
        == .error("#NUM!"))
    do {
      _ = try SheetFormula.parse("1E-999")
      throw SevraError("test", "Accepted a number past the decimal range")
    } catch is SheetFormulaGap {}
  }
  check("sheet references keep quoted names and ranges share their sheet") {
    let quoted = try SheetFormula.parse("'It''s here'!B2+Other!C3").references
    try expect(
      quoted.map(\.sheet) == ["It's here", "Other"] && quoted.map(\.name) == ["B2", "C3"])
    let range = try SheetFormula.parse("SUM(Other!A1:B2)").references
    try expect(range.count == 4 && range.allSatisfy { $0.sheet == "Other" })
  }
  check("formulas outside the subset say what they use") {
    let gaps = [
      "VLOOKUP(A1,B1:C2,2,FALSE)": "Uses VLOOKUP,",
      "_xlfn.XLOOKUP(A1,B1:B2,C1:C2)": "Uses XLOOKUP,",
      "\"a\"&B1": "joined text", "A1^2": "powers", "A1&B1": "joined text",
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
    try expect(
      !SheetFormula.same(number("123"), as: "00123")
        && !SheetFormula.same(number("7.2"), as: "7.20"))
    // Noise never moves a saved cell at import, and any digit Excel would show moves it later.
    try expect(!SheetFormula.moved(number("20000000000000"), from: "20000000000000"))
    try expect(SheetFormula.moved(number("20000000000001"), from: "20000000000000"))
    try expect(SheetFormula.moved(number("1000000.00000001"), from: "1000000"))
    try expect(!SheetFormula.moved(number("0.3"), from: "0.30000000000000004"))
    try expect(!SheetFormula.moved(number("7.2"), from: "7.20"))
  }
  check("an edit and its recalculated cells are one row version, and Undo restores both") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Formulas.sevra"), title: "Lines")
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
    try expect(
      try book.rows(table.id)[0].version == 1 && book.sheetFormulaReport(table.id)?.saved == 0)
    try edit(book, table, row: 0, ["c1": "5"])
    try expect(try book.rows(table.id)[0].data["c3"].text == "11")
    try expect(try book.rows(table.id)[1].data["c3"].text == "7")
    try book.setColumns(table.id, columns: table.columns.filter { $0.id != "c2" })
    var rows = try book.rows(table.id)
    try expect(rows[0].data["c3"].text == "#REF!" && rows[1].data["c3"].text == "#REF!")
    let versions = rows.map(\.version)
    // The row stays editable, and an edit elsewhere rewrites nothing that did not move.
    var values = Workbook.activeValues(
      rows[1].data.object, columns: try book.dataset(table.id).columns)
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
      _ = try book.proposeTableEdit(
        table.id, edits: [RowEdit(id: row.id, values: ["c2": .string("9")])])
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
