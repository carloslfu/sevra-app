import Foundation

/// Constant-period payments. The caller supplies numeric operands after ordinary
/// worksheet blank/error coercion. No model-generated arithmetic or business constants.
enum SheetFinancial {
  static func payment(_ values: [Decimal]) -> SheetValue {
    guard (3...5).contains(values.count) else { return .error("#VALUE!") }
    let rate = values[0], periods = values[1], present = values[2]
    let future = values.count > 3 ? values[3] : 0
    let due = values.count > 4 && values[4] != 0
    guard periods != 0, rate >= -1 else { return .error("#NUM!") }
    if rate == 0 {
      // Keep zero-interest amounts decimal, including signed half-cent ties.
      guard let total = try? Numbers.binary(present, future, op: "+"),
        let payment = try? Numbers.binary(-total, periods, op: "/")
      else { return .error("#NUM!") }
      return .number(payment)
    }
    let r = NSDecimalNumber(decimal: rate).doubleValue
    let n = NSDecimalNumber(decimal: periods).doubleValue
    let pv = NSDecimalNumber(decimal: present).doubleValue
    let fv = NSDecimalNumber(decimal: future).doubleValue
    // Decimal addition avoids rounding a rate just above -1 to exactly -1.
    guard let base = try? Numbers.binary(1, rate, op: "+") else { return .error("#NUM!") }
    let baseValue = NSDecimalNumber(decimal: base).doubleValue
    let timing = due ? baseValue : 1
    guard timing != 0 else { return .error("#NUM!") }
    let result: Double
    if rate == -1 {
      guard n > 0 else { return .error("#NUM!") }
      result = -fv
    } else {
      // log1p/expm1 preserve tiny rates. Work on the smaller exponential so
      // normal payments do not lose precision through subtracting nearly equal values.
      let exponent = n * (rate < -0.5 ? log(baseValue) : log1p(r))
      guard exponent.isFinite, exponent <= log(Double.greatestFiniteMagnitude) else {
        return .error("#NUM!")
      }
      if exponent > 0 {
        result = (pv + fv * exp(-exponent)) * r / expm1(-exponent) / timing
      } else {
        result = (pv * exp(exponent) + fv) * r / -expm1(exponent) / timing
      }
    }
    guard result.isFinite, let decimal = SheetFormula.number(String(result)),
      let normalized = SheetFormula.number(SheetFormula.text(decimal))
    else { return .error("#NUM!") }
    return .number(normalized)
  }
}
