import CryptoKit
import Foundation

/// Exact results live in the journal. Model messages contain complete JSON values
/// or an explicit, navigable projection; a partial string is never a whole value.
public enum ToolResultProjection {
  public static let byteLimit = 16_000

  static func digest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  static func description(_ value: Value, path: [String]) -> Value {
    let kind: String
    let count: Int
    switch value {
    case .object(let fields):
      kind = "object"
      count = fields.count
    case .array(let values):
      kind = "array"
      count = values.count
    case .string(let text):
      kind = "string"
      count = text.unicodeScalars.count
    default:
      kind = "scalar"
      count = 1
    }
    return .object([
      "omitted": .bool(true), "type": .string(kind),
      "count": .number(Double(count)), "path": .array(path.map(Value.string)),
    ])
  }
  public static func project(_ value: Value, receiptID: String) throws -> Value {
    let json = try value.json()
    if json.utf8.count <= byteLimit { return value }
    do {
      return try page(value, receiptID: receiptID, hash: digest(json), path: [], offset: 0)
    } catch {
      return .object([
        "receiptID": .string(receiptID), "hash": .string(digest(json)),
        "complete": .bool(false),
        "notice": .string(
          "The exact result is saved. Use tool_result with rawJSON true to read it in bounded text segments."
        ),
      ])
    }
  }
  /// Bound an ephemeral presentation using the selected tokenizer. The journal
  /// projection stays reproducible and the full result remains retrievable.
  public static func bounded(
    _ value: Value, receiptID: String, maximumTokens: Int,
    tokens: (String) throws -> Int
  ) throws -> Value {
    if try tokens(value.json()) <= maximumTokens { return value }
    let isPage =
      value["receiptID"].string != nil && value["hash"].string != nil
      && value["path"].array.count <= 32 && value["offset"].int != nil
    let source = isPage && value["complete"] == .bool(true) ? value["value"] : value
    var fields: [String: Value] =
      isPage
      ? value.object
      : [
        "receiptID": .string(receiptID), "path": .array([]), "offset": .number(0),
      ]
    fields["complete"] = .bool(false)
    fields["value"] = nil
    fields["notice"] = .string(
      "The exact result is saved. Omitted values are not evidence of absence. Use tool_result with this receipt ID, path and nextOffset, or rawJSON true. Do not repeat a completed action."
    )
    let path = fields["path"]?.array.compactMap(\.string) ?? []
    let offset = fields["offset"]?.int ?? 0
    func fits(_ fields: [String: Value]) throws -> Bool {
      try tokens(Value.object(fields).json()) <= maximumTokens
    }
    if isPage && value["complete"] == .bool(false), let text = value["textSegment"].string {
      fields["textSegment"] = .string(text)
    } else if case .string(let text) = source {
      fields["type"] = .string("string")
      fields["textSegment"] = .string(text)
      fields["offsetUnit"] = .string("Unicode scalar")
      fields["total"] = .number(Double(offset + text.unicodeScalars.count))
    } else {
      var entries: [Value]
      if isPage && value["complete"] == .bool(false), case .array(let existing) = value["entries"] {
        entries = existing
      } else if case .object(let object) = source {
        fields["type"] = .string("object")
        fields["total"] = .number(Double(object.count))
        entries = object.keys.sorted().map { .object(["key": .string($0), "value": object[$0]!]) }
      } else if case .array(let array) = source {
        fields["type"] = .string("array")
        fields["total"] = .number(Double(array.count))
        entries = array.enumerated().map {
          .object(["index": .number(Double($0.offset)), "value": $0.element])
        }
      } else {
        entries = []
      }
      var kept: [Value] = []
      for entry in entries {
        fields["entries"] = .array(kept + [entry])
        fields["nextOffset"] = .number(Double(offset + kept.count + 1))
        if try fits(fields) {
          kept.append(entry)
          continue
        }
        if !kept.isEmpty { break }
        var omitted = entry.object
        let key = entry["key"].string ?? String(entry["index"].int ?? offset)
        omitted["value"] = description(entry["value"], path: path + [key])
        kept.append(.object(omitted))
        break
      }
      fields["entries"] = .array(kept)
      let next = offset + kept.count
      fields["nextOffset"] = next < (fields["total"]?.int ?? next) ? .number(Double(next)) : .null
    }
    if let text = fields["textSegment"]?.string {
      var scalars = Array(text.unicodeScalars)
      // No chopped JSON: this is an explicitly partial string with exact offsets.
      while !scalars.isEmpty {
        fields["textSegment"] = .string(String(String.UnicodeScalarView(scalars)))
        let next = offset + scalars.count
        fields["nextOffset"] = next < (fields["total"]?.int ?? next) ? .number(Double(next)) : .null
        if try fits(fields) { break }
        scalars = Array(scalars.prefix(scalars.count / 2))
      }
      try require(!scalars.isEmpty, "context_limit", "The result cannot fit a retrieval segment.")
    }
    try require(
      try fits(fields), "context_limit",
      "The saved tool result cannot fit its retrieval reference. Completed work is saved.")
    return .object(fields)
  }
  /// What the model sees of a read. The saved receipt keeps every field. `item.text` opens the
  /// first chunk, and an empty reference page with no coverage note has nothing to navigate.
  public static func presentedRead(_ value: Value) -> Value {
    var fields = value.object
    if var item = fields["item"]?.object, let text = item["text"]?.string, !text.isEmpty,
      value["chunks"].array.first?["body"].string?.hasPrefix(text) == true
    {
      item["text"] = nil
      fields["item"] = .object(item)
    }
    let references = value["references"]
    if references["hits"].array.isEmpty, references["nextCursor"] == .null,
      references["fileCoverage"]["snapshot"] == .null,
      references["fileCoverage"]["latestExtraction"].object.isEmpty, references != .null
    {
      fields["references"] = .object(["hits": .array([])])
    }
    return .object(fields)
  }
  /// Only whole fields/elements actually shown in a generated page count as
  /// observed evidence. Omission descriptors never stand in for source values.
  public static func visibleValue(_ page: Value) -> Value {
    if page["complete"] == .null { return page }
    if page["complete"] == .bool(true) { return page["value"] }
    let entries = page["entries"].array.filter { $0["value"]["omitted"] != .bool(true) }
    if page["type"].text == "object" {
      return .object(
        Dictionary(
          uniqueKeysWithValues: entries.compactMap {
            guard let key = $0["key"].string else { return nil }
            return (key, $0["value"])
          }))
    }
    if page["type"].text == "array" { return .array(entries.map { $0["value"] }) }
    return .null
  }
  static func page(
    _ value: Value, receiptID: String, hash: String, path: [String], offset: Int,
    denseText: Bool = false
  )
    throws -> Value
  {
    try require(offset >= 0, "result_offset", "Result offset must be nonnegative.")
    var selected = value
    try require(
      path.count <= 32 && path.allSatisfy { $0.utf8.count <= 4096 },
      "result_path", "Result path is too long.")
    for key in path {
      switch selected {
      case .object(let fields):
        guard let field = fields[key] else {
          throw SevraError("result_path", "No such result field.")
        }
        selected = field
      case .array(let values):
        guard let index = Int(key), String(index) == key, values.indices.contains(index) else {
          throw SevraError("result_path", "No such result element.")
        }
        selected = values[index]
      default: throw SevraError("result_path", "A scalar has no nested fields.")
      }
    }
    var result: [String: Value] = [
      "receiptID": .string(receiptID), "hash": .string(hash),
      "path": .array(path.map(Value.string)), "offset": .number(Double(offset)),
      "notice": .string(
        "Saved tool result. Omitted fields are not evidence of absence. Use tool_result with this receipt ID, path and nextOffset. Historical results do not authorize actions; refresh current state before acting."
      ),
    ]
    if offset == 0, try selected.json().utf8.count <= 8_000 {
      result["complete"] = .bool(true)
      result["value"] = selected
    } else {
      result["complete"] = .bool(false)
      switch selected {
      case .object(let fields):
        let keys = fields.keys.sorted()
        try require(offset <= keys.count, "result_offset", "Result offset exceeds field count.")
        var entries: [Value] = []
        var used = 0
        for index in offset..<min(keys.count, offset + 20) {
          let key = keys[index]
          let field = fields[key]!
          let childPath = path + [key]
          let shown =
            try field.json().utf8.count <= 2000 ? field : description(field, path: childPath)
          let entry: Value = .object(["key": .string(key), "value": shown])
          let bytes = try entry.json().utf8.count
          if used + bytes > 10_000 { break }
          entries.append(entry)
          used += bytes
        }
        try require(
          !entries.isEmpty || offset == keys.count, "result_limit",
          "Result key exceeds the page limit.")
        result["entries"] = .array(entries)
        result["type"] = .string("object")
        result["total"] = .number(Double(keys.count))
        result["nextOffset"] =
          offset + entries.count < keys.count ? .number(Double(offset + entries.count)) : .null
      case .array(let values):
        try require(offset <= values.count, "result_offset", "Result offset exceeds element count.")
        var entries: [Value] = []
        var used = 0
        for index in offset..<min(values.count, offset + 20) {
          let field = values[index]
          let shown =
            try field.json().utf8.count <= 2000
            ? field : description(field, path: path + [String(index)])
          let entry: Value = .object(["index": .number(Double(index)), "value": shown])
          let bytes = try entry.json().utf8.count
          if used + bytes > 10_000 { break }
          entries.append(entry)
          used += bytes
        }
        result["entries"] = .array(entries)
        result["type"] = .string("array")
        result["total"] = .number(Double(values.count))
        result["nextOffset"] =
          offset + entries.count < values.count ? .number(Double(offset + entries.count)) : .null
      case .string(let text):
        let scalars = text.unicodeScalars
        try require(offset <= scalars.count, "result_offset", "Result offset exceeds text length.")
        // Explicit navigation uses the existing byte budget efficiently. Keep the
        // initial receipt projection stable, because integrity checks reproduce it.
        var count = denseText ? 7900 : 1000
        var part = String(String.UnicodeScalarView(scalars.dropFirst(offset).prefix(count)))
        while try denseText && Value.string(part).json().utf8.count > 8000 {
          count /= 2
          part = String(String.UnicodeScalarView(scalars.dropFirst(offset).prefix(count)))
        }
        let next = offset + part.unicodeScalars.count
        result["type"] = .string("string")
        result["textSegment"] = .string(part)
        result["offsetUnit"] = .string("Unicode scalar")
        result["total"] = .number(Double(scalars.count))
        result["nextOffset"] = next < scalars.count ? .number(Double(next)) : .null
      default: throw SevraError("result_offset", "A scalar result only supports offset zero.")
      }
    }
    let output = Value.object(result)
    try require(
      try output.json().utf8.count <= byteLimit, "result_limit",
      "Result page exceeds its context budget.")
    return output
  }
}

