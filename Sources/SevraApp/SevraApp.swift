import AppKit
import SevraAI
import SevraCore
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
  var body: some Scene {
    WindowGroup("Sevra", for: String.self) { $path in
      WorkspaceWindow(path: $path, inbox: documentDelegate)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
    .defaultSize(width: 1200, height: 800)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New Workbook…") { NotificationCenter.default.post(name: .sevraNew, object: nil) }
          .keyboardShortcut("n")
        Button("Open Workbook…") { NotificationCenter.default.post(name: .sevraOpen, object: nil) }
          .keyboardShortcut("o")
      }
      CommandMenu("Workbook") {
        Button("Import Files…") { NotificationCenter.default.post(name: .sevraImport, object: nil) }
          .keyboardShortcut("i")
        Button("Search Workbook") {
          NotificationCenter.default.post(name: .sevraSearch, object: nil)
        }.keyboardShortcut("f", modifiers: [.command, .shift])
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
  private var memoryPressure: DispatchSourceMemoryPressure?
  func applicationDidFinishLaunching(_ notification: Notification) {
    let source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.warning, .critical], queue: .global(qos: .utility))
    source.setEventHandler { Task { await ProductAI.shared.unload() } }
    source.resume()
    memoryPressure = source
  }
  func applicationWillTerminate(_ notification: Notification) {
    NotificationCenter.default.post(name: .sevraStopping, object: nil)
    memoryPressure?.cancel()
  }
  func application(_ application: NSApplication, open urls: [URL]) { pending += urls }
}
extension Notification.Name {
  static let sevraStopping = Notification.Name("sevraStopping")
  static let sevraNew = Notification.Name("sevraNew"), sevraOpen = Notification.Name("sevraOpen"),
    sevraImport = Notification.Name("sevraImport"), sevraSearch = Notification.Name("sevraSearch"),
    sevraExport = Notification.Name("sevraExport")
}
struct WorkspaceWindow: View {
  @Binding var path: String?
  @ObservedObject var inbox: DocumentDelegate
  @StateObject private var state = WorkspaceState()
  @Environment(\.openWindow) private var openWindow
  @State private var welcomeError: String?
  @State private var ownWindow: NSWindow?
  var body: some View {
    Group {
      if state.workbook != nil { WorkbookView(state: state) } else { welcome }
    }
    .frame(minWidth: 820, minHeight: 600)
    .background(
      WindowAccessor { window in
        if ownWindow !== window { ownWindow = window }
        window?.representedURL = state.workbook?.url
        window?.title = state.workbook?.title ?? "Sevra"
      }
    )
    .task(id: path) {
      if let path {
        do {
          try state.open(URL(fileURLWithPath: path))
          let previous = UserDefaults.standard.stringArray(forKey: "recentWorkbooks") ?? []
          UserDefaults.standard.set(
            Array(([path] + previous.filter { $0 != path }).prefix(10)), forKey: "recentWorkbooks")
        } catch {
          welcomeError = error.localizedDescription
        }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .sevraStopping)) { _ in
      state.cancellation.cancel()
      state.speech.stop()
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
    .onReceive(NotificationCenter.default.publisher(for: .sevraSearch)) { _ in
      if isKey { state.navigate(.search) }
    }
    .onReceive(NotificationCenter.default.publisher(for: .sevraExport)) { _ in
      if isKey { state.exportPanel() }
    }
  }
  var isKey: Bool { ownWindow != nil && NSApp.keyWindow === ownWindow }
  var welcome: some View {
    VStack(alignment: .leading, spacing: 26) {
      HStack(spacing: 13) {
        ObserverMark().fill(.primary).frame(width: 70, height: 70)
        SevraWordmark().fill(.primary).frame(width: 189, height: 40)
      }.accessibilityElement(children: .ignore).accessibilityLabel("Sevra")
      Text("A workbook for the work in front of you.").font(.title2)
      Text(
        "Bring your documents and tables together. Explore them through conversation, keep the evidence, and make the result your own."
      )
      .font(.body).foregroundStyle(.secondary).frame(maxWidth: 470, alignment: .leading)
      HStack(spacing: 14) {
        Button("Create a workbook", action: create).buttonStyle(.borderedProminent).controlSize(
          .large)
        Button("Open…", action: open).controlSize(.large)
        Button("Try an example", action: demo).controlSize(.large)
      }
      let recent = UserDefaults.standard.stringArray(forKey: "recentWorkbooks") ?? []
      if !recent.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Recent workbooks").font(.headline)
          ForEach(recent, id: \.self) { path in
            Button(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) {
              openWindow(value: path)
            }
            .buttonStyle(.link)
          }
        }
      }
      if let error = welcomeError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
      Text("Your work stays on this Mac. Local AI setup is available in Settings.").font(.callout)
        .foregroundStyle(.secondary)
    }.padding(60).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      .background(Color(nsColor: .windowBackgroundColor))
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
