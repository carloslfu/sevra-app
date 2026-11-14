import Foundation

extension Workbook {
  func excelOriginalSheets(_ sourceID: String, cancellation: Cancellation = .init()) throws
    -> [ImportedSheet]
  {
    let source = try item(sourceID)
    guard source.category == "source", let assetID = source.assetID else {
      throw SevraError("excel_source", "Missing original workbook.")
    }
    let result = try ExtractionWorker().readTable(
      assetURL(assetID, verify: true, cancellation: cancellation),
      format: .xlsx, cancellation: cancellation
    ).sheets
    _ = try assetURL(assetID, verify: true, cancellation: cancellation)
    return result
  }
  static func excelCells(_ sheets: [ImportedSheet]) throws -> [String: String] {
    var cells: [String: String] = [:]
    for (index, sheet) in sheets.filter({ !$0.rows.isEmpty }).enumerated() {
      let width = sheet.rows.map(\.count).max() ?? 0
      for (number, values) in zip(sheet.rowNumbers, sheet.rows) {
        for column in 0..<width {
          cells["sheet\(index + 1)!" + XLSX.cellName(column: column, row: number)] =
            column < values.count ? values[column] : ""
          try require(
            cells.count <= 100_000, "excel_comparison_limit", "Comparison exceeds 100,000 cells.")
        }
      }
    }
    return cells
  }
  /// Explicit addresses avoid confusing row offsets with Excel coordinates in model context.
  static func excelCalculationEvidence(_ sheets: [ImportedSheet]) throws -> Value {
    let nonempty = sheets.filter { !$0.rows.isEmpty }
    let cells = try excelCells(nonempty)
    var formulas: [String: Value] = [:]
    var inputs: [String: Value] = [:]
    var budget = 12_000
    var omitted = false
    for (index, sheet) in nonempty.enumerated() {
      for key in sheet.formulas.keys.sorted() {
        let address = "sheet\(index + 1)!" + key
        let text = sheet.formulas[key]!
        if formulas.count < 40 && text.utf8.count + address.utf8.count < budget {
          formulas[address] = .string(text)
          budget -= text.utf8.count + address.utf8.count
        } else {
          omitted = true
        }
      }
    }
    for key in cells.keys.sorted() {
      let address = try ExcelBehavior.address(key)
      let cell = String(key.split(separator: "!")[1])
      if nonempty[address.sheet].formulas[cell] != nil
        || nonempty[address.sheet].formulaKinds[cell] != nil
      {
        continue
      }
      let value = cells[key]!
      if inputs.count < 100 && value.utf8.count <= 500
        && value.utf8.count + key.utf8.count < budget
      {
        inputs[key] = .string(value)
        budget -= value.utf8.count + key.utf8.count
      } else {
        omitted = true
      }
    }
    return .object([
      "formulas": .object(formulas), "inputCells": .object(inputs),
      "partial": .bool(omitted),
      "notice": .string(
        "Exact original cell addresses. Read input.cells[address]; c1=A, c2=B, c3=C. Translate expressions and read variable values from cells. These are original evidence, not synthetic test fixtures. Use inspect_excel_evidence for omitted source."
      ),
    ])
  }
  public func compareExcelBehavior(
    _ behavior: ExcelBehavior, conversionID: String,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try compareExcelResults(behavior, conversionID: conversionID, cancellation: cancellation)
  }
  public func compareExcelApplication(
    _ package: NativeAppPackage, conversionID: String,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try compareExcelResults(
      package.excelBehavior, conversionID: conversionID, cancellation: cancellation)
  }
  private func compareExcelResults(
    _ behavior: ExcelBehavior?, conversionID: String,
    cancellation: Cancellation
  ) throws -> Value {
    try behavior?.validate()
    let conversion = try excelConversion(conversionID)
    let original = try excelOriginalSheets(conversion.sourceID, cancellation: cancellation).filter {
      !$0.rows.isEmpty
    }
    let baseline = try Self.excelCells(original)
    try require(
      !original.contains { $0.formulaKinds["*"] != nil }, "excel_coverage",
      "The original contains a formula output range that could not be bounded. Its saved data is preserved; narrow the workbook before comparing recreated behavior."
    )
    let formulas = Set(
      original.enumerated().flatMap { index, sheet in
        Set(sheet.formulas.keys).union(sheet.formulaKinds.keys.filter { $0 != "*" })
          .map { "sheet\(index + 1)!" + $0 }
      })
    let outputs: [String]
    let actions = behavior?.actions ?? []
    let evaluate: ([String: String], String, Value) throws -> [String: String]
    if let behavior {
      try require(
        Set(behavior.outputs) == formulas
          && Set(behavior.outputs + actions.flatMap(\.writes)).isSubset(of: Set(baseline.keys)),
        "excel_coverage",
        "Declare exactly the original formula cells as outputs. Input cells may change only through declared actions, never automatic recalculation."
      )
      outputs = behavior.outputs
      evaluate = {
        try behavior.evaluate(cells: $0, action: $1, arguments: $2, cancellation: cancellation)
      }
    } else {
      let plan =
        try conversion.datasetIDs.first.flatMap { try sheetFormulaPlan($0)?.plan }
        ?? SheetFormulaPlan(sheets: [], cells: [])
      try require(
        plan.behavior == nil, "excel_coverage",
        "Preserve or replace the existing recreated behavior on rebuild.")
      let engine = SheetFormulaEngine(plan: plan)
      outputs = engine.order.map {
        "sheet\($0.sheet + 1)!" + XLSX.cellName(column: $0.column, row: $0.row)
      }
      try require(
        Set(outputs) == formulas, "excel_coverage",
        "Some formulas still keep saved values. Inspect their original expressions and supply excelBehavior to recreate them, including every formula output."
      )
      evaluate = { cells, action, _ in
        try require(
          action == "recalculate", "excel_coverage",
          "Recreate the action named by this original-result example.")
        return Dictionary(
          uniqueKeysWithValues: engine.values { key in
            SheetValue(
              stored: cells[
                "sheet\(key.sheet + 1)!" + XLSX.cellName(column: key.column, row: key.row)] ?? "")
          }.map { key, value in
            (
              "sheet\(key.sheet + 1)!" + XLSX.cellName(column: key.column, row: key.row),
              SheetFormula.text(value)
            )
          })
      }
    }
    let outputSet = Set(outputs)
    var cases: [Value] = []
    var differences: [Value] = []
    var failingScenarios: [Value] = []
    var unverified: [String] = []
    var total = 0
    var varied = 0
    var exercisedActions = Set<String>()
    if conversion.inspection["evidence"].array.contains(where: {
      $0["id"].text.hasPrefix("xl/connections") || $0["id"].text.hasPrefix("xl/externalLinks/")
    }) {
      unverified.append(
        "External connections are preserved as evidence; refresh against their original services is not connected."
      )
    }
    for part in conversion.inspection["evidence"].array where part["complete"] == .bool(false) {
      unverified.append(part["id"].text + ": original source could not be fully read.")
    }
    if conversion.inspection["evidence"].array.contains(where: { $0["kind"] == .string("vba") })
      && actions.isEmpty
    {
      unverified.append("The original contains VBA source; no translated actions were declared.")
    }
    let sources: [Value] =
      [.object(["sourceID": .string(conversion.sourceID), "action": .string("recalculate")])]
      + conversion.record.data["examples"].array
    try require(
      sources.count <= 13, "excel_comparison_limit", "Use up to twelve original-result examples.")
    for reference in sources {
      try cancellation.check()
      let sourceID = reference["sourceID"].text
      let action = reference["action"].text
      let sheets =
        sourceID == conversion.sourceID
        ? original
        : try excelOriginalSheets(sourceID, cancellation: cancellation).filter { !$0.rows.isEmpty }
      try Self.requireMatchingExcelStructure(sheets, original)
      let expected = try Self.excelCells(sheets)
      var inputs = expected
      var caseOutputs = outputSet
      if action != "recalculate" {
        guard let definition = actions.first(where: { $0.id == action }) else {
          throw SevraError(
            "excel_example", "The example names an action absent from this behavior.")
        }
        for cell in definition.writes { inputs[cell] = baseline[cell] }
        caseOutputs.formUnion(definition.writes)
        exercisedActions.insert(action)
      }
      let changedInputValues = inputs.filter {
        !outputSet.contains($0.key) && $0.value != baseline[$0.key]
      }
      let changedInputs = changedInputValues.count
      let shownInputs = changedInputValues.sorted { $0.key < $1.key }.prefix(32)
      let scenario: Value = .object([
        "sourceID": .string(sourceID), "action": .string(action),
        "inputChanges": .object(
          Dictionary(
            uniqueKeysWithValues: shownInputs.map {
              ($0.key, .string(String($0.value.prefix(500))))
            })),
        "arguments": reference["arguments"] == .null ? .object([:]) : reference["arguments"],
        "truncated": .bool(changedInputs > 32 || shownInputs.contains { $0.value.count > 500 }),
      ])
      if changedInputs > 0 { varied += 1 }
      let actual: [String: String]
      do {
        actual = try evaluate(
          inputs, action, reference["arguments"] == .null ? .object([:]) : reference["arguments"])
      } catch {
        try cancellation.check()
        throw SevraError(
          "excel_comparison",
          error.localizedDescription
            + "\nFailing original scenario (input changes relative to the original): "
            + (try scenario.json()))
      }
      var compared = 0
      var differs = false
      for key in caseOutputs.sorted() {
        let address = try ExcelBehavior.address(key)
        let cell = String(key.split(separator: "!")[1])
        if sheets[address.sheet].unsettled[cell] == "uncached" {
          unverified.append(key + " has no result saved by Excel.")
          continue
        }
        let value = actual[key] ?? inputs[key] ?? ""
        let saved = expected[key] ?? ""
        compared += 1
        if !(outputSet.contains(key) ? Self.sameExcelResult(value, saved) : value == saved) {
          differs = true
          if differences.count < 100 {
            differences.append(
              .object([
                "sourceID": .string(sourceID), "cell": .string(key),
                "expected": .string(String(saved.prefix(500))),
                "actual": .string(String(value.prefix(500))),
              ]))
          }
        }
      }
      if differs && failingScenarios.count < 3 { failingScenarios.append(scenario) }
      total += compared
      let asset = try item(sourceID).assetID.flatMap { try self.asset($0) }
      cases.append(
        .object([
          "sourceID": .string(sourceID), "sourceHash": .string(asset?.hash ?? ""),
          "action": .string(action), "compared": .number(Double(compared)),
          "changedInputs": .number(Double(changedInputs)),
        ]))
    }
    return .object([
      "status": .string(differences.isEmpty ? "matched" : "mismatch"),
      "programDigest": .string(behavior?.digest ?? "builtin"),
      "conversionVersion": .string(conversion.version),
      "cases": .array(cases), "compared": .number(Double(total)),
      "variedCases": .number(Double(varied)),
      "differences": .array(differences),
      "failingScenarios": .array(failingScenarios),
      "calculationEvidence": differences.isEmpty
        ? .null : try Self.excelCalculationEvidence(original),
      "unverified": .array(Array(Set(unverified)).sorted().map(Value.string)),
      "actionsWithoutExamples": .array(
        actions.filter { !exercisedActions.contains($0.id) }.map { .string($0.title) }),
      "gaps": .array((behavior?.gaps ?? []).map(Value.string)),
      "notCompared": .array([
        .string(
          "Visual layout, manual steps and external service behavior are not established by cell-result comparisons."
        )
      ]),
      "notice": .string(
        "Compared only the saved original results listed here. Saved-state matches do not prove changed-input behavior or every business rule."
      ),
    ])
  }
  static func sameExcelResult(_ actual: String, _ expected: String) -> Bool {
    if actual == expected { return true }
    let numeric = "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$"
    guard actual.range(of: numeric, options: .regularExpression) != nil,
      expected.range(of: numeric, options: .regularExpression) != nil,
      let a = SheetFormula.number(actual), let b = SheetFormula.number(expected)
    else { return false }
    return abs(a - b) <= max(abs(a), abs(b)) * Decimal(string: "0.00000000000005")!
  }
  public static func excelComparisonFailure(_ report: Value, includeEvidence: Bool = false)
    -> String
  {
    let examples = report["differences"].array.prefix(3).map {
      $0["cell"].text + ": original “" + String($0["expected"].text.prefix(100))
        + "”; recreated “" + String($0["actual"].text.prefix(100)) + "”."
    }.joined(separator: "\n")
    return
      "Recreated results differ from the original. Nothing was published. Repair the calculation and compare again.\n"
      + examples
      + (report["failingScenarios"].array.isEmpty
        ? ""
        : "\nFailing scenarios, with input changes relative to the original (evidence, never constants to copy into code): "
          + String((try? report["failingScenarios"].json())?.prefix(12_000) ?? ""))
      + (!includeEvidence || report["calculationEvidence"] == .null
        ? ""
        : "\nCheck the original addresses and expressions before retrying: "
          + String((try? report["calculationEvidence"].json())?.prefix(12_000) ?? ""))
  }
}