extension Workbook {
  /// Write intent before executing. Reusing a call ID never executes it again,
  /// even if its previous process disappeared between mutation and receipt.
  public func prepareToolCall(
    runID: String, callID: String, tool: String, arguments: Value,
    assistantText: String = ""
  ) throws -> String {
    try require(
      !callID.isEmpty && callID.utf8.count <= 256 && !tool.isEmpty && tool.utf8.count <= 128,
      "tool_call", "Invalid tool call identity.")
    try require(
      arguments.object.count > 0 || arguments == .object([:]), "tool_call",
      "Tool arguments must be an object.")
    let args = try arguments.json()
    let operationToken = try WorkbookTools.operationToken(runID: runID, tool, arguments)
    try require(
      args.utf8.count <= 32_000 && (try Value.string(assistantText).json()).utf8.count <= 32_000
        && operationToken.utf8.count <= 512,
      "tool_call", "Tool call exceeds the saved request budget.")
    let id = identifier()
    _ = try mutation("tool_prepare", request: .string(id)) {
      try require(
        try db.scalar(
          "SELECT count(*) FROM agent_runs a JOIN run_requests r ON r.run_id=a.id WHERE a.id=? AND a.status='running'",
          [.string(runID)]
        ).int == 1,
        "tool_run", "Tool calls require an active run linked to its user request.")
      try require(
        try db.scalar(
          "SELECT count(*) FROM tool_calls WHERE run_id=? AND call_id=?",
          [.string(runID), .string(callID)]
        ).int == 0,
        "tool_duplicate", "This call was already prepared. Inspect its receipt before continuing.")
      try db.execute(
        "INSERT INTO tool_calls(id,run_id,call_id,tool,arguments,operation_token,assistant_text,state,created) VALUES(?,?,?,?,?,?,?,'prepared',?)",
        [
          .string(id), .string(runID), .string(callID), .string(tool), .string(args),
          .string(operationToken), .string(assistantText), .string(timestamp()),
        ])
      return .string(id)
    }
    return id
  }

