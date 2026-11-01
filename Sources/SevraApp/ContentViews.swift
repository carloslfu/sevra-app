import AppKit
import Charts
import SevraCore
import SevraPreviewUI
import SevraSearchUI
import SevraTableUI
import SwiftUI

struct SearchView: View {
  @ObservedObject var state: WorkspaceState
  @ObservedObject var results: SearchSession
  private var hits: [SearchHit] { results.loadedQuery == query ? results.hits : [] }
  private var next: String? { results.loadedQuery == query ? results.nextCursor : nil }
  private var incomplete: Int { results.loadedQuery == query ? results.incomplete : 0 }
  private var searching: Bool { results.loading }
  private var failure: String? { results.query == query ? results.failure : nil }
  @State private var facets: Value = .null
  @State private var showingFilters = false
  @FocusState private var focused: Bool
  var query: SearchQuery {
    SearchQuery(
      workbook: state.workbook?.url, revision: state.revision, text: state.searchQuery,
      historical: state.searchHistorical,
      kind: state.searchKind.isEmpty ? nil : state.searchKind,
      meaning: state.searchMeaning.isEmpty ? nil : state.searchMeaning,
      status: state.searchStatus.isEmpty ? nil : state.searchStatus,
      scenario: state.searchScenario.isEmpty ? nil : state.searchScenario)
  }
  var facetIdentity: SearchQuery {
    SearchQuery(workbook: state.workbook?.url, revision: state.revision, text: "")
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Find words, documents, filenames…", text: $state.searchQuery).textFieldStyle(
          .plain
        ).focused($focused)
        if searching { ProgressView().controlSize(.small) }
        if !state.searchQuery.isEmpty {
          Button {
            state.searchQuery = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
        }
      }.padding(12).background(
        Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8)
      ).overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(focused ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: 1)
      )
      DisclosureGroup(
        activeFilters == 0 ? "Filters" : "Filters (\(activeFilters) active)",
        isExpanded: $showingFilters
      ) {
        VStack(alignment: .leading, spacing: 12) {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190, maximum: 240), alignment: .leading)],
            alignment: .leading, spacing: 10
          ) { filters }
          Toggle("Include earlier versions", isOn: $state.searchHistorical)
            .toggleStyle(.checkbox).font(.callout)
          if activeFilters > 0 {
            Button("Clear filters") {
              state.searchKind = ""
              state.searchMeaning = ""
              state.searchStatus = ""
              state.searchScenario = ""
              state.searchHistorical = false
            }
          }
        }.padding(.top, 8).fixedSize(horizontal: false, vertical: true)
      }
      if incomplete > 0 {
        Text(
          (incomplete == 1
            ? "1 source has an incomplete content index."
            : "\(incomplete) sources have incomplete content indexes.")
            + " Filename search is still available."
        ).font(.caption).foregroundStyle(.secondary)
      }
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(hits) { hit in
              Button {
                results.anchor = hit.itemID
                state.openEvidence(hit.itemID, locator: hit.locator)
              } label: {
                VStack(alignment: .leading, spacing: 6) {
                  Text(hit.title).font(.headline)
                  Text(StructuredPresentation.searchExcerpt(hit.snippet, title: hit.title))
                    .lineLimit(4).foregroundStyle(.secondary)
                  if let location = DisplayText.location(hit.locator) {
                    Text(location).font(.caption).foregroundStyle(.tertiary)
                  }
                }.multilineTextAlignment(.leading)
                  .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
              }.buttonStyle(.plain).id(hit.itemID)
              Divider()
            }
            if next != nil {
              Button("Show more results") { Task { await search(more: true) } }.disabled(searching)
                .padding(.vertical, 14)
            }
            if hits.isEmpty && !query.isEmpty && !searching && failure == nil
              && results.loadedQuery == query
            {
              ContentUnavailableView.search(text: state.searchQuery).padding(.top, 30)
            }
            if query.isEmpty {
              Text(
                "Search evidence directly, or ask Sevra to investigate across sources in the conversation."
              ).foregroundStyle(.secondary).padding(.top, 20)
            }
          }
        }.onAppear { if let id = results.anchor { proxy.scrollTo(id, anchor: .center) } }
          .onChange(of: hits.count) { _, _ in
            if let id = results.anchor { proxy.scrollTo(id, anchor: .center) }
          }
      }
      if let failure {
        HStack {
          Text(failure).foregroundStyle(.red).textSelection(.enabled)
          Spacer()
          Button("Retry search") { Task { await search(more: results.loadedQuery == query) } }
            .disabled(searching)
        }
      }
    }.padding(24).task {
      focused = true
      showingFilters = activeFilters > 0
    }
    .task(id: facetIdentity) {
      let identity = facetIdentity
      if let book = state.workbook {
        let found = try? await Task.detached { try book.searchFacets() }.value
        guard !Task.isCancelled, facetIdentity == identity else { return }
        facets = found ?? .null
      }
    }
    .task(id: query) { await search(more: false) }
    .onDisappear { results.cancelRead() }
  }
  @ViewBuilder var filters: some View {
    facet("Kind", key: "kind", selection: $state.searchKind)
    facet("Meaning", key: "meaning", selection: $state.searchMeaning)
    facet("Status", key: "status", selection: $state.searchStatus)
    facet("Scenario", key: "scenario", selection: $state.searchScenario)
  }
  private var activeFilters: Int {
    [state.searchKind, state.searchMeaning, state.searchStatus, state.searchScenario]
      .filter { !$0.isEmpty }.count + (state.searchHistorical ? 1 : 0)
  }
  func facet(_ title: String, key: String, selection: Binding<String>) -> some View {
    HStack(spacing: 10) {
      Text(title).frame(width: 60, alignment: .trailing).accessibilityHidden(true)
      Picker(title, selection: selection) {
        Text("All").tag("")
        ForEach(facets[key].array.compactMap(\.string), id: \.self) {
          Text(StructuredPresentation.label($0)).tag($0)
        }
      }.labelsHidden().accessibilityLabel(title).frame(width: 120, alignment: .leading)
    }.font(.caption).frame(width: 190)
  }
  func search(more: Bool) async {
    guard let book = state.workbook else { return }
    let request = query
    await results.load(request, more: more, debounce: !more) { cursor, cancellation in
      try await Task.detached {
        try book.search(
          request.text, kind: request.kind, meaning: request.meaning,
          historical: request.historical, cursor: cursor, status: request.status,
          scenario: request.scenario, cancellation: cancellation)
      }.value
    }
  }
}
struct SpaceView: View {
  let space: Space
  @ObservedObject var state: WorkspaceState
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 28) {
        if let captured = space.definition.pinnedAt {
          Text("Snapshot from " + DisplayText.date(captured)).font(.caption).foregroundStyle(
            .secondary)
        }
        if space.definition.components.isEmpty {
          Text("Make room for your work").font(.system(size: 28, weight: .medium))
          Text(
            "Describe what you want here, or edit the layout. Removing sections keeps your information in the workbook."
          )
          .foregroundStyle(.secondary).frame(maxWidth: 520, alignment: .leading)
        }
        ForEach(visibleComponents) { component in
          NativeComponent(component: component, state: state).id(component.id)
        }
      }.scrollTargetLayout().padding(26).frame(maxWidth: .infinity, alignment: .leading)
    }.scrollPosition(
      id: Binding(get: { state.spaceScroll[space.id] }, set: { state.spaceScroll[space.id] = $0 }),
      anchor: .top
    )
  }
  private var visibleComponents: [Component] {
    let pending = state.pendingReview?.items.isEmpty == false
    let components =
      space.id == "home"
      ? space.definition.homeComponents(pendingReview: pending) : space.definition.components
    return components.filter { component in
      switch component.type {
      case "reviews": return state.pendingReview?.items.isEmpty == false
      case "tables": return !state.datasets.isEmpty || !state.archivedDatasets.isEmpty
      case "recent": return !state.items.isEmpty
      case "intake":
        return !state.pendingExtractions.isEmpty
      case "shortcuts":
        let shortcuts = SpacePickerSections(
          spaces: state.spaces, navigation: state.spaceNavigation.state, query: "")
        return !shortcuts.pinned.isEmpty || !shortcuts.recent.isEmpty
      default: return true
      }
    }
  }
}
extension SpaceDefinition {
  var containsSections: Bool { Self.containsSections(components) }
  private static func containsSections(_ components: [Component]) -> Bool {
    components.contains {
      SpaceDefinition.sectionTypes.contains($0.type) || containsSections($0.children ?? [])
    }
  }
}
struct WorkbookSection: View {
  let type: String
  @ObservedObject var state: WorkspaceState
  @ViewBuilder var body: some View {
    switch type {
    case "input":
      HStack {
        Button("Add files…") { state.importPanel() }
        Button("Search workbook") { state.navigate(.search) }
      }
    case "reviews":
      if let pending = state.pendingReview, !pending.items.isEmpty {
        HStack {
          Text("\(pending.items.count) pending").font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Show all drafts") { state.navigate(.reviews) }
        }
        ForEach(pending.items) { item in
          DraftReviewRow(item: item) { state.navigate(.item(item.id)) }
        }
      }

      else {
        Text("No drafts waiting for review.").foregroundStyle(.secondary)
      }
    case "shortcuts":
      let shortcuts = SpacePickerSections(
        spaces: state.spaces, navigation: state.spaceNavigation.state, query: "")
      if !shortcuts.pinned.isEmpty {
        sectionTitle("Pinned spaces")
        ForEach(shortcuts.pinned) { saved in
          SpaceShortcutRow(space: saved, state: state) { state.navigate(.space(saved.id)) }
        }
      }
      if !shortcuts.recent.isEmpty {
        sectionTitle("Recent spaces")
        ForEach(Array(shortcuts.recent.prefix(4))) { saved in
          SpaceShortcutRow(space: saved, state: state) { state.navigate(.space(saved.id)) }
        }
      }

    case "tables":
      if !state.datasets.isEmpty {
        ForEach(state.datasets) { table in
          Button {
            state.navigate(.table(table.id))
          } label: {
            HStack {
              Image(systemName: "tablecells")
              Text(table.title)
              Spacer()
              Text(
                state.savedRows(table)
                  ?? (table.rowCount == 1 ? "1 row" : "\(table.rowCount.formatted()) rows")
              ).foregroundStyle(.secondary)
            }.padding(.vertical, 7)
          }.buttonStyle(.plain)
        }
      }

      else {
        Text("No tables yet.").foregroundStyle(.secondary)
      }
      if !state.archivedDatasets.isEmpty {
        DisclosureGroup("Archived tables (\(state.archivedDatasets.count))") {
          ForEach(state.archivedDatasets) { table in
            Button(table.title) { state.navigate(.table(table.id)) }
              .buttonStyle(.plain).padding(.vertical, 7)
          }
        }
      }
    case "intake":
      if !state.pendingExtractions.isEmpty {
        ForEach(state.pendingExtractions, id: \.text) { job in
          HStack {
            VStack(alignment: .leading) {
              Text(job["title"].text)
              Text(state.intakeDetail(job)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let id = job["job_id"].string {
              Button(job["state"].text == "awaiting_role" ? "Choose use" : "Continue") {
                state.presentIntake(id)
              }.disabled(state.busy)
            } else if job["asset_id"].string != nil {
              Button("Resume") {
                let progress = state.rowProgress()
                state.run("Resuming intake") { book, cancel in
                  try book.resumeIntake(
                    job["item_id"].text, cancellation: cancel, progress: progress)
                }
              }
            } else {
              Button("Review reference") { state.navigate(.item(job["item_id"].text)) }
            }
          }
        }
      }

    case "recent":
      let recent = state.items
      if recent.isEmpty {
        Text("Included files and saved work will appear here.").foregroundStyle(.secondary)
      }
      ForEach(Array(recent)) { item in
        Button {
          state.navigate(.item(item.id))
        } label: {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.assetID == nil ? "text.alignleft" : "doc").foregroundStyle(
              .secondary)
            VStack(alignment: .leading, spacing: 3) {
              Text(item.title)
              Text(
                item.status == "draft"
                  ? "Draft · \(item.meaning)"
                  : item.kind == "table-intake-update" ? "Table update" : item.kind.capitalized
              )
              .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
          }.padding(.vertical, 6)
        }.buttonStyle(.plain)
      }

    default: EmptyView()
    }
  }
  func sectionTitle(_ title: String) -> some View {
    Text(title).font(.headline).padding(.top, 6)
  }
}
struct NativeComponent: View {
  let component: Component
  @ObservedObject var state: WorkspaceState
  @State private var data: ComponentSnapshot?
  @State private var metric: String?
  @State private var failure: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(component.title).font(.title3.weight(.medium))
      if let snapshot = component.snapshot {
        Text("Pinned as of " + DisplayText.date(snapshot.captured)).font(.caption).foregroundStyle(
          .secondary)
      }
      switch component.type {
      case "input", "reviews", "shortcuts", "tables", "intake", "recent":
        WorkbookSection(type: component.type, state: state)
      case "calculation", "query":
        DefinitionComponentView(component: component, workspace: state).id(
          state.interactionIdentity)
      case "form":
        FormComponentView(component: component, workspace: state).id(state.interactionIdentity)
      case "text": Text(component.text ?? "").textSelection(.enabled).foregroundStyle(.secondary)
      case "comparison":
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 20) {
            ForEach(component.children ?? []) { child in
              AnyView(NativeComponent(component: child, state: state)).frame(minWidth: 260)
            }
          }
          VStack(alignment: .leading, spacing: 20) {
            ForEach(component.children ?? []) { child in
              AnyView(NativeComponent(component: child, state: state))
            }
          }
        }
      case "metric":
        if let metric {
          Text(metric + unitSuffix).font(.system(size: 32, weight: .medium, design: .rounded))
        }
      case "table":
        if component.snapshot == nil, let id = component.datasetID,
          let table = state.dataset(id)
        {
          DatasetView(table: table, state: state, compact: true)
            .frame(height: min(280, CGFloat(max(1, table.rowCount)) * 32 + 108))
        } else if let data {
          ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
              GridRow { ForEach(data.columns) { Text($0.title).fontWeight(.semibold) } }
              ForEach(data.rows) { row in
                GridRow {
                  ForEach(data.columns) { c in
                    Text(row.values[c.id]?.text ?? "Unknown").textSelection(.enabled)
                  }
                }
              }
            }.padding(8)
          }.frame(maxHeight: 280)
        }
      case "chart":
        if let data {
          let points = data.rows.compactMap { row -> PlotPoint? in
            guard let y = Double(row.values[component.y ?? ""]?.text ?? ""), y.isFinite else {
              return nil
            }
            return PlotPoint(id: row.id, label: row.values[component.x ?? ""]?.text ?? "", value: y)
          }
          Chart(points) { point in
            if component.chartStyle == "line" {
              LineMark(x: .value("Category", point.label), y: .value("Value", point.value))
                .foregroundStyle(Color.accentColor)
              PointMark(x: .value("Category", point.label), y: .value("Value", point.value))
                .foregroundStyle(Color.accentColor)
            } else {
              BarMark(x: .value("Category", point.label), y: .value("Value", point.value))
                .foregroundStyle(Color.accentColor)
            }
          }.frame(height: 220)
          if points.count < data.rows.count {
            Text(
              "\(data.rows.count - points.count) rows have unknown or invalid values and are not plotted."
            ).font(.caption).foregroundStyle(.secondary)
          }
          if data.rows.count < data.totalRows {
            Text("Showing \(data.rows.count) of \(data.totalRows) rows.").font(.caption)
              .foregroundStyle(.secondary)
          }
          if !unitSuffix.isEmpty { Text(unitSuffix).font(.caption).foregroundStyle(.secondary) }
        }
      case "document", "asset":
        if let id = component.itemID {
          Button(component.type == "asset" ? "Open file" : "Open document") {
            state.navigate(.item(id))
          }
        }
      case "search":
        SearchComponentView(component: component, state: state)
      default: Text("This component is unavailable.").foregroundStyle(.secondary)
      }
      if let failure { Text(failure).font(.callout).foregroundStyle(.red) }
    }.frame(maxWidth: .infinity, alignment: .leading)
      .task(id: component.id + String(state.revision)) {
        guard component.datasetID != nil, let book = state.workbook else { return }
        do {
          let result = try await Task.detached {
            let data = try book.componentData(component)
            return (
              data,
              component.type == "metric" ? try book.componentMetric(component, data: data) : nil
            )
          }.value
          try Task.checkCancellation()
          data = result.0
          metric = result.1
          failure = nil
        } catch is CancellationError {} catch { failure = error.localizedDescription }
      }
  }
  var unitSuffix: String {
    let unit = component.unit ?? data?.columns.first(where: { $0.id == component.y })?.unit
    return unit.map { " " + $0 } ?? ""
  }
}
/// Live search runs away from view rendering; the shared session refuses stale
/// completions. Pinned results remain usable even if current indexing changes.
struct SearchComponentView: View {
  let component: Component
  @ObservedObject var state: WorkspaceState
  @StateObject private var results = SearchSession()
  private var query: SearchQuery {
    SearchQuery(
      workbook: state.workbook?.url, revision: state.revision,
      text: component.query ?? "")
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let snapshot = component.searchSnapshot {
        Text("Search results from " + DisplayText.date(snapshot.captured))
          .font(.caption).foregroundStyle(.secondary)
        content(snapshot.hits, incomplete: snapshot.incomplete, hasMore: snapshot.hasMore)
      } else if results.loadedQuery == query {
        content(results.hits, incomplete: results.incomplete, hasMore: results.nextCursor != nil)
      } else if results.query == query, let failure = results.failure {
        Text(failure).foregroundStyle(.red)
      } else {
        ProgressView().controlSize(.small).accessibilityLabel("Searching workbook")
      }
    }.task(id: query) {
      guard component.searchSnapshot == nil, let book = state.workbook else { return }
      let request = query
      await results.load(request) { _, cancellation in
        try await Task.detached {
          try book.search(request.text, limit: 8, cancellation: cancellation)
        }.value
      }
    }
  }
  @ViewBuilder private func content(_ hits: [SearchHit], incomplete: Int, hasMore: Bool)
    -> some View
  {
    ForEach(hits) { hit in
      Button(hit.title) { state.openEvidence(hit.itemID, locator: hit.locator) }
        .buttonStyle(.link)
    }
    if hits.isEmpty { Text("No matches for this search.").foregroundStyle(.secondary) }
    if hasMore {
      Text("Showing the first \(hits.count) results.").font(.caption).foregroundStyle(.secondary)
    }
    if incomplete > 0 {
      Text(
        incomplete == 1
          ? "1 source had an incomplete content index when searched."
          : "\(incomplete) sources had incomplete content indexes when searched."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
}
struct PlotPoint: Identifiable {
  let id: String
  let label: String
  let value: Double
}
struct DatasetView: View {
  let table: Dataset
  @ObservedObject var state: WorkspaceState
  var compact = false
  @StateObject private var loader = TablePageLoader()
  @State private var selection = Set<String>()
  private var rows: [Item] { loader.page?.rows ?? [] }
  private var total: Int { loader.page?.total ?? 0 }
  private var displayedOffset: Int { loader.page?.offset ?? offset }
  private var query: TableQuery {
    TableQuery(
      workbook: state.workbook?.url, dataset: table.id, revision: state.revision,
      offset: offset, filter: filter,
      sort: TableQuery.sort(state.tableSorts[table.id], in: table.columns),
      descending: state.tableDescending[table.id] ?? false)
  }
  @State private var column = 0
  @State private var clipboardStatus = ""
  @State private var showingFormulas = false
  private var pageIsCurrent: Bool { loader.loadedQuery == query && !loader.loading }
  private var canPaste: Bool {
    pageIsCurrent && !selection.isEmpty && !table.archived && !state.busy
  }
  @State private var schemaEditing: Dataset?
  private var offset: Int { state.tableOffsets[table.id] ?? 0 }
  private var filter: String { state.tableFilters[table.id] ?? "" }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        TextField(
          "Filter rows",
          text: Binding(
            get: { filter },
            set: {
              state.tableFilters[table.id] = $0
              state.tableOffsets[table.id] = 0
            })
        )
        .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
        .accessibilityLabel("Filter rows in " + table.title)
        if !filter.isEmpty {
          Button {
            state.tableFilters[table.id] = ""
            state.tableOffsets[table.id] = 0
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.plain).foregroundStyle(.secondary)
          .accessibilityLabel("Clear row filter").help("Show all rows")
        }
        Spacer()
        if loader.loading { ProgressView().controlSize(.small).accessibilityLabel("Updating rows") }
        MoreActionsMenu("Table actions: " + table.title) {
          Button("Copy selected rows") { copyRows() }.disabled(selection.isEmpty || !pageIsCurrent)
          Button("Copy with headings") { copyRows(headings: true) }
            .disabled(selection.isEmpty || !pageIsCurrent)
          Button("Paste cells", action: pasteCells).disabled(!canPaste)
            .help("Starts at the first selected row and last clicked column")
          Divider()
          Button("Undo") { undo(false) }.disabled(state.tableUndo[table.id] == nil || state.busy)
          Button("Redo") { undo(true) }.disabled(state.tableRedo[table.id] == nil || state.busy)
          Divider()
          Button("Table definition…") { schemaEditing = table }
          Button("Export CSV…", action: export)
        }
      }.padding(compact ? 8 : 14)
      if table.archived {
        Text(
          "Archived table. Its data and history are preserved. Restore it in Table definition to edit."
        )
        .font(.callout).foregroundStyle(.secondary).padding(8)
      }
      if let page = loader.page {
        NativeTable(
          page: page,
          onEdit: { edit, revision in apply([edit], expectedRevision: revision) },
          onSelect: { selected, c in
            selection = Set(selected.map(\.logicalID))
            column = c
            clipboardStatus = ""
            let shown = TableSelectionPresentation(page: page, selected: selected, column: c)
            state.selectedContext = shown.context
            state.selectionLabel = shown.label
          },
          onSort: { id, descending in
            state.tableSorts[table.id] = id
            state.tableDescending[table.id] = descending
            state.tableOffsets[table.id] = 0
          }, onCopy: { copyRows() }, onPaste: pasteCells,
          onUndo: state.tableUndo[table.id] == nil || state.busy ? nil : { undo(false) },
          onRedo: state.tableRedo[table.id] == nil || state.busy ? nil : { undo(true) },
          editable: pageIsCurrent && !state.busy
        )
        .overlay {
          if page.rows.isEmpty && !loader.loading && loader.failure == nil {
            Text(filter.isEmpty ? "No rows in this table." : "No rows match this filter.")
              .foregroundStyle(.secondary).padding(20)
          }
        }
      } else if loader.failure == nil {
        ProgressView("Loading table").frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      if let failure = loader.failure {
        HStack {
          Text(failure).foregroundStyle(.red).textSelection(.enabled)
          Spacer()
          Button("Retry table") { Task { await loadTable() } }.disabled(loader.loading)
        }.padding(10)
      }
      ViewThatFits(in: .horizontal) {
        HStack {
          rowCount
          Spacer()
          tableFeedback
        }
        VStack(alignment: .leading, spacing: 6) {
          rowCount
          HStack {
            tableFeedback
            Spacer()
          }
        }
      }.padding(10)
    }
    .task(id: query) { await loadTable() }
    .onChange(of: query) { _, _ in clipboardStatus = "" }
    .onDisappear { loader.cancel() }
    .sheet(item: $schemaEditing) { frozen in ColumnEditor(table: frozen, state: state) }
  }
  private var rowCount: some View {
    HStack {
      if total > 200 || offset > 0 {
        Button("Previous") {
          state.tableOffsets[table.id] = max(0, offset - 200)
        }.disabled(offset == 0)
        Text(
          rows.isEmpty
            ? "0 rows on this page of \(total.formatted())"
            : "\((displayedOffset+1).formatted())–\(min(displayedOffset+rows.count,total).formatted()) of \(total.formatted())"
        )
        .font(.caption)
        Button("Next") {
          state.tableOffsets[table.id] = offset + 200
        }.disabled(offset + rows.count >= total)
      } else {
        Text(total == 1 ? "1 row" : "\(total) rows").font(.caption).foregroundStyle(.secondary)
      }
      if let saved = state.savedRows(table) {
        Text("Import unfinished: " + saved).font(.caption).foregroundStyle(.secondary)
      }
      if let report = loader.page?.formulaReport {
        Button(report.summary) { showingFormulas = true }
          .buttonStyle(.link).font(.caption)
          .popover(isPresented: $showingFormulas, arrowEdge: .top) {
            ExcelFormulaReportView(report: report)
          }
      }
      if !selection.isEmpty {
        Text("\(selection.count) selected on this page").font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private var tableFeedback: some View {
    HStack {
      if !clipboardStatus.isEmpty {
        Text(clipboardStatus).font(.caption).foregroundStyle(.secondary)
      }
      if state.tableUndo[table.id] != nil {
        Button("Undo") { undo(false) }.disabled(state.busy)
      }
      if compact { Button("Open table") { state.navigate(.table(table.id)) } }
    }
  }
  func loadTable() async {
    let request = query
    guard let book = state.workbook else { return }
    await loader.load(request, debounce: !request.filter.isEmpty) {
      try await Task.detached {
        try book.tablePage(
          request.dataset, offset: request.offset, query: request.filter,
          sort: request.sort, descending: request.descending)
      }.value
    }
    guard !Task.isCancelled, query == request else { return }
    if let page = loader.page, page.revision != state.revision { state.refresh() }
  }
  func apply(_ edits: [RowEdit], expectedRevision: Int? = nil) {
    guard let revision = expectedRevision ?? loader.page?.revision else { return }
    guard !state.busy else {
      state.error =
        "This table change was not saved because another task is running. Try the edit again when it finishes."
      return
    }
    let tableID = table.id
    state.run(
      "Saving table changes",
      operation: { book, _ in
        try book.editRows(
          tableID, edits: edits, expectedRevision: revision,
          actor: .human("Sevra native table editor"))
      },
      completion: { change in
        state.tableUndo[tableID] = change.id
        state.tableRedo[tableID] = nil
      })
  }
  func undo(_ redo: Bool) {
    guard let id = redo ? state.tableRedo[table.id] : state.tableUndo[table.id]
    else { return }
    let tableID = table.id
    state.run(
      redo ? "Redoing table changes" : "Undoing table changes",
      operation: { book, _ in
        try book.undoTableChange(id, actor: .human("Sevra native table history"))
      },
      completion: { inverse in
        if redo {
          state.tableUndo[tableID] = inverse.id
          state.tableRedo[tableID] = nil
        } else {
          state.tableRedo[tableID] = inverse.id
          state.tableUndo[tableID] = nil
        }
      })
  }
  func copyRows(headings: Bool = false) {
    guard pageIsCurrent, let page = loader.page else { return }
    do {
      let copied = try TableClipboard(page: page, selection: selection, headings: headings)
      try copied.write()
      clipboardStatus =
        "Copied \(selection.count) \(selection.count == 1 ? "row" : "rows")"
        + (headings ? " with headings" : "")
    } catch { state.error = error.localizedDescription }
  }
  func pasteCells() {
    guard canPaste, let page = loader.page else { return }
    do {
      let edits = try TableClipboard.edits(
        cells: TableClipboard.read(), page: page, selection: selection, column: column)
      apply(edits, expectedRevision: page.revision)
    } catch { state.error = error.localizedDescription }
  }
  func export() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = table.title + ".csv"
    if panel.runModal() == .OK, let url = panel.url {
      state.run("Exporting table") { book, control in
        try book.exportCSV(table.id, to: url, cancellation: control)
      }
    }
  }
}
struct ColumnEditor: View {
  let table: Dataset
  @ObservedObject var state: WorkspaceState
  @Environment(\.dismiss) private var dismiss
  @State private var columns: [Column] = []
  @State private var title = ""
  @State private var archived = false
  @State private var history: [DatasetDefinition] = []
  @State private var expandedColumns = Set<String>()
  @State private var saving = false
  @State private var failure: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Table definition").font(.title2)
      TextField("Table title", text: $title).accessibilityLabel("Table title")
      Text("Open a column’s options to set units, formulas or validation.")
        .foregroundStyle(.secondary)
      ScrollView {
        VStack(spacing: 12) {
          ForEach($columns) { $c in
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                TextField("Column title", text: $c.title)
                  .accessibilityLabel("Column title, " + c.id)
                Picker("Type", selection: $c.type) {
                  Text("Text").tag("text")
                  Text("Number").tag("decimal")
                  Text("Yes or no").tag("boolean")
                  Text("Date").tag("date")
                }.frame(width: 180).accessibilityLabel("Type, " + c.id)
                Button(role: .destructive) {
                  columns.removeAll { $0.id == c.id }
                } label: {
                  Image(systemName: "minus.circle")
                }.help("Remove column " + c.title).accessibilityLabel("Remove column " + c.title)
                  .disabled(columns.count == 1)
              }
              DisclosureGroup(
                isExpanded: Binding(
                  get: { expandedColumns.contains(c.id) },
                  set: { expanded in
                    if expanded {
                      expandedColumns.insert(c.id)
                    } else {
                      expandedColumns.remove(c.id)
                    }
                  })
              ) {
                VStack(alignment: .leading, spacing: 10) {
                  LabeledContent("Column ID") {
                    Text(c.id).font(.callout.monospaced()).textSelection(.enabled)
                  }
                  TextField(
                    "Unit (optional)",
                    text: Binding(get: { c.unit ?? "" }, set: { c.unit = $0.isEmpty ? nil : $0 })
                  ).accessibilityLabel("Unit, " + c.id)
                  TextField(
                    "Formula (optional)",
                    text: Binding(
                      get: { c.formula ?? "" }, set: { c.formula = $0.isEmpty ? nil : $0 })
                  ).accessibilityLabel("Formula, " + c.id)
                  HStack {
                    Toggle(
                      "Required",
                      isOn: Binding(
                        get: { c.required == true }, set: { c.required = $0 ? true : nil })
                    ).accessibilityLabel("Required, " + c.id)
                    Toggle(
                      "Unique",
                      isOn: Binding(get: { c.unique == true }, set: { c.unique = $0 ? true : nil })
                    ).accessibilityLabel("Unique, " + c.id)
                  }.disabled(c.formula != nil)
                }.padding(.top, 8)
              } label: {
                Text(columnOptions(c))
                  .accessibilityLabel("Options for " + c.title + ", " + columnOptions(c))
              }
              Divider()
            }
          }
        }
      }
      if let failure { Text(failure).foregroundStyle(.red) }
      DisclosureGroup("About formulas and history") {
        Text("Formulas use column IDs, such as quantity * unit_cost. Empty cells remain unknown.")
        Text(
          "Removing a column preserves its saved values. Restore a definition from History to recover it."
        )
      }.font(.caption).foregroundStyle(.secondary)
      Toggle("Archive table", isOn: $archived)
      Text(
        "Archive hides this table from the working list and prevents row edits. Saved views and history remain available."
      )
      .font(.caption).foregroundStyle(.secondary)
      HStack {
        Menu("History") {
          ForEach(history) { record in
            Button(
              "Restore version \(record.version): \(record.title)"
                + (record.archived ? " (archived)" : "")
            ) {
              restore(record.id)
            }
          }
          if let oldest = history.last, oldest.version > 1 {
            Button("Show older definitions") {
              do {
                history =
                  try state.workbook?.datasetDefinitions(table.id, beforeVersion: oldest.version)
                  ?? []
              } catch { failure = error.localizedDescription }
            }
          }
          if let newest = history.first, newest.version < table.version {
            Button("Show newest definitions") {
              do { history = try state.workbook?.datasetDefinitions(table.id) ?? [] } catch {
                failure = error.localizedDescription
              }
            }
          }
        }
        Button("Add column") {
          columns.append(.init(id: "column_" + String(identifier().prefix(8)), title: "New column"))
        }
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save definition") {
          save()
        }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
      }
    }.padding(24).frame(width: 780, height: 540).disabled(saving)
      .interactiveDismissDisabled(saving).onAppear {
        columns = table.columns
        title = table.title
        archived = table.archived
        do { history = try state.workbook?.datasetDefinitions(table.id) ?? [] } catch {
          failure = error.localizedDescription
        }
      }
  }
  private func columnOptions(_ column: Column) -> String {
    var details: [String] = []
    if column.formula != nil { details.append("calculated") }
    if let unit = column.unit, !unit.isEmpty { details.append(unit) }
    if column.required == true { details.append("required") }
    if column.unique == true { details.append("unique") }
    return details.isEmpty ? "Options" : "Options · " + details.joined(separator: ", ")
  }
  private func save() {
    guard let book = state.workbook else { return }
    let title = title
    let columns = columns
    let archived = archived
    saving = true
    Task {
      do {
        _ = try await Task.detached {
          try book.updateDatasetDefinition(
            table.id, expectedVersion: table.version,
            expectedDefinitionID: table.definitionID, title: title, columns: columns,
            archived: archived,
            actor: .human("Sevra native table definition editor"))
        }.value
        state.refresh()
        dismiss()
      } catch { failure = error.localizedDescription }
      saving = false
    }
  }
  private func restore(_ id: String) {
    guard let book = state.workbook else { return }
    saving = true
    Task {
      do {
        _ = try await Task.detached {
          try book.restoreDatasetDefinition(
            table.id, definitionID: id,
            expectedVersion: table.version, expectedDefinitionID: table.definitionID,
            actor: .human("Sevra native table definition history"))
        }.value
        state.refresh()
        dismiss()
      } catch { failure = error.localizedDescription }
      saving = false
    }
  }
}
