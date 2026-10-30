import AppKit
import SevraCore
import SevraPreviewUI
import SwiftUI

struct ConversationMessageRow: View {
  @ObservedObject var state: WorkspaceState
  let message: Message
  private var speaker: String {
    message.role == "user" ? "You" : message.role == "event" ? "Activity" : "Sevra"
  }
  private var status: String {
    guard message.state == "needs_review" else { return message.state }
    guard let review = state.proposalReviews[message.id] else { return "Review requested" }
    switch review.status {
    case "accepted": return "Current version accepted"
    case "rejected": return "Current version withdrawn"
    case "draft":
      return review.proposalID == review.currentVersionID ? "Needs your review" : "Newer draft"
    default: return "Review requested"
    }
  }
  var body: some View {
    let content = ConversationPresentation(message.body)
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(speaker).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        if message.state != "complete" {
          if let review = state.proposalReviews[message.id] {
            Button(status) { state.navigate(.item(review.currentVersionID)) }
              .buttonStyle(.plain).font(.caption)
              .foregroundStyle(review.status == "draft" ? Color.orange : Color.secondary)
              .help("Open the current proposal, version \(review.currentVersion)")
          } else {
            Text(status).font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer()
        MoreActionsMenu(
          speaker + " message actions", help: "Open links, save this exchange or start a thread"
        ) {
          ConversationMessageActions(state: state, message: message, content: content)
        }
      }
      VStack(alignment: .leading, spacing: 10) {
        ForEach(Array(content.blocks.enumerated()), id: \.offset) { _, block in
          switch block {
          case .text(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              Text(ConversationPresentation(text.trimmingCharacters(in: .newlines)).text)
                .textSelection(.enabled).lineSpacing(4)
            }
          case .table(let table):
            ReadOnlyTableView(
              content: table, label: "Comparison table", inline: true,
              open: state.openConversationLink)
          }
        }
      }
      .accessibilityActions {
        ForEach(content.links) { link in
          Button(link.actionTitle) { state.openConversationLink(link.url) }
        }
      }
    }.accessibilityElement(children: .contain)
      .accessibilityLabel(speaker + " message" + (message.state == "complete" ? "" : ", " + status))
      .accessibilityIdentifier("message-" + message.id)
      .contextMenu { ConversationMessageActions(state: state, message: message, content: content) }
  }
}

struct ConversationMessageActions: View {
  @ObservedObject var state: WorkspaceState
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
          Button(link.actionTitle) { state.openConversationLink(link.url) }
        }
      }
    }
    Button("Save this exchange") {
      do {
        try state.workbook?.chapter(
          title: String(message.body.prefix(60)), message: message.id, bookmark: true)
        state.refresh()
      } catch { state.error = error.localizedDescription }
    }
    Button("Start a thread") {
      state.startThread(from: message.id)
    }
    if state.conversation != "main", message.state == "complete",
      ["user", "assistant"].contains(message.role)
    {
      Button("Share summary with conversation…") { state.requestSummary(message: message) }
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
    CommandMenu("Conversation") {
      if let workspace {
        ConversationCommandContent(state: workspace)
      } else {
        Button("Open a workbook to use conversation actions") {}.disabled(true)
      }
    }
  }
}

private struct ConversationCommandContent: View {
  @ObservedObject var state: WorkspaceState
  var body: some View {
    Button("Message Sevra") { state.composerFocusRequest = UUID() }.keyboardShortcut("l")
    Button("Search This Conversation…") { state.showingHistorySearch = true }
      .keyboardShortcut("f", modifiers: [.command, .option])
    Button("Start a Thread") {
      if let message = state.messages.last { state.startThread(from: message.id) }
    }.disabled(state.messages.isEmpty || state.changingConversation)
    Button("Rename Thread…", action: state.requestRenameThread).disabled(
      state.conversation == "main")
    Button("Back to Conversation") { state.changeConversation("main") }
      .disabled(state.conversation == "main")
    Divider()
    Section("Recent exchanges") {
      ForEach(Array(state.messages.filter { $0.role != "tool" }.suffix(20).reversed())) { message in
        let preview = ConversationPresentation(String(message.body.prefix(240)))
        let speaker =
          message.role == "user" ? "You" : message.role == "event" ? "Activity" : "Sevra"
        let text = String(preview.text.characters).replacingOccurrences(of: "\n", with: " ")
        Menu(speaker + ": " + String(text.prefix(60))) {
          ConversationMessageActions(
            state: state, message: message,
            content: ConversationPresentation(message.body))
        }
      }
    }
  }
}
