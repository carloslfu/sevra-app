import Foundation
import SevraCore

extension WorkbookAgent {
  /// Reconstruct conversational outcomes from saved messages and current item
  /// heads. Never infer acceptance from an assistant's wording or a document.
  package static func conversationHistory(_ workbook: Workbook, conversation: String) throws
    -> [InferenceMessage]
  {
    func project(_ history: [Message]) throws -> [InferenceMessage] {
      var projected: [InferenceMessage] = []
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
          ["complete", "needs_review"].contains(message.state) || ended
        else { continue }
        var content = String(message.body.prefix(1600))
        if ended {
          content =
            "The previous request ended with status " + message.state
            + ". It is not pending. Do not resume it unless the user asks. Any completed changes remain saved. Diagnostic: "
            + content
        }
        if message.state == "needs_review", let id = proposalID {
          let original = try workbook.item(id)
          let current = try workbook.item(original.logicalID)
          let state: Value = .object([
            "proposalID": .string(original.id), "currentVersionID": .string(current.id),
            "status": .string(current.status), "meaning": .string(current.meaning),
            "datasetID": current.data["datasetID"],
          ])
          content +=
            "\nCurrent recorded proposal state: " + (try state.json())
            + ". This is historical workbook state, not permission for a new action."
        }
        projected.append(InferenceMessage(role: message.role, content: content))
        proposalID = nil
      }
      return projected
    }
    let parent = try project(workbook.parentContext(conversation: conversation))
    let current = try project(workbook.messages(conversation: conversation, limit: 100))
    let unresolved = try workbook.unresolvedToolCalls(conversation: conversation)
    let notices =
      unresolved.isEmpty
      ? []
      : [
        InferenceMessage(
          role: "user",
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
    return parent + current.suffix(8) + notices
  }
}
