import Foundation

public struct Column: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var type: String
  public var formula: String?
  public var unit: String?
  public init(
    id: String, title: String, type: String = "text", formula: String? = nil, unit: String? = nil
  ) {
    self.id = id
    self.title = title
    self.type = type
    self.formula = formula
    self.unit = unit
  }
}
public struct Dataset: Codable, Identifiable, Sendable {
  public let id: String
  public let title: String
  public let columns: [Column]
  public let rowCount: Int
}
public struct RowEdit: Codable, Sendable {
  public let id: String
  public let values: [String: Value]
  public init(id: String, values: [String: Value]) {
    self.id = id
    self.values = values
  }
}
public struct TableEdit: Codable, Sendable {
  public let id: String
  public let items: [Item]
}
/// The grid's rows, totals, schema and calculated values belong to one read snapshot.
public struct TablePage: Sendable {
  public let dataset: Dataset
  public let rows: [Item]
  public let values: [[String: Value]]
  public let total: Int
  public let revision: Int
  public let offset: Int
}
public enum CSV {
  public static func parse(_ text: String, delimiter: Character = ",") throws -> [[String]] {
    var result: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    let chars = Array(text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text)
    var i = 0
    while i < chars.count {
      let c = chars[i]
      if c == "\"" {
        if quoted && i + 1 < chars.count && chars[i + 1] == "\"" {
          field.append("\"")
          i += 1
        } else if quoted || field.isEmpty {
          quoted.toggle()
        } else {
          throw SevraError("csv", "Unexpected quote inside an unquoted field.")
        }
      } else if c == delimiter && !quoted {
        row.append(field)
        field = ""
      } else if (c == "\n" || c == "\r" || c == "\r\n") && !quoted {
        row.append(field)
        result.append(row)
        row = []
        field = ""
      } else {
        field.append(c)
      }
      try require(
        field.utf8.count <= 1_000_000 && row.count <= 500 && result.count <= 100_000, "csv_limit",
        "CSV exceeds the current field, column or row limit.")
      i += 1
    }
    try require(!quoted, "csv", "Unclosed quoted CSV field.")
    if !field.isEmpty || !row.isEmpty {
      row.append(field)
      result.append(row)
    }
    return result
  }
  public static func encode(_ rows: [[String]]) -> String {
    rows.map { row in
      row.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(
        separator: ",")
    }.joined(separator: "\r\n") + "\r\n"
  }
}
extension Workbook {
  @discardableResult public func importCSV(_ sourceID: String, cancellation: Cancellation = .init())
    throws -> Dataset
  {
    try cancellation.check()
    let source = try item(sourceID)
    guard let asset = source.assetID else { throw SevraError("csv", "CSV source has no file.") }
    let file = try assetURL(asset, cancellation: cancellation)
    try require(
      try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 <= 32_000_000, "csv_limit",
      "Structured CSV import is limited to 32 MB per file in this version.")
    let rows = try CSV.parse(
      String(contentsOf: file, encoding: .utf8),
      delimiter: file.pathExtension.lowercased() == "tsv" ? "\t" : ",")
    guard let header = rows.first, !header.isEmpty else {
      throw SevraError("csv", "This CSV is empty.")
    }
    try require(
      rows.dropFirst().allSatisfy { $0.count <= header.count }, "csv_columns",
      "A data row has more values than the header. Correct the original header before importing.")
    try cancellation.check()
    var used = Set<String>()
    let columns = header.enumerated().map { i, name -> Column in
      let title =
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Column \(i+1)" : name
      var id = title.lowercased().replacingOccurrences(
        of: "[^a-z0-9_]+", with: "_", options: .regularExpression)
      if id.isEmpty { id = "column_\(i+1)" }
      while used.contains(id) { id += "_\(i+1)" }
      used.insert(id)
      let samples = rows.dropFirst().compactMap { i < $0.count ? $0[i] : nil }.filter {
        !$0.isEmpty
      }
      let numeric = !samples.isEmpty && samples.allSatisfy { (try? Numbers.decimal($0)) != nil }
      return Column(id: id, title: title, type: numeric ? "decimal" : "text")
    }
    return try importDataset(
      title: source.title, columns: columns,
      rows: rows.dropFirst().map { values in
        Dictionary(
          uniqueKeysWithValues: columns.enumerated().map { i, c in
            (c.id, i < values.count && !values[i].isEmpty ? .string(values[i]) : Value.null)
          })
      }, sourceID: sourceID, cancellation: cancellation)
  }
  public func createDataset(
    title: String, columns: [Column], rows: [[String: Value]], sourceID: String,
    token: String = identifier()
  ) throws -> Dataset {
    _ = try item(sourceID)
    try require(
      !columns.isEmpty && columns.count <= 500 && Set(columns.map(\.id)).count == columns.count,
      "columns", "Columns require unique identifiers.")
    let id = identifier()
    let columnsJSON = try encoded(columns).json()
    let result = try mutation(
      "dataset", token: token,
      request: .object([
        "title": .string(title), "source": .string(sourceID), "columns": .string(columnsJSON),
        "rows": .string(try Self.rowDigest(rows)),
      ])
    ) {
      try insertDataset(
        id: id, title: title, columns: columns, rows: rows, sourceID: sourceID, inputs: [sourceID],
        meaning: "actual")
      return .string(id)
    }
    return try dataset(result.text)
  }
  func insertDataset(
    id: String, title: String, columns: [Column], rows: [[String: Value]], sourceID: String,
    inputs: [String], meaning: String
  ) throws {
    let columnsJSON = try encoded(columns).json()
    try validateColumns(columns)
    try db.execute(
      "INSERT INTO datasets VALUES(?,?,?,?)",
      [.string(id), .string(title), .string(columnsJSON), .string(sourceID)])
    try db.execute(
      "INSERT INTO column_versions VALUES(?,?,?,?)",
      [.string(id), .number(1), .string(columnsJSON), .string(timestamp())])
    for (n, values) in rows.enumerated() {
      try validateValues(values, columns: columns)
      let itemID = try insertItem(
        category: "record", kind: "row", title: "\(title), row \(n+1)",
        text: values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.text)" }.joined(
          separator: "\n"), data: .object(values), meaning: meaning, status: "accepted",
        scenario: meaning == "actual" ? "actual" : "planning", inputs: inputs,
        transformation: "table-intake-v1")
      let row = try item(itemID)
      try db.execute(
        "INSERT INTO dataset_rows VALUES(?,?,?,?)",
        [.string(id), .string(identifier()), .number(Double(n)), .string(row.logicalID)])
    }
  }
  public func dataset(_ id: String) throws -> Dataset {
    try synchronized {
      guard
        let d = try db.execute(
          "SELECT *, (SELECT count(*) FROM dataset_rows WHERE dataset_id=datasets.id) AS count FROM datasets WHERE id=?",
          [.string(id)]
        ).first
      else { throw SevraError("not_found", "Table not found.") }
      return Dataset(
        id: id, title: d["title"]!.text,
        columns: try JSONDecoder().decode([Column].self, from: Data(d["columns"]!.text.utf8)),
        rowCount: d["count"]!.int!)
    }
  }
  public func datasets() throws -> [Dataset] {
    try synchronized {
      try db.execute(
        "SELECT id FROM datasets WHERE NOT EXISTS(SELECT 1 FROM meta WHERE key='archived-dataset:'||datasets.id AND value='1') ORDER BY title LIMIT 500"
      ).map {
        try dataset($0["id"]!.text)
      }
    }
  }
  public func rows(
    _ datasetID: String, offset: Int = 0, limit: Int = 200, query: String = "", sort: String? = nil,
    descending: Bool = false
  ) throws -> [Item] {
    try synchronized {
      let table = try dataset(datasetID)
      let term = try Self.searchTerms(query)
      var args: [Value] = [.string(datasetID)]
      let filter =
        term.isEmpty
        ? ""
        : " AND i.id IN (SELECT c.item_id FROM search_fts JOIN chunks c ON c.id=search_fts.rowid WHERE search_fts MATCH ?)"
      if !term.isEmpty { args.append(.string(term)) }
      var order = "r.ordinal"
      if let sort {
        guard let column = table.columns.first(where: { $0.id == sort }) else {
          throw SevraError("column", "Unknown sort column.")
        }
        try require(
          column.formula == nil, "sort_formula",
          "Sort a stored column; calculated-column sorting needs a materialized result.")
        let path = "$.\"" + column.id.replacingOccurrences(of: "\"", with: "") + "\""
        order =
          "json_extract(i.data,?) COLLATE "
          + (column.type == "decimal" ? "SEVRA_DECIMAL" : "NOCASE")
          + (descending ? " DESC" : " ASC") + ",r.ordinal"
        args.append(.string(path))
      }
      args += [.number(Double(min(max(limit, 1), 1000))), .number(Double(max(offset, 0)))]
      return try db.execute(
        "SELECT i.* FROM dataset_rows r JOIN heads h ON h.logical_id=r.logical_id JOIN items i ON i.id=h.item_id WHERE r.dataset_id=? \(filter) ORDER BY \(order) LIMIT ? OFFSET ?",
        args
      ).map(decodeItem)
    }
  }
  public func filteredRowCount(_ datasetID: String, query: String) throws -> Int {
    try synchronized {
      let term = try Self.searchTerms(query)
      if term.isEmpty { return try dataset(datasetID).rowCount }
      return try db.scalar(
        "SELECT count(*) FROM dataset_rows r JOIN heads h ON h.logical_id=r.logical_id WHERE r.dataset_id=? AND h.item_id IN(SELECT c.item_id FROM search_fts JOIN chunks c ON c.id=search_fts.rowid WHERE search_fts MATCH ?)",
        [.string(datasetID), .string(term)]
      ).int ?? 0
    }
  }
  public func tablePage(
    _ datasetID: String, offset: Int = 0, limit: Int = 200, query: String = "",
    sort: String? = nil, descending: Bool = false
  ) throws -> TablePage {
    try synchronized {
      try db.readTransaction {
        let table = try dataset(datasetID)
        let rows = try rows(
          datasetID, offset: offset, limit: limit, query: query, sort: sort,
          descending: descending)
        return TablePage(
          dataset: table, rows: rows,
          values: rows.map { calculatedValues($0, columns: table.columns) },
          total: try filteredRowCount(datasetID, query: query), revision: try revision(),
          offset: max(0, offset))
      }
    }
  }
  public func calculatedValues(_ row: Item, columns: [Column]) -> [String: Value] {
    var output = row.data.object
    var visiting = Set<String>()
    var cache: [String: Decimal] = [:]
    let raw = row.data.object.filter { entry in
      !columns.contains { $0.id == entry.key && $0.formula != nil }
    }
    var datasetID: String?
    func resolve(_ column: Column) throws -> Decimal {
      if let found = cache[column.id] { return found }
      try require(
        !visiting.contains(column.id), "formula_cycle", "Formula cycle at \(column.title).")
      visiting.insert(column.id)
      defer { visiting.remove(column.id) }
      guard let formula = column.formula else {
        return try Numbers.decimal(raw[column.id]?.text ?? "")
      }
      let result = try Numbers.calculate(formula, values: raw) { name in
        if let c = columns.first(where: { $0.id == name }) { return try resolve(c) }
        if datasetID == nil {
          datasetID = try self.synchronized {
            try self.db.scalar(
              "SELECT dataset_id FROM dataset_rows WHERE logical_id=?", [.string(row.logicalID)]
            ).string
          }
        }
        guard let id = datasetID else {
          throw SevraError("cell", "This row has no table for cell references.")
        }
        return try Numbers.decimal(self.cellValue(id, address: name))
      }
      let decimal = try Numbers.decimal(result)
      cache[column.id] = decimal
      return decimal
    }
    for c in columns where c.formula != nil {
      do { output[c.id] = .string(try Numbers.string(resolve(c))) } catch {
        output[c.id] = .string("#ERROR: " + error.localizedDescription)
      }
    }
    return output
  }
  public func validateColumns(_ columns: [Column]) throws {
    try require(
      !columns.isEmpty && columns.count <= 500 && Set(columns.map(\.id)).count == columns.count,
      "columns", "Use between 1 and 500 unique columns.")
    for c in columns {
      try require(
        !c.id.isEmpty && c.id.utf8.count <= 100 && !c.id.contains("\"")
          && ["text", "decimal", "boolean", "date"].contains(c.type), "columns",
        "Invalid column identifier or type.")
      try require((c.unit?.utf8.count ?? 0) <= 40, "unit", "Unit labels are limited to 40 bytes.")
      try require((c.formula?.utf8.count ?? 0) <= 4096, "formula_limit", "Formula is too long.")
    }
  }
  public func validateValues(_ values: [String: Value], columns: [Column]) throws {
    try require(
      Set(values.keys).isSubset(of: Set(columns.map(\.id))), "column",
      "A row contains an unknown column.")
    for c in columns where c.formula == nil {
      let v = values[c.id] ?? .null
      if v == .null || v.text.isEmpty { continue }
      try require(v.text.utf8.count <= 1_000_000, "cell_limit", "Cell is too large.")
      switch c.type {
      case "decimal": _ = try Numbers.decimal(v.text)
      case "boolean":
        try require(
          ["true", "false"].contains(v.text.lowercased()), "boolean",
          "Use true or false for \(c.title).")
      case "date": _ = try BusinessTime.normalized(v.text)
      default: break
      }
    }
  }
  @discardableResult public func editRows(
    _ datasetID: String, edits: [RowEdit], expectedRevision: Int? = nil,
    token: String = identifier()
  ) throws -> TableEdit {
    try require(
      !edits.isEmpty && edits.count <= 10_000 && Set(edits.map(\.id)).count == edits.count,
      "paste_limit", "An edit needs 1 to 10,000 distinct rows.")
    let request: Value = .object(["dataset": .string(datasetID), "edits": try encoded(edits)])
    let result = try mutation(
      "edit_rows", token: token, request: request, expected: expectedRevision
    ) {
      try applyRows(datasetID, edits: edits, request: request)
    }
    return TableEdit(
      id: result["id"].text, items: try result["items"].array.map { try item($0.text) })
  }
  func applyRows(_ datasetID: String, edits: [RowEdit], request: Value, proposalID: String? = nil)
    throws -> Value
  {
    try require(
      !edits.isEmpty && edits.count <= 10_000 && Set(edits.map(\.id)).count == edits.count,
      "paste_limit", "An edit needs distinct rows within the edit limit.")
    let table = try dataset(datasetID)
    let evidence = try insertItem(
      category: "source", kind: "correction", title: "Edit \(table.title)",
      text: "User updated \(edits.count) table rows.", data: request, meaning: "actual",
      status: "accepted", scenario: "actual", inputs: [], transformation: "human-table-edit-v1")
    var ids: [String] = []
    for edit in edits {
      let old = try item(edit.id)
      try require(
        try db.scalar(
          "SELECT count(*) FROM dataset_rows WHERE dataset_id=? AND logical_id=?",
          [.string(datasetID), .string(old.logicalID)]
        ).int == 1, "row", "Row does not belong to this table.")
      try validateValues(edit.values, columns: table.columns)
      for c in table.columns where c.formula != nil {
        try require(
          edit.values[c.id] == old.data.object[c.id], "calculated_cell",
          "Edit the formula or its inputs, not its calculated value.")
      }
      let new = try insertItem(
        category: "record", kind: old.kind, title: old.title,
        text: edit.values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.text)" }.joined(
          separator: "\n"), data: .object(edit.values), meaning: old.meaning, status: old.status,
        scenario: old.scenario, inputs: [old.id, evidence] + (proposalID.map { [$0] } ?? []),
        transformation: "table-edit-v1",
        supersedes: old.id)
      ids.append(new)
    }
    let change = identifier()
    try db.execute(
      "INSERT INTO table_changes VALUES(?,?,?,?,?)",
      [
        .string(change), .string(datasetID), .string(try encoded(edits.map(\.id)).json()),
        .string(try encoded(ids).json()), .string(timestamp()),
      ])
    return .object(["id": .string(change), "items": .array(ids.map(Value.string))])
  }
  @discardableResult public func editRow(
    _ id: String, values: [String: Value], expectedRevision: Int? = nil,
    token: String = identifier()
  ) throws -> Item {
    let datasetID = try synchronized {
      try db.scalar(
        "SELECT dataset_id FROM dataset_rows WHERE logical_id=?", [.string(try item(id).logicalID)]
      ).text
    }
    try require(!datasetID.isEmpty, "row", "This is not a table row.")
    return try editRows(
      datasetID, edits: [RowEdit(id: id, values: values)], expectedRevision: expectedRevision,
      token: token
    ).items[0]
  }
  @discardableResult public func undoTableChange(_ id: String) throws -> TableEdit {
    let change = try synchronized {
      try db.execute("SELECT * FROM table_changes WHERE id=?", [.string(id)]).first
    }
    guard let change else { throw SevraError("undo", "No such table change.") }
    let before = try Value.parse(change["before_ids"]!.text).array
    let after = try Value.parse(change["after_ids"]!.text).array
    let edits = try zip(before, after).map {
      RowEdit(id: $1.text, values: try item($0.text).data.object)
    }
    return try editRows(change["dataset_id"]!.text, edits: edits)
  }
  @discardableResult public func undoItem(_ id: String) throws -> Item {
    let result = try mutation("undo", request: .string(id)) {
      let current = try item(id)
      guard let prior = current.supersedes else {
        throw SevraError("undo", "No previous version exists.")
      }
      let old = try item(prior)
      var restoredData = old.data
      if current.kind == "table-creation", let datasetID = current.data["datasetID"].string {
        try db.execute(
          "INSERT INTO meta VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
          [
            .string("archived-dataset:" + datasetID),
            .string(current.status == "accepted" ? "1" : "0"),
          ])
        var values = old.data.object
        values["datasetID"] = .string(datasetID)
        restoredData = .object(values)
      }
      if current.kind == "table-change", let change = current.data["tableChangeID"].string {
        guard
          let row = try db.execute("SELECT * FROM table_changes WHERE id=?", [.string(change)])
            .first
        else { throw SevraError("undo", "The accepted table change is missing.") }
        let before = try Value.parse(row["before_ids"]!.text).array
        let after = try Value.parse(row["after_ids"]!.text).array
        let edits = try zip(before, after).map {
          RowEdit(id: $1.text, values: try item($0.text).data.object)
        }
        let inverse = try applyRows(
          row["dataset_id"]!.text, edits: edits, request: .object(["undo": .string(change)]),
          proposalID: current.id)
        var values = old.data.object
        values["tableChangeID"] = inverse["id"]
        restoredData = .object(values)
      }
      let evidence = try insertItem(
        category: "source", kind: "decision", title: "Undo \(current.title)",
        text: "The user requested restoration of the prior version.",
        data: .object(["record": .string(id)]), meaning: "actual", status: "accepted",
        scenario: "actual", inputs: [], transformation: "human-undo-v1")
      let restored = try insertItem(
        category: current.category, kind: current.kind, title: old.title, text: old.text,
        data: restoredData, meaning: old.meaning,
        status: current.status == "accepted" && old.status == "draft" ? "rejected" : old.status,
        scenario: old.scenario, inputs: [current.id, old.id, evidence], transformation: "undo-v1",
        assetID: old.assetID, supersedes: current.id)
      try db.execute(
        "INSERT INTO effects SELECT occurrence,subject,kind,?,quantity,effective FROM effects WHERE item_id=?",
        [.string(restored), .string(old.id)])
      return .string(restored)
    }
    return try item(result.text)
  }
  public func setColumns(_ id: String, columns: [Column]) throws {
    try validateColumns(columns)
    let data = try encoded(columns).json()
    _ = try mutation("columns", request: .object(["id": .string(id), "columns": .string(data)])) {
      let old = try dataset(id)
      try require(
        Set(old.columns.map(\.id)).isSubset(of: Set(columns.map(\.id))), "column_removal",
        "Removing columns would hide retained values. Keep the source columns and change the view instead."
      )
      if old.columns.contains(where: { prior in
        columns.first(where: { $0.id == prior.id })?.type != prior.type
      }) {
        var offset = 0
        while true {
          let batch = try rows(id, offset: offset, limit: 1000)
          if batch.isEmpty { break }
          for row in batch { try validateValues(row.data.object, columns: columns) }
          offset += batch.count
        }
      }
      let version =
        (try db.scalar("SELECT max(version) FROM column_versions WHERE dataset_id=?", [.string(id)])
          .int ?? 0) + 1
      try db.execute(
        "INSERT INTO column_versions VALUES(?,?,?,?)",
        [.string(id), .number(Double(version)), .string(data), .string(timestamp())])
      try db.execute("UPDATE datasets SET columns=? WHERE id=?", [.string(data), .string(id)])
      return .string(id)
    }
  }
  public func exportCSV(_ id: String, to destination: URL) throws {
    let fm = FileManager.default
    try require(
      !fm.fileExists(atPath: destination.path), "exists", "Export destination already exists.")
    let snapshotURL = fm.temporaryDirectory.appendingPathComponent(
      "sevra-csv-snapshot-" + identifier())
    let stage = destination.deletingLastPathComponent().appendingPathComponent(
      ".sevra-csv-" + identifier())
    try fm.createDirectory(at: snapshotURL, withIntermediateDirectories: true)
    defer {
      try? fm.removeItem(at: snapshotURL)
      try? fm.removeItem(at: stage)
    }
    try synchronized {
      try db.backup(to: snapshotURL.appendingPathComponent("workbook.sqlite"))
      try fm.copyItem(
        at: url.appendingPathComponent("manifest.json"),
        to: snapshotURL.appendingPathComponent("manifest.json"))
    }
    let snapshot = try Workbook(snapshotURL)
    let table = try snapshot.dataset(id)
    fm.createFile(atPath: stage.path, contents: nil)
    let file = try FileHandle(forWritingTo: stage)
    defer { try? file.close() }
    try file.write(contentsOf: Data(CSV.encode([table.columns.map(\.title)]).utf8))
    var offset = 0
    while true {
      let batch = try snapshot.rows(id, offset: offset, limit: 1000)
      if batch.isEmpty { break }
      try autoreleasepool {
        let output = batch.map { row in
          let values = snapshot.calculatedValues(row, columns: table.columns)
          return table.columns.map { values[$0.id]?.text ?? "" }
        }
        try file.write(contentsOf: Data(CSV.encode(output).utf8))
      }
      offset += batch.count
    }
    try file.synchronize()
    try file.close()
    try fm.moveItem(at: stage, to: destination)
  }

}

