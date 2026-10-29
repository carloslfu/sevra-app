import SevraCore
import SevraPreviewUI
import SwiftUI

struct WorkflowClarificationView: View {
  @ObservedObject var session: WorkflowClarificationSession
  @ObservedObject var workspace: WorkspaceState
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let state = session.state {
        let target = state.entry.target
        Text("Supply missing information").font(.headline)
        Text("Your answer is saved separately from the original AI interpretation.")
          .foregroundStyle(.secondary)
        Text(target["title"].text).font(.callout.weight(.medium))
        Text("Meaning: " + target["meaning"].text + " · Scenario: " + target["scenario"].text)
          .font(.caption).foregroundStyle(.secondary)
        ForEach(target["issues"].array, id: \.text) { issue in Text(issue.text) }
        if state.entry.receipt != nil {
          Label("Your information was saved", systemImage: "checkmark.circle")
          Text("Continue the workflow deliberately. Business changes still need review.")
            .foregroundStyle(.secondary)
        } else {
          if session.failure == nil {
            Text(session.dirty ? "Saving inputs…" : "Inputs saved on this device.")
              .font(.caption).foregroundStyle(.secondary)
          }
          if target != session.currentTarget {
            Text("This answer belongs to an earlier request. Your inputs are kept.")
              .foregroundStyle(.secondary)
          }
          ForEach(target["fields"].array, id: \.text) { field in
            FormParameterField(
              parameter: field, value: binding(field), workbook: workspace.workbook,
              evidenceIDs: target["evidenceIDs"].array.map(\.text))
          }.disabled(session.busy)
          TextField(
            "Explain where this information came from",
            text: Binding(
              get: { session.state?.entry.reason ?? "" },
              set: {
                session.update(values: session.state?.entry.values ?? .object([:]), reason: $0)
              }),
            axis: .vertical
          ).lineLimit(2...8).textFieldStyle(.roundedBorder)
            .accessibilityLabel("Explanation for supplied information")
            .disabled(session.busy)
          if let preview = session.preview {
            Text(preview["notice"].text).font(.callout)
            WorkflowInputsView(
              parameters: target["fields"].array, arguments: preview["values"], workspace: workspace
            )
            Button("Save my answer") {
              let book = workspace.workbook
              let owner = workspace.interactionIdentity
              Task {
                await session.submit()
                guard workspace.workbook === book, workspace.interactionIdentity == owner else {
                  return
                }
                workspace.refresh()
              }
            }.disabled(session.busy || workspace.busy || session.conflict)
          } else {
            Button("Preview answer") { Task { await session.prepare() } }
              .disabled(
                session.busy || workspace.busy || session.conflict
                  || target != session.currentTarget)
          }
          if session.currentTarget != nil, target != session.currentTarget {
            Button("Use current request and keep these inputs") {
              Task { await session.useCurrent() }
            }.font(.callout).disabled(session.busy || workspace.busy || session.conflict)
          }
        }
        if !state.alternatives.isEmpty {
          DisclosureGroup("Saved alternatives (\(state.alternatives.count))") {
            ForEach(Array(state.alternatives.enumerated()), id: \.element.id) {
              index, alternative in
              HStack {
                Text(
                  "Saved answer \(index + 1)" + (alternative.receipt == nil ? "" : " · Submitted"))
                Button("Open") { Task { await session.restoreAlternative(alternative.id) } }
                Button("Remove") { Task { await session.discardAlternative(alternative.id) } }
              }.disabled(session.busy || session.conflict)
            }
          }
        }
      } else if session.busy {
        ProgressView("Opening saved inputs")
      }
      if let failure = session.failure {
        Text(failure).foregroundStyle(.red).textSelection(.enabled)
        if session.conflict {
          Button("Keep both drafts") { Task { await session.keepBoth() } }.disabled(session.busy)
        } else if session.dirty {
          Button("Retry saving inputs") { Task { _ = await session.flush() } }.disabled(
            session.busy)
        }
      }
    }
  }
  private func binding(_ field: Value) -> Binding<Value> {
    .init(
      get: { session.state?.entry.values[field["id"].text] ?? .null },
      set: { value in
        var values = session.state?.entry.values.object ?? [:]
        values[field["id"].text] = value
        session.update(values: .object(values), reason: session.state?.entry.reason ?? "")
      })
  }
}

struct ClarificationEvidenceField: View {
  let title: String
  let evidenceIDs: [String]
  @Binding var value: Value
  let workbook: Workbook?
  @State private var titles: [String: String] = [:]
  var body: some View {
    Picker(
      title,
      selection: Binding(
        get: { value.string ?? "" },
        set: { value = $0.isEmpty ? .null : .string($0) }
      )
    ) {
      Text("Choose original evidence…").tag("")
      ForEach(evidenceIDs, id: \.self) { id in Text(titles[id] ?? id).tag(id) }
    }.labelsHidden().accessibilityLabel(title)
      .task(id: evidenceIDs) {
        guard let workbook else { return }
        let ids = evidenceIDs
        let names = await Task.detached {
          Dictionary(uniqueKeysWithValues: ids.map { ($0, (try? workbook.item($0).title) ?? $0) })
        }.value
        guard !Task.isCancelled else { return }
        titles = names
      }
  }
}
