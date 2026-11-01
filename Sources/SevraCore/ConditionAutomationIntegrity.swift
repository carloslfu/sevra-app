import Foundation

extension Workbook {
  func verifyConditionOwner(_ consumer: [String: Value]) throws {
    let source = try item(consumer["source_id"]!.text)
    try require(
      source.kind == "condition_intent" && source.category == "source"
        && source.status == "accepted" && source.meaning == "rule"
        && source.data["subject"] == consumer["subject"]
        && source.data["rule"] == Value.parse(consumer["rule"]!.text)
        && source.data["anchorID"] == consumer["anchor_id"]
        && source.data["ownerLogicalID"] == consumer["owner_logical"]
        && source.data["definitionID"] == consumer["definition_id"],
      "condition_integrity", "The condition lost its creating intent or owner.")
    guard let owner = consumer["owner_logical"]?.string else { return }
    let definition = try applicationDefinition(consumer["definition_id"]!.text)
    guard
      let condition = try DefinitionAutomation(DefinitionDescriptor(definition.content)).condition
    else {
      throw SevraError("condition_integrity", "The consumer owner has no inventory condition.")
    }
    try require(
      definition.logicalID == owner && condition.subject == consumer["subject"]!.text
        && condition.rule == Value.parse(consumer["rule"]!.text), "condition_integrity",
      "The consumer does not match its immutable owner scope.")
    try automationLineage(source.id, definition.sourceID)
  }

  func verifyConditionActivation(_ activation: Value) throws {
    let saved = try applicationDefinition(activation["definition_id"].text)
    let condition = try DefinitionAutomation(DefinitionDescriptor(saved.content)).condition
    guard let consumerID = activation["consumer_id"].string else {
      try require(
        condition == nil && activation["policy"] != .string("condition-drafts-v1"),
        "automation_integrity", "A condition activation lost its owned consumer.")
      return
    }
    let consumer = try inventoryConditionRow(consumerID)
    try verifyConditionOwner(consumer)
    let source = try item(activation["source_id"].text)
    try require(
      condition != nil && activation["policy"] == .string("condition-drafts-v1")
        && consumer["owner_logical"] == .string(saved.logicalID)
        && consumer["subject"] == .string(condition!.subject)
        && condition!.rule == Value.parse(consumer["rule"]!.text)
        && source.data["consumerID"] == .string(consumerID),
      "automation_integrity", "The exact authorization does not own its inventory condition.")
    if source.data["state"] == .string("armed") {
      try automationLineage(source.id, consumer["source_id"]!.text)
    }
  }

  func verifyConditionRun(
    _ binding: Value, run: Value, invocation: Item, dispatch: Item,
    authority: Item, saved: ApplicationDefinition
  ) throws {
    guard
      let candidate = try db.execute(
        "SELECT * FROM condition_candidates WHERE id=?", [binding["candidate_id"]]
      ).first
    else {
      throw SevraError("automation_integrity", "The condition run lost its exact candidate.")
    }
    let observation = try validateDispatchCandidate(candidate)
    let consumer = try inventoryConditionRow(candidate["consumer_id"]!.text)
    let retained = try validateAutomationDefinition(
      DefinitionDescriptor(saved.content), historical: true)
    guard let condition = try DefinitionAutomation(DefinitionDescriptor(saved.content)).condition
    else {
      throw SevraError("automation_integrity", "The condition run points to a calendar definition.")
    }
    let causes = try inspectInventoryConditionCauses(
      candidate["observation_id"]!.text,
      cancellation: Cancellation(deadlineAfterSeconds: 3))
    let node = try automationCausalGraph([run["id"].text])[run["id"].text]!
    let trigger: Value = .object([
      "consumerID": candidate["consumer_id"]!, "candidateID": candidate["id"]!,
      "observationID": candidate["observation_id"]!,
      "knowledgeBatchID": observation["knowledgeBatchID"],
      "effectiveThrough": observation["effectiveThrough"], "quantity": observation["quantity"],
      "inputSetHash": causes["inputSetHash"],
      "workflowReadCommitID": dispatch.data["trigger"]["workflowReadCommitID"],
    ])
    let origin: Value = .object([
      "activationID": binding["activation_id"], "automationID": binding["definition_id"],
      "candidateID": binding["candidate_id"], "generation": binding["generation"],
      "authorizationSourceID": binding["authorization_source"],
      "dispatchSourceID": binding["dispatch_source"],
      "trigger": trigger, "causality": node.context,
    ])
    try require(
      binding["occurrence_id"] == .null && run["policy"] == .string("automation-drafts-v1")
        && run["definition_id"] == .string(retained.workflow.id)
        && run["arguments"] == retained.arguments
        && run["actor"] == encoded(ChangeActor.programmatic("SevraCore.automationDispatcher"))
        && invocation.data["origin"] == origin && dispatch.data["trigger"] == trigger
        && candidate["state"] == .string("dispatched")
        && candidate["detail"] == .string("workflow_queued")
        && candidate["decision_source"] == binding["dispatch_source"]
        && consumer["owner_logical"] == .string(saved.logicalID)
        && consumer["subject"] == .string(condition.subject)
        && condition.rule == Value.parse(consumer["rule"]!.text)
        && authority.kind == "automation_authorization" && authority.category == "source"
        && authority.status == "accepted" && authority.meaning == "actual"
        && authority.data["state"] == .string("armed")
        && authority.data["policy"] == .string("condition-drafts-v1")
        && authority.data["consumerID"] == candidate["consumer_id"]
        && authority.data["activationID"] == binding["activation_id"]
        && authority.data["definitionID"] == binding["definition_id"]
        && authority.data["generation"] == binding["generation"]
        && dispatch.kind == "automation_dispatch" && dispatch.category == "source"
        && dispatch.status == "accepted"
        && dispatch.meaning == "actual" && dispatch.data["policy"] == .string("condition-drafts-v1")
        && dispatch.data["activationID"] == binding["activation_id"]
        && dispatch.data["definitionID"] == binding["definition_id"]
        && dispatch.data["authorizationSourceID"] == binding["authorization_source"]
        && dispatch.data["generation"] == binding["generation"]
        && dispatch.data["candidateID"] == candidate["id"] && dispatch.data["runID"] == run["id"]
        && causes["resolution"] == .string("resolved")
        && node.roots == causes["rootIDs"].array.map(\.text)
        && node.parents == causes["automaticParentRunIDs"].array.map(\.text)
        && node.independentInputs == causes["declaredInputs"].array.map { $0["sourceID"].text },
      "automation_integrity",
      "The condition run lost its exact trigger, causes, authorization or dispatch evidence.")
    _ = try AutomationTime.date(dispatch.data["observedAt"].text)
    try require(
      try db.scalar(
        "SELECT EXISTS(SELECT 1 FROM committed_changes WHERE id=?)",
        [trigger["workflowReadCommitID"]]
      ).int == 1,
      "automation_integrity", "The dispatch lost its actual workflow read coordinate.")
    let workflow = try DefinitionWorkflow(DefinitionDescriptor(retained.workflow.content))
    try require(
      authority.data["allowAI"] == .bool(true)
        || !workflow.steps.contains { $0.kind == "interpret" },
      "automation_integrity", "The condition workflow lost its local-AI permission.")
    for parent in [authority.id, dispatch.id, consumer["source_id"]!.text] {
      try automationLineage(invocation.id, parent)
    }
    try automationLineage(dispatch.id, authority.id)
    try automationLineage(dispatch.id, consumer["source_id"]!.text)
  }
}
