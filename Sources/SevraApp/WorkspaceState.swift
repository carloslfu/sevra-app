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

@MainActor private final class AssetCopySaveDelegate: NSObject, NSOpenSavePanelDelegate {
  let workbook: Workbook
  init(workbook: Workbook) { self.workbook = workbook }
  func panel(_ sender: Any, validate url: URL) throws {
    _ = try workbook.assetCopyDestination(url)
  }
}

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
  @Published var hasEarlierMessages = false
  @Published var hasLaterMessages = false
  @Published var showingHistorySearch = false
  let historySearch = ConversationHistorySearch()
  @Published var conversations: [Value] = []
  @Published var conversationDraft: ConversationDraft?
  @Published var summaryDraft: ConversationSummaryDraft?
  @Published var composerFocusRequest = UUID()
  @Published var chapters: [Value] = []
  @Published var bookmarks: [Value] = []
  @Published var pendingExtractions: [Value] = []
  @Published var intakeStatus: [Value] = []
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
  let conversationSession = ConversationSession()
  @Published private(set) var changingConversation = false
  @Published var readingRequest = UUID()
  private var restoringConversation = false
  @Published var prompt = "" {
    didSet {
      if prompt != oldValue && !applyingDictation { speech.stop() }
      if !restoringConversation { conversationSession.updateDraft(prompt) }
    }
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
  private let refreshSession = WorkspaceRefreshSession()
  private var loadedRefreshIdentity: WorkspaceReadIdentity?
  private var awaitingSpeechPermission: WorkspaceOperation?
  let mediaOwner = UUID()
  private(set) var interactionActive = false
  private(set) var interactionIdentity = UUID()
  private var applyingDictation = false
  let speech = SpeechInput(pausePlayback: { PlaybackRegistry.shared.pauseAll() })
  func open(_ url: URL) async throws {
    let opened = try Workbook(url)
    try require(
      documentDrafts.flush(), "document_save",
      "Save or preserve the current draft before opening another workbook.")
    speech.stop()
    let restored = await conversationSession.open(
      opened,
      conversation: UserDefaults.standard.string(forKey: "lastConversation:" + opened.url.path)
        ?? "main")
    try require(
      restored, "conversation_save",
      conversationSession.failure ?? "Could not restore the conversation draft.")
    endInteraction()
    workbook = opened
    spaces = []
    items = []
    datasets = []
    messages = []
    conversations = []
    chapters = []
    bookmarks = []
    pendingExtractions = []
    intakeStatus = []
    revision = 0
    conversation = conversationSession.conversation
    route = .space("home")
    navigation = []
    itemPreviewIdentity = UUID()
    viewedItemVersion = nil
    activeDocument = nil
    restoreConversationPresentation()
    selectedContext = ""
    itemLocators = [:]
    messageAnchor = conversationSession.state.reading.message
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
  init() {
    conversationSession.changed = { [weak self] in self?.objectWillChange.send() }
    conversationSession.restoredDraft = { [weak self] draft in
      guard let self else { return }
      self.restoringConversation = true
      self.prompt = draft
      self.restoringConversation = false
    }
  }
  private func restoreConversationPresentation() {
    restoringConversation = true
    prompt = conversationSession.state.draft
    restoringConversation = false
    messageAnchor = conversationSession.state.reading.message
    readingRequest = UUID()
  }
  func refresh() { requestRefresh(polling: false) }
  func poll() {
    guard !busy else { return }
    requestRefresh(polling: true)
  }
  private func requestRefresh(polling: Bool, pageAnchor: String? = nil) {
    guard interactionActive, let book = workbook else { return }
    let identity = WorkspaceReadIdentity(
      workbook: book, window: interactionIdentity, conversation: conversation,
      messageAnchor: messageAnchor)
    let changedView = refreshSession.identity != identity
    if changedView && refreshSession.identity?.conversation != conversation {
      messages = []
      hasEarlierMessages = false
      hasLaterMessages = false
    }
    let readingAnchor = pageAnchor ?? conversationSession.state.reading.message
    let knownRevision = polling && loadedRefreshIdentity == identity ? revision : nil
    refreshSession.request(identity: identity, onlyWhenIdle: polling && !changedView) { control in
      try book.workspaceSnapshot(
        conversation: identity.conversation, messageAnchor: readingAnchor,
        ifChangedFrom: knownRevision, cancellation: control)
    } complete: { [weak self] result in
      guard let self, self.interactionActive, self.workbook === book,
        self.interactionIdentity == identity.window,
        self.conversation == identity.conversation, self.messageAnchor == identity.messageAnchor
      else { return }
      switch result {
      case .success(let snapshot):
        guard let snapshot else { return }
        if let current = self.conversationSession.state.reading.message,
          !snapshot.messages.contains(where: { $0.id == current })
        {
          // The user scrolled beyond this pending window. Read the current
          // position instead of replacing it with an obsolete bounded window.
          if let pageAnchor {
            self.conversationSession.updateReading(.init(message: pageAnchor))
            self.readingRequest = UUID()
          } else {
            self.refresh()
            return
          }
        }
        self.loadedRefreshIdentity = identity
        self.revision = snapshot.revision
        self.spaces = snapshot.spaces
        self.items = snapshot.items
        self.datasets = snapshot.datasets
        self.messages = snapshot.messages
        self.hasEarlierMessages = snapshot.hasEarlierMessages
        self.hasLaterMessages = snapshot.hasLaterMessages
        self.conversations = snapshot.conversations
        self.chapters = snapshot.chapters
        self.bookmarks = snapshot.bookmarks
        self.pendingExtractions = snapshot.pendingExtractions
        self.intakeStatus = snapshot.intakeStatus
      case .failure(let failure):
        // A busy workbook can be retried by the next timer tick. An explicit
        // refresh reports its failure while preserving the last complete view.
        if !polling || (failure as? SevraError)?.code != "deadline" {
          self.error = failure.localizedDescription
        }
      }
    }
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
      changeConversation(location?["conversation_id"].text ?? "main", anchor: id)
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
    panel.message =
      "Includes the workbook, conversations and saved unsent drafts. Review them before sharing."
    panel.nameFieldStringValue = book.title + ".sevraz"
    if panel.runModal() == .OK, let url = panel.url, interactionActive, workbook === book,
      interactionIdentity == identity
    {
      Task {
        guard await conversationSession.flush(), interactionActive,
          workbook === book, interactionIdentity == identity, documentDrafts.flush()
        else { return }
        run("Making a shareable copy") { book, cancel in
          try book.export(to: url, cancellation: cancel)
        }
      }
    }
  }
  var canSend: Bool {
    conversationSession.ready && !changingConversation && !conversationSession.loading
      && WorkspaceControlCommand.allowsSubmission(prompt, busy: busy)
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
    conversationSession.updateReading(.init())
    readingRequest = UUID()
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
    if conversationCommand(input, book: book) {
      refresh()
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
  private func conversationCommand(_ input: String, book: Workbook) -> Bool {
    guard let command = ConversationCommand.parse(input) else { return false }
    do {
      // Keep navigation/sharing instructions in their originating history. Only
      // the explicitly shared findings are copied into the main conversation.
      _ = try book.addMessage(input, role: "user", conversation: conversation)

      switch command {
      case .backToConversation: changeConversation("main")
      case .startThread(let title):
        guard let message = messages.last(where: { ["user", "assistant"].contains($0.role) })
        else {
          throw SevraError("conversation", "Start the conversation before opening a thread.")
        }
        startThread(from: message.id, title: title)
      case .shareSummary(let text):
        if let text {
          guard conversation != "main",
            let message = messages.last(where: {
              $0.role == "assistant" && $0.state == "complete"
            })
          else { throw SevraError("summary", "Choose a completed thread answer to share.") }
          _ = try book.shareSummary(message: message.id, text: text)
          changeConversation("main")
        } else {
          requestSummary()
        }
      }

    } catch { self.error = error.localizedDescription }
    return true
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
    case .openCopy:
      openAssetCopy(input: input)
      return
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
  func openAssetCopy(input: String? = nil) {
    guard interactionActive, !busy, let book = workbook,
      case .item = route, let source = activeDocument?.current, viewedItemVersion == source.id,
      let assetID = source.assetID
    else {
      error = "Open a file preview first, then ask to open a copy."
      return
    }
    let identity = interactionIdentity
    let navigationID = itemPreviewIdentity
    let chat = conversation
    do {
      let asset = try book.asset(assetID)
      let name = URL(fileURLWithPath: asset.name).lastPathComponent
      let fileName = URL(fileURLWithPath: name)
      let suffix = fileName.pathExtension.isEmpty ? "" : "." + fileName.pathExtension
      let panel = NSSavePanel()
      panel.title = "Open a copy in another app"
      panel.prompt = "Save and Open"
      panel.message =
        "The workbook original stays unchanged. Edits to this copy are not added to the workbook."
      panel.nameFieldStringValue =
        fileName.deletingPathExtension().lastPathComponent + " copy" + suffix
      panel.canCreateDirectories = true
      let validation = AssetCopySaveDelegate(workbook: book)
      panel.delegate = validation
      if let input { _ = try book.addMessage(input, role: "user", conversation: chat) }
      guard withExtendedLifetime(validation, { panel.runModal() }) == .OK,
        let destination = panel.url, interactionActive, workbook === book,
        interactionIdentity == identity, itemPreviewIdentity == navigationID,
        let (_, ticket) = beginOperation("Preparing file copy")
      else { return }
      Task {
        defer { finishOperation(ticket, in: book) }
        do {
          let copy = try await Task.detached(priority: .userInitiated) { [weak self] in
            var lastProgress = -Double.infinity
            return try book.copyAsset(assetID, to: destination, cancellation: ticket.cancellation) {
              bytes, total in
              let now = ProcessInfo.processInfo.systemUptime
              guard now - lastProgress >= 0.1 else { return }
              lastProgress = now
              let message =
                "Copying " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                + " of " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
              Task { @MainActor [weak self] in
                guard let self, self.owns(ticket, in: book), self.operations.acceptsProgress(ticket)
                else { return }
                self.status = message
              }
            }
          }.value
          _ = try book.addMessage(
            "Saved a copy of " + source.referenceMarkdown + " as " + copy.lastPathComponent
              + ". Edits to the copy are not added to this workbook.", role: "event",
            conversation: chat)
          guard owns(ticket, in: book), !ticket.cancellation.isCancelled else { return }
          if !NSWorkspace.shared.open(copy) {
            error =
              "The copy was saved, but no app opened it. You can find it in the folder you chose."
          }
        } catch { report(error, for: ticket, in: book) }
      }
    } catch { self.error = error.localizedDescription }
  }
  func openConversationLink(_ url: URL) {
    switch ConversationLinkTarget(url) {
    case .evidence(let id, let locator): openEvidence(id, locator: locator)
    case .message(let id): jumpToMessage(id)
    case .external: NSWorkspace.shared.open(url)
    case nil: break
    }
  }
  func requestSummary(message: Message? = nil) {
    guard conversation != "main",
      let selected = message
        ?? messages.last(where: { $0.role == "assistant" && $0.state == "complete" })
    else {
      error = "Choose a completed thread answer to share."
      return
    }
    summaryDraft = .init(id: selected.id, text: selected.body)
  }
  func changeConversation(_ id: String, anchor: String? = nil) {
    guard interactionActive, !changingConversation else { return }
    speech.stop()
    changingConversation = true
    let owner = interactionIdentity
    Task {
      defer { changingConversation = false }
      await selectConversation(id, anchor: anchor, owner: owner)
    }
  }
  private func selectConversation(_ id: String, anchor: String? = nil, owner: UUID) async {
    guard await conversationSession.select(id), interactionActive, interactionIdentity == owner
    else { return }
    conversationDraft = nil
    summaryDraft = nil
    showingHistorySearch = false
    if conversation != id { historySearch.reset() }
    conversation = id
    if let workbook {
      UserDefaults.standard.set(id, forKey: "lastConversation:" + workbook.url.path)
    }
    selectedContext = ""
    if let anchor { conversationSession.updateReading(.init(message: anchor)) }
    restoreConversationPresentation()
    refresh()
    composerFocusRequest = UUID()
  }
  func startThread(from message: String, title: String? = nil) {
    guard interactionActive, !changingConversation, let book = workbook else { return }
    speech.stop()
    changingConversation = true
    let owner = interactionIdentity
    Task {
      defer { changingConversation = false }
      guard await conversationSession.flush(), interactionActive, interactionIdentity == owner
      else { return }
      do {
        let id = try await Task.detached(priority: .userInitiated) {
          try book.startThread(parentMessage: message, title: title)
        }.value
        guard interactionActive, interactionIdentity == owner, workbook === book else { return }
        await selectConversation(id, owner: owner)
      } catch { if interactionIdentity == owner { self.error = error.localizedDescription } }
    }
  }
  var conversationTitle: String {
    conversation == "main"
      ? "Conversation"
      : conversations.first { $0["id"].text == conversation }?["title"].text ?? "Thread"
  }
  func requestRenameThread() {
    guard conversation != "main" else { return }
    conversationDraft = .init(message: "", threadID: conversation, title: conversationTitle)
  }
  func pageConversation(earlier: Bool) {
    guard !changingConversation, let boundary = earlier ? messages.first?.id : messages.last?.id
    else { return }
    messageAnchor = boundary
    requestRefresh(polling: false, pageAnchor: boundary)
  }
  func latestConversationMessages() {
    guard !changingConversation else { return }
    conversationSession.updateReading(.init())
    messageAnchor = nil
    readingRequest = UUID()
    refresh()
  }
  func saveBeforeClosing() async -> Bool {
    speech.stop()
    guard !changingConversation, documentDrafts.flush() else { return false }
    let saved = await conversationSession.flush()
    return saved && documentDrafts.flush()
  }
  func restoreSavedConversationDraft(_ id: String) {
    guard !changingConversation else { return }
    changingConversation = true
    Task {
      defer { changingConversation = false }
      _ = await conversationSession.restoreSaved(id)
      restoreConversationPresentation()
    }
  }
  func voice() {
    guard interactionActive, conversationSession.ready, !changingConversation else { return }
    if speech.active {
      speech.stop()
      return
    }
    var draft = DictationDraft(prompt)
    let chat = conversation
    let owner = interactionIdentity
    speech.start { [weak self] text in
      guard let self else { return }
      guard self.interactionActive, self.interactionIdentity == owner,
        !self.changingConversation, self.conversation == chat,
        let rendered = draft.apply(text, to: self.prompt)
      else {
        self.speech.stop()
        return
      }
      self.applyingDictation = true
      self.prompt = rendered
      self.applyingDictation = false
    } failure: { [weak self] error in
      guard let self, self.interactionActive, self.interactionIdentity == owner,
        self.conversation == chat, !self.changingConversation
      else { return }
      self.error = error
    }
  }
  func beginInteraction() { interactionActive = true }
  func endInteraction() {
    interactionActive = false
    conversationDraft = nil
    summaryDraft = nil
    showingHistorySearch = false
    historySearch.reset()
    interactionIdentity = UUID()
    operations.invalidate()
    refreshSession.reset()
    loadedRefreshIdentity = nil
    awaitingSpeechPermission = nil
    busy = false
    status = ""
    activePreview?.cancel()
    activePreview = nil
    searchResults.reset()
    speech.stop()
    PlaybackRegistry.shared.close(owner: mediaOwner)
    backgroundPlayer?.releasePlayback()
    backgroundPlayer = nil
    backgroundMediaTitle = ""
  }
}
