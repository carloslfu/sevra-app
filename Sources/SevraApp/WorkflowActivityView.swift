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
        "Saved workflows, newest first. Open a run to inspect or continue it. Conversation activity stays with each message."
      )
      .foregroundStyle(.secondary)
      HStack {
        Button("Automations", systemImage: "clock.arrow.circlepath") {
          workspace.navigate(.automations)
        }
        Picker("Workflow state", selection: $filter) {
          Text("All runs").tag("")
          ForEach(
            ["waiting_review", "needs_attention", "queued", "running", "completed", "cancelled"],
            id: \.self
          ) { Text(workflowStateTitle($0)).tag($0) }
        }.labelsHidden().fixedSize()
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
                Text(
                  (run["policy"] == .string("automation-drafts-v1") ? "Automatic · " : "Manual · ")
                    + workflowStateTitle(run["state"].text)
                ).font(.callout)
                Text("Updated " + DisplayText.date(run["updated"].text))
                  .font(.caption).foregroundStyle(.secondary)
                if !run["detail"].text.isEmpty {
                  Text(run["detail"].text).font(.callout).foregroundStyle(.secondary)
                }
              }.multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                .contentShape(Rectangle())
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
      if pages.hasPrevious || pages.hasNext {
        HStack {
          Button("Previous") { Task { await load(direction: -1) } }
            .disabled(!pages.hasPrevious || pages.loading)
          Text("Page \(pages.pageNumber)").font(.callout).foregroundStyle(.secondary)
          Button("Next") { Task { await load(direction: 1) } }
            .disabled(!pages.hasNext || pages.loading)
        }
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
  @State private var clarification: WorkflowClarificationSession?
  @State private var clarificationFailure: String?
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
            run["policy"] == .string("automation-drafts-v1")
              ? "Automatic draft workflow. Continue is a separate manual request for this run; it does not enable future automations. Business changes require review."
              : "Manual workflow. Each continuation stops for required review. Completed work is kept."
          )
          .foregroundStyle(.secondary)
          if saved["invocation"]["origin"]["candidateID"].string != nil {
            let origin = saved["invocation"]["origin"]
            Text(
              "Stock at the trigger: " + origin["trigger"]["quantity"].text + " · "
                + DisplayText.date(origin["trigger"]["effectiveThrough"].text))
            Text("Each later step shows its own saved inputs.").font(.caption).foregroundStyle(
              .secondary)
            Button("Trigger and evidence") {
              workspace.navigate(.item(origin["dispatchSourceID"].text))
            }
          }
          if !run["detail"].text.isEmpty,
            !saved["steps"].array.contains(where: { $0["detail"] == run["detail"] })
          {
            Text(run["detail"].text).foregroundStyle(.red).textSelection(.enabled)
          }
          ViewThatFits(in: .horizontal) {
            HStack { runActions(saved) }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) { runActions(saved) }
          }.disabled(workspace.busy)
          DisclosureGroup("Inputs") {
            WorkflowInputsView(
              parameters: saved["definition"]["parameters"].array,
              arguments: run["arguments"], workspace: workspace)
          }
          if let clarification {
            WorkflowClarificationView(session: clarification, workspace: workspace)
          }
          if let clarificationFailure {
            Text(clarificationFailure).foregroundStyle(.red).textSelection(.enabled)
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
              } else if output["kind"] == .string("intake") {
                let summary = output["summary"]
                Text("Table update prepared for review").font(.callout)
                Text(
                  "\(summary["added"].int ?? 0) added · \(summary["changed"].int ?? 0) changed · \(summary["removed"].int ?? 0) removed"
                )
                Text(
                  "New rows: " + summary["newRowMeaning"].text + ", scenario "
                    + summary["newRowScenario"].text
                ).font(.caption).foregroundStyle(.secondary)
                Text(output["notice"].text).font(.caption).foregroundStyle(.secondary)
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
                if output["clarification"] != .null {
                  let supplied = output["clarification"]
                  Text(
                    supplied["actor"]["kind"] == .string("human")
                      ? "Information supplied by you"
                      : "Information supplied by the calling program"
                  ).font(.headline)
                  Text(
                    "The original model response is preserved above. Business review is separate."
                  )
                  .font(.caption).foregroundStyle(.secondary)
                  WorkflowInputsView(
                    parameters: step["outputFields"].array, arguments: supplied["values"],
                    workspace: workspace)
                  Text(supplied["reason"].text).textSelection(.enabled)
                  Button("Open clarification source") {
                    workspace.navigate(.item(supplied["sourceID"].text))
                  }
                  Button("Open clarification record") {
                    workspace.navigate(.item(supplied["recordID"].text))
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
                    StructuredValueView(value: step["attempt"]["modelResponse"])
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
          _ = try book.cancelWorkflow(
            id, token: identifier(), actor: .human("Sevra.native-workflow-stop"))
        }
      }
    } message: {
      Text(
        "Completed steps, proposals and accepted changes stay in the workbook. Unfinished steps will stop."
      )
    }
  }
  @ViewBuilder private func runActions(_ saved: Value) -> some View {
    let run = saved["run"]
    if !["completed", "cancelled"].contains(run["state"].text) {
      if run["state"] == .string("needs_attention") {
        Button("Retry unfinished work") { resume(retry: true) }
      } else {
        Button(run["state"] == .string("waiting_review") ? "Check review and continue" : "Continue")
        {
          resume()
        }
      }
      Button("Stop workflow", role: .destructive) { confirmingStop = true }
    }
    Button("Definition and evidence") {
      workspace.navigate(.item(saved["definition"]["sourceID"].text))
    }
    Button("Start request") { workspace.navigate(.item(run["source_id"].text)) }
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
    guard !Task.isCancelled, workspace.workbook === book else { return }
    do {
      let available = try await Task.detached {
        let saved = try book.workflowClarificationDraft(id)
        return saved != nil || (try? book.workflowClarification(id)) != nil
      }.value
      guard !Task.isCancelled, workspace.workbook === book else { return }
      clarificationFailure = nil
      if available, let session = workspace.clarificationDrafts.session(id) {
        clarification = session
        await session.open()
        await session.refreshTarget()
      }
    } catch {
      guard !Task.isCancelled, workspace.workbook === book else { return }
      clarificationFailure =
        "Saved answer inputs could not be opened. " + error.localizedDescription
    }
  }
  private func resume(retry: Bool = false) {
    let id = runID
    workspace.continueWorkflow(id, retry: retry)
  }
}

struct WorkflowInputsView: View {
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
