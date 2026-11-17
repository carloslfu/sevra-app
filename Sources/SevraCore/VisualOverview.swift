import Foundation

/// Several related readings of one workbook snapshot.
public struct VisualOverview: Codable, Equatable, Sendable {
  public let title: String
  public let panels: [VisualChart]
  public let columns: Int?

  public static func parse(_ value: Value) throws -> Self {
    try require(
      Set(value.object.keys).isSubset(of: ["title", "panels", "columns"]),
      "visual_overview", "Use the declared overview fields.")
    let panels = try value["panels"].array.map(VisualChart.parse)
    let overview = Self(title: value["title"].text, panels: panels, columns: value["columns"].int)
    try require(
      value["columns"] == .null || overview.columns != nil, "visual_overview",
      "Choose a whole number of columns.")
    try overview.validate()
    return overview
  }

  func validate(appAliases: Set<String>? = nil) throws {
    try require(
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && title.utf8.count <= 120 && (2...8).contains(panels.count)
        && (1...3).contains(columns ?? 2), "visual_overview",
      "Give the overview a title, two to eight panels and one to three columns.")
    for panel in panels {
      try panel.validate(appAliases: appAliases)
      try require(
        panel.links?.isEmpty ?? true, "visual_overview",
        "Linked filters must name individual declared app views.")
    }
  }
}

extension Workbook {
  public func overviewData(
    _ overview: VisualOverview, capture: Bool = false,
    cancellation: Cancellation = .init()
  ) throws -> [VisualChartData] {
    try overview.validate()
    let results = try queryDatasetSet(
      overview.panels.map(\.query), captureLineage: capture,
      cancellation: cancellation)
    return try overviewPanels(
      overview, results: results, capture: capture, cancellation: cancellation)
  }

  func overviewPanels(
    _ overview: VisualOverview, results: [Value], capture: Bool, cancellation: Cancellation,
    commitGuard: (() throws -> Void)? = nil
  ) throws -> [VisualChartData] {
    // Validate the complete set before saving any lineage.
    _ = try zip(overview.panels, results).map { try VisualChartData($1, chart: $0) }
    return try zip(overview.panels, results).map { chart, result in
      if capture {
        return try capturedChartData(
          result, chart: chart, cancellation: cancellation, commitGuard: commitGuard)
      }
      return try VisualChartData(result, chart: chart)
    }
  }
}
