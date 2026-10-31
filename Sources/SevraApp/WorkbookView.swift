import AVKit
import AppKit
import SevraCore
import SevraPreviewUI
import SevraVoice
import SwiftUI

struct WorkbookView: View {
  @ObservedObject var state: WorkspaceState
  @State private var showSpaces = false
  @State private var editingSpace: Space?
  @State private var conversationFrames: [String: CGRect] = [:]
  @FocusState private var composerFocused: Bool
  let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button {
          state.focus.toggle()
        } label: {
          Image(systemName: "sidebar.left")
        }.help(state.focus ? "Show conversation" : "Focus workspace")
          .accessibilityLabel(state.focus ? "Show conversation" : "Focus workspace")
        ObserverMark().fill(.primary).frame(width: 28, height: 28).accessibilityHidden(true)
        Text(state.workbook?.title ?? "Sevra").font(.headline).lineLimit(1)
        Spacer()
        if state.busy {
          ProgressView().controlSize(.small)
          Text(state.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
          Button("Paste table data…", action: state.pasteTableData)
        } label: {
          Label("Add files…", systemImage: "plus")
        } primaryAction: {
          state.importPanel()
        }.disabled(state.busy)
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
            Text(routeTitle).font(.title3.weight(.medium)).lineLimit(1).help(routeTitle)
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
                Button("Edit layout…") { editingSpace = space }.disabled(state.busy)
                if !space.definition.components.isEmpty && !space.definition.containsSections {
                  Button("Save a snapshot") {
                    state.pinSpace(
                      space.id,
                      title: space.title + " · "
                        + Date().formatted(date: .abbreviated, time: .shortened))
                  }.disabled(state.busy)
                }
                Divider()
              }
              Button("Drafts to review") { state.navigate(.reviews) }
              Button("Workflow runs") { state.navigate(.activity) }
              Button("Automations") { state.navigate(.automations) }
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
        }.frame(minWidth: 450, maxWidth: .infinity)
      }
      if let error = state.error {
        Divider()
        HStack(alignment: .top) {
          Image(systemName: "exclamationmark.circle")
          Text(error).textSelection(.enabled)
          Spacer()
          Button("Dismiss") { state.error = nil }
        }.font(.callout).padding(12).background(Color.red.opacity(0.07))
      }
    }.background(Color(nsColor: .windowBackgroundColor))
      .focusedSceneValue(\.conversationWorkspace, state)
      .sheet(item: $state.conversationDraft) { draft in
        ConversationNameSheet(draft: draft) { name in
          guard let book = state.workbook else { return }
          let owner = state.interactionIdentity
          try await Task.detached(priority: .userInitiated) {
            if let thread = draft.threadID {
              try book.renameThread(
                thread, title: name, expectedTitle: draft.title, token: draft.id.uuidString)
            } else {
              try book.chapter(title: name, message: draft.message)
            }
          }.value
          guard state.interactionIdentity == owner, state.workbook === book else { return }
          state.refresh()
          state.conversationDraft = nil
          composerFocused = true
        }
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
      .sheet(item: $editingSpace) { space in SpaceLayoutEditor(space: space, state: state) }
      .sheet(item: $state.summaryDraft) { draft in
        ConversationSummarySheet(draft: draft) { summary in
          guard let book = state.workbook else { return }
          _ = try book.shareSummary(message: draft.id, text: summary)
          state.summaryDraft = nil
          state.changeConversation("main")
          composerFocused = true
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
    case .item(let id):
      return (try? state.workbook?.item(state.viewedItemVersion ?? id).title) ?? "Document"
    case .table(let id): return state.dataset(id)?.title ?? "Table"
    case .tableUpdate: return "Review table update"
    case .search: return "Search workbook"
    case .reviews: return "Drafts to review"
    case .activity: return "Workflow runs"
    case .automations: return "Automations"
    case .automation: return "Automation"
    case .workflow: return "Workflow"
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
  var conversationHeader: some View {
    PaneHeader {
      if state.conversation != "main" {
        Button {
          state.changeConversation("main")
        } label: {
          Image(systemName: "arrow.uturn.backward")
        }.help("Back to conversation").accessibilityLabel("Back to conversation")
      }
      let threads = state.conversations.filter { $0["id"].text != "main" }
      if threads.isEmpty {
        Text(state.conversationTitle).font(.subheadline.weight(.medium)).lineLimit(1)
      } else {
        Menu {
          Button("Conversation") { state.changeConversation("main") }
          Section("Threads") {
            ForEach(threads, id: \.text) { chat in
              Button(chat["title"].text) { state.changeConversation(chat["id"].text) }
            }
          }
        } label: {
          Text(state.conversationTitle).font(.subheadline.weight(.medium)).lineLimit(1)
        }
        .help("Switch between the main conversation and its threads")
        .accessibilityLabel("Switch conversation: " + state.conversationTitle)
      }
      Spacer()
      MoreActionsMenu("Conversation actions") {
        Button("Start a chapter…") {
          if let message = state.messages.last {
            state.conversationDraft = .init(message: message.id)
          }
        }.disabled(state.messages.isEmpty)
        Button("Start a thread") {
          if let message = state.messages.last {
            state.startThread(from: message.id)
          }
        }.disabled(state.messages.isEmpty)
        if state.conversation != "main" {
          Button("Rename thread…", action: state.requestRenameThread)
          Button("Share summary with conversation…") { state.requestSummary() }
            .disabled(
              !state.messages.contains { $0.role == "assistant" && $0.state == "complete" })
        }
        Button("Search this conversation…") { state.showingHistorySearch = true }
        if !state.bookmarks.isEmpty {
          Menu("Saved exchanges") {
            ForEach(state.bookmarks, id: \.text) { bookmark in
              Button(bookmark["title"].text) { state.jumpToMessage(bookmark["message_id"].text) }
            }
          }
        }
        if !state.chapters.isEmpty {
          Menu("Chapters") {
            ForEach(state.chapters, id: \.text) { chapter in
              Button(chapter["title"].text) { state.jumpToMessage(chapter["message_id"].text) }
            }
          }
        }
      }
    }.disabled(state.changingConversation)
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
                Text("What are we working on?").font(.title2.weight(.medium))
                Text("Add a file, ask a question, or describe what you want to organize.")
                  .foregroundStyle(.secondary)
              }.padding(.top, 30)
            }
            ForEach(state.messages.filter { $0.role != "tool" }) { message in
              VStack(alignment: .leading, spacing: 12) {
                ConversationMessageRow(state: state, message: message)
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
                Text(state.status).font(.callout).foregroundStyle(.secondary)
              }.id("working")
            }
          }.padding(20)
            .coordinateSpace(name: "conversation-content")
            .background(
              ConversationScrollObserver(
                frames: conversationFrames,
                position: state.conversationSession.state.reading, request: state.readingRequest,
                canFollowLatest: state.messageAnchor == nil
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
      if state.messageAnchor != nil || state.conversationSession.state.reading.message != nil {
        Button("Return to latest", action: state.latestConversationMessages).padding(.bottom, 8)
      }
      Divider()
      composer.padding(14)
    }
  }
  var composer: some View {
    VStack(alignment: .leading, spacing: 8) {
      if state.changingConversation {
        Text("Opening conversation…").font(.caption).foregroundStyle(.secondary)
      }
      if let failure = state.conversationSession.failure {
        Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled)
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
      if !state.selectedContext.isEmpty {
        HStack(alignment: .top) {
          Text("About: " + (state.selectionLabel ?? String(state.selectedContext.prefix(100))))
            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
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
      TextField("Type or speak…", text: $state.prompt, axis: .vertical).textFieldStyle(.plain)
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
        if let item = try? book.item(id) {
          ItemView(item: item, workbook: book, state: state).id(
            id + state.itemPreviewIdentity.uuidString)
        }
      case .table(let id):
        if let table = state.dataset(id) {
          DatasetView(table: table, state: state)
        }
      case .search: SearchView(state: state, results: state.searchResults)
      case .tableUpdate(let source, let job):
        TableUpdateView(book: book, sourceID: source, intakeID: job, state: state)
          .id(source + (job ?? ""))
      case .reviews: ReviewQueueView(state: state, results: state.reviewResults)
      case .activity: WorkflowActivityView(workspace: state)
      case .automations: AutomationSchedulesView(workspace: state)
      case .automation(let id): AutomationFocusedView(definitionID: id, workspace: state)
      case .workflow(let id): WorkflowRunView(runID: id, workspace: state)
      }
    }
  }
}

struct ConversationDraft: Identifiable {
  let id = UUID()
  let message: String
  var threadID: String? = nil
  var title: String = ""
}

private struct ConversationNameSheet: View {
  let draft: ConversationDraft
  let create: (String) async throws -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var failure: String?
  @State private var saving = false
  @FocusState private var focused: Bool
  private var title: String { draft.threadID != nil ? "Rename thread" : "Start a chapter" }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(title).font(.title2.weight(.medium))
      Text(
        draft.threadID != nil
          ? "Choose a title that helps you recognize this discussion."
          : "Name this point so you can find it later in the conversation."
      )
      .foregroundStyle(.secondary)
      TextField("Name", text: $name).textFieldStyle(.roundedBorder).focused($focused)
      if let failure { Text(failure).foregroundStyle(.red).font(.callout) }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button(draft.threadID != nil ? "Save title" : "Create chapter") {
          saving = true
          Task {
            defer { saving = false }
            do { try await create(name.trimmingCharacters(in: .whitespacesAndNewlines)) } catch {
              failure = error.localizedDescription
            }
          }
        }.keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(24).frame(width: 400).disabled(saving).onAppear {
      name = draft.title
      focused = true
    }
  }
}

struct ConversationSummaryDraft: Identifiable {
  let id: String
  let text: String
}

private struct ConversationSummarySheet: View {
  let draft: ConversationSummaryDraft
  let share: (String) throws -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var failure: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Share summary with conversation").font(.title2.weight(.medium))
      Text("Edit the findings you want to bring back. The original exchange stays linked.")
        .foregroundStyle(.secondary)
      TextEditor(text: $text).font(.body).frame(minHeight: 180)
        .accessibilityLabel("Summary to share")
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
      if let failure { Text(failure).foregroundStyle(.red) }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Share summary") {
          do { try share(text) } catch { failure = error.localizedDescription }
        }.keyboardShortcut(.defaultAction)
          .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(24).frame(width: 480)
      .onAppear { text = draft.text }
  }
}
