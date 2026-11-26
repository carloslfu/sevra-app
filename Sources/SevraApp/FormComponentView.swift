import SevraCore
import SevraPreviewUI
import SevraTableUI
import SwiftUI

struct FormComponentView: View {
  let component: Component
  @ObservedObject var workspace: WorkspaceState
  @State private var session: FormDraftSession?
  @State private var currentFormID: String?
  @State private var failure: String?
  var body: some View {
    Group {
      if let session {
        NativeFormEditor(session: session, currentFormID: currentFormID, workspace: workspace)
      } else if let failure {
        Text(failure).foregroundStyle(.red).textSelection(.enabled)
      } else {
        ProgressView("Opening form")
      }
    }
    .task(id: (component.definitionBinding?.text ?? "") + String(workspace.revision)) {
      guard let book = workspace.workbook, let binding = component.definitionBinding else { return }
      do {
        let definition = try await Task.detached { try book.boundApplicationDefinition(binding) }
          .value
        guard !Task.isCancelled else { return }
        currentFormID = definition.id
        let space: String
        if case .space(let id) = workspace.route { space = id } else { space = "standalone" }
        let key = try FormDraftState.componentKey(spaceID: space, componentID: component.id)
        guard let owner = workspace.formDrafts.session(key) else { return }
        session = owner
        await owner.open(definition.id)
      } catch { failure = error.localizedDescription }
    }
  }
}

