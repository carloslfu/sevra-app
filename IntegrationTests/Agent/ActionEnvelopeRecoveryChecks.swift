import Foundation
import SevraAI
import SevraCore

func checkMisplacedActionRecovery() throws {
  let inputs: Value = .object(["employee": .string("E2"), "hourlyCost": .string("35")])
  let correct: Value = .object([
    "id": .string("jobs-app"), "expectedVersion": .number(1),
    "action": .string("updateHourlyCost"), "inputs": inputs,
  ])
  let contract: Value = .object([
    "employee": .object(["type": .string("text"), "valueType": .string("string")]),
    "hourlyCost": .object(["type": .string("decimal"), "valueType": .string("string")]),
  ])
  for shape in ["action-in-inputs", "inputs-as-arguments"] {
    for mode in [
      "saved", "refused", "other-app", "other-action", "other-version", "other-input",
      "real-action-input", "missing-contract",
    ] {
      var malformed = correct.object
      if shape == "action-in-inputs" {
        malformed.removeValue(forKey: "action")
        malformed["inputs"] = .object(inputs.object.merging(["action": correct["action"]]) { $1 })
      } else {
        malformed.removeValue(forKey: "inputs")
        malformed["arguments"] = inputs
      }
      var confirmations = ActionConfirmations()
      confirmations.recordFailure(
        tool: "workspace_action",
        arguments: .object(["action": .string("app.run"), "arguments": .object(malformed)]),
        result: .object(["error": .string("Malformed envelope")]), receiptID: "format")
      var repaired = correct.object
      if mode == "other-app" { repaired["id"] = .string("other-app") }
      if mode == "other-action" { repaired["action"] = .string("otherAction") }
      if mode == "other-version" { repaired["expectedVersion"] = .number(2) }
      if mode == "other-input" {
        repaired["inputs"] = .object(inputs.object.merging(["hourlyCost": .string("99")]) { $1 })
      }
      var fields = contract.object
      if mode == "real-action-input" {
        fields["action"] = .object(["type": .string("text"), "required": .bool(false)])
      }
      let args: Value = .object(["action": .string("app.run"), "arguments": .object(repaired)])
      let result: Value = .object([
        "invocationInputContract": mode == "missing-contract" ? .null : .object(fields),
        "error": mode == "refused" ? .string("Rate is locked") : .null,
        "outcome": .string(mode == "refused" ? "failed" : "completed"),
      ])
      if mode == "refused" {
        confirmations.recordFailure(
          tool: "workspace_action", arguments: args, result: result, receiptID: "actual")
      } else {
        confirmations.record(
          tool: "workspace_action", arguments: args, result: result, receiptID: "actual")
      }
      let settled =
        mode == "saved"
        || (["real-action-input", "missing-contract"].contains(mode)
          && shape == "inputs-as-arguments")
      try expectEqual(confirmations.hasUnresolvedFailure, !settled)
      try expectEqual(confirmations.evidence.array.count, 2)
      if mode == "refused" {
        try expectEqual(confirmations.rendered, "Couldn’t finish that action. Rate is locked")
      }
    }
  }
  try checkDuplicatedEnvelopeSelectors()
  print(
    "PASS misplaced action recovery preserves app, action, version, business values and real refusals"
  )
}

private func checkDuplicatedEnvelopeSelectors() throws {
  let inputs: [String: Value] = [
    "employee": .string("E2"), "job": .string("J1"), "hours": .string("3.5"),
    "reference": .string("TEST-T1"),
  ]
  let call: [String: Value] = [
    "id": .string("jobs-app"), "expectedVersion": .number(1), "action": .string("logTime"),
  ]
  for mode in [
    "corrected", "handler-refused", "different-id", "business-id-dropped", "business-id-kept",
    "unproved", "changed-hours", "changed-version", "all-selectors",
  ] {
    var nested = inputs
    nested["id"] = mode == "different-id" ? .string("another-id") : call["id"]
    if mode == "all-selectors" {
      nested["action"] = call["action"]
      nested["expectedVersion"] = call["expectedVersion"]
    }
    let malformed = Value.object(call.merging(["arguments": .object(nested)]) { _, new in new })
    var repaired = call
    var selected = inputs
    if mode == "changed-hours" { selected["hours"] = .string("4") }
    if mode == "changed-version" { repaired["expectedVersion"] = .number(2) }
    if mode == "business-id-kept" { selected["id"] = nested["id"] }
    repaired["inputs"] = .object(selected)
    let field: Value = .object(["type": .string("text"), "valueType": .string("string")])
    var contract = inputs.mapValues { _ in field }
    if mode.hasPrefix("business-id") { contract["id"] = field }
    let result: Value = .object([
      "invocationInputContract": mode == "unproved" ? .null : .object(contract),
      "outcome": .string(mode == "handler-refused" ? "failed" : "completed"),
      "error": mode == "handler-refused" ? .string("Job is closed") : .null,
    ])
    var confirmations = ActionConfirmations()
    confirmations.recordFailure(
      tool: "workspace_action",
      arguments: .object(["action": .string("app.run"), "arguments": malformed]),
      result: .object(["error": .string("Missing fields: inputs")]), receiptID: "format")
    let corrected: Value = .object([
      "action": .string("app.run"), "arguments": .object(repaired),
    ])
    if mode == "handler-refused" {
      confirmations.recordFailure(
        tool: "workspace_action", arguments: corrected, result: result, receiptID: "handler")
    } else {
      confirmations.record(
        tool: "workspace_action", arguments: corrected, result: result, receiptID: "handler")
    }
    let settled = ["corrected", "all-selectors", "business-id-kept"].contains(mode)
    try expectEqual(confirmations.hasUnresolvedFailure, !settled)
    try expectEqual(confirmations.evidence.array.count, 2)
    if mode == "handler-refused" {
      try expectEqual(confirmations.rendered, "Couldn’t finish that action. Job is closed")
    } else {
      try expectEqual(confirmations.rendered?.contains("Missing fields") ?? false, !settled)
    }
  }
}

/// An export refused for a misnamed field, then sent right, answers with what really happened:
/// a cancelled save panel says nothing was exported, and a refusal for another table stays.
func checkMisnamedHostActionRecovery() throws {
  let note = "The save panel was closed, so nothing was exported."
  for mode in ["cancelled", "saved", "other-table"] {
    var confirmations = ActionConfirmations()
    confirmations.recordFailure(
      tool: "workspace_action",
      arguments: .object([
        "action": .string("file.export_table"),
        "arguments": .object(["tableID": .string("table-1")]),
      ]),
      result: .object(["error": .string("Missing fields: id. Unexpected fields: tableID.")]),
      receiptID: "misnamed")
    confirmations.record(
      tool: "workspace_action",
      arguments: .object([
        "action": .string("file.export_table"),
        "arguments": .object(["id": .string(mode == "other-table" ? "table-2" : "table-1")]),
      ]),
      result: mode == "saved"
        ? .object(["status": .string("saved"), "path": .string("/tmp/Table.csv")])
        : .object(["status": .string("cancelled"), "note": .string(note)]),
      receiptID: "sent")
    let rendered = confirmations.rendered
    switch mode {
    case "cancelled": try expectEqual(rendered, note)
    // A saved export is the model's to describe from its receipt.
    case "saved": try expectEqual(rendered, nil)
    default:
      try expectEqual(rendered?.contains("Unexpected fields: tableID."), true)
      try expectEqual(rendered?.contains(note), true)
    }
  }
}
