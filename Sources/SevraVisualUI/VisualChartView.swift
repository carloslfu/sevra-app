import Charts
import SevraCore
import SwiftUI

public struct VisualChartView: View {
  let definition: VisualChart
  let data: VisualChartData
  let openOriginal: ((String) -> Void)?
  let showsInspection: Bool
  let compact: Bool
  let onSelect: ((VisualChartData.Point?) -> Void)?
  let selected: VisualChartData.Point?
  let loadSources: ((Int, Int) async throws -> Value)?
  @State private var pointSources: VisualChartData.Point?
  @State private var showExact = false

  public init(
    definition: VisualChart, data: VisualChartData, showsInspection: Bool = true,
    compact: Bool = false,
    openOriginal: ((String) -> Void)? = nil,
    onSelect: ((VisualChartData.Point?) -> Void)? = nil, selected: VisualChartData.Point? = nil,
    loadSources: ((Int, Int) async throws -> Value)? = nil
  ) {
    self.definition = definition
    self.data = data
    self.openOriginal = openOriginal
    self.showsInspection = showsInspection
    self.compact = compact
    self.onSelect = onSelect
    self.selected = selected
    self.loadSources = loadSources
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(definition.title).font(.headline).accessibilityAddTraits(.isHeader)
      if let periods = definition.periods {
        metric(periods)
      } else if definition.style == .table || definition.style == .records {
        exactRows
      } else if data.points.isEmpty
        || (definition.style == .donut && data.points.allSatisfy { Double($0.amount) == 0 })
      {
        Text("No plottable values for this query.").foregroundStyle(.secondary).font(.callout)
      } else {
        let segments = temporalSegments
        Chart {
          ForEach(data.points) { point in
            marks(point, segment: segments[point.id])
          }
          if let threshold = definition.threshold, let value = Double(threshold) {
            if definition.style == .horizontalBar {
              RuleMark(x: .value("Threshold", value)).lineStyle(StrokeStyle(dash: [4, 4]))
            } else {
              RuleMark(y: .value("Threshold", value)).lineStyle(StrokeStyle(dash: [4, 4]))
            }
          }
        }
        .chartXAxis {
          if definition.style == .scatter || definition.style == .horizontalBar
            || definition.style == .histogram || data.temporal == true
          {
            AxisMarks()
          } else if definition.style != .donut && data.points.count <= 10 {
            AxisMarks { _ in AxisValueLabel(collisionResolution: .greedy) }
          }
        }
        .chartLegend(
          (definition.series != nil && definition.style != .heatmap)
            || (definition.style == .donut && data.points.count <= 8)
            ? .visible : .hidden
        )
        .chartForegroundStyleScale(domain: seriesDomain, range: seriesColors)
        .frame(height: 195)
        .accessibilityLabel(definition.title)
      }
      if definition.style == .heatmap,
        let low = data.points.min(by: { (Double($0.amount) ?? 0) < (Double($1.amount) ?? 0) }),
        let high = data.points.max(by: { (Double($0.amount) ?? 0) < (Double($1.amount) ?? 0) })
      {
        Text("Color scale: " + low.amount + " to " + high.amount)
          .font(.caption).foregroundStyle(.secondary)
      }
      if let bin = data.binWidth, definition.style == .histogram {
        Text("Bin width " + bin + ". Each bin includes its lower edge.")
          .font(.caption).foregroundStyle(.secondary)
      }
      if let unit = data.unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
      if let threshold = definition.threshold {
        Text("Threshold " + [threshold, data.unit].compactMap { $0 }.joined(separator: " "))
          .font(.caption).foregroundStyle(.secondary)
      }
      if data.unknown > 0 {
        Text("\(data.unknown) values are missing a category or measure.").font(.caption)
          .foregroundStyle(.secondary)
      }
      if let notes = definition.annotations, !notes.isEmpty {
        ForEach(Array(notes.enumerated()), id: \.offset) { _, annotation in
          let point = annotation.point.flatMap { id in data.points.first { $0.id == id } }
          if annotation.point == nil || point != nil {
            VStack(alignment: .leading, spacing: 3) {
              if let point { Text(point.label).font(.caption.weight(.semibold)) }
              Text(annotation.text).font(.callout).textSelection(.enabled)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
          }
        }
      }
      if let selected, let onSelect {
        HStack {
          Text("Selected " + selected.label).font(.caption)
          Button("Clear selection") { onSelect(nil) }.buttonStyle(.link).font(.caption)
        }
      }
      if showsInspection && ![.table, .records].contains(definition.style) { exactValues }
    }
    .onChange(of: [data.snapshot, data.queryHash]) { _, _ in pointSources = nil }
    .popover(item: $pointSources) { point in
      if let loadSources, let openOriginal {
        ChartSourcePage(point: point, load: loadSources) { source in
          pointSources = nil
          openOriginal(source)
        }
      }
    }
  }

