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
      let settled = mode == "saved"
        || (["real-action-input", "missing-contract"].contains(mode) && shape == "inputs-as-arguments")
      try expectEqual(confirmations.hasUnresolvedFailure, !settled)
      try expectEqual(confirmations.evidence.array.count, 2)
      if mode == "refused" {
        try expectEqual(confirmations.rendered, "Couldn’t finish that action. Rate is locked")
      }
    }
  }
  print("PASS misplaced action recovery preserves app, action, version, business values and real refusals")
}
