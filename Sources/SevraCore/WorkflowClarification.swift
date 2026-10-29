import Foundation

extension Workbook {
  /// Inspecting missing information grants no execution or submission authority.
  public func workflowClarification(_ runID: String) throws -> Value {
    try synchronized { try pendingWorkflowClarification(workflowRun(runID)) }
  }

  private func pendingWorkflowClarification(_ run: Value) throws -> Value {
    guard run["state"] == .string("needs_attention"),
      let step = run["steps"].array.first(where: { $0["state"] != .string("completed") }),
      step["state"] == .string("needs_attention"), step["kind"] == .string("interpret"),
      step["output"]["value"]["kind"] == .string("interpretation"),
      step["output"]["value"]["response"]["state"] == .string("needs_input"),
      step["output"]["value"]["clarification"] == .null
    else {
      throw SevraError(
        "workflow_clarification", "This run has no paused interpretation awaiting information.")
    }
    return try workflowClarificationTarget(runID: run["id"].text, step: step)
  }

  func workflowClarificationTarget(runID: String, step: Value) throws -> Value {
    let value = step["output"]["value"]
    let definition = try applicationDefinition(step["output"]["definitionID"].text)
    let interpretation = try DefinitionInterpretation(DefinitionDescriptor(definition.content))
    return .object([
      "workbookID": .string(id), "runID": .string(runID), "stepID": step["step_id"],
      "outputHash": .string(ChangeFormat.hash(try step["output"].json())),
      "definitionID": .string(definition.id), "originalRecordID": value["recordID"],
      "title": .string(definition.title), "fields": interpretation.rawOutputs,
      "meaning": .string(interpretation.meaning), "scenario": .string(interpretation.scenario),
      "issues": value["response"]["issues"],
      "evidenceIDs": .array(value["request"]["evidence"].array.map { $0["id"] }),
    ])
  }

  func clarificationValues(
    _ values: Value, interpretation: DefinitionInterpretation, evidenceIDs: [Value]
  ) throws -> Value {
    let raw = try definitionObject(values, keys: Set(interpretation.outputs.map(\.id)))
    var result: [String: Value] = [:]
    func checkItems(_ parameter: DefinitionParameter, _ value: Value) throws {
      if parameter.type == "item", value != .null {
        try require(
          evidenceIDs.contains(value), "workflow_clarification",
          "Item values must stay within the original interpretation evidence.")
      }
      if parameter.type == "entries" {
        for row in value.array {
          for field in parameter.fields { try checkItems(field, row[field.id]) }
        }
      }
    }
    for field in interpretation.outputs {
      guard let supplied = raw[field.id] else {
        try require(
          !field.required, "workflow_clarification", "Supply the missing value: " + field.label)
        continue
      }
      let value = try field.normalize(supplied)
      try checkItems(field, value)
      result[field.id] = value
    }
    let normalized = Value.object(result)
    try require(
      try normalized.json().utf8.count <= 65_536, "workflow_limit",
      "Clarification values exceed 64 KiB.")
    return normalized
  }

  /// Adds supplied information without rewriting the original model response.
  /// CLI attribution remains programmatic; only an actual native submission may
  /// identify a human. No acceptance or subsequent step runs in this operation.
  public func clarifyWorkflow(
    _ session: WorkflowExecutionSession, target: Value, values: Value, reason: String,
    token: String, actor: ChangeActor = .programmatic("SevraCore.workflowClarification"),
    readOnly: Bool = false, preparation: Value? = nil, cancellation: Cancellation = .init()
  ) throws -> Value {
    try workflowSession(session)
    try workflowToken(token)
    try require(!readOnly, "read_only_request", "Read-only requests cannot supply workflow values.")
    try actor.validate()
    try require(
      actor.kind != "ai", "workflow_clarification",
      "AI clarification submission is not qualified. Ask the user for missing information.")
    try require(
      !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && reason.utf8.count <= 4096,
      "workflow_clarification", "Explain the supplied information in at most 4096 UTF-8 bytes.")
    var arguments: [String: Value] = [
      "target": target, "values": values, "reason": .string(reason), "actor": try encoded(actor),
    ]
    if let preparation { arguments["preparation"] = preparation }
    let result = try mutation(
      "workflow_clarification", token: token,
      request: .object(arguments), cancellation: cancellation, actor: actor
    ) {
      let run = try self.workflowRun(session.runID)
      try require(
        try self.pendingWorkflowClarification(run) == target,
        "stale_workflow_clarification", "The paused interpretation changed. Inspect it again.")
      let saved = run["steps"].array.first { $0["step_id"] == target["stepID"] }!
      let definition = try self.applicationDefinition(target["definitionID"].text)
      let interpretation = try DefinitionInterpretation(DefinitionDescriptor(definition.content))
      let normalized = try self.clarificationValues(
        values, interpretation: interpretation, evidenceIDs: target["evidenceIDs"].array)
      var inputIDs = [target["originalRecordID"].text]
      var sourceData: [String: Value] = [
        "target": target, "values": normalized, "reason": .string(reason),
        "actor": try encoded(actor), "policy": .string("workflow-clarification-v1"),
      ]
      if let preparation {
        try self.validateWorkflowAnswerPreparation(preparation, target: target)
        inputIDs.append(preparation["requestSourceID"].text)
        sourceData["preparation"] = preparation
      }
      let source = try self.insertItem(
        category: "source", kind: "submission", title: "Clarification: " + definition.title,
        text: reason + "\n" + (try normalized.json()),
        data: .object(sourceData), meaning: interpretation.meaning, status: "accepted",
        scenario: interpretation.scenario,
        inputs: inputIDs.sorted(),
        transformation: "workflow-clarification-submission-v1")
      let record = try self.insertItem(
        category: "record", kind: "interpretation_clarification", title: definition.title,
        text: "Supplied clarification. Review before business use. " + reason,
        data: .object([
          "sourceID": .string(source), "originalRecordID": target["originalRecordID"],
          "definitionID": target["definitionID"], "values": normalized,
          "policy": .string("workflow-clarification-v1"),
        ]), meaning: interpretation.meaning, status: "draft", scenario: interpretation.scenario,
        inputs: [source, target["originalRecordID"].text, definition.sourceID].sorted(),
        transformation: "workflow-clarification-v1")
      var value = saved["output"]["value"].object
      var supplied: [String: Value] = [
        "sourceID": .string(source), "recordID": .string(record), "values": normalized,
        "actor": try encoded(actor), "reason": .string(reason), "target": target,
      ]
      if let preparation { supplied["preparation"] = preparation }
      value["clarification"] = .object(supplied)
      var output = saved["output"].object
      output["value"] = .object(value)
      try require(
        try Value.object(output).json().utf8.count <= 524_288, "workflow_limit",
        "The clarified output and its original provenance exceed 512 KiB.")
      try self.db.execute(
        "UPDATE workflow_steps SET state='completed',output=?,detail='',updated=? WHERE run_id=? AND step_id=?",
        [
          .string(try Value.object(output).json()), .string(timestamp()), run["id"],
          target["stepID"],
        ])
      let remaining = try self.db.scalar(
        "SELECT count(*) FROM workflow_steps WHERE run_id=? AND state!='completed'", [run["id"]]
      ).int!
      try self.db.execute(
        "UPDATE workflow_runs SET state=?,detail='',updated=? WHERE id=?",
        [.string(remaining == 0 ? "completed" : "queued"), .string(timestamp()), run["id"]])
      try self.workflowEvent(
        session.runID, stepID: target["stepID"].text, kind: "clarified",
        payload: .object(value)["clarification"])
      WorkflowPublicationProbe.observer?(.prepared, session.runID)
      return try self.workflowRun(session.runID)
    }
    WorkflowPublicationProbe.observer?(.committed, session.runID)
    return result
  }

