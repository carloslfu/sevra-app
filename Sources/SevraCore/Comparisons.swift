import Foundation

extension Workbook {
  public func compareRows(_ datasetID: String, labelColumn: String, valueColumn: String) throws
    -> Value
  {
    let table = try dataset(datasetID)
    try require(
      table.rowCount > 0 && table.rowCount <= 1000, "comparison_limit",
      "Compare a table with 1 to 1,000 rows. Filter or derive a smaller table first.")
    try require(
      table.columns.contains { $0.id == labelColumn }
        && table.columns.contains { $0.id == valueColumn }, "column",
      "Comparison columns do not exist.")
    let values = try rows(datasetID, limit: 1000).map { row -> (Item, Decimal, String) in
      let cells = calculatedValues(row, columns: table.columns)
      return (
        row, try Numbers.decimal(cells[valueColumn]?.text ?? ""), cells[labelColumn]?.text ?? ""
      )
    }.sorted { $0.1 < $1.1 }
    guard let low = values.first, let high = values.last else {
      throw SevraError("comparison_empty", "This table has no comparable rows.")
    }
    let difference = try Numbers.binary(high.1, low.1, op: "-")
    let percent =
      high.1 > 0
      ? try Numbers.calculate(
        "(high-low)/high*100",
        values: ["high": .string(Numbers.string(high.1)), "low": .string(Numbers.string(low.1))])
      : nil
    func point(_ p: (Item, Decimal, String)) -> Value {
      .object(["id": .string(p.0.id), "label": .string(p.2), "value": .string(Numbers.string(p.1))])
    }
    return .object([
      "datasetID": .string(datasetID), "minimum": point(low), "maximum": point(high),
      "difference": .string(Numbers.string(difference)),
      "percentCheaper": percent.map(Value.string) ?? .null,
      "percentageDenominator": .string(Numbers.string(high.1)),
      "explanation": .string(
        "Percentage cheaper is (maximum - minimum) / maximum * 100. Values have no inferred currency or unit."
      ), "inputs": .array(values.map { .string($0.0.id) }),
    ])
  }
}
