import Foundation

/// A summary after a save says what was saved and what was chosen. The host's receipt proves
/// that something was saved, not that its content is faithful, so a claim that the content was
/// kept perfectly, verbatim or verified is the model's word alone and is sent back. The patterns
/// need such a claim about content: "Perfect!" as an opener, or "placed exactly where you
/// asked", is not one.
package enum FidelityClaim {
  package static func overstates(_ answer: String) -> Bool {
    let text = answer.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
  }

  package static let feedback =
    "The host confirms what was saved, not how faithful its content is. Say what you saved and what you chose, without claiming it was kept perfectly, verbatim or verified."

  private static let verbs =
    #"(?:preserved|kept|copied|reproduced|captured|transcribed|matched|saved|recorded|carried over)"#
  private static let manner =
    #"(?:perfectly|flawlessly|faithfully|verbatim|word for word|without (?:any )?(?:errors?|changes?|loss|omissions?))"#
  private static let patterns = [
    #"\b"# + verbs + #"\b(?:\s+\w+){0,4}\s+"# + manner + #"\b"#,
    #"\b(?:perfectly|flawlessly|faithfully|verbatim)\s+"# + verbs + #"\b"#,
    #"\b(?:every|each|all)\s+(?:\w+\s+){0,3}(?:details?|conditions?|identifiers?|values?|fields?|lines?|requirements?)\s+(?:(?:was|were|is|are|has been|have been)\s+)?(?:preserved|verified|validated|kept intact)\b"#,
    #"\b(?:guard|copi|conserv|preserv|registr)\w*\s+(?:\w+\s+){0,3}(?:perfectamente|fielmente|sin errores|tal cual)\b"#,
  ]
}
