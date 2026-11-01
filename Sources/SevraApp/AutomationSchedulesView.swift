import SevraAutomationUI
import SevraCore
import SevraPreviewUI
import SwiftUI

struct AutomationSchedulesView: View {
  @ObservedObject var workspace: WorkspaceState
  @ObservedObject private var owner = NativeAutomationHost.shared.controller
  @StateObject private var pages = DefinitionResultSession()
  @State private var query = ""
  @State private var selected: ApplicationDefinition?
  @State private var creating = false
  @State private var failure: String?
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        TextField("Find an automation", text: $query)
        Button("New automation…") { creating = true }.disabled(workspace.busy)
        Button("Import template…", action: importTemplate).disabled(workspace.busy)
        Button("Runs") { workspace.navigate(.activity) }
      }
      Text(owner.gate).font(.callout).foregroundStyle(.secondary)
      Text(
        "Saved automations travel with this workbook. Enable each exact version on this Mac to run it here."
      )
      .font(.caption).foregroundStyle(.secondary)
      if let failure = failure ?? pages.failure ?? owner.failure ?? owner.notice {
        Text(failure).foregroundStyle(.red).textSelection(.enabled)
      }
      if pages.loading { ProgressView("Reading automations") }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          ForEach(pages.evaluation?["hits"].array ?? [], id: \.text) { row in
            Button {
              open(row["id"].text)
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                Text(row["title"].text).font(.headline)
                Text("Version \(row["version"].int ?? 0) · " + row["description"].text)
                  .foregroundStyle(.secondary)
              }.multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            Divider()
          }
          if pages.evaluation?["hits"].array.isEmpty == true && !pages.loading
            && pages.failure == nil
          {
            Text(
              query.isEmpty
                ? "No automations yet. Save a workflow, then choose New automation."
                : "No automations match “\(query)”."
            )
            .foregroundStyle(.secondary)
          }
        }
      }
      HStack {
        if pages.hasPrevious || pages.hasNext {
          Button("Previous") { Task { await load(direction: -1) } }
            .disabled(!pages.hasPrevious || pages.loading)
          Text("Page \(pages.pageNumber)").font(.caption)
          Button("Next") { Task { await load(direction: 1) } }
            .disabled(!pages.hasNext || pages.loading)
        }
        Spacer()
        Button("Refresh") {
          Task {
            await load(force: true)
            await owner.reload()
          }
        }.disabled(pages.loading)
      }
      if !owner.grants.isEmpty {
        DisclosureGroup("Registered on this Mac (\(owner.grants.count))") {
          ScrollView {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(owner.grants) { grant in
                HStack {
                  VStack(alignment: .leading) {
                    Text(grant.workbookTitle + " · " + grant.title)
                    Text(owner.statuses[grant.id] ?? "Registered on this Mac.")
                      .font(.caption).foregroundStyle(.secondary)
                  }
                  Spacer()
                  Button("Open workbook") {
                    let registry = owner.registry
                    Task {
                      do {
                        let url = try await Task.detached { try registry.resolvedURL(grant) }.value
                        openWindow(value: url.path)
                      } catch { failure = error.localizedDescription }
                    }
                  }
                  Button("Pause") {
                    Task {
                      do {
                        try await owner.pause(grant)
                        workspace.refresh()
                      } catch {
                        failure =
                          "Device permission removed if available. " + error.localizedDescription
                      }
                    }
                  }
                }
              }
            }
          }.frame(maxHeight: 160)
        }
      }
    }.padding(22)
      .task(id: workspace.interactionIdentity.uuidString + String(workspace.revision) + query) {
        await load()
        await owner.reload()
      }
      .onDisappear { pages.cancel() }
      .sheet(item: $selected) { definition in
        AutomationScheduleDetail(definition: definition, workspace: workspace)
      }
      .sheet(isPresented: $creating) { AutomationScheduleEditor(workspace: workspace) }
  }
  private func importTemplate() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let file = panel.url, let book = workspace.workbook else {
      return
    }
    Task {
      do {
        let saved = try await Task.detached {
          try book.importTemplate(file, actor: .human("Sevra.native-template-import"))
        }.value
        workspace.refresh()
        if saved.kind == "automation" { selected = saved }
      } catch { failure = error.localizedDescription }
    }
  }
  private func open(_ id: String) {
    guard let book = workspace.workbook else { return }
    Task {
      do {
        let definition = try await Task.detached { try book.applicationDefinition(id) }.value
        guard workspace.workbook === book else { return }
        selected = definition
      } catch { failure = error.localizedDescription }
    }
  }
  private func load(direction: Int = 0, force: Bool = false) async {
    guard let book = workspace.workbook else { return }
    let query = query
    await pages.load(
      scope: workspace.interactionIdentity.uuidString + String(workspace.revision) + query,
      direction: direction, force: force
    ) { cursor, control in
      try await Task.detached {
        try book.searchApplicationDefinitions(
          query, kind: "automation", cursor: cursor,
          cancellation: control)
      }.value
    }
  }
}

