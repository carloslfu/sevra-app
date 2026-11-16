import Foundation

public struct VisualChart: Codable, Equatable, Sendable {
  public enum Style: String, Codable, Sendable {
    case bar, horizontalBar, stackedBar, line, area, scatter, donut
  }
  public let title: String
  public let style: Style
  public let query: Value
  public let x: String
  public let y: String
  public let threshold: String?
  public let series: String?

  public init(
    title: String, style: Style, query: Value, x: String, y: String, threshold: String? = nil,
    series: String? = nil
  ) {
    self.title = title
    self.style = style
    self.query = query
    self.x = x
    self.y = y
    self.threshold = threshold
    self.series = series
  }

  static func parse(_ value: Value) throws -> Self {
    _ = try queryObject(value, keys: ["title", "style", "query", "x", "y", "threshold", "series"])
    let definition = try JSONDecoder().decode(Self.self, from: Data(value.json().utf8))
    try definition.validate()
    return definition
  }

  func validate(appAliases: Set<String>? = nil) throws {
    try require(
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.utf8.count <= 200
        && x != y && query.json().utf8.count <= 8192,
      "visual_chart", "Use a short title, two distinct output fields and a bounded typed query.")
    if let threshold {
      try require(
        style != .donut && threshold.utf8.count <= 128, "visual_chart",
        "Use a decimal threshold on a chart with axes.")
      _ = try Numbers.decimal(threshold)
    }
    let contract = try visualQuery(query, appAliases: appAliases)
    let fields = [x, y] + (series.map { [$0] } ?? [])
    try require(
      Set(fields).count == fields.count && Set(contract.selections.map(\.id)) == Set(fields)
        && contract.limit <= 100,
      "visual_chart", "Select the x, y and optional series fields. Use a limit of up to 100 marks.")
    try require(
      (style != .stackedBar || series != nil)
        && (series == nil || [.bar, .line, .stackedBar].contains(style)),
      "visual_chart", "Choose grouped bars, stacked bars or lines for multiple series.")
    try require(
      !contract.grouped || contract.joins.isEmpty,
      "visual_chart", "Aggregate a single table so joined rows cannot multiply the chart totals.")
  }
}

func visualQuery(_ query: Value, appAliases: Set<String>?) throws -> DatasetQuery {
  var normalized = query
  if let appAliases {
    guard case .array(let sources) = query["sources"] else {
      throw SevraError("visual_chart", "Declare the chart's dataset aliases.")
    }
    var fields = query.object
    fields["sources"] = .array(
      try sources.map { source in
        let source = try queryObject(source, keys: ["table", "scope"])
        guard let alias = source["table"]?.string, appAliases.contains(alias) else {
          throw SevraError(
            "visual_chart", "Chart sources must use the app’s declared dataset aliases.")
        }
        return .object([
          "datasetID": .string(alias), "definitionID": .string(alias),
          "scope": source["scope"] ?? .object([:]),
        ])
      })
    normalized = .object(fields)
  }
  return try DatasetQuery(normalized)
}