  func validateWorkflowClarification(_ output: Value, runID: String, stepID: String) throws {
    let value = output["value"]
    let clarification = value["clarification"]
    guard clarification != .null else { return }
    let c = try definitionObject(
      clarification,
      keys: ["sourceID", "recordID", "values", "actor", "reason", "target", "preparation"])
    let actor = try JSONDecoder().decode(
      ChangeActor.self, from: Data(clarification["actor"].json().utf8))
    try actor.validate()
    let source = try item(clarification["sourceID"].text)
    let record = try item(clarification["recordID"].text)
    let target = clarification["target"]
    let definition = try applicationDefinition(output["definitionID"].text)
    let interpretation = try DefinitionInterpretation(DefinitionDescriptor(definition.content))
    let normalized = try clarificationValues(
      clarification["values"], interpretation: interpretation,
      evidenceIDs: value["request"]["evidence"].array.map { $0["id"] })
    var originalValue = value.object
    originalValue.removeValue(forKey: "clarification")
    var originalOutput = output.object
    originalOutput["value"] = .object(originalValue)
    let expectedTarget = try workflowClarificationTarget(
      runID: runID, step: .object(["step_id": .string(stepID), "output": .object(originalOutput)]))
    var expectedData: [String: Value] = [
      "target": target, "values": normalized, "reason": clarification["reason"],
      "actor": clarification["actor"], "policy": .string("workflow-clarification-v1"),
    ]
    var sourceInputs = [value["recordID"].text]
    if let preparation = c["preparation"] {
      try validateWorkflowAnswerPreparation(preparation, target: target)
      expectedData["preparation"] = preparation
      sourceInputs.append(preparation["requestSourceID"].text)
    }
    try require(
      c.count == (c["preparation"] == nil ? 6 : 7) && actor.kind != "ai"
        && !clarification["reason"].text.isEmpty
        && clarification["reason"].text.utf8.count <= 4096
        && value["response"]["state"] == .string("needs_input")
        && target == expectedTarget
        && source.id == clarification["sourceID"].text && source.category == "source"
        && source.kind == "submission" && source.status == "accepted"
        && source.meaning == interpretation.meaning && source.scenario == interpretation.scenario
        && source.data == .object(expectedData)
        && source.text == clarification["reason"].text + "\n" + (try normalized.json())
        && record.id == clarification["recordID"].text && record.category == "record"
        && record.kind == "interpretation_clarification" && record.status == "draft"
        && record.meaning == interpretation.meaning && record.scenario == interpretation.scenario
        && record.data
          == .object([
            "sourceID": clarification["sourceID"], "originalRecordID": value["recordID"],
            "definitionID": output["definitionID"], "values": normalized,
            "policy": .string("workflow-clarification-v1"),
          ])
        && normalized == clarification["values"],
      "workflow_integrity",
      "The clarification lost its exact original output or supplied provenance.")
    let sourceParents = try db.execute(
      "SELECT parent FROM lineage WHERE child=?", [.string(source.id)]
    )
    .map { $0["parent"]!.text }
    try require(
      Set(sourceParents) == Set(sourceInputs), "workflow_integrity",
      "The supplied information lost its exact request lineage.")
    let parents = try db.execute("SELECT parent FROM lineage WHERE child=?", [.string(record.id)])
      .map { $0["parent"]!.text }
    try require(
      Set(parents) == Set([source.id, value["recordID"].text, definition.sourceID]),
      "workflow_integrity", "The clarification lost its exact input lineage.")
  }
}
