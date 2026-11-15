import Foundation

extension Workbook {
  /// A ledger can grow without moving any original Excel coordinate. Formula-bearing
  /// sheets require an explicit formula-extension contract; never invent one from the
  /// last row, which might be a total, exception, or different business calculation.
  func extendSheetInputRows(after datasetID: String) throws {
    guard let (id, original) = try sheetFormulaPlan(datasetID) else { return }
    var plan = original
    var added: [String] = []
    for index in plan.sheets.indices {
      let sheet = plan.sheets[index]
      // Oversized imports deliberately retain no coordinate map and no live
      // calculations. Their saved-value tables remain editable as before.
      guard !sheet.logical.isEmpty else { continue }
      let members = try db.execute(
        "SELECT logical_id FROM dataset_rows WHERE dataset_id=? ORDER BY ordinal,row_id",
        [.string(sheet.dataset)]
      ).map { $0["logical_id"]!.text }
      let known = Set(sheet.logical)
      let fresh = members.filter { !known.contains($0) }
      guard !fresh.isEmpty else { continue }
      try require(
        !plan.cells.contains { $0.sheet == index }
          && (index >= plan.unlisted.count || plan.unlisted[index] == 0),
        "excel_row_growth",
        "This worksheet contains formulas. Add records to its input ledger; formula rows need an explicit extension before they can grow."
      )
      let last = sheet.rows.max() ?? 0
      try require(
        last + fresh.count <= 1_048_576
          && plan.sheets.reduce(0, { $0 + $1.logical.count }) + fresh.count
            <= SheetFormulaPlan.rowLimit,
        "excel_row_growth", "This worksheet has reached its calculation row limit.")
      plan.sheets[index].rows += Array((last + 1)...(last + fresh.count))
      plan.sheets[index].logical += fresh
      plan.sheets[index].appended = (sheet.appended ?? []) + fresh
      added += fresh
    }
    guard !added.isEmpty else { return }
    let previous = try item(id)
    _ = try insertItem(
      category: previous.category, kind: previous.kind, title: previous.title,
      text: previous.text,
      data: .object([
        "plan": .string(String(decoding: try JSONEncoder().encode(plan), as: UTF8.self))
      ]),
      meaning: previous.meaning, status: previous.status, scenario: previous.scenario,
      inputs: [previous.id] + (try added.map { try item($0).id }),
      transformation: "xlsx-input-rows-v1", supersedes: previous.id)
  }
}
