import Foundation

extension Workbook {
  public func proposeTableEdit(_ datasetID: String, edits: [RowEdit], token: String = identifier())
    throws -> Item
  {
    try require(
      !edits.isEmpty && edits.count <= 100 && Set(edits.map(\.id)).count == edits.count,
      "proposal_limit", "Propose between 1 and 100 rows per review.")
    let table = try dataset(datasetID)
    try require(
      !table.archived, "archived_dataset", "Restore this table before proposing row edits.")
    var descriptions: [String] = []
    var full: [RowEdit] = []
    let recalculating = try recalculatingColumns(datasetID)
    for edit in edits {
      try require(
        !edit.values.isEmpty, "empty_edit", "Each proposed row needs at least one changed field.")
      let old = try item(edit.id)
      let belongs = try synchronized {
        try db.scalar(
          "SELECT count(*) FROM dataset_rows WHERE dataset_id=? AND logical_id=?",
          [.string(datasetID), .string(old.logicalID)]
        ).int == 1
      }
      try require(belongs, "row", "The row does not belong to the selected table.")
      var values = Self.activeValues(old.data.object, columns: table.columns)
      for (key, value) in edit.values {
        guard let column = table.columns.first(where: { $0.id == key }) else {
          throw SevraError("column", "Unknown column.")
        }
        try require(
          column.formula == nil, "calculated_cell",
          "Change the formula inputs instead of a calculated value.")
        try require(
          recalculating[old.logicalID]?.contains(key) != true, "calculated_cell",
          "This cell comes from an Excel formula. Edit the cells it reads instead.")
        descriptions.append(
          old.title + ": " + column.title + ": " + (values[key]?.text ?? "Unknown") + " → "
            + value.text)
        values[key] = value
      }
      try validateValues(values, columns: table.columns)
      full.append(RowEdit(id: old.id, values: values))
    }
    return try addHostOwnedItem(
      category: "record", kind: "table-change", title: "Review changes to " + table.title,
      text: descriptions.joined(separator: "\n"),
      data: .object(["datasetID": .string(datasetID), "edits": try encoded(full)]), meaning: "plan",
      status: "draft", inputs: edits.map(\.id), transformation: "proposed-table-edit-v1",
      token: token)
  }
}

extension Workbook {
  public func proposeTable(
    title: String, columns: [Column], rows: [[String: Value]], meaning: String = "plan",
    inputs: [String], token: String = identifier()
  ) throws -> Item {
    try require(
      !title.isEmpty && columns.count <= 40 && rows.count <= 100, "table_proposal_limit",
      "Propose at most 40 columns and 100 rows per review.")
    try validateColumns(columns)
    for row in rows { try validateValues(row, columns: columns) }
    let preview =
      columns.map(\.title).joined(separator: " · ") + "\n\n"
      + rows.map { row in columns.map { row[$0.id]?.text ?? "Unknown" }.joined(separator: " · ") }
      .joined(separator: "\n")
    return try addHostOwnedItem(
      category: "record", kind: "table-creation", title: "Review table: " + title, text: preview,
      data: .object([
        "title": .string(title), "columns": try encoded(columns),
        "rows": .array(rows.map(Value.object)),
      ]), meaning: meaning, status: "draft", inputs: inputs, transformation: "proposed-table-v1",
      token: token)
  }
}
