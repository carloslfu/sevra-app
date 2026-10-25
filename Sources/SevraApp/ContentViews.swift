import AppKit
import Charts
import SevraCore
import SwiftUI

struct SearchView: View {
  @ObservedObject var state: WorkspaceState
  @State private var hits: [SearchHit] = []
  @State private var next: String?
  @State private var incomplete = 0
  @State private var searching = false
  @State private var failure: String?
  @State private var facets: Value = .null
  @FocusState private var focused: Bool
  var identity: String {
    [
      state.searchQuery, String(state.searchHistorical), state.searchKind, state.searchMeaning,
      state.searchStatus, state.searchScenario, String(state.revision),
    ].joined(separator: "\u{1f}")
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
          "\(incomplete) sources have incomplete content indexes. Filename search is still available."
        ).font(.caption).foregroundStyle(.secondary)
      }
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(hits) { hit in
              Button {
                state.searchAnchor = hit.itemID
                state.openEvidence(hit.itemID, locator: hit.locator)
              } label: {
                VStack(alignment: .leading, spacing: 6) {
                  Text(hit.title).font(.headline)
                  Text(hit.snippet).lineLimit(4).foregroundStyle(.secondary)
                  Text(hit.locator).font(.caption).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
              }.buttonStyle(.plain).id(hit.itemID)
              Divider()
            }
            if next != nil {
              Button("Show more results") { Task { await search(more: true) } }.disabled(searching)
                .padding(.vertical, 14)
            }
            if hits.isEmpty && !state.searchQuery.isEmpty && !searching {
              ContentUnavailableView.search(text: state.searchQuery).padding(.top, 30)
            }
            if state.searchQuery.isEmpty {
              Text(
                "Search evidence directly, or ask Sevra to investigate across sources in the conversation."
              ).foregroundStyle(.secondary).padding(.top, 20)
            }
          }
        }.onChange(of: hits.count) { _, _ in
          if let id = state.searchAnchor { proxy.scrollTo(id, anchor: .center) }
        }
      }
      if let failure { Text(failure).foregroundStyle(.red) }
    }.padding(22).task { focused = true }
      .task(id: state.revision) {
        if let book = state.workbook {
          facets = (try? await Task.detached { try book.searchFacets() }.value) ?? .null
        }
      }
      .task(id: identity) {
        do {
          try await Task.sleep(nanoseconds: 180_000_000)
          await search(more: false)
        } catch {}
      }
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
    guard let book = state.workbook, !state.searchQuery.isEmpty else {
      hits = []
      next = nil
      return
    }
    let key = identity
    let query = state.searchQuery
    let old = state.searchHistorical
    let kind = state.searchKind
    let meaning = state.searchMeaning
    let status = state.searchStatus
    let scenario = state.searchScenario
    let cursor = more ? next : nil
    searching = true
    do {
      let found = try await Task.detached {
        try book.search(
          query, kind: kind.isEmpty ? nil : kind, meaning: meaning.isEmpty ? nil : meaning,
          historical: old, cursor: cursor, status: status.isEmpty ? nil : status,
          scenario: scenario.isEmpty ? nil : scenario)
      }.value
      try Task.checkCancellation()
      guard key == identity else { return }
      hits = more ? hits + found.hits : found.hits
      next = found.nextCursor
      incomplete = found.incomplete
      failure = nil
    } catch is CancellationError {} catch {
      if key == identity { failure = error.localizedDescription }
    }
    if key == identity { searching = false }
  }
}
struct SpaceView: View {
  let space: Space
  @ObservedObject var state: WorkspaceState
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 28) {
        if !space.definition.components.isEmpty {
          HStack {
            Spacer()
            Button("Save a pinned copy") {
              do {
                if let id = try state.workbook?.pinSpace(space.id) {
                  state.refresh()
                  state.navigate(.space(id))
                }
              } catch { state.error = error.localizedDescription }
            }.help("Keep exact values and input versions as of now.")
          }
        }
        if space.definition.components.isEmpty {
          Text("Make room for your work").font(.system(size: 28, weight: .medium))
          Text(
            "Drop files here, or describe what you want to organize. Useful tables, documents and views can live together in this space."
          ).foregroundStyle(.secondary).frame(maxWidth: 520, alignment: .leading)
          HStack {
            Button("Add files…") { state.importPanel() }
            Button("Search workbook") { state.navigate(.search) }
          }
        }
        ForEach(space.definition.components) { component in
          NativeComponent(component: component, state: state).id(component.id)
        }
        if space.id == "home" {
          if !state.datasets.isEmpty {
            sectionTitle("Tables")
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
          if let jobs = try? state.workbook?.pendingExtractions(), !jobs.isEmpty {
            sectionTitle("Intake needs attention")
            ForEach(jobs, id: \.text) { job in
              HStack {
                VStack(alignment: .leading) {
                  Text(job["title"].text)
                  Text(job["detail"].text).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Resume") {
                  state.run("Resuming intake") { book, cancel in
                    try book.resumeIntake(job["item_id"].text, cancellation: cancel)
                  }
                }
              }
            }
          }
          if let imports = try? state.workbook?.intakeStatus() {
            ForEach(imports.filter { $0["state"].text != "ready" }, id: \.text) { job in
              let title = job["title"].text
              let completed = job["completed"].text
              let total = job["total"].text
              Text("\(title): \(completed) of \(total) rows imported. Resume from the original source.")
                .font(.callout).foregroundStyle(.secondary)
            }
          }
          sectionTitle("Recent sources and drafts")
          let recent = state.items.filter { $0.kind != "row" }.prefix(20)
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
                  Text(item.status == "draft" ? "Draft · \(item.meaning)" : item.kind.capitalized)
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
              }.padding(.vertical, 6)
            }.buttonStyle(.plain)
          }
        }
      }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  func sectionTitle(_ title: String) -> some View {
    Text(title).font(.title3.weight(.medium)).padding(.top, 10)
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
        Text("Pinned as of " + snapshot.captured).font(.caption).foregroundStyle(.secondary)
      }
      switch component.type {
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
          DatasetView(table: table, state: state, compact: true).frame(height: 280)
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
        if let id = component.itemID { Button("Open document") { state.navigate(.item(id)) } }
      case "search":
        if let hits = try? state.workbook?.search(component.query ?? "", limit: 8).hits {
          ForEach(hits) { hit in
            Button(hit.title) { state.openEvidence(hit.itemID, locator: hit.locator) }.buttonStyle(
              .link)
          }
        }
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
struct PlotPoint: Identifiable {
  let id: String
  let label: String
  let value: Double
}
struct DatasetView: View {
  let table: Dataset
  @ObservedObject var state: WorkspaceState
  var compact = false
  @State private var rows: [Item] = []
  @State private var total = 0
  @State private var selection = IndexSet()
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
      NativeTable(
        columns: table.columns, rows: rows, book: state.workbook,
        onEdit: { rowID, c, value in
          guard let row = rows.first(where: { $0.id == rowID }) else { return }
          var values = row.data.object
          values[c] = value.isEmpty ? .null : .string(value)
          apply([RowEdit(id: row.id, values: values)])
        },
        onSelect: { indexes, c in
          selection = indexes
          column = c
          if let n = indexes.first, rows.indices.contains(n) {
            state.selectedContext = "\(table.title), data row \(offset+n+1): \(rows[n].data.text)"
          }
        },
        onSort: { id, descending in
          state.tableSorts[table.id] = id
          state.tableDescending[table.id] = descending
          state.tableOffsets[table.id] = 0
          load()
        }, onCopy: copyRows, onPaste: pasteCells)
      HStack {
        Button("Previous") {
          state.tableOffsets[table.id] = max(0, offset - 200)
          load()
        }.disabled(offset == 0)
        Text("\(min(offset+1,total))–\(min(offset+rows.count,total)) of \(total)").font(.caption)
        Button("Next") {
          state.tableOffsets[table.id] = offset + 200
          load()
        }.disabled(offset + rows.count >= total)
        Spacer()
        if state.tableUndo[table.id] != nil { Button("Undo") { undo(false) } }
        if compact { Button("Open table") { state.navigate(.table(table.id)) } }
      }.padding(10)
    }
    .task(id: table.id + String(state.revision) + filter) {
      do {
        if !filter.isEmpty { try await Task.sleep(nanoseconds: 180_000_000) }
        load()
      } catch {}
    }
    .sheet(isPresented: $showColumns) { ColumnEditor(table: table, state: state) }
  }
  func load() {
    guard let book = state.workbook else { return }
    let offset = offset
    let filter = filter
    let sort = state.tableSorts[table.id]
    let desc = state.tableDescending[table.id] ?? false
    Task {
      do {
        let result = try await Task.detached {
          (
            try book.rows(
              table.id, offset: offset, limit: 200, query: filter, sort: sort, descending: desc),
            try book.filteredRowCount(table.id, query: filter)
          )
        }.value
        guard self.filter == filter, self.offset == offset else { return }
        rows = result.0
        total = result.1
      } catch { state.error = error.localizedDescription }
    }
  }
  func apply(_ edits: [RowEdit]) {
    guard let book = state.workbook, !state.busy else { return }
    let revision = state.revision
    Task {
      do {
        let change = try await Task.detached {
          try book.editRows(table.id, edits: edits, expectedRevision: revision)
        }.value
        state.tableUndo[table.id] = change.id
        state.tableRedo[table.id] = nil
        state.refresh()
        load()
      } catch { state.error = error.localizedDescription }
    }
  }
  func undo(_ redo: Bool) {
    guard let id = redo ? state.tableRedo[table.id] : state.tableUndo[table.id],
      let book = state.workbook
    else { return }
    Task {
      do {
        let inverse = try await Task.detached { try book.undoTableChange(id) }.value
        if redo {
          state.tableUndo[table.id] = inverse.id
          state.tableRedo[table.id] = nil
        } else {
          state.tableRedo[table.id] = inverse.id
          state.tableUndo[table.id] = nil
        }
        state.refresh()
        load()
      } catch { state.error = error.localizedDescription }
    }
  }
  func copyRows() {
    guard let book = state.workbook else { return }
    let data = selection.compactMap { n -> [String]? in
      guard rows.indices.contains(n) else { return nil }
      let values = book.calculatedValues(rows[n], columns: table.columns)
      return table.columns.map { values[$0.id]?.text ?? "" }
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
    guard let start = selection.first, let text = NSPasteboard.general.string(forType: .string)
    else { return }
    do {
      try require(text.utf8.count <= 4_000_000, "paste_limit", "Paste at most 4 MB at a time.")
      let cells = try CSV.parse(text, delimiter: "\t")
      try require(
        start + cells.count <= rows.count, "paste_range",
        "The paste exceeds the visible rows. Import a file to add a larger table.")
      var edits: [RowEdit] = []
      for (r, values) in cells.enumerated() {
        try require(
          column + values.count <= table.columns.count, "paste_range",
          "The paste exceeds the table columns.")
        var data = rows[start + r].data.object
        for (c, value) in values.enumerated() {
          let target = table.columns[column + c]
          try require(
            target.formula == nil, "calculated_cell", "The paste includes a calculated column.")
          data[target.id] = value.isEmpty ? .null : .string(value)
        }
        edits.append(.init(id: rows[start + r].id, values: data))
      }
      apply(edits)
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
final class GridTable: NSTableView {
  var copyAction: (() -> Void)?, pasteAction: (() -> Void)?
  var activeColumn = 0
  override func mouseDown(with event: NSEvent) {
    let c = column(at: convert(event.locationInWindow, from: nil))
    if c >= 0 { activeColumn = c }
    super.mouseDown(with: event)
    if event.clickCount == 2 { beginCellEditing() }
  }
  func beginCellEditing() {
    guard selectedRow >= 0,
      let field = view(atColumn: activeColumn, row: selectedRow, makeIfNecessary: true)
        as? NSTextField,
      field.isEditable
    else { return }
    window?.makeFirstResponder(field)
    field.selectText(nil)
  }
  @objc func copy(_ sender: Any?) { copyAction?() }
  @objc func paste(_ sender: Any?) { pasteAction?() }
  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
      copyAction?()
      return
    }
    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
      pasteAction?()
      return
    }
    if event.keyCode == 36 || event.keyCode == 76 {
      beginCellEditing()
      return
    }
    super.keyDown(with: event)
  }
}
struct NativeTable: NSViewRepresentable {
  let columns: [Column], rows: [Item]
  let book: Workbook?
  let onEdit: (String, String, String) -> Void
  let onSelect: (IndexSet, Int) -> Void
  let onSort: (String, Bool) -> Void
  let onCopy: () -> Void, onPaste: () -> Void
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let table = GridTable()
    table.delegate = context.coordinator
    table.dataSource = context.coordinator
    table.rowHeight = 30
    table.usesAlternatingRowBackgroundColors = true
    table.allowsMultipleSelection = true
    table.columnAutoresizingStyle = .noColumnAutoresizing
    table.headerView = NSTableHeaderView()
    table.gridStyleMask = [.solidHorizontalGridLineMask]
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.documentView = table
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let table = scroll.documentView as? GridTable else { return }
    table.copyAction = onCopy
    table.pasteAction = onPaste
    let columnSignature = columns.map { $0.id + $0.title + $0.type + ($0.formula ?? "") }.joined()
    if context.coordinator.columnSignature != columnSignature {
      for column in table.tableColumns { table.removeTableColumn(column) }
      for c in columns {
        let column = NSTableColumn(identifier: .init(c.id))
        column.title = c.title
        column.isEditable = c.formula == nil
        column.width = 160
        column.minWidth = 80
        if c.formula == nil {
          column.sortDescriptorPrototype = NSSortDescriptor(key: c.id, ascending: true)
        }
        table.addTableColumn(column)
      }
      context.coordinator.columnSignature = columnSignature
    }
    let signature = rows.map(\.id).joined() + columnSignature
    if context.coordinator.signature != signature {
      context.coordinator.values = rows.map {
        book?.calculatedValues($0, columns: columns) ?? $0.data.object
      }
      let selection = table.selectedRowIndexes.filter { $0 < rows.count }
      table.reloadData()
      table.selectRowIndexes(IndexSet(selection), byExtendingSelection: false)
      context.coordinator.signature = signature
    }
  }
  final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate
  {
    var parent: NativeTable, signature = "", columnSignature = ""
    var values: [[String: Value]] = []
    init(_ parent: NativeTable) { self.parent = parent }
    func numberOfRows(in tableView: NSTableView) -> Int { parent.rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      guard let column = tableColumn,
        let c = parent.columns.first(where: { $0.id == column.identifier.rawValue }),
        values.indices.contains(row)
      else { return nil }
      let cell = NSTextField()
      cell.isBordered = false
      cell.backgroundColor = .clear
      cell.font = .systemFont(ofSize: 13)
      cell.isEditable = c.formula == nil
      cell.isSelectable = true
      cell.delegate = self
      cell.identifier = .init(c.id)
      cell.tag = row
      cell.stringValue = values[row][c.id]?.text ?? ""
      cell.setAccessibilityLabel(c.title + ", row \(row+1)")
      return cell
    }
    func controlTextDidBeginEditing(_ notification: Notification) {
      guard let cell = notification.object as? NSTextField,
        let c = parent.columns.firstIndex(where: { $0.id == cell.identifier?.rawValue })
      else { return }
      parent.onSelect(IndexSet(integer: cell.tag), c)
    }
    func controlTextDidEndEditing(_ notification: Notification) {
      guard let cell = notification.object as? NSTextField, parent.rows.indices.contains(cell.tag),
        let column = cell.identifier?.rawValue
      else { return }
      let row = parent.rows[cell.tag]
      if row.data[column].text != cell.stringValue {
        parent.onEdit(row.id, column, cell.stringValue)
      }
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
      guard let table = notification.object as? GridTable else { return }
      parent.onSelect(table.selectedRowIndexes, table.activeColumn)
    }
    func tableView(
      _ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
    ) {
      if let sort = tableView.sortDescriptors.first, let key = sort.key {
        parent.onSort(key, !sort.ascending)
      }
    }
  }
}
