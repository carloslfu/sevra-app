import Foundation

/// Present the known native capture envelope without altering its original text.
/// Unrecognized contexts, including multiline titles, remain visible verbatim.
public struct RequestContextPresentation {
  public enum Location: String {
    case space = "Space"
    case item = "Item"
    case table = "Table"
  }
  public let original: String
  public let location: Location?
  public let title: String?
  public let id: String?
  public let selection: String?

  public init(_ original: String) {
    self.original = original
    let lines = original.components(separatedBy: "\n")
    let prefixes: [(Location, String)] = [
      (.space, "Active space ID: "), (.item, "Active item version ID: "),
      (.table, "Active dataset ID: "),
    ]
    if lines.count >= 2,
      let (kind, prefix) = prefixes.first(where: {
        lines[0].hasPrefix($0.0.rawValue + ": ") && lines[1].hasPrefix($0.1)
      })
    {
      let candidate = String(lines[1].dropFirst(prefix.count))
      let name = String(lines[0].dropFirst(kind.rawValue.count + 2))
      let remaining = lines.dropFirst(2).joined(separator: "\n")
      if !name.trimmingCharacters(in: .whitespaces).isEmpty,
        UUID(uuidString: candidate) != nil || (kind == .space && candidate == "home"),
        lines.count == 2 || remaining.hasPrefix("Selection: ")
      {
        location = kind
        title = name
        id = candidate
        selection = lines.count == 2 ? nil : String(remaining.dropFirst("Selection: ".count))
        return
      }
    }
    location = nil
    title = nil
    id = nil
    selection = nil
  }
}
