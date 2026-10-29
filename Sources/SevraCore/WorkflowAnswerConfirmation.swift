import Foundation

/// Standalone composer commands, shared by typed and dictated input.
public enum WorkflowAnswerCommand: Equatable, Sendable {
  case preview, confirm
  public static func parse(_ input: String) -> Self? {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
    if ["preview my answer", "preview this answer"].contains(text) { return .preview }
    if ["save my answer", "confirm my answer"].contains(text) { return .confirm }
    return nil
  }
}

/// Live authority stays in the native session, never in serialized chat/history.
public struct WorkflowAnswerConversationPreview: Sendable {
  public let conversation: String
  public let entry: WorkflowClarificationEntry
  public let preview: Value
  public let messageID: String
  public let cancellation = Cancellation()
  fileprivate let owner: ObjectIdentifier
}

extension Workbook {
  func workflowAnswerPreviewHash(
    target: Value, values: Value, reason: String, preparation: Value?
  ) throws -> String {
    let definition = try applicationDefinition(target["definitionID"].text)
    let interpretation = try DefinitionInterpretation(DefinitionDescriptor(definition.content))
    let typed = try clarificationValues(
      values, interpretation: interpretation, evidenceIDs: target["evidenceIDs"].array)
    return ChangeFormat.hash(
      try Value.object([
        "target": target, "values": typed, "reason": .string(reason),
        "preparation": preparation ?? .null,
      ]).json())
  }

  private func workflowAnswerPreviewBody(_ preview: Value) throws -> String {
    let target = preview["target"]
    func lines(_ fields: [Value], _ values: Value, indent: String = "") throws -> [String] {
      var result: [String] = []
      for field in fields {
        let value = values[field["id"].text]
        guard value != .null else { continue }
        let label = indent + field["label"].text
        if field["type"].text == "entries" {
          result.append(label + ":")
          for (index, row) in value.array.enumerated() {
            result.append(indent + "  Entry \(index + 1):")
            result += try lines(field["fields"].array, row, indent: indent + "    ")
          }
        } else {
          let display =
            field["type"].text == "item" ? try item(value.text).referenceMarkdown : value.text
          result.append(label + ": " + display + (field["unit"].string.map { " " + $0 } ?? ""))
        }
      }
      return result
    }
    let values = try lines(target["fields"].array, preview["values"]).joined(separator: "\n")
    let body = """
      Review your answer for “\(target["title"].text)”:

      \(values)

      Meaning: \(target["meaning"].text). Scenario: \(target["scenario"].text).
      Explanation: \(preview["reason"].text)

      Say or type “Save my answer” to save these exact values. This completes only the paused interpretation. Continuing the workflow and reviewing business changes are separate.
      """
    try require(
      body.utf8.count <= 128_000, "message_limit",
      "This answer is too large to preview in the conversation. Use the full native preview.")
    return body
  }

  public func previewWorkflowAnswerForConversation(
    _ draft: WorkflowClarificationDraft, conversation: String, cancellation: Cancellation = .init()
  ) throws -> WorkflowAnswerConversationPreview {
    try synchronized(cancellation: cancellation) {
      try cancellation.check()
      let runID = draft.entry.target["runID"].text
      try require(
        try workflowClarificationDraft(runID)?.entry == draft.entry,
        "stale_workflow_clarification",
        "Your saved answer changed. Preview the current inputs again.")
      let preview = try previewWorkflowClarificationDraft(draft)
      let digest = try workflowAnswerPreviewHash(
        target: draft.entry.target, values: preview["values"], reason: draft.entry.reason,
        preparation: draft.entry.preparation)
      let message = try addMessage(
        workflowAnswerPreviewBody(preview), role: "event", conversation: conversation,
        payload: .object([
          "kind": .string("workflow_answer_preview"), "workflowRunID": .string(runID),
          "entryID": .string(draft.entry.id), "token": .string(draft.entry.token),
          "previewHash": .string(digest),
        ]))
      try cancellation.check()
      return WorkflowAnswerConversationPreview(
        conversation: conversation, entry: draft.entry, preview: preview,
        messageID: message, owner: ObjectIdentifier(self))
    }
  }

