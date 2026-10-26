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
          let result = (try? Value.parse(message.body))?["result"] ?? .null
          proposalID = result["status"].text == "draft" ? result["id"].string : nil
          continue
        }
        guard ["user", "assistant"].contains(message.role),
          ["complete", "needs_review"].contains(message.state)
        else { continue }
        var content = String(message.body.prefix(1600))
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
    return parent + current.suffix(8)
  }
}
