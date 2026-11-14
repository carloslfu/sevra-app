import Foundation
import SevraCore

/// A conversion has one calculation draft and one UI candidate. Keep their latest complete
/// tool exchanges, not obsolete broken programs or the reasoning that produced them. Original
/// evidence, the user request and successful writes remain verbatim; all attempts stay in the
/// workbook's durable receipts. This does not reset the step or repeated-failure budgets.
package enum ExcelBuildContext {
  package static func refresh(_ messages: [InferenceMessage]) -> [InferenceMessage] {
    var latestComparison: Int?
    var latestFailedSave: Int?
    var superseded = Set<Int>()
    for index in messages.indices.reversed() where index > 0 {
      let result = messages[index]
      let call = messages[index - 1]
      guard result.role == "tool", call.role == "assistant", call.toolCalls.count == 1,
        call.toolCalls[0].id == result.toolCallId,
        call.toolCalls[0].name == result.toolName
      else { continue }
      let replace: Bool
      if result.toolName == "compare_excel_behavior" {
        replace = latestComparison != nil
        latestComparison = index
      } else if result.toolName == "save_native_app",
        let value = try? Value.parse(result.content), value["error"].string != nil
      {
        replace = latestFailedSave != nil
        latestFailedSave = index
      } else {
        continue
      }
      if replace { superseded.formUnion([index - 1, index]) }
    }
    return messages.enumerated().compactMap { index, message in
      guard !superseded.contains(index) else { return nil }
      guard !message.reasoning.isEmpty else { return message }
      var clean = InferenceMessage(
        role: message.role, content: message.content, toolCalls: message.toolCalls,
        toolCallId: message.toolCallId, toolName: message.toolName,
        itemReferences: message.itemReferences, conversationActions: message.conversationActions,
        documentCopyIDs: message.documentCopyIDs, historyReferences: message.historyReferences)
      clean.nativeAppAuthoring = message.nativeAppAuthoring
      return clean
    }
  }
}
