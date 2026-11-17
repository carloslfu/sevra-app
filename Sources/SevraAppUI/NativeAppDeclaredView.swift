import SevraCore
import SevraVisualUI
import SwiftUI

/// The app and Home reuse a window's session for a named view and preset.
public struct NativeAppDeclaredView: View {
  @ObservedObject var session: NativeAppSession
  let viewID: String
  let presetID: String?
  let datasetSnapshot: String
  let openOriginal: ((String) -> Void)?
  @State private var grantRevision = 0
  @State private var result: VisualResult?
  @State private var error: String?
  @State private var refreshing = false

  public init(
    session: NativeAppSession, viewID: String, presetID: String? = nil,
    datasetSnapshot: String = "", openOriginal: ((String) -> Void)? = nil
  ) {
    self.session = session
    self.viewID = viewID
    self.presetID = presetID
    self.datasetSnapshot = datasetSnapshot
    self.openOriginal = openOriginal
  }

  private var revision: String {
    [
      datasetSnapshot, String(session.visualRevision), String(grantRevision),
      String(session.presentationRevision),
    ].joined(separator: "/")
  }

  public var body: some View {
    Group {
      if !session.isGranted {
        Label("Enable this app to show its saved view.", systemImage: "lock")
          .font(.callout).foregroundStyle(.secondary)
      } else if let error {
        Label(error, systemImage: "exclamationmark.circle").font(.callout)
      } else if let work = session.package.views?[viewID]?.work {
        LiveWorkVisualView(
          definition: work, revision: revision,
          load: { cursor in
            guard let data = try await session.loadVisual(viewID, cursor: cursor).workData else {
              throw SevraError("visual", "The app’s work view is unavailable.")
            }
            return data
          }, openRecord: openOriginal,
          thumbnail: work.thumbnailAliases.map { aliases in
            { @MainActor @Sendable key in
              guard let alias = aliases[key] else {
                throw SevraError("visual_image", "No bound image.")
              }
              return try await session.loadRecordThumbnail(alias)
            }
          })
      } else if let result, let chart = result.chart, let data = result.chartData {
        VStack(alignment: .leading, spacing: 6) {
          if refreshing { ProgressView("Updating chart…").controlSize(.small) }
          VisualChartView(
            definition: chart, data: data, openOriginal: openOriginal,
            onSelect: chart.links?.isEmpty == false
              ? { point in
                do { try session.selectVisualPoint(viewID, presetID: presetID, point: point) } catch
                { self.error = error.localizedDescription }
              } : nil,
            selected: session.selectedVisualPoint(viewID, presetID: presetID),
            loadSources: { point, offset in
              let filters = session.visualFilters(viewID, presetID: presetID)
              return try await session.withVisualAccess { book, access in
                try book.nativeAppChartSources(
                  access, view: viewID, presetID: presetID, filters: filters,
                  snapshot: data.snapshot, queryHash: data.queryHash, point: point, offset: offset)
              }
            }
          )
          .disabled(refreshing)
        }
      } else if let text = session.package.views?[viewID]?.text {
        VisualTextView(definition: text)
      } else if let result, let overview = result.overview, let panels = result.overviewData {
        VisualOverviewView(definition: overview, panels: panels, openOriginal: openOriginal)
      } else if let result, let diagram = result.diagram, let data = result.diagramData {
        VisualDiagramView(definition: diagram, data: data, openRecord: openOriginal)
      } else {
        ProgressView("Loading saved view…").controlSize(.small)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
      if !session.isGranted { result = nil }
      grantRevision &+= 1
    }
    .task(id: [viewID, presetID ?? "", revision]) {
      guard session.isGranted, session.package.views?[viewID]?.work == nil,
        session.package.views?[viewID]?.text == nil
      else {
        result = nil
        return
      }
      let cancellation = Cancellation()
      let capturedRevision = revision
      refreshing = true
      error = nil
      await withTaskCancellationHandler {
        do {
          let values = try await session.loadVisual(
            viewID, presetID: presetID, cancellation: cancellation)
          try Task.checkCancellation()
          if capturedRevision == revision { result = values }
        } catch {
          guard !Task.isCancelled else { return }
          result = nil
          self.error = error.localizedDescription
        }
        if capturedRevision == revision { refreshing = false }
      } onCancel: {
        cancellation.cancel()
      }
    }
  }
}
