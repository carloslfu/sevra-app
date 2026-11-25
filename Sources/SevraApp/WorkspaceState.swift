import AVKit
import AppKit
import Foundation
import SevraAI
import SevraAppUI
import SevraCore
import SevraDocumentUI
import SevraPreviewUI
import SevraProduct
import SevraSearchUI
import SevraTableUI
import SevraVoice
import SwiftUI
import UniformTypeIdentifiers
import os

typealias WorkbookReadingTarget = ReadingTarget

@MainActor private final class AssetCopySaveDelegate: NSObject, NSOpenSavePanelDelegate {
  let workbook: Workbook
  init(workbook: Workbook) { self.workbook = workbook }
  func panel(_ sender: Any, validate url: URL) throws {
    _ = try workbook.assetCopyDestination(url)
  }
}

/// A message on its way to its chat, or one that did not get there.
struct SentMessage: Equatable {
  let id = UUID()
  let text: String
  let conversation: String
  /// Parsed once, as the saved message will be, so the bubble keeps its shape when that loads.
  let content: ConversationMessageContent
  private(set) var failure: String?
  init(text: String, conversation: String) {
    self.text = text
    self.conversation = conversation
    content = ConversationMessageContent(text)
  }
  static func == (left: SentMessage, right: SentMessage) -> Bool {
    left.id == right.id && left.text == right.text && left.conversation == right.conversation
      && left.failure == right.failure
  }
  func failed(_ reason: String) -> SentMessage {
    var next = self
    next.failure = reason
    return next
  }
}

struct FolderReview {
  let root: URL
  let plan: FolderPlan
}

