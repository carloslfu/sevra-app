import AppKit
import SevraCore
import SwiftUI

public struct NativeAppSpaceView: View {
  @StateObject private var session: NativeAppSession
  private let embedded: Bool
  @State private var showSource = false
  @State private var tableTitles: [String: String]?
  @State private var imageTitles: [String: String]?
  @State private var accessError: String?
  public init(session: NativeAppSession, embedded: Bool = false) {
    self.embedded = embedded
    _session = StateObject(wrappedValue: session)
  }
  private var content: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        if session.status != "running" { Text(session.package.name).font(.title2) }
        Spacer()
        if session.status == "running" {
          Button(session.canRedo ? "Redo last change" : "Undo last change") {
            if session.canRedo { session.redo() } else { session.undo() }
          }.disabled((!session.canUndo && !session.canRedo) || session.conversationBusy)
          Button("Disable app") { session.revoke() }
        } else if session.status == "failed" {
          Button("Restart app") { session.start() }
          Button("Disable app") { session.revoke() }
        }
        Menu("App") {
          Button("View source") { showSource = true }
          Button("Export app template…") { exportTemplate() }
        }
      }
      .controlSize(.small)
      if let error = session.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
      if session.status == "disabled" {
        Text("This app is ready to enable").font(.headline)
        Text(
          "Enable this version here or in chat to grant the workbook access shown below on this Mac."
        )
        ForEach(session.package.datasets.keys.sorted(), id: \.self) { key in
          let binding = session.package.datasets[key]!
          Label(
            (tableTitles?[key]
              ?? (accessError == nil ? "Loading table…" : "Unavailable table"))
              + (binding.writable ? " · Read and change records" : " · Read records"),
            systemImage: binding.writable ? "pencil" : "eye")
        }
        ForEach((session.package.images ?? [:]).keys.sorted(), id: \.self) { key in
          Label(
            (imageTitles?[key]
              ?? (accessError == nil ? "Loading image…" : "Unavailable image"))
              + " · Display image",
            systemImage: "photo")
        }
        if session.package.datasets.isEmpty && (session.package.images ?? [:]).isEmpty {
          Text("This app requests no workbook data access.")
        }
        if let accessError {
          Text(accessError).foregroundStyle(.red)
          Button("Reload access") { Task { await loadAccess() } }
        }
        Button("Enable app") { session.enable() }.buttonStyle(.borderedProminent)
          .disabled(tableTitles == nil || imageTitles == nil)
        Spacer()
      } else if session.status == "starting" {
        ProgressView("Starting app…")
        Spacer()
      } else if session.status == "running" {
        NativeAppSurface(session: session).frame(maxWidth: .infinity, maxHeight: .infinity)
          .disabled(session.conversationBusy)
      } else {
        Text("Saved records remain in your workbook. Your draft will be restored when you restart.")
        Spacer()
      }
    }
    .padding(embedded ? 12 : 20)
  }
  public var body: some View {
    Group {
      if session.status == "disabled" || (embedded && session.status != "running") {
        ScrollView { content.frame(maxWidth: .infinity, alignment: .leading) }
      } else {
        content
      }
    }
    .task { await loadAccess() }
    .onAppear { session.start() }
    .sheet(isPresented: $showSource) {
      VStack(alignment: .leading) {
        Text("App source · SDK \(session.package.sdkVersion)").font(.headline)
        ScrollView {
          Text(session.package.source).font(.system(.caption, design: .monospaced)).textSelection(
            .enabled
          ).frame(maxWidth: .infinity, alignment: .leading)
        }
        Button("Done") { showSource = false }.keyboardShortcut(.cancelAction)
      }.padding().frame(width: 720, height: 520)
    }
  }
  private func loadAccess() async {
    tableTitles = nil
    imageTitles = nil
    accessError = nil
    let book = session.book
    let package = session.package
    do {
      let (tables, images) = try await Task.detached {
        (try book.nativeAppTableTitles(package), try book.nativeAppImageTitles(package))
      }.value
      guard !Task.isCancelled else { return }
      tableTitles = tables
      imageTitles = images
    } catch {
      guard !Task.isCancelled else { return }
      accessError = error.localizedDescription
    }
  }
  private func exportTemplate() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = session.package.name + ".sevraapp"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      var package = session.package
      for key in package.datasets.keys { package.datasets[key]?.datasetID = nil }
      try Data(encoded(package).json().utf8).write(to: url, options: .atomic)
    } catch {
      let alert = NSAlert()
      alert.messageText = "Cannot export app"
      alert.informativeText = error.localizedDescription
      alert.runModal()
    }
  }
}
