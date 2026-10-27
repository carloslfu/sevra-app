import Foundation

public enum StructuredFormat: String, Sendable { case csv, tsv, xlsx }

/// Parser output only. Dataset creation, lineage and resumable commits stay in the host.
public struct StructuredResult: Codable, Sendable {
  public let sheets: [ImportedSheet]

  static func readInProcess(
    _ url: URL, format: StructuredFormat, cancellation: Cancellation
  ) throws -> StructuredResult {
    if format == .xlsx {
      return .init(sheets: try XLSX.readInProcess(url, cancellation: cancellation))
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    try cancellation.check()
    // Read one extra byte so a changed file cannot evade a metadata-only limit.
    let bytes = try handle.read(upToCount: 32_000_001) ?? Data()
    try require(
      bytes.count <= 32_000_000, "csv_limit", "Structured CSV import is limited to 32 MB per file.")
    guard let text = String(data: bytes, encoding: .utf8) else {
      throw SevraError("encoding", "CSV and TSV imports require UTF-8 text.")
    }
    let rows = try CSV.parse(
      text, delimiter: format == .tsv ? "\t" : ",", cancellation: cancellation)
    return .init(sheets: [
      .init(
        name: "", rows: rows,
        rowNumbers: Array(1..<(rows.count + 1)), notes: [], formulas: [:])
    ])
  }

  func validate() throws {
    try require(
      !sheets.isEmpty && sheets.count <= 100, "structured_output", "Invalid worksheet count.")
    var cells = 0
    var bytes = 0
    for sheet in sheets {
      try require(
        sheet.rows.count <= 100_000 && sheet.rowNumbers.count == sheet.rows.count
          && sheet.name.utf8.count <= 4096 && sheet.notes.count <= 100
          && sheet.formulas.count <= 1_000_000,
        "structured_output", "Worksheet exceeds the import limits.")
      let width = sheet.rows.map(\.count).max() ?? 0
      try require(width <= 500, "structured_output", "Worksheet exceeds 500 columns.")
      // The host fills missing columns. Bound that dense expansion, not just stored cells.
      cells += width * sheet.rows.count
      try require(
        cells <= 1_000_000, "structured_output",
        "Worksheet import exceeds one million cells including blank positions.")
      try require(
        sheet.rowNumbers.allSatisfy { (1...1_048_576).contains($0) },
        "structured_output", "Invalid worksheet row reference.")
      for row in sheet.rows {
        for value in row { bytes += value.utf8.count }
      }
      for (reference, formula) in sheet.formulas {
        try require(reference.utf8.count <= 128, "structured_output", "Invalid formula reference.")
        bytes += formula.utf8.count
      }
      for note in sheet.notes { bytes += note.utf8.count }
      bytes += sheet.name.utf8.count
      try require(
        bytes <= 32_000_000, "structured_output",
        "Expanded cell text exceeds the 32 MB import limit.")
    }
  }
}
