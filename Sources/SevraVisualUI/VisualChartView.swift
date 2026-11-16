import Charts
import SevraCore
import SwiftUI

public struct VisualChartView: View {
  let definition: VisualChart
  let data: VisualChartData
  let openOriginal: ((String) -> Void)?
  let showsInspection: Bool
  @State private var showExact = false

  public init(
    definition: VisualChart, data: VisualChartData, showsInspection: Bool = true,
    openOriginal: ((String) -> Void)? = nil
  ) {
    self.definition = definition
    self.data = data
    self.openOriginal = openOriginal
    self.showsInspection = showsInspection
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(definition.title).font(.headline).accessibilityAddTraits(.isHeader)
      if data.points.isEmpty
        || (definition.style == .donut && data.points.allSatisfy { Double($0.amount) == 0 })
      {
        Text("No plottable values for this query.").foregroundStyle(.secondary).font(.callout)
      } else {
        Chart {
          ForEach(data.points) { point in
            marks(point)
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
            || data.temporal == true
          {
            AxisMarks()
          } else if definition.style != .donut && data.points.count <= 10 {
            AxisMarks { _ in AxisValueLabel(collisionResolution: .greedy) }
          }
        }
        .chartLegend(
          definition.series != nil || (definition.style == .donut && data.points.count <= 8)
            ? .visible : .hidden
        )
        .chartForegroundStyleScale(domain: seriesDomain, range: seriesColors)
        .frame(height: 195)
        .accessibilityLabel(definition.title)
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
      if showsInspection { exactValues }
    }
  }

  @ChartContentBuilder private func marks(_ point: VisualChartData.Point) -> some ChartContent {
    let value = Double(point.amount) ?? 0
    let measure = data.unit.map { definition.y + " (" + $0 + ")" } ?? definition.y
    let amount = PlottableValue.value(measure, value)
    if data.temporal == true, let instant = VisualChartData.parseInstant(point.label) {
      let time = PlottableValue.value(definition.x, instant)
      if let series = point.series {
        seriesMarks(x: time, y: amount, series: series)
      } else if definition.style == .bar {
        BarMark(x: time, y: amount)
      } else {
        if data.unknown == 0 {
          if definition.style == .line { LineMark(x: time, y: amount) }
          if definition.style == .area { AreaMark(x: time, y: amount) }
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

  private var seriesDomain: [String] {
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

  private var exactValues: some View {
    DisclosureGroup("Exact values and sources", isExpanded: $showExact) {
      if showExact {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(data.points) { point in
              HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(point.label)
                  if let series = point.series {
                    Text(series).font(.caption).foregroundStyle(.secondary)
                  }
                }
                Spacer()
                Text([point.amount, data.unit].compactMap { $0 }.joined(separator: " "))
                  .monospacedDigit().textSelection(.enabled)
                if let openOriginal {
                  ForEach(Array(point.sourceIDs.enumerated()), id: \.offset) { i, id in
                    Button {
                      openOriginal(id)
                    } label: {
                      Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain).accessibilityLabel(
                      "Open source \(i + 1) for " + point.label)
                  }
                }
              }
              Divider()
            }
          }.padding(.vertical, 8)
        }.frame(maxHeight: 240)
      }
    }.font(.callout)
  }
}

public struct LiveVisualChartView: View {
  let definition: VisualChart
  let revision: String
  let load: @MainActor () async throws -> VisualChartData
  let openOriginal: ((String) -> Void)?
  @State private var data: VisualChartData?
  @State private var loadedDefinition: VisualChart?
  @State private var error: String?

  public init(
    definition: VisualChart, revision: String,
    load: @escaping @MainActor () async throws -> VisualChartData,
    openOriginal: ((String) -> Void)? = nil
  ) {
    self.definition = definition
    self.revision = revision
    self.load = load
    self.openOriginal = openOriginal
  }

  public var body: some View {
    Group {
      if let error {
        Label(error, systemImage: "chart.bar.xaxis").font(.callout).foregroundStyle(.secondary)
      } else if let data, loadedDefinition == definition {
        VisualChartView(definition: definition, data: data, openOriginal: openOriginal)
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
