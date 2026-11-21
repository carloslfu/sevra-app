import AppKit
import SevraAppUI
import SevraCore
import SevraPreviewUI
import SevraTableUI
import SwiftUI

@main struct CatalogApp: App {
  @NSApplicationDelegateAdaptor(CatalogDelegate.self) var delegate
  var body: some Scene {
    WindowGroup("Sevra UI Catalog") { CatalogBrowser().readingFont(.body) }
      .defaultSize(width: 1440, height: 940)
    Settings { ModelSettingsView() }
      .commands {
        ConversationCommands()
        CommandMenu("Reading") { ReadingSizeCommands() }
      }
  }
}
@MainActor final class CatalogDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    guard Bundle.main.bundleIdentifier == "com.sevra.ui-catalog" else {
      fputs("Run the packaged Sevra UI Catalog.app. Unbundled launch refused.\n", stderr)
      exit(2)
    }
    NSApp.setActivationPolicy(.regular)
    if CatalogCLI.isBatch { Task { await CatalogCLI.run() } }
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    !CatalogCLI.isBatch
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task {
      for session in CatalogSession.live.allObjects {
        CatalogCapture.close(session)
        await session.tearDown()
      }
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
  func applicationWillTerminate(_ notification: Notification) {
    try? FileManager.default.removeItem(at: AppHost.root)
  }
}

