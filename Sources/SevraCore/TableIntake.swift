import CryptoKit
import Foundation

public enum TableUpdateMode: String, Codable, Sendable { case append, replace, merge }

/// Every input position is accounted for. A nil target explicitly ignores that column.
public struct IntakeColumnMapping: Codable, Equatable, Sendable {
  public let position: Int
  public let target: String?
  public init(position: Int, target: String?) {
    self.position = position
    self.target = target
  }
}

public struct TableUpdateSource: Codable, Sendable {
  public let sourceID: String
  public let headerRow: Int
  public let headings: [String]
  public let incoming: Int
  public let examples: [[String]]
  /// Worksheet names of an Excel original in file order. Empty for CSV and TSV.
  public let sheets: [String]
  public let sheet: String?
  /// What an Excel review must disclose about saved values.
  public let notes: [String]
  /// A multi-sheet original returns its names first; nothing is read until one is chosen.
  public var needsSheet: Bool { !sheets.isEmpty && sheet == nil }
}

public struct TableUpdatePreview: Codable, Sendable {
  public let sourceID: String
  public let datasetID: String
  public let mode: TableUpdateMode
  public let mapping: [IntakeColumnMapping]
  public let keys: [String]
  public let headerRow: Int
  public let sheet: String?
  public let headings: [String]
  public let columns: [Column]
  public let revision: Int
  public let fingerprint: String
  public let incoming: Int
  public let added: Int
  public let changed: Int
  public let removed: Int
  public let unchanged: Int
  public let repeatedIncomingRows: Int
  public let rowsMatchingTarget: Int
  public let examples: [Value]
  public let limitations: [String]
}

/// Created only by the verified native parser boundary. Planning consumes this
/// value without reopening a file or running a child under a workbook lock.
struct TableUpdateInput: Sendable {
  let sourceID: String
  let assetID: String
  let assetHash: String
  let headerRow: Int
  let headings: [String]
  let rows: [[String]]
  /// The original's record number for each row, which skips empty worksheet rows.
  let records: [Int]
  let sheet: String?
  let notes: [String]
  let formulas: Set<String>
  let unsettled: [String: String]

  fileprivate init(
    sourceID: String, assetID: String, assetHash: String,
    headerRow: Int, headings: [String], rows: [[String]], records: [Int],
    sheet: String? = nil, notes: [String] = [], formulas: Set<String> = [],
    unsettled: [String: String] = [:]
  ) {
    self.sourceID = sourceID
    self.assetID = assetID
    self.assetHash = assetHash
    self.headerRow = headerRow
    self.headings = headings
    self.rows = rows
    self.records = records
    self.sheet = sheet
    self.notes = notes
    self.formulas = formulas
    self.unsettled = unsettled
  }
}

/// The verified parse of one original, before a header or worksheet is chosen.
private struct TableUpdateOriginal {
  let sourceID: String
  let assetID: String
  let assetHash: String
  let format: StructuredFormat
  let sheets: [ImportedSheet]

  func input(headerRow: Int, sheet name: String?) throws -> TableUpdateInput {
    let chosen: ImportedSheet
    if format == .xlsx {
      let named = name.flatMap { name in sheets.first { $0.name == name } }
      guard let match = named ?? (name == nil && sheets.count == 1 ? sheets.first : nil) else {
        throw SevraError(
          "update_sheet", name == nil ? "Choose a worksheet." : "This file has no such worksheet.")
      }
      chosen = match
    } else {
      try require(name == nil, "update_sheet", "Only Excel files have worksheets.")
      chosen = sheets[0]
    }
    guard let index = chosen.rowNumbers.firstIndex(of: headerRow) else {
      throw SevraError(
        "update_header",
        "Choose an existing header row."
          + (chosen.rowNumbers.first.map { " The first row with values is \($0)." } ?? ""))
    }
    var header = chosen.rows[index]
    var rows = Array(chosen.rows.dropFirst(index + 1))
    var records = Array(chosen.rowNumbers.dropFirst(index + 1))
    if format == .xlsx {
      // A worksheet's used range often runs past the table with empty styled cells.
      while header.last?.isEmpty == true { header.removeLast() }
      let kept = zip(rows, records).filter { row, _ in row.contains { !$0.isEmpty } }
      rows = kept.map { row, _ in
        row.count > header.count && row[header.count...].allSatisfy(\.isEmpty)
          ? Array(row[..<header.count]) : row
      }
      records = kept.map(\.1)
    }
    try require(
      !header.isEmpty && rows.count <= 1000, "update_limit",
      header.isEmpty ? "That row has no headings." : "Review at most 1,000 incoming rows at a time."
    )
    try require(
      rows.allSatisfy { $0.count <= header.count }, "update_mapping",
      "An input row extends beyond the selected headings.")
    return .init(
      sourceID: sourceID, assetID: assetID, assetHash: assetHash, headerRow: headerRow,
      headings: header, rows: rows, records: records,
      sheet: format == .xlsx ? chosen.name : nil, notes: chosen.notes,
      formulas: Set(chosen.formulas.keys), unsettled: chosen.unsettled)
  }
}

