import AppKit
import SevraCore
import SevraMedia
import SevraPreviewUI
import SevraTableUI
import SevraVisualUI
import SwiftUI

/// Takes plain values, so only a changed message or review draws this row again.
struct ConversationMessageRow: View, Equatable {
  let state: WorkspaceState
  let message: Message
  let content: ConversationMessageContent
  let review: ProposalReviewState?
  let inputSurface: ConversationSurface?
  let approval: ChatApproval?
  let visuals: [VisualResult]
  let resumable: Bool
  let controlsEnabled: Bool
  @State private var hovering = false
  static func == (left: Self, right: Self) -> Bool {
    left.message.id == right.message.id && left.message.body == right.message.body
      && left.content.source == right.content.source
      && left.message.state == right.message.state && left.message.role == right.message.role
      && left.review == right.review && left.inputSurface == right.inputSurface
      && left.visuals == right.visuals && left.approval == right.approval
      && left.resumable == right.resumable && left.controlsEnabled == right.controlsEnabled
  }
  private var speaker: String {
    message.role == "user" ? "You" : message.role == "event" ? "Activity" : "Sevra"
  }
  private var status: String {
    if message.state == "needs_input" {
      return inputSurface == nil ? "Question" : "Waiting for your answer"
    }
    // A saved state is a word for the host. The person reads what happened.
    guard message.state == "needs_review" else {
      switch message.state {
      case "failed": return "Couldn’t finish"
      case "cancelled": return "Stopped"
      case "interrupted": return "Interrupted"
      default: return message.state.replacingOccurrences(of: "_", with: " ").capitalized
      }
    }
    guard let review else { return "Review requested" }
    switch review.status {
    case "accepted": return "Current version accepted"
    case "rejected": return "Current version withdrawn"
    case "draft":
      return review.proposalID == review.currentVersionID ? "Needs your review" : "Newer draft"
    default: return "Review requested"
    }
  }
  var body: some View {
    // The Undo row sits outside the spaced stack, since most replies leave it empty.
    VStack(alignment: .leading, spacing: 0) {
      if message.role == "user" { userBubble } else { messageStack }
      if message.role == "assistant" && message.state == "complete" {
        ConversationReversalView(state: state, messageID: message.id)
      }
    }.environment(
      \.openURL,
      OpenURLAction { url in
        state.openConversationLink(url, returningTo: .message(message.id))
        return .handled
      }
    ).accessibilityElement(children: .contain)
      .accessibilityLabel(speaker + " message" + (message.state == "complete" ? "" : ", " + status))
      .accessibilityIdentifier("message-" + message.id)
      .onHover { hovering = $0 }
      .contextMenu {
        ConversationMessageActions(state: state, message: message, content: content.presentation)
      }
  }
  /// Shown while the pointer is over the message; still reachable by keyboard and VoiceOver.
  private var actionsMenu: some View {
    MoreActionsMenu(
      (speaker == "You" ? "Your" : speaker) + " message actions",
      help: "Copy this message or open its links"
    ) {
      ConversationMessageActions(state: state, message: message, content: content.presentation)
    }.opacity(hovering ? 1 : 0)
  }
  /// The person's own message: on the right, in a tinted bubble no wider than the text.
  private var userBubble: some View {
    HStack(alignment: .center, spacing: 4) {
      Spacer(minLength: 48)
      actionsMenu
      VStack(alignment: .leading, spacing: 10) { bodyBlocks }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(
          Color.primary.opacity(0.065),
          in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }.frame(maxWidth: .infinity, alignment: .trailing)
  }
  @ViewBuilder private var bodyBlocks: some View {
    ForEach(Array(content.blocks.enumerated()), id: \.offset) { _, block in
      switch block {
      case .text(let text):
        Text(text).textSelection(.enabled).lineSpacing(4)
      case .table(let table):
        ReadOnlyTableView(
          content: table, label: "Comparison table", inline: true,
          open: { state.openConversationLink($0, returningTo: .message(message.id)) })
      case .code(let code):
        ConversationCodeBlock(code: code)
      }
    }
  }
  private var messageStack: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Sevra's replies need no name: the side says who is speaking. A state or an
      // activity note still gets a line.
      if message.state != "complete" || message.role == "event" {
        HStack {
          if message.role == "event" {
            Text(speaker).readingFont(.caption, weight: .semibold).foregroundStyle(.secondary)
          }
          if message.state != "complete" {
            if let review {
              Button(status) {
                state.navigate(.item(review.currentVersionID), returningTo: .message(message.id))
              }
              .buttonStyle(.plain).readingFont(.caption)
              .foregroundStyle(review.status == "draft" ? Color.orange : Color.secondary)
              .help("Open the current proposal, version \(review.currentVersion)")
            } else {
              Text(status).readingFont(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      VStack(alignment: .leading, spacing: 10) {
        if let input = inputSurface?.input {
          Text(input.question).textSelection(.enabled).lineSpacing(4)
          if input.allowTextReply {
            Text("You can also type Answer: followed by your response.")
              .font(.caption).foregroundStyle(.secondary)
          }
        } else {
          bodyBlocks
        }
      }
      .accessibilityActions {
        ForEach(content.presentation.links) { link in
          Button(link.actionTitle) {
            state.openConversationLink(link.url, returningTo: .message(message.id))
          }
        }
      }
      if let book = state.workbook {
        let conversation = state.conversation
        ForEach(Array(visuals.enumerated()), id: \.offset) { index, visual in
          if let image = visual.image {
            WorkbookImageView(book: book, presentation: image) {
              state.navigate(.item(image.reference.sourceID), returningTo: .message(message.id))
            }
          } else if let chart = visual.chart, let data = visual.chartData {
            VisualChartView(
              definition: chart, data: data, compact: true,
              openOriginal: { state.navigate(.item($0), returningTo: .message(message.id)) },
              loadSources: { point, offset in
                let messageID = message.id
                return try await Task.detached {
                  try book.chartGroupSources(
                    messageID: messageID, index: index,
                    conversation: conversation, point: point, offset: offset)
                }.value
              })
          } else if let work = visual.work, let data = visual.workData {
            WorkVisualView(
              definition: work, data: data,
              openRecord: {
                state.navigate(.item($0), returningTo: .message(message.id))
              },
              thumbnail: (visual.thumbnailReferences ?? work.thumbnailAssets).map { refs in
                { @MainActor @Sendable key in
                  guard let ref = refs[key] else {
                    throw SevraError("visual_image", "No bound image.")
                  }
                  let asset = try await Task.detached { try book.imageAssetRead(ref) }.value
                  return try await WorkbookImageDecoder.shared.load(asset)
                }
              })
          }
          if let text = visual.definition.text {
            VisualTextView(definition: text) {
              state.navigate(.item($0), returningTo: .message(message.id))
            }
          }
          if let overview = visual.overview, let panels = visual.overviewData {
            VisualOverviewView(
              definition: overview, panels: panels, compact: true,
              openOriginal: { state.navigate(.item($0), returningTo: .message(message.id)) },
              loadSources: { panel, _, point, offset in
                let messageID = message.id
                return try await Task.detached {
                  try book.chartGroupSources(
                    messageID: messageID, index: index, conversation: conversation,
                    point: point, offset: offset, panel: panel)
                }.value
              })
          }
          if let diagram = visual.diagram, let data = visual.diagramData {
            VisualDiagramView(definition: diagram, data: data) {
              state.navigate(.item($0), returningTo: .message(message.id))
            }
          }
          HStack(spacing: 14) {
            let origin = VisualOrigin(
              messageID: message.id, index: index, conversation: conversation)
            if visual.chart != nil || visual.overview != nil || visual.diagram != nil {
              Button("Expand") { state.showChatVisual(message.id, index: index, current: false) }
            }
            if visual.appReference != nil
              || state.spaces.first(where: { $0.id == "home" })?
                .definition.components.contains(where: {
                  $0.visualOrigin == origin
                    || ($0.visualOrigin == nil && $0.visual == visual.definition)
                }) == true
            {
              Button("Open current view") {
                state.showChatVisual(message.id, index: index, current: true)
              }
            }
            Button("Add live view to Home") { state.promoteVisual(message.id, index: index) }
              .disabled(!controlsEnabled)
          }.buttonStyle(.link).font(.caption)
        }
      }
      if let inputSurface, let input = inputSurface.input, let book = state.workbook {
        ConversationInputView(input: input, surface: inputSurface, book: book) {
          response, revision in
          state.submitInput(inputSurface, response: response, draftRevision: revision)
        }
        .id(inputSurface.id)
        .disabled(!controlsEnabled)
      }
      if let approval {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Button("Confirm change") { state.respondToApproval(approval, cancel: false) }
              .buttonStyle(.borderedProminent)
            Button("Cancel approval") { state.respondToApproval(approval, cancel: true) }
          }
        }.disabled(!controlsEnabled)
      }
      if resumable {
        HStack {
          Text("Answer saved").foregroundStyle(.secondary)
          Button("Retry continuation") { state.retryInput(message.id) }
        }.readingFont(.caption).disabled(!controlsEnabled)
      }
      actionsMenu.padding(.leading, -6).padding(.vertical, -8)
    }
  }
}

/// The room a message's actions button takes, kept by a message drawn before it has the button:
/// the answer being written, under itself, and the message just sent, beside its bubble. The
/// saved message that replaces either then lays out the same.
struct MessageActionsSpace: View {
  /// Beside a sent message's bubble, rather than under a reply.
  var beside = false
  @AppStorage(ReadingStyle.preference) private var textScale = 1.0
  var body: some View {
    let side = 28 * ReadingStyle.scale(textScale)
    if beside {
      Color.clear.frame(width: side, height: side).accessibilityHidden(true)
    } else {
      Color.clear.frame(width: side, height: side).padding(.leading, -6).padding(.vertical, -8)
        .accessibilityHidden(true)
    }
  }
}

/// Whether each saved reply has a change row, read with the chat off the main thread. A reply
/// that saved a change then lands with the row's line already there, instead of growing a line
/// a moment later. The row reads its exact state itself.
final class ConversationReceiptHints: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String: Bool] = [:]

