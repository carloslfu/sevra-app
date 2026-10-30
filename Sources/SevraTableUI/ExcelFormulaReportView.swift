import SevraCore
import SwiftUI

extension SheetFormulaReport {
  public var summary: String {
    let current =
      recalculating == 1
      ? "1 Excel formula recalculates" : "\(recalculating.formatted()) Excel formulas recalculate"
    if saved == 0 { return current }
    if recalculating == 0 {
      return saved == 1
        ? "1 Excel formula keeps its saved value" : "\(saved.formatted()) Excel formulas keep saved values"
    }
    return current + (saved == 1 ? ", 1 keeps its saved value" : ", \(saved.formatted()) keep saved values")
  }
}

/// Names each cell that did not recalculate and says why, next to the table it affects.
public struct ExcelFormulaReportView: View {
  let report: SheetFormulaReport
  public init(report: SheetFormulaReport) { self.report = report }
  public var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Excel formulas").font(.headline)
      Text(
        "Sevra recalculates simple Excel formulas after edits. It is not Excel, and other formulas keep the value Excel saved."
      )
      .font(.callout).foregroundStyle(.secondary)
      if report.valuesChanged && report.saved > 0 {
        Text("Values changed since import, so these saved values may be out of date.")
          .font(.callout)
      }
      if !report.savedCells.isEmpty {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(report.savedCells, id: \.cell) { cell in
              VStack(alignment: .leading, spacing: 2) {
                Text(cell.formula.isEmpty ? cell.cell : cell.cell + "  =" + cell.formula)
                  .font(.caption.monospaced()).lineLimit(2).textSelection(.enabled)
                Text(cell.reason ?? "").font(.caption).foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
        .frame(maxHeight: 260)
      }
      if report.saved > report.savedCells.count {
        Text("Showing the first \(report.savedCells.count.formatted()) of \(report.saved.formatted()).")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(14).frame(width: 380)
  }
}
