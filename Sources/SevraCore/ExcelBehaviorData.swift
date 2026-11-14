import Foundation

extension Workbook {
  func excelBehaviorSnapshot(_ plan: SheetFormulaPlan, pending: [String: [String: Value]] = [:])
    throws
    -> (cells: [String: String], rows: [String: (logical: String, column: String, dataset: String)])
  {
    var cells: [String: String] = [:]
    var targets: [String: (logical: String, column: String, dataset: String)] = [:]
    var bytes = 0
    for (index, sheet) in plan.sheets.enumerated() {
      let table = try dataset(sheet.dataset)
      try require(
        !table.archived && table.columns.count == sheet.width
          && sheet.rows.count == sheet.logical.count
          && sheet.rows.count <= SheetFormulaPlan.rowLimit,
        "excel_behavior", "The recreated worksheet structure changed. Rebuild its workspace.")
      let members = Set(
        try db.execute(
          "SELECT logical_id FROM dataset_rows WHERE dataset_id=?",
          [.string(sheet.dataset)]
        ).map { $0["logical_id"]!.text })
      try require(
        members == Set(sheet.logical), "excel_behavior",
        "Worksheet rows changed. Rebuild its behavior before calculating.")
      for (number, logical) in zip(sheet.rows, sheet.logical) {
        try require(
          members.contains(logical), "excel_behavior", "A recreated worksheet row was removed.")
        let row = try item(logical)
        let values = pending[logical] ?? row.data.object
        for column in 0..<sheet.width {
          let key = "sheet\(index + 1)!" + XLSX.cellName(column: column, row: number)
          let field = "c\(column + 1)"
          try require(
            table.columns[column].id == field, "excel_behavior", "Worksheet columns changed.")
          let value = values[field]?.text ?? ""
          bytes += value.utf8.count + key.utf8.count
          try require(
            cells.count < 100_000 && bytes <= 2_000_000,
            "excel_behavior_limit", "The recreated calculation exceeds its cell budget.")
          cells[key] = value
          targets[key] = (logical, field, sheet.dataset)
        }
      }
    }
    return (cells, targets)
  }

  func excelBehaviorChanges(
    planID: String, plan: SheetFormulaPlan, behavior: ExcelBehavior,
    pending: [String: [String: Value]]
  ) throws
    -> (plan: String, cells: [String: [String: String]])
  {
    let snapshot = try excelBehaviorSnapshot(plan, pending: pending)
    let calculated = try behavior.evaluate(cells: snapshot.cells)
    var changes: [String: [String: String]] = [:]
    for (key, value) in calculated where value != snapshot.cells[key] {
      guard let row = snapshot.rows[key] else {
        throw SevraError("excel_behavior", "A derived cell is unavailable.")
      }
      let table = try dataset(row.dataset)
      guard let column = table.columns.first(where: { $0.id == row.column }) else {
        throw SevraError("excel_behavior", "A derived column is unavailable.")
      }
      try validateValues([row.column: .string(value)], columns: [column])
      changes[row.logical, default: [:]][row.column] = value
    }
    try require(
      changes.count <= SheetFormulaPlan.rewriteLimit,
      "excel_behavior_limit", "This calculation would change too many rows.")
    return (planID, changes)
  }

