import SevraCore
import SevraTableUI
import SwiftUI

struct TableUpdateView: View {
  private enum MappingChoice: Hashable {
    case unselected, ignore
    case column(String)
  }
  let book: Workbook
  let sourceID: String
  let intakeID: String?
  @ObservedObject var state: WorkspaceState
  @StateObject private var session = TableUpdateSession()
  @State private var target = ""
  @State private var mode: TableUpdateMode?
  @State private var header = "1"
  @State private var mapping: [Int: MappingChoice] = [:]
  @State private var keys = Set<String>()
  @State private var meaning = ""
  @State private var scenario = ""
  private var table: Dataset? { state.datasets.first { $0.id == target } }
  private var columns: [Column] { table?.columns.filter { $0.formula == nil } ?? [] }
  private var entries: [IntakeColumnMapping] {
    (session.source?.headings.indices ?? 0..<0).map {
      let target: String?
      if case .column(let id) = mapping[$0] { target = id } else { target = nil }
      return .init(position: $0, target: target)
    }
  }
  private var canPreview: Bool {
    guard let source = session.source, table != nil, let mode else { return false }
    let targets = mapping.values.compactMap {
      if case .column(let id) = $0 { return id }
      return nil
    }
    return source.headerRow == Int(header) && mapping.count == source.headings.count
      && !mapping.values.contains(.unselected)
      && Set(targets) == Set(columns.map(\.id)) && targets.count == columns.count
      && (mode != .merge || !keys.isEmpty)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Update a working table").font(.title2)
          Text(
            "Choose how the saved CSV or TSV should change a table. This creates a draft first; your original stays available."
          )
          .foregroundStyle(.secondary)
          HStack {
            TextField("Header record", text: $header).frame(maxWidth: 190)
            Button("Read headings") { Task { await inspect() } }
              .disabled(Int(header).map { $0 > 0 } != true)
          }.disabled(session.busy || state.busy)
          Text("Header record is counted from 1. Quoted fields may span several lines.")
            .font(.caption).foregroundStyle(.secondary)
          if Int(header).map({ $0 > 0 }) != true {
            Text("Enter a whole header record number of 1 or more.")
              .font(.caption).foregroundStyle(.secondary)
          }
          if let source = session.source {
            Text("\(source.incoming) incoming rows · CSV/TSV values only").font(.callout)
            configuration(source)
            if let preview = session.preview {
              Divider()
              TableUpdateSummary(preview: preview)
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
      }
      if let failure = session.failure {
        Text(failure).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal, 22)
      }
      Divider()
      HStack {
        if session.busy {
          ProgressView().controlSize(.small)
          Text("Preparing review…")
          Button("Stop") { session.stop() }
        } else {
          Button("Preview changes") { Task { await inspectChanges() } }
            .disabled(!canPreview || state.busy)
          Spacer()
          Button("Create update draft") { Task { await publish() } }
            .disabled(session.preview == nil || meaning.isEmpty || scenario.isEmpty || state.busy)
        }
      }.padding(18)
    }
    .task { await inspect() }
    .onDisappear { session.stop() }
    .onChange(of: header) { _, _ in
      mapping = [:]
      session.invalidate(clearSource: true)
    }
    .onChange(of: target) { _, _ in
      mapping = [:]
      keys = []
      session.invalidate()
    }
    .onChange(of: mode) { _, _ in
      keys = []
      session.invalidate()
    }
    .onChange(of: mapping) { _, _ in session.invalidate() }
    .onChange(of: keys) { _, _ in session.invalidate() }
    .onChange(of: meaning) { _, _ in session.invalidate() }
    .onChange(of: scenario) { _, _ in session.invalidate() }
  }
  @ViewBuilder private func configuration(_ source: TableUpdateSource) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Picker("Target table", selection: $target) {
        Text("Choose a table").tag("")
        ForEach(state.datasets) { Text($0.title).tag($0.id) }
      }
      Picker("Update method", selection: $mode) {
        Text("Choose method").tag(Optional<TableUpdateMode>.none)
        Text("Add rows").tag(Optional(TableUpdateMode.append))
        Text("Replace all rows").tag(Optional(TableUpdateMode.replace))
        Text("Match by key").tag(Optional(TableUpdateMode.merge))
      }
      Text(
        mode == nil
          ? "Choose a method before previewing."
          : mode == .append
            ? "Add every incoming row, including duplicates."
            : mode == .replace
              ? "Remove every current row from this table, then add the incoming rows. Undo preserves history."
              : "Update matching rows and add new keys. Empty or duplicate keys require correction first."
      )
      .font(.callout).foregroundStyle(mode == .replace ? .primary : .secondary)
      if table != nil {
        Text("Map incoming columns").font(.headline)
        Text(
          "Map each stored table column exactly once. Calculated columns are kept. Choose Ignore explicitly for unused input."
        )
        .font(.caption).foregroundStyle(.secondary)
        ForEach(Array(source.headings.enumerated()), id: \.offset) { index, heading in
          VStack(alignment: .leading, spacing: 4) {
            Picker(
              "\(index + 1). \(heading.isEmpty ? "Unnamed column" : heading)",
              selection: Binding(
                get: { mapping[index] ?? .unselected }, set: { mapping[index] = $0 })
            ) {
              Text("Choose column").tag(MappingChoice.unselected)
              Text("Ignore this input").tag(MappingChoice.ignore)
              ForEach(columns) { Text($0.title).tag(MappingChoice.column($0.id)) }
            }
            Text(
              "Examples: "
                + source.examples.prefix(3).map { index < $0.count ? $0[index] : "(empty)" }.joined(
                  separator: " · ")
            )
            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
          }
        }
        if mode == .merge {
          Text("Match rows using").font(.headline)
          ForEach(columns) { column in
            Toggle(
              column.title,
              isOn: Binding(
                get: { keys.contains(column.id) },
                set: {
                  if $0 { keys.insert(column.id) } else { keys.remove(column.id) }
                })
            ).toggleStyle(.checkbox)
          }
          Text("Keys match exact values. Leading zeros, case and whitespace are preserved.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Picker("New rows describe", selection: $meaning) {
          Text("Choose meaning").tag("")
          ForEach(["actual", "estimate", "plan", "commitment", "assumption", "rule"], id: \.self) {
            Text($0.capitalized).tag($0)
          }
        }
        TextField("New row scenario, for example actual or forecast", text: $scenario)
        Text(
          "Matching rows keep their current meaning and scenario. Updating values does not post inventory or financial transactions."
        )
        .font(.caption).foregroundStyle(.secondary)
      } else if state.datasets.isEmpty {
        Text(
          "There are no working tables yet. Create a table from the saved file or start one in the conversation."
        )
      }
    }.disabled(session.busy || state.busy)
  }
  private func inspect() async {
    guard let row = Int(header), row > 0 else { return }
    let source = sourceID
    await session.inspect { cancel in
      try await Task.detached {
        try book.inspectTableUpdateSource(source, headerRow: row, cancellation: cancel)
      }.value
    }
  }
  private func inspectChanges() async {
    guard let operation = mode else { return }
    let selected = target
    let mapped = entries
    let match = keys.sorted()
    let row = Int(header) ?? 0
    let source = sourceID
    await session.inspectChanges { cancel in
      try await Task.detached {
        try book.previewTableUpdate(
          sourceID: source, datasetID: selected,
          mode: operation, mapping: mapped, keys: match, headerRow: row, cancellation: cancel)
      }.value
    }
  }
  private func publish() async {
    guard let preview = session.preview else { return }
    let owner = state.interactionIdentity
    let newMeaning = meaning
    let newScenario = scenario
    let job = intakeID
    let result = await session.publish { token, cancel in
      try await Task.detached {
        try book.proposeTableUpdate(
          sourceID: preview.sourceID, datasetID: preview.datasetID,
          mode: preview.mode, mapping: preview.mapping, keys: preview.keys,
          headerRow: preview.headerRow,
          newRowMeaning: newMeaning, newRowScenario: newScenario,
          expectedRevision: preview.revision, expectedFingerprint: preview.fingerprint,
          intakeID: job, token: token, cancellation: cancel)
      }.value
    }
    guard let result, state.interactionActive, state.interactionIdentity == owner,
      state.workbook === book
    else { return }
    state.refresh()
    state.navigate(.item(result.id))
  }
}

