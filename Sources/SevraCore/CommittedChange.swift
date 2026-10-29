import CryptoKit
import Foundation

/// Attribution states what the calling software actually knows. No account or
/// inferred human identity is created. AI decisions require an explicit policy.
public struct ChangeActor: Codable, Equatable, Sendable {
  public let kind: String
  public let component: String
  public let model: String?
  public let policy: String?
  public static func programmatic(_ component: String) -> Self {
    .init(kind: "programmatic", component: component, model: nil, policy: nil)
  }
  public static func human(_ component: String) -> Self {
    .init(kind: "human", component: component, model: nil, policy: nil)
  }
  public static func ai(_ component: String, model: String, policy: String) -> Self {
    .init(kind: "ai", component: component, model: model, policy: policy)
  }
  func validate() throws {
    try require(
      ["human", "programmatic", "ai"].contains(kind) && !component.isEmpty
        && component.utf8.count <= 256
        && (model?.utf8.count ?? 0) <= 4096 && (policy?.utf8.count ?? 0) <= 4096
        && (kind != "ai" || (!(model ?? "").isEmpty && !(policy ?? "").isEmpty)),
      "change_actor", "Decision attribution needs a component and any required model and policy.")
  }
  var label: String {
    kind == "human"
      ? "The user" : kind == "ai" ? "The AI under its saved policy" : "The calling program"
  }
}

enum ChangeAttribution {
  @TaskLocal static var actor: ChangeActor?
}

/// SQLite values are lossless here, independently of the public JSON Value API.
/// Integers and IEEE-754 bits are strings; text/blob bytes use base64, including NULs.
enum ChangeCell: Codable, Equatable {
  case null
  case integer(String)
  case real(String)
  case text(Data)
  case blob(Data)

  var string: String? {
    if case .text(let data) = self { return String(data: data, encoding: .utf8) }
    return nil
  }
}

struct ChangeRow: Codable, Equatable {
  let rowID: String
  let values: [ChangeCell]
}
struct RowChange: Codable, Equatable {
  let table: String
  let before: ChangeRow?
  let after: ChangeRow?
  var resetProjection: Bool? = nil
}
struct CommittedChange: Codable, Equatable {
  let version: Int
  let storageVersion: Int
  let id: String
  let workbookID: String
  let previousID: String?
  let previousHash: String?
  let recorded: String
  let writerID: String
  let actor: ChangeActor
  let changes: [RowChange]
}

enum ChangeFormat {
  // Every ordinary canonical table must be classified. Schema changes fail
  // opening until the new durable family has a declared capture policy.
  static let tables: Set<String> = [
    "meta", "assets", "items", "heads", "lineage", "chunks", "extraction", "effects", "bases",
    "datasets", "dataset_rows", "table_changes", "column_versions", "operations", "agent_runs",
    "conversations", "messages", "chapters", "bookmarks", "spaces", "space_versions",
    "context_checkpoints", "checkpoint_inputs", "run_requests", "message_payloads", "tool_calls",
    "reference_sets", "reference_heads", "reference_bindings", "reference_coverage",
    "reference_index",
    "file_reference_inputs", "file_reference_sets", "file_reference_heads", "file_reference_index",
    "intake_jobs", "app_definitions", "app_definition_heads", "app_definition_dependencies",
    "workflow_runs", "workflow_steps", "workflow_attempts", "workflow_approvals", "workflow_outbox",
    "automation_activations", "automation_occurrences", "automation_outbox",
  ]
  static func isIndex(_ table: String) -> Bool {
    ["search_fts", "names_fts", "message_fts", "definition_fts"].contains {
      table == $0 || table.hasPrefix($0 + "_")
    }
  }
  static func isPresentation(_ key: String) -> Bool {
    key == "space-navigation" || key.hasPrefix("conversation-view:") || key.hasPrefix("form-draft:")
      || key.hasPrefix("workflow-clarification-draft:")
  }
  static func portable(_ row: ChangeRow?, table: String) -> ChangeRow? {
    guard let row else { return nil }
    var values = row.values
    if table == "meta", let key = values.first?.string, isPresentation(key) { return nil }
    if table == "assets", values.count == 10, values[6].string == "linked" {
      values[2] = .text(Data())  // device path
      values[8] = .null  // local access bookmark
    }
    if table == "intake_jobs", values.count == 10 { values[4] = .null }  // worker claim
    return .init(rowID: row.rowID, values: values)
  }
  static func encode<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
  static func hash(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  static func quote(_ name: String) -> String {
    "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }
}