  /// Completing the journal and appending the conversation receipt are atomic.
  /// Cancellation cannot discard a result that has already been executed.
  public func completeToolCall(_ id: String, result: Value, failed: Bool = false) throws -> Value {
    let json = try result.json()
    let hash = ToolResultProjection.digest(json)
    let projected = try ToolResultProjection.project(result, receiptID: id)
    let request: Value = .object([
      "id": .string(id), "hash": .string(hash), "failed": .bool(failed),
    ])
    _ = try mutation("tool_complete", token: "tool-complete-" + id, request: request) {
      guard
        let call = try db.execute(
          "SELECT t.*,a.conversation_id FROM tool_calls t JOIN agent_runs a ON a.id=t.run_id WHERE t.id=?",
          [.string(id)]
        ).first
      else {
        throw SevraError("tool_call", "No saved call exists.")
      }
      try require(call["state"]?.text == "prepared", "tool_state", "The call already has a result.")
      let messageID = identifier()
      let body = try Value.object([
        "tool": call["tool"]!, "arguments": try Value.parse(call["arguments"]!.text),
        "runID": call["run_id"]!, "callID": call["call_id"]!, "receiptVersion": .number(1),
        "receiptID": .string(id), "resultHash": .string(hash), "result": projected,
        "resultIdentity": .object(
          result.object.filter {
            ["id", "status", "meaning", "kind", "logicalID"].contains($0.key)
              && $0.value.string != nil && $0.value.text.utf8.count <= 4096
          }),
        "assistantText": call["assistant_text"]!,
      ]).json()
      try require(
        body.utf8.count <= 128_000, "message_limit", "Tool receipt exceeds the message budget.")
      try db.execute(
        "INSERT INTO messages VALUES(?,?,'tool',?,'complete',?)",
        [.string(messageID), call["conversation_id"]!, .string(body), .string(timestamp())])
      try db.execute(
        "UPDATE tool_calls SET state=?,result=?,result_hash=?,message_id=? WHERE id=?",
        [
          .string(failed ? "failed" : "completed"), .string(json), .string(hash),
          .string(messageID), .string(id),
        ])
      return .string(messageID)
    }
    return projected
  }

