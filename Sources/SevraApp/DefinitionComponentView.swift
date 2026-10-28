import SevraCore
import SevraPreviewUI
import SwiftUI

struct SavedDefinitionResultView: View {
  let item: Item
  let workbook: Workbook
  @ObservedObject var workspace: WorkspaceState
  @State private var component: Component?
  @State private var failure: String?
  var body: some View {
    VStack(alignment: .leading) {
      if let component {
        DefinitionComponentView(component: component, workspace: workspace)
      } else if let failure {
        Text("Saved computation unavailable: " + failure).foregroundStyle(.secondary)
      } else {
        ProgressView("Opening saved result")
      }
    }
    .task(id: item.id + workspace.interactionIdentity.uuidString) {
      component = nil
      failure = nil
      let cancellation = Cancellation()
      do {
        let saved = try await withTaskCancellationHandler {
          try await Task.detached {
            try workbook.publishedApplicationResultComponent(item.id, cancellation: cancellation)
          }.value
        } onCancel: {
          cancellation.cancel()
        }
        guard !Task.isCancelled, workspace.workbook === workbook else { return }
        component = saved
        if saved == nil {
          failure =
            "This record has no verified saved computation. Its text and evidence remain below."
        }
      } catch {
        guard !Task.isCancelled, workspace.workbook === workbook else { return }
        failure = error.localizedDescription
      }
    }
  }
}

