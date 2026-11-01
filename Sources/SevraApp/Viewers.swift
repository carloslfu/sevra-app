import AVKit
import AppKit
import PDFKit
import QuickLookUI
import SevraCore
import SevraDocumentUI
import SevraPreviewUI
import SevraVoice
import SwiftUI

@MainActor struct ItemView: View {
  @StateObject private var document: DocumentDraft
  @StateObject private var preview = AssetPreviewSession()
  @StateObject private var references = ReferenceDocumentSession()
  @State private var linkNavigation: Cancellation?
  private let workbook: Workbook
  var item: Item { document.current }
  init(item: Item, workbook: Workbook, state: WorkspaceState) {
    _document = StateObject(wrappedValue: DocumentDraft(workbook: workbook, item: item))
    self.state = state
    self.workbook = workbook
  }
  @ObservedObject var state: WorkspaceState
  private var file: URL? { preview.file }
  @State private var player: AVPlayer?
  @State private var keepPlaying = false
  @State private var asset: Asset?
  @State private var choosingArchiveMembers = false
  private var classification: String {
    let status = item.status == "rejected" ? "Withdrawn" : item.status.capitalized
    return [item.category.capitalized, item.meaning.capitalized, status].joined(separator: " · ")
  }
  private var movementDirection: String? {
    guard item.kind == "movement", let quantity = try? Numbers.decimal(item.data["quantity"].text)
    else { return nil }
    if quantity == 0 { return "No stock quantity change" }
    let amount = Numbers.string(quantity < 0 ? -quantity : quantity)
    return (quantity < 0 ? "Decrease: " : "Increase: ") + amount + " " + item.data["subject"].text
  }
  private func scalarDetail(_ key: String) -> String? {
    switch item.data[key] {
    case .string, .number, .bool: return item.data[key].text
    case .null, .array, .object: return nil
    }
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(classification).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        Spacer()
        Button("Links", systemImage: "link") { state.referencePanel = .outgoing }
          .help("Links in this document and documents that mention it")
        if item.status == "draft" {
          Button("Accept") {
            if document.end() { state.review(document.current.id, accepting: true) }
          }.buttonStyle(.borderedProminent).disabled(state.busy)
        }
        if item.status == "draft" {
          Button("Withdraw") {
            if document.end() { state.review(document.current.id, action: .withdraw) }
          }.disabled(state.busy).help(
            "Keep this draft in history without applying it. Undo can restore it.")
        }
        if item.supersedes != nil {
          Button(isTableUpdateRedo ? "Redo" : "Undo") {
            if document.end() {
              state.review(document.current.id, action: isTableUpdateRedo ? .redo : .undo)
            }
          }.disabled(state.busy)
        }
        if item.assetID != nil {
          Menu("File actions") {
            if file != nil {
              Button("Open a copy…") { state.openAssetCopy() }.disabled(state.busy)
                .help("Save a copy for another app. The workbook original stays unchanged.")
              Divider()
            }
            Button("Use saved file…") { state.useSavedFile(item.id) }.disabled(state.busy)
            if let ext = file?.pathExtension.lowercased(), ["csv", "tsv", "xlsx"].contains(ext) {
              Button("Update a working table…") { state.navigate(.tableUpdate(item.id, nil)) }
                .disabled(state.busy)
            }
            if let ext = file?.pathExtension.lowercased(),
              ["mp4", "mov", "m4v", "mp3", "wav", "m4a", "aiff"].contains(ext)
            {
              Button("Transcribe on this Mac") { state.transcribe(item.id) }.disabled(state.busy)
            }
            if file?.pathExtension.lowercased() == "zip" {
              Button("Choose files from ZIP…") { choosingArchiveMembers = true }
            }
            if state.pendingExtractions.contains(where: {
              $0["item_id"].text == item.id
                && ["queued", "running", "failed", "cancelled"].contains($0["state"].text)
            }) {
              Button("Resume file processing") {
                let id = item.id
                let progress = state.rowProgress()
                state.run("Resuming intake") { book, cancel in
                  try book.resumeIntake(id, cancellation: cancel, progress: progress)
                }
              }.disabled(state.busy)
            }
            if asset?.mode == "linked" {
              Divider()
              Button("Include in workbook") {
                let id = item.id
                state.run("Including original") { book, cancel in
                  _ = try book.includeLinked(id, cancellation: cancel)
                }
              }
              Button("Find original…") { state.findOriginal() }
            }
          }
        }
        if file == nil && document.editable {
          Button(document.editing ? "Done" : "Edit draft") {
            if document.editing { document.end() } else { document.begin() }
          }
        }
      }.padding(12)
      Divider()
      if let error = document.failure {
        VStack(alignment: .leading, spacing: 8) {
          Text(error).textSelection(.enabled)
          if document.dirty {
            ViewThatFits(in: .horizontal) {
              HStack { recoveryActions }
              VStack(alignment: .leading, spacing: 8) { recoveryActions }
            }
          }
        }.font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading)
        Divider()
      }
      if let newer = document.newerVersionID, !document.dirty {
        HStack {
          Text("Viewing an earlier version.").foregroundStyle(.secondary)
          Button("Open newer version") { state.navigate(.item(newer)) }
        }.font(.callout).padding(10)
        Divider()
      }
      if preview.loading {
        VStack(spacing: 12) {
          if preview.totalBytes > 0 {
            ProgressView(
              value: Double(min(preview.checkedBytes, preview.totalBytes)),
              total: Double(preview.totalBytes)
            )
            .frame(maxWidth: 260)
            Text("Checking original file")
            Text(
              ByteCountFormatter.string(fromByteCount: preview.checkedBytes, countStyle: .file)
                + " checked"
            )
            .font(.caption).foregroundStyle(.secondary)
          } else {
            ProgressView("Opening file")
          }
          Button("Stop") { preview.stop() }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let failure = preview.failure {
        ContentUnavailableView {
          Label("File unavailable", systemImage: "doc.badge.ellipsis")
        } description: {
          Text(failure)
        } actions: {
          Button("Retry preview") { preview.retry() }
        }
      } else if let file {
        let ext = file.pathExtension.lowercased()
        if ext == "pdf" {
          PDFWorkspace(
            url: file, locator: state.itemLocators[item.id],
            onPage: { page in
              guard state.workbook === workbook, state.viewedItemVersion == item.id else { return }
              state.itemLocators[item.id] = "page=\(page)"
            },
            onSelection: { state.selectedContext = $0 },
            onLink: { state.openConversationLink($0) })
        } else if ["mp4", "mov", "m4v", "mp3", "wav", "m4a", "aiff"].contains(ext) {
          VStack {
            NativeMediaPlayer(player: player).onAppear {
              guard state.interactionActive, state.workbook === workbook else { return }
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
              if let player { PlaybackRegistry.shared.register(player, owner: state.mediaOwner) }
            }
            Toggle("Keep playing while I explore", isOn: $keepPlaying).padding(10)
            TranscriptView(item: item.id, workbook: workbook, revision: state.revision) { seconds in
              player?.seek(
                to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero,
                toleranceAfter: .zero)
            }
          }.onDisappear {
            if !keepPlaying || !state.interactionActive {
              player?.releasePlayback()
              player = nil
            } else {
              if state.backgroundPlayer !== player { state.backgroundPlayer?.releasePlayback() }
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
          if ["csv", "tsv"].contains(file.pathExtension.lowercased()) {
            DelimitedFileViewer(file: file)
          } else {
            SafeTextViewer(file: file)
          }
        } else {
          QuickLookViewer(url: file)
        }
      } else if document.editing {
        TextEditor(text: Binding(get: { document.text }, set: { document.update($0) })).font(.body)
          .padding(
            16
          )
          .accessibilityLabel("Document draft")
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            Text(item.title).font(.title2)
            if let movementDirection {
              Text(movementDirection).font(.headline)
              if item.status == "draft" {
                Text("Check whether these units entered or left your stock before accepting.")
                  .foregroundStyle(.secondary)
              }
            }
            if let saved = references.document, saved.body.originVersionID == item.id {
              ReferenceReadingText(presentation: saved.presentation, open: openReference)
            } else {
              Text(item.text).textSelection(.enabled)
            }
            if item.kind == "calculation", item.data["evaluation"] != .null {
              SavedDefinitionResultView(item: item, workbook: workbook, workspace: state)
            }
            if let failure = references.failure {
              Text("Saved links are unavailable: " + failure).font(.caption).foregroundStyle(
                .secondary)
            }
            if item.kind == "link", let target = URL(string: item.data["url"].text) {
              Link("Open source website", destination: target)
            }
            if item.kind == "table-creation", item.status == "accepted",
              let id = item.data["datasetID"].string
            {
              Button("Open table") { state.navigate(.table(id)) }
            }
            if item.kind == "table-intake-update" {
              Text(
                item.status == "draft"
                  ? "Preview only. Working rows have not changed."
                  : item.status == "accepted"
                    ? "This update was applied. The preview below describes its original changes."
                    : isTableUpdateRedo
                      ? "This update was undone. The preview below describes its original changes."
                      : "This draft was withdrawn without applying it."
              )
              .font(.callout).foregroundStyle(.secondary)
              if let preview = try? JSONDecoder().decode(
                TableUpdatePreview.self, from: Data(item.data["preview"].json().utf8))
              {
                TableUpdateSummary(preview: preview)
              }
              Button("Open table") { state.navigate(.table(item.data["datasetID"].text)) }
            }
            if item.category == "source", item.kind == "request",
              let context = item.data["context"].string, !context.isEmpty
            {
              CapturedRequestContextView(context: context, state: state)
            }
            if !["table-change", "table-creation", "table-intake-update"].contains(item.kind) {
              Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(item.data.object.keys.sorted(), id: \.self) { key in
                  if !["input", "inputs", "supersedes", "datasetID", "url"].contains(key),
                    !(item.kind == "calculation" && item.data["evaluation"] != .null
                      && ["populationScope", "captured", "submittedInputs"].contains(key)),
                    !(item.kind == "movement"
                      && ["requestSourceID", "status", "meaning"].contains(key)),
                    !(item.category == "source" && item.kind == "request"
                      && (["conversationID", "messageID"].contains(key)
                        || (key == "context" && item.data["context"].string != nil))),
                    let value = scalarDetail(key)
                  {
                    GridRow {
                      Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                        .foregroundStyle(.secondary)
                      Text(value).textSelection(.enabled)
                    }
                  }
                }
              }.font(.callout)
            }
            copiedPassages
            lineage
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .background(
              DocumentScrollObserver(position: state.itemReading[item.id] ?? .init()) {
                state.itemReading[item.id] = $0
              })
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
    .sheet(item: $state.referenceModal) { modal in
      switch modal {
      case .browser:
        ReferencesPanel(
          item: item, workbook: workbook, session: references, state: state, open: openReference)
      case .choice(let occurrence):
        ReferenceTargetPicker(
          item: item, occurrence: occurrence, workbook: workbook,
          revision: state.revision
        ) { target, token in
          guard let saved = references.document, saved.body.originVersionID == item.id,
            state.workbook === workbook,
            state.interactionActive, !state.busy, document.current.id == occurrence.origin,
            !document.dirty
          else {
            throw SevraError("workspace_changed", "Refresh this document before changing a link.")
          }
          let original = item
          let updated = try await Task.detached(priority: .userInitiated) {
            try saved.choose(
              occurrence, target: target, item: original, workbook: workbook,
              token: token, cancellation: Cancellation(deadlineAfterSeconds: 3))
          }.value
          guard state.workbook === workbook, state.interactionActive else { return }
          state.refresh()
          if document.current.id == original.id && state.viewedItemVersion == original.id {
            if updated.id != original.id {
              state.navigate(.item(updated.id))
            } else {
              await references.load(original, workbook: workbook)
            }
          }
        }
      }
    }
    .task(id: "\(item.id):\(state.revision)") {
      await references.load(item, workbook: workbook)
    }
    .onAppear {
      if item.assetID != nil { state.activePreview = preview }
      state.documentDrafts.register(document)
      state.activeDocument = document
      state.viewedItemVersion = item.id
      document.changed = { [weak state, weak document] in
        guard let state, let document else { return }
        state.viewedItemVersion = document.current.id
        state.refresh()
      }
      document.refreshHead()
    }
    .onChange(of: state.revision) { _, _ in document.refreshHead() }
    .onDisappear {
      references.cancel()
      linkNavigation?.cancel()
      preview.cancel()
      if state.activePreview === preview { state.activePreview = nil }
      document.flush()
      document.changed = nil
      if state.activeDocument === document { state.activeDocument = nil }
      if state.viewedItemVersion == item.id { state.viewedItemVersion = nil }
    }
    .task(id: "\(item.id):\(preview.reloadID)") {
      guard !Task.isCancelled, let assetID = item.assetID,
        state.workbook === workbook, state.interactionActive
      else { return }
      // Retry/relink must not retain or continue playing the previously verified
      // file while a new verification is pending or has failed.
      player?.releasePlayback()
      player = nil
      keepPlaying = false
      // Keep external-file recovery available even when the original is missing.
      asset = try? workbook.asset(assetID)
      preview.isExternal = asset?.mode == "linked"
      let chosen = preview.originalURL
      let identity = preview.reloadID
      let book = workbook
      let resolved = await preview.load { cancel, progress in
        try await Task.detached {
          if let chosen {
            return try book.relinkAsset(
              assetID, to: chosen, cancellation: cancel, progress: progress)
          }
          return try book.assetURL(assetID, cancellation: cancel, progress: progress)
        }.value
      }
      if resolved, preview.reloadID == identity, chosen != nil,
        state.workbook === workbook, state.interactionActive
      {
        preview.didResolve(identity)
        state.refresh()
      }
    }
  }
  private var isTableUpdateRedo: Bool {
    item.kind == "table-intake-update" && item.status == "rejected"
      && item.data["afterFingerprint"].string != nil
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
  @ViewBuilder private var copiedPassages: some View {
    let provenance = DocumentProvenance.make(item)
    if provenance.unavailable {
      Text("Copy information is unavailable. Earlier versions remain in Evidence and history.")
        .font(.callout).foregroundStyle(.secondary)
    } else if !provenance.passages.isEmpty {
      Divider()
      DisclosureGroup("Copied passages (\(provenance.passages.count))") {
        VStack(alignment: .leading, spacing: 16) {
          Text(
            "Each link opens the exact version used in this document. It may be an earlier version."
          )
          .font(.caption).foregroundStyle(.secondary)
          ForEach(provenance.passages) { passage in
            VStack(alignment: .leading, spacing: 6) {
              Text(verbatim: passage.text).lineLimit(3).textSelection(.enabled)
              if !passage.locator.isEmpty {
                Text(passage.locator).font(.caption).foregroundStyle(.secondary).lineLimit(2)
              }
              Button("Open original passage") {
                state.openEvidence(passage.sourceVersionID, locator: passage.locator)
              }
              .buttonStyle(.link)
              .accessibilityLabel("Open original passage \(passage.id + 1)")
            }
          }
        }.padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
  @ViewBuilder private var recoveryActions: some View {
    Button("Retry save") { document.flush() }
    Button("Keep my changes as a separate draft") { document.keepSeparate() }
    Button("Copy text") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(document.text, forType: .string)
    }
  }
  private func openReference(_ occurrence: ReferenceOccurrence) {
    guard let saved = references.document, saved.body.originVersionID == item.id,
      state.workbook === workbook,
      state.interactionActive, document.end()
    else { return }
    if occurrence.reference.resolution == .unresolved {
      if item.category == "source" || (item.kind == "document" && item.assetID == nil) {
        state.referenceChoice = occurrence
      } else {
        state.referenceModal = nil
        state.error =
          "This link has no chosen destination. Change this record through a new record version."
      }
      return
    }
    state.referenceModal = nil
    let navigation = state.itemPreviewIdentity
    linkNavigation?.cancel()
    let control = Cancellation(deadlineAfterSeconds: 3)
    linkNavigation = control
    Task {
      do {
        let result = try await Task.detached(priority: .userInitiated) {
          try saved.resolve(occurrence, workbook: workbook, cancellation: control)
        }.value
        guard !control.isCancelled, state.workbook === workbook, state.interactionActive,
          state.itemPreviewIdentity == navigation
        else { return }
        if let target = result["destination"]["id"].string {
          state.openEvidence(target)
        } else {
          state.error = result["detail"].string ?? "This saved link is unavailable."
        }
      } catch {
        guard !control.isCancelled, state.itemPreviewIdentity == navigation else { return }
        state.error = error.localizedDescription
      }
    }
  }
}
@MainActor final class PDFControls: ObservableObject {
  weak var view: PDFView?
  @Published var page = 1
  @Published var pages = 0
  @Published var query = ""
  @Published var status = ""
  @Published var unavailable = false
  private var previousQuery = ""
  private var lastPage = -1
  private var lastEnd = 0
  func refresh() {
    unavailable = view?.document == nil
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
  let onPage: (Int) -> Void
  let onSelection: (String) -> Void
  let onLink: (URL) -> Void
  @StateObject private var controls = PDFControls()
  var body: some View {
    VStack(spacing: 0) {
      if !controls.unavailable {
        HStack {
          if controls.pages > 1 {
            Button {
              controls.view?.goToPreviousPage(nil)
            } label: {
              Image(systemName: "chevron.up")
            }.accessibilityLabel("Previous PDF page").help("Previous PDF page")
              .disabled(controls.page <= 1)
            Button {
              controls.view?.goToNextPage(nil)
            } label: {
              Image(systemName: "chevron.down")
            }.accessibilityLabel("Next PDF page").help("Next PDF page")
              .disabled(controls.page >= controls.pages)
          }
          if controls.pages > 0 {
            Text(controls.pages == 1 ? "1 page" : "\(controls.page) / \(controls.pages)")
              .font(.caption).monospacedDigit()
              .accessibilityLabel("Page \(controls.page) of \(controls.pages)")
          }
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
      }
      PDFViewer(
        url: url, locator: locator, onSelection: onSelection, onLink: onLink, controls: controls)
        .overlay {
          if controls.unavailable {
            ContentUnavailableView(
              "PDF preview unavailable", systemImage: "doc.badge.ellipsis",
              description: Text(
                "This file could not be opened as a PDF. Use File actions to open a copy in another app."
              )
            ).frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(Color(nsColor: .windowBackgroundColor))
          }
        }
    }
    .onChange(of: controls.page) { _, page in onPage(page) }
  }
}
struct TranscriptLine: Identifiable, Sendable {
  let id: Int
  let seconds: Double
  let text: String
  /// Only a transcript's chunks carry a time.
  init?(_ chunk: Value) {
    let locator = chunk["locator"].text
    guard let id = chunk["id"].int, let range = locator.range(of: "^time=[0-9.]+", options: .regularExpression),
      let seconds = Double(locator[range].dropFirst(5))
    else { return nil }
    self.id = id
    self.seconds = seconds
    text = chunk["body"].text
  }
}

/// What Transcribe heard, in order. Choosing a time moves the player there.
struct TranscriptView: View {
  let item: String
  let workbook: Workbook
  let revision: Int
  let seek: (Double) -> Void
  @State private var lines: [TranscriptLine] = []
  private func clock(_ seconds: Double) -> String { DisplayText.clock(seconds) ?? "" }
  private func load() async {
    let book = workbook
    let id = item
    let found = await Task.detached { () -> [TranscriptLine] in
      var read = 0
      var rows: [TranscriptLine] = []
      while let page = try? book.readChunks(id, offset: read, limit: 12), !page.isEmpty {
        read += page.count
        rows += page.compactMap(TranscriptLine.init)
      }
      return rows
    }.value
    lines = found
  }
  var body: some View {
    VStack(spacing: 0) {
      Color.clear.frame(height: 0)
      if !lines.isEmpty {
        Divider()
        HStack {
          Text("Transcript").font(.headline)
          Spacer()
          Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
              lines.map(\.text).joined(separator: " "), forType: .string)
          }.help("Copy the whole transcript")
        }.padding(.horizontal, 12).padding(.top, 8)
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(lines) { line in
              HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button(clock(line.seconds)) { seek(line.seconds) }
                  .buttonStyle(.link).monospacedDigit().frame(width: 56, alignment: .trailing)
                  .accessibilityLabel("Go to \(clock(line.seconds))")
                Text(line.text).textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }.padding(12)
        }.frame(maxHeight: .infinity)
      }
    }.task(id: "\(item) \(revision)") { await load() }
  }
}

@MainActor struct PDFViewer: NSViewRepresentable {
  let url: URL
  let locator: String?
  let onSelection: (String) -> Void
  let onLink: (URL) -> Void
  let controls: PDFControls
  func makeCoordinator() -> Coordinator {
    Coordinator(onSelection, onLink: onLink, controls: controls)
  }
  func makeNSView(context: Context) -> PDFView {
    let view = PDFView()
    view.delegate = context.coordinator
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    context.coordinator.navigation.apply(view, url: url, locator: locator)
    controls.view = view
    context.coordinator.observe(view)
    DispatchQueue.main.async { controls.refresh() }
    return view
  }
  func updateNSView(_ view: PDFView, context: Context) {
    context.coordinator.navigation.apply(view, url: url, locator: locator)
  }
  @MainActor final class Coordinator: NSObject, @preconcurrency PDFViewDelegate {
    let callback: (String) -> Void
    let onLink: (URL) -> Void
    var token: NSObjectProtocol?
    var pageToken: NSObjectProtocol?
    let controls: PDFControls
    let navigation = PDFReadingNavigation()
    init(
      _ callback: @escaping (String) -> Void, onLink: @escaping (URL) -> Void,
      controls: PDFControls
    ) {
      self.callback = callback
      self.onLink = onLink
      self.controls = controls
    }
    // Left to its default, PDFView opens a link of any scheme directly.
    func pdfViewWillClick(onLink sender: PDFView, with url: URL) { onLink(url) }
    func observe(_ view: PDFView) {
      pageToken = NotificationCenter.default.addObserver(
        forName: .PDFViewPageChanged, object: view, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.controls.refresh() } }
      token = NotificationCenter.default.addObserver(
        forName: .PDFViewSelectionChanged, object: view, queue: .main
      ) { [weak self, weak view] _ in
        MainActor.assumeIsolated {
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
          .disabled(scale <= 0.25)
        Button("Zoom in") { scale = min(6, scale * 1.25) }
          .disabled(scale >= 6)
        if scale != 1 {
          Button("Reset zoom") { scale = 1 }
        }
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
struct DelimitedFileViewer: View {
  let file: URL
  @State private var preview: DelimitedPreview?
  @State private var failure: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let preview {
        Text(preview.detail).font(.caption).foregroundStyle(.secondary)
        if preview.table.headings.isEmpty {
          ContentUnavailableView(
            "Empty table", systemImage: "tablecells",
            description: Text("The original file has no values."))
        } else {
          ReadOnlyTableView(content: preview.table, label: "Original table values")
        }
      } else if let failure {
        ContentUnavailableView(
          "Table preview unavailable", systemImage: "tablecells",
          description: Text(failure + " The original remains available through File actions."))
      } else {
        ProgressView("Reading table values…").frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }.padding(20).task(id: file) {
      preview = nil
      failure = nil
      let token = Cancellation()
      do {
        let result = try await withTaskCancellationHandler {
          try await Task.detached { try DelimitedPreview.load(file, cancellation: token) }.value
        } onCancel: {
          token.cancel()
        }
        try Task.checkCancellation()
        preview = result
      } catch {
        guard !Task.isCancelled else { return }
        failure = error.localizedDescription
      }
    }
  }
}
struct SafeTextViewer: View {
  let file: URL
  @State private var text = ""
  @State private var detail = ""
  @State private var structured: Value?
  var body: some View {
    ScrollView {
      if let structured {
        StructuredValueView(value: structured).padding(20)
      } else if file.pathExtension.lowercased() != "json" {
        Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(
          maxWidth: .infinity, alignment: .leading
        ).padding(20)
      }
      if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).padding(10) }
    }.task(id: file) {
      guard !Task.isCancelled else { return }
      text = ""
      detail = ""
      structured = nil
      do {
        let result = try await Task.detached { () -> (String, String, Value?) in
          let handle = try FileHandle(forReadingFrom: file)
          defer { try? handle.close() }
          let bytes = try handle.read(upToCount: 1_000_001) ?? Data()
          if file.pathExtension.lowercased() == "json" {
            guard bytes.count <= 1_000_000 else {
              return (
                "",
                "This file exceeds the 1 MB structured preview limit. Open a copy to inspect the original.",
                nil
              )
            }
            guard let source = String(data: bytes, encoding: .utf8),
              let value = StructuredPresentation.parseJSON(source)
            else {
              return (
                "",
                "This file could not be read as structured data. The original remains available through Open a copy.",
                nil
              )
            }
            return ("", "", value)
          }
          return (
            String(decoding: bytes.prefix(1_000_000), as: UTF8.self),
            bytes.count > 1_000_000
              ? "Previewing the first 1 MB. The original file remains intact." : "", nil
          )
        }.value
        try Task.checkCancellation()
        text = result.0
        detail = result.1
        structured = result.2
      } catch {
        guard !Task.isCancelled else { return }
        detail = error.localizedDescription
      }
    }
  }
}
