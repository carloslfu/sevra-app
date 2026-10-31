import Foundation
import SevraCore

/// The choices in one reviewed update. Keeping them here lets every rule run
/// without a window: suggestions fill only undecided inputs, and a person's
/// choices, including Ignore, stand until they change them.
public struct TableUpdateForm: Equatable, Sendable {
  public enum Choice: Hashable, Sendable {
    case unselected, ignore
    case column(String)
  }
  public var target = ""
  public var mode: TableUpdateMode?
  public var header = "1"
  public var sheet: String?
  public var mapping: [Int: Choice] = [:]
  public var keys = Set<String>()
  public var meaning = ""
  public var scenario = ""
  public var intake: String?
  public private(set) var suggested: [Int: String] = [:]
  public private(set) var suggestionNotes: [String] = []
  public init() {}

  public var mappedColumns: [String] {
    mapping.values.compactMap {
      if case .column(let id) = $0 { return id }
      return nil
    }
  }

  public func undecided(_ source: TableUpdateSource?) -> [Int] {
    (source?.headings.indices ?? 0..<0).filter { mapping[$0] == nil || mapping[$0] == .unselected }
  }

  public func isSuggested(_ position: Int) -> Bool {
    suggested[position].map { mapping[position] == .column($0) } ?? false
  }

  /// What still stands between this review and a preview, in the order to fix it.
  public func blocker(_ source: TableUpdateSource?, columns: [Column]?) -> String? {
    guard let source else { return nil }
    if source.needsSheet { return "Choose a worksheet." }
    if source.headerRow != Int(header) { return "Read the headings for this header row." }
    guard let columns else { return "Choose a target table." }
    if mode == nil { return "Choose an update method." }
    let stored = columns.filter { $0.formula == nil }
    let used = mappedColumns
    if let repeated = stored.first(where: { column in used.filter { $0 == column.id }.count > 1 }) {
      return "\(repeated.title) is mapped twice."
    }
    let missing = stored.filter { !used.contains($0.id) }.map(\.title)
    if !missing.isEmpty { return "Still to map: " + missing.joined(separator: ", ") + "." }
    if !undecided(source).isEmpty { return "Map or ignore every incoming column." }
    if mode == .merge && keys.isEmpty { return "Choose at least one key column." }
    return nil
  }

  /// Every stored column is mapped, so the remaining inputs have nowhere to go.
  public func canIgnoreRest(_ source: TableUpdateSource?, columns: [Column]) -> Bool {
    !undecided(source).isEmpty
      && Set(mappedColumns).isSuperset(of: columns.filter { $0.formula == nil }.map(\.id))
  }

  public mutating func ignoreRest(_ source: TableUpdateSource?) {
    for position in undecided(source) { mapping[position] = .ignore }
  }

  public mutating func suggest(_ source: TableUpdateSource?, columns: [Column]?) {
    suggested = [:]
    suggestionNotes = []
    guard let source, !source.needsSheet, let columns else { return }
    let suggestion = source.suggestion(for: columns)
    suggestionNotes = suggestion.notes
    var taken = Set(mappedColumns)
    for entry in suggestion.mapping {
      guard let column = entry.target else { continue }
      suggested[entry.position] = column
      if mapping[entry.position] == nil || mapping[entry.position] == .unselected,
        taken.insert(column).inserted
      {
        mapping[entry.position] = .column(column)
      }
    }
    if mode == .merge && keys.isEmpty { keys = Set(suggestion.keys) }
  }

  public mutating func choose(target next: String, source: TableUpdateSource?, columns: [Column]?) {
    guard next != target else { return }
    target = next
    mapping = [:]
    keys = []
    suggest(source, columns: columns)
  }

  public mutating func choose(
    mode next: TableUpdateMode?, source: TableUpdateSource?, columns: [Column]?
  ) {
    guard next != mode else { return }
    mode = next
    keys = []
    suggest(source, columns: columns)
  }

  /// A different header or worksheet means different inputs, so mapping starts again.
  public mutating func clearInputs() {
    mapping = [:]
    suggested = [:]
    suggestionNotes = []
  }

  public func draft(sourceID: String) -> TableUpdateDraft {
    var draft = TableUpdateDraft(sourceID: sourceID)
    draft.intakeID = intake
    draft.headerRow = Int(header).flatMap { (1...1_048_576).contains($0) ? $0 : nil } ?? 1
    draft.sheet = sheet
    draft.datasetID = target.isEmpty ? nil : target
    draft.mode = mode
    draft.decisions = mapping.sorted { $0.key < $1.key }.compactMap { position, choice in
      switch choice {
      case .unselected: return nil
      case .ignore: return .init(position: position, target: nil)
      case .column(let id): return .init(position: position, target: id)
      }
    }
    draft.keys = keys.sorted()
    draft.meaning = meaning
    draft.scenario = scenario
    return draft
  }

  public mutating func restore(_ draft: TableUpdateDraft) {
    header = String(draft.headerRow)
    sheet = draft.sheet
    target = draft.datasetID ?? ""
    mode = draft.mode
    keys = Set(draft.keys)
    meaning = draft.meaning
    scenario = draft.scenario
    intake = draft.intakeID
    mapping = Dictionary(
      uniqueKeysWithValues: draft.decisions.map {
        ($0.position, $0.target.map(Choice.column) ?? .ignore)
      })
  }
}
