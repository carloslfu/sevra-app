import Foundation

extension Workbook {
  /// A read-only starter. Runtime cursors, candidates and device authority are
  /// deliberately absent; the canonical definition validator owns its meaning.
  /// With `alert` in place of a workflow, the rule drafts that alert for review when it fires.
  func inventoryAutomationTemplate(_ arguments: Value) throws -> Value {
    if arguments.object["alert"] != nil { return try stockAlertTemplate(arguments) }
    try require(
      Set(arguments.object.keys) == ["workflowID", "arguments", "subject", "operator", "threshold"]
        && arguments["workflowID"].string != nil && arguments["subject"].string != nil,
      "automation_template",
      "Supply an exact workflow, typed arguments and explicit inventory rule, or alert text in place of the workflow.")
    let workflow = try applicationDefinition(arguments["workflowID"].text)
    try require(
      workflow.id == arguments["workflowID"].text && workflow.kind == "workflow"
        && applicationDefinition(workflow.logicalID).id == workflow.id,
      "automation_binding", "Inspect the current exact saved workflow before using its starter.")
    let content: Value = .object([
      "kind": .string("automation"), "title": .string("When stock changes: " + workflow.title),
      "description": .string(
        "Prepare this exact workflow when the inventory rule crosses its threshold."),
      "parameters": .array([]),
      "payload": .object([
        "policy": .string("inventory-condition-drafts-v1"),
        "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow.id)]),
        "arguments": arguments["arguments"],
        "condition": try stockCondition(arguments),
      ]),
    ])
    _ = try validateAutomationDefinition(DefinitionDescriptor(content))
    return content
  }

  private func stockCondition(_ arguments: Value) throws -> Value {
    let rule = try NativeConditionRule(
      .object([
        "policy": .string("native-condition-v1"),
        "scope": .string("inventory:" + arguments["subject"].text),
        "operator": arguments["operator"], "threshold": arguments["threshold"],
      ])
    ).definition
    return .object(["subject": arguments["subject"], "rule": rule])
  }

  /// The starter for a rule with no workflow of the person's to run. It names the alert only;
  /// saving it binds the rule to the shared alert workflow (`stockAlertAutomation`).
  private func stockAlertTemplate(_ arguments: Value) throws -> Value {
    let keys = Set(arguments.object.keys)
    try require(
      keys.isSuperset(of: ["alert", "subject", "operator", "threshold"])
        && keys.isSubset(of: ["alert", "subject", "operator", "threshold", "workflowID", "arguments"])
        && (arguments.object["workflowID"] == nil || arguments["workflowID"] == .string(""))
        && (arguments.object["arguments"] == nil || arguments["arguments"] == .object([:]))
        && arguments["subject"].string != nil && arguments["alert"].string != nil,
      "automation_template",
      "An alert rule takes alert, subject, operator and threshold, with no workflow.")
    let alert = arguments["alert"].text.trimmingCharacters(in: .whitespacesAndNewlines)
    try require(
      !alert.isEmpty && alert.utf8.count <= 2_000, "automation_template",
      "Write the alert as text of at most 2,000 bytes.")
    let subject = arguments["subject"].text
    _ = try stockAlertEvidence(subject)
    return .object([
      "kind": .string("automation"), "title": .string("Stock alert: " + subject),
      "description": .string(
        "Draft this alert for review when the inventory rule crosses its threshold."),
      "parameters": .array([]),
      "payload": .object([
        "policy": .string("inventory-condition-drafts-v1"), "alert": .string(alert),
        "condition": try stockCondition(arguments),
      ]),
    ])
  }

  /// The item that sets the subject's stock. The alert cites it, since an alert document needs
  /// business evidence and the rule watches exactly that stock.
  func stockAlertEvidence(_ subject: String) throws -> Item {
    let subject = subject.precomposedStringWithCanonicalMapping
    guard
      let source = try db.execute(
        "SELECT source_id FROM bases WHERE subject=?", [.string(subject)], maxRows: 1
      ).first?["source_id"]?.string
    else {
      throw SevraError(
        "unknown_basis",
        "The workbook keeps no stock for \(subject). A rule watches an item whose stock the workbook keeps, named as the stock table names it."
      )
    }
    let evidence = try item(source)
    try require(
      evidence.isBusinessEvidence, "unknown_basis",
      "The stock of \(subject) has no business evidence an alert can cite.")
    return evidence
  }

  public static let stockAlertActionID = "5e7a1e47-a1e7-8000-8000-000000000001"
  public static let stockAlertWorkflowID = "5e7a1e47-a1e7-8000-8000-000000000002"

  /// Turns a saved alert starter into a rule bound to the shared alert workflow. The first alert
  /// rule saves that workflow and its action; later ones reuse them. Removing a rule leaves them.
  func stockAlertAutomation(
    _ content: Value, token: String, requestRunID: String?, requestSourceID: String?,
    cancellation: Cancellation
  ) throws -> Value {
    let payload = content["payload"]
    let subject = payload["condition"]["subject"].text
    let evidence = try synchronized { try stockAlertEvidence(subject) }
    func current(_ logicalID: String, kind: String) throws -> ApplicationDefinition? {
      guard let saved = try? applicationDefinition(logicalID) else { return nil }
      try require(
        saved.kind == kind, "definition_kind",
        "The workbook's shared stock alert definition is not a \(kind).")
      return saved
    }
    func save(_ logicalID: String, _ content: Value, base: ApplicationDefinition?, _ suffix: String)
      throws -> ApplicationDefinition
    {
      try saveApplicationDefinition(
        logicalID: logicalID, content: content, expectedDefinitionID: base?.id,
        token: token + "-" + suffix, requestRunID: requestRunID, requestSourceID: requestSourceID,
        cancellation: cancellation)
    }
    var action = try current(Self.stockAlertActionID, kind: "action")
    if action?.content["payload"] != ActionRegistry.alertDefinition()["payload"] {
      action = try save(
        Self.stockAlertActionID, ActionRegistry.alertDefinition(), base: action, "alert-action")
    }
    var wanted = try synchronized {
      try db.readTransaction { try workflowTemplate(action!.id) }
    }.object
    wanted["title"] = .string("Stock alert")
    wanted["description"] = .string(
      "Draft an alert for review. Rules that alert when stock crosses a level run it.")
    var workflow = try current(Self.stockAlertWorkflowID, kind: "workflow")
    if workflow?.content["payload"] != wanted["payload"] {
      workflow = try save(Self.stockAlertWorkflowID, .object(wanted), base: workflow, "alert-workflow")
    }
    var bound = content.object
    bound["payload"] = .object([
      "policy": payload["policy"],
      "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow!.id)]),
      "arguments": .object([
        "title": .string("Stock alert: " + subject), "body": payload["alert"],
        "evidence": .string(evidence.id),
        "meaning": .string(Item.meanings.contains(evidence.meaning) ? evidence.meaning : "estimate"),
        "scenario": .string(evidence.scenario),
      ]),
      "condition": payload["condition"],
    ])
    _ = try synchronized {
      try db.readTransaction {
        try validateAutomationDefinition(DefinitionDescriptor(.object(bound)))
      }
    }
    return .object(bound)
  }
}
