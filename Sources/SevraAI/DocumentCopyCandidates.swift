import Foundation
import SevraCore

/// Only host-presented complete passages supply generation choices. Neither
/// user prose nor a model-written summary can add an ID to this vocabulary.
package enum DocumentCopyCandidates {
  package static func normalized(_ values: [String]) throws -> [String] {
    let ids = Array(Set(values)).sorted()
    try require(
      ids.count <= 256 && ids.allSatisfy { $0.hasPrefix("copy:") && $0.utf8.count <= 128 },
      "context_limit", "Too many source-copy choices. Narrow the document task.")
    return ids
  }
  package static func ids(in messages: [InferenceMessage]) throws -> [String] {
    try normalized(messages.flatMap(\.documentCopyIDs))
  }
  package static func ids(in result: Value) -> [String] {
    DocumentCopyChoices.entries(result).compactMap { entry in
      guard entry["text"].string != nil else { return nil }
      return entry["id"].string
    }
  }
  package static func validate(tool: String, arguments: Value, choices: [String]) throws {
    guard tool == "draft" else { return }
    let selected = arguments["parts"].array.compactMap { $0["copy"].string }
    try require(
      Set(selected).isSubset(of: Set(choices)), "document_copy_scope",
      "Choose a complete original passage shown in the current context. Read omitted passages before copying; earlier summaries cannot supply copy choices."
    )
  }
}
