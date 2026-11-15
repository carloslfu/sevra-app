import Foundation
import SevraAppUI

@testable import SevraCore

/// Reuse the actual generated action/input identities from successful model calls.
/// Change only test inputs; never inspect or modify the generated source.
@MainActor func checkBusinessValidation(
  probes: [Value], calls: [Int: Value], session: NativeAppSession,
  snapshot: () throws -> Value, versions: () throws -> [[String]]
) async throws -> [Value] {
  var states: [Value] = []
  for (group, probe) in probes.enumerated() {
    let call = try expectValue(calls[probe["journey"].int ?? -1])
    let original = call["inputs"].object
    func field(_ value: String) throws -> String {
      let matches = original.filter { Workbook.sameExcelResult($0.value.text, value) }
      try require(
        matches.count == 1, "validation_probe", "Ambiguous original action input: " + value)
      return matches.first!.key
    }
    func replaced(_ args: Value, field: String, value: String) throws -> Value {
      var inputs = args["inputs"].object
      if case .number = original[field] {
        guard let number = Double(value), number.isFinite else {
          throw SevraError("validation_probe", "Invalid numeric probe input.")
        }
        inputs[field] = .number(number)
      } else {
        inputs[field] = .string(value)
      }
      var result = args.object
      result["inputs"] = .object(inputs)
      return .object(result)
    }
    var control = call
    let reference = try probe["reference"].string.map(field)
    if let reference {
      control = try replaced(control, field: reference, value: "CONTROL-\(group)")
    }
    for (original, value) in probe["valid"].object {
      control = try replaced(control, field: field(original), value: value.text)
    }
    let before = try snapshot()
    let accepted = try await session.converse("run", arguments: control)
    try require(
      accepted["outcome"] == .string("completed") && accepted["changes"].array.count == 1,
      "validation_probe",
      "A valid control failed before testing its invalid variants: " + control.json())
    let controlState = try snapshot()
    states.append(
      .object(["step": .string("validation-control-\(group)"), "state": controlState]))
    let undo = try await session.converse("undo")
    try require(undo["outcome"] == .string("completed"), "validation_probe", "Control Undo failed.")
    try expectEqual(try snapshot(), before)
    states.append(.object(["step": .string("validation-undo-\(group)"), "state": try snapshot()]))
    for (rule, invalid) in probe["invalid"].array.enumerated() {
      let key = try field(invalid["original"].text)
      for (variant, value) in invalid["values"].array.enumerated() {
        var args = try replaced(control, field: key, value: value.text)
        if let reference, key != reference {
          args = try replaced(args, field: reference, value: "REFUSE-\(group)-\(rule)-\(variant)")
        }
        // A prior refusal may change transient state without committing data.
        // Restart before each variant, then prove correction works afterward.
        _ = try await session.converse("restart")
        let beforeVersions = try versions()
        let result = try await session.converse("run", arguments: args)
        try require(
          result["outcome"] == .string("failed") && result["changes"].array.isEmpty,
          "validation_probe", "The generated action accepted an invalid input: " + args.json())
        try expectEqual(try snapshot(), before)
        try expectEqual(try versions(), beforeVersions)
        let recovered = try await session.converse("run", arguments: control)
        try require(
          recovered["outcome"] == .string("completed") && recovered["changes"].array.count == 1,
          "validation_probe", "A valid correction failed after a rejected input: " + args.json())
        try expectEqual(try snapshot(), controlState)
        let recoveryUndo = try await session.converse("undo")
        try require(
          recoveryUndo["outcome"] == .string("completed"), "validation_probe",
          "Recovery Undo failed.")
        try expectEqual(try snapshot(), before)
      }
    }
  }
  return states
}
