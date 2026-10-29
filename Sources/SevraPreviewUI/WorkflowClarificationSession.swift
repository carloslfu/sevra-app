import Combine
import Foundation
import SevraCore

/// Window-owned, so navigating away does not destroy incomplete answers.
@MainActor public final class WorkflowClarificationSession: ObservableObject {
  @Published public private(set) var state: WorkflowClarificationDraft?
  @Published public private(set) var preview: Value?
  @Published public private(set) var failure: String?
  @Published public private(set) var conflict = false
  @Published public private(set) var busy = false
  @Published public private(set) var currentTarget: Value?
  private let workbook: Workbook
  private let runID: String
  private var baseline: WorkflowClarificationDraft?
  private var saving: Task<Bool, Never>?
  private var scheduled: Task<Void, Never>?
  private var keepOther = false
  private var targetRequest = UUID()
  public var changed: (() -> Void)?
  public var dirty: Bool { state != baseline }
  public init(workbook: Workbook, runID: String) {
    self.workbook = workbook
    self.runID = runID
  }
  public func open() async {
    guard state == nil, !busy else { return }
    busy = true
    defer { busy = false }
    do {
      let (saved, draft, receipt) = try await Task.detached { [workbook, runID] in
        let saved = try workbook.workflowClarificationDraft(runID)
        let draft = try saved ?? workbook.newWorkflowClarificationDraft(runID)
        return (saved, draft, try workbook.workflowClarificationDraftReceipt(draft.entry))
      }.value
      baseline = saved
      state = draft
      if let receipt { state?.entry.receipt = receipt }
      await refreshTarget()
      _ = await flush()
    } catch { fail(error) }
  }
  public func reloadSaved() async {
    guard !busy, await flush() else { return }
    state = nil
    baseline = nil
    preview = nil
    await open()
  }
  public func refreshTarget() async {
    let request = UUID()
    targetRequest = request
    let target = try? await Task.detached { [workbook, runID] in
      try workbook.workflowClarification(runID)
    }.value
    guard targetRequest == request, !Task.isCancelled else { return }
    if currentTarget != target { preview = nil }
    currentTarget = target
  }
  public func update(values: Value, reason: String) {
    guard !busy, state != nil, state?.entry.receipt == nil else { return }
    state?.entry.values = values
    state?.entry.reason = reason
    preview = nil
    scheduled?.cancel()
    scheduled = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
      guard let self, !self.conflict else { return }
      _ = await self.flush()
    }
    changed?()
  }
  public func prepare() async {
    guard !busy, let draft = state, draft.entry.receipt == nil else { return }
    busy = true
    preview = nil
    defer { busy = false }
    do {
      preview = try await Task.detached { [workbook] in
        try workbook.previewWorkflowClarificationDraft(draft)
      }.value
      failure = nil
    } catch {
      fail(error)
      await refreshTarget()
    }
  }
  public func submit() async {
    guard !busy, let draft = state, let preview, draft.entry.receipt == nil else { return }
    busy = true
    defer { busy = false }
    guard await flush() else { return }
    do {
      let receipt = try await Task.detached { [workbook] in
        try workbook.submitWorkflowClarificationDraft(draft, preview: preview)
      }.value
      state?.entry.receipt = receipt
      self.preview = nil
      _ = await flush()
      changed?()
    } catch { fail(error) }
  }
  public func useCurrent() async {
    guard !busy, await flush(), let old = state else { return }
    busy = true
    defer { busy = false }
    do {
      var next = try await Task.detached { [workbook, runID] in
        try workbook.newWorkflowClarificationDraft(runID)
      }.value
      try require(
        old.alternatives.count < 8, "clarification_draft_limit",
        "Remove an alternative before retaining another.")
      next.alternatives = old.alternatives + [old.entry]
      if old.entry.receipt == nil {
        let fields = Set(next.entry.target["fields"].array.map { $0["id"].text })
        next.entry.values = .object(old.entry.values.object.filter { fields.contains($0.key) })
        next.entry.reason = old.entry.reason
      }
      state = next
      targetRequest = UUID()
      currentTarget = next.entry.target
      preview = nil
      _ = await flush()
    } catch { fail(error) }
  }
  public func restoreAlternative(_ id: String) async {
    guard !busy, await flush(), var draft = state,
      let entry = draft.alternatives.first(where: { $0.id == id })
    else { return }
    draft.alternatives.removeAll { $0.id == id }
    draft.alternatives.append(draft.entry)
    busy = true
    defer { busy = false }
    do {
      var recovered = entry
      recovered.receipt = try await Task.detached { [workbook] in
        try workbook.workflowClarificationDraftReceipt(entry)
      }.value
      draft.entry = recovered
      state = draft
      preview = nil
      _ = await flush()
    } catch { fail(error) }
  }
  public func discardAlternative(_ id: String) async {
    guard !busy else { return }
    state?.alternatives.removeAll { $0.id == id }
    _ = await flush()
  }
  public func keepBoth() async {
    keepOther = true
    _ = await flush()
  }
  @discardableResult public func flush() async -> Bool {
    scheduled?.cancel()
    scheduled = nil
    if let saving, !(await saving.value) { return false }
    guard dirty, state != nil else { return true }
    let task = Task { [self] in
      defer { saving = nil }
      while let draft = state, dirty {
        let expected = baseline
        let preserve = keepOther
        do {
          let saved = try await Task.detached { [workbook, runID] in
            try workbook.saveWorkflowClarificationDraft(
              runID, draft: draft, expected: expected, keepOther: preserve)
          }.value
          baseline = saved
          if state == draft {
            state = saved
          } else {
            // Retain edits typed while the write was in progress.
            let values = state?.entry.values ?? saved.entry.values
            let reason = state?.entry.reason ?? saved.entry.reason
            state = saved
            state?.entry.values = values
            state?.entry.reason = reason
          }
          keepOther = false
          failure = nil
          conflict = false
          changed?()
        } catch {
          fail(error)
          return false
        }
      }
      return true
    }
    saving = task
    return await task.value
  }
  private func fail(_ error: Error) {
    failure = error.localizedDescription
    conflict = (error as? SevraError)?.code == "clarification_draft_conflict"
    changed?()
  }
}

@MainActor public final class WorkflowClarificationScope {
  private struct WeakScope { weak var value: WorkflowClarificationScope? }
  private static var scopes: [WeakScope] = []
  private var workbook: Workbook?
  private var sessions: [String: WorkflowClarificationSession] = [:]
  public var changed: (() -> Void)?
  public init() {
    Self.scopes.removeAll { $0.value == nil }
    Self.scopes.append(.init(value: self))
  }
  public func open(_ workbook: Workbook) async -> Bool {
    guard await flush() else { return false }
    self.workbook = workbook
    sessions = [:]
    return true
  }
  public func session(_ runID: String) -> WorkflowClarificationSession? {
    guard let workbook else { return nil }
    if let session = sessions[runID] { return session }
    let session = WorkflowClarificationSession(workbook: workbook, runID: runID)
    session.changed = { [weak self] in self?.changed?() }
    sessions[runID] = session
    return session
  }
  public func flush() async -> Bool {
    var saved = true
    for session in sessions.values { if !(await session.flush()) { saved = false } }
    return saved
  }
  public static func flushAll() async -> Bool {
    Self.scopes.removeAll { $0.value == nil }
    var saved = true
    for scope in Self.scopes.compactMap(\.value) { if !(await scope.flush()) { saved = false } }
    return saved
  }
}
