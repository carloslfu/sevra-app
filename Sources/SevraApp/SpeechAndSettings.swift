import SevraAI
import SevraCore
import SevraProduct
import SevraVoice
import SwiftUI

struct ModelSettingsView: View {
  @AppStorage("appearance") private var appearance = "system"
  @AppStorage(ProductAI.preferenceKey) private var modelDirectory = ProductAI.defaultDirectory.path
  @State private var busy = false
  @State private var status = ""
  @State private var error: String?
  @State private var cancellation = Cancellation()
  var body: some View {
    Form {
      Picker("Appearance", selection: $appearance) {
        Text("System").tag("system")
        Text("Light").tag("light")
        Text("Dark").tag("dark")
      }
      Section("Local AI") {
        Text(ProductAI.name).font(.headline)
        Text(ProductAI.detail).foregroundStyle(.secondary)
        Text(
          "The model stays on this Mac and is shared across workbooks. Setup downloads approximately \(ByteCountFormatter.string(fromByteCount:ProductAI.downloadBytes,countStyle:.file))."
        )
        TextField(
          ProductAI.canReuseModel ? "Model storage folder" : "Model folder", text: $modelDirectory
        )
        .disabled(busy)
        HStack {
          Button("Choose folder…") {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            if panel.runModal() == .OK, let url = panel.url { modelDirectory = url.path }
          }.disabled(busy)
          Button("Download / verify model") { setup() }.disabled(busy)
        }
        if ProductAI.canReuseModel {
          Button("Reuse an existing Fast model…") {
            let panel = NSOpenPanel()
            panel.title = "Choose the Fast model folder containing its dflash folder"
            panel.directoryURL = ProductAI.suggestedReuseDirectory
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            if panel.runModal() == .OK, let source = panel.url { setup(reusing: source) }
          }.disabled(busy)
          Text(
            "Existing weights are verified and reused in place. Keep their original folder available."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        Button("Unload model from memory") {
          Task {
            let released = await ProductAI.shared.unload()
            status =
              released
              ? "Idle model released."
              : "The model is working. Cancel its current turn before unloading."
          }
        }.disabled(busy)
        if busy {
          ProgressView()
          Button("Cancel") { cancellation.cancel() }
        }
        if !status.isEmpty { Text(status).font(.caption).textSelection(.enabled) }
        if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
      }
      Section("Voice") {
        Text(
          "Dictation uses on-device speech recognition. Microphone permission is requested when you first use it. Review dictated text before sending."
        ).foregroundStyle(.secondary)
      }
    }.formStyle(.grouped).padding(12).frame(width: 600, height: 580)
      .onDisappear { cancellation.cancel() }
  }
  func setup(reusing source: URL? = nil) {
    busy = true
    error = nil
    status = "Starting model setup…"
    cancellation = Cancellation()
    let cancel = cancellation
    let folder = URL(fileURLWithPath: modelDirectory)
    Task {
      do {
        try await ProductAI.shared.setup(
          at: folder, reusing: source, cancellation: cancel,
          progress: { text in
            Task { @MainActor in
              guard busy, cancellation === cancel, !cancel.isCancelled else { return }
              status = text
            }
          })
        status = "Model files are ready."
      } catch {
        if cancel.isCancelled {
          status = "Setup cancelled. Downloaded files are kept so you can resume."
        } else {
          status = ""
          self.error = error.localizedDescription
        }
      }
      busy = false
    }
  }
}

struct VoiceButton: View {
  @ObservedObject var speech: SpeechInput
  let action: () -> Void
  var body: some View {
    Button(action: action) { Image(systemName: speech.active ? "stop.circle.fill" : "mic") }.help(
      speech.active ? "Stop dictation" : "Dictate on this Mac"
    ).accessibilityLabel(speech.active ? "Stop dictation" : "Start dictation")
  }
}
