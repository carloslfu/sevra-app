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
}

public struct TableUpdatePreview: Codable, Sendable {
  public let sourceID: String
  public let datasetID: String
  public let mode: TableUpdateMode
  public let mapping: [IntakeColumnMapping]
  public let keys: [String]
  public let headerRow: Int
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

  fileprivate init(
    sourceID: String, assetID: String, assetHash: String,
    headerRow: Int, headings: [String], rows: [[String]]
  ) {
    self.sourceID = sourceID
    self.assetID = assetID
    self.assetHash = assetHash
    self.headerRow = headerRow
    self.headings = headings
    self.rows = rows
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
    _ sourceID: String, headerRow: Int = 1, cancellation: Cancellation = .init()
  ) throws -> TableUpdateSource {
    let input = try tableUpdateInput(
      sourceID, headerRow: headerRow, cancellation: cancellation)
    return .init(
      sourceID: sourceID, headerRow: headerRow, headings: input.headings,
      incoming: input.rows.count, examples: Array(input.rows.prefix(5)))
  }

  func tableUpdateInput(
    _ sourceID: String, headerRow: Int, worker: ExtractionWorker = .init(),
    cancellation: Cancellation
  ) throws -> TableUpdateInput {
    try cancellation.check()
    let source = try item(sourceID)
    guard source.category == "source", let assetID = source.assetID else {
      throw SevraError("intake_source", "Choose a captured original CSV or TSV.")
    }
    let asset = try self.asset(assetID)
    let file = try assetURL(assetID, verify: true, cancellation: cancellation)
    guard let format = StructuredFormat(rawValue: file.pathExtension.lowercased()), format != .xlsx
    else {
      throw SevraError(
        "update_format",
        "Reviewed updates currently support CSV and TSV. Excel update mapping is not implemented.")
    }
    let parsed = try worker.readTable(file, format: format, cancellation: cancellation)
    _ = try assetURL(assetID, verify: true, cancellation: cancellation)
    let sheet = parsed.sheets[0]
    try require(
      headerRow > 0 && headerRow <= sheet.rows.count,
      "update_header", "Choose an existing header row.")
    let header = sheet.rows[headerRow - 1]
    let input = Array(sheet.rows.dropFirst(headerRow))
    try require(
      !header.isEmpty && input.count <= 1000, "update_limit",
      "Review at most 1,000 incoming rows at a time.")
    try require(
      input.allSatisfy { $0.count <= header.count }, "update_mapping",
      "An input row extends beyond the selected headings.")
    return .init(
      sourceID: source.id, assetID: assetID, assetHash: asset.hash,
      headerRow: headerRow, headings: header, rows: input)
  }

  /// Inspect only. A preview cannot apply rows or accept inventory/financial effects.
  /// Explicit full mappings are the first qualified subset; no header/key/locale guessing.
  public func previewTableUpdate(
    sourceID: String, datasetID: String, mode: TableUpdateMode,
    mapping: [IntakeColumnMapping], keys: [String] = [], headerRow: Int = 1,
    cancellation: Cancellation = .init()
  ) throws -> TableUpdatePreview {
    try tableUpdatePlan(
      sourceID: sourceID, datasetID: datasetID, mode: mode,
      mapping: mapping, keys: keys, headerRow: headerRow,
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
    mapping: [IntakeColumnMapping], keys: [String], headerRow: Int,
    cancellation: Cancellation
  ) throws -> TableUpdatePlan {
    let input = try tableUpdateInput(
      sourceID, headerRow: headerRow, cancellation: cancellation)
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
        let mapped = try input.map { values -> [String: Value] in
          try cancellation.check()
          let row = Dictionary(
            uniqueKeysWithValues: mapping.compactMap { entry -> (String, Value)? in
              guard let target = entry.target else { return nil }
              let value = entry.position < values.count ? values[entry.position] : ""
              return (target, value.isEmpty ? .null : .string(value))
            })
          try validateValues(row, columns: table.columns)
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
        if mode == .merge {
          for row in existing {
            let value = try key(row.data.object)
            try require(
              keyed[value] == nil, "update_key_duplicate",
              "The target has duplicate merge keys. Resolve them before updating.")
            keyed[value] = row
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
          let sourceRecord = headerRow + index + 1
          try cancellation.check()
          let digest = try Value.object(row).json()
          if !digests.insert(digest).inserted { repeated += 1 }
          if existingValues.contains(digest) { matching += 1 }
          if mode == .merge {
            let value = try key(row)
            try require(
              incomingKeys.insert(value).inserted, "update_key_duplicate",
              "The input has duplicate merge keys. No row was chosen automatically.")
            if let old = keyed[value] {
              var values = old.data.object
              for (column, value) in row { values[column] = value }
              if stored.allSatisfy({ row[$0.id] == old.data[$0.id] }) {
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
          mapping: mapping, keys: keys, headerRow: headerRow, headings: header,
          columns: table.columns,
          revision: try revision(),
          fingerprint: try tableFingerprint(datasetID), incoming: mapped.count,
          added: additions.count, changed: changes.count,
          removed: mode == .replace ? existing.count : 0, unchanged: unchanged,
          repeatedIncomingRows: repeated, rowsMatchingTarget: matching, examples: examples,
          limitations: [
            "CSV/TSV values only; full stored-column mapping; lexical merge keys.",
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
}