struct TableUpdateSummary: View {
  let preview: TableUpdatePreview
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(
        "\(preview.added) added · \(preview.changed) changed · \(preview.removed) removed · \(preview.unchanged) matched rows unchanged"
      )
      .font(.headline)
      Text(
        "\(preview.repeatedIncomingRows) repeated incoming rows · \(preview.rowsMatchingTarget) incoming rows exactly match existing values"
      )
      .font(.callout)
      ForEach(preview.limitations, id: \.self) {
        Text($0).font(.caption).foregroundStyle(.secondary)
      }
      if !preview.examples.isEmpty {
        Text("Examples (up to 20)").font(.headline)
        ForEach(Array(preview.examples.enumerated()), id: \.offset) { _, example in
          VStack(alignment: .leading, spacing: 4) {
            Text(
              example["operation"].text.capitalized + " · Source record "
                + (example["sourceRecord"].int.map(String.init) ?? "unknown")
            ).font(.subheadline.weight(.medium))
            ForEach(preview.columns.filter { $0.formula == nil }) { column in
              let after = example["after"][column.id]
              let before = example["before"][column.id]
              Text(
                column.title + ": "
                  + (example["operation"].text == "change" ? shown(before) + " → " : "")
                  + shown(after)
              )
              .font(.callout).textSelection(.enabled)
            }
          }.padding(.vertical, 6)
        }
      }
    }
  }
  private func shown(_ value: Value) -> String { value == .null ? "(empty)" : value.text }
}
