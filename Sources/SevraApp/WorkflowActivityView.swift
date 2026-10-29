import SevraCore
import SevraPreviewUI
import SwiftUI

private func workflowStateTitle(_ state: String) -> String {
  switch state {
  case "queued": return "Ready to continue"
  case "running": return "Step claimed"
  case "waiting_review": return "Waiting for review"
  case "needs_attention": return "Needs attention"
  case "completed": return "Completed"
  case "cancelled": return "Stopped"
  case "pending": return "Not started"
  case "claimed": return "Claimed"
  default: return state.replacingOccurrences(of: "_", with: " ").capitalized
  }
}

struct WorkflowActivityView: View {
  @ObservedObject var workspace: WorkspaceState
  @StateObject private var pages = DefinitionResultSession()
  @State private var filter = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        "Saved workflow runs, newest first. Open a run to inspect its saved state or deliberately continue unfinished work."
      )
      .foregroundStyle(.secondary)
      HStack {
        Picker("Show", selection: $filter) {
          Text("All runs").tag("")
          ForEach(
            ["waiting_review", "needs_attention", "queued", "running", "completed", "cancelled"],
            id: \.self
          ) { Text(workflowStateTitle($0)).tag($0) }
        }.frame(maxWidth: 260)
        Spacer()
        Button("Refresh") { Task { await load(force: true) } }.disabled(pages.loading)
      }
      if let failure = pages.failure { Text(failure).foregroundStyle(.red) }
      if pages.loading { ProgressView("Reading activity") }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(pages.evaluation?["runs"].array ?? [], id: \.text) { run in
            Button {
              workspace.navigate(.workflow(run["id"].text))
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                Text(run["title"].text).font(.headline)
                Text(workflowStateTitle(run["state"].text)).font(.callout)
                Text("Updated " + DisplayText.date(run["updated"].text))
                  .font(.caption).foregroundStyle(.secondary)
                if !run["detail"].text.isEmpty {
                  Text(run["detail"].text).font(.callout).foregroundStyle(.secondary)
                }
              }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            }.buttonStyle(.plain)
              .accessibilityLabel(run["title"].text + ", " + workflowStateTitle(run["state"].text))
            Divider()
          }
          if pages.evaluation?["runs"].array.isEmpty == true && !pages.loading {
            Text(filter.isEmpty ? "No workflow runs yet." : "No runs in this state.")
              .foregroundStyle(.secondary)
          }
        }
      }
      HStack {
        Button("Previous") { Task { await load(direction: -1) } }
          .disabled(!pages.hasPrevious || pages.loading)
        Text("Page \(pages.pageNumber)").font(.callout).foregroundStyle(.secondary)
        Button("Next") { Task { await load(direction: 1) } }
          .disabled(!pages.hasNext || pages.loading)
      }
    }.padding(22)
      .task(id: scope) { await load() }
      .onDisappear { pages.cancel() }
  }
  private var scope: String {
    workspace.interactionIdentity.uuidString + ":" + String(workspace.revision) + ":" + filter
  }
  private func load(direction: Int = 0, force: Bool = false) async {
    guard let book = workspace.workbook else { return }
    let state = filter.isEmpty ? nil : filter
    await pages.load(scope: scope, direction: direction, force: force) { cursor, cancellation in
      try await Task.detached {
        try book.workflowActivity(state: state, cursor: cursor, cancellation: cancellation)
      }.value
    }
  }
}

