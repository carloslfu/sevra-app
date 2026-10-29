import Foundation

/// Explicit navigation and sharing phrases work without loading the model.
/// Ordinary questions, negated instructions and quoted phrases are not commands.
public enum ConversationCommand: Equatable, Sendable {
  case startThread(title: String?)
  case backToConversation
  case shareSummary(text: String?)

  public static func parse(_ input: String) -> Self? {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = text.lowercased().replacingOccurrences(of: "’", with: "'")
    let phrase = lower.trimmingCharacters(in: CharacterSet(charactersIn: ".! "))
    if [
      "back to main", "back to conversation", "go back to our main conversation",
      "go back to the main conversation", "return to main",
    ].contains(phrase) {
      return .backToConversation
    }
    if ["start a thread", "let's explore this separately", "let us explore this separately"]
      .contains(phrase)
    {
      return .startThread(title: nil)
    }
    if phrase == "share summary with conversation" { return .shareSummary(text: nil) }
    for prefix in ["start a thread called ", "start a thread: ", "thread ", "tangent "] {
      if lower.hasPrefix(prefix) {
        let title = String(text.dropFirst(prefix.count)).trimmingCharacters(
          in: .whitespacesAndNewlines)
        if !title.isEmpty { return .startThread(title: title) }
      }
    }
    let prefix = "share summary with conversation:"
    if lower.hasPrefix(prefix) {
      let summary = String(text.dropFirst(prefix.count)).trimmingCharacters(
        in: .whitespacesAndNewlines)
      return .shareSummary(text: summary.isEmpty ? nil : summary)
    }
    return nil
  }
}
