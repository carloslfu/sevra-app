import Foundation
import SevraCore

extension NativeAppReview {
  /// Interpret numeric rules independently, then derive typed counterexamples.
  /// No numeric test value or expected result comes from generated app code.
  package static func numberProbes(role: Value, input: Value) throws -> [(String, Value)] {
    try require(
      Set(role.object.keys) == ["kind", "whole", "minimum", "maximum", "nonzero"]
        && role["kind"] == .string("number")
        && [.bool(true), .bool(false)].contains(role["whole"])
        && [.bool(true), .bool(false)].contains(role["nonzero"]),
      "app_review_inputs",
      "Numeric roles need kind:number, whole:boolean, minimum:number or null, maximum:number or null, and nonzero:boolean. Derive them from the request, not the implementation."
    )
    func number(_ value: Value) throws -> Decimal {
      if case .number(let n) = value, n.isFinite,
        let d = Decimal(string: String(n), locale: Locale(identifier: "en_US_POSIX")), !d.isNaN
      {
        return d
      }
      if case .string(let text) = value { return try Numbers.decimal(text) }
      throw SevraError("app_review_inputs", "Numeric rules require finite numeric values.")
    }
    func bound(_ key: String) throws -> Decimal? {
      if role[key] == .null { return nil }
      guard case .number = role[key] else {
        throw SevraError("app_review_inputs", "Use a number or null for " + key)
      }
      return try number(role[key])
    }
    func rounded(_ value: Decimal, _ mode: Decimal.RoundingMode) -> Decimal {
      var value = value
      var result = Decimal()
      NSDecimalRound(&result, &value, 0, mode)
      return result
    }
    func isWhole(_ value: Decimal) -> Bool { rounded(value, .plain) == value }
    let base = try number(input)
    let minimum = try bound("minimum")
    let maximum = try bound("maximum")
    func inRange(_ value: Decimal) -> Bool {
      !value.isNaN && (minimum.map { value >= $0 } ?? true) && (maximum.map { value <= $0 } ?? true)
    }
    try require(
      inRange(base) && (role["whole"] != .bool(true) || isWhole(base))
        && (role["nonzero"] != .bool(true) || base != 0),
      "app_review_inputs",
      "The successful numeric test must satisfy the declared requested rules. Use a valid base call; the host derives invalid variants."
    )
    var values: [(String, Decimal)] = []
    if role["whole"] == .bool(true) {
      var candidates = [base + Decimal(string: "0.5")!, base - Decimal(string: "0.5")!]
      // A half-step can be outside a narrow range. Its midpoint with a distinct
      // endpoint still exercises integer validation without violating the range.
      if let minimum, minimum < base { candidates.append(base / 2 + minimum / 2) }
      if let maximum, maximum > base { candidates.append(base / 2 + maximum / 2) }
      if let fraction =
        candidates
        .first(where: { inRange($0) && !isWhole($0) && (role["nonzero"] != .bool(true) || $0 != 0) }
        )
      {
        values.append(("whole", fraction))
      } else {
        try require(
          minimum == base && maximum == base, "app_review_inputs",
          "Cannot derive a representable fractional probe within the requested range. Use a smaller valid base value."
        )
      }
    }
    if let minimum {
      var value = role["whole"] == .bool(true) ? rounded(minimum, .down) : minimum - 1
      if value == minimum { value -= 1 }
      if role["nonzero"] == .bool(true) && value == 0 { value -= 1 }
      try require(
        !value.isNaN && value < minimum, "app_review_inputs",
        "Minimum probe exceeded decimal precision.")
      values.append(("minimum", value))
    }
    if let maximum {
      var value = role["whole"] == .bool(true) ? rounded(maximum, .up) : maximum + 1
      if value == maximum { value += 1 }
      if role["nonzero"] == .bool(true) && value == 0 { value += 1 }
      try require(
        !value.isNaN && value > maximum, "app_review_inputs",
        "Maximum probe exceeded decimal precision.")
      values.append(("maximum", value))
    }
    if role["nonzero"] == .bool(true) { values.append(("nonzero", 0)) }
    return try values.map { rule, value in
      try require(!value.isNaN, "app_review_inputs", "Numeric probe exceeded decimal bounds.")
      if case .string = input { return (rule, .string(Numbers.string(value))) }
      let typed = Value.number(NSDecimalNumber(decimal: value).doubleValue)
      try require(
        try number(typed) == value, "app_review_inputs",
        "Numeric probe cannot be represented exactly by this input type.")
      return (rule, typed)
    }
  }
}
