import CryptoKit
import Foundation

/// A workbook tool: a saved definition of kind `tool`, whose body is SQL statements or a
/// JavaScript function body, with typed inputs ([[records/plans/general-chat-tools]], phase 5).
///
/// A tool can do nothing that `sql` or `run` cannot: its statements run through `chatSQL` and
/// its script through `chatRun`. It is versioned, searchable and undone like every definition.
/// A tool runs on a Mac only with that Mac's grant. Saving a tool here grants it; a tool that
/// arrived in a copied workbook waits until the person enables it (P5).
struct DefinitionTool {
  static let inputTypes = ["text", "decimal", "boolean", "date"]
  let name: String
  let language: String
  let statements: [String]
  let source: String
  /// A removed tool keeps its versions for history and Undo. It is not listed or run.
  let retired: Bool

  init(_ descriptor: DefinitionDescriptor) throws {
    try require(descriptor.kind == "tool", "definition_kind", "Not a tool definition.")
    let o = try definitionObject(
      descriptor.payload, keys: ["name", "language", "statements", "source", "retired"])
    let name = o["name"]?.string ?? ""
    try require(
      Self.isName(name) && !["tables", "columns"].contains(name), "tool_name",
      "Name the tool in lower case with letters, digits and underscores, such as low_stock.")
    try require(
      descriptor.parameters.count <= 16
        && descriptor.parameters.allSatisfy {
          Self.isName($0.id) && Self.inputTypes.contains($0.type)
        }, "tool_inputs",
      "Give up to 16 inputs with lower-case names, each text, decimal, boolean or date.")
    try require(
      descriptor.description.utf8.count <= 1_000, "tool", "Keep a tool's description short.")
    let language = o["language"]?.string ?? ""
    switch language {
    case "sql":
      guard case .array(let raw) = o["statements"] ?? .null, o["source"] == nil,
        (1...8).contains(raw.count),
        raw.allSatisfy({ ($0.string?.utf8.count ?? 0) > 0 && $0.text.utf8.count <= 8_000 })
      else {
        throw SevraError("tool", "A SQL tool holds one to eight statements under 8,000 bytes.")
      }
      statements = raw.map(\.text)
      source = ""
    case "javascript":
      guard let text = o["source"]?.string, o["statements"] == nil,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 24_000
      else {
        throw SevraError("tool", "A JavaScript tool holds the body of one function under 24,000 bytes.")
      }
      statements = []
      source = text
    default:
      throw SevraError("tool", "A tool's language is sql or javascript.")
    }
    if let retired = o["retired"] {
      try require(retired == .bool(true), "tool", "retired is true when present.")
    }
    self.name = name
    self.language = language
    self.retired = o["retired"] == .bool(true)
  }

  static func isName(_ name: String) -> Bool {
    guard let first = name.unicodeScalars.first, ("a"..."z").contains(first), name.utf8.count <= 48
    else { return false }
    return name.unicodeScalars.allSatisfy {
      ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_"
    }
  }
}

extension Workbook {
  /// A workbook's tools as the chat and the command line see them: the current version of
  /// each tool definition that is not removed.
  public struct SavedTool: Sendable {
    public let definitionID: String
    public let logicalID: String
    public let name: String
    public let description: String
    public let inputs: [(name: String, type: String, required: Bool)]
    public let language: String
    public let statements: [String]
    public let source: String
    /// Whether this Mac has granted this exact version.
    public let enabled: Bool
    var signature: String {
      name + "("
        + inputs.map {
          $0.name + " " + ($0.type == "decimal" ? "REAL" : $0.type == "boolean" ? "BOOLEAN" : "TEXT")
        }.joined(separator: ", ") + ")"
    }
  }