extension Workbook {
  /// A1 denotes the first data cell, excluding display headings. Stable ordinal order
  /// determines addresses; filtering and sorting a view do not move formula references.
  public func cellValue(_ datasetID: String, address: String) throws -> String {
    try synchronized {
      let table = try dataset(datasetID)
      var visiting = Set<String>()
      var cache: [String: Decimal] = [:]
      var reads = 0
      func resolve(_ address: String) throws -> Decimal {
        let (column, row) = try CellReference.parse(address)
        let key = "\(column):\(row)"
        if let cached = cache[key] { return cached }
        try require(
          !visiting.contains(key), "formula_cycle", "Cell dependency cycle at \(address).")
        try require(
          column < table.columns.count && row < table.rowCount, "cell",
          "Cell \(address) is outside this table.")
        reads += 1
        try require(
          reads <= 10_000, "formula_limit", "Calculation exceeds its 10,000-cell read budget.")
        try require(visiting.count < 128, "formula_limit", "Cell dependency depth exceeds 128.")
        visiting.insert(key)
        defer { visiting.remove(key) }
        guard let item = try rows(datasetID, offset: row, limit: 1).first else {
          throw SevraError("cell", "Cell row is missing.")
        }
        let c = table.columns[column]
        let result: Decimal
        if let formula = c.formula {
          let value = try Numbers.calculate(
            formula,
            values: item.data.object.filter { entry in
              !table.columns.contains { $0.id == entry.key && $0.formula != nil }
            }
          ) { name in
            if let index = table.columns.firstIndex(where: { $0.id == name }) {
              return try resolve(Self.spreadsheetColumn(index) + String(row + 1))
            }
            return try resolve(name)
          }
          result = try Numbers.decimal(value)
        } else {
          let value = item.data[c.id]
          try require(
            value != .null && !value.text.isEmpty, "missing_value", "Cell \(address) is unknown.")
          result = try Numbers.decimal(value.text)
        }
        cache[key] = result
        return result
      }
      return try Numbers.string(resolve(address))
    }
  }
}
