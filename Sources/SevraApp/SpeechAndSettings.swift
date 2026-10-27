import AVFoundation
import SevraAI
import SevraCore
import SevraProduct
import Speech
import SwiftUI

@MainActor final class SpeechInput: ObservableObject {
  @Published var active = false
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var tapped = false
  func start(result: @escaping (String) -> Void, failure: @escaping (String) -> Void) {
    guard !active else { return }
    SFSpeechRecognizer.requestAuthorization { authorization in
      Task { @MainActor in
        guard authorization == .authorized else {
          failure("Speech recognition permission is required. You can continue typing.")
          return
        }
        AVCaptureDevice.requestAccess(for: .audio) { allowed in
          Task { @MainActor in
            guard allowed else {
              failure(
                "Microphone access is disabled. You can enable it in System Settings or continue typing."
              )
              return
            }
            self.begin(result: result, failure: failure)
          }
        }
      }
    }
  }
  private func begin(result: @escaping (String) -> Void, failure: @escaping (String) -> Void) {
    guard let recognizer = SFSpeechRecognizer(), recognizer.supportsOnDeviceRecognition,
      recognizer.isAvailable
    else {
      failure(
        "On-device dictation is unavailable for this language. Sevra will not send audio to a server."
      )
      return
    }
    MediaPlayback.shared.player?.pause()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    self.request = request
    let node = engine.inputNode
    let format = node.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      failure("No working microphone is available.")
      return
    }
    node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      request.append(buffer)
    }
    tapped = true
    task = recognizer.recognitionTask(with: request) { [weak self] value, error in
      Task { @MainActor in
        if let value {
          result(value.bestTranscription.formattedString)
          if value.isFinal { self?.stop() }
        }
        if let error {
          self?.stop()
          failure(error.localizedDescription)
        }
      }
    }
    do {
      engine.prepare()
      try engine.start()
      active = true
    } catch {
      stop()
      failure(error.localizedDescription)
    }
  }
  func stop() {
    if tapped {
      engine.inputNode.removeTap(onBus: 0)
      tapped = false
    }
    engine.stop()
    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil
    active = false
  }
}
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
    cancellation = Cancellation()
    let cancel = cancellation
    let folder = URL(fileURLWithPath: modelDirectory)
    Task {
      do {
        try await ProductAI.shared.setup(
          at: folder, reusing: source, cancellation: cancel,
          progress: { text in Task { @MainActor in status = text } })
        status = "Model files are ready."
      } catch { self.error = error.localizedDescription }
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