struct WorkflowRunView: View {
  let runID: String
  @ObservedObject var workspace: WorkspaceState
  @StateObject private var inspection = DefinitionResultSession()
  @State private var confirmingStop = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if let saved = inspection.evaluation {
          let run = saved["run"]
          Text(saved["definition"]["title"].text).font(.title2)
          Text(workflowStateTitle(run["state"].text)).font(.headline)
          Text(
            "Started " + DisplayText.date(run["created"].text) + " · " + saved["actorLabel"].text
          )
          .font(.callout).foregroundStyle(.secondary)
          Text(
            "Manual workflow. Each continuation stops for required review. Completed work is kept."
          )
          .foregroundStyle(.secondary)
          if !run["detail"].text.isEmpty,
            !saved["steps"].array.contains(where: { $0["detail"] == run["detail"] })
          {
            Text(run["detail"].text).foregroundStyle(.red).textSelection(.enabled)
          }
          HStack {
            if !["completed", "cancelled"].contains(run["state"].text) {
              if run["state"] == .string("needs_attention") {
                Button("Retry unfinished work") { resume(retry: true) }
              } else {
                Button(
                  run["state"] == .string("waiting_review")
                    ? "Check review and continue" : "Continue"
                ) {
                  resume()
                }
              }
              Button("Stop workflow", role: .destructive) { confirmingStop = true }
            }
            Button("Definition and evidence") {
              workspace.navigate(.item(saved["definition"]["sourceID"].text))
            }
            Button("Start request") { workspace.navigate(.item(run["source_id"].text)) }
          }.disabled(workspace.busy)
          DisclosureGroup("Inputs") {
            WorkflowInputsView(
              parameters: saved["definition"]["parameters"].array,
              arguments: run["arguments"], workspace: workspace)
          }
          ForEach(saved["steps"].array, id: \.text) { step in
            Divider()
            VStack(alignment: .leading, spacing: 8) {
              Text("\((step["ordinal"].int ?? 0) + 1). " + step["title"].text).font(.headline)
              Text(workflowStateTitle(step["state"].text)).font(.callout)
              Text("Updated " + DisplayText.date(step["updated"].text))
                .font(.caption).foregroundStyle(.secondary)
              let output = step["output"]["value"]
              if !step["detail"].text.isEmpty,
                !["interpretation", "extraction"].contains(output["kind"].text)
              {
                Text(step["detail"].text).foregroundStyle(.red)
              }
              if output["kind"] == .string("function") {
                Text(output["result"].text + (output["unit"].string.map { " " + $0 } ?? ""))
                  .font(.title3).textSelection(.enabled)
              } else if output["kind"] == .string("extraction") {
                Text(
                  output["complete"] == .bool(true)
                    ? "Document prepared" : "Document needs attention"
                )
                .font(.callout)
                Text(output["detail"].text).foregroundStyle(.secondary)
                Text(output["coverage"].text).font(.caption).foregroundStyle(.secondary)
                Button("Open original document") {
                  workspace.navigate(.item(output["itemID"].text))
                }
              } else if output["kind"] == .string("interpretation") {
                Text("Local AI interpretation · Review before business use").font(.callout)
                WorkflowInputsView(
                  parameters: step["outputFields"].array, arguments: output["response"]["values"],
                  workspace: workspace)
                ForEach(output["response"]["issues"].array, id: \.text) { issue in
                  Text(issue.text).foregroundStyle(.secondary)
                }
                Button("Open saved interpretation") {
                  workspace.navigate(.item(output["recordID"].text))
                }
                DisclosureGroup("Model and exact evidence quotations") {
                  Text(output["model"].text).font(.caption).textSelection(.enabled)
                  ForEach(output["response"]["citations"].array, id: \.text) { citation in
                    Text(citation["field"].text + ": “" + citation["quote"].text + "”")
                      .textSelection(.enabled)
                    Button("Open quoted evidence") {
                      workspace.navigate(.item(citation["itemID"].text))
                    }
                  }
                }
              } else if output["kind"] == .string("query") {
                Text(
                  "Saved \(output["result"]["rows"].array.count) result rows and their scoped inputs."
                )
              }
              ForEach(step["proposals"].array, id: \.text) { proposal in
                VStack(alignment: .leading, spacing: 4) {
                  Button(proposal["title"].text) { workspace.navigate(.item(proposal["id"].text)) }
                  Text(proposal["meaning"].text.capitalized + " · " + proposal["scenario"].text)
                    .font(.caption).foregroundStyle(.secondary)
                  if proposal["changed"] == .bool(true) {
                    Button("Open current \(proposal["status"].text) version") {
                      workspace.navigate(.item(proposal["currentID"].text))
                    }.font(.callout)
                  } else {
                    Text("Awaiting review").font(.caption).foregroundStyle(.secondary)
                  }
                }
              }
              if step["kind"] == .string("review") && step["state"] == .string("waiting_review") {
                Text(
                  "Open the proposals above to inspect and accept them. Then choose Check review and continue."
                )
                .foregroundStyle(.secondary)
              }
              if let source = step["definitionSource"].string {
                Button("Step definition") { workspace.navigate(.item(source)) }.font(.callout)
              }
              if let generation = step["attempt"]["generation"].int {
                Text("Attempt \(generation)").font(.caption).foregroundStyle(.secondary)
                if step["output"] == .null, step["attempt"]["modelResponse"] != .null {
                  DisclosureGroup("Unvalidated model response") {
                    Text(
                      "This response did not complete the step. Treat it as a diagnostic, not an established fact."
                    )
                    .foregroundStyle(.secondary)
                    Text(step["attempt"]["model"].text).font(.caption)
                    Text(
                      String(((try? step["attempt"]["modelResponse"].json()) ?? "").prefix(16_384))
                    )
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text(
                      "Preview limited to 16,384 characters. The saved operation retains the response."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                  }
                }
                if step["state"] == .string("claimed"),
                  let deadline = Double(step["attempt"]["deadline"].text)
                {
                  Text(
                    "Worker lease ends "
                      + Date(timeIntervalSince1970: deadline).formatted(
                        date: .omitted, time: .standard) + ". An expired step can be resumed."
                  )
                  .font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
        if inspection.loading { ProgressView("Reading workflow") }
        if let failure = inspection.failure { Text(failure).foregroundStyle(.red) }
        Button("Refresh") { Task { await load(force: true) } }.disabled(inspection.loading)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
    }
    .task(id: workspace.interactionIdentity.uuidString + runID + String(workspace.revision)) {
      await load()
    }
    .onDisappear { inspection.cancel() }
    .confirmationDialog(
      "Stop this workflow?", isPresented: $confirmingStop, titleVisibility: .visible
    ) {
      Button("Stop workflow", role: .destructive) {
        let id = runID
        workspace.run("Stopping workflow") { book, cancellation in
          try cancellation.check()
          _ = try book.cancelWorkflow(book.authorizeWorkflowExecution(id), token: identifier())
        }
      }
    } message: {
      Text(
        "Completed steps, proposals and accepted changes stay in the workbook. Unfinished steps will stop."
      )
    }
  }
  private func load(force: Bool = false) async {
    guard let book = workspace.workbook else { return }
    let id = runID
    await inspection.load(
      scope: workspace.interactionIdentity.uuidString + id + String(workspace.revision),
      force: force
    ) { _, cancellation in
      try await Task.detached { try book.inspectWorkflow(id, cancellation: cancellation) }.value
    }
  }
  private func resume(retry: Bool = false) {
    let id = runID
    workspace.continueWorkflow(id, retry: retry)
  }
}

private struct WorkflowInputsView: View {
  let parameters: [Value]
  let arguments: Value
  @ObservedObject var workspace: WorkspaceState
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(parameters, id: \.text) { parameter in
        let value = arguments[parameter["id"].text]
        if value != .null {
          if parameter["type"] == .string("item") {
            Button("Open " + parameter["label"].text) { workspace.navigate(.item(value.text)) }
          } else if parameter["type"] == .string("entries") {
            Text(parameter["label"].text).font(.callout.weight(.medium))
            ForEach(value.array.indices, id: \.self) { index in
              AnyView(
                WorkflowInputsView(
                  parameters: parameter["fields"].array, arguments: value.array[index],
                  workspace: workspace)
              )
              .padding(.leading, 14)
              Divider()
            }
          } else {
            Text(
              parameter["label"].text + ": " + value.text
                + (parameter["unit"].string.map { " " + $0 } ?? "")
            )
            .textSelection(.enabled)
          }
        }
      }
    }.padding(.top, 8)
  }
}
