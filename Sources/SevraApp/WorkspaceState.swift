import AVKit
import AppKit
import Foundation
import SevraAI
import SevraCore
import SevraDocumentUI
import SevraPreviewUI
import SevraProduct
import SevraSearchUI
import SevraTableUI
import SevraVoice
import SwiftUI
import os

@MainActor private final class AssetCopySaveDelegate: NSObject, NSOpenSavePanelDelegate {
  let workbook: Workbook
  init(workbook: Workbook) { self.workbook = workbook }
  func panel(_ sender: Any, validate url: URL) throws {
    _ = try workbook.assetCopyDestination(url)
  }
}

struct FolderReview {
  let root: URL
  let plan: FolderPlan
}

@MainActor final class WorkspaceState: ObservableObject {
  enum Route: Equatable {
    case space(String)
    case item(String)
    case table(String)
    case tableUpdate(String, String?)
    case search
    case reviews
    case activity
    case automations
    case automation(String)
    case workflow(String)
  }
  @Published var workbook: Workbook?
  @Published var folderReview: FolderReview?
  @Published var spaces: [Space] = []
  let spaceNavigation = SpaceNavigationSession()
  @Published var pendingReview: ReviewQueuePage?
  let reviewResults = ReviewQueueSession()
  @Published var items: [ItemSummary] = []
  @Published var datasets: [Dataset] = []
  @Published var archivedDatasets: [Dataset] = []
  func dataset(_ id: String) -> Dataset? {
    (datasets + archivedDatasets).first { $0.id == id }
  }
  @Published var messages: [Message] = []
  private let contents = ConversationContentCache()
  func messageContent(_ message: Message) -> ConversationMessageContent {
    contents.content(id: message.id, body: message.body)
  }
  @Published var requestActivities: [RequestActivity] = []
  @Published var liveActivity: LiveRequestActivity?
  @Published var proposalReviews: [String: ProposalReviewState] = [:]
  @Published var hasEarlierMessages = false
  @Published var hasLaterMessages = false
  @Published var showingHistorySearch = false
  private var conversationNavigationIdentity = UUID()
  let historySearch = ConversationHistorySearch()
  @Published var conversations: [Value] = []
  @Published var conversationDraft: ConversationDraft?
  @Published var summaryDraft: ConversationSummaryDraft?
  @Published var composerFocusRequest = UUID()
  @Published var chapters: [Value] = []
  @Published var bookmarks: [Value] = []
  @Published var pendingExtractions: [Value] = []
  @Published var importProgress: (saved: Int, total: Int)?
  @Published var activeIntake: String?
  @Published var intakePrompt: IntakePrompt?
  @Published var conversation = "main" {
    didSet {
      if conversation != oldValue {
        speech.stop()
        clarificationDrafts.invalidateConversationPreviews()
      }
    }
  }
  @Published var route: Route = .space("home") {
    didSet { if route != oldValue { clarificationDrafts.invalidateConversationPreviews() } }
  }
  @Published var navigation: [Route] = []
  @Published var viewedItemVersion: String?
  /// Known once the viewer has the item, so no view reads the workbook to draw its title.
  var viewedItemTitle: String? {
    activeDocument.flatMap { $0.current.id == viewedItemVersion ? $0.current.title : nil }
  }
  @Published var itemPreviewIdentity = UUID()
  weak var activeDocument: DocumentDraft?
  weak var activePreview: AssetPreviewSession?
  let documentDrafts = DocumentDraftScope()
  let conversationSession = ConversationSession()
  let formDrafts = FormDraftScope()
  let clarificationDrafts = WorkflowClarificationScope()
  @Published private(set) var changingConversation = false
  @Published var readingRequest = UUID()
  private var restoringConversation = false
  @Published var prompt = "" {
    didSet {
      if prompt != oldValue && !applyingDictation { speech.stop() }
      if !restoringConversation { conversationSession.updateDraft(prompt) }
    }
  }
  private let automationBusyOwner = UUID()
  @Published var busy = false {
    didSet { NativeAutomationHost.shared.setBusy(automationBusyOwner, busy) }
  }
  @Published var status = ""
  @Published var error: String?
  @Published var selectedContext = "" {
    didSet { selectionLabel = nil }
  }
  @Published var selectionLabel: String?
  @Published var itemLocators: [String: String] = [:]
  /// Changes each time a citation asks for its place, even the same place twice.
  @Published var locatorRequest = UUID()
  @Published var itemReading: [String: DocumentReadingPosition] = [:]
  @Published var referenceModal: ReferenceModal?
  var referencePanel: ReferenceDirection? {
    get {
      if case .browser(let direction) = referenceModal { return direction }
      return nil
    }
    set { referenceModal = newValue.map(ReferenceModal.browser) }
  }
  var referenceChoice: ReferenceOccurrence? {
    get {
      if case .choice(let occurrence) = referenceModal { return occurrence }
      return nil
    }
    set { referenceModal = newValue.map(ReferenceModal.choice) }
  }
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
  let mediaOwner = UUID()
  private(set) var interactionActive = false
  private(set) var interactionIdentity = UUID()
  private var applyingDictation = false
  /// The submitted message until its conversation has saved it. Only one operation runs at a time.
  private var unsent: (input: String, chat: String, book: Workbook)?
  let speech = SpeechInput(pausePlayback: { PlaybackRegistry.shared.pauseAll() })
  func open(_ url: URL) async throws {
    // Opening checks the whole schema and can wait for another process to let go of the workbook.
    let opened = try await Task.detached(priority: .userInitiated) { try Workbook(url) }.value
    try require(
      documentDrafts.flush(), "document_save",
      "Save or preserve the current draft before opening another workbook.")
    let formsSaved = await formDrafts.flush()
    try require(
      formsSaved, "form_draft_save", "Save or preserve form drafts before opening another workbook."
    )
    let clarificationsSaved = await clarificationDrafts.flush()
    try require(
      clarificationsSaved, "clarification_draft_save",
      "Save or preserve clarification inputs before opening another workbook.")
    speech.stop()
    let restored = await conversationSession.open(
      opened,
      conversation: UserDefaults.standard.string(forKey: "lastConversation:" + opened.url.path)
        ?? "main")
    try require(
      restored, "conversation_save",
      conversationSession.failure ?? "Could not restore the conversation draft.")
    _ = await formDrafts.open(opened)
    let clarificationOpened = await clarificationDrafts.open(opened)
    try require(
      clarificationOpened, "clarification_draft_save",
      "Save or preserve clarification inputs before opening another workbook.")
    await spaceNavigation.open(opened)
    endInteraction()
    workbook = opened
    spaces = []
    items = []
    pendingReview = nil
    reviewResults.reset()
    datasets = []
    archivedDatasets = []
    messages = []
    proposalReviews = [:]
    conversations = []
    chapters = []
    bookmarks = []
    pendingExtractions = []
    importProgress = nil
    activeIntake = nil
    intakePrompt = nil
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
    itemReading = [:]
    referenceModal = nil
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
    formDrafts.changed = { [weak self] in self?.objectWillChange.send() }
    clarificationDrafts.changed = { [weak self] in self?.objectWillChange.send() }
    spaceNavigation.changed = { [weak self] in self?.objectWillChange.send() }
    spaceNavigation.failed = { [weak self] in self?.error = $0 }
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
      proposalReviews = [:]
      requestActivities = []
      hasEarlierMessages = false
      hasLaterMessages = false
    }
    let readingAnchor = pageAnchor ?? conversationSession.state.reading.message
    let knownRevision = polling && loadedRefreshIdentity == identity ? revision : nil
    let knownSpaceNavigation = spaceNavigation.state
    let navigationGeneration = spaceNavigation.generation
    let contents = contents
    refreshSession.request(identity: identity, onlyWhenIdle: polling && !changedView) { control in
      let snapshot = try book.workspaceSnapshot(
        conversation: identity.conversation, messageAnchor: readingAnchor,
        ifChangedFrom: knownRevision, ifSpaceNavigationMatches: knownSpaceNavigation,
        cancellation: control)
      if let snapshot { try contents.prepare(snapshot.messages, cancellation: control) }
      return snapshot
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
        self.spaceNavigation.receive(snapshot.spaceNavigation, generation: navigationGeneration)
        self.pendingReview = snapshot.reviewQueue
        self.items = snapshot.items
        self.datasets = snapshot.datasets
        self.archivedDatasets = snapshot.archivedDatasets
        self.messages = snapshot.messages
        self.contents.retain(snapshot.messages)
        self.requestActivities = snapshot.requestActivities
        self.proposalReviews = snapshot.proposalReviews
        self.hasEarlierMessages = snapshot.hasEarlierMessages
        self.hasLaterMessages = snapshot.hasLaterMessages
        self.conversations = snapshot.conversations
        self.chapters = snapshot.chapters
        self.bookmarks = snapshot.bookmarks
        self.pendingExtractions = snapshot.pendingExtractions
        if !self.busy { self.importProgress = nil }
      case .failure(let failure):
        // A busy workbook can be retried by the next timer tick. An explicit
        // refresh reports its failure while preserving the last complete view.
        if !polling || (failure as? SevraError)?.code != "deadline" {
          self.error = failure.localizedDescription
        }
      }
    }
  }
  @discardableResult func navigate(_ new: Route, replacing: Bool = false) -> Bool {
    guard documentDrafts.flush() else { return false }
    let shown: Route
    if case .item(let id) = route { shown = .item(viewedItemVersion ?? id) } else { shown = route }
    if shown != new {
      if !replacing { navigation.append(shown) }
      if navigation.count > 20 { navigation.removeFirst() }
      route = new
      referenceModal = nil
      viewedItemVersion = nil
      itemPreviewIdentity = UUID()
      selectedContext = ""
      if case .space(let id) = new { spaceNavigation.visit(id) }
    }
    return true
  }
  func openEvidence(_ id: String, locator: String? = nil) {
    guard navigate(.item(id)) else { return }
    if let locator {
      itemLocators[id] = locator
      locatorRequest = UUID()
    }
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
      referenceModal = nil
      viewedItemVersion = nil
      itemPreviewIdentity = UUID()
      selectedContext = ""
      if case .space(let id) = prior { spaceNavigation.visit(id) }
    }
  }
  func continueWorkflow(_ runID: String, retry: Bool = false) {
    guard let (book, ticket) = beginOperation("Continuing workflow") else { return }
    let path =
      UserDefaults.standard.string(forKey: ProductAI.preferenceKey).map { URL(fileURLWithPath: $0) }
      ?? ProductAI.defaultDirectory
    Task {
      defer { finishOperation(ticket, in: book) }
      do {
        let session = try await Task.detached {
          let session = try book.authorizeWorkflowExecution(
            runID, actor: .human("Sevra.native-workflow-continue"))
          if retry { _ = try book.retryWorkflow(session, token: identifier()) }
          return session
        }.value
        await NativeAutomationHost.shared.yieldForInteractive()
        try ticket.cancellation.check()
        _ = try await ProductAI.shared.continueWorkflow(
          workbook: book, session: session, owner: "native:" + identifier(),
          modelDirectory: path, cancellation: ticket.cancellation,
          progress: { update in
            Task { @MainActor in
              if self.owns(ticket, in: book) { self.status = update }
            }
          })
      } catch { report(error, for: ticket, in: book) }
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
    liveActivity = nil
    activeIntake = nil
    refresh()
  }
  private func report(_ failure: Error, for ticket: WorkspaceOperation, in book: Workbook) {
    guard owns(ticket, in: book) else { return }
    error = failure.localizedDescription
  }
  func pinSpace(_ id: String, title: String) {
    guard !busy, documentDrafts.flush(), let (book, ticket) = beginOperation("Saving a snapshot")
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
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK, interactionActive, workbook === book,
      conversation == chat, interactionIdentity == identity
    else { return }
    importFiles(panel.urls, linked: linked)
  }
  /// One explicit comparison of a folder, shown before anything is added.
  func folderPanel() {
    guard interactionActive, !busy, workbook != nil else { return }
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.message = "Sevra compares this folder once, now. It does not watch it."
    guard panel.runModal() == .OK, let folder = panel.url else { return }
    run(
      "Comparing folder",
      operation: { book, cancel in try book.folderPlan(folder, cancellation: cancel) },
      completion: { self.folderReview = FolderReview(root: folder, plan: $0) })
  }
  func addFolder(_ review: FolderReview) {
    let plan = review.plan
    let urls = plan.files.map { review.root.appendingPathComponent($0.relative) }
    importFiles(
      urls, tokens: Dictionary(uniqueKeysWithValues: zip(urls, plan.files.map(plan.token))),
      finished: "Compared folder " + plan.folder + ": " + plan.summary + ". Nothing was deleted.")
  }
  func importFiles(
    _ urls: [URL], linked: Bool = false, tokens: [URL: String] = [:], finished: String? = nil
  ) {
    let chat = conversation
    run(
      linked ? "Linking files" : "Including files",
      operation: { book, cancel in
        var failures: [String] = []
        for url in urls {
          try cancel.check()
          do {
            // Capturing a file is enough to make it evidence. Table conversion
            // remains an explicit later request, never an import prerequisite.
            let job = try book.captureIntake(
              url, linked: linked, role: .reference, token: tokens[url] ?? UUID().uuidString,
              cancellation: cancel)
            let item = try book.item(job.sourceID)
            _ = try book.addMessage(
              (linked ? "Linked " : "Included ") + item.referenceMarkdown, role: "event",
              conversation: chat)
            _ = try book.runIntake(job.id, cancellation: cancel)
          } catch {
            if cancel.isCancelled { throw error }
            failures.append(url.lastPathComponent + ": " + error.localizedDescription)
          }
        }
        if !failures.isEmpty {
          throw SevraError("import_partial", failures.joined(separator: "\n"))
        }
        if let finished { _ = try book.addMessage(finished, role: "event", conversation: chat) }
        return urls.count
      },
      completion: { _ in
        self.composerFocusRequest = UUID()
      })
  }
  func presentIntake(_ id: String) {
    run(
      "Reading saved intake",
      operation: { book, _ in
        let job = try book.intakeJob(id)
        let source = try book.item(job.sourceID)
        let asset = try book.asset(source.assetID!)
        return IntakeChoice(
          job: job, title: source.title,
          supportsTable: ["csv", "tsv", "xlsx"].contains(
            URL(fileURLWithPath: asset.name).pathExtension.lowercased()),
          supportsUpdate: ["csv", "tsv", "xlsx"].contains(
            URL(fileURLWithPath: asset.name).pathExtension.lowercased()))
      },
      completion: { choice in
        // A chosen update has nothing left to ask; go straight back to its review.
        if choice.job?.state == "awaiting_update" {
          self.navigate(.tableUpdate(choice.sourceID, choice.id))
        } else if choice.job?.role == .values {
          // Saving the rest of a stopped table import is the only next step.
          Task { self.continueIntake(choice, role: .values) }
        } else {
          self.intakePrompt = .init(choices: [choice])
        }
      })
  }
  func useSavedFile(_ sourceID: String) {
    run(
      "Preparing saved file",
      operation: { book, _ in
        let source = try book.item(sourceID)
        let asset = try book.asset(source.assetID!)
        return IntakeChoice(
          sourceID: source.id, title: source.title,
          supportsTable: ["csv", "tsv", "xlsx"].contains(
            URL(fileURLWithPath: asset.name).pathExtension.lowercased()),
          supportsUpdate: ["csv", "tsv", "xlsx"].contains(
            URL(fileURLWithPath: asset.name).pathExtension.lowercased()))
      }, completion: { choice in self.intakePrompt = .init(choices: [choice]) })
  }
  func continueIntake(_ choice: IntakeChoice, role: IntakeRole) {
    guard !busy else { return }
    let chat = conversation
    let navigationID = itemPreviewIdentity
    let progress = rowProgress()
    activeIntake = choice.id
    run(
      "Preparing " + choice.title,
      operation: { book, cancel in
        if choice.job == nil { _ = try book.beginIntake(sourceID: choice.sourceID, token: choice.id) }
        do {
          let current = try book.intakeJob(choice.id)
          if current.role == nil {
            _ = try book.chooseIntakeRole(choice.id, role: role)
          } else {
            try require(
              current.role == role, "intake_role",
              "This intake already has another use. Reopen the saved file to start a different use."
            )
          }
          let result = try book.runIntake(
            choice.id, cancellation: cancel, progress: progress)
          if result.state != current.state {
            _ = try book.addMessage(result.detail, role: "event", conversation: chat)
          }
          return IntakeAttempt(job: result, failure: nil)
        } catch {
          // Stop is the person's own choice, and Home shows what it left saved.
          return try IntakeAttempt(
            job: book.intakeJob(choice.id),
            failure: cancel.isCancelled ? nil : error.localizedDescription)
        }
      },
      completion: { attempt in
        let result = attempt.job
        if let failure = attempt.failure {
          self.error = failure
          if let index = self.intakePrompt?.choices.firstIndex(where: { $0.id == result.id }) {
            self.intakePrompt?.choices[index] = .init(
              job: result, title: choice.title, supportsTable: choice.supportsTable,
              supportsUpdate: choice.supportsUpdate)
          }
          return
        }
        self.intakePrompt?.choices.removeAll { $0.id == result.id }
        if self.intakePrompt?.choices.isEmpty == true { self.intakePrompt = nil }
        // Someone who moved on while this ran keeps their place, and their selection.
        if result.state == "cancelled" || self.conversation != chat
          || self.itemPreviewIdentity != navigationID
        {
          return
        }
        if role == .update {
          self.navigate(.tableUpdate(result.sourceID, result.id))
        } else if let id = result.datasetIDs.first {
          self.navigate(.table(id))
        }
      })
  }
  /// Status follows committed rows, reported from the import's own thread.
  func rowProgress() -> @Sendable (Int, Int) -> Void {
    { [weak self] done, total in
      Task { @MainActor in
        guard let self, self.busy else { return }
        self.importProgress = (done, total)
        // Stop stays on screen until the import has stopped.
        if self.status != "Stopping…" {
          self.status = "Saved \(done.formatted()) of \(total.formatted()) rows"
        }
      }
    }
  }
  /// Home's line for an intake: live while it runs, and plain once nothing is running.
  func intakeDetail(_ job: Value) -> String {
    if let activeIntake, job["job_id"].string == activeIntake { return status }
    return job["state"].text == "running" && !busy
      ? "Interrupted. Continue to pick up where it stopped." : job["detail"].text
  }
  /// How much of an unfinished import is saved. The table list only catches up
  /// after the import, because a running import keeps the workbook busy between batches.
  func savedRows(_ table: Dataset) -> String? {
    guard let source = table.unfinishedImportTotal else { return nil }
    let saved = importProgress?.saved ?? table.rowCount
    return "\(saved.formatted()) of \((importProgress?.total ?? source).formatted()) rows saved"
  }
  func pasteTableData() {
    guard interactionActive, !busy else { return }
    guard let text = NSPasteboard.general.string(forType: .string), TableClipboard.holdsTable(text)
    else {
      error =
        "Copy a table range with tab-separated columns and rows, up to 4 MB. Ordinary text belongs in the conversation."
      return
    }
    run(
      "Saving copied table range",
      operation: { book, cancel in
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(identifier())
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Copied table range.tsv")
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(text.utf8).write(to: file, options: .atomic)
        let source = try book.importFile(
          file, origin: "clipboard:values-only", cancellation: cancel, independentInput: true)
        let job = try book.beginIntake(sourceID: source.id)
        let result = try book.runIntake(job.id, cancellation: cancel)
        return IntakeChoice(
          job: result, title: "Copied table range (values only)", supportsTable: true,
          supportsUpdate: true)
      }, completion: { choice in self.intakePrompt = .init(choices: [choice]) })
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
        await spaceNavigation.flush()
        guard interactionActive, workbook === book, interactionIdentity == identity else { return }
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
    do { try ComposerInput.admit(input) } catch {
      self.error = error.localizedDescription
      return
    }
    if let answerCommand = WorkflowAnswerCommand.parse(input) {
      prompt = ""
      workflowAnswerCommand(answerCommand, input: input, book: book)
      return
    }
    clarificationDrafts.invalidateConversationPreviews()
    if let command = WorkspaceControlCommand.parse(input) {
      prompt = ""
      error = nil
      control(command, input: input, book: book)
      if error != nil { returnInput(input) }
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
    if let target = WorkspaceControlCommand.captureURL(input) {
      unsent = (input, conversation, book)
      guard let (_, ticket) = beginOperation("Capturing source") else {
        returnUnsent()
        return
      }
      let chat = conversation
      let navigationID = itemPreviewIdentity
      Task {
        defer { finishOperation(ticket, in: book) }
        do {
          let source = try await book.captureURL(target, cancellation: ticket.cancellation)
          unsent = nil
          _ = try book.addMessage(
            (source.assetID == nil ? "Saved reference: " : "Captured ") + source.referenceMarkdown,
            role: "event", conversation: chat)
          guard owns(ticket, in: book) else { return }
          if conversation == chat, itemPreviewIdentity == navigationID {
            navigate(.item(source.id))
          }
        } catch {
          returnUnsent()
          report(error, for: ticket, in: book)
        }
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
    unsent = (input, conversation, book)
    guard let (_, ticket) = beginOperation("Preparing local AI") else {
      returnUnsent()
      return
    }
    // Set on the agent's own thread, so a failure right after admission still sees it.
    let admitted = OSAllocatedUnfairLock(initialState: false)
    liveActivity = LiveRequestActivity(conversation: conversation)
    let chat = conversation
    let navigationID = itemPreviewIdentity
    let context = agentContext + (selectedContext.isEmpty ? "" : "\nSelection: " + selectedContext)
    let conversationOrigin = conversationNavigationIdentity
    let path =
      UserDefaults.standard.string(forKey: ProductAI.preferenceKey).map { URL(fileURLWithPath: $0) }
      ?? ProductAI.defaultDirectory
    Task {
      defer { finishOperation(ticket, in: book) }
      var expectedNavigationID = navigationID
      let openRequestedView: @MainActor @Sendable (Route) throws -> Void = { destination in
        guard self.owns(ticket, in: book), self.conversation == chat,
          self.itemPreviewIdentity == expectedNavigationID,
          self.conversationNavigationIdentity == conversationOrigin,
          !ticket.cancellation.isCancelled, !self.changingConversation
        else {
          throw SevraError(
            "workspace_changed",
            "You moved to another view or conversation. No view was opened. Ask again from the view you want to use."
          )
        }
        guard self.navigate(destination) else {
          throw SevraError(
            "workspace_changed",
            "The current document has an unsaved change. Save or preserve it before opening another view."
          )
        }
        expectedNavigationID = self.itemPreviewIdentity
        self.refresh()
      }
      do {
        guard await clarificationDrafts.flush() else {
          throw SevraError(
            "clarification_draft",
            "Your workflow inputs could not be saved. Preserve them before sending another request."
          )
        }
        try ticket.cancellation.check()
        await NativeAutomationHost.shared.yieldForInteractive()
        try ticket.cancellation.check()
        let result = try await ProductAI.shared.run(
          input, workbook: book, conversation: chat, context: context, modelDirectory: path,
          cancellation: ticket.cancellation,
          progress: { value in
            Task { @MainActor in
              guard self.owns(ticket, in: book), self.operations.acceptsProgress(ticket) else {
                return
              }
              self.status = value
              self.liveActivity?.update(value)
              // Phase/count updates are ephemeral; only fetch saved history when
              // the workbook revision changed. Reads remain off the UI actor.
              self.requestRefresh(polling: true)
            }
          },
          requestStarted: { request, destination in
            admitted.withLock { $0 = true }
            Task { @MainActor in
              self.unsent = nil
              guard self.owns(ticket, in: book), self.operations.acceptsProgress(ticket) else {
                return
              }
              self.liveActivity?.attach(request, conversation: destination)
              self.refresh()
            }
          },
          openSpace: { target in try openRequestedView(.space(target.id)) },
          openReviews: { try openRequestedView(.reviews) })
        unsent = nil
        guard owns(ticket, in: book) else { return }
        refresh()
        let present =
          conversation == chat && itemPreviewIdentity == expectedNavigationID
          && conversationNavigationIdentity == conversationOrigin
          && !ticket.cancellation.isCancelled && !changingConversation
        if present,
          let action = result.conversationAction, action.originConversation == chat
        {
          applyConversationAction(action)
        }
        if present, let focus = result.focus {
          switch focus.kind {
          case "space": navigate(.space(focus.id))
          case "automation": navigate(.automation(focus.id))
          case "workflow":
            if let session = clarificationDrafts.session(focus.id) { await session.reloadSaved() }
            guard owns(ticket, in: book), conversation == chat,
              itemPreviewIdentity == expectedNavigationID,
              conversationNavigationIdentity == conversationOrigin,
              !ticket.cancellation.isCancelled, !changingConversation
            else { return }
            navigate(.workflow(focus.id))
          default: navigate(.item(focus.id))
          }
        }
      } catch {
        if admitted.withLock({ $0 }) { unsent = nil } else { returnUnsent() }
        report(error, for: ticket, in: book)
      }
    }
  }
  /// Puts a message that failed before anything was saved back in front of the person.
  private func returnInput(_ input: String) {
    prompt = ComposerInput.restored(input, over: prompt)
  }
  /// A message that never reached its conversation goes back where it was typed. When that
  /// composer is showing something else or has closed, it becomes that conversation's draft.
  private func returnUnsent() {
    guard let unsent else { return }
    self.unsent = nil
    if interactionActive, workbook === unsent.book, conversation == unsent.chat,
      !changingConversation
    {
      returnInput(unsent.input)
    } else {
      do { try ComposerInput.keep(unsent.input, conversation: unsent.chat, in: unsent.book) } catch {
        if interactionActive { returnInput(unsent.input) }
      }
    }
  }
  private func workflowAnswerCommand(
    _ command: WorkflowAnswerCommand, input: String, book: Workbook
  ) {
    do {
      let chat = conversation
      let message = try book.addMessage(input, role: "user", conversation: chat)
      guard case .workflow(let runID) = route else {
        _ = try book.addMessage(
          "Open the workflow containing your answer, then say or type “Preview my answer”. No answer was submitted.",
          role: "event", conversation: chat)
        refresh()
        return
      }
      guard
        let (_, ticket) = beginOperation(
          command == .preview ? "Preparing answer preview" : "Saving your answer")
      else { return }
      let navigationID = itemPreviewIdentity
      let conversationOrigin = conversationNavigationIdentity
      Task {
        defer { finishOperation(ticket, in: book) }
        do {
          guard let session = clarificationDrafts.session(runID) else {
            throw SevraError(
              "clarification_draft", "Open the workflow again to load its saved inputs.")
          }
          await session.open()
          guard owns(ticket, in: book), conversation == chat, !changingConversation,
            route == .workflow(runID), itemPreviewIdentity == navigationID,
            conversationNavigationIdentity == conversationOrigin,
            !ticket.cancellation.isCancelled
          else { return }
          switch command {
          case .preview:
            try await session.prepareForConversation(chat, cancellation: ticket.cancellation)
          case .confirm:
            try await session.confirmForConversation(
              chat, messageID: message, cancellation: ticket.cancellation)
            _ = try book.addMessage(
              "Your supplied answer was saved. Only the paused interpretation completed. Continue the workflow when ready; business changes still need review.",
              role: "event", conversation: chat,
              payload: .object([
                "kind": .string("workflow_answer_confirmed"),
                "receipt": session.state?.entry.receipt ?? .null,
              ]))
          }
          guard owns(ticket, in: book), conversation == chat else { return }
          refresh()
        } catch { report(error, for: ticket, in: book) }
      }
    } catch {
      self.error = error.localizedDescription
      returnInput(input)
    }
  }
  var agentContext: String {
    switch route {
    case .space(let id): return routeContext + "\nActive space ID: " + id
    case .item(let id):
      return routeContext + "\nActive item version ID: " + (viewedItemVersion ?? id)
    case .table(let id): return routeContext + "\nActive dataset ID: " + id
    case .tableUpdate(let source, _):
      return routeContext + "\nTable-update review for source ID: " + source
    case .automation(let id): return routeContext + "\nActive exact automation version ID: " + id
    case .workflow(let id): return routeContext + "\nActive workflow run ID: " + id
    case .search, .reviews, .activity, .automations: return routeContext
    }
  }
  var routeContext: String {
    switch route {
    case .space(let id): return "Space: " + (spaces.first { $0.id == id }?.title ?? id)
    case .item(let id):
      return "Item: " + (viewedItemTitle ?? id)
    case .table(let id): return "Table: " + (dataset(id)?.title ?? id)
    case .tableUpdate: return "Review table update"
    case .search: return "Workbook search"
    case .reviews: return "Drafts to review"
    case .activity: return "Workflow activity"
    case .automations: return "Automations"
    case .automation:
      return
        "Inspecting a saved automation. Saving/opening never grants device execution permission."
    case .workflow:
      return "Inspecting a saved workflow run; opening it does not authorize execution."
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
        requestSummary(text: text)
      }

    } catch {
      self.error = error.localizedDescription
      returnInput(input)
    }
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
      if lower == "add folder" || lower == "add a folder" {
        folderPanel()
        return true
      }
      if lower == "make a shareable copy" || lower == "export workbook" {
        exportPanel()
        return true
      }
      if lower.hasPrefix("open ") {
        let matching = spaces.filter { $0.title.lowercased() == String(lower.dropFirst(5)) }
        if matching.count > 1 {
          throw SevraError(
            "space_ambiguous",
            "More than one space has that name. Which one do you mean? You can describe it or select it in Spaces."
          )
        }
        if let space = matching.first {
          navigate(.space(space.id))
          return true
        }
      }
      if ["withdraw this", "withdraw that", "withdraw this draft"].contains(lower),
        case .item(let id) = route
      {
        review(viewedItemVersion ?? id, action: .withdraw)
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
      switch WorkbookTextCommand.parse(input) {
      case .accept(let id):
        review(id, accepting: true)
        return true
      case .undo(let id):
        review(id, accepting: false)
        return true
      case .chapter(let title):
        if let message = messages.last {
          try book.chapter(title: title, message: message.id)
          return true
        }
      case nil: break
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
  enum ReviewAction {
    case accept, undo, redo, withdraw
    var progress: String {
      switch self {
      case .accept: return "Accepting changes"
      case .undo: return "Undoing changes"
      case .redo: return "Redoing changes"
      case .withdraw: return "Withdrawing draft"
      }
    }
    var receipt: String {
      switch self {
      case .accept: return "Accepted "
      case .undo: return "Undid the last change to "
      case .redo: return "Redid the last change to "
      case .withdraw: return "Withdrew "
      }
    }
  }
  func review(_ id: String, accepting: Bool) { review(id, action: accepting ? .accept : .undo) }
  func review(_ id: String, action: ReviewAction) {
    guard let (book, ticket) = beginOperation(action.progress)
    else { return }
    let chat = conversation
    let navigationID = itemPreviewIdentity
    Task {
      defer { finishOperation(ticket, in: book) }
      do {
        let record = try await Task.detached {
          try ticket.cancellation.check()
          switch action {
          case .accept:
            return try book.accept(
              id, cancellation: ticket.cancellation, actor: .human("SevraApp.review"))
          case .undo, .redo:
            return try book.undoItem(
              id, cancellation: ticket.cancellation, actor: .human("SevraApp.review"))
          case .withdraw: return try book.withdrawDraft(id, actor: .human("SevraApp.review"))
          }
        }.value
        let receipt =
          action == .withdraw && record.status == "accepted"
          ? "Withdrew the draft. Previous accepted version restored: " : action.receipt
        _ = try book.addMessage(
          receipt + record.referenceMarkdown,
          role: "event", conversation: chat)
        guard owns(ticket, in: book) else { return }
        refresh()
        if conversation == chat, itemPreviewIdentity == navigationID {
          navigate(.item(record.id), replacing: true)
        }
      } catch { report(error, for: ticket, in: book) }
    }
  }
  func transcribe(_ id: String) {
    guard let (book, ticket) = beginOperation("Transcribing on this Mac") else { return }
    speech.stop()
    PlaybackRegistry.shared.pauseAll()
    Task { @MainActor in
      defer { self.finishOperation(ticket, in: book) }
      do {
        try await book.transcribe(id, cancellation: ticket.cancellation) { value in
          Task { @MainActor in
            if self.owns(ticket, in: book) { self.status = value }
          }
        }
      } catch { self.report(error, for: ticket, in: book) }
    }
  }
  func stop() {
    speech.stop()
    operations.cancel()
    if activePreview?.loading == true { activePreview?.stop() }
    if busy {
      status = "Stopping…"
      liveActivity?.stop()
    }
  }
  private func control(_ command: WorkspaceControlCommand, input: String, book: Workbook) {
    let notice: String
    switch command {
    case .showMentions, .showLinks:
      guard case .item = route, viewedItemVersion != nil else {
        error = "Open a document or record first."
        return
      }
      referencePanel = command == .showMentions ? .incoming : .outgoing
      notice =
        command == .showMentions
        ? "Showing saved mentions of this item." : "Showing saved links in this item."
    case .goBack:
      guard !navigation.isEmpty else {
        error = "There is no earlier view in this window."
        return
      }
      let count = navigation.count
      back()
      guard navigation.count < count else { return }
      notice = "Returned to the previous view."
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
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
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
          try Workbook.quarantineCopy(copy)
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
  func requestSummary(message: Message? = nil, text: String? = nil) {
    guard conversation != "main", let book = workbook else {
      error = "Choose a completed thread answer to share."
      return
    }
    if let message {
      summaryDraft = .init(id: message.id, text: text ?? message.body)
      return
    }
    let owner = interactionIdentity
    let chat = conversation
    let navigation = conversationNavigationIdentity
    Task {
      do {
        let selected = try await Task.detached(priority: .userInitiated) {
          try book.latestShareableAnswer(conversation: chat)
        }.value
        guard interactionActive, interactionIdentity == owner, workbook === book,
          conversation == chat, conversationNavigationIdentity == navigation,
          !changingConversation
        else { return }
        guard let selected else {
          throw SevraError("summary", "Choose a completed thread answer to share.")
        }
        summaryDraft = .init(id: selected.id, text: text ?? selected.body)
      } catch {
        if interactionActive && interactionIdentity == owner && conversation == chat
          && conversationNavigationIdentity == navigation
        {
          self.error = error.localizedDescription
        }
      }
    }
  }
  private func applyConversationAction(_ action: ConversationActionResult) {
    switch action.kind {
    case .created, .returnToMain: changeConversation(action.conversation)
    case .renamed: refresh()
    case .reviewSummary:
      if let id = action.message, let text = action.summary {
        summaryDraft = .init(id: id, text: text)
      }
    }
  }
  func changeConversation(_ id: String, anchor: String? = nil) {
    guard interactionActive, !changingConversation else { return }
    speech.stop()
    clarificationDrafts.invalidateConversationPreviews()
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
    conversationNavigationIdentity = UUID()
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
    clarificationDrafts.invalidateConversationPreviews()
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
    await spaceNavigation.flush()
    let formsSaved = await formDrafts.flush()
    let clarificationsSaved = await clarificationDrafts.flush()
    return saved && formsSaved && clarificationsSaved && documentDrafts.flush()
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
    returnUnsent()
    conversationDraft = nil
    summaryDraft = nil
    showingHistorySearch = false
    historySearch.reset()
    interactionIdentity = UUID()
    clarificationDrafts.invalidateConversationPreviews()
    operations.invalidate()
    refreshSession.reset()
    loadedRefreshIdentity = nil
    busy = false
    status = ""
    liveActivity = nil
    requestActivities = []
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