  public func confirmWorkflowAnswer(
    _ presented: WorkflowAnswerConversationPreview, messageID: String,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try presented.cancellation.check()
    try require(
      presented.owner == ObjectIdentifier(self), "workflow_answer_confirmation",
      "Preview this answer in the current workbook before confirming it.")
    try synchronized {
      try require(
        try workflowClarificationDraft(presented.entry.target["runID"].text)?.entry
          == presented.entry,
        "stale_workflow_clarification", "Your saved inputs changed. Preview them again.")
    }
    let text = try synchronized {
      try db.scalar("SELECT body FROM messages WHERE id=?", [.string(messageID)]).text
    }
    let confirmation: Value = .object([
      "policy": .string("workflow-answer-confirmation-v1"),
      "conversationID": .string(presented.conversation), "messageID": .string(messageID),
      "text": .string(text), "previewMessageID": .string(presented.messageID),
      "entryID": .string(presented.entry.id), "token": .string(presented.entry.token),
      "previewHash": .string(
        try workflowAnswerPreviewHash(
          target: presented.entry.target, values: presented.preview["values"],
          reason: presented.entry.reason, preparation: presented.entry.preparation)),
    ])
    var draft = WorkflowClarificationDraft(target: presented.entry.target)
    draft.entry = presented.entry
    return try submitWorkflowClarificationDraft(
      draft, preview: presented.preview, confirmation: confirmation,
      confirmationControl: presented.cancellation, cancellation: cancellation)
  }

  func validateWorkflowAnswerConfirmation(
    _ confirmation: Value, target: Value, values: Value, reason: String, preparation: Value?,
    current: Bool = false
  ) throws {
    let fields: Set<String> = [
      "policy", "conversationID", "messageID", "text", "previewMessageID", "entryID", "token",
      "previewHash",
    ]
    let object = try definitionObject(confirmation, keys: fields)
    let conversation = confirmation["conversationID"]
    guard object.count == fields.count,
      confirmation["policy"].text == "workflow-answer-confirmation-v1",
      WorkflowAnswerCommand.parse(confirmation["text"].text) == .confirm,
      UUID(uuidString: confirmation["entryID"].text) != nil,
      UUID(uuidString: confirmation["token"].text) != nil,
      let message = try db.execute(
        "SELECT rowid,* FROM messages WHERE id=?", [confirmation["messageID"]]
      ).first,
      let shown = try db.execute(
        "SELECT rowid,* FROM messages WHERE id=?", [confirmation["previewMessageID"]]
      ).first,
      message["role"]?.text == "user", message["conversation_id"] == conversation,
      message["body"] == confirmation["text"], shown["role"]?.text == "event",
      shown["conversation_id"] == conversation, shown["rowid"]!.int! < message["rowid"]!.int!
    else {
      throw SevraError(
        "workflow_answer_confirmation",
        "Confirm the current preview explicitly in this conversation.")
    }
    let hash = try workflowAnswerPreviewHash(
      target: target, values: values, reason: reason, preparation: preparation)
    let payload = try Value.parse(
      db.scalar(
        "SELECT payload FROM message_payloads WHERE message_id=?",
        [confirmation["previewMessageID"]]
      ).text)
    try require(
      confirmation["previewHash"].text == hash
        && payload
          == .object([
            "kind": .string("workflow_answer_preview"), "workflowRunID": target["runID"],
            "entryID": confirmation["entryID"], "token": confirmation["token"],
            "previewHash": .string(hash),
          ]),
      "workflow_answer_confirmation", "The exact answer preview changed. Preview it again.")
    try require(
      try db.scalar(
        "SELECT count(*) FROM messages WHERE conversation_id=? AND rowid>? AND rowid<?",
        [conversation, shown["rowid"]!, message["rowid"]!]
      ).int == 0,
      "workflow_answer_confirmation",
      "Another message followed this preview. Preview your answer again.")
    if current {
      try require(
        try db.scalar(
          "SELECT id FROM messages WHERE conversation_id=? ORDER BY rowid DESC LIMIT 1",
          [conversation]) == confirmation["messageID"],
        "workflow_answer_confirmation", "Confirm a fresh preview in the current conversation.")
      let saved = try workflowClarificationDraft(target["runID"].text)?.entry
      try require(
        saved?.id == confirmation["entryID"].text && saved?.token == confirmation["token"].text
          && saved?.target == target && saved?.reason == reason
          && saved?.preparation == preparation && saved?.receipt == nil,
        "stale_workflow_clarification", "Your saved inputs changed. Preview them again.")
      try require(
        try workflowAnswerPreviewHash(
          target: target, values: saved!.values, reason: saved!.reason,
          preparation: saved!.preparation) == hash,
        "stale_workflow_clarification", "Your saved inputs changed. Preview them again.")
    }
  }
}
