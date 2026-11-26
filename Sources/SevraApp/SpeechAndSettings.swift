import SevraAI
import SevraCore
import SevraProduct
import SevraTableUI
import SevraVoice
import SwiftUI

struct ModelSettingsView: View {
  // Scoped initial presentation for deterministic developer previews. Effects
  // still use the app host; ordinary settings have no override.
  private let initialState: String?
  private let automaticUpdateChecks: Binding<Bool>?
  init(initialState: String? = nil, automaticUpdateChecks: Binding<Bool>? = nil) {
    self.initialState = initialState
    self.automaticUpdateChecks = automaticUpdateChecks
    _busy = State(initialValue: initialState == "Installing" || initialState == "Loading")
    _filesFound = State(initialValue: initialState == "Installed")
    _status = State(
      initialValue: initialState == "Installing"
        ? "Downloading model files…"
        : initialState == "Loading"
          ? "Loading local model…"
          : initialState == "Cancelled"
            ? "Setup cancelled. Downloaded files are kept so you can resume." : "")
    _error = State(
      initialValue: initialState == "Failure"
        ? "Synthetic setup failed. Retry preserves downloaded files." : nil)
  }
  @AppStorage(ReadingStyle.preference) private var textScale = 1.0
  @AppStorage("appearance") private var appearance = "system"
  @AppStorage(ProductAI.preferenceKey) private var modelDirectory = ProductAI.defaultDirectory.path
  @State private var busy = false
  @State private var status = ""
  @State private var error: String?
  @State private var cancellation = Cancellation()
  @State private var filesFound = false
  var body: some View {
    Form {
      Picker("Appearance", selection: $appearance) {
        Text("System").tag("system")
        Text("Light").tag("light")
        Text("Dark").tag("dark")
      }
      Section("Reading") {
        Picker("Text size", selection: $textScale) {
          ForEach([1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { value in
            Text("\(Int(value * 100)) percent").tag(value)
          }
        }
        Text(
          "Changes Sevra text, including tables and document text. Original PDFs and images keep their own zoom controls."
        ).foregroundStyle(.secondary)
      }
      Section("Local AI") {
        Text(ProductAI.name).readingFont(.headline).accessibilityAddTraits(.isHeader)
        Text(ProductAI.detail).foregroundStyle(.secondary)
        Label(
          filesFound ? "Model files found" : "Set up local AI to start asking questions",
          systemImage: filesFound ? "checkmark.circle" : "arrow.down.circle")
        if filesFound {
          Text("Sevra verifies the files before using them.").readingFont(.caption).foregroundStyle(
            .secondary)
        }
        Text(
          "The model stays on this Mac and is shared across workbooks. Setup downloads approximately \(ByteCountFormatter.string(fromByteCount:ProductAI.downloadBytes,countStyle:.file))."
        )
        Button(filesFound ? "Verify model files" : "Download model") { setup() }
          .buttonStyle(.borderedProminent).disabled(busy)
        DisclosureGroup("Model files and storage") {
          TextField("Model storage folder", text: $modelDirectory)
            .disabled(busy)
          HStack {
            Button("Choose folder…") {
              let panel = AppHost.openPanel()
              panel.canChooseDirectories = true
              panel.canChooseFiles = false
              if panel.runModal() == .OK, let url = panel.url { modelDirectory = url.path }
            }.disabled(busy)
          }
          Button("Use existing model files…") {
            let panel = AppHost.openPanel()
            panel.title = "Choose the model folder containing its dflash folder"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            if panel.runModal() == .OK, let source = panel.url { setup(reusing: source) }
          }.disabled(busy)
          Text(
            "Existing weights are verified and reused in place. Keep their original folder available."
          )
          .readingFont(.caption).foregroundStyle(.secondary)
          Button("Unload model from memory") {
            Task {
              let released = await AppHost.ai.unload()
              status =
                released
                ? "Idle model released."
                : "The model is working. Cancel its current turn before unloading."
            }
          }.disabled(busy)
        }
        if busy {
          ProgressView()
          Button("Cancel") { cancellation.cancel() }
        }
        if !status.isEmpty { Text(status).readingFont(.caption).textSelection(.enabled) }
        if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
      }
      Section("Voice") {
        Text(
          "Dictation uses on-device speech recognition. Microphone permission is requested when you first use it. Review dictated text before sending."
        ).foregroundStyle(.secondary)
      }
      if let automaticUpdateChecks {
        Section("Software updates") {
          Toggle("Check for updates automatically", isOn: automaticUpdateChecks)
          Text("Sevra asks before installing an update.").foregroundStyle(.secondary)
        }
      }
    }.formStyle(.grouped).padding(12).frame(
      minWidth: 420, idealWidth: 600, minHeight: 400, idealHeight: 580
    )
    .announceStatus(error ?? (busy || status.isEmpty ? nil : status))
    .task(id: modelDirectory) {
      guard initialState == nil else { return }
      filesFound = false
      let found = await AppHost.installed(at: URL(fileURLWithPath: modelDirectory))
      guard !Task.isCancelled else { return }
      filesFound = found
    }
    .onReceive(NotificationCenter.default.publisher(for: .sevraStopping)) { _ in
      cancellation.cancel()
    }
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
        try await AppHost.setup(
          at: folder, reusing: source, cancellation: cancel,
          progress: { text in
            Task { @MainActor in
              guard busy, cancellation === cancel, !cancel.isCancelled else { return }
              status = text
            }
          })
        status = "Model files are ready."
        filesFound = true
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
      .accessibilityValue(speech.status)
  }
}

/// The mic of every box where the person writes to Sevra. It draws one `Dictation`: the mic,
/// and beside it "Listening…" while it records, "Cleaning up…" after, then "Undo cleanup", or
/// the failure. Typing over dictated text stops it, and so does the box going away.
struct DictationControl: View {
  @ObservedObject var dictation: Dictation
  @Binding var text: String
  var body: some View {
    HStack(spacing: 6) {
      VoiceButton(speech: dictation.speech) {
        dictation.toggle(read: { text }, write: { text = $0 })
      }
      DictationStatus(dictation: dictation, speech: dictation.speech)
    }
    .onChange(of: text) { _, value in dictation.edited(value) }
    .onDisappear { dictation.stop() }
  }
}

/// A box that owns its dictation. The chat box instead uses the workbook's, so sending,
/// switching chats and closing can stop it.
struct DictationButton: View {
  @Binding var text: String
  @StateObject private var dictation = Dictation(
    speech: AppHost.speech(), cleaner: AppHost.dictationCleaner())
  var body: some View { DictationControl(dictation: dictation, text: $text) }
}

private struct DictationStatus: View {
  @ObservedObject var dictation: Dictation
  @ObservedObject var speech: SpeechInput
  var body: some View {
    if speech.active {
      VoiceStatus(speech: speech)
    } else if dictation.cleaning {
      HStack(spacing: 4) {
        ProgressView().controlSize(.mini)
        Text("Cleaning up…").readingFont(.caption).foregroundStyle(.secondary)
      }.accessibilityElement(children: .combine)
    } else if let failure = dictation.failure {
      Text(failure).readingFont(.caption).foregroundStyle(.red).lineLimit(2)
    } else if dictation.original != nil {
      Button("Undo cleanup", action: dictation.restoreOriginal).buttonStyle(.link)
        .readingFont(.caption).help("Put back the words as you said them")
    }
  }
}

struct VoiceStatus: View {
  @ObservedObject var speech: SpeechInput
  var body: some View {
    Text(speech.status).readingFont(.caption).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}