private struct NativeFormEditor: View {
  @ObservedObject var session: FormDraftSession
  let currentFormID: String?
  @ObservedObject var workspace: WorkspaceState
  @AccessibilityFocusState private var validationFocused: Bool
  /// The draft's form runs a saved tool, so it runs without a preview step.
  @State private var runsTool = false
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let definition = session.definition, let state = session.state {
        if state.definitionID != currentFormID {
          Text("This draft keeps the form version you opened. A newer form is available.")
            .readingFont(.callout).foregroundStyle(.secondary)
        }
        if let receipt = state.lastReceipt {
          if let runID = receipt["workflowRunID"].string {
            Label("Saved workflow run", systemImage: "checkmark.circle")
            Button("Open workflow") { workspace.navigate(.workflow(runID)) }
          } else if receipt["state"] == .string("applied") {
            ToolRunOutcome(receipt: receipt, workspace: workspace)
          } else {
            Label(
              "Saved \(receipt["proposals"].array.count) draft \(receipt["proposals"].array.count == 1 ? "proposal" : "proposals")",
              systemImage: "checkmark.circle")
            Text("Open the saved proposals to inspect their current status.").foregroundStyle(
              .secondary)
            Button("Review drafts") { workspace.navigate(.reviews) }
          }
          HStack {
            Button("New entry") {
              Task { await session.useCurrent(currentFormID ?? definition.id, carryInputs: false) }
            }
          }
        } else {
          if !session.issues.isEmpty {
            Text(
              "Check \(session.issues.count) input issues. "
                + session.issues.map { $0["message"].text }.joined(separator: " ")
            )
            .foregroundStyle(.red).textSelection(.enabled)
            .accessibilityFocused($validationFocused)
          }
          ForEach(definition.payload["fields"].array, id: \.text) { presentation in
            let id = presentation["parameter"].text
            if let parameter = definition.parameters.array.first(where: { $0["id"].text == id }) {
              FormParameterField(
                parameter: parameter, label: presentation["label"].string,
                help: presentation["help"].string, value: parameterBinding(parameter),
                workbook: workspace.workbook, issues: session.issues)
            }
          }
          .disabled(session.busy)
          if let preview = session.preview {
            Divider()
            Text(preview["effect"].text).readingFont(.callout)
            ForEach(Array(preview["documents"].array.enumerated()), id: \.offset) { _, document in
              Text(document["title"].text).readingFont(.headline).accessibilityAddTraits(.isHeader)
              Text(document["body"].text).textSelection(.enabled)
            }
            ForEach(Array(preview["steps"].array.enumerated()), id: \.offset) { index, step in
              Text("\(index + 1). " + step["title"].text).readingFont(.callout)
            }
            Button(
              preview["kind"] == .string("workflow")
                ? "Start workflow" : preview["tool"] != .null ? "Run" : "Save draft proposals"
            ) {
              let book = workspace.workbook
              let owner = workspace.interactionIdentity
              let origin = workspace.route
              Task {
                await session.submit()
                guard workspace.workbook === book, workspace.interactionIdentity == owner else {
                  return
                }
                workspace.refresh()
                if let runID = session.state?.lastReceipt?["workflowRunID"].string {
                  if workspace.route == origin { workspace.navigate(.workflow(runID)) }
                  workspace.continueWorkflow(runID)
                }
              }
            }.disabled(session.busy || workspace.busy)
          } else if runsTool {
            // A tool form runs at once: its change is recorded and one Undo takes it back.
            VStack(alignment: .leading, spacing: 6) {
              Button(definition.title) { check(run: true) }
                .buttonStyle(.borderedProminent)
                .disabled(session.busy || workspace.busy)
              Text("Runs right away. If it changes rows, you can undo the change.")
                .readingFont(.caption).foregroundStyle(.secondary)
            }
          } else {
            Button("Preview") { check(run: false) }.disabled(session.busy)
          }
          if let currentFormID, currentFormID != state.definitionID || session.stale {
            Button("Use current form and keep these inputs") {
              Task { await session.useCurrent(currentFormID, carryInputs: true) }
            }.readingFont(.callout).disabled(session.busy)
          }
        }
        if !state.alternatives.isEmpty {
          DisclosureGroup("Saved alternatives (\(state.alternatives.count))") {
            ForEach(Array(state.alternatives.enumerated()), id: \.element.id) { index, saved in
              HStack {
                Text("Saved draft \(index + 1)")
                Button("Open") { Task { await session.restoreAlternative(saved.id) } }
                  .accessibilityLabel("Open saved draft \(index + 1)")
                Button("Remove") { Task { await session.discardAlternative(saved.id) } }
                  .accessibilityLabel("Remove saved draft \(index + 1)")
              }.disabled(session.busy)
            }
          }
        }
      }
      if session.busy { ProgressView().controlSize(.small) }
      if let failure = session.failure {
        Text(failure).foregroundStyle(.red).textSelection(.enabled)
        if session.conflict {
          Button("Keep both drafts") { Task { await session.keepBoth() } }
        } else if session.dirty {
          Button("Retry saving inputs") { Task { _ = await session.flush() } }
        }
      }
    }
    .task(id: session.state?.definitionID) {
      guard let book = workspace.workbook, let id = session.state?.definitionID else { return }
      let found = (try? await Task.detached { try book.formRunsTool(id) }.value) ?? false
      guard !Task.isCancelled else { return }
      runsTool = found
    }
    .announceStatus(
      session.failure
        ?? (session.state?.lastReceipt.map {
          $0["state"] == .string("applied")
            ? $0["summary"].string ?? "Done." : "Saved. Review the result before business use."
        }))
  }
  /// Checks the inputs, then previews them or, for a tool form, runs it. A problem moves
  /// VoiceOver to the list of input issues.
  private func check(run: Bool) {
    validationFocused = false
    let book = workspace.workbook
    let origin = workspace.route
    let owner = workspace.interactionIdentity
    Task {
      if run { await session.run() } else { await session.prepare() }
      guard workspace.workbook === book, workspace.interactionIdentity == owner else { return }
      if run, session.state?.lastReceipt != nil { workspace.refresh() }
      if !session.issues.isEmpty, workspace.route == origin,
        workspace.readingWindow?.isKeyWindow == true
      {
        validationFocused = true
      }
    }
  }
  private func parameterBinding(_ parameter: Value) -> Binding<Value> {
    let key = parameter["id"].text
    return .init(
      get: {
        session.state?.arguments.object[key] ?? parameter.object["default"] ?? .null
      },
      set: { value in
        var arguments = session.state?.arguments.object ?? [:]
        arguments[key] = value
        session.update(.object(arguments))
      })
  }
}