  @ChartContentBuilder private func marks(_ point: VisualChartData.Point, segment: Int?)
    -> some ChartContent
  {
    let value = Double(point.amount) ?? 0
    let measure = data.unit.map { definition.y + " (" + $0 + ")" } ?? definition.y
    let amount = PlottableValue.value(measure, value)
    if definition.style == .heatmap, let group = point.series {
      let minimum = data.points.compactMap { Double($0.amount) }.min() ?? 0
      let maximum = data.points.compactMap { Double($0.amount) }.max() ?? minimum
      let level = maximum > minimum ? (value - minimum) / (maximum - minimum) : 0.5
      RectangleMark(
        x: .value(definition.x, point.label),
        y: .value(definition.series ?? "Group", group)
      )
      .foregroundStyle(Color.accentColor.opacity(0.18 + 0.82 * level))
      .accessibilityLabel(point.label + ", " + group)
      .accessibilityValue(point.amount)
    } else if definition.style == .histogram, let width = data.binWidth.flatMap(Double.init),
      let lower = Double(point.label)
    {
      BarMark(
        xStart: .value(definition.x, lower), xEnd: .value(definition.x, lower + width),
        y: amount)
    } else if data.temporal == true, let instant = VisualChartData.parseInstant(point.label) {
      let time = PlottableValue.value(definition.x, instant)
      if definition.style == .bar || definition.style == .stackedBar {
        if let series = point.series {
          seriesMarks(x: time, y: amount, series: series)
        } else {
          BarMark(x: time, y: amount)
        }
      } else if let series = point.series {
        let color = PlottableValue.value(definition.series ?? "Series", series)
        if let segment {
          LineMark(x: time, y: amount, series: .value("Observed interval", segment))
            .foregroundStyle(by: color)
        }
        PointMark(x: time, y: amount).foregroundStyle(by: color).symbol(by: color)
      } else {
        if let segment {
          if definition.style == .line {
            LineMark(x: time, y: amount, series: .value("Observed interval", segment))
          }
          if definition.style == .area {
            AreaMark(x: time, y: amount, series: .value("Observed interval", segment))
          }
        }
        PointMark(x: time, y: amount)
      }
    } else {
      let category = PlottableValue.value(definition.x, point.label)
      if let series = point.series {
        seriesMarks(x: category, y: amount, series: series)
      } else {
        switch definition.style {
        case .bar, .stackedBar:
          BarMark(x: category, y: amount)
        case .horizontalBar:
          BarMark(x: amount, y: category)
        case .line, .area:
          if data.unknown == 0 {
            if definition.style == .line { LineMark(x: category, y: amount) }
            if definition.style == .area { AreaMark(x: category, y: amount) }
          }
          PointMark(x: category, y: amount)
        case .scatter:
          PointMark(x: .value(definition.x, Double(point.label) ?? 0), y: amount)
        case .histogram, .heatmap, .metric, .table, .records:
          ChartContentBuilder.buildBlock()
        case .donut:
          SectorMark(angle: amount, innerRadius: .ratio(0.62))
            .foregroundStyle(by: category)
        }
      }
    }
  }

  @ChartContentBuilder private func seriesMarks<X: Plottable>(
    x: PlottableValue<X>, y: PlottableValue<Double>, series: String
  ) -> some ChartContent {
    let identity = PlottableValue.value(definition.series ?? "Series", series)
    switch definition.style {
    case .line:
      if data.unknown == 0 {
        LineMark(x: x, y: y, series: identity).foregroundStyle(by: identity)
      }
      PointMark(x: x, y: y).foregroundStyle(by: identity).symbol(by: identity)
    case .stackedBar:
      BarMark(x: x, y: y, stacking: .standard).foregroundStyle(by: identity)
    default:
      BarMark(x: x, y: y).position(by: identity).foregroundStyle(by: identity)
    }
  }

  // Only connect adjacent observed buckets. Raw timestamps have no declared cadence.
  private var temporalSegments: [Int: Int] {
    guard data.temporal == true && [.line, .area].contains(definition.style),
      let cadence = data.cadence
    else { return [:] }
    let components: [String: Calendar.Component] =
      ["day": .day, "week": .weekOfYear, "month": .month, "year": .year]
    guard let component = components[cadence] else { return [:] }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var segments: [Int: Int] = [:]
    var previous: [String: (date: Date, segment: Int)] = [:]
    for point in data.points {
      guard let current = VisualChartData.parseInstant(point.label) else { continue }
      let series = point.series ?? ""
      let prior = previous[series]
      let segment =
        prior.flatMap {
          calendar.date(byAdding: component, value: 1, to: $0.date) == current ? $0.segment : nil
        } ?? point.id
      previous[series] = (current, segment)
      segments[point.id] = segment
    }
    return segments
  }

