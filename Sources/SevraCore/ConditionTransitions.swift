import CryptoKit
import Foundation

/// Pure supplied-observation preview. It cannot assert business-event coverage,
/// save occurrences, restore device authority or execute a workflow.
public struct NativeConditionRule: Sendable {
  public let definition: Value
  private let comparison: String
  private let threshold: Decimal

  public init(_ value: Value) throws {
    try require(
      Set(value.object.keys) == ["policy", "scope", "operator", "threshold"]
        && value["policy"] == .string("native-condition-v1"),
      "condition", "Use an exact native-condition-v1 rule with scope, operator and threshold.")
    try Self.identity(value["scope"], label: "condition scope")
    let operation = value["operator"].text
    try require(
      ["<", "<=", ">", ">=", "=", "<>"].contains(operation), "condition",
      "Choose <, <=, >, >=, = or <> for a numeric condition.")
    let number = try Self.decimal(value["threshold"])
    comparison = operation
    threshold = number.1
    definition = .object([
      "policy": .string("native-condition-v1"), "scope": value["scope"],
      "operator": .string(operation), "threshold": .string(number.0),
    ])
  }

  public func preview(_ observations: Value, cancellation: Cancellation = .init()) throws -> Value {
    try cancellation.check()
    guard case .array(let values) = observations else {
      throw SevraError("condition", "Supply an ordered array of observations.")
    }
    try require(values.count <= 100, "condition_limit", "Preview at most 100 observations.")
    let inputs = try values.map { value -> Observation in
      try cancellation.check()
      return try Observation(value)
    }
    // Validate shapes and field sizes before encoding any caller-built Value.
    try require(
      try observations.json().utf8.count <= 65_536, "condition_limit",
      "Observation input is limited to 64 KiB.")
    var seen: [String: Value] = [:]
    var rows: [Value] = []
    var transitions: [Value] = []
    var lastCertain: Bool?
    var lastCertainID: String?
    var gap = false
    for input in inputs {
      try cancellation.check()
      let truth = try input.number.map { try Numbers.binary($0, threshold, op: comparison) != 0 }
      var row: [String: Value] = [
        "id": .string(input.id), "truth": truth.map(Value.bool) ?? .null,
        "occurrenceID": .null, "coverageGap": .bool(false),
      ]
      if let previous = seen[input.id] {
        try require(
          previous == input.content, "condition_identity",
          "An observation ID was reused with different content.")
        row["disposition"] = .string("duplicate")
      } else {
        seen[input.id] = input.content
        if let truth {
          row["coverageGap"] = .bool(gap)
          if lastCertain == nil {
            row["disposition"] = .string("baseline")
          } else if lastCertain == false && truth {
            let identity: Value = .object([
              "rule": definition, "observationID": .string(input.id),
            ])
            let bytes = Data(try identity.json().utf8)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            row["disposition"] = .string("transition")
            row["occurrenceID"] = .string("condition:" + hash)
            row["previousCertainObservationID"] = lastCertainID.map(Value.string) ?? .null
            transitions.append(.object(row))
          } else {
            row["disposition"] = .string(lastCertain == true && !truth ? "reset" : "unchanged")
          }
          lastCertain = truth
          lastCertainID = input.id
          gap = false
        } else {
          row["disposition"] = .string("unknown")
          row["reason"] = input.content["reason"]
          gap = true
        }
      }
      rows.append(.object(row))
    }
    return .object([
      "rule": definition, "observations": .array(rows), "transitions": .array(transitions),
      "count": .number(Double(rows.count)), "uniqueCount": .number(Double(seen.count)),
      "transitionCount": .number(Double(transitions.count)),
      "lastCertainTruth": lastCertain.map(Value.bool) ?? .null,
      "lastCertainObservationID": lastCertainID.map(Value.string) ?? .null,
      "unresolvedGap": .bool(gap), "scope": .string("fixture-observations"),
      "businessEvidence": .bool(false), "execution": .string("inert"), "enabled": .bool(false),
    ])
  }

  func truth(_ value: String) throws -> Bool {
    try Numbers.binary(Numbers.decimal(value), threshold, op: comparison) != 0
  }

  private struct Observation {
    let id: String
    let content: Value
    let number: Decimal?
    init(_ value: Value) throws {
      let unknown = value["value"] == .null
      try require(
        Set(value.object.keys) == (unknown ? ["id", "value", "reason"] : ["id", "value"]),
        "condition", "Each observation needs id and value; unknown values also need a reason.")
      try NativeConditionRule.identity(value["id"], label: "observation ID")
      id = value["id"].text
      if unknown {
        guard let reason = value["reason"].string else {
          throw SevraError("condition", "An unknown value needs a text reason.")
        }
        try require(
          !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reason.utf8.count <= 512,
          "condition_limit", "An unknown reason needs 1 to 512 UTF-8 bytes.")
        content = value
        number = nil
      } else {
        let parsed = try NativeConditionRule.decimal(value["value"])
        content = .object(["id": value["id"], "value": .string(parsed.0)])
        number = parsed.1
      }
    }
  }

  private static func identity(_ value: Value, label: String) throws {
    guard let text = value.string else {
      throw SevraError("condition", "Use a text " + label + ".")
    }
    try require(
      !text.isEmpty && text.utf8.count <= 256
        && text.trimmingCharacters(in: .whitespacesAndNewlines) == text
        && !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
      "condition_limit",
      "Use a nonempty " + label + " up to 256 UTF-8 bytes without control characters.")
  }

  private static func decimal(_ value: Value) throws -> (String, Decimal) {
    guard let raw = value.string else {
      throw SevraError("condition", "Use a decimal string, not a JSON number.")
    }
    try require(
      raw.utf8.count <= 128, "condition_limit", "A decimal is limited to 128 UTF-8 bytes.")
    let number = try Numbers.decimal(raw)
    // Keep canonical output in plain decimal notation, including extreme values.
    let unsigned = raw.first == "-" || raw.first == "+" ? String(raw.dropFirst()) : raw
    let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
    let integer = String(parts[0].drop(while: { $0 == "0" }))
    let fraction =
      parts.count == 2 ? String(parts[1].reversed().drop(while: { $0 == "0" }).reversed()) : ""
    let magnitude = (integer.isEmpty ? "0" : integer) + (fraction.isEmpty ? "" : "." + fraction)
    let canonical = raw.first == "-" && magnitude != "0" ? "-" + magnitude : magnitude
    return (canonical, number)
  }
}
