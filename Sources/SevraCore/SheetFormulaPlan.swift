import Foundation

/// What a workbook keeps about one Excel file's formulas. Row values stay the stored
/// truth. The plan says which cells recalculate and why the others keep a saved value.
struct SheetFormulaPlan: Codable, Sendable {
  struct Sheet: Codable, Sendable {
    let name: String
    let dataset: String
    /// Columns the sheet held. A read past them is blank, while one inside them was removed.
    let width: Int
    /// Excel row numbers, and the table row each became. Empty rows have no table row.
    let rows: [Int]
    let logical: [String]
  }
  struct Cell: Codable, Sendable {
    let sheet: Int
    let cell: String
    let formula: String
    /// Set when the cell keeps its saved value.
    var reason: String?
  }
  var sheets: [Sheet]
  var cells: [Cell]
  /// Saved-value formulas left unlisted per sheet, so a huge file fits in one saved change.
  var unlisted: [Int] = []

  /// The plan keeps a row map, so its size follows the file's rows as well as its formulas.
  static let rowLimit = 20_000
  static let cellLimit = 10_000
  static let referenceLimit = 200_000
  static let rewriteLimit = 2_000
  static let listLimit = 100_000
  static let unlistedSample = 200

  /// Past the list limit no formula can recalculate, so a sample stands in for the rest.
  mutating func capList() {
    guard cells.count > Self.listLimit else { return }
    let reason = "The file has too many formulas to recalculate."
    var kept: [Cell] = []
    unlisted = Array(repeating: 0, count: sheets.count)
    var listed = Array(repeating: 0, count: sheets.count)
    for var cell in cells {
      if listed[cell.sheet] < Self.unlistedSample {
        listed[cell.sheet] += 1
        cell.reason = cell.reason ?? reason
        kept.append(cell)
      } else {
        unlisted[cell.sheet] += 1
      }
    }
    cells = kept
  }
}

public struct SheetFormulaCell: Codable, Sendable, Equatable {
  public let cell: String
  public let formula: String
  /// Why the cell keeps its saved value. Nil when it recalculates.
  public let reason: String?
}

public struct SheetFormulaReport: Codable, Sendable, Equatable {
  public let recalculating: Int
  public let saved: Int
  /// A table this file became has changed since import, so saved values may be behind.
  public let valuesChanged: Bool
  public let savedCells: [SheetFormulaCell]
}

/// One pass over a plan: dependency order, then values. Import and recalculation share it,
/// so a cell recalculates by the same rules that accepted it.
struct SheetFormulaEngine {
  struct Key: Hashable, Comparable {
    var sheet: Int
    var column: Int
    var row: Int
    static func < (a: Key, b: Key) -> Bool { (a.sheet, a.row, a.column) < (b.sheet, b.row, b.column) }
  }
  let plan: SheetFormulaPlan
  private let sheetIndex: [String: Int]
  private(set) var expressions: [Key: SheetExpression] = [:]
  private(set) var reasons: [Key: String] = [:]
  private var dependencies: [Key: Set<Key>] = [:]

  init(plan: SheetFormulaPlan) {
    self.plan = plan
    sheetIndex = Dictionary(
      plan.sheets.enumerated().map { ($0.element.name.lowercased(), $0.offset) },
      uniquingKeysWith: { first, _ in first })
    var references = 0
    let tooMany = plan.cells.filter { $0.reason == nil }.count > SheetFormulaPlan.cellLimit
    for entry in plan.cells {
      guard let address = SheetFormulaToken.address(entry.cell) else { continue }
      let key = Key(sheet: entry.sheet, column: address.column, row: address.row)
      if let reason = entry.reason {
        reasons[key] = reason
        continue
      }
      if tooMany || references > SheetFormulaPlan.referenceLimit {
        reasons[key] = "The file has too many formulas to recalculate."
        continue
      }
      do {
        let expression = try SheetFormula.parse(entry.formula)
        var reads = Set<Key>()
        for cell in expression.references {
          guard let target = self.key(cell, from: entry.sheet) else {
            throw SheetFormulaGap(reason: "Reads the sheet \(cell.sheet ?? ""), which was not imported.")
          }
          reads.insert(target)
        }
        references += reads.count
        expressions[key] = expression
        dependencies[key] = reads
      } catch let gap as SheetFormulaGap {
        reasons[key] = gap.reason
      } catch {
        reasons[key] = "The formula could not be read."
      }
    }
    if references > SheetFormulaPlan.referenceLimit {
      for key in expressions.keys { reasons[key] = "The file has too many formulas to recalculate." }
      expressions = [:]
      dependencies = [:]
    }
    settle()
  }

