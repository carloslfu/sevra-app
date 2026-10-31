import Foundation

/// A narrow backstop for a plain request to draft something, not a reading of every request.
/// The model gets one correction, so a false alarm costs one step and nothing more.
package enum DraftRequest {
  package static func asks(_ request: String) -> Bool {
    request.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }
  private static let pattern =
    #"^\s*(?:please\s+)?draft\b|\b(?:write|save|make|prepare|create)\s+(?:me\s+)?(?:a|an|one)\s+(?:\w+\s+)?draft\b|\b(?:redacta|escribe|haz|prepara|crea|guarda)(?:me)?\s+(?:un|una)\s+(?:\w+\s+)?borrador\b"#
}
