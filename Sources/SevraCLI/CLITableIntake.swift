import Foundation
import SevraCore

extension CLI {
  static func runTableIntakeCommand(
    _ command: String, book: Workbook, args: [String], cancellation: Cancellation
  ) throws -> Value? {
    guard
      [
        "table-update-inspect", "table-update-suggest", "table-update-preview",
        "table-update-propose", "table-update-draft", "table-update-draft-save",
        "table-update-draft-discard",
      ].contains(command)
    else { return nil }
    if command == "table-update-inspect" {
      try require(
        (3...5).contains(args.count), "usage",
        "table-update-inspect WORKBOOK SOURCE_ID [HEADER_RECORD [SHEET]]")
      let header = args.count >= 4 ? (Int(args[3]) ?? 0) : 1
      return try encoded(
        book.inspectTableUpdateSource(
          args[2], headerRow: header, sheet: args.count == 5 ? args[4] : nil,
          cancellation: cancellation))
    }
    if command == "table-update-suggest" {
      try require(
        (4...6).contains(args.count), "usage",
        "table-update-suggest WORKBOOK SOURCE_ID TABLE_ID [HEADER_RECORD [SHEET]]")
      let header = args.count >= 5 ? (Int(args[4]) ?? 0) : 1
      let source = try book.inspectTableUpdateSource(
        args[2], headerRow: header, sheet: args.count == 6 ? args[5] : nil,
        cancellation: cancellation)
      return try encoded(source.suggestion(for: book.dataset(args[3]).columns))
    }
    if command == "table-update-draft" {
      try require(args.count == 3, "usage", "table-update-draft WORKBOOK SOURCE_ID")
      return try book.tableUpdateDraft(args[2]).map { try encoded($0) } ?? .null
    }
    if command == "table-update-draft-save" {
      try require(
        args.count == 3 && args[2].utf8.count <= 256_000, "usage",
        "table-update-draft-save WORKBOOK DRAFT_JSON")
      let draft = try JSONDecoder().decode(TableUpdateDraft.self, from: Data(args[2].utf8))
      try book.saveTableUpdateDraft(draft)
      return try encoded(draft)
    }
    if command == "table-update-draft-discard" {
      try require(args.count == 3, "usage", "table-update-draft-discard WORKBOOK SOURCE_ID")
      try book.discardTableUpdateDraft(args[2])
      return .object(["discarded": .string(args[2])])
    }
    try require(
      args.count == 5 && args[4].utf8.count <= 128_000, "usage",
      "\(command) WORKBOOK SOURCE_ID TABLE_ID OPTIONS_JSON")
    let options = try Value.parse(args[4])
    let allowed: Set<String> = [
      "mode", "mapping", "keys", "headerRow", "sheet", "newRowMeaning", "newRowScenario",
      "expectedRevision", "expectedFingerprint", "token", "intakeID",
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
    if options.object["sheet"] != nil {
      try require(
        options["sheet"].string != nil, "update_options", "Provide a string for sheet.")
    }
    let sheet = options["sheet"].string
    if command == "table-update-preview" {
      try require(
        Set(options.object.keys).isSubset(of: ["mode", "mapping", "keys", "headerRow", "sheet"]),
        "update_options", "A preview accepts mode, mapping, keys, headerRow and sheet only.")
      return try encoded(
        book.previewTableUpdate(
          sourceID: args[2], datasetID: args[3], mode: mode,
          mapping: mapping, keys: keys, headerRow: header, sheet: sheet,
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
        mapping: mapping, keys: keys, headerRow: header, sheet: sheet,
        newRowMeaning: options["newRowMeaning"].text,
        newRowScenario: options["newRowScenario"].text,
        expectedRevision: revision,
        expectedFingerprint: options["expectedFingerprint"].text,
        intakeID: options["intakeID"].string,
        token: options["token"].string ?? identifier(), cancellation: cancellation))
  }
}