@MainActor final class CatalogBrowserModel: ObservableObject {
  @Published var selected =
    CommandLine.arguments.drop(while: { $0 != "--story" }).dropFirst().first
    ?? "composition.supplier"
  @Published var variant = "Default"
  @Published var query = ""
  @Published var group = "All surfaces"
  @Published var level = "All examples"
  @Published var label = ""
  @Published var rows = 6
  @Published var width = 900.0
  @Published var height = 640.0
  @Published var dark = false
  @Published var reading = 1.0
  @Published var spacing = 16
  @Published var columns = 2
  @Published var vertical = false
  @Published var session: CatalogSession?
  @Published var inspector = true
  @Published var error: String?
  var task: Task<Void, Never>?
  init() {
    guard !CatalogCLI.isBatch else { return }
    do { apply(try CatalogCLI.configuration()) } catch { self.error = error.localizedDescription }
  }
  func apply(_ config: CatalogConfiguration) {
    query = ""
    group = "All surfaces"
    level = "All examples"
    selected = config.story
    variant = config.variant
    label = config.label
    rows = config.rows
    width = config.width
    height = config.height
    dark = config.dark
    reading = config.readingScale
    spacing = config.spacing
    columns = config.columns
    vertical = config.vertical
  }
  var story: CatalogStory {
    CatalogRegistry.stories.first { $0.id == selected } ?? CatalogRegistry.stories[0]
  }
  func load() {
    do { try configuration.validate() } catch {
      self.error = error.localizedDescription
      return
    }
    error = nil
    let previousTask = task
    let previous = session
    previousTask?.cancel()
    let next = CatalogSession(
      story: story, variant: variant, label: label, count: rows, spacing: spacing, columns: columns,
      vertical: vertical)
    next.defaults.set(reading, forKey: ReadingStyle.preference)
    session = next
    task = Task {
      await previousTask?.value
      if let previous {
        CatalogCapture.close(previous)
        await previous.tearDown()
      }
      guard !Task.isCancelled else { return }
      await next.prepare()
    }
  }
  var configuration: CatalogConfiguration {
    .init(
      story: selected, variant: variant, label: label, rows: rows, width: width, height: height,
      dark: dark, readingScale: reading, spacing: spacing, columns: columns, vertical: vertical)
  }
}
struct CatalogBrowser: View {
  @StateObject var model = CatalogBrowserModel()
  @State var selectionTab = "Inputs"
  @State var showingCoverage = false
  @State var editingConfiguration = false
  @State var configurationText = ""
  @State var configurationError: String?
  @State var availableWidth = 1440.0
  var filtered: [CatalogStory] {
    CatalogRegistry.stories.filter {
      (model.group == "All surfaces" || $0.group == model.group)
        && (model.level == "All examples" || $0.level == model.level)
        && (model.query.isEmpty
          || ($0.title + " " + $0.id + " " + $0.source + " "
            + $0.capabilities.joined(separator: " ")).localizedCaseInsensitiveContains(
              model.query))
    }
  }
  var body: some View {
    HSplitView {
      if availableWidth >= 900 {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            ObserverMark().fill(.primary).frame(width: 25, height: 25)
            Text("UI Catalog").font(.title3.weight(.semibold))
          }.padding(.top, 16)
          TextField("Find a view or capability", text: $model.query).textFieldStyle(.roundedBorder)
          Picker("Surface", selection: $model.group) {
            Text("All surfaces").tag("All surfaces")
            ForEach(CatalogRegistry.groups, id: \.self) { Text($0).tag($0) }
          }.labelsHidden()
          Picker("Examples", selection: $model.level) {
            ForEach(["All examples", "Components", "States", "Flows"], id: \.self) {
              Text($0).tag($0)
            }
          }.labelsHidden()
          List(selection: $model.selected) {
            ForEach(CatalogRegistry.groups, id: \.self) { group in
              let stories = filtered.filter { $0.group == group }
              if !stories.isEmpty {
                Section(group) {
                  ForEach(stories) { story in Text(story.title).tag(story.id).help(story.id) }
                }
              }
            }
          }.listStyle(.sidebar)
          Text("\(filtered.count) examples · synthetic data").font(.caption).foregroundStyle(
            .secondary
          ).padding(.bottom, 12)
        }.padding(.horizontal, 12).frame(minWidth: 220, idealWidth: 250, maxWidth: 310)
      }
      VStack(spacing: 0) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 5) {
            Text(model.story.group).font(.caption).foregroundStyle(.secondary)
            Text("Synthetic data · scripted services").font(.caption2).foregroundStyle(.secondary)
            Text(model.story.title).font(.title2.weight(.medium))
            Text(model.story.id).font(.caption.monospaced()).foregroundStyle(.secondary)
          }
          Spacer()
          Button("Coverage") { showingCoverage = true }
          Button("Reset", systemImage: "arrow.counterclockwise") { model.load() }
          if let session = model.session { CatalogReplayButton(session: session) }
          Button {
            model.inspector.toggle()
          } label: {
            Image(systemName: "sidebar.right")
          }.help("Show inspector")
        }.padding(20)
        Divider()
        HStack {
          Picker("State", selection: $model.variant) {
            ForEach(model.story.variants, id: \.self) { Text($0).tag($0) }
          }.frame(maxWidth: 230)
          Picker("Canvas", selection: $model.width) {
            Text("Compact · 520").tag(520.0)
            Text("Standard · 900").tag(900.0)
            Text("Wide · 1200").tag(1200.0)
          }.frame(maxWidth: 220)
          Toggle("Dark", isOn: $model.dark).toggleStyle(.switch).controlSize(.small)
          Spacer()
          Button("Capture") {
            if let s = model.session {
              s.runUI {
                do {
                  _ = try await CatalogCapture.capture(s, configuration: model.configuration)
                } catch { if model.session === s { model.error = error.localizedDescription } }
              }
            }
          }
          Button("Window") {
            if let s = model.session {
              CatalogCapture.openWindow(
                s, width: model.width, height: model.height, dark: model.dark)
            }
          }
        }.padding(.horizontal, 20).padding(.vertical, 10)
        Divider()
        if let session = model.session {
          HSplitView {
            ScrollView([.horizontal, .vertical]) {
              CatalogStage(session: session, width: model.width, height: model.height)
                .defaultAppStorage(session.defaults).readingFont(.body).preferredColorScheme(
                  model.dark ? .dark : .light
                )
                .background(Color(nsColor: .windowBackgroundColor)).padding(24)
            }.background(Color(nsColor: .underPageBackgroundColor))
            if model.inspector && availableWidth >= 1180 {
              inspector(session).frame(minWidth: 240, idealWidth: 285, maxWidth: 360)
            }
          }
        }
        if let error = model.error { Text(error).foregroundStyle(.red).padding(8) }
      }.frame(minWidth: 620)
    }
    .background(
      GeometryReader { geometry in
        Color.clear.onAppear { availableWidth = geometry.size.width }
          .onChange(of: geometry.size.width) { _, width in availableWidth = width }
      }
    )
    .onAppear { if !CatalogCLI.isBatch { model.load() } }
    .onChange(of: model.selected) { _, _ in
      if model.session?.story.id != model.selected {
        model.variant = "Default"
        model.load()
      }
    }
    .onChange(of: model.variant) { _, _ in
      if model.session?.variant != model.variant { model.load() }
    }
    .onChange(of: model.reading) { _, value in
      model.session?.defaults.set(value, forKey: ReadingStyle.preference)
    }
    .onDisappear {
      let task = model.task
      let session = model.session
      task?.cancel()
      Task {
        await task?.value
        if let session {
          CatalogCapture.close(session)
          await session.tearDown()
        }
      }
    }
    .sheet(isPresented: $showingCoverage) {
      CatalogCoverageView(session: model.session, configuration: model.configuration)
    }
    .sheet(isPresented: $editingConfiguration) {
      VStack(alignment: .leading, spacing: 14) {
        Text("Reproduce an example").font(.title2)
        Text(
          "Paste a saved catalog configuration. Only declared stories and bounded inputs are accepted."
        ).foregroundStyle(.secondary)
        TextEditor(text: $configurationText).font(.body.monospaced()).frame(
          minWidth: 500, minHeight: 260)
        if let configurationError { Text(configurationError).foregroundStyle(.red) }
        HStack {
          Button("Cancel") { editingConfiguration = false }
          Spacer()
          Button("Apply configuration") {
            do {
              let config = try JSONDecoder().decode(
                CatalogConfiguration.self, from: Data(configurationText.utf8))
              try config.validate()
              model.apply(config)
              editingConfiguration = false
              model.load()
            } catch { configurationError = error.localizedDescription }
          }.keyboardShortcut(.defaultAction)
        }
      }.padding(24)
    }
  }
  func inspector(_ session: CatalogSession) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Picker("Inspector", selection: $selectionTab) {
        ForEach(["Inputs", "Behavior", "Implementation"], id: \.self) { Text($0).tag($0) }
      }.pickerStyle(.segmented)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if selectionTab == "Inputs" {
            Text("Compose the example").font(.headline)
            TextField("Label override", text: $model.label)
            Stepper("Rows: \(model.rows)", value: $model.rows, in: 0...100)
            if model.story.group == "Mini apps" {
              Stepper("Layout gap: \(model.spacing)", value: $model.spacing, in: 0...48)
              Stepper("Grid columns: \(model.columns)", value: $model.columns, in: 1...4)
              Toggle("Vertical split", isOn: $model.vertical)
            }
            Picker("Reading size", selection: $model.reading) {
              ForEach([1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { Text("\(Int($0*100))%").tag($0) }
            }
            Slider(value: $model.height, in: 360...1000) { Text("Canvas height") }
            Text(
              "Requested: \(Int(model.width)) × \(Int(model.height)) points. Native minimums apply."
            ).font(.caption.monospaced())
            Button("Apply inputs") { model.load() }.buttonStyle(.borderedProminent)
            Button("Copy configuration") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(
                (try? model.configuration.json()) ?? "", forType: .string)
            }
            Button("Load configuration…") {
              configurationError = nil
              configurationText = (try? model.configuration.json()) ?? ""
              editingConfiguration = true
            }
            Text(model.story.note).foregroundStyle(.secondary)
            if let failure = session.validationFailure { Text(failure).foregroundStyle(.red) }
          } else if selectionTab == "Behavior" {
            CatalogBehavior(session: session, configuration: model.configuration)
          } else {
            Text("Production renderer").font(.headline)
            Text(model.story.source).font(.caption.monospaced()).textSelection(.enabled)
            Text("Readiness").font(.headline)
            Text(model.story.readiness).font(.caption)
            Text(model.story.statePolicy).font(.caption).foregroundStyle(.secondary)
            Text("Capabilities").font(.headline)
            ForEach(model.story.capabilities, id: \.self) { Text($0).font(.caption.monospaced()) }
            if let app = session.app {
              Button("Copy SDK recipe") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.definition.app!.source, forType: .string)
              }
            } else if let visual = session.visual {
              Button("Copy visual recipe") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                  (try? encoded(visual).json()) ?? "", forType: .string)
              }
            }
            Text(
              "Registered does not mean visually reviewed. Capture and interaction evidence are recorded independently."
            ).foregroundStyle(.secondary)
            Text(
              "Model, file selection, voice and scheduling are controlled services. Native UI, workbook storage and app workers are real."
            ).foregroundStyle(.secondary)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }.padding(16)
  }
}
struct CatalogReplayButton: View {
  @ObservedObject var session: CatalogSession
  var body: some View {
    Button("Replay", systemImage: "play") { session.runUI { await session.replay() } }
      .disabled(!session.ready || session.replaying || session.step >= session.flowSteps.count)
  }
}
struct CatalogBehavior: View {
  @ObservedObject var session: CatalogSession
  let configuration: CatalogConfiguration
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(session.ready ? "Ready" : "Preparing").font(.headline)
      Text("Step \(session.step) of \(session.flowSteps.count)").font(.caption)
      ForEach(Array(session.flowSteps.enumerated()), id: \.offset) { index, title in
        Label(
          title,
          systemImage: index < session.step
            ? "checkmark.circle.fill" : index == session.step ? "circle.inset.filled" : "circle"
        ).font(.caption).foregroundStyle(index < session.step ? Color.green : Color.secondary)
      }
      Button("Advance flow") { session.runUI { await session.replay() } }.disabled(
        !session.ready || session.step >= session.flowSteps.count)
      Text(session.interactionChecked ? "Interaction checked" : "Interaction not checked").font(
        .caption
      ).foregroundStyle(.secondary)
      TextField("Visual review note", text: $session.visualReviewNote)
      Button("Record visual review") {
        session.visualReviewed = true
        session.reviewedConfiguration = try? configuration.json()
        session.reviewedRevision = try? session.book?.revision()
        session.events.append("Visual review: " + session.visualReviewNote)
      }.disabled(
        !session.rendered || !session.ready || session.failure != nil
          || session.visualReviewNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      Button("Check this interaction") {
        session.runUI {
          do {
            try await CatalogChecks.verify(session)
            session.interactionChecked = true
          } catch { session.events.append("Check failed: " + error.localizedDescription) }
        }
      }.disabled(!CatalogChecks.stories.contains(session.story.id))
      Button("Revoke app access") {
        if let a = session.app, let b = session.book {
          session.state?.nativeAppSession(a, book: b).revoke()
          session.events.append("Grant revoked")
        }
      }.disabled(session.app == nil)
      if session.story.id == "mini.state.starting" {
        Button("Fail pending transport") { Task { await session.transport.finish() } }
        Text("Reset cancels pending work and starts a fresh transport.").font(.caption)
          .foregroundStyle(.secondary)
      }
      Button("Restore saved input") { session.state?.refresh() }
      ForEach(Array(session.events.enumerated()), id: \.offset) { _, event in
        Text(event).font(.caption).textSelection(.enabled)
      }
    }
  }
}
struct CatalogStage: View {
  @ObservedObject var session: CatalogSession
  var width: Double? = nil
  var height: Double? = nil
  @ViewBuilder var body: some View {
    Group {
      if let failure = session.failure {
        ContentUnavailableView(
          "Example unavailable", systemImage: "exclamationmark.triangle", description: Text(failure)
        )
      } else if let state = session.state, session.ready {
        CatalogProductionView(session: session, state: state).disabled(
          session.variant == "Disabled"
        )
        .onAppear { session.rendered = true }
      } else {
        ProgressView("Preparing synthetic workbook…")
      }
    }.frame(
      width: width.map { CGFloat(max($0, session.minimumCanvasWidth)) },
      height: height.map { CGFloat($0) })
  }
}
struct CatalogProductionView: View {
  @ObservedObject var session: CatalogSession
  @ObservedObject var state: WorkspaceState
  @State private var automaticUpdateChecks = false
  @ViewBuilder var body: some View {
    let id = session.story.id
    if id == "main.welcome" {
      WelcomeView(
        startFromFiles: { state.importPanel() },
        open: { state.error = "Catalog open is restricted to synthetic fixtures." },
        create: { state.route = .space("home") }, demo: { state.route = .table(session.table!.id) },
        openRecent: { _ in
          state.error = "Synthetic recent file is missing. Create an example instead."
        }, defaults: session.defaults)
    } else if id == "main.opening" {
      OpeningWorkbookView(
        name: session.variant == "Long labels"
          ? "Quarterly supplier comparison for the north and south warehouses, revised" : "Willow Workshop"
      ) { state.error = "Cancel closes the window in the app." }
    } else if id == "main.settings" {
      ModelSettingsView(
        initialState: session.variant,
        automaticUpdateChecks: session.variant == "Software updates" ? $automaticUpdateChecks : nil)
    } else if id == "main.column-editor", let table = session.table {
      ColumnEditor(table: table, state: state)
    } else if id == "main.navigation" {
      SpacePickerView(state: state, dismiss: {})
    } else if id == "home.layout", let space = state.spaces.first(where: { $0.id == "home" }) {
      SpaceLayoutEditor(space: space, state: state)
    } else if id == "main.intake", let item = session.fileItems["csv"] {
      IntakeView(
        state: state,
        prompt: .init(choices: [
          .init(sourceID: item, title: "Quotes.csv", supportsTable: true, supportsUpdate: true)
        ]))
    } else if id.hasPrefix("home.component."), let c = session.component {
      ScrollView { NativeComponent(component: c, state: state).padding(26) }
    } else if id == "main.voice" {
      VStack(alignment: .leading, spacing: 20) {
        VoiceButton(speech: state.speech, action: { state.voice() })
        VoiceStatus(speech: state.speech)
        Text(state.prompt)
      }.padding(30)
    } else {
      WorkbookView(state: state)
    }
  }
}