  func hasChange(_ messageID: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return entries[messageID] ?? false
  }

  /// Call off the main thread with the messages about to be shown. Each reply is read once.
  func prepare(
    _ messages: [Message], book: Workbook, conversation: String, cancellation: Cancellation
  ) throws {
    for message in messages where message.role == "assistant" && message.state == "complete" {
      try cancellation.check()
      lock.lock()
      let known = entries[message.id] != nil
      lock.unlock()
      if known { continue }
      let change =
        try book.conversationAppReceipt(message.id, conversation: conversation) != nil
        || book.conversationSQLReceipt(message.id, conversation: conversation) != nil
      lock.lock()
      entries[message.id] = change
      lock.unlock()
    }
  }

  /// The window that is now on screen. Everything else is forgotten.
  func retain(_ messages: [Message]) {
    let shown = Set(messages.map(\.id))
    lock.lock()
    entries = entries.filter { shown.contains($0.key) }
    lock.unlock()
  }
}

/// A code block keeps its lines; a long line scrolls sideways instead of wrapping.
struct ConversationCodeBlock: View {
  let code: String
  var body: some View {
    ScrollView(.horizontal) {
      // The answer's own font, monospaced, so code matches the text around it.
      Text(code).monospaced().textSelection(.enabled)
        .fixedSize().padding(.horizontal, 10).padding(.vertical, 8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Code: " + code)
  }
}

private struct ConversationReversalView: View {
  @ObservedObject var state: WorkspaceState
  let messageID: String
  @State private var receipt: ConversationAppReceipt?
  @State private var current: (token: String, redo: Bool)?
  @State private var sql: (token: String, state: String)?
  @State private var busy = false
  @State private var failure: String?
  /// Whether the first read is done. Until then a reply known to have saved a change keeps the
  /// row's line, so the reply does not grow a line after it lands.
  @State private var loaded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if !loaded && sql == nil && receipt == nil && state.receiptHints.hasChange(messageID) {
        Text("Change saved").font(.caption).hidden().accessibilityHidden(true)
      } else if let sql {
        HStack {
          Text(sql.state == "undone" ? "Change undone" : "Change saved")
            .foregroundStyle(.secondary)
          if sql.state == "saved" {
            Button("Undo this change") {
              Task { await undo(sql.token) }
            }.buttonStyle(.link).disabled(busy || state.busy)
          }
        }.font(.caption)
        if let failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
      } else if let receipt {
        HStack {
          Text(
            current?.redo == true
              ? "Change undone" : (receipt.partial ? "Some changes were saved" : "Change saved")
          )
          .foregroundStyle(.secondary)
          if let current {
            Button(current.redo ? "Redo this change" : "Undo this change") {
              Task { await reverse(receipt, token: current.token, redo: current.redo) }
            }.buttonStyle(.link).disabled(busy || state.busy)
          }
        }.font(.caption)
        if let failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
      }
    }
    // A stack, not a Group: an empty Group never starts its task, so the row never loaded.
    // It brings its own spacing, so replies without a change keep their layout.
    .padding(
      .top,
      sql == nil && receipt == nil && (loaded || !state.receiptHints.hasChange(messageID)) ? 0 : 6
    )
    .task(id: [state.conversation, state.datasetSnapshot, String(state.spaces.count)]) {
      await refresh()
    }
  }

