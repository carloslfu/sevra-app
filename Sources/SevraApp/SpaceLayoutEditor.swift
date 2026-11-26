import SevraCore
import SevraTableUI
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
  @State private var imagePicker: ImageLayoutTarget?
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Edit layout").readingFont(.title2).accessibilityAddTraits(.isHeader)
      Text(
        "Change what this space shows. Your documents, tables and pending work stay in the workbook."
      )
      .foregroundStyle(.secondary)
      TextField("Space title", text: $title)
      Picker("Layout section", selection: $showingHistory) {
        Text("Layout").tag(false)
        Text("History").tag(true)
      }.pickerStyle(.segmented).labelsHidden()
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
                  Text(component.type.capitalized).readingFont(.caption).foregroundStyle(.secondary)
                    .frame(minWidth: 76, alignment: .leading)
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
                if let image = component.visual?.image {
                  imageFields($component, image: image)
                }
                if component.type == "search", space.definition.pinnedAt == nil {
                  TextField(
                    "Search words",
                    text: Binding(
                      get: { component.query ?? "" }, set: { component.query = $0 }))
                }
                if let id = component.spaceID {
                  Text(state.spaces.first { $0.id == id }?.title ?? "Unavailable app")
                    .readingFont(.caption).foregroundStyle(.secondary)
                }
                if Workbook.showsQuery(component) {
                  Text("Shows what its query selects. Ask in chat to change the query.")
                    .readingFont(.caption).foregroundStyle(.secondary)
                } else if let id = component.datasetID {
                  Text(state.datasets.first { $0.id == id }?.title ?? "Missing table binding")
                    .readingFont(.caption).foregroundStyle(.secondary)
                }
                if !(component.children ?? []).isEmpty {
                  Text(
                    "Grouped components retain their bindings. Describe individual group edits in the conversation."
                  )
                  .readingFont(.caption).foregroundStyle(.secondary)
                }
              }.padding(12).background(
                .quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
          }
        }
        if space.definition.pinnedAt == nil {
          Menu("Add section") {
            Button("Text") { add(.init(type: "text", title: "Note", text: "")) }
            Button("Included image") { imagePicker = .init(componentID: nil) }
            Button("Saved search") { add(.init(type: "search", title: "Search", query: "")) }
            Menu("Live app") {
              ForEach(state.spaces.filter { $0.definition.app != nil }) { app in
                Button(app.title) { add(.init(type: "app", title: app.title, spaceID: app.id)) }
              }
            }
            Menu("Table") {
              ForEach(state.datasets) { table in
                Button(table.title) {
                  add(.init(type: "table", title: table.title, datasetID: table.id))
                }
              }
            }
            Divider()
            ForEach(
              SpaceDefinition.defaultHome.components + [
                Component(id: "input", type: "input", title: "Add information"),
                Component(id: "tables", type: "tables", title: "Tables"),
                Component(id: "recent", type: "recent", title: "Recent files and records"),
                Component(id: "reviews", type: "reviews", title: "Drafts to review"),
                Component(id: "intake", type: "intake", title: "Intake needs attention"),
              ]
            ) { component in
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
      .sheet(item: $imagePicker) { target in
        if let book = state.workbook {
          IncludedImagePicker(book: book) { sourceID, title in
            let index = components.firstIndex { $0.id == target.componentID }
            let caption = index.flatMap { components[$0].visual?.image?.caption } ?? ""
            let visual = try book.imageDefinition(sourceID: sourceID, caption: caption)
            if let index {
              components[index].visual = visual
            } else if target.componentID == nil {
              add(.init(type: "visual", title: String(title.prefix(120)), visual: visual))
            }
          }
        }
      }
      .onAppear {
        title = space.title
        components = space.definition.components
      }
      .task(id: showingHistory) {
        guard showingHistory else { return }
        await loadHistory(before: nil)
      }
  }
  private func imageFields(_ component: Binding<Component>, image: ImagePresentation) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField(
        "Caption",
        text: Binding(
          get: { component.wrappedValue.visual?.image?.caption ?? image.caption },
          set: { component.wrappedValue.visual?.image?.caption = $0 }))
      TextField(
        "Image description",
        text: Binding(
          get: {
            component.wrappedValue.visual?.image?.accessibilityDescription
              ?? image.accessibilityDescription
          },
          set: { component.wrappedValue.visual?.image?.accessibilityDescription = $0 }))
      Button("Replace image…") { imagePicker = .init(componentID: component.wrappedValue.id) }
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
                .readingFont(.caption).foregroundStyle(.secondary)
              if !saved.recorded.isEmpty {
                Text(DisplayText.date(saved.recorded)).readingFont(.caption).foregroundStyle(
                  .secondary)
              }
            }
            Spacer()
            if saved.version != space.version {
              Button("Restore") { restore(saved.version) }
                .accessibilityLabel("Restore layout version \(saved.version) as a new version")
            } else {
              Text("Opened version").readingFont(.caption)
            }
          }
        }
        if let nextHistory {
          Button("Earlier versions") { Task { await loadHistory(before: nextHistory) } }
        }
      }
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

private struct ImageLayoutTarget: Identifiable {
  let id = UUID()
  let componentID: String?
}

private struct IncludedImagePicker: View {
  let book: Workbook
  let choose: (String, String) throws -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  @State private var images: [(id: String, title: String)] = []
  @State private var selection: String?
  @State private var failure: String?
  @State private var loading = true

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Choose an included image").font(.headline).accessibilityAddTraits(.isHeader)
      TextField("Search included images", text: $search)
      List(selection: $selection) {
        ForEach(images, id: \.id) { image in
          Text(image.title).tag(image.id)
        }
      }
      if let failure {
        Text(failure).foregroundStyle(.red)
      } else if loading {
        ProgressView().controlSize(.small)
      } else if images.isEmpty {
        Text("No included images match.").foregroundStyle(.secondary)
      }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Use image") {
          guard let image = images.first(where: { $0.id == selection }) else { return }
          do {
            try choose(image.id, image.title)
            dismiss()
          } catch { failure = error.localizedDescription }
        }.keyboardShortcut(.defaultAction).disabled(loading || selection == nil)
      }
    }
    .padding(20).frame(width: 460, height: 380)
    .task(id: search) {
      selection = nil
      images = []
      failure = nil
      loading = true
      let query = search
      do {
        let result = try await Task.detached { try book.includedImageSources(matching: query) }
          .value
        try Task.checkCancellation()
        images = result
        loading = false
      } catch {
        guard !Task.isCancelled else { return }
        failure = error.localizedDescription
        loading = false
      }
    }
  }
}
