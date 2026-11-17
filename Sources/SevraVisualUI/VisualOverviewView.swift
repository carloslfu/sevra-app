import SevraCore
import SwiftUI

public struct VisualOverviewView: View {
  let definition: VisualOverview
  let panels: [VisualChartData]
  let openOriginal: ((String) -> Void)?
  let compact: Bool
  let loadSources: ((Int, VisualChartData, Int, Int) async throws -> Value)?

  public init(
    definition: VisualOverview, panels: [VisualChartData], compact: Bool = false,
    openOriginal: ((String) -> Void)? = nil,
    loadSources: ((Int, VisualChartData, Int, Int) async throws -> Value)? = nil
  ) {
    self.definition = definition
    self.panels = panels
    self.openOriginal = openOriginal
    self.compact = compact
    self.loadSources = loadSources
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(definition.title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
      let columns = definition.columns ?? 2
      ViewThatFits(in: .horizontal) {
        if columns == 3 { grid(columns: 3).frame(minWidth: 808) }
        if columns >= 2 { grid(columns: 2).frame(minWidth: 534) }
        grid(columns: 1)
      }
    }
  }

  private func grid(columns: Int) -> some View {
    LazyVGrid(
      columns: Array(
        repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
        count: columns), alignment: .leading, spacing: 14
    ) {
      ForEach(Array(panels.enumerated()), id: \.offset) { index, data in
        if definition.panels.indices.contains(index) {
          VisualChartView(
            definition: definition.panels[index], data: data, compact: compact,
            openOriginal: openOriginal,
            loadSources: loadSources.map { load in { try await load(index, data, $0, $1) } }
          )
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
      }
    }
  }
}

public struct LiveVisualOverviewView: View {
  let definition: VisualOverview
  let revision: String
  let load: @MainActor (Cancellation) async throws -> [VisualChartData]
  let openOriginal: ((String) -> Void)?
  let loadSources: ((Int, VisualChartData, Int, Int) async throws -> Value)?
  @State private var panels: [VisualChartData]?
  @State private var loadedDefinition: VisualOverview?
  @State private var refreshing = false
  @State private var failure: String?

  public init(
    definition: VisualOverview, revision: String,
    load: @escaping @MainActor (Cancellation) async throws -> [VisualChartData],
    openOriginal: ((String) -> Void)? = nil,
    loadSources: ((Int, VisualChartData, Int, Int) async throws -> Value)? = nil
  ) {
    self.definition = definition
    self.revision = revision
    self.load = load
    self.openOriginal = openOriginal
    self.loadSources = loadSources
  }

  public var body: some View {
    Group {
      if let failure {
        Label(failure, systemImage: "exclamationmark.circle")
      } else if let panels, loadedDefinition == definition {
        VStack(alignment: .leading, spacing: 6) {
          if refreshing { ProgressView("Updating overview…").controlSize(.small) }
          VisualOverviewView(
            definition: definition, panels: panels, openOriginal: openOriginal,
            loadSources: loadSources
          )
          .disabled(refreshing)
        }
      } else {
        ProgressView("Loading overview…")
      }
    }
    .task(id: revision + "/" + ((try? encoded(definition).json()) ?? "")) {
      refreshing = true
      failure = nil
      let cancellation = Cancellation()
      await withTaskCancellationHandler {
        do {
          let next = try await load(cancellation)
          try Task.checkCancellation()
          panels = next
          loadedDefinition = definition
        } catch {
          guard !Task.isCancelled else { return }
          failure = error.localizedDescription
        }
        refreshing = false
      } onCancel: {
        cancellation.cancel()
      }
    }
  }
}