public struct VisualChartData: Codable, Equatable, Sendable {
  public struct Point: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let label: String
    public let amount: String
    public let series: String?
    public let sourceIDs: [String]
  }
  public let points: [Point]
  public let queryHash: String
  public let snapshot: String
  public let scope: Value
  public let temporal: Bool?
  public let unit: String?
  public let unknown: Int
  public let captured: String

  init(_ queryResult: Value, chart: VisualChart) throws {
    try require(
      queryResult["hasMore"] == .bool(false), "visual_chart_coverage",
      "The chart query has more than the selected limit. Filter or aggregate it to show the complete result."
    )
    let columns = queryResult["columns"].array
    guard let measure = columns.first(where: { $0["id"].string == chart.y }),
      ["decimal", "integer"].contains(measure["type"].text)
    else {
      throw SevraError("visual_chart_type", "Choose a decimal quantity or count as the measure.")
    }
    let dimension = columns.first { $0["id"].string == chart.x }?["type"].text
    let isTemporal = dimension == "date" && [.bar, .stackedBar, .line, .area].contains(chart.style)
    if chart.style == .scatter {
      try require(
        dimension == "decimal" || dimension == "integer",
        "visual_chart_type", "Choose a numeric x field for a scatter plot.")
    }
    var unknown = 0
    var points: [Point] = []
    for (index, row) in queryResult["rows"].array.enumerated() {
      let x = row["values"][chart.x]
      let y = row["values"][chart.y]
      let series = chart.series.map { row["values"][$0].text }
      guard x != .null, y != .null, !x.text.isEmpty, !y.text.isEmpty, series != "" else {
        unknown += 1
        continue
      }
      let amount = try Numbers.decimal(y.text)
      if chart.style == .scatter { _ = try Numbers.decimal(x.text) }
      if isTemporal {
        try require(
          Self.parseInstant(x.text) != nil, "visual_chart_type",
          "A date value could not be plotted.")
      }
      if chart.style == .donut {
        try require(amount >= 0, "visual_chart_values", "A donut needs nonnegative values.")
      }
      try require(
        x.text.utf8.count <= 240 && (series?.utf8.count ?? 0) <= 120,
        "visual_chart_label", "Use shorter group labels or another field.")
      points.append(
        Point(
          id: index, label: x.text, amount: Numbers.string(amount), series: series,
          sourceIDs: row["inputs"].array.compactMap { $0["versionID"].string }))
    }
    if chart.style != .scatter {
      try require(
        Dictionary(grouping: points, by: \.series).values.allSatisfy {
          Set($0.map(\.label)).count == $0.count
        },
        "visual_chart_groups",
        "Select a unique category in each series or aggregate by category and series.")
    }
    try require(
      Set(points.compactMap(\.series)).count <= 6, "visual_chart_series",
      "Filter the chart to six series or fewer.")
    self.points = isTemporal ? points.sorted { $0.label < $1.label } : points
    self.temporal = isTemporal
    self.queryHash = queryResult["queryHash"].text
    self.snapshot = queryResult["snapshot"].text
    self.scope = queryResult["sourceScopes"]
    self.unit = measure["unit"].string
    self.unknown = unknown
    self.captured = timestamp()
  }

  public static func parseInstant(_ value: String) -> Date? {
    try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value)
  }

  public func validate() throws {
    try require(
      points.count <= 100 && unknown >= 0 && points.count + unknown <= 100
        && Set(points.map(\.id)).count == points.count && queryHash.utf8.count <= 128
        && snapshot.utf8.count <= 128 && scope.array.count <= 3
        && points.allSatisfy({ point in
          point.label.utf8.count <= 240 && point.amount.utf8.count <= 256
            && (point.series?.utf8.count ?? 0) <= 120
            && (try? Numbers.decimal(point.amount)) != nil && point.sourceIDs.count <= 3
            && (temporal != true || Self.parseInstant(point.label) != nil)
            && point.sourceIDs.allSatisfy { $0.utf8.count <= 256 }
        }),
      "visual_chart", "The saved chart exceeds its bounds.")
  }
}

public struct VisualResult: Codable, Equatable, Sendable {
  public let definition: VisualDefinition
  public let chartData: VisualChartData?
  public let workData: WorkVisualData?

  public var image: ImagePresentation? { definition.image }
  public var chart: VisualChart? { definition.chart }
  public var work: WorkVisual? { definition.work }

  public init(
    definition: VisualDefinition, chartData: VisualChartData? = nil, workData: WorkVisualData? = nil
  ) {
    self.definition = definition
    self.chartData = chartData
    self.workData = workData
  }

  public func sourceForInspection(_ requested: String?) throws -> String {
    if let source = image?.reference.sourceID, requested == nil || requested == source {
      return source
    }
    if let requested,
      chartData?.points.contains(where: { $0.sourceIDs.contains(requested) }) == true
        || workData?.records.contains(where: { $0.id == requested }) == true
    {
      return requested
    }
    throw SevraError("visual_source", "Choose a source version referenced by this capture.")
  }

  func validate() throws {
    try definition.validate()
    try require(
      (definition.kind == .chart) == (chartData != nil), "visual", "Mismatched visual capture.")
    try require(
      (definition.kind == .work) == (workData != nil), "visual", "Mismatched work capture.")
    try chartData?.validate()
    try workData?.validate()
  }
}

extension Workbook {
  public func chartData(_ chart: VisualChart, cancellation: Cancellation = .init()) throws
    -> VisualChartData
  {
    try chart.validate()
    return try VisualChartData(queryDataset(chart.query, cancellation: cancellation), chart: chart)
  }

  public func nativeAppVisual(_ access: NativeAppAccess, view: String) throws -> VisualResult {
    guard let definition = access.package.views?[view] else {
      throw SevraError("visual", "Choose a declared app view.")
    }
    if let chart = definition.chart {
      let result = try nativeAppQuery(access, request: chart.query)
      return try VisualResult(
        definition: definition, chartData: VisualChartData(result, chart: chart))
    }
    if let work = definition.work {
      let result = try nativeAppQuery(access, request: work.query)
      return try VisualResult(definition: definition, workData: WorkVisualData(result, work: work))
    }
    throw SevraError("visual", "This app view is unsupported.")
  }

  public func nativeAppChart(_ access: NativeAppAccess, view: String) throws -> VisualChartData {
    guard let chart = access.package.views?[view]?.chart else {
      throw SevraError("visual_chart", "Choose a declared app view.")
    }
    return try VisualChartData(nativeAppQuery(access, request: chart.query), chart: chart)
  }
}
