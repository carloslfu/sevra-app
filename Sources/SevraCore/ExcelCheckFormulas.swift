/// Formula definitions only. This template does not copy original row values,
/// identities or permissions into the disposable authoring checker. Fixture
/// values are supplied separately by the author and remain untrusted test data.
public struct ExcelCheckFormulas: Sendable {
  package let sheets: [String]
  package let cells: [[SheetFormulaCell]]
}

extension Workbook {
  package func excelCheckFormulas(_ conversionID: String) throws -> ExcelCheckFormulas? {
    let conversion = try excelConversion(conversionID)
    guard let table = conversion.datasetIDs.first,
      let (_, plan) = try sheetFormulaPlan(table), !plan.cells.isEmpty
    else { return nil }
    return ExcelCheckFormulas(
      sheets: plan.sheets.map(\.name),
      cells: plan.sheets.indices.map { index in
        plan.cells.filter { $0.sheet == index }.map {
          .init(cell: $0.cell, formula: $0.formula, reason: $0.reason)
        }
      })
  }
}