struct FormParameterField: View {
  let parameter: Value
  var label: String?
  var help: String?
  @Binding var value: Value
  let workbook: Workbook?
  var evidenceIDs: [String]?
  var context: String?
  var issues: [Value] = []
  var path: [Value] = []
  @State private var choosingEvidence = false
  @State private var evidenceTitle: String?
  private var presentation: FormFieldPresentation {
    .init(
      parameter: parameter, label: label, help: help, context: context, issues: issues, path: path)
  }
  private var title: String { presentation.title }
  private var fieldPath: [Value] { presentation.path }
  private var fieldIssues: [String] { presentation.issues }
  private var accessibleTitle: String { presentation.accessibleTitle }
  private var fieldHelp: String { presentation.help }
  private var required: Bool { parameter["required"] == .bool(true) }
  /// The input is a plain text field, which carries its own placeholder.
  private var textEntry: Bool {
    !["entries", "choice", "boolean", "item"].contains(parameter["type"].text)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Like a view's button: required is the norm, and an optional input says so. A text
      // field says it in its placeholder; other controls say it beside the title.
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(title).readingFont(.callout, weight: .medium)
        if !required && !textEntry {
          Text("Optional").readingFont(.caption).foregroundStyle(.secondary)
        }
      }
      switch parameter["type"].text {
      case "entries":
        ForEach(value.array.indices, id: \.self) { index in
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text("Line \(index + 1)").readingFont(.caption)
              Spacer()
              Button("Remove line") {
                var rows = value.array
                guard rows.indices.contains(index) else { return }
                rows.remove(at: index)
                value = .array(rows)
              }
              .accessibilityLabel("Remove " + title + ", line \(index + 1)")
            }
            ForEach(parameter["fields"].array, id: \.text) { field in
              AnyView(
                FormParameterField(
                  parameter: field, value: entryBinding(index, field: field), workbook: workbook,
                  evidenceIDs: evidenceIDs,
                  context: [context, title, "Line \(index + 1)"].compactMap { $0 }.joined(
                    separator: ", "),
                  issues: issues,
                  path: fieldPath + [.number(Double(index)), .string(field["id"].text)]))
            }
          }.accessibilityElement(children: .contain)
            .accessibilityLabel(title + ", line \(index + 1)")
            .padding(12).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        }
        Button("Add delivery line") { value = .array(value.array + [.object([:])]) }
          .accessibilityLabel("Add line to " + accessibleTitle)
          .accessibilityHint(fieldHelp)
          .disabled(value.array.count >= (parameter["maxEntries"].int ?? 0))
      case "choice", "boolean":
        Picker(
          title,
          selection: Binding(
            get: { value == .null ? "" : value.text },
            set: {
              value =
                $0.isEmpty
                ? .null : parameter["type"].text == "boolean" ? .bool($0 == "true") : .string($0)
            })
        ) {
          Text("Choose…").tag("")
          if parameter["type"].text == "boolean" {
            Text("Yes").tag("true")
            Text("No").tag("false")
          } else {
            ForEach(parameter["choices"].array, id: \.text) { Text($0.text).tag($0.text) }
          }
        }.labelsHidden().accessibilityLabel(accessibleTitle).accessibilityHint(fieldHelp)
      case "item":
        if let evidenceIDs {
          ClarificationEvidenceField(
            title: accessibleTitle, evidenceIDs: evidenceIDs, value: $value, workbook: workbook
          ).accessibilityHint(fieldHelp)
        } else {
          HStack {
            Button(
              value == .null || value.text.isEmpty
                ? "Choose evidence…" : evidenceTitle ?? "Selected evidence"
            ) { choosingEvidence = true }
            .accessibilityLabel(accessibleTitle + ": " + (evidenceTitle ?? "Choose evidence"))
            .accessibilityHint(fieldHelp)
            if value != .null {
              Button("Open") {
                NotificationCenter.default.post(name: .sevraOpenEvidence, object: value.text)
              }.accessibilityLabel(
                "Open " + accessibleTitle + ": " + (evidenceTitle ?? "Selected evidence"))
              if parameter["required"] != .bool(true) {
                Button("Clear") { value = .null }.accessibilityLabel("Clear " + accessibleTitle)
              }
            }
          }
          .sheet(isPresented: $choosingEvidence) {
            if let workbook {
              FormEvidencePicker(workbook: workbook) { item in
                value = .string(item.0)
                evidenceTitle = item.1
              }
            }
          }
          .task(id: value.text) {
            guard let workbook, value != .null else {
              evidenceTitle = nil
              return
            }
            let id = value.text
            evidenceTitle = try? await Task.detached { try workbook.item(id).title }.value
          }
        }
      default:
        TextField(
          title,
          text: Binding(
            get: { value == .null ? "" : value.text },
            set: { value = formFieldValue($0, parameter: parameter) }),
          prompt: Text(FormFieldPresentation.prompt(parameter["type"].text, required: required)),
          axis: parameter["type"].text == "text" ? .vertical : .horizontal
        )
        .lineLimit(1...12).textFieldStyle(.roundedBorder).accessibilityLabel(accessibleTitle)
        .accessibilityHint(fieldHelp)
        if let unit = parameter["unit"].string {
          Text(unit).readingFont(.caption).foregroundStyle(.secondary)
        }
      }
      if let help, !help.isEmpty { Text(help).readingFont(.caption).foregroundStyle(.secondary) }
      ForEach(Array(fieldIssues.enumerated()), id: \.offset) { _, message in
        Text(message).readingFont(.caption).foregroundStyle(.red).textSelection(.enabled)
      }
    }.accessibilityElement(children: .contain)
  }
  private func entryBinding(_ index: Int, field: Value) -> Binding<Value> {
    let key = field["id"].text
    return .init(
      get: {
        guard value.array.indices.contains(index) else { return .null }
        return value.array[index].object[key] ?? field.object["default"] ?? .null
      },
      set: { next in
        var rows = value.array
        guard rows.indices.contains(index) else { return }
        var row = rows[index].object
        row[key] = next
        rows[index] = .object(row)
        value = .array(rows)
      })
  }
}

