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
  @FocusedValue(\.conversationWorkspace) private var workspace
  @ObservedObject private var recents = RecentWorkbookList.shared
  private var files: WorkbookFiles { WorkbookFiles(openWindow: openWindow) }
  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("New Workbook") { files.startPage() }.keyboardShortcut("n")
      Button("New Workbook in Folder…") { files.create() }
        .keyboardShortcut("n", modifiers: [.command, .shift])
      Button("Open Workbook…") { files.open() }.keyboardShortcut("o")
      Menu("Open Recent") {
        RecentWorkbookButtons(paths: recents.paths, files: files)
      }.disabled(recents.paths.isEmpty)
      Divider()
      Button("Rename Workbook…") {
        if let workspace, let book = workspace.workbook {
          workspace.workbookRename = .init(title: book.title)
        }
      }.disabled(workspace?.workbook == nil || workspace?.renameWorkbook == nil)
      Button("Show Workbook in Finder") {
        if let url = workspace?.workbook?.url {
          NSWorkspace.shared.activateFileViewerSelecting([url])
        }
      }.disabled(workspace?.workbook == nil)
    }
  }
}

/// One menu item per recent workbook, named as its file is.
struct RecentWorkbookButtons: View {
  let paths: [String]
  let files: WorkbookFiles
  var body: some View {
    ForEach(paths, id: \.self) { path in
      Button(WorkbookLibrary.displayName(path)) {
        files.show(URL(fileURLWithPath: path))
      }
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
  /// A new workbook starts as the start page, which makes the workbook on the first message or
  /// file. One start page is enough, so an open one comes forward.
  func startPage() {
    if let start = WorkbookWindowRegistry.start {
      if start.isMiniaturized { start.deminiaturize(nil) }
      start.makeKeyAndOrderFront(nil)
    } else {
      openWindow(id: WorkspaceWindow.scene)
    }
  }
  /// A free place in the workbooks folder, or nil after saying why there is none.
  static func newURL(_ name: String) -> URL? {
    do { return try WorkbookLibrary.newURL(name) } catch {
      report("Cannot create a workbook", error.localizedDescription)
      return nil
    }
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
    // A portable workbook unpacks into the workbooks folder under its own name.
    guard let target = Self.newURL(url.deletingPathExtension().lastPathComponent) else { return }
    build(target) { _ = try Workbook.openArchive(url, at: target) }
  }
  /// Brings an open workbook forward, or opens a window for it. Either way the start page closes,
  /// and a workbook that is gone is reported before any window opens.
  func show(_ url: URL) {
    if let owner = WorkbookWindowRegistry.owner(of: WorkbookWindowRegistry.canonical(url.path)) {
      WorkbookWindowRegistry.bringForward(owner)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let url = Self.fileNamedLikeTitle(url)
    let path = WorkbookWindowRegistry.canonical(url.path)
    guard FileManager.default.fileExists(atPath: path) else {
      RecentWorkbooks.forget(url.path)
      Self.report(
        "Can’t find “\(url.deletingPathExtension().lastPathComponent)”",
        "It is no longer in \((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath). It may have been moved, renamed or deleted."
      )
      return
    }
    openWindow(value: path)
  }
  /// A workbook Sevra named while it was open keeps its old file name until it opens again,
  /// since nothing may hold it while it moves. Here nothing does, so the file takes the name.
  static func fileNamedLikeTitle(_ url: URL) -> URL {
    guard WorkbookWindowRegistry.owner(of: WorkbookWindowRegistry.canonical(url.path)) == nil,
      FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path),
      let moved = try? WorkbookLibrary.fileMatchingAutomaticTitle(url)
    else { return url }
    let defaults = UserDefaults.standard
    for old in Set([url.path, WorkbookWindowRegistry.canonical(url.path)]) {
      RecentWorkbooks.forget(old)
      if let chat = defaults.string(forKey: "lastConversation:" + old) {
        defaults.removeObject(forKey: "lastConversation:" + old)
        defaults.set(chat, forKey: "lastConversation:" + moved.path)
      }
    }
    return moved
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
    guard let url = Self.newURL("Willow Workshop") else { return }
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

/// The recent workbooks as the menus show them, kept current as workbooks open and close.
@MainActor final class RecentWorkbookList: ObservableObject {
  static let shared = RecentWorkbookList()
  @Published private(set) var paths = UserDefaults.standard.stringArray(
    forKey: RecentWorkbooks.key) ?? []
  func reload() {
    let saved = UserDefaults.standard.stringArray(forKey: RecentWorkbooks.key) ?? []
    if saved != paths { paths = saved }
  }
}

/// The workbooks listed on the start page and in the menus, newest first.
@MainActor enum RecentWorkbooks {
  static let key = "recentWorkbooks"
  /// Another spelling of the same workbook replaces its older entry rather than adding a second.
  static func add(_ path: String) {
    let path = WorkbookWindowRegistry.canonical(path)
    let previous = UserDefaults.standard.stringArray(forKey: key) ?? []
    let others = previous.filter { WorkbookWindowRegistry.canonical($0) != path }
    UserDefaults.standard.set(Array(([path] + others).prefix(10)), forKey: key)
    RecentWorkbookList.shared.reload()
  }
  static func forget(_ path: String) {
    let previous = UserDefaults.standard.stringArray(forKey: key) ?? []
    let canonical = WorkbookWindowRegistry.canonical(path)
    let kept = previous.filter { $0 != path && $0 != canonical }
    guard kept.count != previous.count else { return }
    UserDefaults.standard.set(kept, forKey: key)
    RecentWorkbookList.shared.reload()
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
    // The local engine starts with the first window, so a first message does not wait for it.
    if !CommandLine.arguments.contains("--check-resources") {
      WorkspaceState.prewarmLocalAI()
      // After memory pressure released it, the engine starts again once pressure eases, but only
      // while the owner is in the app.
      if AppHost.allowsBackgroundServices {
        let ai = AppHost.ai
        Task { await ai.setReloadHost { [weak self] in await self?.reloadFolder() } }
      }
    }
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
  /// The models folder while the owner is in the app, for a reload after memory pressure.
  private func reloadFolder() -> URL? {
    guard NSApp.isActive, !quitting, !WorkbookWindowRegistry.quitting else { return nil }
    return UserDefaults.standard.string(forKey: ProductAI.preferenceKey).map {
      URL(fileURLWithPath: $0)
    } ?? ProductAI.defaultDirectory
  }
  /// Coming back after the idle timer released the engine starts it again before Send, and
  /// coming back after closing other apps lets a small engine grow.
  func applicationDidBecomeActive(_ notification: Notification) {
    guard !quitting, !WorkbookWindowRegistry.quitting,
      !CommandLine.arguments.contains("--check-resources")
    else { return }
    WorkspaceState.prewarmLocalAI(resizing: true)
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
    NotificationCenter.default.post(name: .sevraKeepNotSent, object: nil)
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
  static let sevraKeepNotSent = Notification.Name("sevraKeepNotSent")
  static let sevraImport = Notification.Name("sevraImport"),
    sevraSearch = Notification.Name("sevraSearch"),
    sevraReviews = Notification.Name("sevraReviews"),
    sevraActivity = Notification.Name("sevraActivity"),
    sevraExport = Notification.Name("sevraExport")
}
/// A workbook, or the start page when `path` is nil. The start page is ready to type into and
/// becomes a workbook on the first message or file. It closes once another workbook is in front,
/// and comes back when the last workbook window closes.
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
  /// What was typed on the start page, for the workbook it made. Sent when it started the workbook
  /// alone, and left in the composer when files started it.
  @State private var startingMessage: (destination: String, text: String, send: Bool)?
  @State private var starting = false
  var body: some View {
    Group {
      if state.workbook != nil {
        WorkbookView(state: state)
      } else if let path {
        // Opening can wait for another process to let go of the workbook. Showing the start page
        // meanwhile looked like a second one, and closing it left no window at all.
        OpeningWorkbookView(name: Self.name(path)) { ownWindow?.performClose(nil) }
      } else {
        welcome
      }
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
                // A window still opening its workbook counts too: closing it cancels the open.
                let heldWorkbook = state?.workbook != nil || claimed != nil
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
        window?.title = state.workbook?.title ?? path.map(Self.name) ?? "Sevra"
      }
    )
    .onAppear {
      inbox.files = files
      state.renameWorkbook = { name in try await rename(to: name) }
    }
    .task(id: claimed) {
      guard let path = claimed, let window = ownWindow else { return }
      // The window still holds the workbook only if it was not closed while the workbook opened.
      let stillOpen = { @MainActor in
        !Task.isCancelled && WorkbookWindowRegistry.owner(of: path) === window
      }
      do {
        try await state.open(URL(fileURLWithPath: path))
        guard stillOpen() else {
          state.close()
          return
        }
        WorkbookWindowRegistry.closeStarts(except: window)
        RecentWorkbooks.add(path)
        if let intake = startingFiles, intake.destination == path {
          startingFiles = nil
          state.importFiles(intake.files)
        }
        if let message = startingMessage, message.destination == path {
          startingMessage = nil
          state.prompt = message.text
          if message.send { state.send() }
        }
      } catch {
        guard stillOpen() else {
          state.close()
          return
        }
        openFailed(path, error, in: window)
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
          path = WorkbookWindowRegistry.canonical(
            WorkbookFiles.fileNamedLikeTitle(urls.remove(at: first)).path)
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
    StartView(
      start: start, addFiles: pickFiles, open: { files.open() }, demo: { files.demo() },
      openWorkbook: { files.open($0) }, starting: starting)
  }
  static func name(_ path: String) -> String {
    URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
  }
  /// A window that cannot open its workbook gives it up. With other windows open it closes and the
  /// error shows on the one in front; otherwise it becomes the start page and shows the error there.
  private func openFailed(_ failed: String, _ error: Error, in window: NSWindow) {
    WorkbookWindowRegistry.release(window)
    if WorkbookWindowRegistry.hasWindows(besides: window) {
      retired = true
      window.close()
      // After the close, so the window now in front shows it.
      DispatchQueue.main.async {
        WorkbookFiles.report("Can’t open “\(Self.name(failed))”", error.localizedDescription)
      }
      return
    }
    // Nothing the failed open had already taken stays held by a window that is now the start page.
    state.close()
    claimed = nil
    path = nil
    // Recorded here rather than left to the next window update, which might not come before a
    // workbook opens elsewhere and would then leave this page behind it.
    WorkbookWindowRegistry.showsStart(window, true)
    welcomeError = error.localizedDescription
  }
  /// Closing the last workbook leaves the start page, never an app with no window. Quitting does not.
  private func reopenStartIfLast() {
    let openWindow = openWindow
    DispatchQueue.main.async {
      if WorkbookWindowRegistry.shouldOpenStart() { openWindow(id: Self.scene) }
    }
  }
  func pickFiles(_ message: String) {
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
    start(message, input.urls)
  }
  /// Makes the workbook in the workbooks folder, named after its first files or message, and
  /// turns this window into it.
  private func start(_ message: String, _ sources: [URL]) {
    guard !starting, path == nil, let owner = ownWindow, owner.isVisible else { return }
    starting = true
    let name =
      sources.isEmpty
      ? WorkbookLibrary.name(fromMessage: message) : WorkbookLibrary.name(fromFiles: sources)
    Task {
      defer { starting = false }
      do {
        let url = try await Task.detached(priority: .userInitiated) {
          let url = try WorkbookLibrary.newURL(name)
          // Sevra chose this name, so it may name the workbook better once the work is clear.
          _ = try Workbook.create(
            at: url, title: url.deletingPathExtension().lastPathComponent, automaticTitle: true)
          return url
        }.value
        guard ownWindow === owner, path == nil else { return }
        if !sources.isEmpty { startingFiles = (url.path, sources) }
        if !message.isEmpty { startingMessage = (url.path, message, sources.isEmpty) }
        path = url.path
      } catch { welcomeError = error.localizedDescription }
    }
  }
  /// Renames the workbook's file and title together. The workbook closes for the move and opens
  /// again in this window under its new name.
  private func rename(to requested: String) async throws {
    // Only the place is kept: holding the workbook itself here would keep it open through the move.
    guard let window = ownWindow, let source = state.workbook?.url else { return }
    try require(
      !state.busy, "busy", "Wait for the current work to finish, then rename the workbook.")
    // Refused here, while the workbook is still open and the rename sheet can say why.
    _ = try WorkbookLibrary.renameTarget(source, to: requested)
    let saved = await state.saveBeforeClosing()
    try require(saved, "save", "Save or preserve the open drafts before renaming the workbook.")
    let defaults = UserDefaults.standard
    let chat = defaults.string(forKey: "lastConversation:" + source.path)
    state.workbookRename = nil
    state.close()
    WorkbookWindowRegistry.release(window)
    // Cleared so the window claims and opens the workbook again, under either name.
    claimed = nil
    do {
      let target = try await Task.detached(priority: .userInitiated) {
        try WorkbookLibrary.rename(source, to: requested)
      }.value
      RecentWorkbooks.forget(source.path)
      defaults.removeObject(forKey: "lastConversation:" + source.path)
      if let chat { defaults.set(chat, forKey: "lastConversation:" + target.path) }
      path = target.path
    } catch {
      WorkbookFiles.report("Can’t rename “\(Self.name(source.path))”", error.localizedDescription)
    }
  }
}

/// Reports the window this view is in. A new view is often not in its window yet, so it also
/// reports when it joins one: a window that waited for its next redraw instead could sit on
/// "Opening…" until something else happened to redraw it.
struct WindowAccessor: NSViewRepresentable {
  let changed: (NSWindow?) -> Void
  final class Probe: NSView {
    var changed: ((NSWindow?) -> Void)?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      // Async, because SwiftUI state must not change while it is attaching views.
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.changed?(self.window)
      }
    }
  }
  func makeNSView(context: Context) -> Probe {
    let view = Probe()
    view.changed = changed
    return view
  }
  func updateNSView(_ view: Probe, context: Context) {
    view.changed = changed
    DispatchQueue.main.async { [weak view] in
      guard let view else { return }
      changed(view.window)
    }
  }
}
