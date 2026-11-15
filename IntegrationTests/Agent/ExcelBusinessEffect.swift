import Foundation
import SevraAppProtocol

@testable import SevraCore

/// The expected input record comes from the independent scenario, never the app.
/// Formula outputs are checked separately against the recalculated original.
func checkBusinessSavedEffect(
  before: Value, after: Value, expected: Value, original: [ImportedSheet]
) throws {
  guard Set(expected.object.keys) == ["sheet", "match", "values"],
    let target = expected["sheet"].int, expected["sheet"] == .number(Double(target)),
    before.array.count == original.count, after.array.count == original.count,
    after.array.indices.contains(target), !expected["match"].object.isEmpty,
    !expected["values"].object.isEmpty
  else { throw SevraError("journey", "Missing or invalid independent saved-effect expectation.") }
  func matches(_ row: Value) -> Bool {
    expected["match"].object.allSatisfy { row[$0.key] == $0.value }
  }
  let rows = after.array[target].array.filter(matches)
  try require(rows.count == 1, "journey", "Expected exactly one saved business record.")
  for (column, value) in expected["values"].object {
    let actual = rows[0][column]
    let sameDecimal: Bool
    if let a = actual.string.flatMap(NativeAppCheck.decimalSpelling),
      let b = value.string.flatMap(NativeAppCheck.decimalSpelling)
    {
      sameDecimal = a == b
    } else { sameDecimal = false }
    try require(
      actual == value || sameDecimal, "journey",
      "Wrong saved " + column + ": expected " + value.text + ", observed " + actual.text)
  }
  try require(after != before, "journey", "No saved change after the requested operation.")
  for sheet in before.array.indices {
    let priorRows = before.array[sheet].array
    let nextRows = after.array[sheet].array
    try require(
      nextRows.count == priorRows.count
        || (sheet == target && nextRows.count == priorRows.count + 1),
      "journey", "Unexpected row insertion, removal or replacement.")
    for position in priorRows.indices {
      let isTarget = sheet == target && matches(nextRows[position])
      for (column, old) in priorRows[position].object {
        guard let number = Int(column.dropFirst()), number > 0, column == "c\(number)" else {
          throw SevraError("journey", "Unexpected worksheet column in the saved-effect check.")
        }
        let address = XLSX.cellName(
          column: number - 1,
          row: position < original[sheet].rowNumbers.count
            ? original[sheet].rowNumbers[position] : position + 1)
        if original[sheet].formulas[address] != nil { continue }
        let allowed = isTarget && expected["values"].object[column] != nil
        try require(
          allowed || nextRows[position][column] == old, "journey",
          "Unrelated input changed: " + original[sheet].name + "!" + address)
      }
    }
  }
}
