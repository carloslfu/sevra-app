import Foundation
import SevraCore

extension CLI {
  static func referenceOptions(_ text: String, allowed: Set<String>) throws -> Value {
    try require(text.utf8.count <= 400_000, "usage", "Reference JSON is limited to 400,000 bytes.")
    let value = try Value.parseExact(text)
    guard case .object(let fields) = value, Set(fields.keys).isSubset(of: allowed) else {
      throw SevraError("usage", "Use a JSON object with documented reference options.")
    }
    return value
  }

  static func decodeReferenceSelections(_ value: Value) throws -> [ReferenceSelection] {
    guard case .array(let values) = value, values.count <= 128 else {
      throw SevraError("usage", "Use an array of at most 128 reference selections.")
    }
    for row in values {
      guard case .object(let fields) = row,
        Set(fields.keys).isSubset(of: ["id", "startScalar", "scalarCount", "lookup", "target"])
      else { throw SevraError("usage", "Unknown reference selection field.") }
      if row["target"] != .null {
        guard case .object(let fields) = row["target"],
          Set(fields.keys).isSubset(of: ["workbookID", "mode", "identity"])
        else { throw SevraError("usage", "Unknown reference target field.") }
      }
    }
    do {
      return try JSONDecoder().decode([ReferenceSelection].self, from: Data(value.json().utf8))
    } catch { throw SevraError("usage", "Invalid reference selection or target type.") }
  }

  static func decodeExtractedReferenceSelections(_ value: Value) throws
    -> [ExtractedReferenceSelection]
  {
    guard case .array(let values) = value, values.count <= 128 else {
      throw SevraError("usage", "Use an array of at most 128 extracted reference selections.")
    }
    return try values.map { row in
      guard case .object(let fields) = row, Set(fields.keys) == ["region", "selection"],
        let region = row["region"].int, row["region"] == .number(Double(region)),
        region >= 0, region < 512
      else { throw SevraError("usage", "Use an integer region and one reference selection.") }
      let selection = try decodeReferenceSelections(.array([row["selection"]]))[0]
      return ExtractedReferenceSelection(region: region, selection: selection)
    }
  }

