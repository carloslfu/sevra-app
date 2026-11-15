import Foundation
import SevraCore

extension NativeAppCheck {
  /// Shared setup diagnostics, not business validation. Explicit SDK-error tests
  /// may deliberately supply these invalid inputs; callers retain that distinction.
  package static func inputSetupErrors(_ step: Value, fields: [String: Value]) -> [String] {
    let inputs = step["inputs"] == .null ? Value.object([:]) : step["inputs"]
    guard case .object = inputs else { return ["Action test inputs must be an object."] }
    var errors: [String] = []
    if !Set(inputs.object.keys).isSubset(of: Set(fields.keys)) {
      errors.append("Action test inputs must use the declared field IDs.")
    }
    for (key, field) in fields.sorted(by: { $0.key < $1.key }) {
      let value = inputs[key]
      if inputs.object[key] == nil && field["required"] == .bool(false) { continue }
      let valid: Bool
      switch field["valueType"].text {
      case "boolean": if case .bool = value { valid = true } else { valid = false }
      case "number":
        if case .number(let number) = value { valid = number.isFinite } else { valid = false }
      default: valid = value.string != nil
      }
      if !valid {
        errors.append(
          "Invalid counterexample setup: input \(key) requires JSON \(field["valueType"].text). Use the declared input types for a successful action test, or supply error to assert rejection. Decimal inputs are strings, for example \"5\"."
        )
      }
    }
    return errors
  }

  /// Explain trailing fractional zeros without accepting a different string or
  /// rounding through floating point. Leading zeros, signs and all other digits
  /// remain significant; this hint never changes assertion matching.
  package static func decimalSpelling(_ value: String) -> String? {
    var text = value
    guard text.utf8.count <= 256,
      text.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?$"#, options: .regularExpression)
        == text.startIndex..<text.endIndex
    else { return nil }
    if text.contains(".") {
      while text.last == "0" { text.removeLast() }
      if text.last == "." { text.removeLast() }
    }
    return text
  }

  package static func decimalTextHint(_ values: [String: Value], rows: [Value]) throws -> String {
    let expected = values.mapValues { $0.string.flatMap(decimalSpelling) }
    guard
      let row = rows.first(where: { row in
        values.allSatisfy { key, value in
          let actual = row["values"][key]
          if actual == value { return true }
          guard let a = actual.string.flatMap(decimalSpelling), let b = expected[key] ?? nil else {
            return false
          }
          return a == b
        }
      })
    else { return "" }
    let differences = try values.keys.sorted().compactMap { key -> String? in
      let actual = row["values"][key]
      guard actual != values[key]! else { return nil }
      return "Column \(key): expected \(try values[key]!.json()), stored \(try actual.json())."
    }.joined(separator: " ")
    guard !differences.isEmpty else { return "" }
    return " Decimal TEXT spelling differs; the exact assertion still failed. "
      + String(differences.prefix(1500))
      + " These strings differ only in trailing fractional zeros. Do not invent decimal padding when the request only specifies a numeric value. Preserve explicitly requested text formatting; a real formatting requirement still needs its exact assertion."
  }
}
