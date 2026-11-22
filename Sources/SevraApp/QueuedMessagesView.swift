import SevraCore
import SevraTableUI
import SwiftUI
import UniformTypeIdentifiers

/// Messages written while a reply runs. They send one at a time, in this order, after it
/// finishes. The person can edit, reorder (drag or menu) and remove each one.
struct QueuedMessagesView: View {
  @ObservedObject var state: WorkspaceState
  @State private var editing: String?
  @State private var editText = ""
  @State private var dropTarget: String?
  @FocusState private var editorFocused: Bool

  var body: some View {
    let queue = state.queue
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(queue.paused ? "Paused" : "Waiting")
          .readingFont(.caption).fontWeight(.semibold)
        Text(
          queue.paused
            ? "\(queue.messages.count) not sent. Resume when ready."
            : "\(queue.messages.count) of \(ConversationQueue.limit). Each sends after the reply before it."
        )
        .readingFont(.caption).foregroundStyle(.secondary).lineLimit(1)
        Spacer(minLength: 4)
        if queue.paused {
          Button("Resume", action: state.resumeQueue).controlSize(.small)
        }
        Button("Clear", action: state.clearQueue).buttonStyle(.link).readingFont(.caption)
          .accessibilityLabel("Remove all waiting messages")
      }
      ScrollView {
        VStack(spacing: 2) {
          ForEach(Array(queue.messages.enumerated()), id: \.element.id) { index, message in
            row(message, index: index, count: queue.messages.count)
          }
        }
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(maxHeight: queue.messages.count > 4 ? 190 : nil)
      .fixedSize(horizontal: false, vertical: queue.messages.count <= 4)
    }
    .padding(.bottom, 2)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Waiting messages")
  }

  @ViewBuilder private func row(_ message: QueuedConversationMessage, index: Int, count: Int)
    -> some View
  {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("\(index + 1)").readingFont(.caption).monospacedDigit().foregroundStyle(.secondary)
        .frame(minWidth: 14, alignment: .trailing).accessibilityHidden(true)
      if editing == message.id {
        VStack(alignment: .leading, spacing: 6) {
          TextField("Waiting message", text: $editText, axis: .vertical)
            .textFieldStyle(.roundedBorder).lineLimit(1...6).focused($editorFocused)
            .onSubmit { save(message.id) }
            .onExitCommand { editing = nil }
            .accessibilityLabel("Edit waiting message \(index + 1)")
          HStack {
            Button("Save") { save(message.id) }.controlSize(.small)
              .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel") { editing = nil }.controlSize(.small)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 2) {
          Text(message.text).readingFont(.callout).lineLimit(2).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
          if !message.context.isEmpty {
            Label("With the selection from when it was written", systemImage: "text.quote")
              .readingFont(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginEditing(message) }
        Menu {
          Button("Edit") { beginEditing(message) }
          Divider()
          Button("Move to top") { state.moveQueued(message.id, before: state.queue.messages.first?.id) }
            .disabled(index == 0)
          Button("Move up") { state.moveQueued(message.id, by: -1) }.disabled(index == 0)
          Button("Move down") { state.moveQueued(message.id, by: 1) }.disabled(index == count - 1)
          Button("Move to bottom") { state.moveQueued(message.id, before: nil) }
            .disabled(index == count - 1)
          Divider()
          Button("Remove") { state.removeQueued(message.id) }
        } label: {
          Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Edit, move or remove").accessibilityLabel("Actions for waiting message \(index + 1)")
        Button {
          state.removeQueued(message.id)
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.borderless).foregroundStyle(.secondary)
        .help("Remove").accessibilityLabel("Remove waiting message \(index + 1)")
      }
    }
    .padding(.vertical, 5).padding(.horizontal, 6)
    .background(
      Color.primary.opacity(dropTarget == message.id ? 0.10 : 0.04),
      in: RoundedRectangle(cornerRadius: 6)
    )
    .overlay(alignment: .top) {
      if dropTarget == message.id {
        Rectangle().fill(Color.accentColor).frame(height: 2).offset(y: -2)
      }
    }
    .draggable(QueuedMessageDrag(id: message.id)) {
      Text(message.text).lineLimit(1).padding(6)
    }
    .dropDestination(for: QueuedMessageDrag.self) { items, _ in
      guard let moved = items.first, moved.id != message.id else { return false }
      state.moveQueued(moved.id, before: message.id)
      return true
    } isTargeted: { targeted in
      if targeted { dropTarget = message.id } else if dropTarget == message.id { dropTarget = nil }
    }
    // Contain, not combine: a combined row is one element whose press opens the actions
    // menu, which hides the remove and actions buttons from VoiceOver and automation.
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Waiting message \(index + 1) of \(count): \(message.text)")
    .accessibilityAction(named: "Edit") { beginEditing(message) }
    .accessibilityAction(named: "Move up") { state.moveQueued(message.id, by: -1) }
    .accessibilityAction(named: "Move down") { state.moveQueued(message.id, by: 1) }
    .accessibilityAction(named: "Remove") { state.removeQueued(message.id) }
  }

  private func beginEditing(_ message: QueuedConversationMessage) {
    editText = message.text
    editing = message.id
    editorFocused = true
  }
  private func save(_ id: String) {
    if state.editQueued(id, text: editText) { editing = nil }
  }
}

/// Drag payload for reordering inside one window's queue.
struct QueuedMessageDrag: Codable, Transferable {
  let id: String
  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .data)
  }
}