struct TableUpdatePlan: Sendable {
  let preview: TableUpdatePreview
  let columns: [Column]
  let membership: [Value]
  let incoming: [[String: Value]]
  let changes: [RowEdit]
  let additions: [[String: Value]]
  let changeRecords: [String: Int]
  let additionRecords: [Int]
}

extension Workbook {
  /// The same bounded, verified parser supplies native mapping and the final preview.
  public func inspectTableUpdateSource(
    _ sourceID: String, headerRow: Int = 1, sheet: String? = nil,
    cancellation: Cancellation = .init()
  ) throws -> TableUpdateSource {
    let original = try tableUpdateOriginal(
      sourceID, worker: .init(), cancellation: cancellation)
    let names = original.format == .xlsx ? original.sheets.map(\.name) : []
    if sheet == nil && names.count > 1 {
      return .init(
        sourceID: sourceID, headerRow: headerRow, headings: [], incoming: 0, examples: [],
        sheets: names, sheet: nil, notes: [])
    }
    let input = try original.input(headerRow: headerRow, sheet: sheet)
    return .init(
      sourceID: sourceID, headerRow: headerRow, headings: input.headings,
      incoming: input.rows.count, examples: Array(input.rows.prefix(5)),
      sheets: names, sheet: input.sheet, notes: input.notes)
  }

  /// A pending update needs a readable original. The header row is chosen during
  /// review, so its first row need not be the heading.
  func validateTableUpdateOriginal(_ sourceID: String, cancellation: Cancellation) throws {
    _ = try tableUpdateOriginal(sourceID, worker: .init(), cancellation: cancellation)
  }

  func tableUpdateInput(
    _ sourceID: String, headerRow: Int, sheet: String? = nil, worker: ExtractionWorker = .init(),
    cancellation: Cancellation
  ) throws -> TableUpdateInput {
    try tableUpdateOriginal(sourceID, worker: worker, cancellation: cancellation)
      .input(headerRow: headerRow, sheet: sheet)
  }

  private func tableUpdateOriginal(
    _ sourceID: String, worker: ExtractionWorker, cancellation: Cancellation
  ) throws -> TableUpdateOriginal {
    try cancellation.check()
    let source = try item(sourceID)
    guard source.category == "source", let assetID = source.assetID else {
      throw SevraError("intake_source", "Choose a captured original CSV, TSV or XLSX file.")
    }
    let asset = try self.asset(assetID)
    let file = try assetURL(assetID, verify: true, cancellation: cancellation)
    guard let format = StructuredFormat(rawValue: file.pathExtension.lowercased()) else {
      throw SevraError("update_format", "Reviewed updates support CSV, TSV and XLSX saved values.")
    }
    let parsed = try worker.readTable(file, format: format, cancellation: cancellation)
    _ = try assetURL(assetID, verify: true, cancellation: cancellation)
    return .init(
      sourceID: source.id, assetID: assetID, assetHash: asset.hash, format: format,
      sheets: parsed.sheets)
  }

