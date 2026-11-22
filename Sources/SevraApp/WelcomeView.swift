import SevraCore
import SevraProduct
import SevraTableUI
import SwiftUI

/// A window opening its workbook. Opening can wait for another process to let the workbook go, so
/// it says which workbook and can be cancelled, which closes the window.
struct OpeningWorkbookView: View {
  let name: String
  let cancel: () -> Void
  var body: some View {
    VStack(spacing: 16) {
      ProgressView().controlSize(.large).accessibilityHidden(true)
      Text("Opening “\(name)”…").readingFont(.title3).multilineTextAlignment(.center)
        .lineLimit(2).truncationMode(.middle).frame(maxWidth: 420)
      Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Opening \(name)")
  }
}

/// The window before it holds a workbook. It is ready to type into: the first message or the
/// first files make the workbook in the workbooks folder, named after them, with no save panel.
struct StartView: View {
  /// Makes a workbook from a message, from files, or from files with a message left in the composer.
  let start: (_ message: String, _ files: [URL]) -> Void
  let addFiles: (_ message: String) -> Void
  let open: () -> Void
  let demo: () -> Void
  let openWorkbook: (URL) -> Void
  /// True while the workbook is being made, so nothing starts a second one.
  var starting = false
  var folder: URL = WorkbookLibrary.directory()
  var defaults: UserDefaults = .standard
  @State private var message = ""
  @State private var recents: [String] = []
  @State private var showingAll = false
  @State private var dropTargeted = false
  @State private var modelMissing = false
  @FocusState private var composerFocused: Bool
  private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 26) {
          VStack(spacing: 16) {
            HStack(spacing: 9) {
              ObserverMark().fill(.primary).frame(width: 44, height: 44)
              SevraWordmark().fill(.primary).frame(width: 118, height: 25)
            }.accessibilityElement(children: .ignore).accessibilityLabel("Sevra")
            Text("What are we working on?").readingFont(.title, weight: .medium)
              .accessibilityAddTraits(.isHeader)
          }.multilineTextAlignment(.center)
          VStack(spacing: 10) {
            composer
            VStack(spacing: 3) {
              Text("Drop files anywhere in this window to start from them.")
              Text("Workbooks are saved in \(folderLabel) and stay on this Mac.")
                .lineLimit(1).truncationMode(.middle)
            }.readingFont(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if modelMissing {
              HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                  .accessibilityHidden(true)
                Text("Local AI is not set up yet, so replies cannot start.")
                  .foregroundStyle(.secondary)
                SettingsLink { Text("Set up…") }.buttonStyle(.link)
              }.readingFont(.callout)
            }
          }
          if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              Text("Recent workbooks").readingFont(.subheadline, weight: .medium)
                .foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
              VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(recents.prefix(showingAll ? 10 : 4)), id: \.self) { path in
                  Button {
                    openWorkbook(URL(fileURLWithPath: path))
                  } label: {
                    HStack(spacing: 10) {
                      Image(systemName: "doc").foregroundStyle(.secondary)
                      Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                        .foregroundStyle(Color.primary).lineLimit(1).truncationMode(.middle)
                      Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                      .padding(.vertical, 5).contentShape(Rectangle())
                  }.buttonStyle(.borderless).help(path)
                }
              }
              if recents.count > 4 {
                Button(showingAll ? "Show fewer" : "Show all \(min(recents.count, 10))") {
                  showingAll.toggle()
                }.buttonStyle(.link)
              }
            }.frame(maxWidth: 380)
          }
          HStack(spacing: 18) {
            Button("Open workbook…", action: open).buttonStyle(.link)
            Button("Try an example", action: demo).buttonStyle(.link)
          }
        }.frame(maxWidth: 600).padding(32).disabled(starting)
          .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
      }
    }.background(Color(nsColor: .windowBackgroundColor))
      .overlay {
        if dropTargeted {
          RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .padding(10).allowsHitTesting(false)
        }
      }
      .onDrop(of: ["public.file-url"], isTargeted: $dropTargeted) { providers in
        guard !starting else { return false }
        Task {
          var urls: [URL] = []
          for provider in providers {
            let url: URL? = await withCheckedContinuation { continuation in
              _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
              }
            }
            if let url { urls.append(url) }
          }
          // A dropped workbook opens. Anything else starts a new workbook from the files.
          let workbooks = urls.filter { ["sevra", "sevraz"].contains($0.pathExtension) }
          workbooks.forEach(openWorkbook)
          let files = urls.filter { !workbooks.contains($0) }
          if !files.isEmpty { start(trimmed, files) }
        }
        return true
      }
      .onAppear {
        recents = defaults.stringArray(forKey: "recentWorkbooks") ?? []
        composerFocused = true
      }
      .task {
        let directory =
          defaults.string(forKey: ProductAI.preferenceKey).map { URL(fileURLWithPath: $0) }
          ?? ProductAI.defaultDirectory
        modelMissing = !(await AppHost.installed(at: directory))
      }
      .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) {
        _ in
        let saved = defaults.stringArray(forKey: "recentWorkbooks") ?? []
        if saved != recents { recents = saved }
      }
  }

  private var folderLabel: String { (folder.path as NSString).abbreviatingWithTildeInPath }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("Ask, or describe what you need to do…", text: $message, axis: .vertical)
        .textFieldStyle(.plain).focused($composerFocused).lineLimit(3...8).onSubmit(send)
        .accessibilityLabel("Message Sevra")
      HStack {
        Button {
          addFiles(trimmed)
        } label: {
          Label("Add files…", systemImage: "paperclip")
        }.buttonStyle(.borderless).help("Start from spreadsheets, PDFs or other files")
        Spacer()
        if starting { ProgressView().controlSize(.small) }
        Button(action: send) { Image(systemName: "arrow.up") }.buttonStyle(.borderedProminent)
          .disabled(trimmed.isEmpty).keyboardShortcut(.return, modifiers: .command)
          .help("Send").accessibilityLabel("Send message")
      }
    }.padding(14).background(
      Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14)
    ).overlay(
      RoundedRectangle(cornerRadius: 14)
        .stroke(composerFocused ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: 1)
    )
  }

  private func send() {
    guard !starting, !trimmed.isEmpty else { return }
    start(trimmed, [])
  }
}
