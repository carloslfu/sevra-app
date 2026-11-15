import Foundation

extension Workbook {
  /// Exact immutable original cells for host checks. The model's bounded excerpt
  /// is presentation context, never an exhaustive source-of-truth dictionary.
  package func excelOriginalInputLookup(
    _ conversionID: String, cancellation: Cancellation = .init()
  ) throws -> (String) throws -> Value {
    let conversion = try excelConversion(conversionID)
    return Self.excelInputLookup(
      try excelOriginalSheets(conversion.sourceID, cancellation: cancellation))
  }

  package static func excelInputLookup(_ originals: [ImportedSheet]) -> (String) throws -> Value {
    let sheets = originals.filter { !$0.rows.isEmpty }
    return { key in
      let address = try ExcelBehavior.address(key)
      guard sheets.indices.contains(address.sheet) else { return .null }
      let sheet = sheets[address.sheet]
      let cell = XLSX.cellName(column: address.column, row: address.row)
      guard sheet.formulas[cell] == nil, sheet.formulaKinds[cell] == nil,
        sheet.formulaKinds["*"] == nil,
        let position = sheet.rowNumbers.firstIndex(of: address.row),
        sheet.rows.indices.contains(position),
        sheet.rows[position].indices.contains(address.column)
      else { return .null }
      let value = sheet.rows[position][address.column]
      try require(
        value.utf8.count <= 4096, "app_review_inputs", "The original lookup header exceeds 4 KiB.")
      return .string(value)
    }
  }
}
