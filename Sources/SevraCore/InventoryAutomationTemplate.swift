import Foundation

extension Workbook {
  /// A read-only starter. Runtime cursors, candidates and device authority are
  /// deliberately absent; the canonical definition validator owns its meaning.
  func inventoryAutomationTemplate(_ arguments: Value) throws -> Value {
    try require(
      Set(arguments.object.keys) == ["workflowID", "arguments", "subject", "operator", "threshold"]
        && arguments["workflowID"].string != nil && arguments["subject"].string != nil,
      "automation_template",
      "Supply an exact workflow, typed arguments and explicit inventory rule.")
    let workflow = try applicationDefinition(arguments["workflowID"].text)
    try require(
      workflow.id == arguments["workflowID"].text && workflow.kind == "workflow"
        && applicationDefinition(workflow.logicalID).id == workflow.id,
      "automation_binding", "Inspect the current exact saved workflow before using its starter.")
    let rule = try NativeConditionRule(
      .object([
        "policy": .string("native-condition-v1"),
        "scope": .string("inventory:" + arguments["subject"].text),
        "operator": arguments["operator"], "threshold": arguments["threshold"],
      ])
    ).definition
    let content: Value = .object([
      "kind": .string("automation"), "title": .string("When stock changes: " + workflow.title),
      "description": .string(
        "Prepare this exact workflow when the inventory rule crosses its threshold."),
      "parameters": .array([]),
      "payload": .object([
        "policy": .string("inventory-condition-drafts-v1"),
        "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow.id)]),
        "arguments": arguments["arguments"],
        "condition": .object(["subject": arguments["subject"], "rule": rule]),
      ]),
    ])
    _ = try validateAutomationDefinition(DefinitionDescriptor(content))
    return content
  }
}
