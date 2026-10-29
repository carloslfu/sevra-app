import Foundation

public struct SpaceTarget: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
}

extension Workbook {
  /// Resolve an exact ID or an unambiguous name. A partial name never selects the
  /// first convenient match. The caller must ask when the saved names collide.
  public func spaceTarget(_ nameOrID: String, cancellation: Cancellation = .init()) throws
    -> SpaceTarget
  {
    let target = nameOrID.trimmingCharacters(in: .whitespacesAndNewlines)
    try require(
      !target.isEmpty && target.utf8.count <= 512, "space_target", "Choose a space by name.")
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        if let row = try db.execute("SELECT id,title FROM spaces WHERE id=?", [.string(target)])
          .first
        {
          return .init(id: row["id"]!.text, title: row["title"]!.text)
        }
        let rows = try db.execute(
          "SELECT id,title FROM spaces WHERE title=? COLLATE NOCASE ORDER BY id LIMIT 2",
          [.string(target)])
        try require(
          !rows.isEmpty, "space_not_found", "No space has that exact name. Which space do you mean?"
        )
        try require(
          rows.count == 1, "space_ambiguous",
          "More than one space has that name. Which one do you mean? You can describe it or select it in Spaces."
        )
        return .init(id: rows[0]["id"]!.text, title: rows[0]["title"]!.text)
      }
    }
  }
}