  func key(_ cell: SheetCell, from sheet: Int) -> Key? {
    guard let name = cell.sheet else {
      return Key(sheet: sheet, column: cell.column, row: cell.row)
    }
    return sheetIndex[name.lowercased()].map { Key(sheet: $0, column: cell.column, row: cell.row) }
  }

  func name(_ key: Key) -> String {
    let cell = XLSX.cellName(column: key.column, row: key.row)
    return plan.sheets.count > 1 ? plan.sheets[key.sheet].name + "!" + cell : cell
  }

  /// A formula that reads a cell Sevra cannot keep current cannot be current either.
  private mutating func settle() {
    var readers: [Key: [Key]] = [:]
    for (key, reads) in dependencies { for read in reads { readers[read, default: []].append(key) } }
    // Sorted, so one file always states the same reason.
    var queue = reasons.keys.sorted()
    while let blocked = queue.popLast() {
      for reader in (readers[blocked] ?? []).sorted() where expressions[reader] != nil {
        expressions[reader] = nil
        reasons[reader] = "Reads \(name(blocked)), which keeps its saved value."
        queue.append(reader)
      }
    }
    var waiting: [Key: Int] = [:]
    for key in expressions.keys {
      waiting[key] = dependencies[key]!.filter { expressions[$0] != nil }.count
    }
    var ready = waiting.filter { $0.value == 0 }.map(\.key)
    var sorted: [Key] = []
    while let key = ready.popLast() {
      sorted.append(key)
      for reader in readers[key] ?? [] where expressions[reader] != nil {
        waiting[reader]! -= 1
        if waiting[reader] == 0 { ready.append(reader) }
      }
    }
    // Whatever never became ready sits on a loop or reads one.
    let kept = Set(sorted)
    for key in expressions.keys where !kept.contains(key) {
      reasons[key] = "Part of a circular reference."
    }
    expressions = expressions.filter { kept.contains($0.key) }
    order = sorted
  }
  /// Every recalculating cell, after the cells it reads.
  private(set) var order: [Key] = []
  /// The columns a pass reads or writes on one sheet.
  func columns(of sheet: Int) -> Set<Int> {
    var columns = Set<Int>()
    for key in order {
      if key.sheet == sheet { columns.insert(key.column) }
      for read in dependencies[key] ?? [] where read.sheet == sheet { columns.insert(read.column) }
    }
    return columns
  }

  /// The cells one formula reads, in reading order.
  func reads(_ key: Key) -> [Key] { (dependencies[key] ?? []).sorted() }

  /// Every recalculating cell's value, reading the stored value of anything else. A skipped cell
  /// has no result, so whatever reads it sees its stored value.
  func values(skipping skipped: (Key) -> Bool = { _ in false }, stored: (Key) -> SheetValue)
    -> [Key: SheetValue]
  {
    var results: [Key: SheetValue] = [:]
    for key in order where !skipped(key) {
      let value = expressions[key]!.evaluate { cell in
        guard let target = self.key(cell, from: key.sheet) else { return .error("#REF!") }
        return results[target] ?? stored(target)
      }
      results[key] = value == .blank ? .number(0) : value
    }
    return results
  }

  /// Drops cells whose result disagrees with what Excel saved, with everything reading them.
  mutating func exclude(_ mismatched: [Key: String]) {
    for (key, reason) in mismatched {
      expressions[key] = nil
      reasons[key] = reason
    }
    settle()
  }