struct DefinitionComponentView: View {
  private struct PublicationSelection: Identifiable {
    let id = UUID()
    let evaluation: Value
  }
  let component: Component
  @ObservedObject var workspace: WorkspaceState
  @StateObject private var results = DefinitionResultSession()
  @State private var publication: PublicationSelection?
  private var scope: String {
    workspace.interactionIdentity.uuidString + ":" + String(workspace.revision) + ":"
      + component.id + ":" + (component.definitionBinding?.text ?? "") + ":"
      + (component.arguments?.text ?? "") + ":" + (component.evaluationSnapshot?.captured ?? "live")
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let saved = component.evaluationSnapshot {
        Text("Saved as of " + DisplayText.date(saved.captured))
          .font(.caption).foregroundStyle(.secondary)
        if let population = saved.inputPopulation {
          Text(
            "Retains \(population.reduce(0) { $0 + $1["rows"].array.count }) input versions. "
              + "Includes scoped candidates removed by filters or joins; group membership is not recorded."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
      if let evaluation = results.evaluation {
        if !evaluation["arguments"].object.isEmpty {
          Text(
            evaluation["arguments"].object.keys.sorted().map {
              $0 + ": " + evaluation["arguments"][$0].text
            }.joined(separator: " · ")
          )
          .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
        if component.type == "calculation" {
          Text(evaluation["result"].text + (evaluation["unit"].string.map { " " + $0 } ?? ""))
            .font(.system(size: 32, weight: .medium, design: .rounded)).textSelection(.enabled)
        } else {
          query(evaluation["result"])
        }
        HStack {
          if let source = evaluation["resolvedDefinitions"].array.first(where: {
            $0["id"] == evaluation["definitionID"]
          })?["sourceID"].string {
            Button("How calculated") { workspace.navigate(.item(source)) }
          }
          if component.evaluationSnapshot == nil {
            Button("Refresh") { Task { await load(force: true) } }.disabled(results.loading)
            if results.pageNumber == 1 && !results.hasNext {
              Button("Save result…") {
                publication = .init(evaluation: evaluation)
              }
              .disabled(results.loading || results.failure != nil || workspace.busy)
            }
          }
        }
      } else if !results.loading && results.failure == nil {
        Text("No result loaded.").foregroundStyle(.secondary)
      }
      if results.loading { ProgressView("Calculating") }
      if let failure = results.failure {
        Text(failure).foregroundStyle(.red).textSelection(.enabled)
        if results.evaluation != nil {
          Text("The values above are the last loaded result. Refresh before using them.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Button("Try again") { Task { await load(force: true) } }.disabled(results.loading)
      }
    }
    .task(id: scope) { await load() }
    .onDisappear { results.cancel() }
    .sheet(item: $publication) { selection in
      DefinitionPublicationSheet(
        component: component, evaluation: selection.evaluation, workspace: workspace)
    }
  }
  @ViewBuilder private func query(_ result: Value) -> some View {
    let rows = result["rows"].array
    let columns = result["columns"].array
    ScrollView([.horizontal, .vertical]) {
      Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
        GridRow {
          ForEach(columns.indices, id: \.self) { index in
            Text(
              columns[index]["title"].text
                + (columns[index]["unit"].string.map { " (" + $0 + ")" } ?? "")
            ).fontWeight(.semibold)
          }
          Text("Inputs").fontWeight(.semibold)
        }
        ForEach(rows.indices, id: \.self) { index in
          GridRow {
            ForEach(columns.indices, id: \.self) { field in
              let value = rows[index]["values"][columns[field]["id"].text]
              Text(value == .null ? "Unknown" : value.text.isEmpty ? "Empty" : value.text)
                .textSelection(.enabled)
            }
            VStack(alignment: .leading) {
              ForEach(rows[index]["inputs"].array.indices, id: \.self) { inputIndex in
                let input = rows[index]["inputs"].array[inputIndex]
                if let id = input["versionID"].string {
                  Button(
                    input["meaning"].text + " · " + input["status"].text + " · "
                      + input["scenario"].text
                  ) {
                    workspace.navigate(.item(id))
                  }.accessibilityLabel(
                    "Open original row, " + input["meaning"].text + ", " + input["status"].text)
                }
              }
              if rows[index]["inputs"].array.isEmpty {
                Text("Aggregate over declared table scopes").font(.caption).foregroundStyle(
                  .secondary)
              }
            }
          }
        }
      }.padding(8)
    }.frame(maxHeight: 300)
    if rows.isEmpty { Text("No rows match this query.").foregroundStyle(.secondary) }
    Text(
      "Page \(results.pageNumber) · \(rows.count) rows"
        + (results.hasNext ? " · More rows available" : " · End of results")
    )
    .font(.caption).foregroundStyle(.secondary)
    if component.evaluationSnapshot != nil && result["hasMore"] == .bool(true) {
      Text("Saved first page only. Additional rows were not captured.")
        .font(.callout).foregroundStyle(.secondary)
    }
    if component.evaluationSnapshot == nil {
      HStack {
        if results.hasPrevious { Button("Previous page") { Task { await load(direction: -1) } } }
        if results.hasNext { Button("Next page") { Task { await load(direction: 1) } } }
      }.disabled(results.loading)
      if results.hasNext {
        Text(
          "This page is partial. Pinning the space saves its first page with this coverage note."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
    ForEach(result["sourceScopes"].array.indices, id: \.self) { index in
      let scope = result["sourceScopes"].array[index]["scope"].object
      Text(
        scope.isEmpty
          ? (component.evaluationSnapshot == nil
            ? "Includes all current row meanings, statuses and scenarios."
            : "Included all row meanings, statuses and scenarios at capture.")
          : (component.evaluationSnapshot == nil ? "Current scope: " : "Scope at capture: ")
            + scope.keys.sorted().map { $0 + ": " + scope[$0]!.text }.joined(separator: " · ")
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
  private func load(direction: Int = 0, force: Bool = false) async {
    guard let book = workspace.workbook else { return }
    await results.load(scope: scope, direction: direction, force: force) { cursor, cancellation in
      try await Task.detached {
        try book.componentDefinitionResult(component, cursor: cursor, cancellation: cancellation)
      }.value
    }
  }
}

private struct DefinitionPublicationSheet: View {
  private enum PublicationOutcome: Sendable {
    case saved(Item)
    case failed(String)
  }
  let component: Component
  let evaluation: Value
  @ObservedObject var workspace: WorkspaceState
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var meaning = "estimate"
  @State private var scenario = "actual"
  @State private var token = identifier()
  @State private var failure: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Save this result").font(.title2)
      Text(
        "Keep these values and their exact inputs as a draft. Later changes will leave this saved result intact."
      )
      .foregroundStyle(.secondary)
      TextField("Result title", text: $title)
      Picker("Meaning", selection: $meaning) {
        ForEach(["actual", "estimate", "plan", "commitment", "assumption", "rule"], id: \.self) {
          Text($0.capitalized).tag($0)
        }
      }
      TextField("Scenario", text: $scenario)
      Text("Accepting a result later keeps its meaning. An accepted estimate remains an estimate.")
        .font(.caption).foregroundStyle(.secondary)
      if let failure {
        Text(failure).foregroundStyle(.red).textSelection(.enabled)
        Text(
          "Your entries are kept here. If inputs changed, close this sheet and refresh the result."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Save draft") { save() }.keyboardShortcut(.defaultAction)
          .disabled(
            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scenario.isEmpty)
      }
    }.padding(24).frame(width: 480)
      .disabled(workspace.busy).interactiveDismissDisabled(workspace.busy)
      .onAppear { title = component.title }
  }
  private func save() {
    let title = title
    let meaning = meaning
    let scenario = scenario
    let token = token
    failure = nil
    workspace.run("Saving result") { book, cancellation in
      do {
        return PublicationOutcome.saved(
          try book.publishApplicationResult(
            evaluation["definitionID"].text, arguments: evaluation["submittedArguments"],
            evaluation: evaluation,
            title: title, meaning: meaning, scenario: scenario, token: token,
            actor: .human("SevraApp.result"), cancellation: cancellation))
      } catch { return PublicationOutcome.failed(error.localizedDescription) }
    } completion: { outcome in
      switch outcome {
      case .saved(let item):
        dismiss()
        workspace.navigate(.item(item.id))
      case .failed(let message): failure = message
      }
    }
  }
}
