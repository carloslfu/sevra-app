import SevraCore
import SevraTableUI
import SwiftUI

/// When a chat was last active, as the chat list groups and labels it.
enum ChatTimes {
  enum Group: Int, CaseIterable {
    case today, yesterday, week, month, older
    var title: String {
      switch self {
      case .today: "Today"
      case .yesterday: "Yesterday"
      case .week: "Previous 7 days"
      case .month: "Previous 30 days"
      case .older: "Older"
      }
    }
  }
  private static let parser = ISO8601DateFormatter()
  private static let fractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
  static func date(_ text: String) -> Date? {
    parser.date(from: text) ?? fractional.date(from: text)
  }
  static func group(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> Group {
    guard let date else { return .older }
    if calendar.isDate(date, inSameDayAs: now) || date > now { return .today }
    if calendar.isDateInYesterday(date) { return .yesterday }
    let start = calendar.startOfDay(for: now)
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: start).day ?? 0
    if days < 7 { return .week }
    if days < 30 { return .month }
    return .older
  }
  /// The time today and yesterday (the group already says which day), the weekday this week,
  /// then the date.
  static func label(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
    guard let date else { return "" }
    switch group(date, now: now, calendar: calendar) {
    case .today, .yesterday: return date.formatted(date: .omitted, time: .shortened)
    case .week: return date.formatted(.dateTime.weekday(.wide))
    case .month, .older:
      return calendar.isDate(date, equalTo: now, toGranularity: .year)
        ? date.formatted(.dateTime.month(.abbreviated).day())
        : date.formatted(.dateTime.month(.abbreviated).day().year())
    }
  }
}

/// The workbook's chats, shown in place of the open chat: search, the chats grouped by when
/// they were last active, and Rename and Delete on each. Opening one, Back or Escape returns.
struct ChatListPanel: View {
  @ObservedObject var state: WorkspaceState
  @State private var query = ""
  @State private var highlighted: String?
  @State private var renaming: String?
  @State private var newTitle = ""
  @State private var renameFailure: String?
  @FocusState private var searchFocused: Bool
  @FocusState private var renameFocused: Bool

  private var matches: [Chat] {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return state.chats }
    return state.chats.filter {
      $0.title.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }
  private var sections: [(group: ChatTimes.Group, chats: [Chat])] {
    let now = Date()
    let grouped = Dictionary(grouping: matches) { ChatTimes.group(ChatTimes.date($0.updated), now: now) }
    return ChatTimes.Group.allCases.compactMap { group in
      grouped[group].map { (group, $0) }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      PaneHeader {
        HeaderIconButton("Back to chat", systemImage: "chevron.left") { close() }
        Text("Chats").readingFont(.subheadline, weight: .medium)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 4)
        HeaderIconButton("New chat", systemImage: "square.and.pencil") { state.newChat() }
          .disabled(state.changingConversation)
      }
      Divider()
      TextField("Search chats", text: $query)
        .textFieldStyle(.roundedBorder)
        .focused($searchFocused)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .onSubmit { open(highlighted ?? matches.first?.id) }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .accessibilityLabel("Search chats")
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
            if matches.isEmpty {
              Text(
                state.chats.isEmpty
                  ? "No chats yet. Start one with New Chat."
                  : "No chats match “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”."
              )
              .foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 12)
            }
            ForEach(sections, id: \.group) { section in
              Text(section.group.title)
                .readingFont(.caption, weight: .medium).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
              ForEach(section.chats) { chat in
                row(chat).id(chat.id)
              }
            }
          }.padding(.horizontal, 8).padding(.bottom, 12)
        }
        .onChange(of: highlighted) { _, id in
          if let id { proxy.scrollTo(id) }
        }
      }
    }
    .disabled(state.changingConversation)
    .onExitCommand {
      if renaming != nil { renaming = nil } else { close() }
    }
    .onAppear {
      highlighted = state.conversation
      searchFocused = true
    }
    .onChange(of: query) { _, _ in highlighted = matches.first?.id }
    .accessibilityElement(children: .contain).accessibilityLabel("Chats")
  }

  @ViewBuilder private func row(_ chat: Chat) -> some View {
    let open = chat.id == state.conversation
    let lit = chat.id == highlighted
    let when = ChatTimes.label(ChatTimes.date(chat.updated))
    if renaming == chat.id {
      VStack(alignment: .leading, spacing: 4) {
        TextField("Chat name", text: $newTitle)
          .textFieldStyle(.roundedBorder)
          .focused($renameFocused)
          .onSubmit { commitRename(chat) }
          .onExitCommand { renaming = nil }
          .accessibilityLabel("Chat name")
        if let renameFailure {
          Text(renameFailure).readingFont(.caption).foregroundStyle(.red)
        }
      }.padding(.horizontal, 8).padding(.vertical, 6)
    } else {
      Button {
        self.open(chat.id)
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(chat.title).lineLimit(2).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fontWeight(open ? .medium : .regular)
          Text(when).readingFont(.caption).foregroundStyle(.secondary).monospacedDigit()
            .lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(
              open
                ? Color.accentColor.opacity(0.16)
                : lit ? Color.primary.opacity(0.07) : Color.clear)
        )
      }
      .buttonStyle(.plain)
      .onHover { inside in if inside { highlighted = chat.id } }
      .contextMenu { actions(chat) }
      .accessibilityLabel(chat.title)
      .accessibilityValue(open ? "Open chat, last active \(when)" : "Last active \(when)")
      .accessibilityHint("Opens this chat")
      .accessibilityActions { actions(chat) }
    }
  }

  @ViewBuilder private func actions(_ chat: Chat) -> some View {
    Button("Rename…") { startRename(chat) }
    Button("Delete…", role: .destructive) { state.chatDeletion = chat }
      .disabled(!state.canDeleteChat)
  }

  private func move(_ step: Int) -> KeyPress.Result {
    let ids = sections.flatMap { $0.chats.map(\.id) }
    guard !ids.isEmpty else { return .handled }
    let index = highlighted.flatMap { ids.firstIndex(of: $0) } ?? (step > 0 ? -1 : ids.count)
    highlighted = ids[min(max(index + step, 0), ids.count - 1)]
    return .handled
  }
  private func open(_ id: String?) {
    guard let id else { return }
    if id == state.conversation { close() } else { state.changeConversation(id) }
  }
  private func close() {
    state.showingChats = false
  }
  private func startRename(_ chat: Chat) {
    renameFailure = nil
    newTitle = chat.title
    renaming = chat.id
    DispatchQueue.main.async { renameFocused = true }
  }
  private func commitRename(_ chat: Chat) {
    let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, title != chat.title else {
      renaming = nil
      return
    }
    Task {
      do {
        try await state.renameChat(chat.id, title: title, token: UUID().uuidString)
        renaming = nil
        searchFocused = true
      } catch {
        renameFailure = error.localizedDescription
      }
    }
  }
}
