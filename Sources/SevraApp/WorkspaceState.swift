import AVKit
import AppKit
import Foundation
import SevraAI
import SevraCore
import SevraDocumentUI
import SevraPreviewUI
import SevraProduct
import SevraSearchUI
import SevraVoice
import Speech
import SwiftUI

@MainActor final class WorkspaceState: ObservableObject {
  enum Route: Equatable {
    case space(String)
    case item(String)
    case table(String)
    case search
  }
  @Published var workbook: Workbook?
  @Published var spaces: [Space] = []
  @Published var items: [ItemSummary] = []
  @Published var datasets: [Dataset] = []
  @Published var messages: [Message] = []
  @Published var conversations: [Value] = []
  @Published var conversation = "main" {
    didSet { if conversation != oldValue { speech.stop() } }
  }
  @Published var route: Route = .space("home")
  @Published var navigation: [Route] = []
  @Published var viewedItemVersion: String?
  @Published var itemPreviewIdentity = UUID()
  weak var activeDocument: DocumentDraft?
  weak var activePreview: AssetPreviewSession?
  let documentDrafts = DocumentDraftScope()
  @Published var prompt = "" {
    didSet { if prompt != oldValue && !applyingDictation { speech.stop() } }
  }
  @Published var busy = false
  @Published var status = ""
  @Published var error: String?
  @Published var selectedContext = "" {
    didSet { selectionLabel = nil }
  }
  @Published var selectionLabel: String?
  @Published var itemLocators: [String: String] = [:]
  @Published var messageAnchor: String?
  @Published var revision = 0
  @Published var focus = false
  @Published var backgroundPlayer: AVPlayer?
  @Published var backgroundMediaTitle = ""
  @Published var searchQuery = ""
  @Published var searchHistorical = false
  @Published var searchKind = ""
  @Published var searchMeaning = ""
  @Published var searchStatus = ""
  @Published var searchScenario = ""
  let searchResults = SearchSession()
  @Published var tableOffsets: [String: Int] = [:]
  @Published var tableFilters: [String: String] = [:]
  @Published var tableSorts: [String: String] = [:]
  @Published var tableDescending: [String: Bool] = [:]
  @Published var tableUndo: [String: String] = [:]
  @Published var tableRedo: [String: String] = [:]
  @Published var spaceScroll: [String: String] = [:]
  private let operations = WorkspaceOperationScope()
  private var awaitingSpeechPermission: WorkspaceOperation?
  let mediaOwner = UUID()
  private(set) var interactionActive = false
  private(set) var interactionIdentity = UUID()
  private var applyingDictation = false
  let speech = SpeechInput(pausePlayback: { PlaybackRegistry.shared.pauseAll() })
  func open(_ url: URL) throws {
    let opened = try Workbook(url)
    try require(
      documentDrafts.flush(), "document_save",
      "Save or preserve the current draft before opening another workbook.")
    endInteraction()
    workbook = opened
    conversation = "main"
    route = .space("home")
    navigation = []
    itemPreviewIdentity = UUID()
    viewedItemVersion = nil
    activeDocument = nil
    prompt = ""
    selectedContext = ""
    itemLocators = [:]
    messageAnchor = nil
    error = nil
    searchQuery = ""
    searchHistorical = false
    searchKind = ""
    searchMeaning = ""
    searchStatus = ""
    searchScenario = ""
    searchResults.reset()
    tableOffsets = [:]
    tableFilters = [:]
    tableSorts = [:]
    tableDescending = [:]
    tableUndo = [:]
    tableRedo = [:]
    spaceScroll = [:]
    beginInteraction()
    refresh()
  }
  func refresh() {
    guard let book = workbook else { return }
    do {
      revision = try book.revision()
      spaces = try book.spaces()
      items = try book.recentItemSummaries()
      datasets = try book.datasets()
      messages =
        try messageAnchor.map { try book.messages(around: $0) }
        ?? book.messages(conversation: conversation)
      conversations = try book.conversations()
    } catch { self.error = error.localizedDescription }
  }
  func poll() {
    guard !busy, let book = workbook else { return }
    if (try? book.revision()) != revision { refresh() }
  }
  func navigate(_ new: Route) {
    guard documentDrafts.flush() else { return }
    let shown: Route
    if case .item(let id) = route { shown = .item(viewedItemVersion ?? id) } else { shown = route }
    if shown != new {
      navigation.append(shown)
      if navigation.count > 20 { navigation.removeFirst() }
      route = new
      viewedItemVersion = nil
      itemPreviewIdentity = UUID()
      selectedContext = ""
    }
  }
  func openEvidence(_ id: String, locator: String? = nil) {
    if let locator { itemLocators[id] = locator }
    navigate(.item(id))
  }
  func jumpToMessage(_ id: String) {
    do {
      let location = try workbook?.messageLocation(id)
      conversation = location?["conversation_id"].text ?? "main"
      messageAnchor = id
      refresh()
    } catch { self.error = error.localizedDescription }
  }
  func back() {
    guard documentDrafts.flush() else { return }
    if let prior = navigation.popLast() {
      route = prior
      viewedItemVersion = nil
      itemPreviewIdentity = UUID()
      selectedContext = ""
    }
  }
  func run(_ title: String, operation: @escaping @Sendable (Workbook, Cancellation) throws -> Void)
  {
    run(title, operation: operation, completion: { _ in })
  }
  func run<Result: Sendable>(
    _ title: String, operation: @escaping @Sendable (Workbook, Cancellation) throws -> Result,
    completion: @escaping @MainActor (Result) -> Void
  ) {
    guard let (book, ticket) = beginOperation(title) else { return }
    Task {
      defer { finishOperation(ticket, in: book) }
      do {
        let result = try await Task.detached(priority: .userInitiated) {
          try ticket.cancellation.check()
          return try operation(book, ticket.cancellation)
        }.value
        guard owns(ticket, in: book) else { return }
        completion(result)
      } catch { report(error, for: ticket, in: book) }
    }
  }
  private func beginOperation(_ title: String) -> (Workbook, WorkspaceOperation)? {
    guard interactionActive, let book = workbook, !busy, let ticket = operations.begin() else {
      return nil
    }
    busy = true
    status = title
    error = nil
    return (book, ticket)
  }
  private func owns(_ ticket: WorkspaceOperation, in book: Workbook) -> Bool {
    interactionActive && workbook === book && operations.owns(ticket)
  }
  private func finishOperation(_ ticket: WorkspaceOperation, in book: Workbook) {
    guard owns(ticket, in: book), operations.finish(ticket) else { return }
    busy = false
    status = ""
    refresh()
  }
  private func report(_ failure: Error, for ticket: WorkspaceOperation, in book: Workbook) {
    guard owns(ticket, in: book) else { return }
    error = failure.localizedDescription
  }
  func pinSpace(_ id: String, title: String) {
    guard !busy, documentDrafts.flush(), let (book, ticket) = beginOperation("Saving a pinned copy")
    else { return }
    let navigationID = itemPreviewIdentity
    let chat = conversation
    Task {
      defer { finishOperation(ticket, in: book) }
      do {
        let saved = try await Task.detached(priority: .userInitiated) {
          try book.pinSpace(id, title: title, cancellation: ticket.cancellation)
        }.value
        guard owns(ticket, in: book) else { return }
        refresh()
        if conversation == chat, itemPreviewIdentity == navigationID { navigate(.space(saved)) }
      } catch { report(error, for: ticket, in: book) }
    }
  }
  func importPanel(linked: Bool = false) {
    guard interactionActive, !busy, let book = workbook else { return }
    let chat = conversation
    let identity = interactionIdentity
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK, interactionActive, workbook === book,
      conversation == chat, interactionIdentity == identity
    else { return }
    importFiles(panel.urls, linked: linked)
  }
  func importFiles(_ urls: [URL], linked: Bool = false) {
    let chat = conversation
    run(linked ? "Linking files" : "Including files") { book, cancel in
      var failures: [String] = []
      for url in urls {
        try cancel.check()
        do {
          let item = try book.importFile(url, linked: linked, cancellation: cancel)
          _ = try book.addMessage(
            (linked ? "Linked " : "Included ") + item.referenceMarkdown, role: "event",
            conversation: chat)
          try book.extract(item.id, cancellation: cancel)
          if ["csv", "tsv"].contains(url.pathExtension.lowercased()) {
            _ = try book.importCSV(item.id, cancellation: cancel)
          }
          if url.pathExtension.lowercased() == "xlsx" {
            _ = try book.importXLSX(item.id, cancellation: cancel)
          }
        } catch {
          if cancel.isCancelled { throw error }
          failures.append(url.lastPathComponent + ": " + error.localizedDescription)
        }
      }
      if !failures.isEmpty { throw SevraError("import_partial", failures.joined(separator: "\n")) }
    }
  }
  func exportPanel() {
    guard interactionActive, !busy, let book = workbook, documentDrafts.flush() else { return }
    let identity = interactionIdentity
    let panel = NSSavePanel()
    panel.title = "Make a shareable copy"
    panel.nameFieldStringValue = book.title + ".sevraz"
    if panel.runModal() == .OK, let url = panel.url, interactionActive, workbook === book,
      interactionIdentity == identity
    {
      run("Making a shareable copy") { book, cancel in
        try book.export(to: url, cancellation: cancel)
      }
    }
  }
  var canSend: Bool {
    WorkspaceControlCommand.allowsSubmission(prompt, busy: busy)
  }
  func send() {
    guard interactionActive, let book = workbook, canSend,
      !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    speech.stop()
    let input = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if let command = WorkspaceControlCommand.parse(input) {
      prompt = ""
      control(command, input: input, book: book)
      return
    }
    if documentCommand(input, book: book) {
      prompt = ""
      refresh()
      return
    }
    guard documentDrafts.flush() else { return }
    prompt = ""
    error = nil
    messageAnchor = nil
    if let target = URL(string: input), ["http", "https"].contains(target.scheme ?? "") {
      guard let (_, ticket) = beginOperation("Capturing source") else { return }
      let chat = conversation
      let navigationID = itemPreviewIdentity
      Task {
        defer { finishOperation(ticket, in: book) }
        do {
          let source = try await book.captureURL(target, cancellation: ticket.cancellation)
          _ = try book.addMessage(
            (source.assetID == nil ? "Saved reference: " : "Captured ") + source.referenceMarkdown,
            role: "event", conversation: chat)
          guard owns(ticket, in: book) else { return }
          if conversation == chat, itemPreviewIdentity == navigationID {
            navigate(.item(source.id))
          }
        } catch { report(error, for: ticket, in: book) }
      }
      return
    }
    if localCommand(input, book: book) {
      _ = try? book.addMessage(input, role: "user", conversation: conversation)
      refresh()
      return
    }
    guard let (_, ticket) = beginOperation("Preparing local AI") else { return }
    let chat = conversation
    let navigationID = itemPreviewIdentity
    let context = agentContext + (selectedContext.isEmpty ? "" : "\nSelection: " + selectedContext)
    let path =
      UserDefaults.standard.string(forKey: ProductAI.preferenceKey).map { URL(fileURLWithPath: $0) }
      ?? ProductAI.defaultDirectory
    Task {
      defer { finishOperation(ticket, in: book) }
      do {
        let result = try await ProductAI.shared.run(
          input, workbook: book, conversation: chat, context: context, modelDirectory: path,
          cancellation: ticket.cancellation,
          progress: { value in
            Task { @MainActor in
              guard self.owns(ticket, in: book), self.operations.acceptsProgress(ticket) else {
                return
              }
              self.status = value
              self.refresh()
            }
          })
        guard owns(ticket, in: book) else { return }
        refresh()
        if conversation == chat, itemPreviewIdentity == navigationID, let focus = result.focus {
          navigate(focus.kind == "space" ? .space(focus.id) : .item(focus.id))
        }
      } catch { report(error, for: ticket, in: book) }
    }
  }
  var agentContext: String {
    switch route {
    case .space(let id): return routeContext + "\nActive space ID: " + id
    case .item(let id):
      return routeContext + "\nActive item version ID: " + (viewedItemVersion ?? id)
    case .table(let id): return routeContext + "\nActive dataset ID: " + id
    case .search: return routeContext
    }
  }
  var routeContext: String {
    switch route {
    case .space(let id): return "Space: " + (spaces.first { $0.id == id }?.title ?? id)
    case .item(let id):
      return "Item: " + ((try? workbook?.item(viewedItemVersion ?? id).title) ?? id)
    case .table(let id): return "Table: " + (datasets.first { $0.id == id }?.title ?? id)
    case .search: return "Workbook search"
    }
  }
  func localCommand(_ input: String, book: Workbook) -> Bool {
    let lower = input.lowercased()
    do {
      if lower == "go home" || lower == "home" {
        navigate(.space("home"))
        return true
      }
      if lower == "back" {
        back()
        return true
      }
      if lower == "import files" || lower == "add files" {
        importPanel()
        return true
      }
      if lower == "link files" {
        importPanel(linked: true)
        return true
      }
      if lower == "make a shareable copy" || lower == "export workbook" {
        exportPanel()
        return true
      }
      if lower == "back to main" {
        conversation = "main"
        return true
      }
      if lower.hasPrefix("open "),
        let space = spaces.first(where: { $0.title.lowercased() == String(lower.dropFirst(5)) })
      {
        navigate(.space(space.id))
        return true
      }
      if ["accept this", "accept that"].contains(lower), case .item(let id) = route {
        review(viewedItemVersion ?? id, accepting: true)
        return true
      }
      if ["undo this", "undo that"].contains(lower), case .item(let id) = route {
        review(viewedItemVersion ?? id, accepting: false)
        return true
      }
      if lower == "transcribe this", case .item(let id) = route {
        transcribe(id)
        return true
      }
      if lower == "include this", case .item(let id) = route {
        run("Including original") { book, cancel in
          _ = try book.includeLinked(id, cancellation: cancel)
        }
        return true
      }
      if lower.hasPrefix("accept ") {
        review(String(input.dropFirst(7)), accepting: true)
        return true
      }
      if lower.hasPrefix("undo ") {
        review(String(input.dropFirst(5)), accepting: false)
        return true
      }
      if lower.hasPrefix("chapter "), let message = messages.last {
        try book.chapter(title: String(input.dropFirst(8)), message: message.id)
        return true
      }
      if lower.hasPrefix("tangent "), let message = messages.last {
        conversation = try book.tangent(
          title: String(input.dropFirst(8)), parentMessage: message.id)
        return true
      }
    } catch {
      self.error = error.localizedDescription
      return true
    }
    return false
  }
  private func documentCommand(_ input: String, book: Workbook) -> Bool {
    let lower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let separate = lower == "keep my changes as a separate draft"
    guard separate || ["save this document", "save document", "retry saving"].contains(lower),
      let draft = activeDocument, draft.editable
    else { return false }
    do {
      _ = try book.addMessage(input, role: "user", conversation: conversation)
      let saved = separate ? draft.keepSeparate() : draft.flush()
      if saved {
        _ = try book.addMessage(
          "Saved " + draft.current.referenceMarkdown, role: "event", conversation: conversation)
      } else {
        error = draft.failure
      }
    } catch { self.error = error.localizedDescription }
    return true
  }
  func review(_ id: String, accepting: Bool) {
    guard let (book, ticket) = beginOperation(accepting ? "Accepting changes" : "Undoing changes")
    else { return }
    let chat = conversation
    let navigationID = itemPreviewIdentity
    Task {
      defer { finishOperation(ticket, in: book) }
      do {
        let record = try await Task.detached {
          try ticket.cancellation.check()
          return accepting ? try book.accept(id) : try book.undoItem(id)
        }.value
        _ = try book.addMessage(
          (accepting ? "Accepted " : "Undid the last change to ") + record.referenceMarkdown,
          role: "event", conversation: chat)
        guard owns(ticket, in: book) else { return }
        refresh()
        if conversation == chat, itemPreviewIdentity == navigationID { navigate(.item(record.id)) }
      } catch { report(error, for: ticket, in: book) }
    }
  }
  func transcribe(_ id: String) {
    guard let (book, ticket) = beginOperation("Preparing on-device transcription") else { return }
    speech.stop()
    PlaybackRegistry.shared.pauseAll()
    awaitingSpeechPermission = ticket
    SFSpeechRecognizer.requestAuthorization { authorization in
      Task { @MainActor in
        guard self.owns(ticket, in: book) else { return }
        self.awaitingSpeechPermission = nil
        defer { self.finishOperation(ticket, in: book) }
        do {
          try ticket.cancellation.check()
          try require(
            authorization == .authorized, "speech_permission",
            "Speech recognition permission was not granted. The original remains available.")
          self.status = "Transcribing on this Mac"
          try await book.transcribe(id, cancellation: ticket.cancellation)
        } catch { self.report(error, for: ticket, in: book) }
      }
    }
  }
  func stop() {
    speech.stop()
    operations.cancel()
    // A system permission prompt cannot be dismissed programmatically. Release
    // our waiting UI immediately; its late response no longer owns this window.
    if let pending = awaitingSpeechPermission, operations.owns(pending), let book = workbook {
      awaitingSpeechPermission = nil
      finishOperation(pending, in: book)
    }
    if activePreview?.loading == true { activePreview?.stop() }
    if busy { status = "Stopping…" }
  }
  private func control(_ command: WorkspaceControlCommand, input: String, book: Workbook) {
    let notice: String
    switch command {
    case .stop:
      let active = busy || activePreview?.loading == true
      stop()
      notice =
        active ? "Stop requested. Completed changes remain saved." : "No operation is running."
    case .stopPreview:
      guard let preview = activePreview else {
        error = "Open a file preview first."
        return
      }
      if preview.loading {
        preview.stop()
        notice = "Preview stopped. The original file is unchanged."
      } else {
        notice = "No file is opening."
      }
    case .retryPreview:
      guard let preview = activePreview else {
        error = "Open a file preview first."
        return
      }
      preview.retry()
      notice = "Opening the file again."
    case .findOriginal:
      findOriginal()
      notice = "Find original requested. The selected file must match the recorded bytes."
    }
    do {
      _ = try book.addMessage(input, role: "user", conversation: conversation)
      _ = try book.addMessage(notice, role: "event", conversation: conversation)
      refresh()
    } catch { self.error = error.localizedDescription }
  }
  func findOriginal() {
    guard let preview = activePreview, preview.isExternal, interactionActive,
      let book = workbook
    else {
      error = "Open an external file reference first."
      return
    }
    let panel = NSOpenPanel()
    panel.title = "Find the original file"
    guard panel.runModal() == .OK, let url = panel.url,
      activePreview === preview, workbook === book, interactionActive
    else { return }
    preview.reconnect(to: url)
  }
  func changeConversation(_ id: String) {
    conversation = id
    messageAnchor = nil
    refresh()
  }
  func voice() {
    guard interactionActive else { return }
    if speech.active {
      speech.stop()
      return
    }
    var draft = DictationDraft(prompt)
    let chat = conversation
    speech.start { [weak self] text in
      guard let self else { return }
      guard self.conversation == chat, let rendered = draft.apply(text, to: self.prompt) else {
        self.speech.stop()
        return
      }
      self.applyingDictation = true
      self.prompt = rendered
      self.applyingDictation = false
    } failure: { [weak self] error in
      self?.error = error
    }
  }
  func beginInteraction() { interactionActive = true }
  func endInteraction() {
    interactionActive = false
    interactionIdentity = UUID()
    operations.invalidate()
    awaitingSpeechPermission = nil
    busy = false
    status = ""
    activePreview?.cancel()
    activePreview = nil
    searchResults.reset()
    speech.stop()
    PlaybackRegistry.shared.close(owner: mediaOwner)
    backgroundPlayer?.pause()
    backgroundPlayer = nil
    backgroundMediaTitle = ""
  }
}
