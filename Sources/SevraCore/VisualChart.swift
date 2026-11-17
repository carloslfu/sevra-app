import Foundation

public struct VisualChart: Codable, Equatable, Sendable {
  public enum Style: String, Codable, Sendable {
    case bar, horizontalBar, stackedBar, line, area, scatter, donut, histogram, heatmap
    case metric, table, records
  }
  public let title: String
  public let style: Style
  public let query: Value
  public let x: String
  public let y: String
  public let threshold: String?
  public let series: String?
  public let periods: Periods?
  public let links: [SelectionLink]?
  public let annotations: [Annotation]?
  public let dataBars: Bool?

  public struct Annotation: Codable, Equatable, Sendable {
    public let text: String
    public let point: Int?
  }

  public struct SelectionLink: Codable, Equatable, Sendable {
    public let viewID: String
    public let field: String
    public let filterIndex: Int
  }

  public struct Periods: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
      public let key: String
      public let start: String
      public let end: String
      public let observedThrough: String?

      func length() throws -> (planned: TimeInterval, observed: TimeInterval) {
        guard let startDate = WorkVisual.date(start), let endDate = WorkVisual.date(end),
          let actual = WorkVisual.date(observedThrough ?? end),
          startDate < endDate, startDate < actual, actual <= endDate,
          !key.isEmpty, key.utf8.count <= 160
        else { throw SevraError("visual_metric", "Use an ordered, half-open reporting period.") }
        return (endDate.timeIntervalSince(startDate), actual.timeIntervalSince(startDate))
      }
    }
    public let current: Window
    public let baseline: Window?
  }

  public init(
    title: String, style: Style, query: Value, x: String, y: String, threshold: String? = nil,
    series: String? = nil, periods: Periods? = nil, links: [SelectionLink]? = nil,
    annotations: [Annotation]? = nil, dataBars: Bool? = nil
  ) {
    self.title = title
    self.style = style
    self.query = query
    self.x = x
    self.y = y
    self.threshold = threshold
    self.series = series
    self.periods = periods
    self.links = links
    self.annotations = annotations
    self.dataBars = dataBars
  }

  static func parse(_ value: Value) throws -> Self {
    _ = try queryObject(
      value,
      keys: [
        "title", "style", "query", "x", "y", "threshold", "series", "periods", "links",
        "annotations",
      ])
    var descriptor = value.object
    var query = value["query"].object
    if query["limit"] == nil { query["limit"] = .number(100) }
    if query["groupBy"] == nil
      && value["query"]["select"].array.contains(where: { $0["aggregate"] != .null })
    {
      let fields = value["query"]["select"].array.filter { $0["aggregate"] == .null }.map {
        $0["column"]
      }
      if !fields.isEmpty { query["groupBy"] = .array(fields) }
    }
    descriptor["query"] = .object(query)
    let definition = try JSONDecoder().decode(
      Self.self, from: Data(Value.object(descriptor).json().utf8))
    try definition.validate()
    return definition
  }

  func validate(appAliases: Set<String>? = nil) throws {
    try require(
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.utf8.count <= 200
        && x != y && query.json().utf8.count <= 8192,
      "visual_chart", "Use a short title, two distinct output fields and a bounded typed query.")
    try require(
      dataBars != true || style == .table, "visual_chart",
      "Data bars require an exact numeric table.")
    if let annotations {
      try require(
        annotations.count <= 6
          && annotations.allSatisfy {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              && $0.text.utf8.count <= 400
              && ($0.point.map { (0..<100).contains($0) } ?? true)
          }, "visual_chart", "Use up to six short annotations attached to optional point indices.")
    }
    if let links {
      try require(
        appAliases != nil && links.count <= 6
          && Set(links.map { $0.viewID + "/" + String($0.filterIndex) }).count == links.count
          && links.allSatisfy {
            ["x", "series"].contains($0.field) && ($0.field != "series" || series != nil)
          },
        "visual_links", "Link a declared app chart field to a distinct target filter.")
    }
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
      (![.stackedBar, .heatmap].contains(style) || series != nil)
        && (series == nil || [.bar, .line, .stackedBar, .heatmap].contains(style)),
      "visual_chart",
      "Choose grouped bars, stacked bars, lines or a heatmap for a second dimension.")
    try require(
      !contract.grouped || contract.joins.allSatisfy(\.manyToOne), "query_join",
      "Aggregates over joins require an asserted manyToOne relationship.")
    if style == .histogram {
      let selected = contract.selections.first { $0.id == x }?.column
      try require(
        selected.flatMap { contract.projections[$0]?.bin } != nil
          && contract.selections.first { $0.id == y }?.aggregate == "countRows",
        "visual_chart", "A histogram needs explicit decimal bins and a count of rows.")
    }
    if [.histogram, .heatmap, .metric, .records].contains(style) {
      try require(threshold == nil, "visual_chart", "This chart does not display a threshold.")
    }
    if let periods {
      try require(
        style == .metric && series == nil && periods.current.key != periods.baseline?.key
          && contract.grouped && contract.limit >= (periods.baseline == nil ? 1 : 2),
        "visual_metric", "A period comparison needs distinct keyed aggregates.")
      _ = try periods.current.length()
      _ = try periods.baseline?.length()
    } else {
      try require(style != .metric, "visual_metric", "Declare the metric’s reporting period.")
    }
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
        let source = try queryObject(source, keys: ["table", "scope", "excelRows"])
        guard let alias = source["table"]?.string, appAliases.contains(alias) else {
          throw SevraError(
            "visual_chart", "Chart sources must use the app’s declared dataset aliases.")
        }
        var normalized = source
        normalized.removeValue(forKey: "table")
        normalized["datasetID"] = .string(alias)
        normalized["definitionID"] = .string(alias)
        return .object(normalized)
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
  public let manifestID: String?
  public let binWidth: String?
  public let cadence: String?
  public let revision: Int?
  public let valueType: String?

  init(_ queryResult: Value, chart: VisualChart, manifestID: String? = nil) throws {
    try require(
      queryResult["hasMore"] == .bool(false), "visual_chart_coverage",
      "The chart query has more than the selected limit. Filter or aggregate it to show the complete result."
    )
    let columns = queryResult["columns"].array
    guard let measure = columns.first(where: { $0["id"].string == chart.y }),
      ["decimal", "integer"].contains(measure["type"].text) || chart.style == .records
    else {
      throw SevraError("visual_chart_type", "Choose a decimal quantity or count as the measure.")
    }
    let numeric = ["decimal", "integer"].contains(measure["type"].text)
    let dimension = columns.first { $0["id"].string == chart.x }?["type"].text
    let isTemporal = dimension == "date" && [.bar, .stackedBar, .line, .area].contains(chart.style)
    if [.scatter, .histogram].contains(chart.style) {
      try require(
        dimension == "decimal" || dimension == "integer",
        "visual_chart_type", "Choose a numeric x field for this chart.")
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
      let amount = try numeric ? Numbers.decimal(y.text) : nil
      if [.scatter, .histogram].contains(chart.style) { _ = try Numbers.decimal(x.text) }
      if isTemporal {
        try require(
          Self.parseInstant(x.text) != nil, "visual_chart_type",
          "A date value could not be plotted.")
      }
      if chart.style == .donut {
        try require((amount ?? 0) >= 0, "visual_chart_values", "A donut needs nonnegative values.")
      }
      try require(
        x.text.utf8.count <= 240 && (series?.utf8.count ?? 0) <= 120,
        "visual_chart_label", "Use shorter group labels or another field.")
      points.append(
        Point(
          id: index, label: x.text, amount: amount.map(Numbers.string) ?? y.text, series: series,
          sourceIDs: row["inputs"].array.compactMap { $0["versionID"].string }))
    }
    if ![.scatter, .table, .records].contains(chart.style) {
      try require(
        Dictionary(grouping: points, by: \.series).values.allSatisfy {
          Set($0.map(\.label)).count == $0.count
        },
        "visual_chart_groups",
        "Select a unique category in each series or aggregate by category and series.")
    }
    try require(
      chart.style == .heatmap || Set(points.compactMap(\.series)).count <= 6, "visual_chart_series",
      "Filter the chart to six series or fewer.")
    // Reject coordinates that lose sign, become nonfinite, or collapse exact
    // distinct values onto the same number on the same numeric axis.
    func coordinates(_ values: [String]) throws {
      var seen: [Double: String] = [:]
      for value in values {
        let exact = try Numbers.decimal(value)
        guard let coordinate = Double(value), coordinate.isFinite, exact == 0 || coordinate != 0,
          seen[coordinate] == nil || seen[coordinate] == value
        else {
          throw SevraError(
            "visual_chart_precision",
            "These exact values cannot be distinguished on the chart. Use a scaled unit or an exact table."
          )
        }
        seen[coordinate] = value
      }
    }
    if ![.metric, .table, .records].contains(chart.style) {
      try coordinates(
        points.map(\.amount)
          + (try chart.threshold.map {
            [Numbers.string(try Numbers.decimal($0))]
          } ?? []))
    }
    if let periods = chart.periods {
      let keys = [periods.current.key, periods.baseline?.key].compactMap { $0 }
      try require(
        points.allSatisfy { keys.contains($0.label) }, "visual_metric",
        "The result contains data outside the named reporting periods.")
    }
    if [.scatter, .histogram].contains(chart.style) { try coordinates(points.map(\.label)) }
    let aliases = Set(chart.query["sources"].array.compactMap { $0["table"].string })
    let query = try visualQuery(chart.query, appAliases: aliases.isEmpty ? nil : aliases)
    let projection = query.selections.first { $0.id == chart.x }?.column.flatMap {
      query.projections[$0]
    }
    self.binWidth = projection?.bin.map(Numbers.string)
    self.cadence = isTemporal ? projection?.bucket : nil
    self.revision = queryResult["revision"].int
    self.valueType = measure["type"].string
    self.manifestID = manifestID
    self.points = isTemporal ? points.sorted { $0.label < $1.label } : points
    self.temporal = isTemporal
    self.queryHash = queryResult["queryHash"].text
    self.snapshot = queryResult["snapshot"].text
    self.scope = queryResult["sourceScopes"]
    self.unit = measure["unit"].string
    self.unknown = unknown
    self.captured = timestamp()
  }

  public func comparison(_ periods: VisualChart.Periods) -> (
    amount: String?, percent: String?, note: String?
  ) {
    guard let baseline = periods.baseline else { return (nil, nil, nil) }
    guard let current = try? periods.current.length(), let prior = try? baseline.length(),
      current.planned == prior.planned, current.observed == prior.observed
    else { return (nil, nil, "The reporting periods cover different lengths.") }
    guard let currentValue = points.first(where: { $0.label == periods.current.key })?.amount,
      let baselineValue = points.first(where: { $0.label == baseline.key })?.amount,
      let lhs = try? Numbers.decimal(currentValue), let rhs = try? Numbers.decimal(baselineValue),
      let delta = try? Numbers.binary(lhs, rhs, op: "-")
    else { return (nil, nil, "An exact value is unavailable for one of these periods.") }
    guard rhs > 0 else {
      return (Numbers.string(delta), nil, "Percent change requires a positive baseline.")
    }
    guard let ratio = try? Numbers.binary(delta, rhs, op: "/"),
      var raw = try? Numbers.binary(ratio, 100, op: "*")
    else { return (Numbers.string(delta), nil, "Percent change exceeds the available range.") }
    var percent = Decimal()
    NSDecimalRound(&percent, &raw, 2, .plain)
    return (Numbers.string(delta), Numbers.string(percent), nil)
  }

  public static func parseInstant(_ value: String) -> Date? {
    try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value)
  }

  public var isTextValue: Bool {
    valueType.map { !["decimal", "integer"].contains($0) } ?? false
  }

  public func validate() throws {
    try require(
      points.count <= 100 && unknown >= 0 && points.count + unknown <= 100
        && Set(points.map(\.id)).count == points.count && queryHash.utf8.count <= 128
        && snapshot.utf8.count <= 128 && scope.array.count <= 3
        && (manifestID?.utf8.count ?? 0) <= 128
        && (binWidth.map { ((try? Numbers.decimal($0)) ?? 0) > 0 } ?? true)
        && points.allSatisfy({ point in
          point.label.utf8.count <= 240 && point.amount.utf8.count <= 256
            && (point.series?.utf8.count ?? 0) <= 120
            && (isTextValue || (try? Numbers.decimal(point.amount)) != nil)
            && point.sourceIDs.count <= 3
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
  public let diagramData: VisualDiagramData?
  public let appReference: VisualAppReference?
  public let overviewData: [VisualChartData]?
  public let thumbnailReferences: [String: ImageReference]?

  public var image: ImagePresentation? { definition.image }
  public var chart: VisualChart? { definition.chart }
  public var work: WorkVisual? { definition.work }
  public var diagram: VisualDiagram? { definition.diagram }
  public var overview: VisualOverview? { definition.overview }

  public init(
    definition: VisualDefinition, chartData: VisualChartData? = nil,
    workData: WorkVisualData? = nil,
    diagramData: VisualDiagramData? = nil, appReference: VisualAppReference? = nil,
    overviewData: [VisualChartData]? = nil, thumbnailReferences: [String: ImageReference]? = nil
  ) {
    self.definition = definition
    self.chartData = chartData
    self.workData = workData
    self.diagramData = diagramData
    self.appReference = appReference
    self.overviewData = overviewData
    self.thumbnailReferences = thumbnailReferences
  }

  public func sourceForInspection(_ requested: String?) throws -> String {
    if let source = image?.reference.sourceID, requested == nil || requested == source {
      return source
    }
    if let requested,
      chartData?.points.contains(where: { $0.sourceIDs.contains(requested) }) == true
        || overviewData?.contains(where: { chart in
          chart.points.contains { $0.sourceIDs.contains(requested) }
        }) == true
        || definition.text?.sourceIDs.contains(requested) == true
        || workData?.records.contains(where: { $0.id == requested }) == true
        || diagramData?.nodes.contains(where: { $0.source == requested }) == true
        || diagramData?.edges.contains(where: { $0.source == requested }) == true
    {
      return requested
    }
    throw SevraError("visual_source", "Choose a source version referenced by this capture.")
  }

  func validate() throws {
    var aliases: Set<String>?
    if let appReference {
      try require(
        appReference.version > 0 && appReference.digest.utf8.count == 64
          && appReference.spaceID.utf8.count <= 128 && appReference.viewID.utf8.count <= 64
          && (appReference.presetID?.utf8.count ?? 0) <= 128,
        "visual", "Invalid saved app view reference.")
      aliases = Set(
        definition.queries.flatMap {
          $0["sources"].array.compactMap {
            $0["table"].string
          }
        })
    }
    try definition.validate(appAliases: aliases)
    try require(
      (definition.kind == .chart) == (chartData != nil), "visual", "Mismatched visual capture.")
    try require(
      (definition.kind == .work) == (workData != nil), "visual", "Mismatched work capture.")
    try chartData?.validate()
    try require(
      chartData?.isTextValue != true || chart?.style == .records,
      "visual", "Text readings belong to a record list.")
    try workData?.validate()
    try require(
      (definition.kind == .diagram) == (diagramData != nil), "visual", "Mismatched diagram capture."
    )
    try diagramData?.validate()
    if let positions = diagram?.positions, let diagramData {
      try require(
        Set(positions.keys).isSubset(of: Set(diagramData.nodes.map(\.id))), "visual_diagram",
        "A positioned record is missing from this diagram capture.")
    }
    try require(
      (overview?.panels.count) == (overviewData?.count), "visual", "Mismatched overview capture.")
    if let overview, let overviewData {
      try require(
        Set(overviewData.map(\.snapshot)).count == 1, "visual",
        "The overview has mixed data snapshots.")
      for (panel, data) in zip(overview.panels, overviewData) {
        try data.validate()
        try require(
          !data.isTextValue || panel.style == .records, "visual",
          "Text readings belong to a record list.")
      }
    }
    if let thumbnailReferences {
      try require(
        appReference != nil && work != nil && thumbnailReferences.count <= 8
          && Set(thumbnailReferences.keys).isSubset(
            of: Set(work?.thumbnailAliases?.keys.map { $0 } ?? [])),
        "visual_image", "The capture's image bindings are invalid.")
    }
  }
}

extension Workbook {
  public func chartData(_ chart: VisualChart, cancellation: Cancellation = .init()) throws
    -> VisualChartData
  {
    try chart.validate()
    return try VisualChartData(queryDataset(chart.query, cancellation: cancellation), chart: chart)
  }

  func captureChart(_ chart: VisualChart, cancellation: Cancellation) throws
    -> VisualChartData
  {
    try chart.validate()
    let result = try queryDatasetSet(
      [chart.query], captureLineage: true, cancellation: cancellation)[0]
    return try capturedChartData(result, chart: chart, cancellation: cancellation)
  }

  func capturedChartData(
    _ result: Value, chart: VisualChart, cancellation: Cancellation,
    commitGuard: (() throws -> Void)? = nil
  ) throws -> VisualChartData {
    guard
      result["rows"].array.first?["contributing"] != nil
        && result["rows"].array.first?["contributing"] != .null
    else { return try VisualChartData(result, chart: chart) }
    let manifest: Value = .object([
      "snapshot": result["snapshot"], "queryHash": result["queryHash"],
      "sources": result["sources"],
      "groups": .array(result["rows"].array.map { $0["contributing"] }),
    ])
    _ = try VisualChartData(result, chart: chart)
    try require(
      try manifest.json().utf8.count <= 4 * 1024 * 1024, "visual_lineage_limit",
      "This chart can be viewed live. Filter it before saving a complete source manifest.")
    let identity = ChangeFormat.hash(try manifest.json())
    let id = try mutation(
      "capture_visual_lineage", token: "visual-lineage-" + identity,
      request: .string(identity), cancellation: cancellation, commitGuard: commitGuard
    ) {
      .string(
        try insertItem(
          category: "source", kind: "visual_lineage", title: "Chart source versions",
          text: "Exact contributing versions from one workbook snapshot.", data: manifest,
          meaning: "actual", status: "accepted", scenario: "actual", inputs: [],
          transformation: "visual-lineage-v1", inheritReferenceBindings: false))
    }.text
    return try VisualChartData(result, chart: chart, manifestID: id)
  }

  public func chartGroupSources(
    messageID: String, index: Int, conversation: String, point: Int, offset: Int = 0,
    panel: Int? = nil
  ) throws -> Value {
    try require((0...100_000).contains(offset), "visual_source", "Use a valid source page.")
    let visual = try conversationVisual(messageID, index: index, conversation: conversation)
    let data: VisualChartData?
    if let panel {
      data = visual.overviewData.flatMap { $0.indices.contains(panel) ? $0[panel] : nil }
    } else {
      data = visual.chartData
    }
    guard let chart = data, let row = chart.points.first(where: { $0.id == point })
    else { throw SevraError("visual_source", "Choose a point in the captured chart.") }
    let groups: [Value]
    if let manifestID = chart.manifestID {
      let manifest = try item(manifestID)
      let saved = manifest.data["groups"].array
      try require(
        manifest.id == manifestID && manifest.kind == "visual_lineage"
          && manifest.data["queryHash"] == .string(chart.queryHash)
          && manifest.data["snapshot"] == .string(chart.snapshot) && saved.indices.contains(point),
        "visual_source", "The source manifest for this capture is unavailable.")
      groups = saved[point].array
    } else {
      groups = [.array(row.sourceIDs.map(Value.string))]
    }
    return sourcePage(chart: chart, row: row, groups: groups, offset: offset)
  }

  public func liveChartSources(
    _ chart: VisualChart, snapshot: String, queryHash: String,
    point: Int, offset: Int, cancellation: Cancellation = .init()
  ) throws -> Value {
    try chart.validate()
    let values = try queryDatasetSet(
      [chart.query], captureLineage: true, cancellation: cancellation)[0]
    return try liveChartSourcePage(
      values, chart: chart, snapshot: snapshot, queryHash: queryHash,
      point: point, offset: offset)
  }

  public func nativeAppChartSources(
    _ access: NativeAppAccess, view: String, presetID: String?,
    filters: [Value]?, snapshot: String, queryHash: String, point: Int, offset: Int,
    panel: Int? = nil, cancellation: Cancellation = .init()
  ) throws -> Value {
    let definition = try nativeAppPresentation(
      access, view: view, presetID: presetID, filters: filters)
    let chart = try definition.sourceChart(panel: panel)
    let result = try nativeAppQuerySet(
      access, requests: [chart.query],
      captureLineage: true, cancellation: cancellation)[0]
    return try liveChartSourcePage(
      result, chart: chart, snapshot: snapshot,
      queryHash: queryHash, point: point, offset: offset)
  }

  private func liveChartSourcePage(
    _ result: Value, chart: VisualChart, snapshot: String,
    queryHash: String, point: Int, offset: Int
  ) throws -> Value {
    try require(
      result["snapshot"] == .string(snapshot) && result["queryHash"] == .string(queryHash),
      "visual_source", "The chart changed. Refresh it to inspect its current sources.")
    try require((0...100_000).contains(offset), "visual_source", "Use a valid source page.")
    let data = try VisualChartData(result, chart: chart)
    guard let row = data.points.first(where: { $0.id == point }),
      result["rows"].array.indices.contains(point)
    else { throw SevraError("visual_source", "Choose a point in the chart.") }
    let contributors = result["rows"].array[point]["contributing"]
    let groups =
      contributors == .null ? [Value.array(row.sourceIDs.map(Value.string))] : contributors.array
    return sourcePage(chart: data, row: row, groups: groups, offset: offset)
  }

  private func sourcePage(
    chart: VisualChartData, row: VisualChartData.Point, groups: [Value], offset: Int
  ) -> Value {
    let page = Array(groups.dropFirst(offset).prefix(25))
    return .object([
      "queryHash": .string(chart.queryHash), "snapshot": .string(chart.snapshot),
      "point": .number(Double(row.id)), "label": .string(row.label),
      "total": .number(Double(groups.count)), "rows": .array(page),
      "nextOffset": offset + page.count < groups.count
        ? .number(Double(offset + page.count)) : .null,
    ])
  }

  public func nativeAppVisual(
    _ access: NativeAppAccess, view: String, presetID: String? = nil, capture: Bool = false,
    cursor: String? = nil, filters: [Value]? = nil, cancellation: Cancellation = .init()
  ) throws -> VisualResult {
    let definition = try nativeAppPresentation(
      access, view: view, presetID: presetID, filters: filters)
    let reference = appVisualReference(access, view: view, presetID: presetID)
    if let chart = definition.chart {
      let result = try nativeAppQuerySet(
        access, requests: [chart.query], captureLineage: capture,
        cancellation: cancellation)[0]
      let data =
        capture
        ? try capturedChartData(
          result, chart: chart, cancellation: cancellation,
          commitGuard: { try access.authorized(self) {} })
        : try VisualChartData(result, chart: chart)
      return VisualResult(definition: definition, chartData: data, appReference: reference)
    }
    if let work = definition.work {
      let result = try nativeAppQuerySet(
        access, requests: [work.query], cursor: cursor,
        cancellation: cancellation)[0]
      let data = try WorkVisualData(result, work: work)
      try require(
        !capture || data.nextCursor == nil, "work_view_coverage",
        "Filter this app view before capturing a complete chat answer.")
      let images =
        try capture
        ? work.thumbnailAliases?.mapValues {
          try nativeAppImageReference(access, alias: $0)
        } : nil
      return VisualResult(
        definition: definition, workData: data, appReference: reference,
        thumbnailReferences: images)
    }
    if let diagram = definition.diagram {
      let result = try nativeAppQuerySet(
        access, requests: [diagram.nodes, diagram.edges], cancellation: cancellation)
      let graph = try VisualDiagramData(result, diagram: diagram)
      if capture, let positions = diagram.positions, !positions.isEmpty {
        _ = try graph.layout(positions: positions, cancellation: cancellation)
      }
      return VisualResult(definition: definition, diagramData: graph, appReference: reference)
    }
    if let overview = definition.overview {
      let results = try nativeAppQuerySet(
        access, requests: overview.panels.map(\.query),
        captureLineage: capture, cancellation: cancellation)
      let panels = try overviewPanels(
        overview, results: results, capture: capture, cancellation: cancellation,
        commitGuard: { try access.authorized(self) {} })
      return VisualResult(definition: definition, appReference: reference, overviewData: panels)
    }
    if definition.text != nil {
      return VisualResult(definition: definition, appReference: reference)
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

extension VisualChartData {
  func inspection(offset: Int = 0, limit: Int = 8) -> Value {
    let page = points.dropFirst(max(0, offset)).prefix(limit)
    let end = offset + page.count
    return .object([
      "queryHash": .string(queryHash), "snapshot": .string(snapshot), "scope": scope,
      "unit": unit.map(Value.string) ?? .null, "total": .number(Double(points.count)),
      "unknown": .number(Double(unknown)),
      "nextOffset": end < points.count && !page.isEmpty ? .number(Double(end)) : .null,
      "points": .array(
        page.map { point in
          .object([
            "id": .number(Double(point.id)), "label": .string(point.label),
            "amount": .string(point.amount), "series": point.series.map(Value.string) ?? .null,
          ])
        }),
    ])
  }
}
