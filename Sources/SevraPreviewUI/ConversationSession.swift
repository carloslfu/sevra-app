import Foundation
import SevraCore

/// One window owns this session. Background writes are serialized, and a failed
/// save keeps the editor alive. Navigation/close await flush instead of dropping
/// a debounced task. Reading position and draft use the same conversation scope.
@MainActor public final class ConversationSession {
  private struct WeakSession { weak var value: ConversationSession? }
  private static var sessions: [WeakSession] = []
  private var workbook: Workbook?
  private var baseline = ConversationViewState()
  private var saving: Task<Bool, Never>?
  private var scheduled: Task<Void, Never>?
  private var preserveOther = false
  private var removeSaved: String?
  public private(set) var conversation = ""
  public private(set) var state = ConversationViewState()
  public private(set) var loading = false
  public private(set) var ready = false
  public private(set) var failure: String?
  public private(set) var conflict = false
  public var changed: (() -> Void)?
  public var restoredDraft: ((String) -> Void)?
  public var revealFailure: (() -> Void)?
  public var dirty: Bool {
    state.draft != baseline.draft || state.reading != baseline.reading
      || state.queue != baseline.queue || preserveOther || removeSaved != nil
  }
  public init() {
    Self.sessions.removeAll { $0.value == nil }
    Self.sessions.append(.init(value: self))
  }

  /// Opens the remembered chat, or the most recently active one when it was deleted or this
  /// file never had it.
  public func open(_ workbook: Workbook, conversation remembered: String?) async -> Bool {
    guard !loading, await flush() else { return false }
    let chat: String
    do {
      chat = try await Task.detached(priority: .userInitiated) {
        let chats = try workbook.chats()
        if let remembered, chats.contains(where: { $0.id == remembered }) { return remembered }
        return try chats.first?.id ?? workbook.createChat()
      }.value
    } catch {
      failure = error.localizedDescription
      revealFailure?()
      return false
    }
    return await load(chat, from: workbook)
  }
  public func select(_ conversation: String) async -> Bool {
    guard !loading, await flush() else { return false }
    guard let workbook else { return false }
    return await load(conversation, from: workbook)
  }
  private func load(_ conversation: String, from workbook: Workbook) async -> Bool {
    loading = true
    changed?()
    defer {
      loading = false
      changed?()
    }
    do {
      var value = try await Task.detached(priority: .userInitiated) {
        try workbook.conversationViewState(conversation)
      }.value
      // Waiting messages never send on their own when a chat is opened again.
      if !value.queue.isEmpty { value.queue.paused = true }
      self.workbook = workbook
      self.conversation = conversation
      state = value
      baseline = value
      failure = nil
      conflict = false
      ready = true
      return true
    } catch {
      failure = error.localizedDescription
      revealFailure?()
      return false
    }
  }
  public func updateDraft(_ text: String) {
    guard ready, !loading, text != state.draft else { return }
    state.draft = text
    schedule()
  }
  /// Waiting messages belong to the open chat and are saved with its draft.
  public func updateQueue(_ queue: ConversationQueue) {
    guard ready, !loading, queue != state.queue else { return }
    state.queue = queue
    schedule()
  }
  public func updateReading(_ position: ConversationReadingPosition) {
    guard ready, !loading, position != state.reading else { return }
    state.reading = position
    schedule()
  }
  private func schedule() {
    scheduled?.cancel()
    scheduled = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
      guard let self else { return }
      // A conflict needs a deliberate choice; typing must not dismiss it.
      if !self.conflict { _ = await self.flush() }
    }
    changed?()
  }
  @discardableResult public func flush() async -> Bool {
    scheduled?.cancel()
    scheduled = nil
    if let saving, !(await saving.value) { return false }
    guard dirty, let workbook else { return true }
    let chat = conversation
    let task = Task { [self] in
      defer { saving = nil }
      while dirty {
        let value = state
        let expected = baseline.draft
        let preserve = preserveOther
        let removing = removeSaved
        do {
          let saved = try await Task.detached(priority: .userInitiated) {
            try workbook.saveConversationViewState(
              chat, draft: value.draft, reading: value.reading,
              expectedDraft: expected, preserveOtherDraft: preserve, removeSavedDraft: removing,
              queue: value.queue)
          }.value
          baseline = saved
          if saved.draft != value.draft {
            if state.draft == value.draft {
              state.draft = saved.draft
              restoredDraft?(saved.draft)
            } else {
              // A keystroke arrived while a reading-only save discovered an
              // external edit. Its next save still needs the old comparison.
              baseline.draft = expected
            }
          }
          state.savedDrafts = saved.savedDrafts
          if preserveOther == preserve { preserveOther = false }
          if removeSaved == removing { removeSaved = nil }
          failure = nil
          conflict = false
          changed?()
        } catch {
          conflict = (error as? SevraError)?.code == "draft_conflict"
          failure = error.localizedDescription
          changed?()
          revealFailure?()
          return false
        }
      }
      return true
    }
    saving = task
    return await task.value
  }
  public func keepBoth() async -> Bool {
    if let saving { _ = await saving.value }
    preserveOther = true
    return await flush()
  }
  public func restoreSaved(_ id: String) async -> Bool {
    guard let saved = state.savedDrafts.first(where: { $0.id == id }), await flush() else {
      return false
    }
    state.draft = saved.text
    preserveOther = true
    removeSaved = id
    return await flush()
  }
  public func discardSaved(_ id: String) async -> Bool {
    if let saving { _ = await saving.value }
    removeSaved = id
    return await flush()
  }
  public static func flushAll() async -> Bool {
    sessions.removeAll { $0.value == nil }
    var success = true
    for session in sessions.compactMap(\.value) {
      if !(await session.flush()) { success = false }
    }
    return success
  }
  /// The open chat was deleted elsewhere: what this window had not saved has nowhere to go.
  public func abandonUnsaved() {
    scheduled?.cancel()
    scheduled = nil
    baseline = state
    preserveOther = false
    removeSaved = nil
    conflict = false
    failure = nil
  }
  /// After the window saved and closed: the workbook is let go and nothing more is written.
  public func close() {
    scheduled?.cancel()
    scheduled = nil
    workbook = nil
    ready = false
  }
}
