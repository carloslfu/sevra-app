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
      }.padding(12).background(
        Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
      ViewThatFits(in: .horizontal) {
        HStack { filters }
        VStack(alignment: .leading) { filters }
      }
      Toggle("Include earlier versions", isOn: $state.searchHistorical).toggleStyle(.checkbox).font(
        .callout)
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
                  Text(hit.snippet).lineLimit(4).foregroundStyle(.secondary)
                  if let location = DisplayText.location(hit.locator) {
                    Text(location).font(.caption).foregroundStyle(.tertiary)
                  }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
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
      if let failure { Text(failure).foregroundStyle(.red) }
    }.padding(22).task { focused = true }
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
  func facet(_ title: String, key: String, selection: Binding<String>) -> some View {
    Picker(title, selection: selection) {
      Text("All").tag("")
      ForEach(facets[key].array.compactMap(\.string), id: \.self) { Text($0.capitalized).tag($0) }
    }.font(.caption).frame(maxWidth: 190)
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
  @State private var editing: Space?
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 28) {
        HStack {
          if let captured = space.definition.pinnedAt {
            Text("Snapshot from " + DisplayText.date(captured)).font(.caption).foregroundStyle(
              .secondary)
          } else {
            Text("Live view").font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button("Edit layout") { editing = space }.disabled(state.busy)
          if !space.definition.components.isEmpty && !containsSections(space.definition.components)
          {
            Button("Save a snapshot") {
              state.pinSpace(
                space.id,
                title: space.title + " · " + Date().formatted(date: .abbreviated, time: .shortened))
            }.help("Keep exact values and input versions as of now.").disabled(state.busy)
          }
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
    .sheet(item: $editing) { selected in SpaceLayoutEditor(space: selected, state: state) }
  }
  private var visibleComponents: [Component] {
    space.definition.components.filter { component in
      switch component.type {
      case "reviews": return state.pendingReview?.items.isEmpty == false
      case "tables": return !state.datasets.isEmpty
      case "recent": return !state.items.isEmpty
      case "intake":
        return !state.pendingExtractions.isEmpty
          || state.intakeStatus.contains { $0["state"].text != "ready" }
      case "shortcuts":
        let shortcuts = SpacePickerSections(
          spaces: state.spaces, navigation: state.spaceNavigation.state, query: "")
        return !shortcuts.pinned.isEmpty || !shortcuts.recent.isEmpty
      default: return true
      }
    }
  }
  private func containsSections(_ components: [Component]) -> Bool {
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
              Text("\(table.rowCount) rows").foregroundStyle(.secondary)
            }.padding(.vertical, 7)
          }.buttonStyle(.plain)
        }
      }

      else {
        Text("No tables yet.").foregroundStyle(.secondary)
      }
    case "intake":
      if !state.pendingExtractions.isEmpty {
        ForEach(state.pendingExtractions, id: \.text) { job in
          HStack {
            VStack(alignment: .leading) {
              Text(job["title"].text)
              Text(job["detail"].text).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let id = job["job_id"].string {
              Button(job["state"].text == "awaiting_role" ? "Choose use" : "Continue") {
                state.presentIntake(id)
              }.disabled(state.busy)
            } else if job["asset_id"].string != nil {
              Button("Resume") {
                state.run("Resuming intake") { book, cancel in
                  try book.resumeIntake(job["item_id"].text, cancellation: cancel)
                }
              }
            } else {
              Button("Review reference") { state.navigate(.item(job["item_id"].text)) }
            }
          }
        }
      }
      ForEach(state.intakeStatus.filter { $0["state"].text != "ready" }, id: \.text) { job in
        let title = job["title"].text
        let completed = job["completed"].text
        let total = job["total"].text
        Text(
          "\(title): \(completed) of \(total) rows imported. Resume from the original source."
        )
        .font(.callout).foregroundStyle(.secondary)
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
          let table = state.datasets.first(where: { $0.id == id })
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
      offset: offset, filter: filter, sort: state.tableSorts[table.id],
      descending: state.tableDescending[table.id] ?? false)
  }
  @State private var column = 0
  @State private var showColumns = false
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
        Spacer()
        Menu {
          Button("Copy selected rows", action: copyRows).disabled(selection.isEmpty)
          Button("Paste cells", action: pasteCells).disabled(selection.isEmpty)
          Button("Undo") { undo(false) }.disabled(state.tableUndo[table.id] == nil)
          Button("Redo") { undo(true) }.disabled(state.tableRedo[table.id] == nil)
          Divider()
          Button("Columns and formulas…") { showColumns = true }
          Button("Export CSV…", action: export)
        } label: {
          Image(systemName: "ellipsis.circle")
        }.menuStyle(.borderlessButton).frame(width: 22).help("Table actions")
      }.padding(compact ? 8 : 14)
      if let page = loader.page {
        NativeTable(
          page: page,
          onEdit: { edit, revision in apply([edit], expectedRevision: revision) },
          onSelect: { selected, c in
            selection = Set(selected.map(\.logicalID))
            column = c
            guard let row = selected.first,
              let n = page.rows.firstIndex(where: { $0.logicalID == row.logicalID })
            else {
              state.selectedContext = ""
              return
            }
            state.selectedContext = "\(table.title), data row \(page.offset+n+1): \(row.data.text)"
            let selectedColumn =
              page.dataset.columns.indices.contains(c) ? page.dataset.columns[c] : nil
            if let selectedColumn {
              state.selectionLabel =
                "\(table.title), row \(page.offset+n+1) · \(selectedColumn.title): \(page.values[n][selectedColumn.id]?.text ?? "Empty")"
            } else {
              state.selectionLabel = "\(table.title), row \(page.offset+n+1)"
            }
          },
          onSort: { id, descending in
            state.tableSorts[table.id] = id
            state.tableDescending[table.id] = descending
            state.tableOffsets[table.id] = 0
          }, onCopy: copyRows, onPaste: pasteCells)
      } else {
        ProgressView("Loading table").frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      HStack {
        Button("Previous") {
          state.tableOffsets[table.id] = max(0, offset - 200)
        }.disabled(offset == 0)
        Text("\(min(displayedOffset+1,total))–\(min(displayedOffset+rows.count,total)) of \(total)")
          .font(.caption)
        Button("Next") {
          state.tableOffsets[table.id] = offset + 200
        }.disabled(offset + rows.count >= total)
        Spacer()
        if state.tableUndo[table.id] != nil { Button("Undo") { undo(false) } }
        if compact { Button("Open table") { state.navigate(.table(table.id)) } }
      }.padding(10)
    }
    .task(id: query) {
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
      if let failure = loader.failure { state.error = failure }
      if let page = loader.page, page.revision != state.revision { state.refresh() }
    }
    .sheet(isPresented: $showColumns) { ColumnEditor(table: table, state: state) }
  }
  func apply(_ edits: [RowEdit], expectedRevision: Int? = nil) {
    guard let revision = expectedRevision ?? loader.page?.revision else { return }
    let tableID = table.id
    state.run(
      "Saving table changes",
      operation: { book, _ in
        try book.editRows(tableID, edits: edits, expectedRevision: revision)
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
      operation: { book, _ in try book.undoTableChange(id) },
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
  func copyRows() {
    guard let page = loader.page else { return }
    let data = page.rows.indices.filter { selection.contains(page.rows[$0].logicalID) }.map { n in
      page.dataset.columns.map { page.values[n][$0.id]?.text ?? "" }
    }
    let text = data.map {
      $0.map { v in
        v.contains("\t") || v.contains("\n") || v.contains("\"")
          ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
      }.joined(separator: "\t")
    }.joined(separator: "\n")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
  func pasteCells() {
    guard let page = loader.page,
      let start = page.rows.firstIndex(where: { selection.contains($0.logicalID) }),
      let text = NSPasteboard.general.string(forType: .string)
    else { return }
    let rows = page.rows
    let columns = page.dataset.columns
    do {
      try require(text.utf8.count <= 4_000_000, "paste_limit", "Paste at most 4 MB at a time.")
      let cells = try CSV.parse(text, delimiter: "\t")
      try require(
        start + cells.count <= rows.count, "paste_range",
        "The paste exceeds the visible rows. Import a file to add a larger table.")
      var edits: [RowEdit] = []
      for (r, values) in cells.enumerated() {
        try require(
          column >= 0 && column + values.count <= columns.count, "paste_range",
          "The paste exceeds the table columns.")
        var data = rows[start + r].data.object
        for (c, value) in values.enumerated() {
          let target = columns[column + c]
          try require(
            target.formula == nil, "calculated_cell", "The paste includes a calculated column.")
          data[target.id] = value.isEmpty ? .null : .string(value)
        }
        edits.append(.init(id: rows[start + r].id, values: data))
      }
      apply(edits, expectedRevision: page.revision)
    } catch { state.error = error.localizedDescription }
  }
  func export() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = table.title + ".csv"
    if panel.runModal() == .OK, let url = panel.url {
      state.run("Exporting table") { book, _ in try book.exportCSV(table.id, to: url) }
    }
  }
}
struct ColumnEditor: View {
  let table: Dataset
  @ObservedObject var state: WorkspaceState
  @Environment(\.dismiss) private var dismiss
  @State private var columns: [Column] = []
  @State private var failure: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Columns and formulas").font(.title2)
      Text("Formulas use column IDs, such as quantity * unit_cost. Empty cells remain unknown.")
        .foregroundStyle(.secondary)
      ScrollView {
        VStack {
          ForEach($columns) { $c in
            HStack {
              TextField("Title", text: $c.title).frame(width: 130)
              Text(c.id).font(.caption.monospaced()).frame(width: 90, alignment: .leading)
              TextField(
                "Unit",
                text: Binding(get: { c.unit ?? "" }, set: { c.unit = $0.isEmpty ? nil : $0 })
              ).frame(width: 65)
              Picker("Type", selection: $c.type) {
                ForEach(["text", "decimal", "boolean", "date"], id: \.self) { Text($0).tag($0) }
              }.labelsHidden().frame(width: 90)
              TextField(
                "Formula (optional)",
                text: Binding(get: { c.formula ?? "" }, set: { c.formula = $0.isEmpty ? nil : $0 }))
            }
          }
        }
      }
      if let failure { Text(failure).foregroundStyle(.red) }
      HStack {
        Menu("History") {
          ForEach((try? state.workbook?.columnHistory(table.id)) ?? [], id: \.text) { record in
            Button("Restore version " + record["version"].text) {
              do {
                try state.workbook?.restoreColumns(table.id, version: record["version"].int ?? 0)
                state.refresh()
                dismiss()
              } catch { failure = error.localizedDescription }
            }
          }
        }
        Button("Add column") {
          columns.append(.init(id: "column_" + String(identifier().prefix(8)), title: "New column"))
        }
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Save") {
          do {
            try state.workbook?.setColumns(table.id, columns: columns)
            state.refresh()
            dismiss()
          } catch { failure = error.localizedDescription }
        }.buttonStyle(.borderedProminent)
      }
    }.padding(24).frame(width: 680, height: 420).onAppear { columns = table.columns }
  }
}
