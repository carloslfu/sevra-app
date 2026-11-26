import SevraAutomationUI
import SevraCore
import SevraPreviewUI
import SevraTableUI
import SwiftUI

struct AutomationSchedulesView: View {
  init(workspace: WorkspaceState) {
    self.workspace = workspace
    _owner = ObservedObject(wrappedValue: workspace.automation.controller)
  }
  @ObservedObject var workspace: WorkspaceState
  @ObservedObject private var owner: NativeAutomationController
  @StateObject private var pages = DefinitionResultSession()
  @State private var query = ""
  @State private var selected: ApplicationDefinition?
  @State private var creating = false
  @State private var failure: String?
  /// What starts each listed automation, by its definition ID.
  @State private var triggers: [String: String] = [:]
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        TextField("Find an automation", text: $query)
        Button("New automation…") { creating = true }.disabled(workspace.busy)
        Button("Import template…", action: importTemplate).disabled(workspace.busy)
        Button("Runs") { workspace.navigate(.activity) }
      }
      Text(owner.gate).readingFont(.callout).foregroundStyle(.secondary)
      Text(
        "Saved automations travel with this workbook. Enable each exact version on this Mac to run it here."
      )
      .readingFont(.caption).foregroundStyle(.secondary)
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
                Text(row["title"].text).readingFont(.headline).accessibilityAddTraits(.isHeader)
                Text("Version \(row["version"].int ?? 0) · " + row["description"].text)
                  .foregroundStyle(.secondary)
                if let trigger = triggers[row["id"].text] {
                  Label(trigger, systemImage: trigger.hasPrefix("On a") ? "calendar" : "checklist")
                    .readingFont(.caption).foregroundStyle(.secondary)
                }
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
          Text("Page \(pages.pageNumber)").readingFont(.caption)
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
                      .readingFont(.caption).foregroundStyle(.secondary)
                  }
                  Spacer()
                  Button("Open workbook") {
                    let registry = owner.registry
                    Task {
                      do {
                        let url = try await Task.detached { try registry.resolvedURL(grant) }.value
                        WorkbookFiles(openWindow: openWindow).show(url)
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
      .announceStatus(failure ?? pages.failure ?? owner.failure ?? owner.notice)
      .task(id: workspace.interactionIdentity.uuidString + String(workspace.revision) + query) {
        await load()
        await owner.reload()
      }
      .onDisappear { pages.cancel() }
      .task(id: (pages.evaluation?["hits"].array ?? []).map { $0["id"].text }.joined()) {
        await loadTriggers()
      }
      .sheet(item: $selected) { definition in
        AutomationScheduleDetail(definition: definition, workspace: workspace)
      }
      .sheet(isPresented: $creating) { AutomationScheduleEditor(workspace: workspace) }
  }
  private func importTemplate() {
    let panel = AppHost.openPanel()
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
  private func loadTriggers() async {
    guard let book = workspace.workbook else { return }
    let ids = (pages.evaluation?["hits"].array ?? []).map { $0["id"].text }
    let found = await Task.detached { () -> [String: String] in
      var found: [String: String] = [:]
      for id in ids {
        guard let definition = try? book.applicationDefinition(id) else { continue }
        found[id] = AutomationTrigger.text(definition, workbook: book)
      }
      return found
    }.value
    guard !Task.isCancelled, workspace.workbook === book else { return }
    triggers = found
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
  init(definition: ApplicationDefinition, workspace: WorkspaceState, onClose: (() -> Void)? = nil) {
    self.definition = definition
    self.workspace = workspace
    self.onClose = onClose
    _owner = ObservedObject(wrappedValue: workspace.automation.controller)
  }
  let definition: ApplicationDefinition
  @ObservedObject var workspace: WorkspaceState
  var onClose: (() -> Void)? = nil
  @ObservedObject private var owner: NativeAutomationController
  @Environment(\.dismiss) private var dismiss
  @State private var preview: Value?
  @State private var state: Value = .null
  @State private var inspectionOwner = UUID()
  @State private var workflow: ApplicationDefinition?
  @State private var grant: AutomationDeviceGrant?
  @State private var allowAI = false
  @State private var working = false
  @State private var changeNotice: String?
  @State private var editing = false
  @State private var failure: String?
  @State private var updatedDefinition: ApplicationDefinition?
  @State private var enabledVersion: Int?
  @State private var loadedDefinitionID: String?
  @State private var checkState: Value = .null
  private var shown: ApplicationDefinition { updatedDefinition ?? definition }
  /// A check starts it, not a calendar. Its page shows no calendar sections.
  private var startsWithCheck: Bool { shown.payload["policy"] == .string("check-v1") }
  var body: some View {
    let page = VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(shown.title).readingFont(.title2).accessibilityAddTraits(.isHeader)
        Text("Saved version \(shown.version)").readingFont(.caption).foregroundStyle(.secondary)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if !shown.description.isEmpty {
            Text(shown.description).fixedSize(horizontal: false, vertical: true)
          }
          trigger
          Divider()
          if let workflow {
            VStack(alignment: .leading, spacing: 6) {
              Text("Then it runs " + workflow.title).readingFont(.headline)
                .accessibilityAddTraits(.isHeader)
              if !workflow.description.isEmpty {
                Text(workflow.description).readingFont(.callout).foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            if !workflow.parameters.array.isEmpty {
              WorkflowInputsView(
                parameters: workflow.parameters.array,
                arguments: shown.payload["arguments"], workspace: workspace)
            }
          }
          if let notice = preview?["notice"].string {
            Text(notice).readingFont(.callout)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityLabel("Before you enable it. " + notice)
          }
          Divider()
          Text("On this Mac").readingFont(.headline).accessibilityAddTraits(.isHeader)
          if let grant {
            Text(
              grantIsCurrent
                ? AutomationGrantNotice.text(
                  enabled: grant.definitionID == shown.id ? shown.version : enabledVersion,
                  shown: shown.version)
                : "This device registration is stale. The workbook no longer authorizes it."
            ).fixedSize(horizontal: false, vertical: true)
            Text(owner.status(grant.id)).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Button(grantIsCurrent ? "Pause on this Mac" : "Remove stale registration") {
              perform { try await owner.pause(grant) }
            }
          } else {
            Text("This automation is not enabled for this workbook on this Mac.")
              .fixedSize(horizontal: false, vertical: true)
          }
          Toggle("Allow this exact workflow to use local AI", isOn: $allowAI)
          Text(
            startsWithCheck
              ? "The check runs while Sevra is active, after each change and every minute. When Sevra opens again or you resume it, the check runs at once, so rows that appeared meanwhile start it once. No background helper is installed."
              : "Runs while Sevra is active. Times missed while Sevra was closed catch up when eligible. No background helper is installed."
          )
          .readingFont(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
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
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      if working { ProgressView("Updating automation") }
      if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        Spacer()
        Button("Done") { close() }.keyboardShortcut(.cancelAction)
      }
    }.padding(24)
    Group {
      if onClose == nil {
        // A sheet sizes itself. In the workspace the page takes the pane's width instead, so
        // a narrow pane wraps it rather than clipping both edges.
        page.frame(minWidth: 540, idealWidth: 620, minHeight: 440, idealHeight: 660)
      } else {
        page.frame(maxWidth: 760, alignment: .leading)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
      .disabled(working || workspace.busy).interactiveDismissDisabled(working)
      .announceStatus(failure ?? changeNotice)
      .task(id: workspace.interactionIdentity.uuidString + shown.id + String(workspace.revision)) {
        await load()
      }
      .sheet(isPresented: $editing, onDismiss: workspace.refresh) {
        AutomationScheduleEditor(
          workspace: workspace, existing: shown, onSave: { updatedDefinition = $0 })
      }
  }
  /// What starts it: the check, with what it watches and its last change, or the calendar.
  @ViewBuilder private var trigger: some View {
    if startsWithCheck {
      if let check = preview?["check"], check != .null {
        VStack(alignment: .leading, spacing: 6) {
          Text("Starts when the check " + check["name"].text + " finds rows")
            .readingFont(.headline).accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
          if !check["description"].text.isEmpty {
            Text(check["description"].text).readingFont(.callout).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Text(AutomationTrigger.checkState(checkState)).readingFont(.callout)
          .fixedSize(horizontal: false, vertical: true)
      }
    } else {
      ScheduleOccurrencePreview(calendar: preview?["calendar"])
    }
  }
  @ViewBuilder private var automationActions: some View {
    Button("Enable on this Mac") {
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
  }
  private func close() {
    if let onClose { onClose() } else { dismiss() }
  }
  private var grantIsCurrent: Bool {
    guard let grant else { return false }
    return state["state"] == .string("armed")
      && state["policy"] == .string("foreground-drafts-v1")
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
      let activation = saved.1["id"].string
      let edge = try await Task.detached {
        try activation.map { try book.automationCheckState($0) } ?? .null
      }.value
      guard !Task.isCancelled, workspace.workbook === book, shown.id == definition.id else {
        return
      }
      preview = saved.0
      state = saved.1
      workflow = saved.2
      checkState = edge
      await owner.reload()
      let registry = owner.registry
      let candidates = owner.grants.filter { $0.id == state["id"].text }
      let currentGrant = try await Task.detached {
        try candidates.first { try registry.matches($0, workbook: book) }
      }.value
      var currentEnabledVersion: Int?
      if let currentGrant {
        let id = currentGrant.definitionID
        currentEnabledVersion = try? await Task.detached {
          try book.applicationDefinition(id).version
        }.value
      }
      guard !Task.isCancelled, workspace.workbook === book, shown.id == definition.id else {
        return
      }
      // Live run updates must not undo an unsaved permission choice in this page.
      if let currentGrant,
        loadedDefinitionID != definition.id || grant?.id != currentGrant.id
          || grant?.generation != currentGrant.generation
      {
        allowAI = currentGrant.allowAI
      }
      grant = currentGrant
      enabledVersion = currentEnabledVersion
      loadedDefinitionID = definition.id
    } catch {
      guard !Task.isCancelled, workspace.workbook === book, shown.id == definition.id else {
        return
      }
      failure = error.localizedDescription
    }
  }
  private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
    working = true
    failure = nil
    changeNotice = nil
    // Automatic work waits for this change only. It must not wait for the page to close.
    let owner = inspectionOwner
    workspace.automation.setBusy(owner, true)
    Task {
      do { try await operation() } catch {
        failure = "Could not confirm the requested state. " + error.localizedDescription
      }
      workspace.automation.setBusy(owner, false)
      await load()
      workspace.refresh()
      if failure == nil {
        changeNotice = "Automation updated. Review its current permission and status below."
      }
      working = false
    }
  }
  private func exportTemplate() {
    let panel = AppHost.savePanel()
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
    if let calendar, calendar != .null {
      let zone = calendar["schedule"]["timeZone"].text
      VStack(alignment: .leading, spacing: 6) {
        Text(zone.isEmpty ? "Upcoming times" : "Upcoming times in " + zone)
          .readingFont(.headline).accessibilityAddTraits(.isHeader)
        ForEach(calendar["occurrences"].array, id: \.text) { slot in
          Text(description(slot)).readingFont(.callout).textSelection(.enabled)
            .help("Exact UTC time: " + slot["due"].text)
        }
      }
      if calendar["occurrences"].array.isEmpty {
        Text("No times fall in the next ten years.")
          .readingFont(.caption).foregroundStyle(.secondary)
      } else if calendar["countReached"] != .bool(true) {
        Text("These are the only times in the next ten years.")
          .readingFont(.caption).foregroundStyle(.secondary)
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

/// How an automation's trigger reads in a list and on its page.
enum AutomationTrigger {
  static func text(_ definition: ApplicationDefinition, workbook: Workbook) -> String {
    guard definition.payload["policy"] == .string("check-v1") else {
      return "On a schedule"
    }
    // The check is followed by its logical ID, so this is its current name.
    let name =
      (try? workbook.applicationDefinition(definition.payload["check"]["logicalID"].text))
      .map { $0.payload["name"].text } ?? "its check"
    return "When the check " + name + " finds rows"
  }

  /// The check's last saved change, in one or two sentences.
  static func checkState(_ state: Value) -> String {
    guard state != .null else {
      return "The check has not run yet. If it finds rows when you enable it, it starts the workflow once right away."
    }
    let rows = state["rows"].int ?? 0
    let when = ISO8601DateFormatter().date(from: state["updated"].text).map {
      " on " + $0.formatted(date: .abbreviated, time: .shortened)
    } ?? ""
    return state["finding"].int == 1
      ? "Last change: it found \(rows == 1 ? "1 row" : "\(rows) rows")\(when). It starts again after the check finds no rows."
      : "Last change: it found no rows\(when). It starts when the check finds rows."
  }
}
