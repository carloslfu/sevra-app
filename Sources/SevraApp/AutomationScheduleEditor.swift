import SevraCore
import SevraPreviewUI
import SwiftUI

struct AutomationScheduleEditor: View {
  @ObservedObject var workspace: WorkspaceState
  var existing: ApplicationDefinition?
  var onSave: ((ApplicationDefinition) -> Void)?
  @Environment(\.dismiss) private var dismiss
  @StateObject private var choices = DefinitionResultSession()
  @State private var query = ""
  @State private var workflow: ApplicationDefinition?
  @State private var choosingWorkflow = true
  @State private var title = ""
  @State private var arguments: Value = .object([:])
  @State private var trigger = "calendar"
  @State private var subject = ""
  @State private var comparison = "<"
  @State private var threshold = "10"
  @State private var zone = TimeZone.current.identifier
  @State private var hour = 9
  @State private var minute = 0
  @State private var recurrence = "daily"
  @State private var weekdays: Set<Int> = [1]
  @State private var day = 1
  @State private var lastDay = false
  @State private var month = 1
  @State private var preview: Value?
  @State private var previewContent: Value?
  @State private var failure: String?
  @State private var working = false
  @State private var editingOwner = UUID()
  @State private var logicalID = identifier()
  @State private var saveToken = identifier()
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(existing == nil ? "New automation" : "Edit automation").font(.title2)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          TextField("Automation title", text: $title)
          if let workflow {
            Text("Workflow: " + workflow.title + " · version \(workflow.version)").font(.headline)
            Text(workflow.description).foregroundStyle(.secondary)
          }
          DisclosureGroup(
            workflow == nil ? "Choose a saved workflow" : "Choose another workflow",
            isExpanded: $choosingWorkflow
          ) {
            TextField("Search workflows", text: $query)
            ForEach(choices.evaluation?["hits"].array ?? [], id: \.text) { row in
              Button(row["title"].text + " · version \(row["version"].int ?? 0)") {
                select(row["id"].text)
              }
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
          Picker("When", selection: $trigger) {
            Text("At a scheduled time").tag("calendar")
            Text("When inventory crosses a threshold").tag("inventory")
          }
          if trigger == "inventory" {
            TextField("Inventory subject", text: $subject)
            Picker("Stock becomes", selection: $comparison) {
              Text("Less than").tag("<")
              Text("At most").tag("<=")
              Text("Greater than").tag(">")
              Text("At least").tag(">=")
              Text("Equal to").tag("=")
              Text("Different from").tag("<>")
            }
            TextField("Quantity", text: $threshold)
            Text(
              "Enabling starts from the current stock. An already-true rule does not run until it becomes false and crosses again. Unknown stock waits for evidence."
            )
            .font(.caption).foregroundStyle(.secondary)
          } else {
            Picker("Repeat", selection: $recurrence) {
              Text("Daily").tag("daily")
              Text("Weekly").tag("weekly")
              Text("Monthly").tag("monthly")
              Text("Yearly").tag("yearly")
            }
            DatePicker("Time", selection: clockTime, displayedComponents: .hourAndMinute)
              .environment(\.timeZone, clockCalendar.timeZone)
              .accessibilityValue(String(format: "%02d:%02d", hour, minute) + " " + zone)
              .help("Uses the time zone below, even when this Mac’s time zone changes")
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
              "Missing dates are skipped. Repeated clock times run once; skipped clock times use the next valid time that day. The explicit time zone stays fixed when you travel."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
          if previewContent == content {
            if trigger == "inventory" {
              Text(
                "When \(subject) becomes \(comparison) \(threshold). Saving keeps this rule inactive."
              )
            } else {
              ScheduleOccurrencePreview(calendar: preview?["calendar"])
            }
          }
          Text(
            "Save keeps this automation in the workbook. Enable on this Mac is a separate step. Business changes still require review."
          )
          .font(.callout).foregroundStyle(.secondary)
        }
      }
      if working { ProgressView("Checking automation") }
      if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Preview") { prepare() }.disabled(workflow == nil)
        Button("Save automation") { save() }.keyboardShortcut(.defaultAction)
          .disabled(previewContent != content || preview == nil || workflow == nil)
      }
    }.padding(24).frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 720)
      .disabled(working || workspace.busy).interactiveDismissDisabled(working)
      .onAppear { NativeAutomationHost.shared.setBusy(editingOwner, true) }
      .onDisappear {
        NativeAutomationHost.shared.setBusy(editingOwner, false)
        choices.cancel()
      }
      .task { await open() }
      .onChange(of: workflow?.id) { _, id in if id != nil { choosingWorkflow = false } }
      .task(id: query + String(workspace.revision)) { await loadChoices() }
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
    if trigger == "inventory" {
      return .object([
        "kind": .string("automation"), "title": .string(title),
        "description": .string(
          "Prepare this workflow when the inventory rule crosses its threshold."),
        "parameters": .array([]),
        "payload": .object([
          "policy": .string("inventory-condition-drafts-v1"),
          "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow?.id ?? "")]),
          "arguments": arguments,
          "condition": .object([
            "subject": .string(subject),
            "rule": .object([
              "policy": .string("native-condition-v1"), "scope": .string("inventory:" + subject),
              "operator": .string(comparison), "threshold": .string(threshold),
            ]),
          ]),
        ]),
      ])
    }
    return .object([
      "kind": .string("automation"), "title": .string(title),
      "description": .string(
        existing?.description ?? "Prepare this saved workflow on a calendar schedule."),
      "parameters": .array([]),
      "payload": .object([
        "policy": .string("calendar-drafts-v1"),
        "workflow": .object(["mode": .string("exact"), "versionID": .string(workflow?.id ?? "")]),
        "arguments": arguments,
        "schedule": .object([
          "policy": .string("native-calendar-v1"), "timeZone": .string(zone),
          "hour": .number(Double(hour)), "minute": .number(Double(minute)), "recurrence": rule,
        ]),
      ]),
    ])
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
    guard let existing, let book = workspace.workbook else { return }
    title = existing.title
    arguments = existing.payload["arguments"]
    logicalID = existing.logicalID
    if existing.payload["policy"] == .string("inventory-condition-drafts-v1") {
      trigger = "inventory"
      subject = existing.payload["condition"]["subject"].text
      comparison = existing.payload["condition"]["rule"]["operator"].text
      threshold = existing.payload["condition"]["rule"]["threshold"].text
    }
    let schedule = existing.payload["schedule"]
    zone = schedule["timeZone"].text
    hour = schedule["hour"].int ?? 9
    minute = schedule["minute"].int ?? 0
    recurrence = schedule["recurrence"]["kind"].text
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
