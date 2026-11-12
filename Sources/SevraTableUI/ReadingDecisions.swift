import Foundation

/// Navigation decisions shared by the native bridge and windowless regression checks.
public enum TableCellNavigation {
  public struct Cell: Equatable {
    public let row: Int
    public let column: Int
    public init(row: Int, column: Int) {
      self.row = row
      self.column = column
    }
  }
  public static func row(identity: String?, rows: [String], selected: IndexSet) -> Int {
    if let identity, let index = rows.firstIndex(of: identity), selected.contains(index) {
      return index
    }
    return selected.first(where: { rows.indices.contains($0) }) ?? -1
  }
  public static func column(identity: String?, columns: [String]) -> Int {
    columns.firstIndex { $0 == identity } ?? 0
  }
  public static func destination(
    rows: Int, columns: Int, current: Cell, delta: Int, editableOnly: Bool,
    isEditable: (Cell) -> Bool
  ) -> Cell? {
    guard rows > 0, columns > 0, [-1, 1].contains(delta),
      current.column >= 0, current.column < columns, current.row < rows
    else { return nil }
    if !editableOnly {
      if current.row < 0 { return .init(row: 0, column: current.column) }
      let column = current.column + delta
      return (0..<columns).contains(column) ? .init(row: current.row, column: column) : nil
    }
    let (count, overflow) = rows.multipliedReportingOverflow(by: columns)
    guard !overflow else { return nil }
    var index =
      current.row < 0 ? (delta > 0 ? 0 : count - 1) : current.row * columns + current.column + delta
    while (0..<count).contains(index) {
      let cell = Cell(row: index / columns, column: index % columns)
      if isEditable(cell) { return cell }
      index += delta
    }
    return nil
  }
}

/// This only decides whether an event is eligible. The native adapter alone posts it.
public struct StatusAnnouncementPolicy {
  public struct Event: Equatable {
    public let text: String
    fileprivate let generation: Int
  }
  private var initialized = false
  private var generation = 0
  private var message: String?
  public init() {}
  public mutating func update(_ next: String?) -> Event? {
    let changed = initialized && message != next
    if message != next { generation += 1 }
    initialized = true
    message = next
    guard changed, let next, !next.isEmpty else { return nil }
    return Event(text: next, generation: generation)
  }
  public func canDeliver(_ event: Event, ownWindowIsKey: Bool, appIsActive: Bool) -> Bool {
    event.generation == generation && event.text == message && ownWindowIsKey && appIsActive
  }
}

public enum ReadingTarget: Hashable {
  case workspace, conversation, composer, status
  case message(String)
}
public enum ReadingFocusPolicy {
  public static func canRequest(appIsActive: Bool, ownWindowIsKey: Bool, ownSheetIsKey: Bool)
    -> Bool
  {
    appIsActive && (ownWindowIsKey || ownSheetIsKey)
  }
  public static func canApply(
    request: UUID, currentRequest: UUID, pending: Bool, interactionActive: Bool,
    ownWindowIsKey: Bool, appIsActive: Bool
  ) -> Bool {
    request == currentRequest && pending && interactionActive && ownWindowIsKey && appIsActive
  }
  public static func destination(_ target: ReadingTarget, visibleMessages: Set<String>)
    -> ReadingTarget
  {
    if case .message(let id) = target, !visibleMessages.contains(id) { return .conversation }
    return target
  }
}

public enum ReadingMetrics {
  public static let preference = "readingTextScale"
  public static func scale(_ value: Double) -> Double { value.isFinite ? min(2, max(1, value)) : 1 }
  public static func adjusted(_ value: Double, steps: Int) -> Double {
    min(2, max(1, scale(value) + Double(steps) * 0.25))
  }
  public static func points(_ base: Double, scale value: Double) -> Double { base * scale(value) }
}