  public func savedTools(includeRetired: Bool = false) throws -> [SavedTool] {
    let rows = try db.execute(
      "SELECT d.* FROM app_definitions d JOIN app_definition_heads h ON h.definition_id=d.id WHERE d.kind='tool' ORDER BY d.title,d.id LIMIT 400",
      maxRows: 400, maxBytes: 16_777_216)
    var tools: [SavedTool] = []
    for row in rows {
      let saved = try ApplicationDefinition(row)
      let descriptor = try DefinitionDescriptor(saved.content)
      let tool = try DefinitionTool(descriptor)
      guard includeRetired || !tool.retired, !tools.contains(where: { $0.name == tool.name })
      else { continue }
      tools.append(
        SavedTool(
          definitionID: saved.id, logicalID: saved.logicalID, name: tool.name,
          description: saved.description,
          inputs: descriptor.parameters.map { ($0.id, $0.type, $0.required) },
          language: tool.language, statements: tool.statements, source: tool.source,
          enabled: isToolEnabled(saved.id)))
      if tools.count == 200 { break }
    }
    return tools
  }

  /// The saved tools as the request's context names them.
  public func chatSavedTools(byteLimit: Int = 1_600) throws -> String {
    var lines: [String] = []
    var bytes = 0
    for tool in try savedTools() {
      let line =
        tool.signature + (tool.language == "javascript" ? " [script]" : "")
        + (tool.enabled ? "" : " [not enabled on this Mac]") + ": "
        + String(tool.description.prefix(120))
      guard bytes + line.utf8.count <= byteLimit else { break }
      bytes += line.utf8.count
      lines.append(line)
    }
    return lines.isEmpty ? "" : "Saved tools: " + lines.joined(separator: "; ")
  }

  // MARK: The per-Mac grant (P5)