  private var seriesDomain: [String] {
    if definition.style == .heatmap { return [] }
    let categories =
      definition.style == .donut ? data.points.map(\.label) : data.points.compactMap(\.series)
    return Set(categories).sorted()
  }

  private var seriesColors: [Color] {
    let palette: [Color] = [
      .blue, .orange, .teal, .purple, .pink, .indigo, .green, .brown, .cyan, .mint,
    ]
    return seriesDomain.map { label in
      let index = label.utf8.reduce(0) { ($0 * 31 + Int($1)) % palette.count }
      return palette[index]
    }
  }

  private func metric(_ periods: VisualChart.Periods) -> some View {
    let change = data.comparison(periods)
    let suffix = data.unit.map { " " + $0 } ?? ""
    return VStack(alignment: .leading, spacing: 6) {
      Text(
        data.points.first(where: { $0.label == periods.current.key }).map {
          $0.amount + suffix
        } ?? "Unavailable"
      )
      .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
      .textSelection(.enabled)
      Text(periodLabel(periods.current)).font(.caption).foregroundStyle(.secondary)
      if let baseline = periods.baseline {
        Text("Baseline " + periodLabel(baseline)).font(.caption).foregroundStyle(.secondary)
      }
      if let amount = change.amount {
        Text("Change " + amount + suffix + (change.percent.map { " (" + $0 + "%)" } ?? ""))
          .font(.callout).monospacedDigit().textSelection(.enabled)
      }
      if let note = change.note { Text(note).font(.caption).foregroundStyle(.secondary) }
    }
  }

  private func periodLabel(_ period: VisualChart.Periods.Window) -> String {
    period.start + " to " + (period.observedThrough ?? period.end) + " (end exclusive)"
  }

  private var exactValues: some View {
    DisclosureGroup("Exact values and sources", isExpanded: $showExact) {
      if showExact { exactRows }
    }.font(.callout)
  }

  private var exactRows: some View {
    VStack(alignment: .leading, spacing: 4) {
      if compact {
        rows(data.points.prefix(8))
        if data.points.count > 8 {
          Text("Showing 8 of \(data.points.count). Expand to see all values.")
            .font(.caption).foregroundStyle(.secondary)
        }
      } else {
        ScrollView { rows(data.points[...]) }.frame(maxHeight: 240)
      }
    }
  }

  private func rows(_ points: ArraySlice<VisualChartData.Point>) -> some View {
    LazyVStack(alignment: .leading, spacing: 7) {
      if data.points.isEmpty {
        Text("No matching values.").font(.callout).foregroundStyle(.secondary)
      }
      ForEach(points) { point in
        if definition.style == .records {
          VStack(alignment: .leading, spacing: 4) {
            Text(point.label).font(.callout.weight(.semibold))
            exactAmount(point)
          }
        } else {
          ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
              Text(point.label).lineLimit(1).truncationMode(.middle)
                .frame(minWidth: 70, alignment: .leading)
              Spacer(minLength: 8)
              exactAmount(point)
            }
            VStack(alignment: .leading, spacing: 4) {
              Text(point.label)
              exactAmount(point)
            }
          }
        }
        Divider()
      }
    }.padding(.vertical, 8)
  }

  private func exactAmount(_ point: VisualChartData.Point) -> some View {
    let threshold = definition.threshold.flatMap(Double.init)
    return HStack(spacing: 9) {
      if definition.dataBars == true, let value = Double(point.amount) {
        let largest = max(
          abs(data.points.compactMap { Double($0.amount) }.min() ?? 0),
          abs(data.points.compactMap { Double($0.amount) }.max() ?? 0))
        if largest > 0 {
          let width = min(36, max(0, 36 * abs(value) / largest))
          HStack(spacing: 0) {
            Capsule().fill(value < 0 ? Color.accentColor : .clear)
              .frame(width: CGFloat(width), height: 5)
              .frame(width: 36, alignment: .trailing)
            Rectangle().fill(.secondary.opacity(0.3)).frame(width: 1, height: 9)
            Capsule().fill(value > 0 ? Color.accentColor : .clear)
              .frame(width: CGFloat(width), height: 5)
              .frame(width: 36, alignment: .leading)
          }.accessibilityHidden(true)
        }
      }
      if let series = point.series { Text(series).font(.caption).foregroundStyle(.secondary) }
      Text([point.amount, data.unit].compactMap { $0 }.joined(separator: " "))
        .monospacedDigit().textSelection(.enabled)
      if definition.style == .table, let threshold, let amount = Double(point.amount),
        amount > threshold
      {
        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
          .accessibilityLabel("Above threshold")
      }
      if let onSelect {
        Button {
          onSelect(point)
        } label: {
          Image(systemName: selected == point ? "checkmark.circle.fill" : "scope")
        }.buttonStyle(.plain).help("Filter linked views by " + point.label)
          .accessibilityLabel("Filter linked views by " + point.label)
      }
      if loadSources != nil && openOriginal != nil && point.sourceIDs.isEmpty {
        Button {
          pointSources = point
        } label: {
          Image(systemName: "list.bullet.rectangle")
        }.buttonStyle(.plain)
          .help("Inspect sources for " + point.label)
          .accessibilityLabel("Inspect sources for " + point.label)
      }
      if let openOriginal {
        ForEach(Array(point.sourceIDs.enumerated()), id: \.offset) { i, id in
          Button {
            openOriginal(id)
          } label: {
            Image(systemName: "arrow.up.right.square")
          }
          .buttonStyle(.plain).accessibilityLabel("Open source \(i + 1) for " + point.label)
        }
      }
    }
  }

}