  private func refresh() async {
    guard let book = state.workbook else { return }
    defer { if !Task.isCancelled { loaded = true } }
    let chat = state.conversation
    do {
      let saved = try await Task.detached {
        try book.conversationAppReceipt(messageID, conversation: chat)
      }.value
      try Task.checkCancellation()
      guard state.workbook === book && state.conversation == chat else { return }
      receipt = saved
      if saved == nil {
        // Changes made through sql keep their own receipt: the call that saved them.
        let found = try await Task.detached { () -> (token: String, state: String)? in
          guard let token = try book.conversationSQLReceipt(messageID, conversation: chat),
            let state = try book.chatSQLState(token)
          else { return nil }
          return (token, state)
        }.value
        try Task.checkCancellation()
        guard state.workbook === book && state.conversation == chat else { return }
        sql = found
        current = nil
        return
      }
      sql = nil
      guard let saved, let app = state.spaces.first(where: { $0.id == saved.appID }),
        app.version == saved.version && app.definition.app != nil
      else {
        current = nil
        return
      }
      current = try await state.nativeAppSession(app, book: book).withVisualAccess { book, access in
        try book.nativeAppReversal(access, original: saved.transaction)
      }
    } catch {
      guard !Task.isCancelled else { return }
      current = nil
    }
  }

