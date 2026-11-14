import Foundation
import SevraCore

/// Keep the latest complete calculation/UI exchanges and one strictly better partial
/// calculation as a repair anchor. Never discard passing branches by forgetting that anchor.
/// A partial candidate is evidence, not a verified draft or permission to save. Original
/// evidence, the user request and successful writes remain verbatim; all attempts stay in the
/// workbook's durable receipts. This does not reset the step or repeated-failure budgets.
package enum ExcelBuildContext {
  package static func refresh(_ messages: [InferenceMessage]) -> [InferenceMessage] {
    var latestComparison: Int?
    var latestFailedSave: Int?
    var superseded = Set<Int>()
    var comparisons: [Int] = []
    var repairContent: [Int: String] = [:]
    for index in messages.indices.reversed() where index > 0 {
      let result = messages[index]
      let call = messages[index - 1]
      guard result.role == "tool", call.role == "assistant", call.toolCalls.count == 1,
        call.toolCalls[0].id == result.toolCallId,
        call.toolCalls[0].name == result.toolName
      else { continue }
      let replace: Bool
      if result.toolName == "compare_excel_behavior" {
        comparisons.append(index)
        if var fields = (try? Value.parse(result.content))?.object,
          fields.removeValue(forKey: "repairAnchor") != nil
        {
          repairContent[index] = try? Value.object(fields).json()
        }
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
    if let latest = comparisons.first,
      let current = try? Value.parse(messages[latest].content),
      current["status"] == .string("mismatch"), !current["differences"].array.isEmpty,
      let version = current["conversionVersion"].string, !version.isEmpty,
      let compared = current["compared"].int, compared > 0
    {
      var best = latest
      var fewest = current["differences"].array.count
      for index in comparisons.dropFirst() {
        guard let previous = try? Value.parse(messages[index].content) else { continue }
        // A matched/replaced comparison is a new draft boundary. Do not resurrect it.
        if previous["status"] == .string("matched") { break }
        guard previous["status"] == .string("mismatch"),
          previous["conversionVersion"] == .string(version),
          previous["compared"] == .number(Double(compared)),
          messages[index - 1].content.utf8.count
            + messages[index - 1].toolCalls[0].inputJSON.utf8.count
            + messages[index].content.utf8.count <= 24_000
        else { continue }
        let count = previous["differences"].array.count
        if count > 0 && count < fewest {
          best = index
          fewest = count
        }
      }
      if best != latest {
        superseded.subtract([best - 1, best])
        var fields = current.object
        fields["repairAnchor"] = .object([
          "toolCallID": .string(messages[best].toolCallId ?? ""),
          "reportedDifferences": .number(Double(fewest)),
          "instruction": .string(
            "The earlier complete candidate retained above had fewer original-result differences. Repair its remaining branches instead of discarding calculations that already matched. It is NOT a verified draft: compare the corrected source again. All original comparison, save, step and repeated-failure gates still apply."
          ),
        ])
        repairContent[latest] = try? Value.object(fields).json()
      }
    }
    return messages.enumerated().compactMap { index, message in
      guard !superseded.contains(index) else { return nil }
      guard !message.reasoning.isEmpty || repairContent[index] != nil else { return message }
      var clean = InferenceMessage(
        role: message.role, content: repairContent[index] ?? message.content,
        toolCalls: message.toolCalls,
        toolCallId: message.toolCallId, toolName: message.toolName,
        itemReferences: message.itemReferences, conversationActions: message.conversationActions,
        documentCopyIDs: message.documentCopyIDs, historyReferences: message.historyReferences)
      clean.nativeAppAuthoring = message.nativeAppAuthoring
      return clean
    }
  }
}