private struct ChartSourcePage: View {
  let point: VisualChartData.Point
  let load: (Int, Int) async throws -> Value
  let open: (String) -> Void
  @State private var offset = 0
  @State private var page: Value = .null
  @State private var failure: String?
  @State private var loading = true

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(point.label).font(.headline)
      if let failure { Label(failure, systemImage: "exclamationmark.circle") }
      if loading { ProgressView("Loading sources…").controlSize(.small) }
      if page != .null {
        let rows = page["rows"].array
        Text("Rows \(offset + 1)–\(offset + rows.count) of \(page["total"].int ?? 0)")
          .font(.caption).foregroundStyle(.secondary)
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
              ForEach(Array(row.array.enumerated()), id: \.offset) { column, source in
                if let id = source.string {
                  Button("Open source \(offset + index + 1)" + (column == 0 ? "" : " (joined)")) {
                    open(id)
                  }
                  .buttonStyle(.link)
                }
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(idealHeight: 160, maxHeight: 240)
        HStack {
          Button("Previous") { offset = max(0, offset - 25) }.disabled(loading || offset == 0)
          Button("Next") { if let next = page["nextOffset"].int { offset = next } }
            .disabled(loading || page["nextOffset"] == .null)
        }
      }
    }
    .padding(14)
    .frame(width: 300)
    .task(id: offset) {
      loading = true
      page = .null
      failure = nil
      do {
        let response = try await load(point.id, offset)
        try Task.checkCancellation()
        page = response
        failure = nil
      } catch {
        guard !Task.isCancelled else { return }
        page = .null
        failure = error.localizedDescription
      }
      loading = false
    }
  }
}

public struct LiveVisualChartView: View {
  let definition: VisualChart
  let revision: String
  let load: @MainActor () async throws -> VisualChartData
  let loadSources: ((VisualChartData, Int, Int) async throws -> Value)?
  let openOriginal: ((String) -> Void)?
  @State private var data: VisualChartData?
  @State private var loadedDefinition: VisualChart?
  @State private var error: String?

  public init(
    definition: VisualChart, revision: String,
    load: @escaping @MainActor () async throws -> VisualChartData,
    openOriginal: ((String) -> Void)? = nil,
    loadSources: ((VisualChartData, Int, Int) async throws -> Value)? = nil
  ) {
    self.definition = definition
    self.revision = revision
    self.load = load
    self.loadSources = loadSources
    self.openOriginal = openOriginal
  }

  public var body: some View {
    Group {
      if let error {
        Label(error, systemImage: "chart.bar.xaxis").font(.callout).foregroundStyle(.secondary)
      } else if let data, loadedDefinition == definition {
        VisualChartView(
          definition: definition, data: data, openOriginal: openOriginal,
          loadSources: loadSources.map { resolve in { try await resolve(data, $0, $1) } })
      } else {
        ProgressView("Loading chart…").frame(minHeight: 195)
      }
    }
    .task(id: revision + "/" + ((try? encoded(definition).json()) ?? "")) {
      error = nil
      do {
        let current = try await load()
        try Task.checkCancellation()
        data = current
        loadedDefinition = definition
      } catch {
        guard !Task.isCancelled else { return }
        data = nil
        self.error = error.localizedDescription
      }
    }
  }
}