  /// Inspect only. A preview cannot apply rows or accept inventory/financial effects.
  /// Explicit full mappings are the first qualified subset; no header/key/locale guessing.
  public func previewTableUpdate(
    sourceID: String, datasetID: String, mode: TableUpdateMode,
    mapping: [IntakeColumnMapping], keys: [String] = [], headerRow: Int = 1,
    sheet: String? = nil, cancellation: Cancellation = .init()
  ) throws -> TableUpdatePreview {
    try tableUpdatePlan(
      sourceID: sourceID, datasetID: datasetID, mode: mode,
      mapping: mapping, keys: keys, headerRow: headerRow, sheet: sheet,
      cancellation: cancellation
    ).preview
  }

  func tableMembership(_ datasetID: String) throws -> [Value] {
    try db.execute(
      "SELECT r.row_id,r.ordinal,r.logical_id,h.item_id FROM dataset_rows r JOIN heads h ON h.logical_id=r.logical_id WHERE r.dataset_id=? ORDER BY r.ordinal,r.row_id",
      [.string(datasetID)]
    ).map(Value.object)
  }

  func tableFingerprint(_ datasetID: String) throws -> String {
    let table = try dataset(datasetID)
    let state: Value = .object([
      "columns": try encoded(table.columns), "membership": .array(try tableMembership(datasetID)),
      "archived": .bool(table.archived), "definitionID": .string(table.definitionID),
    ])
    return SHA256.hash(data: Data(try state.json().utf8)).map { String(format: "%02x", $0) }
      .joined()
  }

  func tableUpdatePlan(
    sourceID: String, datasetID: String, mode: TableUpdateMode,
    mapping: [IntakeColumnMapping], keys: [String], headerRow: Int, sheet: String? = nil,
    cancellation: Cancellation
  ) throws -> TableUpdatePlan {
    let input = try tableUpdateInput(
      sourceID, headerRow: headerRow, sheet: sheet, cancellation: cancellation)
    return try tableUpdatePlan(
      input: input, datasetID: datasetID, mode: mode, mapping: mapping, keys: keys,
      cancellation: cancellation)
  }