@MainActor final class WorkspaceState: ObservableObject {
  let ai: ProductAI
  let appExchange: (@Sendable (Data) async throws -> Data)?
  let automation: NativeAutomationHost
  let defaults: UserDefaults
  private var nativeAppSessions: [String: NativeAppSession] = [:]
  func nativeAppSession(_ space: Space, book: Workbook) -> NativeAppSession {
    if let session = nativeAppSessions[space.id], session.book === book,
      session.space.version == space.version
    {
      return session
    }
    nativeAppSessions[space.id]?.stop()
    let session = NativeAppSession(
      book: book, space: space, defaults: defaults, exchange: appExchange)
    nativeAppSessions[space.id] = session
    return session
  }
  private func closeNativeApps() {
    for session in nativeAppSessions.values { session.stop() }
    nativeAppSessions = [:]
  }
  enum Route: Equatable {
    case space(String)
    case item(String)
    case table(String)
    case tableUpdate(String, String?)
    case excelImport(String)
    case search
    case reviews
    case activity
    case automations
    case automation(String)
    case workflow(String)
    case tools
    case removed
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
  @Published var homeDocuments: [ItemSummary] = []
  @Published var pendingWorkflows: [Value] = []
  @Published var datasetSnapshot = "initial"
  @Published var presentationSnapshot = 0
  @Published var chatApproval: ChatApproval?
  @Published var pendingInputs: [ConversationInputReference] = []
  @Published var pendingInput: ConversationSurface?
  @Published var replyInputID: String?
  @Published var imageInspection: ConversationImageInspection?
  @Published var visualInspection: ConversationVisualInspection?
  @Published var conversationVisuals: [String: [VisualResult]] = [:]
  @Published var resumableAnswer: String?
  @Published var excelImports: [Value] = []
  @Published var excelPurposeDrafts: [String: String] = [:]
  func dataset(_ id: String) -> Dataset? {
    (datasets + archivedDatasets).first { $0.id == id }
  }
  @Published var messages: [Message] = []
  private let contents = ConversationContentCache()
  /// What a message shows. A question that is no longer open keeps its text, but not the line
  /// that says how to answer it.
  nonisolated static func displayBody(_ message: Message, open: Set<String>) -> String {
    message.state == "needs_input" && !open.contains(message.id)
      ? message.body.replacingOccurrences(of: "\n" + ConversationSurface.textReplyHint, with: "")
      : message.body
  }
  func messageContent(_ message: Message) -> ConversationMessageContent {
    contents.content(
      id: message.id, body: Self.displayBody(message, open: Set(pendingInputs.map(\.id))))
  }
  @Published var requestActivities: [RequestActivity] = []
  @Published var liveActivity: LiveRequestActivity?
  /// The message just sent, shown in its chat at once. It stays until the chat has saved it, and
  /// a message that never got there stays as not sent, with why, Retry and Edit.
  @Published var sentMessage: SentMessage?
  /// Whether activity rows start open. They start closed; the UI catalog opens them to show
  /// their contents.
  var activityExpandedByDefault = false
  /// The activity rows the person opened, by run. A row keeps it as it moves from under the sent
  /// message into its saved request and as its run ends. "pending" is the run not yet started.
  @Published var openActivities: Set<String> = []
  /// The reply of a run that just ended, kept on screen until the saved reply loads. It is the
  /// saved reply's own text when the run returned it, so the two look the same.
  struct LandingAnswer: Equatable {
    let request: String
    let run: String
    let text: String
  }
  @Published var landingAnswer: LandingAnswer?
  /// How a run that ended in this window ended, and its time from Send. The activity row reads
  /// the same before the saved run loads, when that still says it is running, and after.
  struct EndedRun: Equatable {
    let state: String
    let started: Date
    let ended: Date
  }
  @Published var endedRuns: [String: EndedRun] = [:]
  /// The run that just ended with a reply on its way. Its last thoughts stay under it until the
  /// first refresh read after it ended, which has the reply when there is one.
  @Published var settlingRun: String?
  /// What the run that is ending returned, until its operation finishes.
  private var runOutcome: (run: String, state: String, answer: String)?
  /// Which saved replies have a change row, read with each refresh.
  let receiptHints = ConversationReceiptHints()
  /// Whether the chat on screen already shows a saved message after this request.
  func hasReply(to request: String) -> Bool {
    let shown = messages.filter { $0.role != "tool" }
    guard let index = shown.firstIndex(where: { $0.id == request }) else { return false }
    return index + 1 < shown.count
  }
  @Published var proposalReviews: [String: ProposalReviewState] = [:]
  @Published var hasEarlierMessages = false
  @Published var hasLaterMessages = false
  @Published var showingHistorySearch = false
  private var conversationNavigationIdentity = UUID()
  let historySearch = ConversationHistorySearch()
  /// The workbook's chats, most recently active first.
  @Published var chats: [Chat] = []
  /// The chat list shown in place of the open chat.
  @Published var showingChats = false
  @Published var chatRename: ChatRename?
  @Published var workbookRename: WorkbookRename?
  /// Set by the window that holds the workbook, which is what moves its file. Nil elsewhere, and
  /// the workbook then shows its name without the menu.
  var renameWorkbook: ((String) async throws -> Void)?
  @Published var chatDeletion: Chat?
  @Published var composerFocusRequest = UUID()
  @Published var pendingExtractions: [Value] = []
  @Published var importProgress: (saved: Int, total: Int)?
  @Published var activeIntake: String?
  @Published var intakePrompt: IntakePrompt?
  @Published var conversation = "" {
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
  private var navigationReturns: [WorkbookReadingTarget] = []
  weak var readingWindow: NSWindow?
  @Published var readingFocusRequest = UUID()
  var readingFocusPending = false
  private(set) var readingFocusTarget: WorkbookReadingTarget = .workspace
  @Published var terminalStatus: String?
  /// Spoken to screen readers only, such as a finished reply that needs no status line.
  @Published var announcement: String?
  /// A finished operation sends the next waiting message once a refresh shows its outcome.
  private var queueAdvanceDue = false
  /// The waiting message being sent, so a refusal before it reaches the chat can put it back.
  private var dispatchedQueued: (message: QueuedConversationMessage, chat: String)?
  private var operationTitle = ""
  func requestReadingFocus(_ target: WorkbookReadingTarget) {
    if target == .conversation || target == .composer { focus = false }
    if case .message = target { focus = false }
    readingFocusTarget = target
    readingFocusPending =
      ReadingFocusPolicy.canRequest(
        appIsActive: NSApp.isActive, ownWindowIsKey: readingWindow?.isKeyWindow == true,
        ownSheetIsKey: readingWindow?.attachedSheet?.isKeyWindow == true)
    readingFocusRequest = UUID()
  }
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
  @Published private(set) var changingConversation = false {
    didSet {
      // A message left unsent goes back into the composer of its chat, which the change saves
      // as that chat's draft, so leaving the chat never loses it.
      if changingConversation, !oldValue { keepNotSentAsDraft() }
      if !changingConversation, unsentAwaitsChange {
        unsentAwaitsChange = false
        returnUnsent()
      }
    }
  }
  /// A change saves the drafts it leaves, so a message that fails meanwhile waits for it.
  private var unsentAwaitsChange = false
  @Published var readingRequest = UUID()
  private var restoringConversation = false
  @Published var prompt = "" {
    didSet {
      if prompt != oldValue && !applyingDictation { speech.stop() }
      if !restoringConversation { conversationSession.updateDraft(prompt) }
      // Typing restarts an engine the idle timer stopped, before Send needs it.
      if oldValue.isEmpty && !prompt.isEmpty && !restoringConversation { prewarmLocalAI() }
    }
  }
  private let automationBusyOwner = UUID()
  @Published var busy = false {
    didSet { automation.setBusy(automationBusyOwner, busy) }
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
  let speech: SpeechInput
  func open(_ url: URL) async throws {
    // Opening checks the whole schema and can wait for another process to let go of the workbook.
    let opened = try await Task.detached(priority: .userInitiated) {
      let book = try Workbook(url)
      try book.recoverConversationAttachments()
      return book
    }.value
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
      conversation: defaults.string(forKey: "lastConversation:" + opened.url.path))
    try require(
      restored, "conversation_save",
      conversationSession.failure ?? "Could not restore the chat draft.")
    _ = await formDrafts.open(opened)
    let clarificationOpened = await clarificationDrafts.open(opened)
    try require(
      clarificationOpened, "clarification_draft_save",
      "Save or preserve clarification inputs before opening another workbook.")
    await spaceNavigation.open(opened)
    endInteraction()
    closeNativeApps()
    workbook = opened
    spaces = []
    items = []
    pendingReview = nil
    reviewResults.reset()
    datasets = []
    archivedDatasets = []
    homeDocuments = []
    pendingWorkflows = []
    chatApproval = nil
    pendingInputs = []
    pendingInput = nil
    replyInputID = nil
    conversationVisuals = [:]
    imageInspection = nil
    visualInspection = nil
    resumableAnswer = nil
    excelImports = []
    excelPurposeDrafts = [:]
    messages = []
    proposalReviews = [:]
    chats = []
    showingChats = false
    pendingExtractions = []
    importProgress = nil
    activeIntake = nil
    intakePrompt = nil
    revision = 0
    conversation = conversationSession.conversation
    route = .space("home")
    navigation = []
    navigationReturns = []
    terminalStatus = nil
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
    prewarmLocalAI()
  }

  /// Starts the local engine while the person reads or types, so Send does not wait for the
  /// model to load. Nothing is sent to it, and the request that follows reports any failure.
  func prewarmLocalAI() { Self.prewarmLocalAI(ai, defaults: defaults) }
  /// Also for the start window and the app coming forward, which have no workbook yet.
  static func prewarmLocalAI(_ ai: ProductAI? = nil, defaults: UserDefaults = .standard) {
    guard AppHost.allowsBackgroundServices else { return }
    let ai = ai ?? AppHost.ai
    let path =
      defaults.string(forKey: ProductAI.preferenceKey).map { URL(fileURLWithPath: $0) }
      ?? ProductAI.defaultDirectory
    Task { await ai.prewarm(modelDirectory: path) }
  }
  init(
    ai: ProductAI? = nil, defaults: UserDefaults = .standard,
    automation: NativeAutomationHost? = nil,
    appExchange: (@Sendable (Data) async throws -> Data)? = nil, speech: SpeechInput? = nil
  ) {
    self.ai = ai ?? AppHost.ai
    self.defaults = defaults
    self.automation = automation ?? .shared
    self.appExchange = appExchange
    self.speech = speech ?? AppHost.speech()
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
    // Quitting saves composers before windows close, so a message not sent goes into its
    // composer first. Delivered on the posting thread, before that save.
    notSentObserver = NotificationCenter.default.addObserver(
      forName: .sevraKeepNotSent, object: nil, queue: nil
    ) { [weak self] _ in MainActor.assumeIsolated { self?.keepNotSentAsDraft() } }
  }
  private var notSentObserver: NSObjectProtocol?
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
      landingAnswer = nil
      settlingRun = nil
      endedRuns = [:]
      openActivities = []
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
    let activeInputID = replyInputID
    let contents = contents
    let receiptHints = receiptHints
    // A read that starts after a run ended sees its saved reply, if it has one.
    let settled = settlingRun
    refreshSession.request(identity: identity, onlyWhenIdle: polling && !changedView) { control in
      let started = ChatTiming.now
      let snapshot = try book.workspaceSnapshot(
        conversation: identity.conversation, messageAnchor: readingAnchor,
        activeInputID: activeInputID,
        ifChangedFrom: knownRevision, ifSpaceNavigationMatches: knownSpaceNavigation,
        cancellation: control)
      ChatTiming.record(
        "ui.refresh_read", since: started,
        ["polling": .bool(polling), "changed": .bool(snapshot != nil)])
      if let snapshot {
        try ChatTiming.span(
          "ui.refresh_prepare", ["messages": .number(Double(snapshot.messages.count))]
        ) {
          let open = Set(snapshot.pendingInputs.map(\.id))
          try contents.prepare(
            snapshot.messages, body: { Self.displayBody($0, open: open) }, cancellation: control)
          try receiptHints.prepare(
            snapshot.messages, book: book, conversation: identity.conversation,
            cancellation: control)
        }
      }
      return snapshot
    } complete: { [weak self] result in
      guard let self, self.interactionActive, self.workbook === book,
        self.interactionIdentity == identity.window,
        self.conversation == identity.conversation, self.messageAnchor == identity.messageAnchor,
        self.replyInputID == activeInputID
      else { return }
      switch result {
      case .success(let snapshot):
        guard let snapshot else {
          if settled != nil, settled == self.settlingRun { self.settlingRun = nil }
          self.advanceQueueIfDue()
          return
        }
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
        let oldReviews = self.pendingReview.map { Set($0.items.map(\.id)) }
        self.pendingReview = snapshot.reviewQueue
        if let oldReviews,
          snapshot.reviewQueue.items.contains(where: { !oldReviews.contains($0.id) })
        {
          self.terminalStatus = "Drafts are ready. Ask to review or accept them here in chat."
        }
        self.items = snapshot.items
        self.datasets = snapshot.datasets
        self.archivedDatasets = snapshot.archivedDatasets
        self.homeDocuments = snapshot.homeDocuments
        self.pendingWorkflows = snapshot.pendingWorkflows
        self.datasetSnapshot = snapshot.datasetSnapshot
        self.presentationSnapshot = snapshot.presentationSnapshot
        self.chatApproval = snapshot.chatApproval
        self.pendingInputs = snapshot.pendingInputs
        self.pendingInput = snapshot.pendingInput
        if let replyInputID = self.replyInputID,
          !snapshot.pendingInputs.contains(where: { $0.id == replyInputID })
        {
          self.replyInputID = nil
        }
        self.conversationVisuals = snapshot.visuals
        self.resumableAnswer = snapshot.resumableAnswer
        self.excelImports = snapshot.excelImports
        // In the same update as the messages, so the reply takes the thoughts' place at once.
        if settled != nil, settled == self.settlingRun { self.settlingRun = nil }
        self.messages = snapshot.messages
        self.contents.retain(snapshot.messages)
        self.receiptHints.retain(snapshot.messages)
        if let waiting = ChatTiming.awaitingReply, self.hasReply(to: waiting) {
          ChatTiming.replyInView(waiting)
        }
        if let landing = self.landingAnswer,
          self.hasReply(to: landing.request)
            || !snapshot.messages.contains(where: { $0.id == landing.request })
        {
          self.landingAnswer = nil
        }
        self.requestActivities = snapshot.requestActivities
        self.proposalReviews = snapshot.proposalReviews
        self.hasEarlierMessages = snapshot.hasEarlierMessages
        self.hasLaterMessages = snapshot.hasLaterMessages
        self.chats = snapshot.chats
        self.pendingExtractions = snapshot.pendingExtractions
        if !self.busy { self.importProgress = nil }
        self.advanceQueueIfDue()
      case .failure(let failure):
        // The open chat was deleted from outside this window, such as from the command line.
        if (failure as? SevraError)?.code == "chat_deleted" {
          self.leaveDeletedChat()
          return
        }
        // A busy workbook can be retried by the next timer tick. An explicit
        // refresh reports its failure while preserving the last complete view.
        if !polling || (failure as? SevraError)?.code != "deadline" {
          self.error = failure.localizedDescription
        }
      }
    }
  }
  @discardableResult func navigate(
    _ new: Route, replacing: Bool = false, returningTo: WorkbookReadingTarget = .workspace
  ) -> Bool {
    guard documentDrafts.flush() else { return false }
    let shown: Route
    if case .item(let id) = route { shown = .item(viewedItemVersion ?? id) } else { shown = route }
    if shown != new {
      if !replacing {
        navigation.append(shown)
        navigationReturns.append(returningTo)
      }
      if navigation.count > 20 {
        navigation.removeFirst()
        navigationReturns.removeFirst()
      }
      route = new
      referenceModal = nil
      viewedItemVersion = nil
      itemPreviewIdentity = UUID()
      selectedContext = ""
      if case .space(let id) = new { spaceNavigation.visit(id) }
      requestReadingFocus(.workspace)
    }
    return true
  }
  func openEvidence(
    _ id: String, locator: String? = nil, returningTo: WorkbookReadingTarget = .workspace
  ) {
    guard navigate(.item(id), returningTo: returningTo) else { return }
    if let locator {
      itemLocators[id] = locator
      locatorRequest = UUID()
    }
  }
  func jumpToMessage(_ id: String) {
    do {
      guard let book = workbook else { return }
      let chat = try book.messageLocation(id)["conversation_id"].text
      guard try book.chats().contains(where: { $0.id == chat }) else {
        throw SevraError("chat_deleted", "That message is in a chat that was deleted.")
      }
      changeConversation(chat, anchor: id)
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
      requestReadingFocus(navigationReturns.popLast() ?? .workspace)
    }
  }
  func continueWorkflow(_ runID: String, retry: Bool = false) {
    guard let (book, ticket) = beginOperation("Continuing workflow") else { return }
    let path =
      defaults.string(forKey: ProductAI.preferenceKey).map { URL(fileURLWithPath: $0) }
      ?? ProductAI.defaultDirectory
    Task {
      defer { finishOperation(ticket, in: book) }
      do {
        let session = try await Task.detached {
          let session = try book.authorizeWorkflowExecution(
            runID, actor: .human("Sevra.native-workflow-continue"))
          if retry {
            _ = try book.retryWorkflow(
              session, token: identifier(), actor: .human("Sevra.native-workflow-retry"))
          }
          return session
        }.value
        await automation.yieldForInteractive()
        try ticket.cancellation.check()
        _ = try await ai.continueWorkflow(
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
    _ title: String, successStatus: String? = nil,
    operation: @escaping @Sendable (Workbook, Cancellation) throws -> Result,
    completion: @escaping @MainActor (Result) -> Void
  ) {
    guard let (book, ticket) = beginOperation(title) else { return }
    Task {
      defer { finishOperation(ticket, in: book, successStatus: successStatus) }
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
  /// A short change from a control on screen, such as a view button: it takes the same turn as
  /// any operation, so nothing else writes meanwhile, but leaves the window as it is. No busy
  /// state, no working row in the chat, no status bar taken away and put back: a press that
  /// lasts a moment would otherwise make the whole window change twice.
  func beginQuietOperation() -> (Workbook, WorkspaceOperation)? {
    guard interactionActive, let book = workbook, !busy, quietOperation == nil,
      let ticket = operations.begin()
    else { return nil }
    quietOperation = ticket
    return (book, ticket)
  }
  func finishQuietOperation(
    _ ticket: WorkspaceOperation, in book: Workbook, status: String?
  ) {
    guard owns(ticket, in: book), operations.finish(ticket) else { return }
    quietOperation = nil
    if error == nil, let status, !status.isEmpty { terminalStatus = status }
    // A message typed during the press waited in the queue.
    queueAdvanceDue = !queue.isEmpty
    refresh()
  }
  /// The quiet operation running now, if any.
  private(set) var quietOperation: WorkspaceOperation?
  /// The running operation belongs to the chat: a request, a confirmation, an Undo from a
  /// message. Only then does the chat show a working row for it.
  @Published private(set) var operationInChat = false
  func beginOperation(_ title: String, inChat: Bool = false) -> (Workbook, WorkspaceOperation)? {
    guard interactionActive, let book = workbook, !busy, quietOperation == nil,
      let ticket = operations.begin()
    else {
      return nil
    }
    busy = true
    status = title
    operationTitle = title
    operationInChat = inChat
    // The last outcome stays in its bar, dimmed, until this one ends: taking the bar away and
    // putting it back moves the whole window twice.
    announcement = nil
    error = nil
    return (book, ticket)
  }
  func owns(_ ticket: WorkspaceOperation, in book: Workbook) -> Bool {
    interactionActive && workbook === book && operations.owns(ticket)
  }
  // Excel builds and ordinary conversation share the same request identity,
  // cancellation guard and revision-aware activity refresh.
  func updateAgentActivity(_ value: String, for ticket: WorkspaceOperation, in book: Workbook) {
    guard owns(ticket, in: book), operations.acceptsProgress(ticket) else { return }
    status = value
    liveActivity?.update(value)
    requestRefresh(polling: true)
  }
  func attachAgentActivity(
    _ request: AgentRequest, conversation: String, for ticket: WorkspaceOperation, in book: Workbook
  ) {
    guard owns(ticket, in: book), operations.acceptsProgress(ticket) else { return }
    liveActivity?.attach(request, conversation: conversation)
    // A row opened before the run had an ID stays open under its ID.
    if openActivities.remove("pending") != nil { openActivities.insert(request.runID) }
    refresh()
  }
  func finishOperation(
    _ ticket: WorkspaceOperation, in book: Workbook, successStatus: String? = nil
  ) {
    guard owns(ticket, in: book), operations.finish(ticket) else { return }
    let succeeded = error == nil && !ticket.cancellation.isCancelled
    terminalStatus =
      error == nil
      ? (ticket.cancellation.isCancelled
        ? "Stopped. Saved work is kept."
        : successStatus.map { $0.isEmpty ? nil : $0 }
          ?? ("Operation ended: " + operationTitle
            + ". Read the result or conversation for its outcome."))
      : nil
    dispatchedQueued = nil
    if succeeded, successStatus?.isEmpty == true { announcement = "Reply finished." }
    if succeeded {
      queueAdvanceDue = !queue.isEmpty
    } else {
      pauseQueue()
    }
    busy = false
    status = ""
    if let live = liveActivity, let run = live.runID {
      let outcome = runOutcome?.run == run ? runOutcome : nil
      let stopped = ticket.cancellation.isCancelled
      endedRuns[run] = .init(
        state: stopped ? "cancelled" : error != nil ? "failed" : outcome?.state ?? "complete",
        started: live.started, ended: Date())
      if error == nil, !stopped, let request = live.requestID, !hasReply(to: request) {
        settlingRun = run
        // The reply as saved, when the run returned a finished one: its links and notes are
        // already in it, so the saved message that replaces it looks the same. Otherwise the
        // answer as written stays until the saved message, which has a shape of its own, loads.
        let text = outcome?.state == "complete" ? outcome?.answer : live.answerPreview
        if let text, !text.isEmpty { landingAnswer = .init(request: request, run: run, text: text) }
      }
    }
    runOutcome = nil
    liveActivity = nil
    // A message kept as not sent says so under itself; the bar would only repeat it.
    if sentMessage?.failure != nil { terminalStatus = nil } else { sentMessage = nil }
    activeIntake = nil
    refresh()
  }
  func report(_ failure: Error, for ticket: WorkspaceOperation, in book: Workbook) {
    guard owns(ticket, in: book) else { return }
    // A requested stop has a neutral terminal status. Do not hide a genuine
    // failure that happens to arrive after Stop was pressed.
    if ticket.cancellation.isCancelled, (failure as? SevraError)?.code == "cancelled" { return }
    error = failure.localizedDescription
  }
  func promoteVisual(_ messageID: String, index: Int) {
    guard !busy, let expected = spaces.first(where: { $0.id == "home" })?.version,
      let (book, ticket) = beginOperation("Adding view to Home")
    else { return }
    let chat = conversation
    Task {
      var saved = false
      defer {
        finishOperation(ticket, in: book, successStatus: saved ? "View added to Home." : nil)
      }
      do {
        let visual = try await Task.detached(priority: .userInitiated) {
          try ticket.cancellation.check()
          return try book.conversationVisual(messageID, index: index, conversation: chat)
        }.value
        if let reference = visual.appReference {
          let app = try book.space(reference.spaceID)
          try require(
            app.version == reference.version && app.definition.app?.digest == reference.digest,
            "stale_app", "Reopen the app and capture its current view.")
          _ = try await nativeAppSession(app, book: book).withVisualAccess(committing: true) {
            book, access in
            try ticket.cancellation.check()
            return try book.pinNativeAppView(
              access, view: reference.viewID,
              presetID: reference.presetID, expectedHomeVersion: expected)
          }
        } else {
          _ = try await Task.detached {
            try ticket.cancellation.check()
            return try book.promoteConversationVisual(
              messageID, index: index,
              conversation: chat, expectedVersion: expected)
          }.value
        }
        saved = true
      } catch { report(error, for: ticket, in: book) }
    }
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
    let panel = AppHost.openPanel(for: workbook)
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.treatsFilePackagesAsDirectories = true
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK, interactionActive, workbook === book,
      conversation == chat, interactionIdentity == identity
    else { return }
    importFiles(panel.urls, linked: linked)
  }
  /// One explicit comparison of a folder, shown before anything is added.
  func folderPanel() {
    guard interactionActive, !busy, workbook != nil else { return }
    let panel = AppHost.openPanel(for: workbook)
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
    _ urls: [URL], linked: Bool = false, tokens: [URL: String] = [:], finished: String? = nil,
    removing staging: URL? = nil
  ) {
    let chat = conversation
    let navigation = itemPreviewIdentity
    run(
      linked ? "Linking files" : "Including files",
      successStatus: finished ?? (linked ? "Files linked." : "Files added."),
      operation: { book, cancel in
        defer { if let staging { try? FileManager.default.removeItem(at: staging) } }
        var failures: [String] = []
        var excel: [String] = []
        for url in urls {
          try cancel.check()
          do {
            // Capturing a file is enough to make it evidence. Table conversion
            // remains an explicit later request, never an import prerequisite.
            let job = try book.captureConversationAttachment(
              url, linked: linked, conversation: chat, token: tokens[url] ?? identifier(),
              cancellation: cancel)
            _ = try book.runIntake(job.id, cancellation: cancel)
            if ["xlsx", "xlsm"].contains(url.pathExtension.lowercased()) {
              excel.append(
                try book.beginExcelConversion(sourceID: job.sourceID, cancellation: cancel).id)
            }
          } catch {
            if cancel.isCancelled { throw error }
            failures.append(url.lastPathComponent + ": " + error.localizedDescription)
          }
        }
        if !failures.isEmpty {
          throw SevraError("import_partial", failures.joined(separator: "\n"))
        }
        if let finished { try Self.postEvent(finished, in: chat, book) }
        return excel
      },
      completion: { excel in
        guard self.itemPreviewIdentity == navigation else { return }
        self.composerFocusRequest = UUID()
        if let id = excel.first {
          self.navigate(.excelImport(id))
          if let book = self.workbook {
            _ = try? book.addMessage(
              "I added your Excel file. Tell me how you use it, or open its tables. I can use your description to build a workspace you can operate here in chat.",
              role: "assistant", conversation: chat)
            self.refresh()
          }
          self.composerFocusRequest = UUID()
        }
      })
  }
  func presentIntake(_ id: String) {
    if let book = workbook, let job = try? book.intakeJob(id), job.role != .update,
      let source = try? book.item(job.sourceID), let assetID = source.assetID,
      let asset = try? book.asset(assetID),
      ["xlsx", "xlsm"].contains(URL(fileURLWithPath: asset.name).pathExtension.lowercased())
    {
      useSavedFile(job.sourceID)
      return
    }
    run(
      "Reading saved intake",
      operation: { book, _ in
        let job = try book.intakeJob(id)
        let source = try book.item(job.sourceID)
        let asset = try book.asset(source.assetID!)
        return IntakeChoice(
          job: job, title: source.title,
          supportsTable: ["csv", "tsv", "xlsx", "xlsm"].contains(
            URL(fileURLWithPath: asset.name).pathExtension.lowercased()),
          supportsUpdate: ["csv", "tsv", "xlsx", "xlsm"].contains(
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
    let navigation = itemPreviewIdentity
    if let book = workbook, let source = try? book.item(sourceID), let assetID = source.assetID,
      let asset = try? book.asset(assetID),
      ["xlsx", "xlsm"].contains(URL(fileURLWithPath: asset.name).pathExtension.lowercased())
    {
      run(
        "Inspecting Excel workbook",
        operation: { book, cancel in
          try book.beginExcelConversion(sourceID: sourceID, cancellation: cancel).id
        },
        completion: {
          if self.itemPreviewIdentity == navigation { self.navigate(.excelImport($0)) }
        })
      return
    }
    run(
      "Preparing saved file",
      operation: { book, _ in
        let source = try book.item(sourceID)
        let asset = try book.asset(source.assetID!)
        return IntakeChoice(
          sourceID: source.id, title: source.title,
          supportsTable: ["csv", "tsv", "xlsx", "xlsm"].contains(
            URL(fileURLWithPath: asset.name).pathExtension.lowercased()),
          supportsUpdate: ["csv", "tsv", "xlsx", "xlsm"].contains(
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
        if choice.job == nil {
          _ = try book.beginIntake(sourceID: choice.sourceID, token: choice.id)
        }
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
            try Self.postEvent(result.detail, in: chat, book)
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
  func pasteImage() {
    guard interactionActive, !busy, !changingConversation else { return }
    let clipboard = NSPasteboard.general
    if let files = clipboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
      !files.isEmpty
    {
      guard
        files.allSatisfy({ url in
          UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
        })
      else {
        error = "Choose image files to paste."
        return
      }
      importFiles(files)
      return
    }
    let formats: [(NSPasteboard.PasteboardType, String)] = [(.png, "png"), (.tiff, "tiff")]
    guard let format = formats.first(where: { clipboard.types?.contains($0.0) == true }),
      let data = clipboard.data(forType: format.0)
    else {
      error = "Copy an image or image file first."
      return
    }
    guard !data.isEmpty && data.count <= 32 * 1024 * 1024 else {
      error = "Paste an image under 32 MB."
      return
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(identifier())
    do {
      try FileManager.default.createDirectory(
        at: temporary, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      let file = temporary.appendingPathComponent("Pasted image." + format.1)
      try data.write(to: file, options: .withoutOverwriting)
      importFiles([file], removing: temporary)
    } catch {
      try? FileManager.default.removeItem(at: temporary)
      self.error = error.localizedDescription
    }
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
        // Done keeps this original as evidence without selecting a conversion.
        // Complete its queued indexing before presenting those optional choices.
        try book.extract(source.id, cancellation: cancel)
        return IntakeChoice(
          sourceID: source.id, title: "Copied table range (values only)", supportsTable: true,
          supportsUpdate: true)
      }, completion: { choice in self.intakePrompt = .init(choices: [choice]) })
  }
  func exportPanel() {
    guard interactionActive, !busy, let book = workbook, documentDrafts.flush() else { return }
    let identity = interactionIdentity
    let panel = AppHost.savePanel()
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
  /// The waiting messages of the open chat.
  var queue: ConversationQueue { conversationSession.state.queue }
  /// While a reply runs, an ordinary message waits in the queue; Stop and other commands that
  /// are allowed during work still act at once.
  private func queues(_ input: String) -> Bool {
    (busy || quietOperation != nil)
      && !WorkspaceControlCommand.allowsSubmission(input, busy: true)
  }
  var canSend: Bool {
    conversationSession.ready && !changingConversation && !conversationSession.loading
      && (WorkspaceControlCommand.allowsSubmission(prompt, busy: busy)
        || (queues(prompt)
          && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
  }
  func send() {
    guard interactionActive, let book = workbook, canSend,
      !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    ChatTiming.pressedSend()
    speech.stop()
    let input = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    do { try ComposerInput.admit(input) } catch {
      self.error = error.localizedDescription
      return
    }
    if queues(input) {
      enqueue(input)
      return
    }
    submit(input, selection: selectedContext, book: book, fromComposer: true)
  }
  /// One message, typed now or sent from the queue. Only a typed message clears the composer,
  /// so a queued message never removes what the person is writing.
  private func submit(_ input: String, selection: String, book: Workbook, fromComposer: Bool) {
    let clearComposer = { if fromComposer { self.prompt = "" } }
    if input.lowercased().hasPrefix("answer:") {
      guard let surface = exactReplyInput() else { return }
      let reply = input.dropFirst("answer:".count).trimmingCharacters(in: .whitespacesAndNewlines)
      let response: ConversationInputResponse =
        reply.lowercased() == "skip"
        ? .decline : reply.lowercased() == "decline" ? .cancel : .text(reply)
      if submitInput(surface, response: response) { clearComposer() }
      return
    }
    if input.lowercased() == "cancel question" {
      guard let surface = exactReplyInput() else { return }
      if submitInput(surface, response: .cancel) { clearComposer() }
      return
    }
    if input.lowercased() == "retry continuation", let answerID = resumableAnswer {
      clearComposer()
      retryInput(answerID)
      return
    }
    if let answerCommand = WorkflowAnswerCommand.parse(input) {
      clearComposer()
      workflowAnswerCommand(answerCommand, input: input, book: book)
      return
    }
    clarificationDrafts.invalidateConversationPreviews()
    if let command = WorkspaceControlCommand.parse(input), command != .openCopy {
      clearComposer()
      error = nil
      control(command, input: input, book: book)
      if error != nil { returnInput(input) }
      return
    }
    if documentCommand(input, book: book) {
      clearComposer()
      refresh()
      return
    }
    guard documentDrafts.flush() else { return }
    clearComposer()
    error = nil
    messageAnchor = nil
    conversationSession.updateReading(.init())
    readingRequest = UUID()
    if let target = WorkspaceControlCommand.captureURL(input) {
      unsent = (input, conversation, book)
      guard let (_, ticket) = beginOperation("Capturing source", inChat: true) else {
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
    if handleChatConfirmation(input, book: book) {
      refresh()
      return
    }
    if localCommand(input, book: book) {
      _ = try? book.addMessage(input, role: "user", conversation: conversation)
      refresh()
      return
    }
    runChat(input, book: book, selection: selection)
  }

  private func exactReplyInput() -> ConversationSurface? {
    if let pendingInput, pendingInput.conversation == conversation,
      pendingInput.id == replyInputID || (replyInputID == nil && pendingInputs.count == 1)
    {
      return pendingInput
    }
    error =
      pendingInputs.isEmpty
      ? "There is no question waiting in this chat."
      : "Choose a question to answer from Pending questions."
    return nil
  }

  func targetInput(_ surface: ConversationInputReference) {
    guard pendingInputs.contains(where: { $0.id == surface.id }) else { return }
    replyInputID = surface.id
    changeConversation(conversation, anchor: surface.id)
  }

  func clearReplyTarget() {
    replyInputID = nil
    refresh()
  }

  @discardableResult func submitInput(
    _ surface: ConversationSurface, response: ConversationInputResponse, draftRevision: Int? = nil
  ) -> Bool {
    guard interactionActive, !busy, !changingConversation, let book = workbook,
      surface.conversation == conversation
    else { return false }
    do {
      let answer = try book.submitConversationInput(
        surface, response: response, draftRevision: draftRevision)
      pendingInputs.removeAll { $0.id == surface.id }
      if pendingInput?.id == surface.id { pendingInput = nil }
      if replyInputID == surface.id { replyInputID = nil }
      resumableAnswer = answer
      refresh()
      if let answer { retryInput(answer) }
      return true
    } catch {
      self.error = error.localizedDescription
      refresh()
      return false
    }
  }

  func retryInput(_ id: String) {
    guard interactionActive, !busy, !changingConversation, let book = workbook,
      resumableAnswer == id
    else { return }
    runChat("", book: book, inputAnswerID: id)
  }

  private func runChat(
    _ input: String, book: Workbook, selection: String? = nil, inputAnswerID: String? = nil
  ) {
    let selection = selection ?? selectedContext
    if inputAnswerID == nil { unsent = (input, conversation, book) }
    let timed = ChatTiming.beginTurn(
      origin: inputAnswerID == nil ? "app" : "app_reply", conversation: conversation)
    guard let (_, ticket) = beginOperation("Preparing local AI", inChat: true) else {
      if timed { ChatTiming.endTurn(outcome: "not_started") }
      returnUnsent()
      return
    }
    // Set on the agent's own thread, so a failure right after admission still sees it.
    let admitted = OSAllocatedUnfairLock(initialState: false)
    openActivities.remove("pending")
    runOutcome = nil
    liveActivity = LiveRequestActivity(conversation: conversation)
    let fromQueue = dispatchedQueued != nil
    sentMessage = inputAnswerID == nil ? SentMessage(text: input, conversation: conversation) : nil
    let chat = conversation
    let navigationID = itemPreviewIdentity
    let context = agentContext + (selection.isEmpty ? "" : "\nSelection: " + selection)
    let conversationOrigin = conversationNavigationIdentity
    let path =
      defaults.string(forKey: ProductAI.preferenceKey).map { URL(fileURLWithPath: $0) }
      ?? ProductAI.defaultDirectory
    Task {
      defer { finishOperation(ticket, in: book, successStatus: "") }
      var expectedNavigationID = navigationID
      let openRequestedView: @MainActor @Sendable (Route) throws -> Void = { destination in
        guard self.owns(ticket, in: book), self.conversation == chat,
          self.itemPreviewIdentity == expectedNavigationID,
          self.conversationNavigationIdentity == conversationOrigin,
          !ticket.cancellation.isCancelled, !self.changingConversation
        else {
          throw SevraError(
            "workspace_changed",
            "You moved to another view or chat. No view was opened. Ask again from the view you want to use."
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
        ChatTiming.mark("ui.task_started")
        let draftsSaved = await ChatTiming.asyncSpan("ui.save_workflow_drafts") {
          await clarificationDrafts.flush()
        }
        guard draftsSaved else {
          throw SevraError(
            "clarification_draft",
            "Your workflow inputs could not be saved. Preserve them before sending another request."
          )
        }
        try ticket.cancellation.check()
        await ChatTiming.asyncSpan("ui.yield_automation") { await automation.yieldForInteractive() }
        try ticket.cancellation.check()
        let result = try await ai.run(
          input, workbook: book, conversation: chat, context: context, modelDirectory: path,
          cancellation: ticket.cancellation,
          progress: { value in
            let sent = ChatTiming.now
            Task { @MainActor in
              ChatTiming.add("ui.progress_main_delay", seconds: ChatTiming.now - sent)
              self.updateAgentActivity(value, for: ticket, in: book)
            }
          },
          answerPreview: { update in
            let sent = ChatTiming.now
            Task { @MainActor in
              ChatTiming.add("ui.preview_main_delay", seconds: ChatTiming.now - sent)
              guard self.owns(ticket, in: book), self.operations.acceptsProgress(ticket),
                self.liveActivity?.conversation == chat
              else { return }
              if self.liveActivity?.answerPreview?.isEmpty ?? true, update.text?.isEmpty == false {
                ChatTiming.mark("ui.first_answer_text")
              }
              self.liveActivity?.show(
                update.text, reasoning: update.reasoning, thoughts: update.thoughts,
                sequence: update.sequence)
            }
          },
          requestStarted: { request, destination in
            admitted.withLock { $0 = true }
            ChatTiming.mark("ui.request_saved")
            Task { @MainActor in
              ChatTiming.mark("ui.request_attached")
              self.unsent = nil
              self.attachAgentActivity(request, conversation: destination, for: ticket, in: book)
            }
          },
          openSpace: { target in try openRequestedView(.space(target.id)) },
          openReviews: { try openRequestedView(.reviews) },
          workspaceAction: { action, arguments, readOnly, cancellation in
            try require(
              self.owns(ticket, in: book) && self.conversation == chat, "workspace_changed",
              "This workbook conversation changed.")
            return try await self.performChatAction(
              action, arguments: arguments, book: book, readOnly: readOnly,
              cancellation: cancellation)
          }, conversationInput: true, inputAnswerID: inputAnswerID)
        if owns(ticket, in: book), let run = liveActivity?.runID {
          runOutcome = (run, result.state, result.answer)
        }
        ChatTiming.requestFinished(awaitingReplyTo: liveActivity?.requestID, outcome: result.state)
        unsent = nil
        guard owns(ticket, in: book) else { return }
        refresh()
        nameWork(book, chat: chat, modelDirectory: path)
        let present =
          conversation == chat && itemPreviewIdentity == expectedNavigationID
          && conversationNavigationIdentity == conversationOrigin
          && !ticket.cancellation.isCancelled && !changingConversation
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
        ChatTiming.requestFinished(
          awaitingReplyTo: nil, outcome: ticket.cancellation.isCancelled ? "cancelled" : "failed")
        if admitted.withLock({ $0 }) {
          unsent = nil
          // The chat already says it under the message when the run recorded the failure, so the
          // bar below would only repeat it. It still shows a failure the chat did not record.
          let shown = error.localizedDescription
          let recorded = await Task.detached {
            (try? book.messages(conversation: chat, limit: 1))?.last.map {
              $0.role == "assistant" && ["failed", "cancelled"].contains($0.state)
                && $0.body == shown
            } ?? false
          }.value
          if !recorded { report(error, for: ticket, in: book) }
        } else if !fromQueue, keepNotSent(error, cancelled: ticket.cancellation.isCancelled,
          chat: chat, book: book)
        {
          unsent = nil
        } else {
          returnUnsent()
          report(error, for: ticket, in: book)
        }
      }
    }
  }
  /// After a reply, while the engine is still running: Sevra names the chat and the workbook if
  /// they are still its to name. Any new request stops this first.
  private func nameWork(_ book: Workbook, chat: String, modelDirectory: URL) {
    let ai = self.ai
    Task {
      guard await ai.nameWork(book, conversation: chat, modelDirectory: modelDirectory),
        workbook === book
      else { return }
      objectWillChange.send()
      refresh()
    }
  }

  // MARK: A message that did not reach its chat

  /// Keeps a message that failed or was stopped before its chat saved it, under the chat with
  /// the reason, rather than back in the composer. False when it belongs elsewhere now.
  private func keepNotSent(_ failure: Error, cancelled: Bool, chat: String, book: Workbook) -> Bool
  {
    guard interactionActive, workbook === book, conversation == chat, !changingConversation,
      let sent = sentMessage, sent.conversation == chat
    else { return false }
    let stopped = cancelled && (failure as? SevraError)?.code == "cancelled"
    sentMessage = sent.failed(
      stopped ? "Not sent. You stopped it before Local AI was ready." : failure.localizedDescription)
    return true
  }
  /// Sends a message that was not sent, as it was.
  func retryNotSent() {
    guard let sent = sentMessage, sent.failure != nil, sent.conversation == conversation,
      let book = workbook, !busy, !changingConversation, conversationSession.ready
    else { return }
    sentMessage = nil
    submit(sent.text, selection: "", book: book, fromComposer: false)
  }
  /// Puts a message that was not sent back into the composer to change it.
  func editNotSent() {
    guard let sent = sentMessage, sent.failure != nil, sent.conversation == conversation else {
      return
    }
    sentMessage = nil
    returnInput(sent.text)
    composerFocusRequest = UUID()
  }
  /// Before the chat changes or the window closes. Quitting saves it through the composer too.
  func keepNotSentAsDraft() {
    guard let sent = sentMessage, sent.failure != nil else { return }
    sentMessage = nil
    if sent.conversation == conversation {
      returnInput(sent.text)
    } else if let workbook {
      try? ComposerInput.keep(sent.text, conversation: sent.conversation, in: workbook)
    }
  }

  // MARK: Waiting messages

  private func enqueue(_ input: String) {
    var next = queue
    do {
      try next.add(input, context: selectedContext, id: identifier(), queued: timestamp())
    } catch {
      self.error = error.localizedDescription
      return
    }
    conversationSession.updateQueue(next)
    prompt = ""
  }
  func editQueued(_ id: String, text: String) -> Bool {
    var next = queue
    do { try next.edit(id, text: text) } catch {
      self.error = error.localizedDescription
      return false
    }
    conversationSession.updateQueue(next)
    return true
  }
  func removeQueued(_ id: String) {
    var next = queue
    next.remove(id)
    conversationSession.updateQueue(next)
  }
  func moveQueued(_ id: String, by offset: Int) {
    var next = queue
    next.move(id, by: offset)
    conversationSession.updateQueue(next)
  }
  func moveQueued(_ id: String, before destination: String?) {
    var next = queue
    next.move(id, before: destination)
    conversationSession.updateQueue(next)
  }
  func clearQueue() {
    var next = queue
    next.clear()
    conversationSession.updateQueue(next)
  }
  /// The person's Resume: sends the next message now when nothing is running, even if a
  /// question is waiting, because they chose to continue.
  func resumeQueue() {
    var next = queue
    next.paused = false
    conversationSession.updateQueue(next)
    if !busy { sendNextQueued() }
  }
  private func pauseQueue() {
    guard !queue.isEmpty, !queue.paused else { return }
    var next = queue
    next.paused = true
    conversationSession.updateQueue(next)
  }
  /// Runs after a refresh, so the outcome of the finished reply is known. A failure, a waiting
  /// question or a change waiting for approval pauses instead of sending.
  private func advanceQueueIfDue() {
    guard queueAdvanceDue, !busy else { return }
    queueAdvanceDue = false
    // A reply that ended waiting on the person (a proposal to review, a question) also pauses.
    let lastReply = messages.last(where: { $0.role == "assistant" })?.state
    if error != nil || !pendingInputs.isEmpty || chatApproval != nil
      || ["needs_review", "needs_input", "failed"].contains(lastReply ?? "")
    {
      pauseQueue()
      return
    }
    sendNextQueued()
  }
  private func sendNextQueued() {
    guard interactionActive, let book = workbook, !busy, !changingConversation,
      conversationSession.ready
    else { return }
    var next = queue
    guard let message = next.takeNext() else { return }
    conversationSession.updateQueue(next)
    dispatchedQueued = (message, conversation)
    submit(message.text, selection: message.context, book: book, fromComposer: false)
    if !busy {
      // Handled at once, such as a local command: continue with the next one.
      dispatchedQueued = nil
      queueAdvanceDue = !queue.isEmpty
      refresh()
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
    guard !changingConversation else {
      unsentAwaitsChange = true
      return
    }
    self.unsent = nil
    // A waiting message that was refused before reaching its chat goes back to the top of the
    // queue, paused, instead of into what the person is typing.
    if let queued = dispatchedQueued, queued.chat == unsent.chat, queued.message.text == unsent.input,
      interactionActive, workbook === unsent.book, conversation == unsent.chat
    {
      dispatchedQueued = nil
      var next = queue
      if next.putBack(queued.message) {
        conversationSession.updateQueue(next)
        return
      }
    }
    if interactionActive, workbook === unsent.book, conversation == unsent.chat {
      returnInput(unsent.input)
    } else {
      do { try ComposerInput.keep(unsent.input, conversation: unsent.chat, in: unsent.book) } catch
      {
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
          command == .preview ? "Preparing answer preview" : "Saving your answer", inChat: true)
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
    case .space(let id):
      let native = spaces.first { $0.id == id }?.definition.app != nil
      return routeContext + "\nActive space ID: " + id
        + (native
          ? "\n" + ChatOperations.appOperationGuidance
          : "")
    case .item(let id):
      return routeContext + "\nActive item version ID: " + (viewedItemVersion ?? id)
    case .table(let id): return routeContext + "\nActive dataset ID: " + id
    case .tableUpdate(let source, _):
      return routeContext + "\nTable-update review for source ID: " + source
    case .excelImport(let id): return routeContext + "\nActive Excel import ID: " + id
    case .automation(let id): return routeContext + "\nActive exact automation version ID: " + id
    case .workflow(let id): return routeContext + "\nActive workflow run ID: " + id
    case .search, .reviews, .activity, .automations, .tools, .removed: return routeContext
    }
  }
  var routeContext: String {
    switch route {
    case .space(let id): return "Space: " + (spaces.first { $0.id == id }?.title ?? id)
    case .item(let id):
      return "Item: " + (viewedItemTitle ?? id)
    case .table(let id): return "Table: " + (dataset(id)?.title ?? id)
    case .tableUpdate: return "Review table update"
    case .excelImport:
      return
        "Excel import review. Use workspace_actions domain=excel to inspect, clarify, analyze, use tables or build the workspace directly in this conversation."
    case .search: return "Workbook search"
    case .reviews: return "Drafts to review"
    case .activity: return "Workflow activity"
    case .automations: return "Automations"
    case .tools:
      return "The workbook's saved tools. Enabling one is the user's step here, never a chat action. remove takes one out after the user confirms."
    case .removed:
      return "What was removed from the workbook. restore brings one back after the user confirms."
    case .automation:
      return
        "Inspecting a saved automation. Saving/opening never grants device execution permission."
    case .workflow:
      return "Inspecting a saved workflow run; opening it does not authorize execution."
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
      if lower == "add folder" || lower == "add a folder" {
        folderPanel()
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
        try await AppHost.transcribe(book, id: id, cancellation: ticket.cancellation) { value in
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
      guard error == nil else { return }
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
    let panel = AppHost.openPanel(for: workbook)
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
      let panel = AppHost.savePanel()
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
          if !AppHost.openExternal(copy) {
            error =
              "The copy was saved, but no app opened it. You can find it in the folder you chose."
          }
        } catch { report(error, for: ticket, in: book) }
      }
    } catch { self.error = error.localizedDescription }
  }
  func openConversationLink(_ url: URL) { openConversationLink(url, returningTo: .workspace) }
  func openConversationLink(_ url: URL, returningTo: WorkbookReadingTarget) {
    switch ConversationLinkTarget(url) {
    case .evidence(let id, let locator):
      openEvidence(id, locator: locator, returningTo: returningTo)
    case .message(let id): jumpToMessage(id)
    case .external: AppHost.openExternal(url)
    case nil: break
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
    chatRename = nil
    chatDeletion = nil
    showingHistorySearch = false
    showingChats = false
    if conversation != id {
      historySearch.reset()
      pendingInputs = []
      pendingInput = nil
      replyInputID = nil
      conversationVisuals = [:]
      imageInspection = nil
      visualInspection = nil
      resumableAnswer = nil
      chatApproval = nil
    }
    conversation = id
    conversationNavigationIdentity = UUID()
    if let workbook {
      defaults.set(id, forKey: "lastConversation:" + workbook.url.path)
    }
    selectedContext = ""
    if let anchor { conversationSession.updateReading(.init(message: anchor)) }
    restoreConversationPresentation()
    refresh()
    composerFocusRequest = UUID()
  }
  /// Shows the chat list, bringing the chat pane back when it was hidden.
  func showChats() {
    guard interactionActive else { return }
    focus = false
    showingChats = true
  }
  /// The open chat's title.
  var chatTitle: String {
    chats.first { $0.id == conversation }?.title ?? Workbook.newChatTitle
  }
  /// A chat cannot be deleted while an answer or an import is still working: either one
  /// writes its result into the chat it started in.
  var canDeleteChat: Bool { !busy && !changingConversation }
  /// An import's closing note. The chat it started in may have been deleted meanwhile; the
  /// import itself is saved either way.
  nonisolated static func postEvent(_ text: String, in chat: String, _ book: Workbook) throws {
    do { _ = try book.addMessage(text, role: "event", conversation: chat) } catch let error
      as SevraError where error.code == "chat_deleted"
    {}
  }
  /// Opens an empty chat. An open chat that is still empty is reused rather than repeated; the
  /// workbook says so, not the list on screen, which a fast second press can find out of date.
  func newChat() {
    guard interactionActive, !changingConversation, let book = workbook else { return }
    let open = conversation
    switchChat(owner: interactionIdentity) {
      try await Task.detached(priority: .userInitiated) {
        let current = try? book.chat(open)
        return current?.messageCount == 0 ? open : try book.createChat()
      }.value
    }
  }
  /// Moves off a chat deleted elsewhere. Its unsent draft cannot be saved into it any more.
  private func leaveDeletedChat() {
    guard interactionActive, !changingConversation, let book = workbook else { return }
    conversationSession.abandonUnsaved()
    switchChat(owner: interactionIdentity) {
      try await Task.detached(priority: .userInitiated) {
        try book.chats().first?.id ?? book.createChat()
      }.value
    }
  }
  func renameChat(_ id: String, title: String, token: String) async throws {
    guard let book = workbook else { return }
    let owner = interactionIdentity
    try await Task.detached(priority: .userInitiated) {
      try book.renameChat(id, title: title, token: token)
    }.value
    guard interactionIdentity == owner, workbook === book else { return }
    refresh()
  }
  /// Deletes a chat. Deleting the open one first moves to the most recent other chat, or to a
  /// new one when it was the last, so its draft is saved before the chat goes away.
  func deleteChat(_ id: String) {
    guard interactionActive, !changingConversation, let book = workbook else { return }
    let owner = interactionIdentity
    let next = chats.first { $0.id != id }?.id
    switchChat(owner: owner, moving: conversation == id) {
      let target: String
      if let next { target = next } else {
        target = try await Task.detached(priority: .userInitiated) { try book.createChat() }.value
      }
      return target
    } then: {
      // Nothing is working in this window, so a run still marked as running was cut off.
      try await Task.detached(priority: .userInitiated) {
        _ = try book.deleteChat(id, closingUnfinishedRuns: true)
      }.value
    }
  }
  /// Moves to the chat `destination` names, when `moving`, then runs `then` in the new chat.
  private func switchChat(
    owner: UUID, moving: Bool = true, _ destination: @escaping () async throws -> String,
    then: (() async throws -> Void)? = nil
  ) {
    speech.stop()
    clarificationDrafts.invalidateConversationPreviews()
    changingConversation = true
    Task {
      defer { changingConversation = false }
      do {
        if moving {
          guard await conversationSession.flush(), interactionActive, interactionIdentity == owner
          else { return }
          let id = try await destination()
          guard interactionActive, interactionIdentity == owner else { return }
          await selectConversation(id, owner: owner)
          guard conversation == id else { return }
        }
        try await then?()
        guard interactionActive, interactionIdentity == owner else { return }
        refresh()
      } catch { if interactionIdentity == owner { self.error = error.localizedDescription } }
    }
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
    keepNotSentAsDraft()
    guard !changingConversation, documentDrafts.flush() else { return false }
    let saved = await conversationSession.flush()
    await spaceNavigation.flush()
    let formsSaved = await formDrafts.flush()
    let clarificationsSaved = await clarificationDrafts.flush()
    return saved && formsSaved && clarificationsSaved && documentDrafts.flush()
  }
  /// SwiftUI can keep a closed window's views, and this state with them, long after the window is
  /// gone. The window saved before it closed, so the workbook is let go here and its connection
  /// and memory end with the window.
  func close() {
    keepNotSentAsDraft()
    closeNativeApps()
    endInteraction()
    conversationSession.close()
    formDrafts.close()
    clarificationDrafts.close()
    spaceNavigation.close()
    workbook = nil
    spaces = []
    items = []
    datasets = []
    archivedDatasets = []
    homeDocuments = []
    pendingWorkflows = []
    chatApproval = nil
    pendingInputs = []
    pendingInput = nil
    replyInputID = nil
    conversationVisuals = [:]
    imageInspection = nil
    visualInspection = nil
    resumableAnswer = nil
    excelImports = []
    excelPurposeDrafts = [:]
    messages = []
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
    keepNotSentAsDraft()
    interactionActive = false
    returnUnsent()
    showingChats = false
    chatRename = nil
    chatDeletion = nil
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
    sentMessage = nil
    landingAnswer = nil
    settlingRun = nil
    endedRuns = [:]
    openActivities = []
    runOutcome = nil
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
