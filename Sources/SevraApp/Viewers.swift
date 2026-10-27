import AVKit
import AppKit
import PDFKit
import QuickLookUI
import SevraCore
import SwiftUI

struct ItemView: View {
  let item: Item
  @ObservedObject var state: WorkspaceState
  @State private var file: URL?
  @State private var failure: String?
  @State private var player: AVPlayer?
  @State private var editing = false
  @State private var draft = ""
  @State private var savedDraft = ""
  @State private var draftVersion: String?
  @State private var keepPlaying = false
  @State private var asset: Asset?
  @State private var choosingArchiveMembers = false
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(
          item.category.capitalized + " · " + item.meaning.capitalized + " · "
            + item.status.capitalized
        ).font(.caption).foregroundStyle(.secondary)
        Spacer()
        if item.status == "draft" {
          Button("Accept") { state.review(item.id, accepting: true) }.disabled(state.busy)
        }
        if item.supersedes != nil {
          Button("Undo") { state.review(item.id, accepting: false) }.disabled(state.busy)
        }
        if item.assetID != nil {
          Menu("File actions") {
            if let ext = file?.pathExtension.lowercased(),
              ["mp4", "mov", "m4v", "mp3", "wav", "m4a", "aiff"].contains(ext)
            {
              Button("Transcribe on this Mac") { state.transcribe(item.id) }
            }
            if file?.pathExtension.lowercased() == "zip" {
              Button("Choose files from ZIP…") { choosingArchiveMembers = true }
            }
            Button("Resume or retry intake") {
              state.run("Resuming intake") { book, cancel in
                try book.resumeIntake(item.id, cancellation: cancel)
              }
            }
          }
        }
        if asset?.mode == "linked" {
          Menu("External file") {
            Button("Include in workbook") {
              state.run("Including original") { book, cancel in
                _ = try book.includeLinked(item.id, cancellation: cancel)
              }
            }
            Button("Find original…") { relink() }
          }
        }
        if let file {
          Button("Open in another app") { NSWorkspace.shared.open(file) }
        } else if item.kind == "document" {
          Button(editing ? "Done" : "Edit draft") {
            if editing { saveDraft() } else { draft = draftVersion == nil ? item.text : savedDraft }
            editing.toggle()
          }
        }
      }.padding(12)
      Divider()
      if let failure {
        ContentUnavailableView(
          "File unavailable", systemImage: "doc.badge.ellipsis", description: Text(failure))
      } else if let file {
        let ext = file.pathExtension.lowercased()
        if ext == "pdf" {
          PDFWorkspace(
            url: file, locator: state.itemLocators[item.id],
            onSelection: { state.selectedContext = $0 })
        } else if ["mp4", "mov", "m4v", "mp3", "wav", "m4a", "aiff"].contains(ext) {
          VStack {
            VideoPlayer(player: player).onAppear {
              if player == nil {
                player = AVPlayer(url: file)
                if let locator = state.itemLocators[item.id],
                  let range = locator.range(of: "time=[0-9.]+", options: .regularExpression),
                  let seconds = Double(locator[range].dropFirst(5)), seconds.isFinite
                {
                  player?.seek(
                    to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero,
                    toleranceAfter: .zero)
                }
              }
              MediaPlayback.shared.player = player
            }
            Toggle("Keep playing while I explore", isOn: $keepPlaying).padding(10)
          }.onDisappear {
            if !keepPlaying {
              player?.pause()
            } else {
              state.backgroundPlayer = player
              state.backgroundMediaTitle = item.title
            }
          }
        } else if ["png", "jpg", "jpeg", "heic", "tiff", "webp"].contains(ext),
          let image = NSImage(contentsOf: file)
        {
          ImageViewer(image: image)
        } else if [
          "html", "htm", "svg", "xml", "js", "swift", "py", "json", "txt", "md", "csv", "tsv",
        ].contains(ext) {
          SafeTextViewer(file: file)
        } else {
          QuickLookViewer(url: file)
        }
      } else if editing {
        TextEditor(text: $draft).font(.body).padding(16)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            Text(item.title).font(.title2)
            Text(draftVersion == nil ? item.text : savedDraft).textSelection(.enabled)
            if item.kind == "link", let target = URL(string: item.data["url"].text) {
              Link("Open source website", destination: target)
            }
            if item.kind == "table-creation", item.status == "accepted",
              let id = item.data["datasetID"].string
            {
              Button("Open table") { state.navigate(.table(id)) }
            }
            if !["table-change", "table-creation"].contains(item.kind) {
              Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(item.data.object.keys.sorted(), id: \.self) { key in
                  if !["input", "inputs", "supersedes", "datasetID", "url"].contains(key),
                    let value = item.data.object[key], value != .null, value.array.isEmpty,
                    value.object.isEmpty
                  {
                    GridRow {
                      Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                        .foregroundStyle(.secondary)
                      Text(value.text).textSelection(.enabled)
                    }
                  }
                }
              }.font(.callout)
            }
            lineage
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      if let status = try? state.workbook?.extractionStatus(item.id), !status["detail"].text.isEmpty
      {
        Divider()
        Text(status["detail"].text).font(.caption).foregroundStyle(.secondary).padding(10).frame(
          maxWidth: .infinity, alignment: .leading)
      }
    }.sheet(isPresented: $choosingArchiveMembers) {
      ArchiveMemberPicker(source: item, state: state)
    }
    .task(id: draft) {
      guard editing, draft != savedDraft else { return }
      do {
        try await Task.sleep(nanoseconds: 600_000_000)
        try Task.checkCancellation()
        saveDraft()
      } catch {}
    }.onDisappear { if editing { saveDraft() } }
    .task(id: item.id) {
      guard let asset = item.assetID, let book = state.workbook else { return }
      do {
        self.asset = try book.asset(asset)
        file = try await Task.detached { try book.assetURL(asset) }.value
        failure = nil
      } catch {
        failure = error.localizedDescription
      }
    }
  }
  func relink() {
    guard let asset = item.assetID, let book = state.workbook else { return }
    let panel = NSOpenPanel()
    panel.title = "Find the original file"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    Task {
      do {
        file = try await Task.detached {
          try book.relinkAsset(asset, to: url)
          return try book.assetURL(asset)
        }.value
        failure = nil
        state.refresh()
      } catch { failure = error.localizedDescription }
    }
  }
  @ViewBuilder var lineage: some View {
    if let links = try? state.workbook?.lineage(item.id), !links.isEmpty {
      Divider()
      Text("Evidence and history").font(.headline)
      ForEach(links, id: \.text) { link in
        let id = link["child"].text == item.id ? link["parent"].text : link["child"].text
        Button((try? state.workbook?.item(id).title) ?? id) { state.navigate(.item(id)) }
          .buttonStyle(.link)
      }
    }
  }
  func saveDraft() {
    guard draft != savedDraft, draft != item.text || draftVersion != nil, let book = state.workbook
    else { return }
    do {
      let evidence = try book.addItem(
        category: "source", kind: "submission", title: "Edit " + item.title, text: draft,
        status: "accepted")
      let updated = try book.addItem(
        category: "record", kind: "document", title: item.title, text: draft, meaning: item.meaning,
        status: "draft", inputs: [draftVersion ?? item.id, evidence.id],
        transformation: "human-draft-edit-v1", supersedes: draftVersion ?? item.id)
      draftVersion = updated.id
      savedDraft = draft
      state.refresh()
    } catch { state.error = error.localizedDescription }
  }
}
@MainActor final class PDFControls: ObservableObject {
  weak var view: PDFView?
  @Published var page = 1
  @Published var pages = 0
  @Published var query = ""
  @Published var status = ""
  private var previousQuery = ""
  private var lastPage = -1
  private var lastEnd = 0
  func refresh() {
    pages = view?.document?.pageCount ?? 0
    page = (view?.currentPage.flatMap { view?.document?.index(for: $0) } ?? 0) + 1
  }
  func nextMatch() {
    guard let view, let document = view.document, document.pageCount > 0 else { return }
    guard !query.isEmpty && query.utf8.count <= 2048 else {
      status = "Enter up to 2,048 bytes of search text."
      return
    }
    if previousQuery != query {
      lastPage = -1
      lastEnd = 0
      previousQuery = query
    }
    let startPage = lastPage >= 0 ? lastPage : max(0, page - 1)
    for step in 0...document.pageCount {
      let index = (startPage + step) % document.pageCount
      guard let pdfPage = document.page(at: index) else { continue }
      let text = (pdfPage.string ?? "") as NSString
      let start = step == 0 && lastPage == index ? min(lastEnd, text.length) : 0
      let match = text.range(
        of: query, options: .caseInsensitive,
        range: NSRange(location: start, length: text.length - start))
      if match.location != NSNotFound, let selection = pdfPage.selection(for: match) {
        view.setCurrentSelection(selection, animate: true)
        view.go(to: selection)
        lastPage = index
        lastEnd = NSMaxRange(match)
        status = "Match on page \(index + 1)"
        refresh()
        return
      }
    }
    status = "No match in PDF text. Scanned pages may only be searchable through workbook OCR."
  }
}
struct PDFWorkspace: View {
  let url: URL
  let locator: String?
  let onSelection: (String) -> Void
  @StateObject private var controls = PDFControls()
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button {
          controls.view?.goToPreviousPage(nil)
        } label: {
          Image(systemName: "chevron.up")
        }.accessibilityLabel("Previous PDF page").disabled(controls.page <= 1)
        Button {
          controls.view?.goToNextPage(nil)
        } label: {
          Image(systemName: "chevron.down")
        }.accessibilityLabel("Next PDF page").disabled(controls.page >= controls.pages)
        Text("\(controls.page) / \(controls.pages)").font(.caption).monospacedDigit()
        Spacer()
        TextField("Search this PDF", text: $controls.query).textFieldStyle(.roundedBorder).frame(
          maxWidth: 220
        ).onSubmit { controls.nextMatch() }
        Button("Next match") { controls.nextMatch() }.disabled(controls.query.isEmpty)
      }.padding(10)
      if !controls.status.isEmpty {
        Text(controls.status).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
      }
      Divider()
      PDFViewer(url: url, locator: locator, onSelection: onSelection, controls: controls)
    }
  }
}
struct PDFViewer: NSViewRepresentable {
  let url: URL
  let locator: String?
  let onSelection: (String) -> Void
  let controls: PDFControls
  func makeCoordinator() -> Coordinator { Coordinator(onSelection, controls: controls) }
  func makeNSView(context: Context) -> PDFView {
    let view = PDFView()
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    view.document = PDFDocument(url: url)
    controls.view = view
    context.coordinator.observe(view)
    DispatchQueue.main.async { controls.refresh() }
    navigate(view)
    return view
  }
  func updateNSView(_ view: PDFView, context: Context) {
    if view.document?.documentURL != url {
      view.document = PDFDocument(url: url)
      navigate(view)
    }
  }
  func navigate(_ view: PDFView) {
    guard let locator, let match = locator.range(of: "page=[0-9]+", options: .regularExpression),
      let n = Int(locator[match].dropFirst(5)), let page = view.document?.page(at: n - 1)
    else { return }
    view.go(to: page)
  }
  final class Coordinator: NSObject {
    let callback: (String) -> Void
    var token: NSObjectProtocol?
    var pageToken: NSObjectProtocol?
    let controls: PDFControls
    init(_ callback: @escaping (String) -> Void, controls: PDFControls) {
      self.callback = callback
      self.controls = controls
    }
    func observe(_ view: PDFView) {
      pageToken = NotificationCenter.default.addObserver(
        forName: .PDFViewPageChanged, object: view, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.controls.refresh() } }
      token = NotificationCenter.default.addObserver(
        forName: .PDFViewSelectionChanged, object: view, queue: .main
      ) { [weak self, weak view] _ in
        guard let view, let selection = view.currentSelection, let text = selection.string,
          let document = view.document
        else { return }
        // Selection notifications can precede scrolling to a search match.
        // Use the selected pages, never the previously visible page.
        let pages = selection.pages.map { document.index(for: $0) }.filter { $0 != NSNotFound }
          .sorted()
        let location: String
        if let first = pages.first, let last = pages.last {
          location = first == last ? "Page \(first + 1)" : "Pages \(first + 1)–\(last + 1)"
        } else {
          location = "PDF selection"
        }
        self?.callback(location + ": " + String(text.prefix(4000)))
      }
    }
    deinit {
      if let token { NotificationCenter.default.removeObserver(token) }
      if let pageToken { NotificationCenter.default.removeObserver(pageToken) }
    }
  }
}
struct QuickLookViewer: NSViewRepresentable {
  let url: URL
  func makeNSView(context: Context) -> QLPreviewView {
    let view = QLPreviewView(frame: .zero, style: .normal)!
    view.autostarts = false
    view.previewItem = url as NSURL
    return view
  }
  func updateNSView(_ view: QLPreviewView, context: Context) {
    if (view.previewItem as? NSURL) != url as NSURL { view.previewItem = url as NSURL }
  }
}
struct ImageViewer: View {
  let image: NSImage
  @State private var scale = 1.0
  var body: some View {
    VStack {
      HStack {
        Button("Zoom out") { scale = max(0.25, scale / 1.25) }
        Button("Zoom in") { scale = min(6, scale * 1.25) }
        Spacer()
      }.padding(12)
      ScrollView([.horizontal, .vertical]) {
        Image(nsImage: image).resizable().scaledToFit().frame(
          width: min(1000, image.size.width) * scale
        ).padding(20)
      }
    }
  }
}
@MainActor final class MediaPlayback {
  static let shared = MediaPlayback()
  var player: AVPlayer?
}

struct SafeTextViewer: View {
  let file: URL
  @State private var text = ""
  @State private var detail = ""
  var body: some View {
    ScrollView {
      Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(
        maxWidth: .infinity, alignment: .leading
      ).padding(20)
      if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).padding(10) }
    }.task(id: file) {
      do {
        let result = try await Task.detached { () -> (String, String) in
          let handle = try FileHandle(forReadingFrom: file)
          defer { try? handle.close() }
          let bytes = try handle.read(upToCount: 1_000_001) ?? Data()
          return (
            String(decoding: bytes.prefix(1_000_000), as: UTF8.self),
            bytes.count > 1_000_000
              ? "Previewing the first 1 MB. The original file remains intact." : ""
          )
        }.value
        text = result.0
        detail = result.1
      } catch { detail = error.localizedDescription }
    }
  }
}
