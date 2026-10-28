import Foundation
import SevraCore

/// Stable IDs, rather than titles, keep duplicate names independently navigable.
public struct SpacePickerSections {
  public let home: [Space]
  public let pinned: [Space]
  public let recent: [Space]
  public let others: [Space]
  public var isEmpty: Bool { home.isEmpty && pinned.isEmpty && recent.isEmpty && others.isEmpty }
  public init(spaces: [Space], navigation: SpaceNavigationState, query: String) {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matching = spaces.filter {
      query.isEmpty || $0.title.localizedStandardContains(query)
    }
    let byID = Dictionary(uniqueKeysWithValues: matching.map { ($0.id, $0) })
    home = matching.filter { $0.id == "home" }
    pinned = navigation.pinned.compactMap { byID[$0] }.filter { $0.id != "home" }
    let pins = Set(pinned.map(\.id))
    recent = navigation.recent.compactMap { byID[$0] }.filter {
      $0.id != "home" && !pins.contains($0.id)
    }
    let shown = Set((home + pinned + recent).map(\.id))
    others = matching.filter { !shown.contains($0.id) }.sorted {
      let comparison = $0.title.localizedStandardCompare($1.title)
      return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
    }
  }
}
