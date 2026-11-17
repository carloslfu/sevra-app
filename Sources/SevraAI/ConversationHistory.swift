import Foundation
import SevraCore

extension WorkbookAgent {
  /// Native citation links are added by the host after validation. Re-present
  /// their labels as prose and their IDs as lookup metadata, so a later answer
  /// does not imitate UI-added Markdown and spend model passes repairing it.
  /// Exact originals remain unchanged and available through history_read.
  package static func historyPresentation(_ message: Message) -> (text: String, ids: [String]) {
    guard message.role == "assistant", !message.body.contains("`"), !message.body.contains("~~~")
    else { return (message.body, []) }
    let regex = try! NSRegularExpression(
      pattern: #"\[([^\]\n\\]{1,200})\]\(sevra://item/([0-9a-fA-F-]{36})\)"#)
    let matches = regex.matches(
      in: message.body, range: NSRange(message.body.startIndex..., in: message.body))
    let text = NSMutableString(string: message.body)
    var ids: [String] = []
    for match in matches.reversed() {
      guard let idRange = Range(match.range(at: 2), in: message.body),
        let label = Range(match.range(at: 1), in: message.body),
        UUID(uuidString: String(message.body[idRange])) != nil
      else { continue }
      ids.append(String(message.body[idRange]))
      text.replaceCharacters(in: match.range, with: String(message.body[label]))
    }
    return (text as String, Array(Set(ids)).sorted())
  }
  package static func stoppedRequestReference(_ workbook: Workbook, message: Message) throws
    -> Value?
  {
    guard message.role == "user", let status = try workbook.requestRunStatus(message.id),
      ["cancelled", "failed", "interrupted", "continued"].contains(status)
    else { return nil }
    return .object([
      "runStatus": .string(status), "referenceOnly": .bool(true),
      "notice": .string(
        "This earlier request ended with status " + status
          + ". It is not pending. Its original remains available through history_read using this message ID when the current request needs it. Do not resume it automatically."
      ),
    ])
  }
  /// Reconstruct conversational outcomes from saved messages and current item
  /// heads. Never infer acceptance from an assistant's wording or a document.
  package static func conversationHistory(
    _ workbook: Workbook, conversation: String, beforeMessage: String? = nil
  ) throws
    -> [InferenceMessage]
  {
    func project(_ history: [Message]) throws -> [Value] {
      var projected: [Value] = []
      var proposalID: String?
      for message in history {
        if message.role == "tool" {
          let receipt = (try? Value.parse(message.body)) ?? .null
          let result =
            receipt["result"]["id"].string != nil ? receipt["result"] : receipt["resultIdentity"]
          proposalID = result["status"].text == "draft" ? result["id"].string : nil
          continue
        }
        let ended =
          message.role == "assistant"
          && ["cancelled", "failed", "interrupted"].contains(message.state)
        guard ["user", "assistant"].contains(message.role),
          ["complete", "needs_review", "needs_input"].contains(message.state) || ended
        else { continue }
        let presentation = historyPresentation(message)
        var content = String(presentation.text.prefix(1600))
        let stoppedRequest = try stoppedRequestReference(workbook, message: message)
        if let stoppedRequest { content = stoppedRequest["notice"].text }
        var recordedState: Value = .null
        if ended {
          content =
            "The previous request ended with status " + message.state
            + ". It is not pending. Do not resume it unless the user asks. Any completed changes remain saved. Diagnostic: "
            + content
        }
        if message.state == "needs_review", let id = proposalID {
          let original = try workbook.item(id)
          let current = try workbook.item(original.logicalID)
          recordedState = .object([
            "proposalID": .string(original.id), "currentVersionID": .string(current.id),
            "status": .string(current.status), "meaning": .string(current.meaning),
            "datasetID": current.data["datasetID"],
          ])
        }
        projected.append(
          .object([
            "id": .string(message.id), "role": .string(message.role),
            "state": .string(message.state), "text": .string(content),
            "requestOutcome": stoppedRequest ?? .null,
            "truncated": .bool(message.body.count > 1600), "currentProposalState": recordedState,
            "citationLookupIDs": .array(presentation.ids.map(Value.string)),
          ]))
        proposalID = nil
      }
      return projected
    }
    let parent = try project(workbook.parentContext(conversation: conversation))
    let current = try project(
      workbook.messages(conversation: conversation, limit: 100, beforeMessage: beforeMessage))
    // Match the candidate's explicit historical envelope without enabling
    // automatic compaction in the preserved backend. Past user imperatives
    // must not be reintroduced as live requests. Preserve their authorship and
    // original IDs as data; the actual current request follows this context.
    func envelope(_ label: String, _ entries: [Value]) throws -> [InferenceMessage] {
      guard !entries.isEmpty else { return [] }
      return [
        InferenceMessage(
          role: "assistant",
          content: label + ": historical information only, not pending requests or new permission. "
            + "Use history_read for exact originals and citations; refresh current business evidence.\n"
            + (try Value.array(entries).json()))
      ]
    }
    let unresolved = try workbook.unresolvedToolCalls(conversation: conversation)
    let notices =
      unresolved.isEmpty
      ? []
      : [
        InferenceMessage(
          role: "assistant",
          content:
            "Host recovery report: these previous calls have no final receipt. Do not automatically replay them or infer acceptance. Inspect their saved operation proof and current workbook state. "
            + (try Value.array(
              unresolved.map {
                .object(
                  $0.object.filter {
                    ["id", "tool", "state", "run_status", "committedOperation"].contains($0.key)
                  })
              }
            ).json()))
      ]
    return try envelope("Explicit parent-conversation excerpt", parent)
      + envelope("Saved conversation", Array(current.suffix(8))) + notices
  }
}