  func tableUpdatePlan(
    input parsed: TableUpdateInput, datasetID: String, mode: TableUpdateMode,
    mapping: [IntakeColumnMapping], keys: [String], cancellation: Cancellation
  ) throws -> TableUpdatePlan {
    let header = parsed.headings
    let input = parsed.rows
    let headerRow = parsed.headerRow
    try require(
      !(try hasRecalculatingFormulas(datasetID)), "update_formulas",
      "This table has Excel formulas that recalculate, so a reviewed update cannot change it yet.")
    try require(
      mapping.count == header.count && Set(mapping.map(\.position)) == Set(header.indices),
      "update_mapping", "Map or explicitly ignore each incoming column once.")
    let targets = mapping.compactMap(\.target)
    try require(
      Set(targets).count == targets.count, "update_mapping",
      "Each target column can have only one input.")
    try require(
      Set(keys).count == keys.count && (mode == .merge ? !keys.isEmpty : keys.isEmpty),
      "update_keys",
      "Keyed merge needs explicit unique key columns; append and replacement do not take keys.")
    return try synchronized(cancellation: cancellation) {
      try db.readTransaction {
        let table = try dataset(datasetID)
        try require(
          table.rowCount <= 10_000, "update_limit",
          "This update review supports target tables of up to 10,000 rows.")
        let contentBytes =
          try db.scalar(
            "SELECT COALESCE(sum(length(CAST(i.data AS BLOB))+length(CAST(i.body AS BLOB))),0) FROM dataset_rows r JOIN heads h ON h.logical_id=r.logical_id JOIN items i ON i.id=h.item_id WHERE r.dataset_id=?",
            [.string(datasetID)]
          ).int ?? Int.max
        try require(
          contentBytes <= 16_000_000, "update_limit",
          "The target exceeds the 16 MB bounded update-review budget.")
        try require(
          !table.archived,
          "update_target", "Choose a current working table, not an archived result.")
        let stored = table.columns.filter { $0.formula == nil }
        try require(
          Set(targets) == Set(stored.map(\.id)), "update_mapping",
          "Map every stored target column. Calculated columns cannot be imported; partial-column updates are not supported yet."
        )
        try require(
          Set(keys).isSubset(of: Set(targets)), "update_keys", "Keys must be mapped stored columns."
        )
        let membership = try tableMembership(datasetID)
        let existing = try membership.map { try item($0["item_id"].text) }
        // A number Excel shows differently is safe only where the amount alone matters.
        // Imported identifiers such as 0012 can be decimal columns, so keys and columns
        // with leading zeros count as exact text.
        let amounts = Set(
          stored.filter { column in
            column.type == "decimal" && !keys.contains(column.id)
              && !existing.contains {
                $0.data[column.id].text.range(of: "^0[0-9]", options: .regularExpression) != nil
              }
          }.map(\.id))
        var formulaCells = 0
        let mapped = try zip(input, parsed.records).map { values, record -> [String: Value] in
          try cancellation.check()
          for entry in mapping where entry.target != nil && entry.position < values.count {
            guard !parsed.formulas.isEmpty || !parsed.unsettled.isEmpty else { break }
            let cell = XLSX.cellName(column: entry.position, row: record)
            if parsed.formulas.contains(cell) { formulaCells += 1 }
            try requireSettled(
              cell, value: values[entry.position], reason: parsed.unsettled[cell],
              amount: amounts.contains(entry.target!))
          }
          let row = Dictionary(
            uniqueKeysWithValues: mapping.compactMap { entry -> (String, Value)? in
              guard let target = entry.target else { return nil }
              let value = entry.position < values.count ? values[entry.position] : ""
              return (target, value.isEmpty ? .null : .string(value))
            })
          do {
            try validateValues(row, columns: table.columns)
          } catch let error as SevraError {
            throw SevraError(error.code, "Source record \(record): " + error.message)
          }
          return row
        }
        try require(
          try Value.array(mapped.map(Value.object)).json().utf8.count <= 8_000_000,
          "update_limit", "The reviewed update exceeds 8 MB of mapped values.")
        func key(_ row: [String: Value]) throws -> String {
          let values = keys.map { row[$0] ?? .null }
          try require(
            values.allSatisfy { $0 != .null && !$0.text.isEmpty }, "update_key_missing",
            "A merge key is empty. Choose a key or correct the source before continuing.")
          // Lexical keys preserve leading zeros, whitespace and case; no locale coercion.
          return try Value.array(values).json()
        }
        var keyed: [String: Item] = [:]
        // Keys stay exact, so a near match is neither a match nor safely a new row:
        // 14 beside 0014 is probably the same key with its zeros lost.
        func near(_ row: [String: Value]) -> String {
          keys.map { key in
            let text = (row[key] ?? .null).text.trimmingCharacters(in: .whitespacesAndNewlines)
              .lowercased()
            return (try? Numbers.decimal(text)).map(Numbers.string) ?? text
          }.joined(separator: "\u{1f}")
        }
        func shown(_ row: [String: Value]) -> String {
          keys.map { (row[$0] ?? .null).text }.joined(separator: " / ")
        }
        var nearKeys: [String: [String: Value]] = [:]
        if mode == .merge {
          for row in existing {
            let value = try key(row.data.object)
            try require(
              keyed[value] == nil, "update_key_duplicate",
              "The target has duplicate merge keys. Resolve them before updating.")
            keyed[value] = row
            nearKeys[near(row.data.object)] = row.data.object
          }
        }
        var incomingKeys = Set<String>()
        var digests = Set<String>()
        let existingValues = try Set(
          existing.map { old in
            try Value.object(Dictionary(uniqueKeysWithValues: targets.map { ($0, old.data[$0]) }))
              .json()
          })
        var repeated = 0
        var unchanged = 0
        var matching = 0
        var changes: [RowEdit] = []
        var additions: [[String: Value]] = []
        var changeRecords: [String: Int] = [:]
        var additionRecords: [Int] = []
        var examples: [Value] = []
        for (index, row) in mapped.enumerated() {
          let sourceRecord = parsed.records[index]
          try cancellation.check()
          let digest = try Value.object(row).json()
          if !digests.insert(digest).inserted { repeated += 1 }
          if existingValues.contains(digest) { matching += 1 }
          if mode == .merge {
            let value = try key(row)
            try require(
              incomingKeys.insert(value).inserted, "update_key_duplicate",
              "The input has duplicate merge keys. No row was chosen automatically.")
            if keyed[value] == nil, let other = nearKeys[near(row)] {
              throw SevraError(
                "update_key_ambiguous",
                "Source record \(sourceRecord) has key \u{2018}\(shown(row))\u{2019}, close to \u{2018}\(shown(other))\u{2019}. Keys must match exactly, so correct the source or choose another key."
              )
            }
            nearKeys[near(row)] = row
            if let old = keyed[value] {
              // A removed column stays in the row's history, not in an edit of it.
              var values = Self.activeValues(old.data.object, columns: table.columns)
              let moved = stored.filter { !sameValue($0, row[$0.id] ?? .null, old.data[$0.id]) }
              for column in moved { values[column.id] = row[column.id] ?? .null }
              // Acceptance reviews every stored column, including one added after this row.
              for column in stored where values[column.id] == nil { values[column.id] = .null }
              if moved.isEmpty {
                unchanged += 1
              } else {
                changes.append(.init(id: old.id, values: values))
                changeRecords[old.id] = sourceRecord
                if examples.count < 20 {
                  examples.append(
                    .object([
                      "operation": .string("change"), "rowID": .string(old.id),
                      "sourceRecord": .number(Double(sourceRecord)),
                      "before": old.data, "after": .object(values),
                    ]))
                }
              }
              continue
            }
          }
          additions.append(row)
          additionRecords.append(sourceRecord)
          if examples.count < 20 {
            examples.append(
              .object([
                "operation": .string("add"), "after": .object(row),
                "sourceRecord": .number(Double(sourceRecord)),
              ]))
          }
        }
        let preview = TableUpdatePreview(
          sourceID: parsed.sourceID, datasetID: datasetID, mode: mode,
          mapping: mapping, keys: keys, headerRow: headerRow, sheet: parsed.sheet,
          headings: header, columns: table.columns,
          revision: try revision(),
          fingerprint: try tableFingerprint(datasetID), incoming: mapped.count,
          added: additions.count, changed: changes.count,
          removed: mode == .replace ? existing.count : 0, unchanged: unchanged,
          repeatedIncomingRows: repeated, rowsMatchingTarget: matching, examples: examples,
          limitations: [
            (parsed.sheet == nil ? "CSV/TSV values only" : "Saved Excel cell values only")
              + "; full stored-column mapping; lexical merge keys."
          ] + (formulaCells > 0
            ? [
              (formulaCells == 1
                ? "1 mapped cell is a saved formula result"
                : "\(formulaCells) mapped cells are saved formula results")
                + "; formulas are not recalculated."
            ]
            : []) + [
            "No business inventory or financial effects are accepted by updating table values.",
            "Append keeps duplicates. Replacement removes every current target row.",
          ])
        return .init(
          preview: preview, columns: table.columns, membership: membership,
          incoming: mapped, changes: changes, additions: additions,
          changeRecords: changeRecords, additionRecords: additionRecords)
      }
    }
  }

  /// An Excel error or unsaved formula has no value to import.
  private func requireSettled(_ cell: String, value: String, reason: String?, amount: Bool) throws {
    switch reason {
    case "error":
      throw SevraError(
        "update_value",
        "Cell \(cell) holds the Excel error \(value). Correct it, save the file and add it again.")
    case "uncached":
      throw SevraError(
        "update_value",
        "Cell \(cell) is a formula with no saved value. Open the file in Excel, save it and add it again."
      )
    case "format" where !amount:
      throw SevraError(
        "update_value",
        "Cell \(cell) saves \(value), but Excel shows it differently. Store that column as text, save the file and add it again."
      )
    default: break
    }
  }

  /// Decimal columns compare amounts, so 1.2 does not change a saved 1.20.
  private func sameValue(_ column: Column, _ new: Value, _ old: Value) -> Bool {
    if new == old { return true }
    guard column.type == "decimal", new != .null, old != .null,
      let left = try? Numbers.decimal(new.text), let right = try? Numbers.decimal(old.text)
    else { return false }
    return left == right
  }
}
