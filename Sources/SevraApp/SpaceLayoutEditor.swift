import SevraCore
import SwiftUI

/// Local editing is deliberate and reviewable. Submission uses the exact opened
/// space version and stable component IDs; failures retain the user's draft.
struct SpaceLayoutEditor: View {
  let space: Space
  @ObservedObject var state: WorkspaceState
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var components: [Component] = []
  @State private var history: [SpaceRevision] = []
  @State private var failure: String?
  @State private var saving = false
  @State private var showingHistory = false
  @State private var nextHistory: Int?
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Edit layout").font(.title2)
      Text(
        "Change what this space shows. Your documents, tables and pending work stay in the workbook."
      )
      .foregroundStyle(.secondary)
      TextField("Space title", text: $title)
      Picker("Mode", selection: $showingHistory) {
        Text("Layout").tag(false)
        Text("History").tag(true)
      }.pickerStyle(.segmented)
      if showingHistory {
        historyView
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach($components) { $component in
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                  TextField("Component label", text: $component.title)
                    .accessibilityLabel("Label for " + component.type)
                  Text(component.type).font(.caption).foregroundStyle(.secondary)
                  Button {
                    move(component.id, direction: -1)
                  } label: {
                    Image(systemName: "arrow.up")
                  }.accessibilityLabel("Move " + component.title + " up")
                    .help("Move " + component.title + " up")
                    .disabled(components.first?.id == component.id)
                  Button {
                    move(component.id, direction: 1)
                  } label: {
                    Image(systemName: "arrow.down")
                  }.accessibilityLabel("Move " + component.title + " down")
                    .help("Move " + component.title + " down")
                    .disabled(components.last?.id == component.id)
                  Button("Remove") { components.removeAll { $0.id == component.id } }
                    .accessibilityLabel("Remove " + component.title + " from layout")
                }
                if component.type == "text" {
                  TextField(
                    "Text",
                    text: Binding(
                      get: { component.text ?? "" }, set: { component.text = $0 }), axis: .vertical
                  )
                  .lineLimit(2...8)
                }
                if component.type == "search", space.definition.pinnedAt == nil {
                  TextField(
                    "Search words",
                    text: Binding(
                      get: { component.query ?? "" }, set: { component.query = $0 }))
                }
                if let id = component.datasetID {
                  Text(state.datasets.first { $0.id == id }?.title ?? "Missing table binding")
                    .font(.caption).foregroundStyle(.secondary)
                }
                if !(component.children ?? []).isEmpty {
                  Text(
                    "Grouped components retain their bindings. Describe individual group edits in the conversation."
                  )
                  .font(.caption).foregroundStyle(.secondary)
                }
              }.padding(12).background(
                .quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
          }
        }
        if space.definition.pinnedAt == nil {
          Menu("Add section") {
            Button("Text") { add(.init(type: "text", title: "Note", text: "")) }
            Button("Receive delivery form") { addReceivingForm() }
            Button("Saved search") { add(.init(type: "search", title: "Search", query: "")) }
            Menu("Table") {
              ForEach(state.datasets) { table in
                Button(table.title) {
                  add(.init(type: "table", title: table.title, datasetID: table.id))
                }
              }
            }
            Divider()
            ForEach(SpaceDefinition.defaultHome.components) { component in
              Button(component.title) {
                add(.init(type: component.type, title: component.title))
              }
            }
          }.disabled(components.count >= 16)
        }
      }
      if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        if !showingHistory {
          Button("Save layout") { save() }.keyboardShortcut(.defaultAction)
        }
      }
    }.padding(24).frame(minWidth: 560, idealWidth: 680, minHeight: 440, idealHeight: 560)
      .disabled(saving)
      .interactiveDismissDisabled(saving)
      .onAppear {
        title = space.title
        components = space.definition.components
      }
      .task(id: showingHistory) {
        guard showingHistory else { return }
        await loadHistory(before: nil)
      }
  }
  private var historyView: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 14) {
        ForEach(history) { saved in
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text("Version \(saved.version): \(saved.title)").fontWeight(.medium)
              Text(saved.definition.components.map(\.title).joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary)
              if !saved.recorded.isEmpty {
                Text(DisplayText.date(saved.recorded)).font(.caption).foregroundStyle(.secondary)
              }
            }
            Spacer()
            if saved.version != space.version {
              Button("Restore") { restore(saved.version) }
                .accessibilityLabel("Restore layout version \(saved.version) as a new version")
            } else {
              Text("Opened version").font(.caption)
            }
          }
        }
        if let nextHistory {
          Button("Earlier versions") { Task { await loadHistory(before: nextHistory) } }
        }
      }
    }
  }
  private func addReceivingForm() {
    guard !saving, let book = state.workbook else { return }
    saving = true
    Task {
      do {
        let form = try await Task.detached {
          let action = try book.saveApplicationDefinition(
            logicalID: identifier(), content: ActionRegistry.receivingDefinition(),
            actor: .human("SevraApp.layout"))
          return try book.saveApplicationDefinition(
            logicalID: identifier(),
            content: ActionRegistry.formDefinition(target: action),
            actor: .human("SevraApp.layout"))
        }.value
        components.append(
          .init(
            type: "form", title: form.title,
            definitionBinding: .object([
              "mode": .string("live"), "logicalID": .string(form.logicalID),
            ])))
        state.refresh()
      } catch { failure = error.localizedDescription }
      saving = false
    }
  }
  private func add(_ component: Component) { components.append(component) }
  private func move(_ id: String, direction: Int) {
    guard let index = components.firstIndex(where: { $0.id == id }),
      components.indices.contains(index + direction)
    else { return }
    components.swapAt(index, index + direction)
  }
  private func loadHistory(before: Int?) async {
    guard let book = state.workbook else { return }
    do {
      let page = try await Task.detached { try book.spaceHistory(space.id, before: before) }.value
      try Task.checkCancellation()
      if before == nil { history = page } else { history += page }
      nextHistory = page.count == 20 ? page.last?.version : nil
    } catch is CancellationError {} catch { failure = error.localizedDescription }
  }
  private func edits() -> [SpaceEdit] {
    if title == space.title && components == space.definition.components { return [] }
    let wanted = Set(components.map(\.id))
    let old = Dictionary(uniqueKeysWithValues: space.definition.components.map { ($0.id, $0) })
    var changes: [SpaceEdit] = []
    if title != space.title { changes.append(.init(operation: "rename", title: title)) }
    for component in space.definition.components where !wanted.contains(component.id) {
      changes.append(.init(operation: "remove", componentID: component.id))
    }
    var next: String?
    for component in components.reversed() {
      if let previous = old[component.id] {
        if previous != component {
          changes.append(
            .init(operation: "replace", componentID: component.id, component: component))
        }
        changes.append(
          .init(
            operation: "move", componentID: component.id, beforeID: next,
            at: next == nil ? "last" : nil))
      } else {
        changes.append(
          .init(
            operation: "insert", beforeID: next, at: next == nil ? "last" : nil,
            component: component))
      }
      next = component.id
    }
    return changes
  }
  private func save() {
    guard let book = state.workbook else { return }
    let changes = edits()
    if changes.isEmpty {
      dismiss()
      return
    }
    saving = true
    Task {
      do {
        _ = try await Task.detached {
          try book.editSpace(
            space.id, expectedVersion: space.version, edits: changes,
            actor: .human("SevraApp.layout"))
        }.value
        state.refresh()
        dismiss()
      } catch { failure = error.localizedDescription }
      saving = false
    }
  }
  private func restore(_ version: Int) {
    guard let book = state.workbook else { return }
    saving = true
    Task {
      do {
        _ = try await Task.detached {
          try book.restoreSpace(
            space.id, version: version, expectedVersion: space.version,
            actor: .human("SevraApp.layout"))
        }.value
        state.refresh()
        dismiss()
      } catch { failure = error.localizedDescription }
      saving = false
    }
  }
}
