import Foundation
import SevraAppProtocol
import SevraCore

struct CatalogStory: Identifiable, Codable, Hashable {
  let id: String
  let title: String
  let group: String
  let source: String
  let capabilities: [String]
  let variants: [String]
  let note: String
  var level: String {
    group == "Compositions"
      ? "Flows"
      : id.contains(".state.") || id.contains("conflict") || id == "main.lifecycle"
        ? "States" : "Components"
  }
  var evidence: String { "Registered" }
  var actions: [String] {
    group == "Compositions"
      ? CatalogFlows.steps(id)
      : ["Edit native controls", "Advance flow", "Reset", "Capture", "Open dedicated window"]
  }
  var readiness: String {
    id == "mini.state.starting"
      ? "Explicit transport gate remains pending"
      : "Workbook snapshot hydrated; worker settled if enabled; canvas mounted"
  }
  var exclusions: [String] {
    [
      "OS accessibility and system preferences need manual qualification",
      "Real model reliability is outside scripted fixtures",
      "Sheets, popovers and media may require a live dedicated window",
    ]
  }
  var statePolicy: String {
    "Only listed initial states are selectable. Interactive states are reached through the production controls; unsupported OS states are manual, never counted as passed."
  }
}

enum CatalogRegistry {
  static let charts = [
    "bar", "horizontalBar", "stackedBar", "line", "area", "scatter", "donut", "histogram",
    "heatmap", "metric", "table", "records",
  ]
  static let work = ["board", "timeline", "agenda", "calendar"]
  static let content = SpaceDefinition.contentTypes.sorted()
  static let groups = [
    "Compositions", "Main app", "Home & spaces", "Mini apps", "Chat", "Shared visuals",
  ]
  static let common = ["Default", "Empty", "Dense", "Long labels", "Disabled"]
  static var stories: [CatalogStory] {
    var result: [CatalogStory] = []
    func add(
      _ id: String, _ title: String, _ group: String, _ source: String,
      _ variants: [String] = common,
      _ note: String = "Uses the production view with synthetic workbook data.",
      _ capabilities: [String] = []
    ) {
      result.append(
        .init(
          id: id, title: title, group: group, source: source,
          capabilities: capabilities.isEmpty ? [id] : capabilities, variants: variants, note: note))
    }
    for (id, title) in [
      ("first-workbook", "First workbook"), ("supplier", "Supplier comparison"),
      ("inventory", "Inventory workspace"), ("projects", "Project planning"),
      ("overview", "Business overview"), ("evidence", "Evidence review"),
      ("excel", "Excel conversion"), ("interrupted", "Interrupted work"),
      ("workflow", "Workflow attention"), ("surfaces", "Captured and current"),
    ] {
      add(
        "composition." + id, title, "Compositions", "Sources/SevraApp/WorkbookView.swift",
        ["Default", "Long labels", "Failure"],
        "A working synthetic composition. Replay advances production operations; inspect receipts in Behavior."
      )
    }
    for (id, title, source, variants) in [
      ("welcome", "Welcome", "WelcomeView.swift", ["Default", "Empty", "Dense"]),
      ("opening", "Opening a workbook", "WelcomeView.swift", ["Default", "Long labels"]),
      (
        "shell", "Workbook shell", "WorkbookView.swift",
        ["Default", "Focused", "Busy", "Failure", "Long labels"]
      ),
      (
        "navigation", "Spaces and navigation", "SpacePickerView.swift",
        ["Default", "Empty", "Long labels"]
      ),
      ("commands", "Commands and chrome", "WorkbookView.swift", ["Default", "Busy", "Focused"]),
      ("search", "Search", "ContentViews.swift", ["Default", "Empty", "Long labels"]),
      (
        "table", "Editable table", "ContentViews.swift",
        ["Default", "Empty", "Dense", "Long labels", "Formula", "Archived"]
      ),
      (
        "document", "Document and provenance", "Viewers.swift",
        ["Default", "Historical", "Removed", "Removed while open", "Failure", "Long labels"]
      ),
      ("intake", "Import and table update", "IntakeView.swift", ["Default", "Empty", "Failure"]),
      (
        "excel", "Excel conversion", "ExcelConversionView.swift",
        ["Default", "Review", "Analyzing", "Building", "Attention", "Tables", "Ready", "Failure"]
      ),
      ("review", "Draft review", "ReviewQueueView.swift", ["Default", "Empty", "Dense"]),
      (
        "definitions", "Calculations and forms", "DefinitionComponentView.swift",
        ["Default", "Empty", "Failure"]
      ),
      (
        "workflows", "Workflow runs", "WorkflowActivityView.swift",
        ["Default", "Empty", "Queued", "Running", "Completed", "Cancelled", "Failure"]
      ),
      (
        "automations", "Automations", "AutomationSchedulesView.swift",
        ["Default", "Empty", "Detail", "Armed", "Paused", "Stale"]
      ),
      ("tools", "Saved tools", "ToolsView.swift", ["Default", "Empty"]),
      ("removed", "Removed", "RemovedView.swift", ["Default", "Empty"]),
      (
        "settings", "Model and reading settings", "SpeechAndSettings.swift",
        ["Default", "Installing", "Installed", "Loading", "Failure", "Cancelled", "Software updates"]
      ),
      ("voice", "Dictation", "SpeechAndSettings.swift", ["Default", "Recording", "Denied"]),
      ("lifecycle", "Reopen and preserve drafts", "WorkspaceState.swift", ["Default", "Failure"]),
    ] { add("main." + id, title, "Main app", "Sources/SevraApp/" + source, variants) }
    for kind in [
      "pdf", "text", "csv", "image", "audio", "video", "archive", "extracted", "references",
    ] {
      add(
        "main.viewer." + kind, kind.capitalized + " viewer", "Main app",
        "Sources/SevraApp/Viewers.swift", ["Default", "Failure"],
        "Synthetic local file. OS-owned Quick Look and media behavior require manual review on this Mac."
      )
    }
    for type in content + SpaceDefinition.sectionTypes.sorted() {
      add(
        "home.component." + type, type.capitalized, "Home & spaces",
        "Sources/SevraApp/ContentViews.swift",
        type == "app"
          ? ["Default", "Disabled", "Missing", "Changed version", "Missing view"] : common,
        "Ordinary-space component, using the same renderer as Home.", ["space." + type])
    }
    for (id, title) in [
      ("start", "Fresh Home"), ("returning", "Continue working"), ("attention", "Needs attention"),
      ("customized", "Customized Home"), ("empty", "Explicitly empty Home"),
      ("embedded", "Embedded mini app"), ("layout", "Layout and history"),
      ("comparison", "Responsive comparison"), ("limits", "Composition limits"),
      ("counter", "Count with a button"),
    ] {
      add(
        "home." + id, title, "Home & spaces", "Sources/SevraApp/HomeViews.swift",
        id == "comparison" ? ["Default", "Long labels"] : ["Default"])
    }
    for type in NativeAppNode.types.sorted() {
      add(
        "mini.node." + type, type, "Mini apps", "Sources/SevraAppUI/NativeAppRenderer.swift",
        common, "Real native renderer and signed JavaScript worker.", ["node." + type])
    }
    for helper in [
      "Fragment", "Workspace", "ActionForm", "For", "signal", "computed", "effect", "batch",
      "draftSignal", "liveQuery", "calculate", "action",
    ] {
      add(
        "mini.helper." + helper, helper, "Mini apps", "sdk/src/runtime.ts",
        ["Default", "Disabled"], "SDK behavior composed from real native primitives.",
        ["sdk." + helper])
    }
    for kind in ["chart", "work", "diagram", "overview", "text", "image"] {
      add(
        "mini.view." + kind, "Declared " + kind, "Mini apps",
        "Sources/SevraAppUI/NativeAppDeclaredView.swift",
        ["Default", "Disabled"] + (kind == "chart" ? charts : kind == "work" ? work : []),
        kind == "image"
          ? "Not applicable as a declared view: the product uses a granted native Image alias instead."
          : "Actual declared app view, protected by its app version grant.",
        ["declared-view." + kind])
    }
    for app in ["inventory", "jobs", "planner"] {
      add(
        "mini.example." + app, app.capitalized, "Mini apps", "examples/apps/" + app + "/main.tsx",
        ["Default", "Disabled"])
    }
    for state in [
      "access", "starting", "failed", "revoke", "stale-version", "draft", "invalid-frame", "limits",
      "canvas-keyboard", "paging",
    ] {
      add(
        "mini.state." + state, state.replacingOccurrences(of: "-", with: " ").capitalized,
        "Mini apps", "Sources/SevraAppUI/NativeAppSession.swift", ["Default"])
    }
    for type in ConversationSurface.Field.Kind.allCases.map(\.rawValue) {
      add(
        "chat.field." + type, type.capitalized + " input", "Chat",
        "Sources/SevraPreviewUI/ConversationInputView.swift",
        ["Default", "Draft", "Conflict", "Answered", "Skipped", "Cancelled"],
        "Typed input persists through the real conversation input lifecycle.", ["field." + type])
    }
    for kind in [
      "messages", "composer", "activity", "choices", "multiple-pending", "draft-conflict",
      "continuation", "approval", "undo-redo", "visuals", "history", "chats", "context",
    ] {
      add(
        "chat." + kind, kind.replacingOccurrences(of: "-", with: " ").capitalized, "Chat",
        "Sources/SevraApp/ConversationViews.swift",
        kind == "activity"
          ? [
            "Default", "Opened", "Empty", "Busy", "Thinking", "Thinking opened", "Between steps",
            "Streaming", "Starting", "Not sent", "Failure", "Long labels",
          ]
          : ["Default", "Empty", "Busy", "Failure", "Long labels"])
    }
    add(
      "chat.queue", "Waiting messages", "Chat", "Sources/SevraApp/QueuedMessagesView.swift",
      ["Default", "Paused", "Many"],
      "Messages written during a reply, in the person's order: edit, reorder, remove, resume; no count limit, so a long queue scrolls.")
    add(
      "chat.chat-list", "Chat list", "Chat", "Sources/SevraApp/ChatListPanel.swift",
      ["Default", "Empty", "Long labels"],
      "The chats panel over the chat pane: chats grouped by last activity, the open chat marked.")
    for kind in ["chart.bar", "work.board", "diagram", "overview", "text", "image"] {
      add(
        "chat.visual." + kind, "Captured " + kind, "Chat",
        "Sources/SevraApp/ConversationViews.swift", ["Default"],
        "Actual captured result through the production agent; live promotion and source navigation retain ownership boundaries.",
        ["chat.visual." + kind])
    }
    for style in charts {
      add(
        "visual.chart." + style, style + " chart", "Shared visuals",
        "Sources/SevraVisualUI/VisualChartView.swift",
        ["Default", "Empty", "Dense", "Long labels", "Failure"]
          + (style == "bar" ? ["Grouped", "Annotated", "Negative", "Missing and zero"] : []),
        "Exact query values. Sources, selection and export use the production visual.",
        ["chart." + style])
    }
    for style in work {
      add(
        "visual.work." + style, style.capitalized, "Shared visuals",
        "Sources/SevraVisualUI/WorkVisualView.swift",
        ["Default", "Empty", "Dense", "Long labels", "Failure"],
        "Live owner view; captured chat and declared app views retain their own editing boundaries.",
        ["work." + style])
    }
    for kind in ["diagram", "overview", "text", "image"] {
      add(
        "visual." + kind, kind.capitalized, "Shared visuals", "Sources/SevraVisualUI/",
        kind == "image"
          ? ["Default", "Portrait", "Transparency", "Missing", "Corrupt", "Failure"]
          : kind == "overview"
            ? ["Default", "Eight panels", "Empty", "Long labels"]
            : kind == "text"
              ? ["Default", "Long labels", "Disabled", "Invalid"]
              : kind == "diagram"
                ? ["Default", "Branch", "Cycle", "Disconnected", "Empty", "Dense", "Long labels"]
                : common,
        "Production native visual and source bindings.", ["visual." + kind])
    }
    for type in ["text", "decimal", "boolean", "number", "date", "record"] {
      add(
        "mini.action-input." + type, type.capitalized + " action input", "Mini apps",
        "sdk/src/runtime.ts", ["Default", "Disabled"],
        "The real SDK ActionForm validates the input before invoking its shared action.",
        ["action-input." + type])
    }
    for (id, title, source) in [
      ("table-update", "Review table mapping", "TableUpdateView.swift"),
      ("column-editor", "Edit table columns", "ContentViews.swift"),
      ("workflow-detail", "Workflow details", "WorkflowActivityView.swift"),
      ("automation-detail", "Automation details", "AutomationFocusedView.swift"),
      ("references", "References and backlinks", "ReferenceViews.swift"),
      ("history-search", "Conversation history search", "WorkbookView.swift"),
      ("chrome", "Headers, menus and typography", "WorkbookView.swift"),
    ] {
      add(
        "main." + id, title, "Main app", "Sources/SevraApp/" + source, ["Default"],
        "Mounted production surface; secondary menus, sheets and context actions remain interactive."
      )
    }
    return result
  }
  static func validate() throws {
    let all = stories
    try require(
      Set(charts) == Set(VisualChart.Style.allCases.map(\.rawValue)), "catalog_registry",
      "Chart styles differ from catalog coverage")
    try require(
      Set(work) == Set(WorkVisual.Style.allCases.map(\.rawValue)), "catalog_registry",
      "Work styles differ from catalog coverage")
    try require(
      Set(all.filter { $0.id.hasPrefix("home.component.") }.map { String($0.id.dropFirst(15)) })
        == SpaceDefinition.contentTypes.union(SpaceDefinition.sectionTypes), "catalog_registry",
      "Home/space component coverage differs"
    )
    try require(
      Set(all.filter { $0.id.hasPrefix("chat.field.") }.map { String($0.id.dropFirst(11)) })
        == Set(ConversationSurface.Field.Kind.allCases.map(\.rawValue)), "catalog_registry",
      "Chat field coverage differs")
    try require(
      Set(VisualDefinition.Kind.allCases.map(\.rawValue)) == [
        "chart", "image", "work", "diagram", "overview", "text",
      ], "catalog_registry", "Review visual family coverage"
    )
    try require(Set(all.map(\.id)).count == all.count, "catalog_registry", "Duplicate story ID.")
    try require(
      Set(all.filter { $0.id.hasPrefix("mini.node.") }.map { String($0.id.dropFirst(10)) })
        == NativeAppNode.types, "catalog_registry",
      "Native node coverage differs from the protocol.")
  }
}
