import Foundation

/// A narrow English backstop for an answer's own consistency, not a semantic
/// proof of arbitrary pricing prose. When the answer itself says that a cost is
/// unknown or missing, a partial sum cannot be labeled a total or the cheapest
/// quote, and a ranking must say that the all-in order remains undetermined.
package enum CostQualification {
  package static func overstates(_ answer: String) -> Bool {
    let units = sentences(answer)
    guard units.contains(where: { has(cost, $0) && has(missing, $0) }) else { return false }
    let unqualifiedClaim = units.contains {
      has(claim, $0) && !has(qualifier, $0) && !has(uncertain, $0) && !has(missing, $0)
        && !(has(unitPrice, $0) && !has(total, $0))
    }
    let openOrdering = units.contains { has(allIn, $0) && has(uncertain, $0) && has(ordering, $0) }
    return unqualifiedClaim || (units.contains { has(ranking, $0) } && !openOrdering)
  }

  package static let feedback =
    "The answer says some costs are unknown or missing, so it must not present a partial sum as a total or a definitive cheapest quote. Label each amount by the components it includes, such as known goods-plus-shipping cost. Name the lowest known cost instead of the cheapest quote, and state that the final all-in ordering cannot be determined until the missing costs are known. Keep supported calculations, citations and currency labels."

  private static let cost =
    #"\b(?:tax(?:es)?|vat|gst|duty|duties|tariffs?|customs|fees?|surcharges?|handling|insurance|freight|costs?|charges?|prices?|pricing)\b"#
  private static let missing =
    #"\b(?:unknown|missing|unavailable|unspecified|undocumented|undetermined|unstated|unresolved|indeterminate)\b|\bnot (?:\w+ )?(?:documented|provided|specified|stated|listed|given|available|known|supplied|shown|quoted|mentioned|determined|determinable|disclosed|found|included)\b|\b(?:does|do|did)(?: not|n't) (?:\w+ )?(?:include|list|specify|state|mention|provide|show|give|document|contain|quote|disclose|cover)\b|\b(?:cannot|can't|could not|couldn't) (?:yet )?be (?:determined|calculated|confirmed|known|established|computed|verified|compared)\b|\bno (?:[\w-]+ ){0,2}(?:rates?|information|details|data|amounts?|figures?|values?)\b"#
  private static let ranking =
    #"\bcheap(?:er|est)\b|\b(?:least|less) expensive\b|\blowest (?:[\w-]+ ){0,3}(?:prices?|costs?|quotes?|offers?|bids?|totals?|amounts?|options?)\b|\bbest (?:prices?|deals?|value|offers?|quotes?)\b|\bmost (?:affordable|economical)\b"#
  // Quantity and count totals are not price claims.
  private static let total =
    #"\b(?:grand )?totals?\b(?! (?:quantity|quantities|units?|items?|rows?|records?|count|weight|volume|pieces?|hours?|days?)\b)"#
  private static let claim = total + "|" + ranking
  private static let unitPrice = #"\bunit (?:prices?|costs?)\b"#
  private static let qualifier =
    #"\bknown\b|\bpartial\b|\bgoods ?(?:-plus-|\+|plus|and|&) ?shipping\b|\b(?:on|for|of) (?:the )?goods\b|\b(?:before|excluding|excludes|excluded|exclusive of|excl|ex|pre|without|net of)[ -](?:[\w-]+ ){0,2}?(?:tax(?:es)?|vat|gst|duty|duties|tariffs?|customs|fees?|surcharges?)\b|\bnot (?:an? |the )?(?:final|all[ -]in|full|complete|definitive|overall|landed)\b|\bprovisional\b|\bpreliminary\b"#
  private static let uncertain =
    #"\b(?:cannot|can't|could not|couldn't|unable to|undetermined|unknown|unresolved|uncertain|indeterminate)\b|\buntil (?:the |those |these |all )?(?:missing|unknown|remaining|tax|taxes|costs?)\b|\bdepends? on\b|\bnot (?:yet )?(?:be )?(?:determined|determinable|known|established|confirmed|possible)\b|\b(?:may|might|could) (?:change|differ)\b"#
  private static let allIn = #"\b(?:all[ -]in|final|overall|landed|full|complete)\b"#
  private static let ordering =
    #"\b(?:costs?|prices?|totals?|order(?:ing)?|rank(?:ing)?|comparison|cheapest|amounts?)\b"#

  private static func has(_ pattern: String, _ text: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
  }

  /// Sentence breaks need following whitespace, so decimal points stay inside a
  /// unit. Table cells are separate labels; Markdown emphasis does not matter.
  private static func sentences(_ answer: String) -> [String] {
    answer.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
    )
    .replacingOccurrences(of: "’", with: "'")
    .replacingOccurrences(of: #"\b(excl|incl|vs|e\.g|i\.e|approx)\."#, with: "$1", options: .regularExpression)
    .replacingOccurrences(of: #"[.!?]+(?=\s)|\|"#, with: "\n", options: .regularExpression)
    .split(whereSeparator: \.isNewline).map(String.init)
  }
}
