import Foundation

/// A bounded record view. Time views use workbook civil dates and retain exact
/// row versions so presentation controls can call the ordinary table editor.
public struct WorkVisual: Codable, Equatable, Sendable {
  public enum Style: String, Codable, Sendable { case board, timeline, agenda, calendar }

  public let title: String
  public let style: Style
  public let query: Value
  public let label: String
  public let field: String
  public let end: String?
  public let lanes: [String]?
  public let month: String?

  static func parse(_ value: Value) throws -> Self {
    _ = try queryObject(
      value, keys: ["title", "style", "query", "label", "field", "end", "lanes", "month"])
    let view = try JSONDecoder().decode(Self.self, from: Data(value.json().utf8))
    try view.validate()
    return view
  }

  func validate(appAliases: Set<String>? = nil) throws {
    try require(
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && title.utf8.count <= 200 && query.json().utf8.count <= 8192,
      "work_view", "Use a short title and a bounded typed query.")
    let contract = try visualQuery(query, appAliases: appAliases)
    let fields = [label, field] + (end.map { [$0] } ?? [])
    try require(
      !contract.grouped && contract.limit <= 100 && contract.sources.count == 1
        && Set(fields).count == fields.count && Set(contract.selections.map(\.id)) == Set(fields),
      "work_view",
      "Select distinct title and status or date columns from one table. Use a limit up to 100 rows."
    )
    if style == .board {
      guard let lanes, (1...8).contains(lanes.count), Set(lanes).count == lanes.count,
        lanes.allSatisfy({
          !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 80
        }),
        end == nil, month == nil
      else {
        throw SevraError(
          "work_view", "Board lanes must be one to eight distinct named status values.")
      }
    } else {
      try require(
        lanes == nil
          && (style == .calendar
            ? month.flatMap(Self.date) != nil && month!.hasSuffix("-01") : month == nil),
        "work_view", "For a calendar, set month to the first day of the visible month.")
    }
  }

  static func date(_ text: String) -> Date? {
    let format = Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash)
    guard let result = try? format.parse(text), result.formatted(format) == text else { return nil }
    return result
  }
}

public struct WorkVisualData: Codable, Equatable, Sendable {
  public struct Record: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let value: String?
    public let end: String?
  }

  public let records: [Record]
  public let revision: Int
  public let scope: Value
  public let captured: String

  init(_ result: Value, work: WorkVisual) throws {
    try require(
      result["hasMore"] == .bool(false), "work_view_coverage",
      "Refine the workspace query to show its complete record set.")
    let columns = result["columns"].array
    func type(_ id: String) -> String {
      columns.first(where: { $0["id"] == .string(id) })?["type"].text ?? ""
    }
    try require(
      type(work.field) == (work.style == .board ? "text" : "date")
        && (work.end.map { type($0) == "date" } ?? true),
      "work_view", "Boards need a text status. Time views need civil date columns.")
    records = try result["rows"].array.map { row in
      guard let version = row["inputs"].array.first?["versionID"].string else {
        throw SevraError("work_view", "This record does not have an exact editable row version.")
      }
      let values = row["values"]
      let label = values[work.label].text
      let field = values[work.field].string.flatMap { $0.isEmpty ? nil : $0 }
      let last = work.end.flatMap { values[$0].string }.flatMap { $0.isEmpty ? nil : $0 }
      let start = work.style == .board ? field : try field.map(Self.civilDay)
      let end = try last.map(Self.civilDay)
      if let end {
        try require(
          start.map { $0 <= end } == true, "work_view_date",
          "A record has a reversed date range.")
      }
      return Record(
        id: version, title: label.isEmpty ? "Untitled record" : label, value: start, end: end)
    }
    revision = result["revision"].int ?? 0
    scope = result["sourceScopes"]
    captured = timestamp()
    try validate()
  }

  /// The typed query normalizes dates to UTC instants. Date-only columns are
  /// midnight UTC. Refuse other times instead of stripping information.
  private static func civilDay(_ normalized: String) throws -> String {
    let day = String(normalized.prefix(10))
    try require(
      normalized == day + "T00:00:00.000Z" && WorkVisual.date(day) != nil,
      "work_view_date", "Use a date-only column for this view.")
    return day
  }

  func validate() throws {
    try require(
      revision > 0 && records.count <= 100 && Set(records.map(\.id)).count == records.count
        && records.allSatisfy {
          $0.id.utf8.count <= 128 && $0.title.utf8.count <= 512
            && ($0.value?.utf8.count ?? 0) <= 160 && ($0.end?.utf8.count ?? 0) <= 10
        },
      "work_view", "The work view contains unsupported record values.")
  }
}