  var settledCells: [SheetFormulaPlan.Cell] {
    plan.cells.map { entry in
      var cell = entry
      if let address = SheetFormulaToken.address(entry.cell) {
        cell.reason = reasons[Key(sheet: entry.sheet, column: address.column, row: address.row)]
      }
      return cell
    }
  }
}

extension SheetValue {
  init(stored text: String) {
    if text.isEmpty {
      self = .blank
    } else if let number = SheetFormula.number(text) {
      self = .number(number)
    } else if text.hasPrefix("#"), text.hasSuffix("!") || text.hasSuffix("?") || text == "#N/A" {
      self = .error(text)
    } else {
      self = .text(text)
    }
  }
}

extension Workbook {
  static let sheetFormulaKind = "excel-formulas"

  private func sheetFormulaPlan(_ datasetID: String) throws -> (id: String, plan: SheetFormulaPlan)? {
    try synchronized {
      guard
        let logical = try db.scalar(
          "SELECT value FROM meta WHERE key=?", [.string("sheet-formulas:" + datasetID)]
        ).string
      else { return nil }
      let record = try item(logical)
      return (
        record.id,
        try JSONDecoder().decode(SheetFormulaPlan.self, from: Data(record.data["plan"].text.utf8))
      )
    }
  }

  /// Runs once every sheet has its table. A formula joins the plan only if the declared
  /// subset reads it and reproduces the value Excel saved. Everything else keeps that value.
  func recordSheetFormulas(sourceID: String, sheets: [ImportedSheet], tables: [Dataset]) throws {
    guard sheets.contains(where: { !$0.formulas.isEmpty || !$0.formulaKinds.isEmpty }) else {
      return
    }
    let source = try item(sourceID)
    _ = try mutation("sheet_formulas", token: "sheet-formulas-" + sourceID) {
      let plan = try settledSheetFormulaPlan(sheets: sheets, tables: tables)
      let saved = plan.cells.filter { $0.reason != nil }.count
      let id = try insertItem(
        category: "record", kind: Self.sheetFormulaKind,
        title: source.title.prefix(4000) + ", Excel formulas",
        text: "\(plan.cells.count - saved) formulas recalculate. \(saved) keep their saved values.",
        data: .object([
          "plan": .string(String(decoding: try JSONEncoder().encode(plan), as: UTF8.self))
        ]), meaning: "actual", status: "accepted", scenario: "actual", inputs: [sourceID],
        transformation: "xlsx-formula-plan-v1")
      for table in tables {
        try db.execute(
          "INSERT INTO meta VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
          [.string("sheet-formulas:" + table.id), .string(try item(id).logicalID)])
      }
      // A row edited while the import was stopped already moved past the saved values. Excel's
      // own results stand until then, including ones that differ only in binary noise.
      if let table = tables.first {
        try applySheetFormulaChanges(try sheetFormulaChanges(after: table.id, importing: true))
      }
      return .string(id)
    }
  }

