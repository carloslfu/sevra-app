import SevraCore
import SevraPreviewUI
import SwiftUI

struct ConversationHistorySheet: View {
  @ObservedObject var state: WorkspaceState
  @ObservedObject var search: ConversationHistorySearch
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @FocusState private var focused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Search " + state.conversationTitle).font(.title3.weight(.medium)).lineLimit(2)
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      TextField("Search messages…", text: $query).textFieldStyle(.roundedBorder)
        .focused($focused).accessibilityLabel("Search conversation messages")
      if search.loading { ProgressView("Searching messages…").controlSize(.small) }
      if let failure = search.failure {
        Text(failure).foregroundStyle(.red).textSelection(.enabled)
        Button("Retry search") {
          Task { await load(direction: search.failedDirection, force: true) }
        }
      }
      if let failure = state.conversationSession.failure {
        Text(failure).foregroundStyle(.red)
        Button("Return to draft") { dismiss() }
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if search.hits.isEmpty && !search.loading && search.failure == nil {
            Text(
              query.isEmpty
                ? "Find an earlier question, answer or activity in this conversation."
                : "No messages match this search in this conversation."
            ).foregroundStyle(.secondary)
          }
          ForEach(search.hits, id: \.text) { hit in
            let excerpt = String(ConversationPresentation(hit["excerpt"].text).text.characters)
            Button {
              state.jumpToMessage(hit["id"].text)
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                HStack {
                  Text(
                    hit["role"].text == "user"
                      ? "You" : hit["role"].text == "event" ? "Activity" : "Sevra"
                  )
                  .font(.caption.weight(.semibold))
                  Spacer()
                  Text(DisplayText.date(hit["created"].text)).font(.caption).foregroundStyle(
                    .secondary)
                }
                Text(excerpt).lineLimit(5).multilineTextAlignment(.leading)
              }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).accessibilityLabel(
              "Open original message: " + excerpt)
          }
        }
      }
      if search.hasPrevious || search.nextCursor != nil {
        HStack {
          Button("Previous matches") { Task { await load(direction: -1) } }.disabled(
            !search.hasPrevious || search.loading)
          Spacer()
          Text("Page \(search.pageNumber)").font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Next matches") { Task { await load(direction: 1) } }.disabled(
            search.nextCursor == nil || search.loading)
        }
      }
    }.padding(22).frame(width: 560, height: 520)
      .onAppear {
        query = search.query
        focused = true
      }
      .task(id: query) { await load(debounce: true) }
      .onDisappear { search.cancel() }
  }
  private func load(direction: Int = 0, debounce: Bool = false, force: Bool = false) async {
    guard let book = state.workbook else { return }
    let chat = state.conversation
    let text = query
    let scope = state.interactionIdentity.uuidString + "/" + chat
    await search.load(
      scope: scope, query: text, direction: direction, debounce: debounce, force: force
    ) { cursor, control in
      try await Task.detached(priority: .userInitiated) {
        try book.searchHistory(
          text, conversation: chat, cursor: cursor, limit: 20,
          cancellation: control, visibleOnly: true)
      }.value
    }
  }
}
