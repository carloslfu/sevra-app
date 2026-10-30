import AppKit
import SevraAI
import SevraCore
import SevraDocumentUI
import SevraPreviewUI
import SevraProduct
import SwiftUI

@main struct SevraApp: App {
  init() {
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
    WindowGroup("Sevra", for: String.self) { $path in
      WorkspaceWindow(path: $path, inbox: documentDelegate)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
    .defaultSize(width: 1200, height: 800)
    .commands {
      ConversationCommands()
      CommandGroup(replacing: .newItem) {
        Button("New Workbook…") { NotificationCenter.default.post(name: .sevraNew, object: nil) }
          .keyboardShortcut("n")
        Button("Open Workbook…") { NotificationCenter.default.post(name: .sevraOpen, object: nil) }
          .keyboardShortcut("o")
      }
      CommandMenu("Workbook") {
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
    Settings { ModelSettingsView() }
  }
}

@MainActor final class DocumentDelegate: NSObject, NSApplicationDelegate, ObservableObject {
  @Published var pending: [URL] = []
  func applicationDidFinishLaunching(_ notification: Notification) {
    NativeAutomationHost.shared.start()
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard DocumentDraftScope.flushAll() else { return .terminateCancel }
    NativeAutomationHost.shared.beginTermination()
    Task {
      await NativeAutomationHost.shared.yieldForInteractive()
      let saved = await ConversationSession.flushAll()
      let formsSaved = await FormDraftScope.flushAll()
      let clarificationsSaved = await WorkflowClarificationScope.flushAll()
      await SpaceNavigationSession.flushAll()
      let complete = saved && formsSaved && clarificationsSaved && DocumentDraftScope.flushAll()
      if complete {
        await NativeAutomationHost.shared.stop()
      } else {
        NativeAutomationHost.shared.cancelTermination()
      }
      sender.reply(toApplicationShouldTerminate: complete)
    }
    return .terminateLater
  }
  func applicationWillTerminate(_ notification: Notification) {
    NotificationCenter.default.post(name: .sevraStopping, object: nil)
  }
  func application(_ application: NSApplication, open urls: [URL]) { pending += urls }
}
extension Notification.Name {
  static let sevraStopping = Notification.Name("sevraStopping")
  static let sevraNew = Notification.Name("sevraNew"), sevraOpen = Notification.Name("sevraOpen"),
    sevraImport = Notification.Name("sevraImport"), sevraSearch = Notification.Name("sevraSearch"),
    sevraReviews = Notification.Name("sevraReviews"),
    sevraActivity = Notification.Name("sevraActivity"),
    sevraExport = Notification.Name("sevraExport")
}
struct WorkspaceWindow: View {
  @Binding var path: String?
  @ObservedObject var inbox: DocumentDelegate
  @StateObject private var state = WorkspaceState()
  @Environment(\.openWindow) private var openWindow
  @State private var welcomeError: String?
  @State private var ownWindow: NSWindow?
  @State private var closeGuard: DocumentCloseGuard?
  @State private var startingFiles: (destination: String, files: [URL])?
  var body: some View {
    Group {
      if state.workbook != nil { WorkbookView(state: state) } else { welcome }
    }
    .frame(minWidth: 820, minHeight: 600)
    .background(
      WindowAccessor { window in
        if ownWindow !== window { ownWindow = window }
        if let window {
          if closeGuard == nil {
            closeGuard = DocumentCloseGuard(asyncFlush: { [weak state] in
              await state?.saveBeforeClosing() ?? true
            })
          }
          closeGuard?.attach(to: window)
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
    .task(id: path) {
      if let path {
        do {
          try await state.open(URL(fileURLWithPath: path))
          guard !Task.isCancelled else { return }
          let previous = UserDefaults.standard.stringArray(forKey: "recentWorkbooks") ?? []
          UserDefaults.standard.set(
            Array(([path] + previous.filter { $0 != path }).prefix(10)), forKey: "recentWorkbooks")
          if let intake = startingFiles, intake.destination == path {
            startingFiles = nil
            state.importFiles(intake.files)
          }
        } catch {
          welcomeError = error.localizedDescription
        }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .sevraStopping)) { _ in
      state.endInteraction()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { event in
      if let window = event.object as? NSWindow, window === ownWindow { state.endInteraction() }
    }
    .onReceive(inbox.$pending) { pending in
      guard !pending.isEmpty else { return }
      DispatchQueue.main.async {
        let urls = inbox.pending
        inbox.pending = []
        for url in urls { openURL(url) }
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
    .onReceive(NotificationCenter.default.publisher(for: .sevraNew)) { _ in if isKey { create() } }
    .onReceive(NotificationCenter.default.publisher(for: .sevraOpen)) { _ in if isKey { open() } }
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
  var welcome: some View {
    WelcomeView(
      startFromFiles: startFromFiles, open: open, create: create, demo: demo,
      openRecent: { openWindow(value: $0) })
  }
  func create() {
    let panel = NSSavePanel()
    panel.title = "Create a workbook"
    panel.nameFieldStringValue = "Untitled.sevra"
    panel.canCreateDirectories = true
    if panel.runModal() == .OK, let url = panel.url {
      do {
        _ = try Workbook.create(at: url, title: url.deletingPathExtension().lastPathComponent)
        openWindow(value: url.path)
      } catch { welcomeError = error.localizedDescription }
    }
  }
  func startFromFiles() {
    guard let owner = ownWindow, owner.isVisible else { return }
    let input = NSOpenPanel()
    input.title = "Start a workbook from your files"
    input.canChooseFiles = true
    input.canChooseDirectories = false
    input.allowsMultipleSelection = true
    guard input.runModal() == .OK, ownWindow === owner, owner.isVisible,
      !input.urls.isEmpty
    else { return }
    saveWorkbook(from: input.urls, owner: owner)
  }
  private func saveWorkbook(from files: [URL], owner: NSWindow) {
    guard ownWindow === owner, owner.isVisible else { return }
    let destination = NSSavePanel()
    destination.title = "Save your new workbook"
    destination.nameFieldStringValue = files[0].deletingPathExtension().lastPathComponent + ".sevra"
    destination.canCreateDirectories = true
    guard destination.runModal() == .OK, ownWindow === owner, owner.isVisible,
      let url = destination.url
    else { return }
    do {
      _ = try Workbook.create(at: url, title: url.deletingPathExtension().lastPathComponent)
      startingFiles = (url.path, files)
      path = url.path
    } catch { welcomeError = error.localizedDescription }
  }
  func open() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.treatsFilePackagesAsDirectories = false
    if panel.runModal() == .OK, let url = panel.url { openURL(url) }
  }
  func openURL(_ url: URL) {
    if url.pathExtension == "sevraz" {
      let panel = NSSavePanel()
      panel.title = "Open portable workbook"
      panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + ".sevra"
      if panel.runModal() == .OK, let target = panel.url {
        Task {
          do {
            _ = try await Task.detached { try Workbook.openArchive(url, at: target) }.value
            openWindow(value: target.path)
          } catch { welcomeError = error.localizedDescription }
        }
      }
    } else {
      openWindow(value: url.path)
    }
  }
  func demo() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Willow Workshop.sevra"
    if panel.runModal() == .OK, let url = panel.url {
      do {
        try Demo.create(at: url)
        openWindow(value: url.path)
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
