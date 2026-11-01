import Foundation

/// One saved job as an inert file: its definitions and nothing else from the workbook. Importing
/// saves them and runs nothing. A copied automation still needs its own Enable on each Mac.
extension Workbook {
  static let templateFormat = "sevra-template-v1"

  public func exportTemplate(_ id: String, to file: URL) throws {
    var ordered: [ApplicationDefinition] = []
    var seen = Set<String>()
    func visit(_ definition: ApplicationDefinition) throws {
      guard seen.insert(definition.id).inserted else { return }
      let needs = try synchronized {
        try db.execute(
          "SELECT kind,target_logical,target_version FROM app_definition_dependencies WHERE definition_id=? ORDER BY ordinal",
          [.string(definition.id)])
      }
      for need in needs {
        try require(
          need["kind"]!.text == "definition", "template_table",
          "“\(definition.title)” reads a table in this workbook, so it cannot travel as a template."
        )
        try visit(
          applicationDefinition(need["target_version"]?.string ?? need["target_logical"]!.text))
      }
      ordered.append(definition)
    }
    let job = try applicationDefinition(id)
    try visit(job)
    try require(ordered.count <= 32, "template_size", "This job has too many parts for a template.")
    let template: Value = .object([
      "format": .string(Self.templateFormat), "title": .string(job.title),
      "definitions": .array(
        ordered.map {
          .object([
            "id": .string($0.id), "logicalID": .string($0.logicalID), "content": $0.content,
          ])
        }),
    ])
    try Data(template.json().utf8).write(to: file, options: .atomic)
  }

  /// The same file saves once. IDs inside a definition point at their imported copies, and one
  /// that names something from its original workbook is refused by the ordinary save check.
  @discardableResult public func importTemplate(_ file: URL, actor: ChangeActor? = nil) throws
    -> ApplicationDefinition
  {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: 1_048_577) ?? Data()
    try require(data.count <= 1_048_576, "template_file", "This template file is too large.")
    guard let template = try? Value.parse(String(decoding: data, as: UTF8.self)),
      template["format"].text == Self.templateFormat,
      (1...32).contains(template["definitions"].array.count)
    else { throw SevraError("template_file", "This file is not a Sevra job template.") }
    let origin = ChangeFormat.hash(String(decoding: data, as: UTF8.self))
    var moved: [(from: String, to: String)] = []
    var saved: ApplicationDefinition?
    for entry in template["definitions"].array {
      var content = try entry["content"].json()
      for id in moved { content = content.replacingOccurrences(of: id.from, with: id.to) }
      let seed = ChangeFormat.hash(origin + entry["id"].text).filter(\.isHexDigit)
      let hex = Array(seed.suffix(32))
      let logical = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32]
        .map { String(hex[$0]) }.joined(separator: "-")
      let definition: ApplicationDefinition
      if let existing = try? applicationDefinition(logical) {
        definition = existing
      } else {
        var parsed = try Value.parse(content)
        // A copy beside one of the same name says so in the list.
        let namesake = try synchronized {
          try db.execute(
            "SELECT 1 FROM app_definition_heads h JOIN app_definitions d ON d.id=h.definition_id WHERE d.kind=? AND d.title=? LIMIT 1",
            [.string(parsed["kind"].text), .string(parsed["title"].text)])
        }
        if !namesake.isEmpty, case .object(var fields) = parsed {
          fields["title"] = .string(parsed["title"].text + " (imported)")
          parsed = .object(fields)
        }
        definition = try saveApplicationDefinition(
          logicalID: logical, content: parsed,
          token: "template-" + origin.suffix(16) + "-" + entry["id"].text, actor: actor)
      }
      moved += [(entry["id"].text, definition.id), (entry["logicalID"].text, logical)]
      saved = definition
    }
    return saved!
  }
}