  private func undo(_ token: String) async {
    guard let (book, operation) = state.beginOperation("Undoing change") else { return }
    busy = true
    var undone = false
    defer {
      busy = false
      state.finishOperation(operation, in: book, successStatus: undone ? "Change undone." : nil)
    }
    do {
      let cancellation = operation.cancellation
      _ = try await Task.detached {
        try book.chatSQLUndo(token, actor: .human("Sevra chat undo"), cancellation: cancellation)
      }.value
      undone = true
      failure = nil
      await refresh()
    } catch {
      failure = error.localizedDescription
      await refresh()
    }
  }

  private func reverse(_ receipt: ConversationAppReceipt, token: String, redo: Bool) async {
    guard let (book, operation) = state.beginOperation(redo ? "Redoing change" : "Undoing change")
    else { return }
    busy = true
    var done = false
    defer {
      busy = false
      state.finishOperation(
        operation, in: book, successStatus: done ? (redo ? "Change redone." : "Change undone.") : nil)
    }
    do {
      _ = try await state.performChatAction(
        redo ? "app.redo" : "app.undo",
        arguments: .object([
          "id": .string(receipt.appID), "expectedVersion": .number(Double(receipt.version)),
          "transaction": .string(token),
        ]), book: book, readOnly: false, cancellation: operation.cancellation)
      done = true
      failure = nil
      await refresh()
    } catch {
      failure = error.localizedDescription
      await refresh()
    }
  }
}

struct ConversationMessageActions: View {
  let state: WorkspaceState
  let message: Message
  let content: ConversationPresentation
  var body: some View {
    Button("Copy message") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(String(content.text.characters), forType: .string)
    }
    if !content.links.isEmpty {
      Section("Links") {
        ForEach(content.links) { link in
          Button(link.actionTitle) {
            state.openConversationLink(link.url, returningTo: .message(message.id))
          }
        }
      }
    }
  }
}

private struct ConversationWorkspaceKey: FocusedValueKey {
  typealias Value = WorkspaceState
}
extension FocusedValues {
  var conversationWorkspace: WorkspaceState? {
    get { self[ConversationWorkspaceKey.self] }
    set { self[ConversationWorkspaceKey.self] = newValue }
  }
}

struct ConversationCommands: Commands {
  @FocusedValue(\.conversationWorkspace) private var workspace
  var body: some Commands {
    CommandMenu("Chat") {
      if let workspace {
        ConversationCommandContent(state: workspace)
      } else {
        Button("Open a workbook to use chats") {}.disabled(true)
      }
    }
  }
}

private struct ConversationCommandContent: View {
  @ObservedObject var state: WorkspaceState
  var body: some View {
    Button("Message Sevra") { state.composerFocusRequest = UUID() }.keyboardShortcut("l")
    Button("Stop", action: state.stop).keyboardShortcut(".").disabled(!state.busy)
    Divider()
    Button("Show Chats", action: state.showChats).keyboardShortcut("l", modifiers: [.command, .option])
    Button("New Chat", action: state.newChat).keyboardShortcut("n", modifiers: [.command, .shift])
      .disabled(state.changingConversation)
    Button("Rename Chat…") {
      state.chatRename = .init(chat: state.conversation, title: state.chatTitle)
    }.disabled(state.changingConversation)
    Button("Search This Chat…") { state.showingHistorySearch = true }
      .keyboardShortcut("f", modifiers: [.command, .option])
    Button("Delete Chat…") {
      state.chatDeletion = state.chats.first { $0.id == state.conversation }
    }.disabled(!state.canDeleteChat)
    Divider()
    Section("Recent exchanges") {
      ForEach(Array(state.messages.filter { $0.role != "tool" }.suffix(20).reversed())) { message in
        let content = state.messageContent(message).presentation
        let speaker =
          message.role == "user" ? "You" : message.role == "event" ? "Activity" : "Sevra"
        let text = String(content.text.characters.prefix(60))
          .replacingOccurrences(of: "\n", with: " ")
        Menu(speaker + ": " + text) {
          ConversationMessageActions(state: state, message: message, content: content)
        }
      }
    }
  }
}