  private func settledSheetFormulaPlan(sheets: [ImportedSheet], tables: [Dataset]) throws
    -> SheetFormulaPlan
  {
    let oversized = sheets.reduce(0) { $0 + $1.rows.count } > SheetFormulaPlan.rowLimit
    // Cells past the fill bound are not listed, so any formula could be reading one.
    let unfollowed = sheets.contains { $0.formulaKinds["*"] != nil }
    var plan = SheetFormulaPlan(sheets: [], cells: [])
    var positions: [[Int: Int]] = []
    for (index, sheet) in sheets.enumerated() {
      let logical =
        oversized
        ? []
        : try db.execute(
          "SELECT logical_id FROM dataset_rows WHERE dataset_id=? ORDER BY ordinal",
          [.string(tables[index].id)]
        ).map { $0["logical_id"]!.text }
      try require(
        oversized || logical.count == sheet.rows.count, "sheet_formulas",
        "A worksheet no longer matches its table.")
      plan.sheets.append(
        .init(
          name: sheet.name, dataset: tables[index].id, width: tables[index].columns.count,
          rows: oversized ? [] : sheet.rowNumbers, logical: logical))
      positions.append(
        Dictionary(sheet.rowNumbers.enumerated().map { ($0.element, $0.offset) }) { first, _ in first })
      func reason(_ reference: String) -> String? {
        if oversized { return "The file has too many rows to recalculate." }
        if unfollowed { return "An Excel array or data table in this file is too large to follow." }
        switch sheet.formulaKinds[reference] {
        case "array": return "Filled by an Excel array formula."
        case "dataTable": return "Filled by an Excel data table."
        case "shared": return "Excel's shared formula could not be read."
        default: break
        }
        return sheet.unsettled[reference] == "uncached"
          ? "Excel saved no value for this formula." : nil
      }
      let references = Set(sheet.formulas.keys).union(sheet.formulaKinds.keys.filter { $0 != "*" })
      for reference in references.sorted(by: { Self.readingOrder($0, $1) }) {
        plan.cells.append(
          .init(
            sheet: index, cell: reference, formula: sheet.formulas[reference] ?? "",
            reason: reason(reference)))
      }
    }
    var engine = SheetFormulaEngine(plan: plan)
    func saved(_ key: SheetFormulaEngine.Key) -> String {
      guard let row = positions[key.sheet][key.row] else { return "" }
      let cells = sheets[key.sheet].rows[row]
      return key.column < cells.count ? cells[key.column] : ""
    }
    var mismatched: [SheetFormulaEngine.Key: String] = [:]
    for (key, value) in engine.values(stored: { SheetValue(stored: saved($0)) })
    where !SheetFormula.same(value, as: saved(key)) {
      mismatched[key] = "Sevra's result differs from the value Excel saved."
    }
    // A saved date reads as text here and as a number in Excel, so a formula can match by accident.
    for key in engine.order where mismatched[key] == nil {
      if let date = engine.reads(key).first(where: { isSheetDate(saved($0)) }) {
        mismatched[key] = "Reads the date in \(engine.name(date)), which Sevra does not calculate."
      }
    }
    engine.exclude(mismatched)
    plan.cells = engine.settledCells
    plan.capList()
    return plan
  }

  private func isSheetDate(_ text: String) -> Bool {
    text.range(
      of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z|Excel-only date", options: .regularExpression
    ) != nil
  }

  private static func readingOrder(_ first: String, _ second: String) -> Bool {
    guard let a = SheetFormulaToken.address(first), let b = SheetFormulaToken.address(second) else {
      return first < second
    }
    return (a.row, a.column) < (b.row, b.column)
  }

  /// Runs inside the change that altered a table, so saved rows are never behind their
  /// inputs. Only cells whose value moved get a new row version.
  func recalculateSheetFormulas(after datasetID: String) throws {
    try applySheetFormulaChanges(try sheetFormulaChanges(after: datasetID))
  }

