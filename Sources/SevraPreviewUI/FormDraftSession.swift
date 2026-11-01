import Combine
import Foundation
import SevraCore

/// Owned by the workbook window, so Back/removing a view cannot drop pending text.
@MainActor public final class FormDraftSession: ObservableObject {
  @Published public private(set) var state: FormDraftState?
  @Published public private(set) var definition: ApplicationDefinition?
  @Published public private(set) var preview: Value?
  @Published public private(set) var issues: [Value] = []
  @Published public private(set) var failure: String?
  @Published public private(set) var conflict = false
  /// A live action or function changed under this draft, so only the current form can submit.
  @Published public private(set) var stale = false
  @Published public private(set) var busy = false
  private let workbook: Workbook
  private let key: String
  private var baseline: FormDraftState?
  /// A form nobody has edited takes no saved-draft slot, however many a workbook shows.
  private var untouched: FormDraftState?
  private var saving: Task<Bool, Never>?
  private var scheduled: Task<Void, Never>?
  private var keepOther = false
  public var changed: (() -> Void)?
  public var revealFailure: (() -> Void)?
  public var dirty: Bool { state != baseline && state != untouched }
  public init(workbook: Workbook, key: String) {
    self.workbook = workbook
    self.key = key
  }

  public func open(_ formID: String) async {
    guard state == nil, !busy else { return }
    busy = true
    defer { busy = false }
    do {
      let loaded = try await Task.detached { [workbook, key] in
        let existing = try workbook.formDraft(key)
        var value = try existing ?? workbook.newFormDraft(formID)
        let definition = try workbook.applicationDefinition(value.definitionID)
        var receipt: Value?
        do {
          receipt = try workbook.applicationFormReceipt(
            value.invocationToken, definitionID: value.definitionID, arguments: value.arguments)
        } catch let error as SevraError where error.code == "action_token" {
          // Another draft spent this retry identity. These inputs can still go under a new one.
          value.invocationToken = identifier()
        }
        return (existing, value, definition, receipt)
      }.value
      baseline = loaded.0
      state = loaded.1
      definition = loaded.2
      if let receipt = loaded.3 { state?.lastReceipt = receipt }
      if loaded.0 == nil, loaded.3 == nil { untouched = state }
      _ = await flush()
    } catch { fail(error) }
  }
  public func update(_ arguments: Value) {
    guard !busy, state?.lastReceipt == nil, state != nil else { return }
    state?.arguments = arguments
    preview = nil
    issues = []
    scheduled?.cancel()
    scheduled = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
      guard let self, !self.conflict else { return }
      _ = await self.flush()
    }
    changed?()
  }
  public func prepare() async {
    guard !busy, let value = state else { return }
    busy = true
    preview = nil
    stale = false
    defer { busy = false }
    do {
      let result = try await Task.detached { [workbook] in
        let issues = try workbook.applicationInputIssues(
          value.definitionID, arguments: value.arguments)
        return (issues, issues.isEmpty ? try workbook.previewFormDraft(value) : nil)
      }.value
      guard state == value else { return }
      issues = result.0
      preview = result.1
      failure = issues.isEmpty ? nil : "Check the highlighted fields. Your inputs are retained."
    } catch { fail(error) }
  }
  public func submit() async {
    guard !busy, let value = state, let preview, value.lastReceipt == nil else { return }
    busy = true
    defer { busy = false }
    // The retry identity is saved before it spends anything.
    untouched = nil
    guard await flush() else { return }
    do {
      let receipt = try await Task.detached { [workbook] in
        try workbook.submitFormDraft(value, preview: preview, actor: .human("SevraNativeForm"))
      }.value
      state?.lastReceipt = receipt
      self.preview = nil
      _ = await flush()
      changed?()
    } catch {
      // The plan it showed is no longer what would run. Preview again from the same inputs.
      self.preview = nil
      fail(error)
    }
  }
  /// This explicit choice follows current definitions. Keep prior unsent values as an alternative.
  public func useCurrent(_ formID: String, carryInputs: Bool) async {
    guard !busy, await flush(), let current = state else { return }
    busy = true
    defer { busy = false }
    do {
      var next = try await Task.detached { [workbook] in try workbook.newFormDraft(formID) }.value
      next.alternatives = current.alternatives
      if carryInputs && current.lastReceipt == nil {
        try require(
          next.alternatives.count < 8, "form_draft_limit",
          "Remove a saved alternative before retaining another.")
        next.alternatives.append(
          .init(
            id: identifier(), definitionID: current.definitionID,
            resolvedDefinitions: current.resolvedDefinitions, arguments: current.arguments,
            invocationToken: current.invocationToken, lastReceipt: current.lastReceipt))
        let definition = try await Task.detached { [workbook] in
          try workbook.applicationDefinition(next.definitionID)
        }.value
        let ids = Set(definition.parameters.array.map { $0["id"].text })
        next.arguments = .object(current.arguments.object.filter { ids.contains($0.key) })
      }
      let definition = try await Task.detached { [workbook] in
        try workbook.applicationDefinition(next.definitionID)
      }.value
      state = next
      self.definition = definition
      preview = nil
      issues = []
      stale = false
      _ = await flush()
    } catch { fail(error) }
  }
  public func restoreAlternative(_ id: String) async {
    guard !busy, await flush(), let current = state,
      let saved = current.alternatives.first(where: { $0.id == id })
    else { return }
    var next = FormDraftState(
      definitionID: saved.definitionID, resolvedDefinitions: saved.resolvedDefinitions,
      invocationToken: saved.invocationToken)
    next.arguments = saved.arguments
    next.lastReceipt = saved.lastReceipt
    next.alternatives = current.alternatives.filter { $0.id != id }
    next.alternatives.append(
      .init(
        id: identifier(), definitionID: current.definitionID,
        resolvedDefinitions: current.resolvedDefinitions, arguments: current.arguments,
        invocationToken: current.invocationToken, lastReceipt: current.lastReceipt))
    do {
      definition = try workbook.applicationDefinition(next.definitionID)
      state = next
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
      while let value = state, dirty {
        let expected = baseline
        let preserve = keepOther
        do {
          let saved = try await Task.detached { [workbook, key] in
            try workbook.saveFormDraft(key, state: value, expected: expected, keepOther: preserve)
          }.value
          baseline = saved
          untouched = nil
          state?.alternatives = saved.alternatives
          state?.invocationToken = saved.invocationToken
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
    conflict = (error as? SevraError)?.code == "form_draft_conflict"
    stale = (error as? SevraError)?.code == "stale_form_definition"
    changed?()
    revealFailure?()
  }
}

/// What a text box holds as a value. An empty optional number or date is no value at all.
public func formFieldValue(_ text: String, parameter: Value) -> Value {
  text.isEmpty && parameter["required"] != .bool(true) && parameter["type"] != .string("text")
    ? .null : .string(text)
}

@MainActor public final class FormDraftScope {
  private struct WeakScope { weak var value: FormDraftScope? }
  private static var scopes: [WeakScope] = []
  private var workbook: Workbook?
  private var sessions: [String: FormDraftSession] = [:]
  public var changed: (() -> Void)?
  public var revealFailure: (() -> Void)?
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
  public func session(_ key: String) -> FormDraftSession? {
    guard let workbook else { return nil }
    if let saved = sessions[key] { return saved }
    let value = FormDraftSession(workbook: workbook, key: key)
    value.changed = { [weak self] in self?.changed?() }
    value.revealFailure = { [weak self] in self?.revealFailure?() }
    sessions[key] = value
    return value
  }
  public func flush() async -> Bool {
    var success = true
    for session in sessions.values { if !(await session.flush()) { success = false } }
    return success
  }
  public static func flushAll() async -> Bool {
    Self.scopes.removeAll { $0.value == nil }
    var success = true
    for scope in Self.scopes.compactMap(\.value) { if !(await scope.flush()) { success = false } }
    return success
  }
}