struct AutomationScheduleDetail: View {
  let definition: ApplicationDefinition
  @ObservedObject var workspace: WorkspaceState
  var onClose: (() -> Void)? = nil
  @ObservedObject private var owner = NativeAutomationHost.shared.controller
  @Environment(\.dismiss) private var dismiss
  @State private var preview: Value?
  @State private var state: Value = .null
  @State private var conditionState: Value = .null
  @State private var conditionQueue: Value = .null
  @State private var confirmingFromNow = false
  @State private var dismissing: String?
  @State private var dismissalReason = ""
  @State private var inspectionOwner = UUID()
  @State private var workflow: ApplicationDefinition?
  @State private var grant: AutomationDeviceGrant?
  @State private var allowAI = false
  @State private var working = false
  @State private var editing = false
  @State private var failure: String?
  @State private var updatedDefinition: ApplicationDefinition?
  @State private var enabledVersion: Int?
  private var shown: ApplicationDefinition { updatedDefinition ?? definition }
  private var isCondition: Bool {
    shown.payload["policy"] == .string("inventory-condition-drafts-v1")
  }
  private var waitingCount: Int { conditionState["pendingCandidates"].int ?? 0 }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(shown.title).font(.title2)
      Text("Saved version \(shown.version)").font(.caption).foregroundStyle(.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text(shown.description)
          if let workflow {
            Text("Workflow: " + workflow.title).font(.headline)
            WorkflowInputsView(
              parameters: workflow.parameters.array,
              arguments: shown.payload["arguments"], workspace: workspace)
          }
          if isCondition {
            let condition = shown.payload["condition"]
            Text(
              "When \(condition["subject"].text) stock becomes \(condition["rule"]["operator"].text) \(condition["rule"]["threshold"].text)"
            ).font(.headline)
            Text(
              "Initial enable establishes current stock. Already-true stock waits for a new crossing. Resume keeps every saved transition and checks missed changes."
            )
            .font(.caption).foregroundStyle(.secondary)
            if conditionState["lastCompleteObservation"]["quantity"].string != nil {
              Text(
                "Last observed stock: " + conditionState["lastCompleteObservation"]["quantity"].text
                  + " · "
                  + DisplayText.date(
                    conditionState["lastCompleteObservation"]["effectiveThrough"].text))
            }
            if waitingCount > 0 {
              Text("\(waitingCount) saved transitions waiting").font(.headline)
              DisclosureGroup("Review waiting transitions") {
                ForEach(conditionQueue["candidates"].array, id: \.text) { candidate in
                  HStack {
                    Text(
                      candidate["observation"]["quantity"].text + " · "
                        + DisplayText.date(candidate["observation"]["effectiveThrough"].text))
                    Spacer()
                    Button("Dismiss…") {
                      dismissing = candidate["candidateID"].text
                      dismissalReason = ""
                    }
                  }
                }
                if conditionQueue["hasMore"] == .bool(true) {
                  Text(
                    "More transitions remain saved. Dismissed entries leave room to inspect the next ones."
                  ).font(.caption)
                }
              }
            }
          } else {
            ScheduleOccurrencePreview(calendar: preview?["calendar"])
          }
          if let grant {
            Text(
              grantIsCurrent
                ? AutomationGrantNotice.text(
                  enabled: grant.definitionID == shown.id ? shown.version : enabledVersion,
                  shown: shown.version)
                : "This device registration is stale. The workbook no longer authorizes it.")
            Text(owner.statuses[grant.id] ?? owner.gate).foregroundStyle(.secondary)
            Button(grantIsCurrent ? "Pause on this Mac" : "Remove stale registration") {
              perform { try await owner.pause(grant) }
            }
          } else {
            Text("This automation is not enabled for this physical workbook on this Mac.")
          }
          Toggle("Allow this exact workflow to use local AI", isOn: $allowAI)
          Text(
            "Automatic work creates drafts and stops for review. Runs while Sevra is active; quit or inactive periods catch up when eligible. No background helper is installed."
          )
          .font(.caption).foregroundStyle(.secondary)
          ViewThatFits(in: .horizontal) {
            HStack { automationActions }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) { automationActions }
          }
          if let runID = state["active_run_id"].string {
            Button("Open saved run") {
              close()
              workspace.navigate(.workflow(runID))
            }
          }
        }
      }
      if working { ProgressView("Updating automation") }
      if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        Spacer()
        Button("Done") { close() }.keyboardShortcut(.cancelAction)
      }
    }.padding(24).frame(minWidth: 540, idealWidth: 620, minHeight: 440, idealHeight: 660)
      .disabled(working || workspace.busy).interactiveDismissDisabled(working)
      .task(id: shown.id) { await load() }
      .confirmationDialog("Start only from now?", isPresented: $confirmingFromNow) {
        Button("Skip earlier transitions and start from now") {
          guard let book = workspace.workbook else { return }
          perform {
            try await owner.enable(
              book, exactID: shown.id,
              expectedGeneration: state["generation"].int ?? 0, allowAI: allowAI, fromNow: true)
          }
        }
      } message: {
        Text(
          "This records an explicit skip for the \(waitingCount) saved transitions and starts a fresh stock baseline. Earlier missed changes will not start new work. Completed work and history remain saved."
        )
      }
      .sheet(isPresented: Binding(get: { dismissing != nil }, set: { if !$0 { dismissing = nil } }))
    {
      VStack(alignment: .leading, spacing: 16) {
        Text("Dismiss this transition").font(.title2)
        TextField("Reason", text: $dismissalReason, axis: .vertical)
        Text(
          "The transition and your reason remain in history. No workflow or business change is created."
        ).font(.caption)
        HStack {
          Button("Cancel") { dismissing = nil }
          Spacer()
          Button("Dismiss transition") {
            guard let candidate = dismissing, let book = workspace.workbook else { return }
            let reason = dismissalReason
            dismissing = nil
            perform {
              _ = try await Task.detached {
                try book.dismissInventoryConditionCandidate(
                  candidate, reason: reason, token: identifier(),
                  actor: .human("Sevra.native-condition-dismiss"))
              }.value
            }
          }.disabled(
            dismissalReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || dismissalReason.utf8.count > 1024)
        }
      }.padding(24).frame(minWidth: 420)
    }
      .sheet(isPresented: $editing, onDismiss: workspace.refresh) {
        AutomationScheduleEditor(
          workspace: workspace, existing: shown, onSave: { updatedDefinition = $0 })
      }
  }
  @ViewBuilder private var automationActions: some View {
    Button(
      isCondition && waitingCount > 0
        ? "Resume waiting transitions on this Mac" : "Enable on this Mac"
    ) {
      guard let book = workspace.workbook else { return }
      perform {
        try await owner.enable(
          book, exactID: shown.id,
          expectedGeneration: state["generation"].int ?? 0, allowAI: allowAI)
      }
    }.disabled(
      preview == nil
        || (grantIsCurrent && grant?.definitionID == shown.id && grant?.allowAI == allowAI))
    Button("Run once") { runOnce() }.disabled(preview == nil)
    Button("Edit…") { editing = true }
    Button("Export template…", action: exportTemplate)
    if isCondition && state["consumer_id"].string != nil {
      Button("Only from now…") { confirmingFromNow = true }
    }
  }
  private func close() {
    if let onClose { onClose() } else { dismiss() }
  }
  private var grantIsCurrent: Bool {
    guard let grant else { return false }
    return state["state"] == .string("armed")
      && [.string("foreground-drafts-v1"), .string("condition-drafts-v1")].contains(state["policy"])
      && state["id"] == .string(grant.id) && state["source_id"] == .string(grant.sourceID)
      && state["definition_id"] == .string(grant.definitionID)
      && state["generation"].int == grant.generation && state["allowAI"] == .bool(grant.allowAI)
  }
  private func load() async {
    guard let book = workspace.workbook else { return }
    let definition = shown
    do {
      let saved = try await Task.detached {
        (
          try book.previewAutomation(definition.id, after: Date()),
          try book.automationState(definition.id),
          try book.applicationDefinition(definition.payload["workflow"]["versionID"].text)
        )
      }.value
      guard !Task.isCancelled, workspace.workbook === book else { return }
      preview = saved.0
      state = saved.1
      workflow = saved.2
      if let id = state["consumer_id"].string {
        let status = try await Task.detached {
          (try book.inventoryCondition(id), try book.inventoryConditionQueue(id))
        }.value
        guard !Task.isCancelled, workspace.workbook === book else { return }
        conditionState = status.0
        conditionQueue = status.1
      } else {
        conditionState = .null
        conditionQueue = .null
      }
      await owner.reload()
      let registry = owner.registry
      let candidates = owner.grants.filter { $0.id == state["id"].text }
      grant = try await Task.detached {
        try candidates.first { try registry.matches($0, workbook: book) }
      }.value
      if let grant {
        allowAI = grant.allowAI
        let id = grant.definitionID
        enabledVersion = try? await Task.detached {
          try book.applicationDefinition(id).version
        }.value
      }
    } catch { failure = error.localizedDescription }
  }
  private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
    working = true
    failure = nil
    // Automatic work waits for this change only. It must not wait for the page to close.
    let owner = inspectionOwner
    NativeAutomationHost.shared.setBusy(owner, true)
    Task {
      do { try await operation() } catch {
        failure = "Could not confirm the requested state. " + error.localizedDescription
      }
      NativeAutomationHost.shared.setBusy(owner, false)
      await load()
      workspace.refresh()
      working = false
    }
  }
  private func exportTemplate() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = shown.title + " template.json"
    guard panel.runModal() == .OK, let file = panel.url, let book = workspace.workbook else {
      return
    }
    let id = shown.id
    Task {
      do {
        try await Task.detached { try book.exportTemplate(id, to: file) }.value
      } catch { failure = error.localizedDescription }
    }
  }
  private func runOnce() {
    guard let book = workspace.workbook else { return }
    let identity = workspace.interactionIdentity
    let payload = shown.payload
    workspace.run("Starting a manual workflow") { book, control in
      try book.startWorkflow(
        payload["workflow"]["versionID"].text,
        arguments: payload["arguments"], token: identifier(),
        actor: .human("Sevra.native-schedule-run-once"), cancellation: control)
    } completion: { run in
      close()
      workspace.navigate(.workflow(run["id"].text))
      Task {
        guard workspace.interactionActive, workspace.workbook === book,
          workspace.interactionIdentity == identity
        else { return }
        workspace.continueWorkflow(run["id"].text)
      }
    }
  }
}

struct ScheduleOccurrencePreview: View {
  let calendar: Value?
  var body: some View {
    if let calendar {
      Text("Upcoming times · " + calendar["schedule"]["timeZone"].text).font(.headline)
      ForEach(calendar["occurrences"].array, id: \.text) { slot in
        Text(description(slot)).font(.callout).textSelection(.enabled)
          .help("Exact UTC time: " + slot["due"].text)
      }
      if calendar["countReached"] != .bool(true) {
        Text("Preview reached its calendar horizon; only the times above were found.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private func description(_ slot: Value) -> String {
    let clock = slot["localDate"].text + " " + slot["actualLocalTime"].text
    let adjustment = slot["shifted"] == .bool(true) ? " (adjusted for daylight saving)" : ""
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = parser.date(from: slot["due"].text),
      let zone = TimeZone(identifier: calendar?["schedule"]["timeZone"].text ?? "")
    else { return clock + adjustment }
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.timeZone = zone
    formatter.dateStyle = .medium
    formatter.timeStyle = slot["actualLocalTime"].text.hasSuffix(":00") ? .short : .medium
    return formatter.string(from: date) + adjustment
  }
}
