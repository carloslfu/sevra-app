import Foundation
import SevraCore

extension NativeAppCheck {
  /// Explain the submitted operation and a common form-test ordering mistake.
  /// This never changes the test sequence, candidate code or asserted values.
  package static func interactionHint(
    steps: [Value], index: Int, actions: [String: Value]
  ) throws -> String {
    let step = steps[index]
    if step["kind"] == .string("run_action") {
      let call =
        step["action"].text + ", inputs: "
        + String(String.UnicodeScalarView(try step["inputs"].json().unicodeScalars.prefix(1000)))
      if step["error"] == .null, step["reject"] == .null {
        return "\nFailed successful action: " + call
          + ". Decide this from the original rules and starting state. If the input should be refused, add \"reject\":true to this exact run_action step and remove any assertion that it saved a new row. Keep a separate successful call with valid inputs. If the input should succeed, keep the success assertion and fix the handler or invalid setup. Do not change a business rule to pass a test."
      }
      if step["error"].string != nil {
        return "\nFailed refusal test: " + call
          + ". Check that these inputs and the state after earlier steps actually isolate the intended rule. For an unknown record use a key with no matching business row; for a conflict use known records in a conflicting state. When exact wording is not required, use reject:true with valid typed inputs and keep a separate valid success case. Do not change correct validation to match invented wording."
      }
    }
    guard ["expect_row", "expect_rows"].contains(step["kind"].text),
      let click = steps.prefix(index).lastIndex(where: { $0["kind"] == .string("click") }),
      !steps[(click + 1)..<index].contains(where: { $0["kind"] == .string("run_action") }),
      let action = actions.values.first(where: { $0["title"] == steps[click]["target"] })
    else { return "" }
    let title = action["title"].text
    let labels = Set(
      action["inputs"].object.map { key, field in
        title + ": " + (field["title"].string ?? key)
      })
    guard
      steps[(click + 1)..<index].contains(where: {
        ["change", "select"].contains($0["kind"].text) && labels.contains($0["target"].text)
      })
    else { return "" }
    return "\nThe test edited fields after clicking " + title
      + " and then asserted a saved row without submitting again. For an ActionForm, enter fields first and then click its submit button; that button submits rather than opens the form. A named run_action can test the same handler directly. Preserve the requested business behavior and exact saved-value assertion."
  }

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
