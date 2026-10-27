import Foundation
import SevraCore

/// Conservative guard for identifiable absence/completeness claims. The model
/// cannot authorize a global assertion by selecting an answer basis or citing a
/// search hit. Exact record counts are rendered by the host in a separate scope.
package enum SearchCoverage {
  package static func overstates(_ answer: String) -> Bool {
    let text = answer.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
    )
    .replacingOccurrences(of: "’", with: "'")
    let patterns = [
      #"\bthere (?:are|is|were|was) (?:no|zero|not any) (?!matches\b|results\b|hits\b)"#,
      #"\b(?:workbook|database|records?|files?|documents?|inventory) (?:has|have|contains?|includes?) (?:no|zero|none)\b"#,
      #"\b(?:does not|doesn't|do not|don't) (?:contain|include|have) (?:any )?(?:\w+\s+){0,3}(?:records?|movements?|documents?|files?|contracts?|invoices?|payments?|orders?|assets?)\b"#,
      #"\bno (?:\w+[ -]){0,6}(?:exist|exists|occurred|happened|recorded|registered|present|available)\b"#,
      #"\bno (?:\w+[ -]){0,4}(?:records?|movements?|documents?|files?|contracts?|invoices?|payments?|orders?|assets?)\b"#,
      #"\b(?:zero|0) (?:\w+[ -]){0,4}(?:records?|movements?|documents?|files?|contracts?|invoices?|payments?|orders?|assets?)\b"#,
      #"\b(?:nothing|none) (?:else )?(?:exists|is recorded|was recorded|is present|is available)\b"#,
      #"\b(?:searched|checked|reviewed|examined|scanned|covered) (?:absolutely )?(?:all|every|the entire|the whole|everything)\b"#,
      #"\b(?:all|every|entire|whole) (?:\w+[ -]){0,5}(?:searched|checked|reviewed|examined|scanned)\b"#,
      #"\b(?:complete|exhaustive|comprehensive) (?:search|coverage|list|inventory)\b"#,
      #"\b(?:no hay|no existen?|no se (?:registraron|registro)|ningun[oa]s? (?:\w+\s+){0,3}(?:registrad[oa]s?|existentes?))\b"#,
      #"\b(?:busque|revise|examine|comprobe) (?:todos?|todas?|cada|todo el|toda la)\b"#,
    ]
    return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
  }

  package static let feedback =
    "Do not infer absence or exhaustive coverage from search, an empty table list, or selected citations. Remove the unsupported claim. You may report what a named search returned. For an exact structured count, call count_records and put its current-run receipt ID in finish.coverage; do not restate its count as a broader claim in prose. Keep the answer focused on the user's question."

  private static func escape(_ text: String) -> String {
    text.reduce("") { result, character in
      result + ("\\`*_{}[]<>()!#|".contains(character) ? "\\" : "") + String(character)
    }
  }

  package static func render(_ result: Value) -> String {
    let filters = result["filters"]
    let category = filters["category"].text == "source" ? "Sources" : "Records"
    let scope = ["kind", "status", "meaning", "scenario"].map {
      $0 + ": " + escape(filters[$0].string ?? "any")
    }.joined(separator: ", ")
    return
      "Current workbook \(category): \(result["count"].int.map(String.init) ?? "unavailable") (\(scope)). This counts classified workbook entries; documents may describe additional events."
  }
}
