import Foundation

/// Workbook presentation preferences, separate from space definitions and business history.
public struct SpaceNavigationState: Codable, Equatable, Sendable {
  public var version = 1
  public private(set) var pinned: [String] = []
  public private(set) var recent: [String] = []
  public init() {}

  fileprivate mutating func apply(_ edit: SpaceNavigationEdit) throws {
    switch edit {
    case .visit(let id):
      guard id != "home" else { return }
      recent.removeAll { $0 == id }
      recent.insert(id, at: 0)
      recent = Array(recent.prefix(8))
    case .pin(let id, let selected):
      guard id != "home" else { return }
      if selected && !pinned.contains(id) {
        try require(pinned.count < 64, "space_navigation", "Unpin a space before pinning another.")
        pinned.append(id)
      } else if !selected {
        pinned.removeAll { $0 == id }
      }
    }
  }
}

public enum SpaceNavigationEdit: Equatable, Sendable {
  case visit(String)
  case pin(String, Bool)
  public var spaceID: String {
    switch self {
    case .visit(let id), .pin(let id, _): return id
    }
  }
}

extension Workbook {
  /// Used inside the bounded workspace snapshot. No bodies or definitions are read here.
  func readSpaceNavigation() throws -> SpaceNavigationState {
    let size =
      try db.scalar(
        "SELECT length(CAST(value AS BLOB)) FROM meta WHERE key='space-navigation'"
      ).int ?? 0
    try require(size <= 32_000, "space_navigation", "Saved space navigation is too large.")
    guard let text = try db.scalar("SELECT value FROM meta WHERE key='space-navigation'").string
    else { return SpaceNavigationState() }
    let state = try JSONDecoder().decode(SpaceNavigationState.self, from: Data(text.utf8))
    try require(
      state.version == 1 && state.pinned.count <= 64 && state.recent.count <= 8
        && Set(state.pinned).count == state.pinned.count
        && Set(state.recent).count == state.recent.count
        && (state.pinned + state.recent).allSatisfy { !$0.isEmpty && $0.utf8.count <= 256 },
      "space_navigation", "Invalid saved space navigation.")
    return state
  }

  /// Merge intentions with the latest saved state under the package lock, so a
  /// recent visit cannot erase a pin made by another window. No business revision changes.
  @discardableResult public func updateSpaceNavigation(_ edits: [SpaceNavigationEdit]) throws
    -> SpaceNavigationState
  {
    try require(edits.count <= 256, "space_navigation", "Too many navigation changes.")
    return try presentationMutation {
      var state = try readSpaceNavigation()
      for edit in edits {
        try require(
          edit.spaceID.utf8.count <= 256
            && db.scalar("SELECT count(*) FROM spaces WHERE id=?", [.string(edit.spaceID)]).int
              == 1,
          "space_navigation", "Space not found.")
        try state.apply(edit)
      }
      let text = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
      try require(
        text.utf8.count <= 32_000, "space_navigation", "Saved space navigation is too large.")
      try db.execute(
        "INSERT INTO meta(key,value) VALUES('space-navigation',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        [.string(text)])
      return state
    }
  }
}
