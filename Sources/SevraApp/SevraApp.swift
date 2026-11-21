import AppKit
import SevraAI
import SevraCore
import SevraDocumentUI
import SevraPreviewUI
import SevraProduct
import SevraTableUI
import SwiftUI
import UniformTypeIdentifiers

#if !SEVRA_UI_CATALOG
  @main struct SevraApp: App {
    init() {
      // macOS otherwise opens contact AutoFill over fields it takes for a person's title.
      UserDefaults.standard.register(defaults: ["NSAutoFillHeuristicsEnabled": false])
      if CommandLine.arguments.contains("--check-resources") {
        Task.detached {
          do {
            print(
              try await ProductAI.checkResources(
                validateMetal: !CommandLine.arguments.contains("--paths-only")
              ).json())
            exit(0)
          } catch {
            fputs(error.localizedDescription + "\n", stderr)
            exit(1)
          }
        }
      }
    }
    @NSApplicationDelegateAdaptor(DocumentDelegate.self) private var documentDelegate
    @AppStorage("appearance") private var appearance = "system"
    @FocusedValue(\.conversationWorkspace) private var workspace
    var body: some Scene {
      WindowGroup("Sevra", id: WorkspaceWindow.scene, for: String.self) { $path in
        WorkspaceWindow(path: $path, inbox: documentDelegate).readingFont(.body)
          .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
      }
      .defaultSize(width: 1200, height: 800)
      .commands {
        #if SEVRA_DISTRIBUTION
          CommandGroup(after: .appInfo) {
            CheckForUpdatesCommand(updates: documentDelegate.updates)
          }
        #endif
        CommandGroup(replacing: .appTermination) {
          Button(
            "Quit \(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Sevra")"
          ) {
            documentDelegate.quit()
          }.keyboardShortcut("q")
        }
        CommandMenu("Reading") {
          ReadingSizeCommands()
          Divider()
          if let workspace { ReadingWorkspaceCommands(state: workspace) }
        }
        ConversationCommands()
        WorkbookFileCommands()
        CommandMenu("Workbook") {
          Button("Add Native App…") { workspace?.importNativeApp() }.disabled(
            workspace?.workbook == nil)
          Button("Update Native App…") {
            if let workspace, case .space(let id) = workspace.route,
              let saved = workspace.spaces.first(where: { $0.id == id && $0.definition.app != nil })
            {
              workspace.importNativeApp(replacing: saved)
            }
          }.disabled(workspace?.workbook == nil)
          Divider()
          Button("Add Files…") { NotificationCenter.default.post(name: .sevraImport, object: nil) }
            .keyboardShortcut("i")
          Button("Search Workbook") {
            NotificationCenter.default.post(name: .sevraSearch, object: nil)
          }.keyboardShortcut("f", modifiers: [.command, .shift])
          Button("Drafts to Review") {
            NotificationCenter.default.post(name: .sevraReviews, object: nil)
          }
          Button("Workflow Runs") {
            NotificationCenter.default.post(name: .sevraActivity, object: nil)
          }.keyboardShortcut("y", modifiers: [.command, .shift])
          Divider()
          if let workspace {
            ReferenceCommandContent(state: workspace)
          } else {
            Button("Links in This Document") {}.disabled(true)
            Button("Where Is This Mentioned?") {}.disabled(true)
          }
          Divider()
          Button("Make Shareable Copy…") {
            NotificationCenter.default.post(name: .sevraExport, object: nil)
          }.keyboardShortcut("e", modifiers: [.command, .shift])
        }
      }
      Settings {
        #if SEVRA_DISTRIBUTION
          DistributionSettings(updates: documentDelegate.updates).readingFont(.body)
        #else
          ModelSettingsView().readingFont(.body)
        #endif
      }
    }
  }

#endif

/// New and Open belong to the app, so they work with no window open or another window in front.
private struct WorkbookFileCommands: Commands {
  @Environment(\.openWindow) private var openWindow
  private var files: WorkbookFiles { WorkbookFiles(openWindow: openWindow) }
  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("New Workbook…") { files.create() }.keyboardShortcut("n")
      Button("Open Workbook…") { files.open() }.keyboardShortcut("o")
    }
  }
}