extension Workbook {
  public func workVisualData(_ view: WorkVisual, cancellation: Cancellation = .init()) throws
    -> WorkVisualData
  {
    try view.validate()
    return try WorkVisualData(queryDataset(view.query, cancellation: cancellation), work: view)
  }

  public func changeWorkRecord(
    spaceID: String, componentID: String, expectedVersion: Int, recordID: String,
    value: String, end: String? = nil, token: String = identifier(),
    cancellation: Cancellation = .init(), actor: ChangeActor? = nil
  ) throws -> TableEdit {
    let request: Value = .object([
      "spaceID": .string(spaceID), "componentID": .string(componentID),
      "version": .number(Double(expectedVersion)), "record": .string(recordID),
      "value": .string(value), "end": end.map(Value.string) ?? .null,
    ])
    return try mutation(
      "visual_record_edit", token: token, request: request, cancellation: cancellation,
      actor: actor,
      reading: { value in
        TableEdit(id: value["id"].text, items: try value["items"].array.map { try item($0.text) })
      }
    ) {
      let owner = try space(spaceID)
      try checkSpaceBase(owner, expectedVersion: expectedVersion)
      guard let view = owner.definition.component(componentID)?.visual?.work else {
        throw SevraError("work_view", "Choose a saved work view.")
      }
      let contract = try DatasetQuery(view.query)
      let current = try workVisualData(view, cancellation: cancellation)
      guard let record = current.records.first(where: { $0.id == recordID }) else {
        throw SevraError("stale_work_record", "This exact record is no longer in the current view.")
      }
      let field = contract.selections.first { $0.id == view.field }!.column!.column
      var changes: [String: Value] = [field: .string(value)]
      if view.style == .board {
        try require(
          view.lanes?.contains(value) == true && end == nil,
          "work_view", "Move this record to a declared lane.")
      } else {
        try require(
          WorkVisual.date(value) != nil, "work_view_date", "Use a date in YYYY-MM-DD format.")
        if let end {
          guard let endID = view.end,
            let column = contract.selections.first(where: { $0.id == endID })?.column
          else { throw SevraError("work_view_date", "This view does not declare an end date.") }
          try require(
            WorkVisual.date(end) != nil && value <= end, "work_view_date",
            "The end date must be on or after the start date.")
          changes[column.column] = .string(end)
        } else if let previousEnd = record.end {
          try require(
            value <= previousEnd, "work_view_date",
            "Supply an end date on or after the new start date.")
        }
      }
      try require(
        record.value != value || (end != nil && record.end != end),
        "work_view", "This record already has the selected value.")
      let datasetID = contract.sources[0].dataset
      let table = try dataset(datasetID)
      let item = try item(recordID)
      let currentValues = Self.activeValues(item.data.object, columns: table.columns)
      return try applyRows(
        datasetID,
        edits: [.init(id: recordID, values: currentValues.merging(changes) { _, next in next })],
        request: request)
    }
  }
}

extension SpaceDefinition {
  func component(_ id: String) -> Component? {
    func find(_ components: [Component]) -> Component? {
      components.first { $0.id == id }
        ?? components.lazy.compactMap { find($0.children ?? []) }.first
    }
    return find(components)
  }
}
