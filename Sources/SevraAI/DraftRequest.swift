import Foundation

/// A narrow backstop for a plain request to draft something, not a reading of every request.
/// The model gets one correction, so a false alarm costs one step and nothing more.
package enum DraftRequest {
  package static func asks(_ request: String) -> Bool {
    request.range(of: question, options: [.regularExpression, .caseInsensitive]) == nil
      && request.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }
  /// "Can you write a draft?" asks for one. "Should I make a draft?" and "How do I create a
  /// draft?" do not.
  private static let question =
    #"^\s*¿?\s*(?:should|shall|did|do|does|how|what|when|why|where|who|which|is|are|was|were|has|have|debo|debería|cómo|qué|cuándo|hiciste)\b"#
  private static let pattern =
    #"^\s*(?:please\s+)?draft\b|\b(?:write|save|make|prepare|create)\s+(?:me\s+)?(?:a|an|one)\s+(?:\w+\s+)?draft\b|\b(?:redacta|escribe|haz|prepara|crea|guarda)(?:me)?\s+(?:un|una)\s+(?:\w+\s+)?borrador\b"#
}