/// What a saved tool run did, from a form or a workflow step, with one Undo for its change.
struct ToolRunOutcome: View {
  let receipt: Value
  @ObservedObject var workspace: WorkspaceState
  /// What ran the tool, for the Undo button's help: "this form" or "this step".
  var subject = "this form"
  @State private var undone = false
  @State private var working = false
  @State private var failure: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(
        undone ? "Change undone" : receipt["summary"].string ?? "Done.",
        systemImage: undone ? "arrow.uturn.backward.circle" : "checkmark.circle")
      if let undo = receipt["undo"].string, !undone {
        Button("Undo this change") { take(undo) }
          .disabled(working || workspace.busy)
          .help("Takes back the rows \(subject) changed")
      }
      if let failure {
        Text(failure).readingFont(.callout).foregroundStyle(.red).textSelection(.enabled)
      }
    }
  }
  private func take(_ token: String) {
    guard let book = workspace.workbook else { return }
    working = true
    failure = nil
    Task {
      defer { working = false }
      do {
        _ = try await Task.detached {
          try book.chatSQLUndo(
            token, actor: .human(subject == "this form" ? "Sevra form" : "Sevra workflow run"))
        }.value
        guard workspace.workbook === book else { return }
        undone = true
        workspace.refresh()
      } catch { failure = error.localizedDescription }
    }
  }
}

private struct FormEvidencePicker: View {
  let workbook: Workbook
  let select: ((String, String)) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var items: [(String, String)] = []
  @State private var selectedID: String?
  @State private var loadedQuery: String?
  @State private var failure: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Delivery evidence").readingFont(.title2).accessibilityAddTraits(.isHeader)
      TextField("Search documents and records", text: $query).textFieldStyle(.roundedBorder)
      List(selection: $selectedID) {
        ForEach(Array(items.enumerated()), id: \.element.0) { _, item in
          Text(item.1).frame(maxWidth: .infinity, alignment: .leading).tag(item.0)
        }
      }.accessibilityLabel("Matching evidence")
        .overlay {
          if failure == nil && items.isEmpty {
            if loadedQuery == query {
              Text(
                query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  ? "Add documents or observations to choose evidence."
                  : "No matching documents or records."
              )
              .foregroundStyle(.secondary)
            } else {
              ProgressView("Searching evidence…")
            }
          }
        }
      if let failure { Text(failure).foregroundStyle(.red) }
      HStack {
        Text("Choose the original information supporting this delivery.").readingFont(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Choose") {
          guard loadedQuery == query, let item = items.first(where: { $0.0 == selectedID }) else {
            return
          }
          select(item)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(loadedQuery != query || !items.contains { $0.0 == selectedID })
      }
    }.padding(24).frame(minWidth: 380, idealWidth: 560, minHeight: 300, idealHeight: 480)
      .task(id: query) {
        let text = query
        let control = Cancellation()
        selectedID = nil
        loadedQuery = nil
        items = []
        do {
          let result = try await withTaskCancellationHandler {
            try await Task.detached {
              if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return try workbook.recentItemSummaries(limit: 20).map { ($0.id, $0.title) }
              }
              return try workbook.search(text, limit: 20, cancellation: control).hits.map {
                ($0.itemID, $0.title)
              }
            }.value
          } onCancel: {
            control.cancel()
          }
          try Task.checkCancellation()
          var seen = Set<String>()
          items = result.filter { seen.insert($0.0).inserted }
          loadedQuery = text
          failure = nil
        } catch { if !Task.isCancelled { failure = error.localizedDescription } }
      }
  }
}

extension Notification.Name {
  static let sevraOpenEvidence = Notification.Name("sevraOpenEvidence")
}
