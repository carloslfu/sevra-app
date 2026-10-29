import Foundation
import SevraCore

extension CLI {
  static func runTableIntakeCommand(
    _ command: String, book: Workbook, args: [String], cancellation: Cancellation
  ) throws -> Value? {
    guard
      ["table-update-inspect", "table-update-preview", "table-update-propose"].contains(command)
    else { return nil }
    if command == "table-update-inspect" {
      try require(
        (3...4).contains(args.count), "usage",
        "table-update-inspect WORKBOOK SOURCE_ID [HEADER_RECORD]")
      let header = args.count == 4 ? (Int(args[3]) ?? 0) : 1
      return try encoded(
        book.inspectTableUpdateSource(args[2], headerRow: header, cancellation: cancellation))
    }
    try require(
      args.count == 5 && args[4].utf8.count <= 128_000, "usage",
      "\(command) WORKBOOK SOURCE_ID TABLE_ID OPTIONS_JSON")
    let options = try Value.parse(args[4])
    let allowed: Set<String> = [
      "mode", "mapping", "keys", "headerRow", "newRowMeaning", "newRowScenario", "expectedRevision",
      "expectedFingerprint", "token", "intakeID",
    ]
    try require(
      Set(options.object.keys).isSubset(of: allowed), "update_options",
      "Unknown table-update option.")
    guard let mode = TableUpdateMode(rawValue: options["mode"].text) else {
      throw SevraError("update_mode", "Choose append, replace or merge explicitly.")
    }
    let mapping = try JSONDecoder().decode(
      [IntakeColumnMapping].self, from: Data(options["mapping"].json().utf8))
    let keys: [String]
    if options["keys"] == .null {
      keys = []
    } else {
      keys = try JSONDecoder().decode([String].self, from: Data(options["keys"].json().utf8))
    }
    let header: Int
    if options["headerRow"] == .null {
      header = 1
    } else {
      header = try JSONDecoder().decode(Int.self, from: Data(options["headerRow"].json().utf8))
    }
    if command == "table-update-preview" {
      try require(
        Set(options.object.keys).isSubset(of: ["mode", "mapping", "keys", "headerRow"]),
        "update_options", "A preview accepts mode, mapping, keys and headerRow only.")
      return try encoded(
        book.previewTableUpdate(
          sourceID: args[2], datasetID: args[3], mode: mode,
          mapping: mapping, keys: keys, headerRow: header,
          cancellation: cancellation))
    }
    let revision = try JSONDecoder().decode(
      Int.self, from: Data(options["expectedRevision"].json().utf8))
    for key in ["newRowMeaning", "newRowScenario", "expectedFingerprint"] {
      try require(options[key].string != nil, "update_options", "Provide a string for " + key + ".")
    }
    for key in ["token", "intakeID"] where options.object[key] != nil {
      try require(options[key].string != nil, "update_options", "Provide a string for " + key + ".")
    }
    return try encoded(
      book.proposeTableUpdate(
        sourceID: args[2], datasetID: args[3], mode: mode,
        mapping: mapping, keys: keys, headerRow: header,
        newRowMeaning: options["newRowMeaning"].text,
        newRowScenario: options["newRowScenario"].text,
        expectedRevision: revision,
        expectedFingerprint: options["expectedFingerprint"].text,
        intakeID: options["intakeID"].string,
        token: options["token"].string ?? identifier(), cancellation: cancellation))
  }
}
