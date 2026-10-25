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
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(
          item.category.capitalized + " · " + item.meaning.capitalized + " · "
            + item.status.capitalized
        ).font(.caption).foregroundStyle(.secondary)
        Spacer()
        if item.status == "draft" {
          Button("Accept") {
            state.run("Accepting record") { book, _ in _ = try book.accept(item.id) }
          }
        }
        if item.assetID != nil {
          Menu("File actions") {
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
          PDFViewer(
            url: file, locator: state.itemLocators[item.id],
            onSelection: { state.selectedContext = $0 })
        } else if ["mp4", "mov", "m4v", "mp3", "wav", "m4a", "aiff"].contains(ext) {
          VStack {
            VideoPlayer(player: player).onAppear {
              if player == nil { player = AVPlayer(url: file) }
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
            if item.data != .object([:]) {
              Text(item.data.text).font(.system(.callout, design: .monospaced)).textSelection(
                .enabled)
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
    }.task(id: draft) {
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
struct PDFViewer: NSViewRepresentable {
  let url: URL
  let locator: String?
  let onSelection: (String) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(onSelection) }
  func makeNSView(context: Context) -> PDFView {
    let view = PDFView()
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    view.document = PDFDocument(url: url)
    context.coordinator.observe(view)
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
    init(_ callback: @escaping (String) -> Void) { self.callback = callback }
    func observe(_ view: PDFView) {
      token = NotificationCenter.default.addObserver(
        forName: .PDFViewSelectionChanged, object: view, queue: .main
      ) { [weak self, weak view] _ in
        guard let view, let text = view.currentSelection?.string else { return }
        let page = view.currentPage.flatMap { view.document?.index(for: $0) } ?? 0
        self?.callback("Page \(page+1): " + String(text.prefix(4000)))
      }
    }
    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
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