  /// The cells that move, by row and column, once `pending` rows are saved. Every value comes
  /// from inputs, so an error clears as soon as its input does. A person's edit and the cells
  /// it recalculates can then share one row version, which Undo restores as one step.
  func sheetFormulaChanges(
    after datasetID: String, pending: [String: [String: Value]] = [:], importing: Bool = false
  ) throws -> (plan: String, cells: [String: [String: String]])? {
    guard let (planID, plan) = try sheetFormulaPlan(datasetID) else { return nil }
    let engine = SheetFormulaEngine(plan: plan)
    guard !engine.order.isEmpty else { return nil }
    typealias Key = SheetFormulaEngine.Key
    var texts: [Key: String] = [:]
    var rows: [Key: String] = [:]
    var mapped: [Int: Set<Int>] = [:]
    var columns: [Int: Set<Int>] = [:]
    var typed: [Int: [Column]] = [:]
    for (index, sheet) in plan.sheets.enumerated() {
      let needed = engine.columns(of: index)
      guard !needed.isEmpty else { continue }
      let schema = try db.managedSchema(sheet.dataset)
      typed[index] = schema.columns
      let active = needed.filter { column in schema.stored.contains { $0.id == "c\(column + 1)" } }
      let fields = active.map {
        ChangeFormat.quote(schema.field("c\($0 + 1)")) + " AS " + ChangeFormat.quote("c\($0)")
      }
      let numbers = Dictionary(zip(sheet.logical, sheet.rows)) { first, _ in first }
      mapped[index] = Set(sheet.rows)
      columns[index] = active
      for row in try db.execute(
        "SELECT " + ([ChangeFormat.quote("_sevra_logical")] + fields).joined(separator: ",")
          + " FROM " + ChangeFormat.quote(schema.table))
      {
        let logical = row["_sevra_logical"]!.text
        guard let number = numbers[logical] else { continue }
        rows[Key(sheet: index, column: -1, row: number)] = logical
        for column in active {
          texts[Key(sheet: index, column: column, row: number)] =
            pending[logical].map { $0["c\(column + 1)"]?.text ?? "" } ?? row["c\(column)"]?.text ?? ""
        }
      }
    }
    // A formula in a removed column writes nothing, and what reads it sees the broken reference.
    let results = engine.values(skipping: { columns[$0.sheet]?.contains($0.column) != true }) { key in
      // Rows and columns Excel left empty read as blank. Ones since removed are a broken reference.
      guard mapped[key.sheet]?.contains(key.row) == true else { return .blank }
      guard rows[Key(sheet: key.sheet, column: -1, row: key.row)] != nil else { return .error("#REF!") }
      guard columns[key.sheet]?.contains(key.column) == true else {
        return key.column < plan.sheets[key.sheet].width ? .error("#REF!") : .blank
      }
      return SheetValue(stored: texts[key] ?? "")
    }
    var changes: [String: [String: String]] = [:]
    for (key, value) in results {
      let saved = texts[key] ?? ""
      guard let logical = rows[Key(sheet: key.sheet, column: -1, row: key.row)],
        importing ? !SheetFormula.same(value, as: saved) : SheetFormula.moved(value, from: saved)
      else { continue }
      let id = "c\(key.column + 1)", text = SheetFormula.text(value)
      if let column = typed[key.sheet]?.first(where: { $0.id == id }) {
        do {
          try validateValues([id: .string(text)], columns: [column])
        } catch {
          throw SevraError(
            "formula_type",
            "Recalculating would put \(text) in \(column.title), which does not accept it. No changes were saved. Change the value or the column's type."
          )
        }
      }
      changes[logical, default: [:]][id] = text
    }
    try require(
      changes.count <= SheetFormulaPlan.rewriteLimit, "formula_limit",
      "This would recalculate more than \(SheetFormulaPlan.rewriteLimit.formatted()) rows. No changes were saved."
    )
    return (planID, changes)
  }

  func applySheetFormulaChanges(_ changes: (plan: String, cells: [String: [String: String]])?) throws {
    guard let changes else { return }
    for (logical, cells) in changes.cells.sorted(by: { $0.key < $1.key }) {
      let old = try item(logical)
      var values = old.data.object
      for (column, text) in cells { values[column] = .string(text) }
      _ = try insertItem(
        category: old.category, kind: old.kind, title: old.title, text: rowDescription(values),
        data: .object(values), meaning: old.meaning, status: old.status, scenario: old.scenario,
        inputs: [old.id, changes.plan], transformation: "xlsx-formula-recalculate-v1",
        supersedes: old.id)
    }
  }

  /// Runs at the end of every change that wrote table rows, however they were written.
  func recalculateChangedSheets() throws {
    let tables = tablesWithChangedRows
    tablesWithChangedRows = []
    var plans = Set<String>()
    for table in tables.sorted() {
      guard let (id, _) = try sheetFormulaPlan(table), plans.insert(id).inserted else { continue }
      try recalculateSheetFormulas(after: table)
    }
    tablesWithChangedRows = []
  }

  /// Columns per row that only recalculation may write.
  func recalculatingColumns(_ datasetID: String) throws -> [String: Set<String>] {
    var columns: [String: Set<String>] = [:]
    let cells = try sheetFormulaCells(datasetID) ?? [:]
    guard !cells.isEmpty else { return columns }
    let stored = Set(try synchronized { try db.managedSchema(datasetID).stored.map(\.id) })
    for (row, cells) in cells {
      let live = cells.filter { $0.value.reason == nil && stored.contains($0.key) }
      if !live.isEmpty { columns[row] = Set(live.keys) }
    }
    return columns
  }