  public func toolCall(_ id: String, conversation: String) throws -> Value {
    try synchronized {
      guard
        let row = try db.execute(
          "SELECT t.id,t.run_id,t.call_id,t.tool,t.arguments,t.operation_token,t.state,t.result_hash,t.message_id,t.created,a.status AS run_status FROM tool_calls t JOIN agent_runs a ON a.id=t.run_id WHERE t.id=? AND a.conversation_id=?",
          [.string(id), .string(conversation)]
        ).first
      else {
        throw SevraError("tool_scope", "No tool receipt exists in this conversation.")
      }
      var value = row
      value["arguments"] = try Value.parse(row["arguments"]!.text)
      try require(
        row["operation_token"]?.text
          == WorkbookTools.operationToken(
            runID: row["run_id"]!.text, row["tool"]!.text, value["arguments"]!),
        "integrity", "Saved operation identity does not match its tool call.")
      // prepare_action commits through its own host preview, under that commit's token.
      var token = row["operation_token"]!
      if row["tool"]?.text == "prepare_action",
        let preview = try db.execute(
          "SELECT id FROM tool_calls WHERE run_id=? AND call_id=?",
          [row["run_id"]!, .string("action-preview-" + id)]
        ).first?["id"]
      {
        token = .string(
          try WorkbookTools.operationToken(
            runID: row["run_id"]!.text, "commit_action_preview",
            .object(["previewReceiptID": preview])))
      }
      // This is the exact committed operation, not an assertion by a summary.
      // Some intake tools perform several resumable operations and have no single token.
      if let operation = try db.execute(
        "SELECT id,kind,result,revision FROM operations WHERE id=?", [token]
      ).first {
        var proof = operation
        proof["result"] = try Value.parse(operation["result"]!.text)
        value["committedOperation"] = .object(proof)
      }
      value["notice"] = .string(
        row["state"]?.text == "prepared"
          ? "The call has no final receipt. It may still be running, interrupted before execution, or interrupted after partial or complete changes. No automatic replay is permitted. A committed operation is proof only of that operation; inspect current state."
          : "Saved result available with tool_result. Refresh current evidence and acceptance before acting."
      )
      return .object(value)
    }
  }
  public func unresolvedToolCalls(conversation: String, limit: Int = 8) throws -> [Value] {
    try synchronized {
      try db.execute(
        "SELECT t.id FROM tool_calls t JOIN agent_runs a ON a.id=t.run_id WHERE a.conversation_id=? AND t.state='prepared' ORDER BY t.rowid DESC LIMIT ?",
        [.string(conversation), .number(Double(min(max(limit, 1), 20)))]
      ).map {
        try toolCall($0["id"]!.text, conversation: conversation)
      }
    }
  }
  public func toolResultPage(
    _ id: String, conversation: String, path: [String] = [],
    offset: Int = 0, rawJSON: Bool = false, cancellation: Cancellation = .init()
  ) throws -> Value {
    try synchronized {
      try cancellation.check()
      let call = try toolCall(id, conversation: conversation)
      if call["state"].text == "prepared" {
        return .object(
          call.object.filter {
            ["id", "run_id", "tool", "state", "run_status", "committedOperation", "notice"]
              .contains($0.key)
          })
      }
      let row = try db.execute(
        "SELECT result,result_hash FROM tool_calls WHERE id=?", [.string(id)]
      ).first!
      let json = row["result"]!.text
      try require(
        ToolResultProjection.digest(json) == row["result_hash"]!.text, "integrity",
        "Saved tool result changed.")
      try cancellation.check()
      return try ToolResultProjection.page(
        rawJSON ? .string(json) : Value.parse(json), receiptID: id,
        hash: row["result_hash"]!.text, path: path, offset: offset, denseText: true)
    }
  }
}

