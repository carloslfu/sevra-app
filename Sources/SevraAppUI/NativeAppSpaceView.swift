import AppKit
import SevraCore
import SwiftUI

public struct NativeAppSpaceView: View {
  @StateObject private var session: NativeAppSession
  @State private var showSource = false
  public init(book: Workbook, space: Space) {
    _session = StateObject(wrappedValue: NativeAppSession(book: book, space: space))
  }
  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        if session.status != "running" { Text(session.package.name).font(.title2) }
        Spacer()
        if session.status == "running" {
          Button("Undo last change") { session.undo() }.disabled(!session.canUndo)
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
          "Its JavaScript runs in an isolated worker. Enable gives this exact version access to the following workbook tables on this Mac."
        )
        ForEach(session.package.datasets.keys.sorted(), id: \.self) { key in
          let binding = session.package.datasets[key]!
          Label(
            binding.title + (binding.writable ? " · Read and change records" : " · Read records"),
            systemImage: binding.writable ? "pencil" : "eye")
        }
        if session.package.datasets.isEmpty { Text("This app requests no business data access.") }
        Button("Enable app") { session.enable() }.buttonStyle(.borderedProminent)
        Spacer()
      } else if session.status == "starting" {
        ProgressView("Starting app…")
        Spacer()
      } else if session.status == "running" {
        NativeAppSurface(session: session).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Text("Saved records remain in your workbook. Your draft will be restored when you restart.")
        Spacer()
      }
    }
    .padding(20)
    .onAppear { session.start() }
    .onDisappear { session.stop() }
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
