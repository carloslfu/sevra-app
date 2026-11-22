import AVKit
import AppKit
import SevraAppUI
import SevraCore
import SevraMedia
import SevraPreviewUI
import SevraTableUI
import SevraVisualUI
import SevraVoice
import SwiftUI

struct ConversationImageInspection: Identifiable {
  let id = UUID()
  let title: String
  let preview: PreviewImage
  let zoom: Double
}

struct ConversationVisualInspection: Identifiable {
  enum Content {
    case captured(VisualResult)
    case current(NativeAppSession, VisualAppReference)
  }
  let id = UUID()
  let messageID: String
  let index: Int
  let conversation: String
  let content: Content
}

struct WorkbookView: View {
  @ObservedObject var state: WorkspaceState
  @State private var showSpaces = false
  @State private var editingSpace: Space?
  @State private var conversationFrames: [String: CGRect] = [:]
  @State private var visibleMessages: [String] = []
  @State private var hydratedChat: String?
  @State private var hydratedVisuals: [String: [VisualResult]] = [:]
  @FocusState private var composerFocused: Bool
  @AccessibilityFocusState private var readingFocus: WorkbookReadingTarget?
  @FocusState private var keyboardPane: WorkbookReadingTarget?
  let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button {
          state.focus.toggle()
          state.requestReadingFocus(state.focus ? .workspace : .conversation)
        } label: {
          Image(systemName: "sidebar.left")
        }.help(state.focus ? "Show conversation" : "Focus workspace")
          .accessibilityLabel(state.focus ? "Show conversation" : "Focus workspace")
        ObserverMark().fill(.primary).frame(width: 28, height: 28).accessibilityHidden(true)
        Text(state.workbook?.title ?? "Sevra").readingFont(.headline).accessibilityAddTraits(
          .isHeader
        ).lineLimit(1)
        Spacer()
        if state.busy {
          ProgressView().controlSize(.small)
          Text(state.status).readingFont(.caption).foregroundStyle(.secondary).lineLimit(1)
            .frame(maxWidth: 160).help(state.status)
          Button("Stop", action: state.stop)
        }
        Button {
          state.navigate(.search)
        } label: {
          Image(systemName: "magnifyingglass")
        }.help("Search documents, records and filenames").accessibilityLabel("Search workbook")
        Menu {
          Button("Include files…") { state.importPanel() }
          Button("Link external files…") { state.importPanel(linked: true) }
          Button("Add a folder…", action: state.folderPanel)
          Button("Paste image", action: state.pasteImage)
          Button("Paste table data…", action: state.pasteTableData)
        } label: {
          Label("Add files…", systemImage: "plus")
        } primaryAction: {
          state.importPanel()
        }.disabled(state.busy).accessibilityLabel("Add files, a folder or pasted data")
      }.padding(.horizontal, 20).padding(.vertical, 12)
      Divider()
      HSplitView {
        if !state.focus { conversation.frame(minWidth: 270, idealWidth: 360, maxWidth: 420) }
        VStack(spacing: 0) {
          PaneHeader {
            if !state.navigation.isEmpty {
              Button(action: state.back) { Image(systemName: "chevron.left") }.help("Back")
                .accessibilityLabel("Back to previous view")
                .keyboardShortcut("[", modifiers: .command)
            }
            if state.route != .space("home") {
              Button {
                state.navigate(.space("home"))
              } label: {
                Image(systemName: "house")
              }.help("Home").accessibilityLabel("Home")
            }
            Text(routeTitle).readingFont(.title3, weight: .medium).accessibilityAddTraits(.isHeader)
              .lineLimit(1).help(routeTitle)
              .accessibilityAddTraits(.isHeader)
              .focusable().focused($keyboardPane, equals: .workspace)
              .accessibilityFocused($readingFocus, equals: .workspace)
              .layoutPriority(1)
            Spacer()
            ViewThatFits(in: .horizontal) {
              workspaceActions
              workspaceActions.labelStyle(.iconOnly)
            }
            MoreActionsMenu("Workbook actions") {
              if case .space(let id) = state.route,
                let space = state.spaces.first(where: { $0.id == id })
              {
                if space.definition.app != nil {
                  Button("Update app…") { state.importNativeApp(replacing: space) }.disabled(
                    state.busy)
                  if state.homeShowsApp(space.id) {
                    Button("Open Home") { state.navigate(.space("home")) }
                  } else {
                    Button("Show on Home") { state.showAppOnHome(space) }.disabled(state.busy)
                  }
                  Button("App history…") { editingSpace = space }.disabled(state.busy)
                } else {
                  Button("Edit layout…") { editingSpace = space }.disabled(state.busy)
                  if id == "home" {
                    Button("Reset Home to default") { state.resetHome(space) }.disabled(state.busy)
                  }
                }
                if !space.definition.components.isEmpty && !space.definition.containsSections
                  && !space.definition.containsComponent("app")
                {
                  Button("Save a snapshot") {
                    state.pinSpace(
                      space.id,
                      title: space.title + " · "
                        + Date().formatted(date: .abbreviated, time: .shortened))
                  }.disabled(state.busy)
                }
                Divider()
              }
              Menu("Tables") {
                ForEach(state.datasets + state.archivedDatasets) { table in
                  Button(table.title + (table.archived ? " (archived)" : "")) {
                    state.navigate(.table(table.id))
                  }
                }
              }
              if !state.excelImports.isEmpty {
                Menu("Excel workbooks") {
                  ForEach(state.excelImports, id: \.text) { entry in
                    Button(entry["title"].text) { state.navigate(.excelImport(entry["id"].text)) }
                  }
                }
              }
              Button("Drafts to review") { state.navigate(.reviews) }
              Button("Workflow runs") { state.navigate(.activity) }
              Button("Automations") { state.navigate(.automations) }
              Button("Tools") { state.navigate(.tools) }
              Divider()
              Button("Make a shareable copy…", action: state.exportPanel).disabled(state.busy)
            }
          }
          Divider()
          workspace.frame(maxWidth: .infinity, maxHeight: .infinity)
          if let player = state.backgroundPlayer {
            Divider()
            HStack {
              NativeMediaPlayer(player: player).frame(width: 180, height: 100)
              Text(state.backgroundMediaTitle).lineLimit(2)
              Spacer()
              Button("Close player") {
                player.releasePlayback()
                state.backgroundPlayer = nil
                state.backgroundMediaTitle = ""
              }
            }.padding(10)
          }
          if state.focus {
            Divider()
            conversationHeader
            composer.padding(14)
          }
        }.accessibilityElement(children: .contain).accessibilityLabel("Workspace")
          .frame(minWidth: 450, maxWidth: .infinity)
      }
      if state.error == nil, let status = state.terminalStatus {
        HStack(alignment: .top) {
          Text(status).textSelection(.enabled)
            .accessibilityFocused($readingFocus, equals: .status)
            .focusable().focused($keyboardPane, equals: .status)
          Spacer()
          if state.pendingReview?.items.isEmpty == false, state.route != .reviews {
            Button("Review drafts") { state.navigate(.reviews) }
          }
          Button("Read conversation") { state.requestReadingFocus(.conversation) }
          Button("Dismiss status") { state.terminalStatus = nil }
        }.padding(12)
      }
      if let error = state.error {
        Divider()
        HStack(alignment: .top) {
          Image(systemName: "exclamationmark.circle")
          Text(error).textSelection(.enabled)
            .accessibilityFocused($readingFocus, equals: .status)
            .focusable().focused($keyboardPane, equals: .status)
          Spacer()
          Button("Dismiss") { state.error = nil }
        }.readingFont(.callout).padding(12).background(Color.red.opacity(0.07))
      }
    }.background(Color(nsColor: .windowBackgroundColor))
      .announceStatus(state.error ?? state.terminalStatus)
      .onChange(of: state.readingFocusRequest) { _, request in applyReadingFocus(request) }
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
        event in
        if let window = event.object as? NSWindow, window === state.readingWindow,
          state.readingFocusPending
        {
          applyReadingFocus(state.readingFocusRequest)
        }
      }
      .focusedSceneValue(\.conversationWorkspace, state)
      .sheet(item: $state.chatRename) { rename in
        ChatRenameSheet(rename: rename) { title in
          try await state.renameChat(rename.chat, title: title, token: rename.id.uuidString)
          state.chatRename = nil
          composerFocused = true
        }
      }
      .alert(
        "Delete this chat?", isPresented: Binding(
          get: { state.chatDeletion != nil }, set: { if !$0 { state.chatDeletion = nil } }),
        presenting: state.chatDeletion
      ) { chat in
        Button("Delete", role: .destructive) { state.deleteChat(chat.id) }
        Button("Cancel", role: .cancel) {}
      } message: { chat in
        Text(
          "“\(chat.title)” leaves your chat list. Records, results and Sources it made stay in the workbook."
        )
      }
      .sheet(isPresented: $state.showingHistorySearch) {
        ConversationHistorySheet(state: state, search: state.historySearch)
      }
      .sheet(item: $state.intakePrompt) { prompt in IntakeView(state: state, prompt: prompt) }
      .alert(
        state.folderReview.map {
          $0.plan.files.isEmpty
            ? $0.plan.folder + " has nothing new"
            : "Add \($0.plan.files.count) files from \($0.plan.folder)?"
        } ?? "",
        isPresented: Binding(
          get: { state.folderReview != nil }, set: { if !$0 { state.folderReview = nil } }),
        presenting: state.folderReview
      ) { review in
        if !review.plan.files.isEmpty {
          Button("Add \(review.plan.files.count) files") { state.addFolder(review) }
        }
        Button(review.plan.files.isEmpty ? "OK" : "Cancel", role: .cancel) {}
      } message: { review in
        Text(review.plan.summary + ". Nothing is deleted, and Sevra does not watch this folder.")
      }
      .sheet(item: $editingSpace) { space in
        if space.definition.app != nil {
          NativeAppHistoryView(space: space, state: state)
        } else {
          SpaceLayoutEditor(space: space, state: state)
        }
      }
      .onReceive(timer) { _ in state.poll() }
      .onChange(of: state.composerFocusRequest) { _, _ in composerFocused = true }
      .onAppear { state.beginInteraction() }.onDisappear { state.endInteraction() }
      .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
        guard state.interactionActive, !state.busy, let book = state.workbook else { return false }
        let identity = state.interactionIdentity
        let chat = state.conversation
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
          guard state.interactionActive, state.interactionIdentity == identity,
            state.workbook === book, state.conversation == chat
          else { return }
          state.importFiles(urls)
        }
        return true
      }
      .environment(
        \.openURL,
        OpenURLAction { url in
          guard ConversationLinkTarget(url) != nil else { return .discarded }
          state.openConversationLink(url)
          return .handled
        })
  }
  var routeTitle: String {
    switch state.route {
    case .space(let id): return state.spaces.first { $0.id == id }?.title ?? "Space"
    case .item: return state.viewedItemTitle ?? "Document"
    case .table(let id): return state.dataset(id)?.title ?? "Table"
    case .tableUpdate: return "Review table update"
    case .excelImport: return "Bring Excel into Sevra"
    case .search: return "Search workbook"
    case .reviews: return "Drafts to review"
    case .activity: return "Workflow runs"
    case .automations: return "Automations"
    case .automation: return "Automation"
    case .workflow: return "Workflow"
    case .tools: return "Tools"
    }
  }
  private var workspaceActions: some View {
    HStack(spacing: 8) {
      if state.pendingReview?.items.isEmpty == false, state.route != .reviews {
        Button("Review drafts", systemImage: "checklist") { state.navigate(.reviews) }
          .help("Open drafts that need your review").accessibilityLabel("Review drafts")
      }
      Button("Spaces", systemImage: "square.grid.2x2") { showSpaces.toggle() }
        .help("Find or create a space").accessibilityLabel("Spaces")
        .popover(isPresented: $showSpaces) {
          SpacePickerView(state: state) { showSpaces = false }
        }
    }
  }
  private func applyReadingFocus(_ request: UUID) {
    guard
      ReadingFocusPolicy.canApply(
        request: request, currentRequest: state.readingFocusRequest,
        pending: state.readingFocusPending, interactionActive: state.interactionActive,
        ownWindowIsKey: state.readingWindow?.isKeyWindow == true, appIsActive: NSApp.isActive)
    else { return }
    let target = state.readingFocusTarget
    readingFocus = nil
    keyboardPane = nil
    if case .message(let id) = target, state.messages.contains(where: { $0.id == id }) {
      state.conversationSession.updateReading(.init(message: id))
      state.readingRequest = UUID()
    }
    Task { @MainActor in
      await Task.yield()
      guard
        ReadingFocusPolicy.canApply(
          request: request, currentRequest: state.readingFocusRequest,
          pending: state.readingFocusPending, interactionActive: state.interactionActive,
          ownWindowIsKey: state.readingWindow?.isKeyWindow == true, appIsActive: NSApp.isActive)
      else { return }
      state.readingFocusPending = false
      if target == .composer {
        composerFocused = true
      } else {
        let destination = ReadingFocusPolicy.destination(
          target,
          visibleMessages: Set(state.messages.filter { $0.role != "tool" }.map(\.id)))
        keyboardPane = destination
        readingFocus = destination
      }
    }
  }
  var conversationHeader: some View {
    PaneHeader {
      Menu {
        Button("New Chat", action: state.newChat)
        Divider()
        ForEach(state.chats) { chat in
          Toggle(
            isOn: Binding(
              get: { chat.id == state.conversation },
              set: { if $0 { state.changeConversation(chat.id) } })
          ) { Text(chat.title) }
        }
      } label: {
        Text(state.chatTitle).readingFont(.subheadline, weight: .medium).lineLimit(1)
      }
      .menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
      .help("Switch chats")
      .accessibilityLabel("Chat: " + state.chatTitle)
      .accessibilityHint("Opens your chats")
      Spacer(minLength: 4)
      HeaderIconButton("New chat", systemImage: "square.and.pencil", action: state.newChat)
      MoreActionsMenu("Chat actions") {
        Button("Rename Chat…") {
          state.chatRename = .init(chat: state.conversation, title: state.chatTitle)
        }
        Button("Search This Chat…") { state.showingHistorySearch = true }
        Divider()
        Button("Delete Chat…", role: .destructive) {
          state.chatDeletion = state.chats.first { $0.id == state.conversation }
        }.disabled(!state.canDeleteChat)
      }
    }.disabled(state.changingConversation)
      .accessibilityElement(children: .contain).accessibilityLabel("Chat: " + state.chatTitle)
      .focusable().focused($keyboardPane, equals: .conversation)
      .accessibilityFocused($readingFocus, equals: .conversation)
  }
  var conversation: some View {
    VStack(spacing: 0) {
      conversationHeader
      Divider()
      Group {
        ScrollView {
          // The core loads a bounded history window. Measure the actual row
          // heights so scrollTo reaches the newest or cited message reliably;
          // lazy height estimates drift with long, differently sized replies.
          VStack(alignment: .leading, spacing: 24) {
            if state.hasEarlierMessages {
              Button("Load earlier exchanges") { state.pageConversation(earlier: true) }
            }
            if state.messages.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Text("What are we working on?").readingFont(.title2, weight: .medium)
                  .accessibilityAddTraits(.isHeader)
                Text("Add a file, ask a question, or describe what you want to organize.")
                  .foregroundStyle(.secondary)
              }.padding(.top, 30)
            }
            ForEach(state.messages.filter { $0.role != "tool" }) { message in
              VStack(alignment: .leading, spacing: 12) {
                ConversationMessageRow(
                  state: state, message: message, content: state.messageContent(message),
                  review: state.proposalReviews[message.id],
                  inputSurface: state.pendingInput?.id == message.id ? state.pendingInput : nil,
                  approval: state.chatApproval?.id == message.id ? state.chatApproval : nil,
                  visuals: (hydratedChat == state.conversation ? hydratedVisuals[message.id] : nil)
                    ?? state.conversationVisuals[message.id] ?? [],
                  resumable: state.resumableAnswer == message.id,
                  controlsEnabled: !state.busy && !state.changingConversation
                ).equatable()
                ForEach(state.requestActivities.filter { $0.requestID == message.id }) { activity in
                  AgentActivityView(
                    workspace: state, activity: activity,
                    live: state.liveActivity?.runID == activity.id ? state.liveActivity : nil)
                }
                if let live = state.liveActivity, live.conversation == state.conversation,
                  live.requestID == message.id,
                  !state.requestActivities.contains(where: { $0.id == live.runID })
                {
                  AgentActivityView(workspace: state, activity: nil, live: live)
                }
              }.id(message.id)
                .accessibilityElement(children: .contain)
                .focusable().focused($keyboardPane, equals: .message(message.id))
                .accessibilityFocused($readingFocus, equals: .message(message.id))
                .background(
                  GeometryReader { geometry in
                    Color.clear.preference(
                      key: ConversationRowFrames.self,
                      value: [message.id: geometry.frame(in: .named("conversation-content"))])
                  })
            }
            if state.hasLaterMessages {
              Button("Load later exchanges") { state.pageConversation(earlier: false) }
            }
            if let live = state.liveActivity, live.conversation == state.conversation,
              !state.messages.contains(where: { $0.id == live.requestID })
            {
              AgentActivityView(workspace: state, activity: nil, live: live).id("working")
            } else if state.busy && state.liveActivity == nil {
              HStack {
                ProgressView().controlSize(.small)
                Text(state.status).readingFont(.callout).foregroundStyle(.secondary)
              }.id("working")
            }
          }.padding(20)
            .coordinateSpace(name: "conversation-content")
            .background(
              ConversationScrollObserver(
                frames: conversationFrames,
                position: state.conversationSession.state.reading, request: state.readingRequest,
                canFollowLatest: state.messageAnchor == nil,
                visible: { ids in
                  let byID = Set(
                    state.messages.filter { ["assistant", "event"].contains($0.role) }.map(\.id))
                  let messages = Array(ids.filter(byID.contains).prefix(4))
                  if messages != visibleMessages { visibleMessages = messages }
                }
              ) { [chat = state.conversation, owner = state.interactionIdentity] position in
                guard state.interactionActive, !state.changingConversation,
                  state.conversation == chat, state.interactionIdentity == owner
                else { return }
                state.conversationSession.updateReading(position)
              }
            )
            .onPreferenceChange(ConversationRowFrames.self) { conversationFrames = $0 }
        }
      }.id(state.conversation)
        .task(id: [state.conversation] + visibleMessages) {
          guard let book = state.workbook else { return }
          let chat = state.conversation
          let ids = visibleMessages
          let cancellation = Cancellation()
          await withTaskCancellationHandler {
            do {
              let values = try await Task.detached {
                try book.hydrateConversationVisuals(
                  ids, conversation: chat, cancellation: cancellation)
              }.value
              try Task.checkCancellation()
              guard state.workbook === book && state.conversation == chat else { return }
              hydratedChat = chat
              hydratedVisuals = values
            } catch {
              guard !Task.isCancelled else { return }
              hydratedVisuals = [:]
            }
          } onCancel: {
            cancellation.cancel()
          }
        }
      if state.messageAnchor != nil || state.conversationSession.state.reading.message != nil {
        Button("Return to latest", action: state.latestConversationMessages).padding(.bottom, 8)
      }
      Divider()
      composer.padding(14)
    }.accessibilityElement(children: .contain).accessibilityLabel("Conversation")
      .sheet(item: $state.visualInspection) { inspection in
        visualInspection(inspection)
      }
      .sheet(item: $state.imageInspection) { inspection in
        VStack(spacing: 0) {
          HStack {
            Text(inspection.title).font(.headline).lineLimit(1)
            Spacer()
            Button("Done") { state.imageInspection = nil }.keyboardShortcut(.cancelAction)
          }.padding(16)
          Divider()
          ImageViewer(
            image: NSImage(cgImage: inspection.preview.image, size: inspection.preview.points),
            title: inspection.title, fitInitially: true, initialScale: inspection.zoom)
        }.frame(minWidth: 480, idealWidth: 720, minHeight: 360, idealHeight: 560)
      }
  }
  private func visualInspection(_ inspection: ConversationVisualInspection) -> some View {
    let open: (String) -> Void = { source in
      state.visualInspection = nil
      state.navigate(.item(source), returningTo: .message(inspection.messageID))
    }
    func sources(panel: Int? = nil, point: Int, offset: Int) async throws -> Value {
      guard let book = state.workbook else {
        throw SevraError("visual", "Reopen the workbook for this visual.")
      }
      return try await Task.detached {
        try book.chartGroupSources(
          messageID: inspection.messageID, index: inspection.index,
          conversation: inspection.conversation, point: point, offset: offset, panel: panel)
      }.value
    }
    return VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Visual detail").font(.headline)
        Spacer()
        Button("Done") { state.visualInspection = nil }.keyboardShortcut(.cancelAction)
      }.padding(16)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          switch inspection.content {
          case .captured(let result):
            if let chart = result.chart, let data = result.chartData {
              VisualChartView(
                definition: chart, data: data, openOriginal: open,
                loadSources: { try await sources(point: $0, offset: $1) })
            } else if let overview = result.overview, let data = result.overviewData {
              VisualOverviewView(
                definition: overview, panels: data, openOriginal: open,
                loadSources: { panel, _, point, offset in
                  try await sources(panel: panel, point: point, offset: offset)
                })
            } else if let diagram = result.diagram, let data = result.diagramData {
              VisualDiagramView(definition: diagram, data: data, openRecord: open)
            }
          case .current(let session, let reference):
            NativeAppDeclaredView(
              session: session, viewID: reference.viewID, presetID: reference.presetID,
              datasetSnapshot: state.datasetSnapshot,
              presentationSnapshot: state.presentationSnapshot, openOriginal: open)
          }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
      }
    }.frame(minWidth: 420, idealWidth: 760, minHeight: 360, idealHeight: 560)
  }

  var composer: some View {
    VStack(alignment: .leading, spacing: 8) {
      if state.changingConversation {
        Text("Opening chat…").readingFont(.caption).foregroundStyle(.secondary)
      }
      if let failure = state.conversationSession.failure {
        Text(failure).readingFont(.caption).foregroundStyle(.red).textSelection(.enabled)
        HStack {
          if state.conversationSession.conflict {
            Button("Keep both drafts") { Task { _ = await state.conversationSession.keepBoth() } }
          } else {
            Button("Retry saving draft") { Task { _ = await state.conversationSession.flush() } }
          }
        }
      }
      if !state.conversationSession.state.savedDrafts.isEmpty {
        Menu("Saved drafts") {
          ForEach(state.conversationSession.state.savedDrafts) { draft in
            Menu(String(draft.text.prefix(60))) {
              Button("Restore to composer") { state.restoreSavedConversationDraft(draft.id) }
              Button("Remove saved draft") {
                Task { _ = await state.conversationSession.discardSaved(draft.id) }
              }
            }
          }
        }
      }
      if !state.pendingInputs.isEmpty {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Menu("Pending questions (\(state.pendingInputs.count))") {
            ForEach(state.pendingInputs) { surface in
              Button(surface.purpose) { state.targetInput(surface) }
            }
          }
          if let selected = state.pendingInputs.first(where: { $0.id == state.replyInputID }) {
            Text("Answering \(selected.purpose)")
              .readingFont(.caption).foregroundStyle(.secondary).lineLimit(1)
            Button("Clear reply target", action: state.clearReplyTarget)
              .buttonStyle(.link)
          }
        }
      }
      if !state.selectedContext.isEmpty {
        HStack(alignment: .top) {
          Text("About: " + (state.selectionLabel ?? String(state.selectedContext.prefix(100))))
            .readingFont(.caption).foregroundStyle(.secondary).lineLimit(2)
          Spacer(minLength: 0)
          Button {
            state.selectedContext = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.plain).foregroundStyle(.secondary)
          .help("Ask without this selection").accessibilityLabel("Remove selection from message")
        }
      }
      TextField("Ask, change, or run something…", text: $state.prompt, axis: .vertical)
        .textFieldStyle(.plain)
        .focused($composerFocused).lineLimit(2...7).onSubmit { state.send() }.accessibilityLabel(
          "Message Sevra"
        )
        .disabled(state.changingConversation || !state.conversationSession.ready)
      HStack {
        VoiceButton(speech: state.speech, action: state.voice)
          .disabled(state.changingConversation || !state.conversationSession.ready)
        Spacer()
        VoiceStatus(speech: state.speech)
        Button(action: state.send) { Image(systemName: "arrow.up") }.buttonStyle(.borderedProminent)
          .disabled(!state.canSend).keyboardShortcut(.return, modifiers: .command)
          .accessibilityLabel("Send message")
      }
    }.padding(12).background(
      Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12)
    ).overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(composerFocused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
    )
  }
  @ViewBuilder var workspace: some View {
    if let book = state.workbook {
      switch state.route {
      case .space(let id):
        if let space = state.spaces.first(where: { $0.id == id }) {
          SpaceView(space: space, state: state).id(space.id)
        }
      case .item(let id):
        ItemRouteView(id: id, workbook: book, state: state).id(
          id + state.itemPreviewIdentity.uuidString)
      case .table(let id):
        if let table = state.dataset(id) {
          DatasetView(table: table, state: state)
        }
      case .search: SearchView(state: state, results: state.searchResults)
      case .tableUpdate(let source, let job):
        TableUpdateView(book: book, sourceID: source, intakeID: job, state: state)
          .id(source + (job ?? ""))
      case .reviews: ReviewQueueView(state: state, results: state.reviewResults)
      case .excelImport(let id): ExcelConversionView(id: id, state: state).id(id)
      case .activity: WorkflowActivityView(workspace: state)
      case .automations: AutomationSchedulesView(workspace: state)
      case .automation(let id): AutomationFocusedView(definitionID: id, workspace: state)
      case .workflow(let id): WorkflowRunView(runID: id, workspace: state).id(id)
      case .tools: ToolsView(workspace: state)
      }
    }
  }
}

/// A rename of one chat, made from the chat actions menu.
struct ChatRename: Identifiable {
  let id = UUID()
  let chat: String
  let title: String
}

private struct ChatRenameSheet: View {
  let rename: ChatRename
  let save: (String) async throws -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var failure: String?
  @State private var saving = false
  @FocusState private var focused: Bool
  private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Rename chat").readingFont(.title2, weight: .medium).accessibilityAddTraits(.isHeader)
      TextField("Title", text: $name).textFieldStyle(.roundedBorder).focused($focused)
        .onSubmit(submit)
      if let failure { Text(failure).foregroundStyle(.red).readingFont(.callout) }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save", action: submit).keyboardShortcut(.defaultAction)
          .disabled(trimmed.isEmpty || trimmed == rename.title)
      }
    }.padding(24).readingFont(.body).frame(minWidth: 320, idealWidth: 420)
      .disabled(saving).interactiveDismissDisabled(saving).announceStatus(failure).onAppear {
        name = rename.title
        focused = true
      }
  }
  private func submit() {
    guard !saving, !trimmed.isEmpty, trimmed != rename.title else { return }
    saving = true
    Task {
      defer { saving = false }
      do { try await save(trimmed) } catch { failure = error.localizedDescription }
    }
  }
}
