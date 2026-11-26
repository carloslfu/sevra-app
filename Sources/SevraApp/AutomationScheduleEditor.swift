import SevraCore
import SevraPreviewUI
import SevraTableUI
import SwiftUI

struct AutomationScheduleEditor: View {
  @ObservedObject var workspace: WorkspaceState
  var existing: ApplicationDefinition?
  var onSave: ((ApplicationDefinition) -> Void)?
  /// A new automation opens on the check trigger.
  var startsWithCheck = false
  @Environment(\.dismiss) private var dismiss
  @StateObject private var choices = DefinitionResultSession()
  @State private var query = ""
  @State private var workflow: ApplicationDefinition?
  @State private var choosingWorkflow = true
  @State private var title = ""
  @State private var arguments: Value = .object([:])
  // With TZ=UTC Foundation names the zone GMT, which the schedule refuses as unnamed.
  @State private var zone =
    TimeZone.current.identifier == "GMT" ? "UTC" : TimeZone.current.identifier
  @State private var hour = 9
  @State private var minute = 0
  @State private var recurrence = "daily"
  @State private var weekdays: Set<Int> = [1]
  @State private var day = 1
  @State private var lastDay = false
  @State private var month = 1
  /// What starts it: "schedule" or "check".
  @State private var trigger = "schedule"
  @State private var checks: [Workbook.SavedTool] = []
  @State private var checksLoaded = false
  @State private var checkID: String?
  @State private var preview: Value?
  @State private var previewContent: Value?
  @State private var failure: String?
  @State private var working = false
  @State private var editingOwner = UUID()
  @State private var logicalID = identifier()
  @State private var saveToken = identifier()
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(existing == nil ? "New automation" : "Edit automation").readingFont(.title2)
        .accessibilityAddTraits(.isHeader)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          TextField("Automation title", text: $title)
          if let workflow {
            Text("Workflow: " + workflow.title + " · version \(workflow.version)").readingFont(
              .headline
            ).accessibilityAddTraits(.isHeader)
            Text(workflow.description).foregroundStyle(.secondary)
          }
          DisclosureGroup(
            workflow == nil ? "Choose a saved workflow" : "Choose another workflow",
            isExpanded: $choosingWorkflow
          ) {
            TextField("Search workflows", text: $query)
            ForEach(choices.evaluation?["hits"].array ?? [], id: \.text) { row in
              Button {
                select(row["id"].text)
              } label: {
                Text(row["title"].text + " · version \(row["version"].int ?? 0)")
                  .multilineTextAlignment(.leading)
                  .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                  .contentShape(Rectangle())
              }.buttonStyle(.bordered)
            }
            if choices.evaluation?["hits"].array.isEmpty == true && !choices.loading {
              Text(
                query.isEmpty
                  ? "Save a workflow in the conversation first." : "No workflows match this search."
              )
              .foregroundStyle(.secondary)
            }
            if choices.hasPrevious || choices.hasNext {
              HStack {
                Button("Previous") { Task { await loadChoices(-1) } }.disabled(!choices.hasPrevious)
                Button("Next") { Task { await loadChoices(1) } }.disabled(!choices.hasNext)
              }.disabled(choices.loading)
            }
            if let failure = choices.failure { Text(failure).foregroundStyle(.red) }
          }
          if let workflow {
            ForEach(workflow.parameters.array, id: \.text) { parameter in
              FormParameterField(
                parameter: parameter, value: argument(parameter),
                workbook: workspace.workbook)
            }
          }
          Divider()
          LabeledContent("Starts") {
            Picker("Starts", selection: $trigger) {
              Text("On a schedule").tag("schedule")
              Text("When a saved check finds rows").tag("check")
            }.labelsHidden().pickerStyle(.radioGroup)
          }
          if trigger == "check" {
            checkFields
          } else {
            scheduleFields
          }
          Text(
            "Save keeps this automation in the workbook. Enable on this Mac is a separate step. Business changes still require review."
          )
          .readingFont(.callout).foregroundStyle(.secondary)
        }.labeledContentStyle(ScheduleFieldStyle())
      }
      if working { ProgressView("Checking automation") }
      if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Preview") { prepare() }.disabled(!ready)
        Button("Save automation") { save() }.keyboardShortcut(.defaultAction)
          .disabled(previewContent != content || preview == nil || !ready)
      }
    }.padding(24).frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 720)
      .disabled(working || workspace.busy).interactiveDismissDisabled(working)
      .announceStatus(
        failure
          ?? (!working && preview != nil
            ? "Automation preview is ready. Review it before saving." : nil)
      )
      .onAppear { workspace.automation.setBusy(editingOwner, true) }
      .onDisappear {
        workspace.automation.setBusy(editingOwner, false)
        choices.cancel()
      }
      .task { await open() }
      .onChange(of: workflow?.id) { _, id in if id != nil { choosingWorkflow = false } }
      .task(id: query + String(workspace.revision)) { await loadChoices() }
      .task(id: String(workspace.revision)) { await loadChecks() }
  }
  /// A workflow is chosen, and a check when the check starts it.
  private var ready: Bool { workflow != nil && (trigger == "schedule" || checkID != nil) }
  @ViewBuilder private var checkFields: some View {
    if checksLoaded && checks.isEmpty && checkID == nil {
      VStack(alignment: .leading, spacing: 6) {
        Text("No saved checks yet").readingFont(.headline)
        Text(
          "A check is a saved SQL tool with no inputs that selects the rows to watch, such as parts below their reorder level. Ask in the chat to save one, then choose it here."
        )
        .readingFont(.callout).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    } else {
      LabeledContent("Check") {
        Picker("Check", selection: $checkID) {
          Text("Choose a check").tag(String?.none)
          ForEach(checks, id: \.definitionID) { tool in
            Text(tool.name).tag(Optional(tool.definitionID))
          }
          if let checkID, !checks.contains(where: { $0.definitionID == checkID }) {
            Text("The version saved with this automation").tag(Optional(checkID))
          }
        }.labelsHidden().accessibilityLabel("Check")
      }
      if let tool = checks.first(where: { $0.definitionID == checkID }) {
        Text(tool.description.isEmpty ? tool.statements.last ?? "" : tool.description)
          .readingFont(.callout).foregroundStyle(.secondary).textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        if !tool.enabled {
          Text(
            "This check came with the workbook. Enable it under Tools before this automation can run here."
          )
          .readingFont(.caption).foregroundStyle(.secondary)
        }
      }
    }
    Text(
      "It starts when the check finds rows after finding none, and again only after the check finds no rows. The first check after you enable it counts any rows it finds. The check runs while Sevra is active, after each change and every minute."
    )
    .readingFont(.caption).foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
    if previewContent == content, let check = preview?["check"], check != .null {
      Label("Watches " + check["name"].text, systemImage: "checkmark.circle")
        .readingFont(.callout)
    }
  }
  @ViewBuilder private var scheduleFields: some View {
    LabeledContent("Repeat") {
      Picker("Repeat", selection: $recurrence) {
        Text("Daily").tag("daily")
        Text("Weekly").tag("weekly")
        Text("Monthly").tag("monthly")
        Text("Yearly").tag("yearly")
      }.labelsHidden()
    }
    LabeledContent("Time") {
      DatePicker("Time", selection: clockTime, displayedComponents: .hourAndMinute)
        .labelsHidden().environment(\.timeZone, clockCalendar.timeZone)
        .accessibilityValue(String(format: "%02d:%02d", hour, minute) + " " + zone)
        .help("Uses the time zone below, even when this Mac’s time zone changes")
    }
    LabeledContent("Time zone") {
      TextField("America/Bogota or UTC", text: $zone)
        .accessibilityLabel("Time zone")
    }
    if recurrence == "weekly" {
      HStack {
        ForEach(
          Array(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].enumerated()),
          id: \.offset
        ) { index, name in
          Toggle(
            name,
            isOn: Binding(
              get: { weekdays.contains(index + 1) },
              set: { enabled in
                if enabled {
                  weekdays.insert(index + 1)
                } else {
                  weekdays.remove(index + 1)
                }
              })
          ).toggleStyle(.button)
        }
      }
    }
    if recurrence == "monthly" {
      Toggle("Last day of the month", isOn: $lastDay)
      if !lastDay { Stepper("Day: \(day)", value: $day, in: 1...31) }
    }
    if recurrence == "yearly" {
      Picker("Month", selection: $month) {
        ForEach(Array(clockCalendar.monthSymbols.enumerated()), id: \.offset) {
          index, name in
          Text(name).tag(index + 1)
        }
      }
      Stepper("Day: \(day)", value: $day, in: 1...31)
    }
    Text(
      "Missing dates are skipped. Repeated clock times run once; skipped clock times use the next valid time. The explicit time zone stays fixed when you travel."
    )
    .readingFont(.caption).foregroundStyle(.secondary)
    if previewContent == content {
      ScheduleOccurrencePreview(calendar: preview?["calendar"])
    }
  }
  // This is a wall-clock editor, not an instant in the Mac's time zone. Bind
  // through a fixed UTC date so changing the schedule's zone never shifts it.
  private var clockCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }
  private var clockTime: Binding<Date> {
    Binding(
      get: {
        clockCalendar.date(
          from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute))!
      },
      set: { time in
        hour = clockCalendar.component(.hour, from: time)
        minute = clockCalendar.component(.minute, from: time)
      })
  }
  private var content: Value {
    let rule: Value
    switch recurrence {
    case "weekly":
      rule = .object([
        "kind": .string("weekly"),
        "weekdays": .array(weekdays.sorted().map { .number(Double($0)) }),
      ])
    case "monthly":
      rule = .object([
        "kind": .string("monthly"), "day": lastDay ? .string("last") : .number(Double(day)),
      ])
    case "yearly":
      rule = .object([
        "kind": .string("yearly"), "month": .number(Double(month)), "day": .number(Double(day)),
      ])
    default: rule = .object(["kind": .string("daily")])
    }
    var payload: [String: Value] = [
      "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow?.id ?? "")]),
      "arguments": arguments,
    ]
    if trigger == "check" {
      payload["policy"] = .string("check-drafts-v1")
      payload["check"] = .object(["mode": .string("exact"), "versionID": .string(checkID ?? "")])
    } else {
      payload["policy"] = .string("calendar-drafts-v1")
      payload["schedule"] = .object([
        "policy": .string("native-calendar-v1"), "timeZone": .string(zone),
        "hour": .number(Double(hour)), "minute": .number(Double(minute)), "recurrence": rule,
      ])
    }
    return .object([
      "kind": .string("automation"), "title": .string(title),
      "description": .string(description),
      "parameters": .array([]),
      "payload": .object(payload),
    ])
  }
  private static let calendarDescription = "Prepare this saved workflow on a calendar schedule."
  private static let checkDescription = "Prepare this saved workflow when its check finds rows."
  /// A written description survives an edit. The default one follows the trigger.
  private var description: String {
    let standard = trigger == "check" ? Self.checkDescription : Self.calendarDescription
    guard let written = existing?.description,
      ![Self.calendarDescription, Self.checkDescription].contains(written)
    else { return standard }
    return written
  }
  /// The saved SQL tools that can be checks: no inputs. Whether one only reads is checked when
  /// the automation is previewed.
  private func loadChecks() async {
    guard let book = workspace.workbook else { return }
    do {
      let found = try await Task.detached {
        try book.savedTools().filter { $0.language == "sql" && $0.inputs.isEmpty }
      }.value
      guard !Task.isCancelled, workspace.workbook === book else { return }
      checks = found
      checksLoaded = true
    } catch { failure = error.localizedDescription }
  }
  private func argument(_ parameter: Value) -> Binding<Value> {
    let key = parameter["id"].text
    return .init(
      get: { arguments.object[key] ?? parameter.object["default"] ?? .null },
      set: {
        var values = arguments.object
        values[key] = $0
        arguments = .object(values)
      })
  }
  private func loadChoices(_ direction: Int = 0) async {
    guard let book = workspace.workbook else { return }
    let query = query
    await choices.load(scope: book.id + query + String(workspace.revision), direction: direction) {
      cursor, control in
      try await Task.detached {
        try book.searchApplicationDefinitions(
          query, kind: "workflow", cursor: cursor, cancellation: control)
      }.value
    }
  }
  private func open() async {
    if existing == nil, startsWithCheck { trigger = "check" }
    guard let existing, let book = workspace.workbook else { return }
    title = existing.title
    arguments = existing.payload["arguments"]
    logicalID = existing.logicalID
    if existing.payload["policy"] == .string("check-drafts-v1") {
      trigger = "check"
      checkID = existing.payload["check"]["versionID"].string
    }
    let schedule = existing.payload["schedule"]
    if let saved = schedule["timeZone"].string { zone = saved }
    hour = schedule["hour"].int ?? 9
    minute = schedule["minute"].int ?? 0
    recurrence = schedule["recurrence"]["kind"].string ?? "daily"
    weekdays = Set(schedule["recurrence"]["weekdays"].array.compactMap(\.int))
    day = schedule["recurrence"]["day"].int ?? 1
    month = schedule["recurrence"]["month"].int ?? 1
    lastDay = schedule["recurrence"]["day"] == .string("last")
    do {
      let selected = try await Task.detached {
        try book.applicationDefinition(existing.payload["workflow"]["versionID"].text)
      }.value
      guard !Task.isCancelled, workspace.workbook === book else { return }
      workflow = selected
    } catch { failure = error.localizedDescription }
  }
  private func select(_ id: String) {
    guard let book = workspace.workbook else { return }
    working = true
    Task {
      defer { working = false }
      do {
        let selected = try await Task.detached { try book.applicationDefinition(id) }.value
        guard !Task.isCancelled, workspace.workbook === book else { return }
        workflow = selected
        arguments = .object([:])
        preview = nil
        if title.isEmpty { title = selected.title }
      } catch { failure = error.localizedDescription }
    }
  }
  private func prepare() {
    guard let book = workspace.workbook, let workflow else { return }
    let captured = content
    working = true
    failure = nil
    Task {
      defer { working = false }
      do {
        let result = try await Task.detached {
          try require(
            !captured["title"].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "definition", "Enter an automation title.")
          let issues = try book.applicationInputIssues(
            workflow.id, arguments: captured["payload"]["arguments"])
          try require(
            issues.isEmpty, "definition_input",
            issues.map { $0["message"].text }.joined(separator: "\n"))
          return try book.previewAutomationDraft(captured, after: Date())
        }.value
        guard !Task.isCancelled, workspace.workbook === book else { return }
        preview = result
        previewContent = captured
      } catch { failure = error.localizedDescription }
    }
  }
  private func save() {
    let captured = content
    guard previewContent == captured, let book = workspace.workbook else { return }
    working = true
    failure = nil
    let logicalID = logicalID
    let saveToken = saveToken
    let base = existing?.id
    Task {
      defer { working = false }
      do {
        let saved = try await Task.detached {
          try book.saveApplicationDefinition(
            logicalID: logicalID, content: captured,
            expectedDefinitionID: base, token: saveToken,
            actor: .human("Sevra.native-schedule-save"))
        }.value
        guard !Task.isCancelled, workspace.workbook === book else { return }
        workspace.refresh()
        onSave?(saved)
        dismiss()
      } catch { failure = error.localizedDescription }
    }
  }
}

private struct ScheduleFieldStyle: LabeledContentStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      configuration.label.frame(minWidth: 96, alignment: .leading)
      configuration.content.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