  /// Called only inside checked conversion publication. Only declared derived cells recalculate.
  func attachExcelBehavior(_ behavior: ExcelBehavior, conversion: ExcelConversion) throws {
    try behavior.validate()
    let original = try excelOriginalSheets(conversion.sourceID).filter { !$0.rows.isEmpty }
    try require(
      original.count == conversion.datasetIDs.count, "excel_behavior", "Worksheet bindings changed."
    )
    var plan = SheetFormulaPlan(sheets: [], cells: [], behavior: behavior)
    for (index, sheet) in original.enumerated() {
      let datasetID = conversion.datasetIDs[index]
      let logical = try db.execute(
        "SELECT logical_id FROM dataset_rows WHERE dataset_id=? ORDER BY ordinal",
        [.string(datasetID)]
      ).map { $0["logical_id"]!.text }
      let table = try dataset(datasetID)
      try require(
        logical.count == sheet.rows.count && logical.count <= SheetFormulaPlan.rowLimit,
        "excel_behavior", "Worksheet rows changed. Rebuild from a matching original.")
      plan.sheets.append(
        .init(
          name: sheet.name, dataset: datasetID, width: table.columns.count,
          rows: sheet.rowNumbers, logical: logical))
    }
    for key in behavior.outputs {
      let address = try ExcelBehavior.address(key)
      try require(
        original.indices.contains(address.sheet), "excel_behavior",
        "An output worksheet is unavailable.")
      let cell = key.split(separator: "!")[1]
      plan.cells.append(
        .init(
          sheet: address.sheet, cell: String(cell),
          formula: original[address.sheet].formulas[String(cell)] ?? "Recreated calculation",
          reason: nil))
    }
    _ = try excelBehaviorSnapshot(plan)
    let previous = try conversion.datasetIDs.first.flatMap { try sheetFormulaPlan($0)?.id }
    let saved = try insertItem(
      category: "record", kind: Self.sheetFormulaKind,
      title: conversion.record.title + ", recreated behavior",
      text: "Compared workbook behavior. See import details for tested coverage.",
      data: .object([
        "plan": .string(String(decoding: try JSONEncoder().encode(plan), as: UTF8.self))
      ]),
      meaning: "actual", status: "accepted", scenario: "actual",
      inputs: [conversion.version, conversion.sourceID],
      transformation: "excel-behavior-v1", supersedes: previous)
    for table in conversion.datasetIDs {
      try db.execute(
        "INSERT INTO meta VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        [.string("sheet-formulas:" + table), .string(try item(saved).logicalID)])
    }
    try applySheetFormulaChanges(try sheetFormulaChanges(after: conversion.datasetIDs[0]))
  }

  /// Trusted checker setup, on its disposable workbook after invented fixtures have been seeded.
  package func attachSyntheticExcelBehavior(_ package: NativeAppPackage, coordinates: [[Int]]?)
    throws
  {
    guard let behavior = package.excelBehavior else { return }
    try package.validate()
    _ = try mutation("excel_synthetic_behavior", token: identifier()) {
      var plan = SheetFormulaPlan(sheets: [], cells: [], behavior: behavior)
      for index in 0..<package.datasets.count {
        guard let tableID = package.datasets["sheet\(index + 1)"]?.datasetID else {
          throw SevraError("app_check", "Missing isolated worksheet binding.")
        }
        let logical = try db.execute(
          "SELECT logical_id FROM dataset_rows WHERE dataset_id=? ORDER BY ordinal",
          [.string(tableID)]
        ).map { $0["logical_id"]!.text }
        let numbers =
          coordinates.flatMap {
            $0.indices.contains(index) ? Array($0[index].prefix(logical.count)) : nil
          }
          ?? Array(1..<(logical.count + 1))
        try require(
          numbers.count == logical.count, "app_check",
          "Fixtures exceed the original worksheet structure.")
        plan.sheets.append(
          .init(
            name: "sheet\(index + 1)", dataset: tableID,
            width: try dataset(tableID).columns.count, rows: numbers, logical: logical))
      }
      for key in behavior.outputs {
        let address = try ExcelBehavior.address(key)
        plan.cells.append(
          .init(
            sheet: address.sheet, cell: String(key.split(separator: "!")[1]),
            formula: "Recreated calculation", reason: nil))
      }
      let evidence = try insertItem(
        category: "source", kind: "observation", title: "Synthetic behavior program",
        text: "Disposable checker input", data: try encoded(behavior), meaning: "actual",
        status: "accepted",
        scenario: "actual", inputs: [], transformation: "excel-synthetic-input-v1")
      let saved = try insertItem(
        category: "record", kind: Self.sheetFormulaKind, title: "Synthetic behavior check",
        text: "Disposable check only",
        data: .object([
          "plan": .string(String(decoding: try JSONEncoder().encode(plan), as: UTF8.self))
        ]),
        meaning: "actual", status: "accepted", scenario: "actual",
        inputs: [evidence], transformation: "excel-synthetic-behavior-v1")
      for sheet in plan.sheets {
        try db.execute(
          "INSERT INTO meta VALUES(?,?)",
          [.string("sheet-formulas:" + sheet.dataset), .string(try item(saved).logicalID)])
      }
      if let first = plan.sheets.first {
        try applySheetFormulaChanges(try sheetFormulaChanges(after: first.dataset))
      }
      return .null
    }
  }

  func excelActionOperations(_ access: NativeAppAccess, action: String, arguments: Value) throws
    -> [Value]
  {
    guard let behavior = access.package.excelBehavior else {
      throw SevraError(
        "excel_action",
        "This app declares no recreated Excel behavior. Include the compared excelBehavior in the app package before invoking its actions."
      )
    }
    guard let declared = behavior.actions.first(where: { $0.id == action }) else {
      throw SevraError(
        "excel_action", "This app does not declare the action: " + String(action.prefix(80)))
    }
    guard let first = access.package.datasets["sheet1"]?.datasetID,
      let (_, plan) = try sheetFormulaPlan(first), plan.behavior == behavior
    else { throw SevraError("excel_action", "This exact workspace behavior is no longer active.") }
    for (index, sheet) in plan.sheets.enumerated() {
      let binding = try access.binding("sheet\(index + 1)")
      try require(
        binding.datasetID == sheet.dataset && binding.columns == dataset(sheet.dataset).columns,
        "app_permission", "The behavior's worksheet access changed.")
    }
    let snapshot = try excelBehaviorSnapshot(plan)
    let changes = try behavior.evaluate(cells: snapshot.cells, action: action, arguments: arguments)
    var grouped: [String: (alias: String, values: [String: Value])] = [:]
    for key in declared.writes {
      guard let value = changes[key], value != snapshot.cells[key], let target = snapshot.rows[key]
      else { continue }
      let alias = String(key.split(separator: "!")[0])
      _ = try access.binding(alias, write: true)
      if grouped[target.logical] == nil { grouped[target.logical] = (alias, [:]) }
      grouped[target.logical]!.values[target.column] = .string(value)
    }
    try require(!grouped.isEmpty, "excel_action", "This action made no changes.")
    return grouped.sorted { $0.key < $1.key }.map { logical, change in
      .object([
        "op": .string("update"), "table": .string(change.alias),
        "id": .string(logical), "values": .object(change.values),
      ])
    }
  }
}