extension Workbook {
  func verifyToolCalls() throws {
    var after = 0
    while let row = try db.execute(
      "SELECT t.rowid,t.*,a.conversation_id,m.conversation_id AS message_conversation,m.body,m.role FROM tool_calls t JOIN agent_runs a ON a.id=t.run_id LEFT JOIN messages m ON m.id=t.message_id WHERE t.rowid>? ORDER BY t.rowid LIMIT 1",
      [.number(Double(after))]
    ).first {
      after = row["rowid"]!.int!
      try require(
        try db.scalar("SELECT count(*) FROM run_requests WHERE run_id=?", [row["run_id"]!]).int
          == 1,
        "integrity", "Tool call has no original user request.")
      _ = try toolCall(row["id"]!.text, conversation: row["conversation_id"]!.text)
      if row["state"]?.text == "prepared" { continue }
      let json = row["result"]!.text
      let receipt = try Value.parse(row["body"]!.text)
      try require(
        row["conversation_id"] == row["message_conversation"] && row["role"]?.text == "tool"
          && ToolResultProjection.digest(json) == row["result_hash"]!.text
          && receipt["receiptID"] == row["id"] && receipt["runID"] == row["run_id"]
          && receipt["callID"] == row["call_id"] && receipt["tool"] == row["tool"]
          && receipt["resultHash"] == row["result_hash"]
          && receipt["assistantText"] == row["assistant_text"]
          && receipt["arguments"] == Value.parse(row["arguments"]!.text)
          && receipt["result"]
            == ToolResultProjection.project(Value.parse(json), receiptID: row["id"]!.text),
        "integrity", "Tool receipt does not match its saved call and result.")
    }
  }
}
