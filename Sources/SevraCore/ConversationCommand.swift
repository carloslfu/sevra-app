import Foundation

/// Typed review commands. A review names one exact version, so a sentence that happens to start
/// with the same word stays a message.
public enum WorkbookTextCommand: Equatable, Sendable {
  case accept(String)
  case undo(String)

  public static func parse(_ input: String) -> Self? {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = text.lowercased()
    func argument(_ prefix: String) -> String? {
      guard lower.hasPrefix(prefix) else { return nil }
      return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let id = argument("accept "), UUID(uuidString: id) != nil { return .accept(id) }
    if let id = argument("undo "), UUID(uuidString: id) != nil { return .undo(id) }
    return nil
  }
}
