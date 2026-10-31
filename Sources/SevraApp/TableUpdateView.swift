import SevraCore
import SevraTableUI
import SwiftUI

struct TableUpdateView: View {
  let book: Workbook
  let sourceID: String
  let intakeID: String?
  @ObservedObject var state: WorkspaceState
  @StateObject private var session = TableUpdateSession()
  @State private var form = TableUpdateForm()
  // Outlives a failed read, so a person can still choose another worksheet.
  @State private var sheetNames: [String] = []
  @State private var notice: String?
  // Restored choices are not edits, and a finished review keeps no draft.
  @State private var ready = false
  @State private var changed = false
  @State private var finished = false
  private var table: Dataset? { state.datasets.first { $0.id == form.target } }
  private var columns: [Column] { table?.columns.filter { $0.formula == nil } ?? [] }
  private var entries: [IntakeColumnMapping] {
    (session.source?.headings.indices ?? 0..<0).map {
      let target: String?
      if case .column(let id) = form.mapping[$0] { target = id } else { target = nil }
      return .init(position: $0, target: target)
    }
  }
  private var blocker: String? { form.blocker(session.source, columns: table?.columns) }
  private var draft: TableUpdateDraft { form.draft(sourceID: sourceID) }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Update a working table").font(.title2)
          Text(
            "Choose how the saved file should change a table. This creates a draft first; your original stays available. Your choices are kept if you leave this page."
          )
          .foregroundStyle(.secondary)
          if let notice { Text(notice).font(.callout) }
          if sheetNames.count > 1 {
            Picker(
              "Worksheet",
              selection: Binding(get: { form.sheet }, set: { choose(sheet: $0) })
            ) {
              Text("Choose a worksheet").tag(Optional<String>.none)
              ForEach(sheetNames, id: \.self) { Text($0).tag(Optional($0)) }
            }
            .fixedSize().disabled(session.busy || state.busy)
          }
          HStack {
            Text(sheetNames.isEmpty ? "Header record" : "Header row")
            TextField(
              "Header record",
              text: Binding(get: { form.header }, set: { choose(header: $0) })
            ).frame(maxWidth: 90)
            Button("Read headings") { Task { await read() } }
              .disabled(Int(form.header).map { $0 > 0 } != true)
          }.disabled(session.busy || state.busy)
          Text(
            !sheetNames.isEmpty
              ? "Use the worksheet row number of the headings. Empty rows are skipped."
              : "Header record is counted from 1. Quoted fields may span several lines."
          )
          .font(.caption).foregroundStyle(.secondary)
          if Int(form.header).map({ $0 > 0 }) != true {
            Text("Enter a whole header record number of 1 or more.")
              .font(.caption).foregroundStyle(.secondary)
          }
          if let source = session.source, !source.needsSheet {
            Text(
              "\(source.incoming) incoming rows · "
                + (source.sheets.isEmpty
                  ? "CSV/TSV values only" : "saved Excel values; formulas are not recalculated")
            ).font(.callout)
            ForEach(source.notes, id: \.self) {
              Text($0).font(.caption).foregroundStyle(.secondary)
            }
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
      if let failure = session.draftFailure {
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
            .disabled(blocker != nil || session.source == nil || state.busy)
          if let blocker {
            Text(blocker).font(.caption).foregroundStyle(.secondary).lineLimit(2)
          }
          Spacer()
          Button("Start over") { Task { await startOver() } }.disabled(state.busy)
          Button("Create update draft") { Task { await publish() } }
            .disabled(
              session.preview == nil || form.meaning.isEmpty || form.scenario.isEmpty || state.busy)
        }
      }.padding(18)
    }
    .task { await open() }
    .onDisappear {
      session.stop()
      guard ready, changed, !finished else { return }
      let current = draft
      let book = book
      session.keep(immediately: true) { try book.saveTableUpdateDraft(current) }
    }
    .onChange(of: draft) { old, new in
      guard ready else { return }
      changed = true
      var before = old
      var after = new
      (before.meaning, before.scenario, after.meaning, after.scenario) = ("", "", "", "")
      // Changing the header or worksheet already restarted reading.
      if before.headerRow == after.headerRow && before.sheet == after.sheet {
        if before == after { session.renewPublication() } else { session.invalidate() }
      }
      let book = book
      session.keep { try book.saveTableUpdateDraft(new) }
    }
  }
  @ViewBuilder private func configuration(_ source: TableUpdateSource) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Picker(
        "Target table",
        selection: Binding(
          get: { form.target },
          set: { next in
            form.choose(target: next, source: session.source, columns: dataset(next)?.columns)
          })
      ) {
        Text("Choose a table").tag("")
        ForEach(state.datasets) { Text($0.title).tag($0.id) }
      }
      Picker(
        "Update method",
        selection: Binding(
          get: { form.mode },
          set: { form.choose(mode: $0, source: session.source, columns: table?.columns) })
      ) {
        Text("Choose method").tag(Optional<TableUpdateMode>.none)
        Text("Add rows").tag(Optional(TableUpdateMode.append))
        Text("Replace all rows").tag(Optional(TableUpdateMode.replace))
        Text("Match by key").tag(Optional(TableUpdateMode.merge))
      }
      Text(
        form.mode == nil
          ? "Choose a method before previewing."
          : form.mode == .append
            ? "Add every incoming row, including duplicates."
            : form.mode == .replace
              ? "Remove every current row from this table, then add the incoming rows. Undo preserves history."
              : "Update matching rows and add new keys. Empty or duplicate keys require correction first."
      )
      .font(.callout).foregroundStyle(form.mode == .replace ? .primary : .secondary)
      if table != nil {
        Text("Map incoming columns").font(.headline)
        Text(
          "Map each stored table column exactly once. Calculated columns are kept. Choose Ignore explicitly for unused input."
        )
        .font(.caption).foregroundStyle(.secondary)
        ForEach(form.suggestionNotes, id: \.self) {
          Text($0).font(.caption).foregroundStyle(.secondary)
        }
        if form.canIgnoreRest(session.source, columns: columns) {
          Button("Ignore the other incoming columns") { form.ignoreRest(session.source) }
        }
        ForEach(Array(source.headings.enumerated()), id: \.offset) { index, heading in
          VStack(alignment: .leading, spacing: 4) {
            Picker(
              "\(index + 1). \(heading.isEmpty ? "Unnamed column" : heading)",
              selection: Binding(
                get: { form.mapping[index] ?? .unselected }, set: { form.mapping[index] = $0 })
            ) {
              Text("Choose column").tag(TableUpdateForm.Choice.unselected)
              Text("Ignore this input").tag(TableUpdateForm.Choice.ignore)
              ForEach(columns) { Text($0.title).tag(TableUpdateForm.Choice.column($0.id)) }
            }
            Text(
              "Examples: "
                + source.examples.prefix(3).map { index < $0.count ? $0[index] : "(empty)" }.joined(
                  separator: " · ")
            )
            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if form.isSuggested(index) {
              Label("Suggested from the same heading", systemImage: "checkmark")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        if form.mode == .merge {
          Text("Match rows using").font(.headline)
          ForEach(columns) { column in
            Toggle(
              column.title,
              isOn: Binding(
                get: { form.keys.contains(column.id) },
                set: {
                  if $0 { form.keys.insert(column.id) } else { form.keys.remove(column.id) }
                })
            ).toggleStyle(.checkbox)
          }
          Text(
            "Keys match exact values. Leading zeros, case and whitespace are preserved. A key that only nearly matches stops the review."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        Picker("New rows describe", selection: $form.meaning) {
          Text("Choose meaning").tag("")
          ForEach(["actual", "estimate", "plan", "commitment", "assumption", "rule"], id: \.self) {
            Text($0.capitalized).tag($0)
          }
        }
        TextField("New row scenario, for example actual or forecast", text: $form.scenario)
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
  private func dataset(_ id: String) -> Dataset? { state.datasets.first { $0.id == id } }
  private func open() async {
    ready = false
    let source = sourceID
    let book = book
    let (saved, waiting) = await Task.detached { () -> (TableUpdateDraft?, Bool) in
      let saved = try? book.tableUpdateDraft(source)
      let job = saved?.intakeID.flatMap { try? book.intakeJob($0) }
      return (saved, job?.state == "awaiting_update")
    }.value
    if let saved { form.restore(saved) }
    form.intake = intakeID ?? (waiting ? saved?.intakeID : nil)
    await inspect()
    if let saved, let headings = session.source?.headings, session.source?.needsSheet == false {
      let kept = saved.reconciled(headings: headings, columns: table?.columns)
      if kept != saved {
        notice = "Some saved choices no longer apply and were cleared."
        let intake = form.intake
        form.restore(kept)
        form.intake = intake
      } else {
        notice = "Your saved choices were restored. Review them before previewing."
      }
    }
    form.suggest(session.source, columns: table?.columns)
    ready = true
  }
  private func choose(header next: String) {
    guard next != form.header else { return }
    form.header = next
    form.clearInputs()
    session.invalidate(clearSource: true)
  }
  private func choose(sheet next: String?) {
    guard next != form.sheet else { return }
    form.sheet = next
    form.clearInputs()
    Task { await read() }
  }
  private func read() async {
    await inspect()
    form.suggest(session.source, columns: table?.columns)
  }
  private func startOver() async {
    let source = sourceID
    let book = book
    let job = form.intake
    finished = false
    ready = false
    changed = false
    session.invalidate()
    // Queued behind any earlier save, so that save cannot bring the draft back.
    session.keep(immediately: true) { try book.discardTableUpdateDraft(source) }
    form = TableUpdateForm()
    form.intake = job
    notice = nil
    await read()
    ready = true
  }
  private func inspect() async {
    guard let row = Int(form.header), row > 0 else { return }
    let source = sourceID
    let selected = form.sheet
    await session.inspect { cancel in
      try await Task.detached {
        try book.inspectTableUpdateSource(
          source, headerRow: row, sheet: selected, cancellation: cancel)
      }.value
    }
    if let names = session.source?.sheets, !names.isEmpty { sheetNames = names }
  }
  private func inspectChanges() async {
    guard let operation = form.mode else { return }
    let selected = form.target
    let mapped = entries
    let match = form.keys.sorted()
    let row = Int(form.header) ?? 0
    let source = sourceID
    let worksheet = session.source?.sheet
    await session.inspectChanges { cancel in
      try await Task.detached {
        try book.previewTableUpdate(
          sourceID: source, datasetID: selected,
          mode: operation, mapping: mapped, keys: match, headerRow: row, sheet: worksheet,
          cancellation: cancel)
      }.value
    }
  }
  private func publish() async {
    guard let preview = session.preview else { return }
    let owner = state.interactionIdentity
    let newMeaning = form.meaning
    let newScenario = form.scenario
    let job = form.intake
    finished = true
    let result = await session.publish { token, cancel in
      try await Task.detached {
        try book.proposeTableUpdate(
          sourceID: preview.sourceID, datasetID: preview.datasetID,
          mode: preview.mode, mapping: preview.mapping, keys: preview.keys,
          headerRow: preview.headerRow, sheet: preview.sheet,
          newRowMeaning: newMeaning, newRowScenario: newScenario,
          expectedRevision: preview.revision, expectedFingerprint: preview.fingerprint,
          intakeID: job, token: token, cancellation: cancel)
      }.value
    }
    guard let result else {
      finished = false
      return
    }
    guard state.interactionActive, state.interactionIdentity == owner, state.workbook === book
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
        "\(preview.added) added · \(preview.changed) changed · \(preview.removed) removed · \(preview.unchanged) unchanged"
      )
      .font(.headline)
      if preview.repeatedIncomingRows > 0 {
        Text("Repeated incoming rows: \(preview.repeatedIncomingRows)").font(.callout)
      }
      if preview.rowsMatchingTarget > 0 {
        Text("Incoming rows that exactly match existing values: \(preview.rowsMatchingTarget)")
          .font(.callout)
      }
      ForEach(preview.limitations, id: \.self) {
        Text($0).font(.caption).foregroundStyle(.secondary)
      }
      if !preview.examples.isEmpty {
        Text("Examples (up to 20)").font(.headline)
        ForEach(Array(preview.examples.enumerated()), id: \.offset) { _, example in
          VStack(alignment: .leading, spacing: 4) {
            Text(
              example["operation"].text.capitalized
                + (preview.sheet == nil ? " · Source record " : " · Worksheet row ")
                + (example["sourceRecord"].int.map(String.init) ?? "unknown")
            ).font(.subheadline.weight(.medium))
            ForEach(preview.columns.filter { $0.formula == nil }) { column in
              let after = example["after"][column.id]
              let before = example["before"][column.id]
              let moved = example["operation"].text == "change" && before != after
              Text(column.title + ": " + (moved ? shown(before) + " → " : "") + shown(after))
              .font(.callout).textSelection(.enabled)
            }
          }.padding(.vertical, 6)
        }
      }
    }
  }
  private func shown(_ value: Value) -> String { value == .null ? "(empty)" : value.text }
}
