import Foundation

extension Workbook {
  public func proposeTableEdit(_ datasetID: String, edits: [RowEdit], token: String = identifier())
    throws -> Item
  {
    try require(
      !edits.isEmpty && edits.count <= 100 && Set(edits.map(\.id)).count == edits.count,
      "proposal_limit", "Propose between 1 and 100 rows per review.")
    let table = try dataset(datasetID)
    var descriptions: [String] = []
    var full: [RowEdit] = []
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
      var values = old.data.object
      for (key, value) in edit.values {
        guard let column = table.columns.first(where: { $0.id == key }) else {
          throw SevraError("column", "Unknown column.")
        }
        try require(
          column.formula == nil, "calculated_cell",
          "Change the formula inputs instead of a calculated value.")
        descriptions.append(
          old.title + ": " + column.title + ": " + (values[key]?.text ?? "Unknown") + " → "
            + value.text)
        values[key] = value
      }
      try validateValues(values, columns: table.columns)
      full.append(RowEdit(id: old.id, values: values))
    }
    return try addItem(
      category: "record", kind: "table-change", title: "Review changes to " + table.title,
      text: descriptions.joined(separator: "\n"),
      data: .object(["datasetID": .string(datasetID), "edits": try encoded(full)]), meaning: "plan",
      status: "draft", inputs: edits.map(\.id), transformation: "proposed-table-edit-v1",
      token: token)
  }
}
