import SevraCore
import SevraVisualUI
import SwiftUI

/// A declared chart has the same host query in an app or on Home.
public struct NativeAppDeclaredView: View {
  @ObservedObject var session: NativeAppSession
  let viewID: String
  let datasetSnapshot: String
  let openOriginal: ((String) -> Void)?
  @State private var grantRevision = 0

  public init(
    session: NativeAppSession, viewID: String, datasetSnapshot: String = "",
    openOriginal: ((String) -> Void)? = nil
  ) {
    self.session = session
    self.viewID = viewID
    self.datasetSnapshot = datasetSnapshot
    self.openOriginal = openOriginal
  }

  public var body: some View {
    content.onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification))
    { _ in
      grantRevision &+= 1
    }
  }

  @ViewBuilder private var content: some View {
    if !session.isGranted {
      Label("Enable this app to show its saved view.", systemImage: "lock")
        .font(.callout).foregroundStyle(.secondary)
    } else if let chart = session.package.views?[viewID]?.chart {
      LiveVisualChartView(
        definition: chart,
        revision: datasetSnapshot + "/" + String(session.visualRevision) + "/"
          + String(grantRevision),
        load: {
          guard let data = try await session.loadVisual(viewID).chartData else {
            throw SevraError("visual", "The app's chart is unavailable.")
          }
          return data
        }, openOriginal: openOriginal
      )
      .id(viewID)
    } else if let work = session.package.views?[viewID]?.work {
      LiveWorkVisualView(
        definition: work,
        revision: datasetSnapshot + "/" + String(session.visualRevision) + "/"
          + String(grantRevision),
        load: {
          guard let data = try await session.loadVisual(viewID).workData else {
            throw SevraError("visual", "The app's work view is unavailable.")
          }
          return data
        }, openRecord: openOriginal
      )
      .id(viewID)
    } else {
      Label("This view is unavailable.", systemImage: "chart.bar.xaxis")
        .font(.callout).foregroundStyle(.secondary)
    }
  }
}