  static func runReferenceCommand(
    _ command: String, book: Workbook, args: [String], cancellation: Cancellation
  ) throws -> Value? {
    let commands: Set<String> = [
      "references", "backlinks", "reference-snapshot", "reference-resolve", "reference-history",
      "index-references", "index-reference-bodies", "rebuild-references", "annotate-references",
      "file-reference-snapshot", "file-reference-history", "file-reference-region",
      "file-reference-resolve", "annotate-file-references",
    ]
    guard commands.contains(command) else { return nil }
    func count(_ range: ClosedRange<Int>) throws {
      try require(
        range.contains(args.count), "usage",
        "Wrong number of reference command arguments. See help.")
    }
    func string(_ options: Value, _ key: String) throws -> String? {
      if options[key] == .null { return nil }
      guard let value = options[key].string else {
        throw SevraError("usage", key + " must be a string.")
      }
      return value
    }
    func integer(_ options: Value, _ key: String, fallback: Int) throws -> Int {
      if options[key] == .null { return fallback }
      guard let value = options[key].int, options[key] == .number(Double(value)) else {
        throw SevraError("usage", key + " must be an integer.")
      }
      return value
    }
    switch command {
    case "references", "backlinks":
      try count(3...4)
      let options = try referenceOptions(
        args.count == 4 ? args[3] : "{}",
        allowed: [
          "targetScope", "historicalOrigins", "kind", "meaning", "status", "scenario", "limit",
          "cursor", "contentScope",
        ])
      guard
        let scope = ReferenceTargetScope(rawValue: try string(options, "targetScope") ?? "logical")
      else { throw SevraError("usage", "targetScope must be logical or exact.") }
      guard
        let contentScope = ReferenceContentScope(
          rawValue: try string(options, "contentScope") ?? "all")
      else { throw SevraError("usage", "contentScope must be all, body or extracted.") }
      var historical = false
      if options["historicalOrigins"] != .null {
        guard case .bool(let value) = options["historicalOrigins"] else {
          throw SevraError("usage", "historicalOrigins must be boolean.")
        }
        historical = value
      }
      return try book.referenceLinks(
        args[2], direction: command == "backlinks" ? .incoming : .outgoing, targetScope: scope,
        historicalOrigins: historical, contentScope: contentScope, kind: string(options, "kind"),
        meaning: string(options, "meaning"), status: string(options, "status"),
        scenario: string(options, "scenario"), limit: integer(options, "limit", fallback: 20),
        cursor: string(options, "cursor"), cancellation: cancellation)
    case "reference-snapshot":
      try count(3...4)
      return try encoded(
        book.referenceSnapshot(
          args[2], snapshotID: args.count == 4 ? args[3] : nil, cancellation: cancellation))
    case "reference-resolve":
      try count(4...5)
      return try book.resolveReference(
        args[3], originVersionID: args[2], snapshotID: args.count == 5 ? args[4] : nil,
        cancellation: cancellation)
    case "reference-history":
      try count(3...4)
      let options = try referenceOptions(
        args.count == 4 ? args[3] : "{}", allowed: ["beforeVersion", "limit"])
      let before =
        try options["beforeVersion"] == .null ? nil : integer(options, "beforeVersion", fallback: 1)
      return try book.referenceHistory(
        args[2], beforeVersion: before, limit: integer(options, "limit", fallback: 30),
        cancellation: cancellation)
    case "file-reference-snapshot":
      try count(3...4)
      return try book.fileReferenceSnapshot(
        args[2], snapshotID: args.count == 4 ? args[3] : nil, cancellation: cancellation)
    case "file-reference-resolve":
      try count(4...5)
      return try book.resolveFileReference(
        args[3], originVersionID: args[2], snapshotID: args.count == 5 ? args[4] : nil,
        cancellation: cancellation)
    case "file-reference-history":
      try count(3...4)
      let options = try referenceOptions(
        args.count == 4 ? args[3] : "{}", allowed: ["beforeVersion", "limit"])
      let before =
        try options["beforeVersion"] == .null ? nil : integer(options, "beforeVersion", fallback: 1)
      return try book.fileReferenceHistory(
        args[2], beforeVersion: before, limit: integer(options, "limit", fallback: 20),
        cancellation: cancellation)
    case "file-reference-region":
      try count(4...4)
      let options = try referenceOptions(
        args[3], allowed: ["snapshotID", "region", "offset", "limit"])
      guard let snapshot = try string(options, "snapshotID"), options["region"] != .null else {
        throw SevraError("usage", "Supply snapshotID and an integer region.")
      }
      return try book.fileReferenceRegion(
        args[2], snapshotID: snapshot, region: integer(options, "region", fallback: -1),
        offset: integer(options, "offset", fallback: 0),
        limit: integer(options, "limit", fallback: 4000), cancellation: cancellation)
    case "annotate-file-references":
      try count(4...4)
      let options = try referenceOptions(
        args[3], allowed: ["selections", "expectedSnapshotID", "token"])
      guard let snapshot = try string(options, "expectedSnapshotID") else {
        throw SevraError("usage", "Supply the current extracted expectedSnapshotID.")
      }
      let token = try string(options, "token") ?? identifier()
      try require(!token.isEmpty && token.utf8.count <= 1024, "usage", "Invalid operation token.")
      return try book.annotateFileReferences(
        args[2], selections: decodeExtractedReferenceSelections(options["selections"]),
        expectedSnapshotID: snapshot, token: token, cancellation: cancellation)
    case "index-references":
      try count(3...3)
      return try encoded(book.indexReferences(args[2], cancellation: cancellation))
    case "index-reference-bodies":
      try count(2...3)
      let options = try referenceOptions(
        args.count == 3 ? args[2] : "{}", allowed: ["afterID", "limit"])
      return try book.indexReferenceBodies(
        afterID: string(options, "afterID"), limit: integer(options, "limit", fallback: 20),
        cancellation: cancellation)
    case "rebuild-references":
      try count(2...2)
      try book.rebuildReferenceIndex(cancellation: cancellation)
      return .bool(true)
    default:
      try count(4...4)
      let options = try referenceOptions(
        args[3], allowed: ["selections", "expectedSnapshotID", "token"])
      try require(
        options.object.keys.contains("expectedSnapshotID"), "usage",
        "Supply expectedSnapshotID, including null for a first annotation.")
      let token = try string(options, "token") ?? identifier()
      try require(!token.isEmpty && token.utf8.count <= 1024, "usage", "Invalid operation token.")
      return try encoded(
        book.annotateReferences(
          args[2], selections: decodeReferenceSelections(options["selections"]),
          expectedSnapshotID: string(options, "expectedSnapshotID"), token: token,
          cancellation: cancellation))
    }
  }
}
