import Foundation

extension Workbook {
  /// Preparation is retained attribution, never confirmation or business truth.
  func validateWorkflowAnswerPreparation(_ preparation: Value, target: Value) throws {
    _ = try definitionObject(
      preparation,
      keys: ["requestSourceID", "agentRunID", "readReceiptID", "values", "quotes", "policy"])
    try require(
      preparation.object.count == 6
        && preparation["policy"].text == "workflow-answer-preparation-v1",
      "workflow_answer", "Keep the exact conversation answer preparation.")
    let source = try item(preparation["requestSourceID"].text)
    guard
      let request = try db.execute(
        "SELECT a.conversation_id,r.message_id,m.body FROM agent_runs a JOIN run_requests r ON r.run_id=a.id JOIN messages m ON m.id=r.message_id WHERE a.id=? AND m.role='user' AND m.conversation_id=a.conversation_id",
        [preparation["agentRunID"]]
      ).first
    else { throw SevraError("workflow_answer", "The original submitted message is unavailable.") }
    try require(
      source.id == preparation["requestSourceID"].text && source.category == "source"
        && source.kind == "request" && source.text == request["body"]!.text
        && source.data["messageID"] == request["message_id"]
        && source.data["conversationID"] == request["conversation_id"],
      "workflow_answer", "Use the exact current submitted request, not earlier chat or evidence.")
    let readID = preparation["readReceiptID"].text
    let call = try toolCall(readID, conversation: request["conversation_id"]!.text)
    try require(
      call["run_id"] == preparation["agentRunID"] && call["tool"].text == "read_workflow"
        && call["state"].text == "completed"
        && call["arguments"] == .object(["id": target["runID"]]),
      "workflow_answer", "Read this exact workflow successfully in the same request first.")
    let row = try db.execute(
      "SELECT result,result_hash FROM tool_calls WHERE id=?", [.string(readID)]
    ).first!
    let raw = row["result"]!.text
    try require(
      ToolResultProjection.digest(raw) == row["result_hash"]!.text
        && Value.parse(raw)["clarification"] == target,
      "workflow_answer", "The read receipt does not retain this exact missing-information request.")
    let definition = try applicationDefinition(target["definitionID"].text)
    let interpretation = try DefinitionInterpretation(DefinitionDescriptor(definition.content))
    let values = preparation["values"]
    let normalized = try clarificationValues(
      values, interpretation: interpretation, evidenceIDs: target["evidenceIDs"].array)
    let quotes = preparation["quotes"]
    try require(
      values == normalized && Set(quotes.object.keys) == Set(values.object.keys)
        && !values.object.isEmpty && quotes.json().utf8.count <= 16_000,
      "workflow_answer", "Quote this submission for every prepared value.")
    for quote in quotes.object.values {
      guard let text = quote.string, !text.isEmpty, text.utf8.count <= 4096,
        Data(source.text.utf8).range(of: Data(text.utf8)) != nil
      else {
        throw SevraError(
          "workflow_answer", "Each quotation must match the current message exactly.")
      }
    }
  }

  func prepareConversationWorkflowAnswer(
    readReceiptID: String, values: Value, quotes: Value, reason: String,
    runID: String, conversation: String, requestSourceID: String?, readOnly: Bool,
    cancellation: Cancellation
  ) throws -> Value {
    try require(!readOnly, "read_only_request", "Read-only requests cannot prepare answer inputs.")
    return try presentationMutation {
      try cancellation.check()
      try validateApplicationToolRun(
        runID, conversation: conversation, requestSourceID: requestSourceID)
      let call = try toolCall(readReceiptID, conversation: conversation)
      let target = try workflowClarification(call["arguments"]["id"].text)
      let definition = try applicationDefinition(target["definitionID"].text)
      let interpretation = try DefinitionInterpretation(DefinitionDescriptor(definition.content))
      let normalized = try clarificationValues(
        values, interpretation: interpretation, evidenceIDs: target["evidenceIDs"].array)
      let preparation: Value = .object([
        "requestSourceID": .string(requestSourceID!), "agentRunID": .string(runID),
        "readReceiptID": .string(readReceiptID), "values": normalized, "quotes": quotes,
        "policy": .string("workflow-answer-preparation-v1"),
      ])
      try validateWorkflowAnswerPreparation(preparation, target: target)
      let workflowID = target["runID"].text
      let current = try workflowClarificationDraft(workflowID)
      if let current, current.entry.preparation == preparation,
        current.entry.reason == reason && current.entry.values == normalized
          && current.entry.receipt == nil
      {
        return workflowAnswerPreparationResult(current)
      }
      try require(
        current == nil
          || (current!.entry.values == .object([:]) && current!.entry.reason.isEmpty
            && current!.entry.preparation == nil && current!.entry.receipt == nil
            && current!.alternatives.isEmpty),
        "clarification_draft_conflict",
        "This workflow already has saved inputs. Review or preserve those answers before preparing another."
      )
      var draft = WorkflowClarificationDraft(target: target)
      draft.entry.values = normalized
      draft.entry.reason = reason
      draft.entry.preparation = preparation
      _ = try previewWorkflowClarificationDraft(draft)
      try cancellation.check()
      let saved = try saveClarificationDraft(
        workflowID, draft: draft, expected: current, keepOther: false)
      return workflowAnswerPreparationResult(saved)
    }
  }

  private func workflowAnswerPreparationResult(_ draft: WorkflowClarificationDraft) -> Value {
    .object([
      "state": .string("prepared_inputs"), "workflowRunID": draft.entry.target["runID"],
      "entryID": .string(draft.entry.id), "values": draft.entry.values,
      "reason": .string(draft.entry.reason), "meaning": draft.entry.target["meaning"],
      "scenario": draft.entry.target["scenario"],
      "notice": .string(
        "AI-prepared unsent inputs. Preview and confirm them yourself. No interpretation completed, workflow continued or business changes accepted."
      ),
    ])
  }
}
