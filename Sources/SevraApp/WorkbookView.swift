import AVKit
import AppKit
import SevraCore
import SwiftUI

struct WorkbookView: View {
  @ObservedObject var state: WorkspaceState
  @State private var showSpaces = false
  @State private var spaceSearch = ""
  @State private var conversationDraft: ConversationDraft?
  @FocusState private var composerFocused: Bool
  let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        ObserverMark().fill(.primary).frame(width: 28, height: 28).accessibilityHidden(true)
        Text(state.workbook?.title ?? "Sevra").font(.headline)
        Spacer()
        if state.busy {
          ProgressView().controlSize(.small)
          Text(state.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          Button("Stop", action: state.stop)
        }
        Button {
          state.navigate(.search)
        } label: {
          Image(systemName: "magnifyingglass")
        }.help("Search documents, records and filenames")
        Menu {
          Button("Include files…") { state.importPanel() }
          Button("Link external files…") { state.importPanel(linked: true) }
          Divider()
          Button("Make a shareable copy…", action: state.exportPanel)
        } label: {
          Image(systemName: "plus")
        }.menuStyle(.borderlessButton).frame(width: 24)
        Button {
          state.focus.toggle()
        } label: {
          Image(systemName: "sidebar.left")
        }.help("Focus workspace")
      }.padding(.horizontal, 20).padding(.vertical, 12)
      Divider()
      HSplitView {
        if !state.focus { conversation.frame(minWidth: 270, idealWidth: 360, maxWidth: 420) }
        VStack(spacing: 0) {
          HStack {
            if !state.navigation.isEmpty {
              Button(action: state.back) { Image(systemName: "chevron.left") }.help("Back")
            }
            Text(routeTitle).font(.title3.weight(.medium)).lineLimit(1)
            Spacer()
            Button("Spaces", systemImage: "square.grid.2x2") { showSpaces.toggle() }
              .popover(isPresented: $showSpaces) { spacePicker }
          }.padding(18)
          Divider()
          workspace.frame(maxWidth: .infinity, maxHeight: .infinity)
          if let player = state.backgroundPlayer {
            Divider()
            HStack {
              VideoPlayer(player: player).frame(width: 180, height: 100)
              Text(state.backgroundMediaTitle).lineLimit(2)
              Spacer()
              Button("Close player") {
                player.pause()
                state.backgroundPlayer = nil
              }
            }.padding(10)
          }
          if state.focus {
            Divider()
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
      .sheet(item: $conversationDraft) { draft in
        ConversationNameSheet(draft: draft) { name in
          guard let book = state.workbook else { return }
          if draft.tangent {
            let id = try book.tangent(title: name, parentMessage: draft.message)
            state.changeConversation(id)
          } else {
            try book.chapter(title: name, message: draft.message)
            state.refresh()
          }
          conversationDraft = nil
          composerFocused = true
        }
      }
      .onReceive(timer) { _ in state.poll() }.onDisappear { state.speech.stop() }
      .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
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
          state.importFiles(urls)
        }
        return true
      }
      .environment(
        \.openURL,
        OpenURLAction { url in
          if url.scheme == "sevra", url.host == "item" {
            state.openEvidence(
              url.lastPathComponent,
              locator: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
                $0.name == "locator"
              }?.value)
            return .handled
          }
          if url.scheme == "sevra", url.host == "conversation",
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(
              where: { $0.name == "message" })?.value
          {
            state.jumpToMessage(id)
            return .handled
          }
          return .systemAction
        })
  }
  var routeTitle: String {
    switch state.route {
    case .space(let id): return state.spaces.first { $0.id == id }?.title ?? "Space"
    case .item(let id): return (try? state.workbook?.item(id).title) ?? "Document"
    case .table(let id): return state.datasets.first { $0.id == id }?.title ?? "Table"
    case .search: return "Search workbook"
    }
  }
  var conversation: some View {
    VStack(spacing: 0) {
      HStack {
        Menu {
          ForEach(state.conversations, id: \.text) { chat in
            Button(chat["title"].text) { state.changeConversation(chat["id"].text) }
          }
        } label: {
          Text(
            state.conversations.first { $0["id"].text == state.conversation }?["title"].text
              ?? "Main conversation"
          ).font(.subheadline.weight(.medium))
        }
        Spacer()
        Menu {
          Button("Start a chapter") {
            if let message = state.messages.last {
              conversationDraft = .init(tangent: false, message: message.id)
            }
          }.disabled(state.messages.isEmpty)
          Button("Explore a tangent") {
            if let message = state.messages.last {
              conversationDraft = .init(tangent: true, message: message.id)
            }
          }.disabled(state.messages.isEmpty)
          if state.conversation != "main" {
            Button("Return to main") { state.changeConversation("main") }
            Button("Bring last answer to main") {
              if let message = state.messages.last(where: {
                $0.role == "assistant" && $0.state == "complete"
              }) {
                do {
                  _ = try state.workbook?.bringToMain(message: message.id)
                  state.changeConversation("main")
                } catch { state.error = error.localizedDescription }
              }
            }
          }
          if let book = state.workbook, let bookmarks = try? book.chapters(bookmarks: true),
            !bookmarks.isEmpty
          {
            Menu("Saved exchanges") {
              ForEach(bookmarks, id: \.text) { bookmark in
                Button(bookmark["title"].text) { state.jumpToMessage(bookmark["message_id"].text) }
              }
            }
          }
          if let book = state.workbook, let chapters = try? book.chapters() {
            ForEach(chapters, id: \.text) { chapter in
              Button(chapter["title"].text) { state.jumpToMessage(chapter["message_id"].text) }
            }
          }
        } label: {
          Image(systemName: "ellipsis")
        }.menuStyle(.borderlessButton).frame(width: 20)
      }.padding(16)
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 24) {
            if state.messages.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Text("What are we working on?").font(.title2.weight(.medium))
                Text("Add a file, ask a question, or describe what you want to organize.")
                  .foregroundStyle(.secondary)
              }.padding(.top, 30)
            }
            ForEach(state.messages.filter { $0.role != "tool" }) { message in
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Text(
                    message.role == "user" ? "You" : message.role == "event" ? "Activity" : "Sevra"
                  ).font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                  if message.state != "complete" {
                    Text(message.state == "needs_review" ? "Needs your review" : message.state)
                      .font(.caption).foregroundStyle(.orange)
                  }
                }
                Text(
                  (try? AttributedString(
                    markdown: message.body,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    ?? AttributedString(message.body)
                ).textSelection(.enabled).lineSpacing(4)
              }.id(message.id).contextMenu {
                Button("Save this exchange") {
                  try? state.workbook?.chapter(
                    title: String(message.body.prefix(60)), message: message.id, bookmark: true)
                }
                Button("Explore a tangent") {
                  conversationDraft = .init(tangent: true, message: message.id)
                }
              }
            }
            if state.busy {
              Text(state.status).font(.callout).foregroundStyle(.secondary).id("working")
            }
          }.padding(20)
        }.onChange(of: state.messages.count) { _, _ in
          if state.messageAnchor == nil, let id = state.messages.last?.id {
            proxy.scrollTo(id, anchor: .bottom)
          }
        }.onChange(of: state.messageAnchor) { _, id in
          if let id { proxy.scrollTo(id, anchor: .top) }
        }
      }
      Divider()
      composer.padding(14)
    }
  }
  var composer: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !state.selectedContext.isEmpty {
        Text("About: " + (state.selectionLabel ?? String(state.selectedContext.prefix(100)))).font(
          .caption
        ).foregroundStyle(
          .secondary
        ).lineLimit(2)
      }
      TextField("Type or speak…", text: $state.prompt, axis: .vertical).textFieldStyle(.plain)
        .focused($composerFocused).lineLimit(2...7).onSubmit { state.send() }.accessibilityLabel(
          "Message Sevra")
      HStack {
        VoiceButton(speech: state.speech, action: state.voice)
        Spacer()
        Text("Local AI").font(.caption).foregroundStyle(.secondary)
        Button(action: state.send) { Image(systemName: "arrow.up") }.buttonStyle(.borderedProminent)
          .disabled(
            state.busy || state.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ).keyboardShortcut(.return, modifiers: .command).accessibilityLabel("Send message")
      }
    }.padding(12).background(
      Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12)
    ).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12)))
  }
  var spacePicker: some View {
    VStack(alignment: .leading, spacing: 12) {
      TextField("Find a space", text: $spaceSearch).textFieldStyle(.roundedBorder)
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(
            state.spaces.filter {
              spaceSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(spaceSearch)
            }
          ) { space in
            Button {
              state.navigate(.space(space.id))
              showSpaces = false
            } label: {
              HStack {
                Image(systemName: space.id == "home" ? "house" : "rectangle.split.2x2")
                Text(space.title)
                Spacer()
              }.padding(8)
            }.buttonStyle(.plain)
          }
        }
      }
      Divider()
      Button("Create a space through conversation") {
        state.prompt = "Create a space for "
        showSpaces = false
      }
    }.padding(16).frame(width: 290, height: 320)
  }
  @ViewBuilder var workspace: some View {
    if let book = state.workbook {
      switch state.route {
      case .space(let id):
        if let space = state.spaces.first(where: { $0.id == id }) {
          SpaceView(space: space, state: state).id(space.id)
        }
      case .item(let id):
        if let item = try? book.item(id) { ItemView(item: item, state: state).id(id) }
      case .table(let id):
        if let table = state.datasets.first(where: { $0.id == id }) {
          DatasetView(table: table, state: state)
        }
      case .search: SearchView(state: state, results: state.searchResults)
      }
    }
  }
}

private struct ConversationDraft: Identifiable {
  let id = UUID()
  let tangent: Bool
  let message: String
}

private struct ConversationNameSheet: View {
  let draft: ConversationDraft
  let create: (String) throws -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var failure: String?
  @FocusState private var focused: Bool
  private var title: String { draft.tangent ? "Explore a tangent" : "Start a chapter" }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(title).font(.title2.weight(.medium))
      Text(
        draft.tangent
          ? "Explore from this point in a separate conversation. You can return to the main conversation at any time."
          : "Name this point so you can find it later in the conversation."
      )
      .foregroundStyle(.secondary)
      TextField("Name", text: $name).textFieldStyle(.roundedBorder).focused($focused)
      if let failure { Text(failure).foregroundStyle(.red).font(.callout) }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button(draft.tangent ? "Explore" : "Create chapter") {
          do { try create(name.trimmingCharacters(in: .whitespacesAndNewlines)) } catch {
            failure = error.localizedDescription
          }
        }.keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(24).frame(width: 400).onAppear { focused = true }
  }
}
