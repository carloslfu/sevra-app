import Foundation

/// A narrow backstop for quantitative comparison language, not a semantic proof
/// of arbitrary prose. The ordinary word "difference" also describes concepts
/// and interface controls; it must not by itself demand a dummy calculation.
package enum CalculationRequirement {
  package static func hasComparisonClaim(_ text: String) -> Bool {
    let numericDifference =
      #"\bdifferences?\b[^.!?\n]{0,80}?(?:\b(?:is|are|of|equals?)\b[ \t]*|[:=][ \t]*)[−+\-]?(?:\d|\.\d)"#
    return text.range(
      of: #"(?i)\bcheaper\b|\bmore expensive\b|\blower cost\b|\bhigher cost\b|"#
        + numericDifference,
      options: .regularExpression) != nil
  }
}