  /// One empty file per granted tool version. The name binds the workbook, its file on this
  /// Mac and the exact definition version, as an app's grant does, so a copied or replaced
  /// workbook and a new version start without one. `SEVRA_TOOL_GRANTS` moves it for checks.
  static var toolGrantDirectory: URL {
    if let folder = ProcessInfo.processInfo.environment["SEVRA_TOOL_GRANTS"], !folder.isEmpty {
      return URL(fileURLWithPath: folder)
    }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/Sevra/ToolGrants")
  }
  private func toolGrant(_ definitionID: String) throws -> URL {
    let physical = try NativeAppAccess.physicalIdentity(self)
    let key = SHA256.hash(data: Data((id + "\n" + physical + "\n" + definitionID).utf8))
      .map { String(format: "%02x", $0) }.joined()
    return Self.toolGrantDirectory.appendingPathComponent(key)
  }
  public func isToolEnabled(_ definitionID: String) -> Bool {
    (try? toolGrant(definitionID)).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
  }
  /// The person's enable step for a tool that arrived with the workbook.
  public func enableTool(_ definitionID: String) throws {
    let saved = try applicationDefinition(definitionID)
    try require(
      saved.id == definitionID && saved.kind == "tool"
        && (try applicationDefinition(saved.logicalID).id) == saved.id, "tool",
      "Enable the current version of a saved tool.")
    let grant = try toolGrant(definitionID)
    try FileManager.default.createDirectory(
      at: grant.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    guard FileManager.default.createFile(
      atPath: grant.path, contents: Data(), attributes: [.posixPermissions: 0o600])
    else { throw SevraError("tool", "This Mac's grant for the tool could not be saved.") }
  }
  public func disableTool(_ definitionID: String) throws {
    let grant = try toolGrant(definitionID)
    if FileManager.default.fileExists(atPath: grant.path) {
      try FileManager.default.removeItem(at: grant)
    }
  }

  // MARK: Saving, removing and running

  /// Saves a tool, or a new version of the tool with that name, after rehearsing its
  /// statements with empty inputs or checking its script's syntax. Saving it here grants it.
  public func chatSaveTool(
    name: String, description: String, inputs: [(name: String, type: String)],
    statements: [String], source: String?, token: String, requestSourceID: String?,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    let parameters: [Value] = inputs.map {
      .object([
        "id": .string($0.name), "label": .string($0.name), "type": .string($0.type),
        "required": .bool(true),
      ])
    }
    var payload: [String: Value] = [
      "name": .string(name), "language": .string(source == nil ? "sql" : "javascript"),
    ]
    if let source { payload["source"] = .string(source) } else {
      payload["statements"] = .array(statements.map(Value.string))
    }
    let content: Value = .object([
      "kind": .string("tool"), "title": .string(name), "description": .string(description),
      "parameters": .array(parameters), "payload": .object(payload),
    ])
    let tool = try DefinitionTool(DefinitionDescriptor(content))
    if let source {
      try checkChatScript(source, cancellation: cancellation)
    }
    let saved = try synchronized(cancellation: cancellation) { () throws -> ApplicationDefinition in
      if source == nil {
        let rehearsal = try SQLScratch(
          tables: datasets(), readOnly: false, draft: false,
          inputs: Dictionary(uniqueKeysWithValues: inputs.map { ($0.name, Value.null) }),
          cancellation: cancellation)
        defer { rehearsal.close() }
        // A tool keeps nothing between runs: what it counts or logs lives in a table.
        try require(
          !(try rehearsal.rehearse(tool.statements)).isEmpty, "tool",
          "Tool \(name) reads and changes no table, so running it does nothing. What a tool records, such as a count or a log, goes in a table: make the table with sql, then save a tool that writes to it or reads it."
        )
      }
      let existing = try savedTools(includeRetired: true).first { $0.name == name }
      return try saveApplicationDefinition(
        logicalID: existing?.logicalID ?? Self.toolIdentity(token), content: content,
        expectedDefinitionID: existing?.definitionID,
        inputs: requestSourceID.map { [$0] } ?? [], token: token,
        requestSourceID: requestSourceID, cancellation: cancellation)
    }
    try enableTool(saved.id)
    let signature =
      name + "(" + inputs.map { $0.name + ($0.type == "decimal" ? " number" : "") }
      .joined(separator: ", ") + ")"
    return .object([
      "saved": .string(name), "definitionID": .string(saved.id),
      "version": .number(Double(saved.version)), "language": .string(tool.language),
      "inputs": .array(inputs.map { .string($0.name + " " + $0.type) }),
      "run": .string(
        (source == nil ? "sql" : "run") + " with tool=\(name)" + (inputs.isEmpty ? "" : " and values")),
      "undo": .object(["action": .string("tool.undo"), "id": .string(saved.id)]),
      "notice": .string(
        "Saved as " + signature
          + ", and not run. This tool is complete: its inputs are the fields a form would have, so do not build a form, an app or a definition for it. A view's button can run it."
      ),
    ])
  }

  /// Removes a tool: a new version marked removed, so history keeps it and Undo restores it.
  public func retireTool(_ name: String, token: String = identifier(), requestSourceID: String? = nil)
    throws -> ApplicationDefinition
  {
    try synchronized {
      guard let tool = try savedTools().first(where: { $0.name == name }) else {
        throw SevraError("tool", "No saved tool is named \(name).")
      }
      let current = try applicationDefinition(tool.definitionID)
      var payload = current.payload.object
      payload["retired"] = .bool(true)
      var content = current.content.object
      content["payload"] = .object(payload)
      try disableTool(tool.definitionID)
      return try saveApplicationDefinition(
        logicalID: current.logicalID, content: .object(content),
        expectedDefinitionID: current.id, token: token, requestSourceID: requestSourceID)
    }
  }

  /// Undo of one tool save: the earlier version comes back, or a new tool is removed. Refused
  /// once a later save has built on it.
  public func undoToolSave(_ definitionID: String) throws -> Value {
    try synchronized {
      let saved = try applicationDefinition(definitionID)
      try require(
        saved.id == definitionID && saved.kind == "tool", "tool", "Undo a saved tool's version.")
      try require(
        try applicationDefinition(saved.logicalID).id == saved.id, "stale_tool",
        "A later save changed this tool. Undo that one first.")
      let name = try DefinitionTool(DefinitionDescriptor(saved.content)).name
      try disableTool(saved.id)
      guard let previous = saved.previousID else {
        _ = try retireTool(name)
        return .object(["undone": .string(name), "removed": .bool(true)])
      }
      let restored = try restoreApplicationDefinition(
        saved.logicalID, versionID: previous, expectedDefinitionID: saved.id)
      if try !DefinitionTool(DefinitionDescriptor(restored.content)).retired {
        try enableTool(restored.id)
      }
      return .object([
        "undone": .string(name), "restoredVersion": .number(Double(restored.version)),
      ])
    }
  }

  static func toolIdentity(_ token: String) -> String {
    var bytes = Array(SHA256.hash(data: Data(("tool:" + token).utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8],
        bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
      )
    ).uuidString.lowercased()
  }

  /// The values a tool's inputs take, checked against their types.
  func toolInputs(_ tool: SavedTool, _ values: [String: Value]) throws -> [String: Value] {
    try toolValues(tool, values, complete: true)
  }

  /// Checks the values given for some or all of a tool's inputs. A view's button fixes some
  /// inputs when it is saved and leaves the rest to the person who presses it.
  func toolValues(_ tool: SavedTool, _ values: [String: Value], complete: Bool) throws
    -> [String: Value]
  {
    let unknown = Set(values.keys).subtracting(tool.inputs.map(\.name)).sorted()
    try require(
      unknown.isEmpty, "tool_inputs",
      "\(tool.signature) has no input named " + unknown.joined(separator: " or ") + ".")
    var bound: [String: Value] = [:]
    for input in tool.inputs where complete || values[input.name] != nil {
      let value = values[input.name] ?? .null
      try require(
        value != .null && !value.text.isEmpty, "tool_inputs",
        "\(tool.signature) needs a value for \(input.name).")
      switch input.type {
      case "decimal":
        // A number input stays a number in comparisons and arithmetic.
        guard let decimal = try? Numbers.decimal(value.text),
          let number = Double(Numbers.string(decimal))
        else { throw SevraError("tool_inputs", "\(input.name) is a number.") }
        bound[input.name] = .number(number)
      case "boolean":
        guard case .bool(let flag) = value else {
          throw SevraError("tool_inputs", "\(input.name) is true or false.")
        }
        bound[input.name] = .bool(flag)
      default:
        bound[input.name] = .string(value.text)
      }
    }
    return bound
  }

  /// Finds a tool to run on this Mac.
  public func runnableTool(_ name: String) throws -> SavedTool {
    let tools = try savedTools()
    guard let tool = tools.first(where: { $0.name == name }) else {
      throw SevraError(
        "tool",
        "Unknown workbook tool: \(name)."
          + (tools.isEmpty
            ? " This workbook has no saved tools."
            : " Saved tools: " + tools.map(\.signature).joined(separator: ", ") + "."))
    }
    try require(
      tool.enabled, "tool_disabled",
      "The tool \(name) came with this workbook and is not enabled on this Mac. The user can enable it under Tools in the workbook's menu. Nothing ran."
    )
    return tool
  }

  /// Runs a saved SQL tool: its statements, with the caller's values bound to its inputs.
  public func chatRunTool(
    name: String, values: [String: Value], readOnly: Bool, token: String,
    requestSourceID: String?, cancellation: Cancellation = .init()
  ) throws -> Value {
    try synchronized(cancellation: cancellation) {
      let tool = try runnableTool(name)
      try require(
        tool.language == "sql", "tool",
        "The tool \(name) is a script. Run it with run and tool=\(name).")
      var result = try chatSQL(
        statements: tool.statements, readOnly: readOnly, token: token,
        requestSourceID: requestSourceID, inputs: toolInputs(tool, values),
        cancellation: cancellation
      ).object
      result["tool"] = .string(tool.signature)
      return .object(result)
    }
  }
}
