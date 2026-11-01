import Foundation

extension Workbook {
  /// Preserve submitted text and its derived draft in one transaction.
  /// A separate draft is an explicit copy, never a silent overwrite of a newer
  /// version. Meaning, scenario and business metadata survive either operation.
  /// Free-text edits discard exact-copy spans. An explicit binding-only change
  /// with byte-identical prose preserves them on the new version.
  public func editDocument(
    _ versionID: String, text: String, separate: Bool = false,
    token: String = identifier(), expectedRevision: Int? = nil,
    cancellation: Cancellation = .init(), references: [ReferenceSelection]? = nil
  ) throws -> Item {
    try cancellation.check()
    var fields: [String: Value] = [
      "version": .string(versionID), "text": .string(text), "separate": .bool(separate),
    ]
    if let references { fields["references"] = try Self.referenceSelectionsValue(references) }
    let result = try mutation(
      "document_edit", token: token, request: .object(fields), expected: expectedRevision,
      cancellation: cancellation
    ) {
      try cancellation.check()
      let original = try item(versionID)
      try require(
        original.id == versionID, "document_version", "Use the exact document version you edited.")
      try require(
        original.category == "record" && original.kind == "document" && original.assetID == nil,
        "document_edit",
        "Only generated text documents can be edited here. Original file assets remain unchanged.")
      if !separate {
        try require(
          try item(original.logicalID).id == original.id, "stale_revision",
          "This document has a newer version. Your unsaved text is still available.")
        try require(
          original.status != "rejected", "document_edit",
          "This version was withdrawn. Keep your changes as a separate draft instead.")
      }
      let source = try insertItem(
        category: "source", kind: "submission",
        title: original.title.utf8.count <= 4_090 ? "Edit " + original.title : "Document edit",
        text: text, data: .object(["document": .string(original.id), "separate": .bool(separate)]),
        meaning: original.meaning, status: "accepted", scenario: original.scenario, inputs: [],
        transformation: "document-input-v1", inheritReferenceBindings: false)
      try cancellation.check()
      var data = original.data
      // A free-text edit can move or change any copied span. Its new submission
      // and original-document lineage preserve evidence without asserting stale
      // byte positions or silently realigning repeated passages.
      let bindingOnly =
        references != nil && !separate && text.utf8.elementsEqual(original.text.utf8)
      if !bindingOnly, case .object(var fields) = data {
        fields.removeValue(forKey: "documentComposition")
        data = .object(fields)
      }
      let draft = try insertItem(
        category: "record", kind: "document",
        title: separate ? Self.documentCopyTitle(original.title) : original.title,
        text: text, data: data, meaning: original.meaning, status: "draft",
        scenario: original.scenario, inputs: [original.id, source],
        transformation: "document-edit-v1", supersedes: separate ? nil : original.id,
        referenceOrigin: original.id,
        inheritReferenceBindings: references == nil)
      if let references {
        try publishInitialReferences(
          draft, selections: references, inheritedOrigin: original.id)
      }
      try cancellation.check()
      return .string(draft)
    }
    return try item(result.text)
  }

  private static func documentCopyTitle(_ original: String) -> String {
    let suffix = " (draft copy)"
    var prefix = ""
    var count = 0
    for character in original {
      let size = String(character).utf8.count
      guard count + size + suffix.utf8.count <= 4096 else { break }
      prefix.append(character)
      count += size
    }
    return prefix.isEmpty ? "Draft copy" : prefix + suffix
  }
}
