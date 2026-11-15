import SevraAppUI
import SevraCore
import SwiftUI

extension WorkspaceState {
  var hasHomeAttention: Bool {
    chatApproval != nil || pendingReview?.items.isEmpty == false || !pendingWorkflows.isEmpty
      || !pendingExtractions.isEmpty || excelImports.contains { $0["state"].text != "ready" }
  }
  var continueSpace: Space? {
    let home = spaces.first { $0.id == "home" }
    func embedded(_ components: [Component]) -> [String] {
      components.flatMap { ($0.spaceID.map { [$0] } ?? []) + embedded($0.children ?? []) }
    }
    let shown = Set(embedded(home?.definition.components ?? []))
    return spaceNavigation.state.recent.compactMap { id in
      spaces.first { $0.id == id && !shown.contains(id) }
    }.first ?? spaces.first { $0.id != "home" && !shown.contains($0.id) }
  }
  var hasContinueWork: Bool {
    continueSpace != nil || !homeDocuments.isEmpty
      || excelImports.contains { $0["state"].text == "ready" }
  }
  func focusHomeChat(_ text: String? = nil) {
    focus = false
    if prompt.isEmpty, let text { prompt = text }
    composerFocusRequest = UUID()
  }
  func homeShowsApp(_ id: String) -> Bool {
    func includes(_ components: [Component]) -> Bool {
      components.contains { $0.spaceID == id || includes($0.children ?? []) }
    }
    return includes(spaces.first { $0.id == "home" }?.definition.components ?? [])
  }
  func showAppOnHome(_ app: Space) {
    guard !homeShowsApp(app.id), let home = spaces.first(where: { $0.id == "home" }) else { return }
    let component = Component(type: "app", title: app.title, spaceID: app.id)
    run("Updating Home") { book, _ in
      _ = try book.editSpace(
        "home", expectedVersion: home.version,
        edits: [.init(operation: "insert", at: "last", component: component)])
    }
  }
  func resetHome(_ home: Space) {
    run("Restoring Home") { book, _ in
      _ = try book.editSpace(
        "home", expectedVersion: home.version, edits: [.init(operation: "reset")])
    }
  }
}

struct HomeStartView: View {
  @ObservedObject var state: WorkspaceState
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        state.items.isEmpty && state.spaces.count <= 1
          ? "Start with your work" : "Make Home useful to you"
      )
      .readingFont(size: 26, weight: .medium).accessibilityAddTraits(.isHeader)
      Text(
        "Describe what you need to do, or add a spreadsheet or document. Your work stays in this workbook."
      )
      .foregroundStyle(.secondary).frame(maxWidth: 460, alignment: .leading)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) { actions }
        VStack(alignment: .leading, spacing: 12) { actions }
      }
    }.padding(.vertical, 20)
  }
  @ViewBuilder private var actions: some View {
    Button("Describe the work") { state.focusHomeChat() }.buttonStyle(.borderedProminent)
    Button("Add files…") { state.importPanel() }.disabled(state.busy)
  }
}

struct HomeContinueView: View {
  @ObservedObject var state: WorkspaceState
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let space = state.continueSpace {
        HomeWorkRow(
          title: space.title,
          detail: state.spaceNavigation.state.recent.contains(space.id)
            ? "Last opened space" : "Saved space", symbol: "rectangle.split.2x2"
        ) {
          state.navigate(.space(space.id))
        }
      }
      ForEach(
        Array(state.excelImports.filter { $0["state"].text == "ready" }.prefix(2)), id: \.text
      ) { entry in
        HomeWorkRow(title: entry["title"].text, detail: "Excel workbook", symbol: "tablecells") {
          state.navigate(.excelImport(entry["id"].text))
        }
      }
      ForEach(state.homeDocuments) { item in
        HomeWorkRow(
          title: item.title, detail: item.assetID == nil ? "Recently saved" : "Recently included",
          symbol: item.assetID == nil ? "doc.text" : "doc"
        ) {
          state.navigate(.item(item.id))
        }
      }
    }
  }
}

struct HomeAttentionView: View {
  @ObservedObject var state: WorkspaceState
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let approval = state.chatApproval {
        HomeWorkRow(
          title: approval.title, detail: "Review the exact change in chat", symbol: "bubble.left"
        ) {
          state.focusHomeChat()
        }
      }
      if let reviews = state.pendingReview, !reviews.items.isEmpty {
        HomeWorkRow(
          title: "Drafts to review", detail: "Review before accepting changes", symbol: "tray"
        ) {
          state.navigate(.reviews)
        }
      }
      ForEach(state.pendingWorkflows, id: \.text) { run in
        HomeWorkRow(
          title: run["title"].text,
          detail: run["state"].text == "needs_attention"
            ? "Needs your attention"
            : run["state"].text == "waiting_review"
              ? "Waiting for your input" : "Ready to continue",
          symbol: "arrow.triangle.branch"
        ) {
          state.navigate(.workflow(run["id"].text))
        }
      }
      if !state.pendingWorkflows.isEmpty {
        Button("All workflow runs") { state.navigate(.activity) }.buttonStyle(.link)
      }
      ForEach(
        Array(state.excelImports.filter { $0["state"].text != "ready" }.prefix(3)), id: \.text
      ) { entry in
        HomeWorkRow(
          title: entry["title"].text, detail: "Continue Excel import", symbol: "tablecells"
        ) {
          state.navigate(.excelImport(entry["id"].text))
        }
      }
      if !state.pendingExtractions.isEmpty { WorkbookSection(type: "intake", state: state) }
    }
  }
}

struct HomeWorkRow: View {
  let title: String
  let detail: String
  let symbol: String
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
        VStack(alignment: .leading, spacing: 3) {
          Text(title).lineLimit(2)
          Text(detail).readingFont(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        Image(systemName: "chevron.right").readingFont(.caption).foregroundStyle(.tertiary)
      }.multilineTextAlignment(.leading).padding(.vertical, 9).contentShape(Rectangle())
    }.buttonStyle(.plain)
  }
}

struct HomeAppView: View {
  let component: Component
  @ObservedObject var state: WorkspaceState
  var body: some View {
    if let app = state.spaces.first(where: {
      $0.id == component.spaceID && $0.definition.app != nil
    }),
      let book = state.workbook
    {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Live · " + app.title).readingFont(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Open app") { state.navigate(.space(app.id)) }.buttonStyle(.link)
            .accessibilityLabel("Open " + app.title)
        }
        NativeAppSpaceView(session: state.nativeAppSession(app, book: book), embedded: true)
          .id(app.id + ":" + String(app.version))
          .frame(height: 420)
          .background(
            Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8)
          )
          .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
      }
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Text("This app is unavailable. Your other views and saved data are still accessible.")
          .foregroundStyle(.secondary)
        Button("Change this view in chat") {
          state.focusHomeChat("Replace the unavailable app view on Home: " + component.title)
        }
      }
    }
  }
}