  private func sheetFormulaCells(_ datasetID: String, shown: Set<String>? = nil) throws
    -> [String: [String: SheetFormulaCell]]?
  {
    guard let (_, plan) = try sheetFormulaPlan(datasetID),
      let sheet = plan.sheets.firstIndex(where: { $0.dataset == datasetID })
    else { return nil }
    return sheetFormulaCells(plan, sheet: sheet, shown: shown)
  }

  private func sheetFormulaCells(_ plan: SheetFormulaPlan, sheet: Int, shown: Set<String>?)
    -> [String: [String: SheetFormulaCell]]
  {
    let logical = Dictionary(zip(plan.sheets[sheet].rows, plan.sheets[sheet].logical)) { first, _ in first }
    var result: [String: [String: SheetFormulaCell]] = [:]
    for cell in plan.cells where cell.sheet == sheet {
      guard let address = SheetFormulaToken.address(cell.cell), let row = logical[address.row],
        shown?.contains(row) != false
      else { continue }
      result[row, default: [:]]["c\(address.column + 1)"] = .init(
        cell: cell.cell, formula: cell.formula, reason: cell.reason)
    }
    return result
  }

  private func sheetFormulaReport(_ plan: SheetFormulaPlan, sheet: Int) throws -> SheetFormulaReport {
    let own = plan.cells.filter { $0.sheet == sheet }
    let saved = own.filter { $0.reason != nil }
    let unlisted = sheet < plan.unlisted.count ? plan.unlisted[sheet] : 0
    var changed = false
    for table in plan.sheets where !changed {
      changed =
        try db.scalar(
          "SELECT EXISTS(SELECT 1 FROM dataset_rows d JOIN heads h ON h.logical_id=d.logical_id "
            + "JOIN items i ON i.id=h.item_id WHERE d.dataset_id=? AND i.version>1)",
          [.string(table.dataset)]
        ).int == 1
    }
    return .init(
      recalculating: own.count - saved.count, saved: saved.count + unlisted, valuesChanged: changed,
      savedCells: saved.prefix(SheetFormulaPlan.unlistedSample).map {
        .init(cell: $0.cell, formula: $0.formula, reason: $0.reason)
      })
  }

  /// The formula cells and summary a table page shows, from one read of the plan.
  func sheetFormulaPage(_ datasetID: String, rows: [Item]) throws
    -> (cells: [String: [String: SheetFormulaCell]], report: SheetFormulaReport)?
  {
    guard let (_, plan) = try sheetFormulaPlan(datasetID),
      let sheet = plan.sheets.firstIndex(where: { $0.dataset == datasetID }),
      plan.cells.contains(where: { $0.sheet == sheet })
    else { return nil }
    return (
      sheetFormulaCells(plan, sheet: sheet, shown: Set(rows.map(\.logicalID))),
      try sheetFormulaReport(plan, sheet: sheet)
    )
  }

  /// What one table's Excel formulas do, in a form a person or agent can repeat. Nil when
  /// the table did not come from a file with formulas.
  public func sheetFormulaReport(_ datasetID: String) throws -> SheetFormulaReport? {
    try synchronized { try sheetFormulaPage(datasetID, rows: [])?.report }
  }

  /// True while any cell in the file still follows its inputs.
  func hasRecalculatingFormulas(_ datasetID: String) throws -> Bool {
    try sheetFormulaPlan(datasetID)?.plan.cells.contains { $0.reason == nil } ?? false
  }

  /// The import summary across every table one file became.
  func sheetFormulaSummary(_ tables: [String]) throws -> (recalculating: Int, saved: Int)? {
    guard let table = tables.first, let (_, plan) = try sheetFormulaPlan(table) else { return nil }
    let saved = plan.cells.filter { $0.reason != nil }.count
    return (plan.cells.count - saved, saved + plan.unlisted.reduce(0, +))
  }
}