/// Everything that starts from a file rather than from a window.
@MainActor struct WorkbookFiles {
  let openWindow: OpenWindowAction
  static func workbookSavePanel(title: String, name: String) -> NSSavePanel {
    let panel = AppHost.savePanel()
    panel.title = title
    panel.nameFieldStringValue = name
    panel.allowedContentTypes = [UTType(filenameExtension: "sevra", conformingTo: .package)]
      .compactMap { $0 }
    panel.canCreateDirectories = true
    return panel
  }
  func create() {
    let panel = Self.workbookSavePanel(title: "Create a workbook", name: "Untitled")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let title = url.deletingPathExtension().lastPathComponent
    build(url) { _ = try Workbook.create(at: url, title: title) }
  }
  func open() {
    let panel = AppHost.openPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.treatsFilePackagesAsDirectories = false
    if panel.runModal() == .OK, let url = panel.url { open(url) }
  }
  func open(_ url: URL) {
    guard url.pathExtension == "sevraz" else {
      show(url)
      return
    }
    let panel = Self.workbookSavePanel(
      title: "Open portable workbook", name: url.deletingPathExtension().lastPathComponent)
    guard panel.runModal() == .OK, let target = panel.url else { return }
    build(target) { _ = try Workbook.openArchive(url, at: target) }
  }
  /// Brings an open workbook forward, or opens a window for it. Either way the start page closes,
  /// and a workbook that is gone is reported before any window opens.
  func show(_ url: URL) {
    if let owner = WorkbookWindowRegistry.owner(of: url.path) {
      WorkbookWindowRegistry.bringForward(owner)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
      RecentWorkbooks.forget(url.path)
      Self.report(
        "Can’t find “\(url.deletingPathExtension().lastPathComponent)”",
        "It is no longer in \((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath). It may have been moved, renamed or deleted."
      )
      return
    }
    openWindow(value: url.path)
  }
  /// On the window in front when there is one, so it reads as that window's answer.
  static func report(_ title: String, _ message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    if let window = NSApp.keyWindow, window.isVisible, window.attachedSheet == nil {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }
  func demo() {
    let panel = Self.workbookSavePanel(title: "Save example workbook", name: "Willow Workshop")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    build(url) { try Demo.create(at: url) }
  }
  private func build(_ url: URL, _ work: @escaping @Sendable () throws -> Void) {
    Task {
      do {
        try await Task.detached(priority: .userInitiated, operation: work).value
        show(url)
      } catch {
        Self.report("Cannot open workbook", error.localizedDescription)
      }
    }
  }
}

/// The workbooks listed on the start page, newest first.
enum RecentWorkbooks {
  static let key = "recentWorkbooks"
  static func add(_ path: String) {
    let previous = UserDefaults.standard.stringArray(forKey: key) ?? []
    UserDefaults.standard.set(Array(([path] + previous.filter { $0 != path }).prefix(10)), forKey: key)
  }
  static func forget(_ path: String) {
    let previous = UserDefaults.standard.stringArray(forKey: key) ?? []
    guard previous.contains(path) else { return }
    UserDefaults.standard.set(previous.filter { $0 != path }, forKey: key)
  }
}

@MainActor final class DocumentDelegate: NSObject, NSApplicationDelegate, ObservableObject {
  @Published var pending: [URL] = []
  #if SEVRA_DISTRIBUTION
    let updates = AppUpdates()
  #endif
  /// From the latest window. It outlives that window, so a file opened from Finder after the last
  /// one closed still gets a window. Until the first window appears, files wait in `pending`.
  var files: WorkbookFiles?
  private var quitting = false
  func applicationDidFinishLaunching(_ notification: Notification) {
    #if SEVRA_DISTRIBUTION
      if !CommandLine.arguments.contains("--check-resources") { updates.start() }
    #endif
    NativeAutomationHost.shared.start()
    let events = NSAppleEventManager.shared()
    events.setEventHandler(
      self, andSelector: #selector(quitEvent(_:reply:)),
      forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEQuitApplication))
    // Once launched, files from Finder and `open` come straight here. SwiftUI's own handling also
    // made an empty window for each, which stayed when the workbook was already open. The file
    // that launched the app still goes through SwiftUI, which makes the first window for it.
    events.setEventHandler(
      self, andSelector: #selector(openEvent(_:reply:)),
      forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEOpenDocuments))
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard DocumentDraftScope.flushAll() else { return .terminateCancel }
    WorkbookWindowRegistry.quitting = true
    Task {
      let finished = await finishWork()
      if !finished { WorkbookWindowRegistry.quitting = false }
      sender.reply(toApplicationShouldTerminate: finished)
    }
    return .terminateLater
  }
  /// AppKit ignores `terminate` while a sheet is open, from the menu, the Dock and logout alike,
  /// and SwiftUI puts back a sheet closed from outside it. So with one open the same saving runs
  /// here and the process ends itself; a failed save leaves the sheet as it was.
  func quit() {
    guard NSApp.windows.contains(where: { $0.attachedSheet != nil }) else {
      NSApp.terminate(nil)
      return
    }
    guard !quitting, DocumentDraftScope.flushAll() else { return }
    quitting = true
    WorkbookWindowRegistry.quitting = true
    Task {
      if await finishWork() {
        UserDefaults.standard.synchronize()
        exit(0)
      }
      quitting = false
      WorkbookWindowRegistry.quitting = false
    }
  }
  @objc private func quitEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
    quit()
  }
  @objc private func openEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
    guard let files = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
    let urls =
      files.numberOfItems > 0
      ? (1...files.numberOfItems).compactMap { files.atIndex($0)?.fileURLValue }
      : [files.fileURLValue].compactMap { $0 }
    application(NSApp, open: urls)
  }
  private func finishWork() async -> Bool {
    NativeAutomationHost.shared.beginTermination()
    await NativeAutomationHost.shared.yieldForInteractive()
    let saved = await ConversationSession.flushAll()
    let formsSaved = await FormDraftScope.flushAll()
    let clarificationsSaved = await WorkflowClarificationScope.flushAll()
    await SpaceNavigationSession.flushAll()
    let complete = saved && formsSaved && clarificationsSaved && DocumentDraftScope.flushAll()
    if complete {
      await NativeAutomationHost.shared.stop()
      // A reply in progress holds the model, and unload declines until it stops.
      NotificationCenter.default.post(name: .sevraStopping, object: nil)
      await ProductAI.shared.unload(waitingSeconds: 5)
    } else {
      NativeAutomationHost.shared.cancelTermination()
    }
    return complete
  }
  func applicationWillTerminate(_ notification: Notification) {
    NotificationCenter.default.post(name: .sevraStopping, object: nil)
  }
  func application(_ application: NSApplication, open urls: [URL]) {
    if let files { urls.forEach(files.open) } else { pending += urls }
  }
}
extension Notification.Name {
  static let sevraStopping = Notification.Name("sevraStopping")
  static let sevraImport = Notification.Name("sevraImport"),
    sevraSearch = Notification.Name("sevraSearch"),
    sevraReviews = Notification.Name("sevraReviews"),
    sevraActivity = Notification.Name("sevraActivity"),
    sevraExport = Notification.Name("sevraExport")
}
/// A workbook, or the start page when `path` is nil. The start page closes once a workbook is in
/// front, and comes back when the last workbook window closes.
struct WorkspaceWindow: View {
  static let scene = "workbook"
  @Binding var path: String?
  @ObservedObject var inbox: DocumentDelegate
  @StateObject private var state = WorkspaceState()
  @Environment(\.openWindow) private var openWindow
  @State private var welcomeError: String?
  /// Cleared as the window closes, or the window would keep itself alive through its own views.
  @State private var ownWindow: NSWindow?
  /// Set once the window lost its claim or closed. SwiftUI keeps calling the accessor for a
  /// closed window, and it must not take the window back.
  @State private var retired = false
  /// The workbook opens only once this window holds it, so a window that loses the claim never
  /// opens a second connection.
  @State private var claimed: String?
  @State private var closeGuard: DocumentCloseGuard?
  @State private var startingFiles: (destination: String, files: [URL])?
  var body: some View {
    Group {
      if state.workbook != nil { WorkbookView(state: state) } else { welcome }
    }
    .frame(minWidth: 820, minHeight: 600)
    .background(
      WindowAccessor { window in
        guard !retired else { return }
        if ownWindow !== window { ownWindow = window }
        state.readingWindow = window
        if let window, let path, claimed != path {
          guard WorkbookWindowRegistry.claim(path, by: window) else {
            retired = true
            window.close()
            return
          }
          claimed = path
        }
        if let window {
          if closeGuard == nil {
            closeGuard = DocumentCloseGuard(
              asyncFlush: { [weak state] in await state?.saveBeforeClosing() ?? true },
              closed: { [weak state] window in
                let heldWorkbook = state?.workbook != nil
                state?.close()
                WorkbookWindowRegistry.release(window)
                retired = true
                ownWindow = nil
                if heldWorkbook { reopenStartIfLast() }
              })
          }
          closeGuard?.attach(to: window)
          WorkbookWindowRegistry.showsStart(window, path == nil && state.workbook == nil)
          state.documentDrafts.revealFailure = { [weak window] in
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
          }
          state.conversationSession.revealFailure = state.documentDrafts.revealFailure
          state.formDrafts.revealFailure = state.documentDrafts.revealFailure
        }
        window?.representedURL = state.workbook?.url
        window?.title = state.workbook?.title ?? "Sevra"
      }
    )
    .onAppear { inbox.files = files }
    .task(id: claimed) {
      if let path = claimed {
        do {
          try await state.open(URL(fileURLWithPath: path))
          guard !Task.isCancelled else { return }
          WorkbookWindowRegistry.closeStarts(except: ownWindow)
          RecentWorkbooks.add(path)
          if let intake = startingFiles, intake.destination == path {
            startingFiles = nil
            state.importFiles(intake.files)
          }
        } catch {
          guard !Task.isCancelled else { return }
          openFailed(path, error)
        }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .sevraStopping)) { _ in
      state.endInteraction()
    }
    .onReceive(inbox.$pending) { pending in
      guard !pending.isEmpty else { return }
      DispatchQueue.main.async {
        var urls = inbox.pending
        inbox.pending = []
        // A cold start already made this window, so the first workbook needs no second one.
        if path == nil, state.workbook == nil,
          let first = urls.firstIndex(where: { $0.pathExtension != "sevraz" })
        {
          path = urls.remove(at: first).path
        }
        urls.forEach(files.open)
      }
    }
    .alert(
      "Cannot open workbook",
      isPresented: Binding(get: { welcomeError != nil }, set: { if !$0 { welcomeError = nil } })
    ) {
      Button("OK") { welcomeError = nil }
    } message: {
      Text(welcomeError ?? "")
    }
    .onReceive(NotificationCenter.default.publisher(for: .sevraImport)) { _ in
      if isKey { state.importPanel() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .sevraOpenEvidence)) { event in
      if isKey, let id = event.object as? String { state.navigate(.item(id)) }
    }
    .onReceive(NotificationCenter.default.publisher(for: .sevraSearch)) { _ in
      if isKey { state.navigate(.search) }
    }
    .onReceive(NotificationCenter.default.publisher(for: .sevraReviews)) { _ in
      if isKey { state.navigate(.reviews) }
    }
    .onReceive(NotificationCenter.default.publisher(for: .sevraActivity)) { _ in
      if isKey { state.navigate(.activity) }
    }
    .onReceive(NotificationCenter.default.publisher(for: .sevraExport)) { _ in
      if isKey { state.exportPanel() }
    }
  }
  var isKey: Bool { ownWindow != nil && NSApp.keyWindow === ownWindow }
  private var files: WorkbookFiles { WorkbookFiles(openWindow: openWindow) }
  var welcome: some View {
    WelcomeView(
      startFromFiles: startFromFiles, open: { files.open() }, create: { files.create() },
      demo: { files.demo() }, openRecent: { files.show(URL(fileURLWithPath: $0)) })
  }
  /// A window that cannot open its workbook gives it up. With other windows open it closes and the
  /// error shows on the one in front; otherwise it becomes the start page and shows the error there.
  private func openFailed(_ failed: String, _ error: Error) {
    let title = "Can’t open “\(URL(fileURLWithPath: failed).deletingPathExtension().lastPathComponent)”"
    guard let window = ownWindow else {
      welcomeError = error.localizedDescription
      return
    }
    WorkbookWindowRegistry.release(window)
    if WorkbookWindowRegistry.hasWindows(besides: window) {
      retired = true
      window.close()
      WorkbookFiles.report(title, error.localizedDescription)
    } else {
      claimed = nil
      path = nil
      welcomeError = error.localizedDescription
    }
  }
  /// Closing the last workbook leaves the start page, never an app with no window. Quitting does not.
  private func reopenStartIfLast() {
    let openWindow = openWindow
    DispatchQueue.main.async {
      if WorkbookWindowRegistry.shouldOpenStart() { openWindow(id: Self.scene) }
    }
  }
  func startFromFiles() {
    guard let owner = ownWindow, owner.isVisible else { return }
    let input = AppHost.openPanel()
    input.title = "Start a workbook from your files"
    input.canChooseFiles = true
    input.canChooseDirectories = false
    input.treatsFilePackagesAsDirectories = true
    input.allowsMultipleSelection = true
    guard input.runModal() == .OK, ownWindow === owner, owner.isVisible,
      !input.urls.isEmpty
    else { return }
    saveWorkbook(from: input.urls, owner: owner)
  }
  private func saveWorkbook(from files: [URL], owner: NSWindow) {
    guard ownWindow === owner, owner.isVisible else { return }
    let destination = WorkbookFiles.workbookSavePanel(
      title: "Save your new workbook", name: files[0].deletingPathExtension().lastPathComponent)
    guard destination.runModal() == .OK, ownWindow === owner, owner.isVisible,
      let url = destination.url
    else { return }
    let title = url.deletingPathExtension().lastPathComponent
    Task {
      do {
        _ = try await Task.detached(priority: .userInitiated) {
          try Workbook.create(at: url, title: title)
        }.value
        startingFiles = (url.path, files)
        path = url.path
      } catch { welcomeError = error.localizedDescription }
    }
  }
}

struct WindowAccessor: NSViewRepresentable {
  let changed: (NSWindow?) -> Void
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async { changed(view.window) }
    return view
  }
  func updateNSView(_ view: NSView, context: Context) {
    DispatchQueue.main.async { changed(view.window) }
  }
}
