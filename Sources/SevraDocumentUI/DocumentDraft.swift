import Combine
import Foundation
import SevraCore

/// The editor owns an exact base version and keeps a failed save in memory.
/// View navigation and native window/application close flush through its scope.
@MainActor public final class DocumentDraft: ObservableObject {
  @Published public private(set) var current: Item
  @Published public private(set) var text: String
  @Published public private(set) var editing = false
  @Published public private(set) var failure: String?
  @Published public private(set) var newerVersionID: String?
  public var changed: (() -> Void)?
  private let workbook: Workbook
  private var scheduled: Task<Void, Never>?
  private var operation: (version: String, text: String, separate: Bool, token: String)?
  private var background: BackgroundSave?
  public var dirty: Bool { text != current.text }
  public var editable: Bool {
    current.category == "record" && current.kind == "document" && current.assetID == nil
  }
  public init(workbook: Workbook, item: Item) {
    self.workbook = workbook
    current = item
    text = item.text
  }
  deinit { scheduled?.cancel() }

  public func refreshHead() async {
    // Source viewers also need an explicit historical-version warning. Inspect
    // bounded metadata rather than decoding the newer document's entire body.
    let version = current.id
    let book = workbook
    let head = await Task.detached(priority: .utility) {
      Self.head(of: version, in: book, cancellation: Cancellation(deadlineAfterSeconds: 3))
    }.value
    guard let head, current.id == version else { return }
    newerVersionID = head == version ? nil : head
  }
  private nonisolated static func head(
    of version: String, in workbook: Workbook, cancellation: Cancellation
  ) -> String? {
    let versions = try? workbook.citationVersions([version], cancellation: cancellation)
    return versions?["versions"].array.first?["current"]["id"].string
  }

  @discardableResult public func begin() -> Bool {
    guard editable else { return false }
    if dirty {
      editing = true
      return true
    }
    do {
      let head = try workbook.item(current.logicalID)
      guard head.id == current.id else {
        newerVersionID = head.id
        failure = "A newer version is available. Open it before editing this document."
        return false
      }
      guard current.status != "rejected" else {
        failure = "This version was withdrawn. Its original text remains available."
        return false
      }
      failure = nil
      newerVersionID = nil
      editing = true
      return true
    } catch {
      failure = error.localizedDescription
      return false
    }
  }
  public func update(_ value: String) {
    guard editing, value != text else { return }
    text = value
    schedule()
  }
  private func schedule() {
    scheduled?.cancel()
    scheduled = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: 600_000_000)
        try Task.checkCancellation()
        self?.saveInBackground()
      } catch {}
    }
  }
  @discardableResult public func end() -> Bool {
    guard flush() else { return false }
    editing = false
    return true
  }
  @discardableResult public func flush() -> Bool { save(separate: false) }
  @discardableResult public func keepSeparate() -> Bool { save(separate: true) }

  /// One save on its way. Its deadline bounds how long `settle` can wait for it.
  private final class BackgroundSave: @unchecked Sendable {
    let finished = DispatchSemaphore(value: 0)
    let text: String
    var result: Result<Item, Error>?
    var head: String?
    init(text: String) { self.text = text }
  }
  private func operationToken(separate: Bool) -> String {
    if operation?.version != current.id || operation?.text != text
      || operation?.separate != separate
    {
      operation = (current.id, text, separate, identifier())
    }
    return operation!.token
  }
  private func accept(_ saved: Item, for savedText: String) {
    current = saved
    // Anything typed since stays, and the next save builds on this version.
    if text == savedText { text = saved.text }
    operation = nil
    failure = nil
    newerVersionID = nil
    changed?()
  }
  private func report(_ error: Error, head: String?) {
    failure = error.localizedDescription
    if let head, head != current.id {
      newerVersionID = head
      failure =
        "A newer version exists. Your text is still here. Keep your changes as a separate draft to preserve both versions."
    }
  }
  /// Typing never waits for a busy workbook. Navigation and closing do, through `save`.
  private func saveInBackground() {
    scheduled = nil
    guard background == nil else {
      schedule()
      return
    }
    guard editable, dirty else { return }
    let token = operationToken(separate: false)
    let job = BackgroundSave(text: text)
    background = job
    let book = workbook
    let version = current.id
    Task.detached(priority: .utility) { [weak self] in
      let control = Cancellation(deadlineAfterSeconds: 3)
      do {
        job.result = .success(
          try book.editDocument(
            version, text: job.text, separate: false, token: token, cancellation: control))
      } catch {
        job.result = .failure(error)
        job.head = Self.head(of: version, in: book, cancellation: control)
      }
      job.finished.signal()
      await self?.settle(job)
    }
  }
  /// The next save has to build on what this one made, so it finishes first.
  private func settle(_ job: BackgroundSave? = nil) {
    guard let running = background, job == nil || job === running else { return }
    running.finished.wait()
    background = nil
    switch running.result {
    case .success(let saved): accept(saved, for: running.text)
    case .failure(let error): report(error, head: running.head)
    case nil: break
    }
  }
  private func save(separate: Bool) -> Bool {
    scheduled?.cancel()
    scheduled = nil
    settle()
    guard editable else { return true }
    guard dirty else {
      failure = nil
      return true
    }
    let token = operationToken(separate: separate)
    // Navigation waits for this save, so a busy workbook cannot hold the window for longer.
    let control = Cancellation(deadlineAfterSeconds: 3)
    let savedText = text
    do {
      let saved = try workbook.editDocument(
        current.id, text: text, separate: separate, token: token, cancellation: control)
      accept(saved, for: savedText)
      return true
    } catch {
      report(error, head: Self.head(of: current.id, in: workbook, cancellation: control))
      return false
    }
  }
}

/// Weak membership cannot prolong a viewer/window's lifetime. The live window
/// keeps its scope; application termination asks every live scope to flush.
@MainActor public final class DocumentDraftScope {
  private struct WeakDraft { weak var value: DocumentDraft? }
  private struct WeakScope { weak var value: DocumentDraftScope? }
  private static var scopes: [WeakScope] = []
  private var drafts: [WeakDraft] = []
  public var revealFailure: (() -> Void)?
  public init() {
    Self.scopes.removeAll { $0.value == nil }
    Self.scopes.append(WeakScope(value: self))
  }
  public func register(_ draft: DocumentDraft) {
    drafts.removeAll { $0.value == nil }
    if !drafts.contains(where: { $0.value === draft }) { drafts.append(WeakDraft(value: draft)) }
  }
  @discardableResult public func flush() -> Bool {
    drafts.removeAll { $0.value == nil }
    var saved = true
    for draft in drafts.compactMap(\.value) { if !draft.flush() { saved = false } }
    if !saved { revealFailure?() }
    return saved
  }
  public static func flushAll() -> Bool {
    scopes.removeAll { $0.value == nil }
    var saved = true
    for scope in scopes.compactMap(\.value) { if !scope.flush() { saved = false } }
    return saved
  }
}
