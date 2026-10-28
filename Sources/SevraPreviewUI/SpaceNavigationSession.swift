import Foundation
import SevraCore

/// Small serialized presentation writes. Only committed preferences are shown;
/// failed saves never masquerade as a persisted pin. Navigation itself stays immediate.
@MainActor public final class SpaceNavigationSession {
  private struct WeakSession { weak var value: SpaceNavigationSession? }
  private static var sessions: [WeakSession] = []
  private var workbook: Workbook?
  private var pending: [SpaceNavigationEdit] = []
  private var saving: Task<Void, Never>?
  public private(set) var state = SpaceNavigationState()
  public private(set) var generation = 0
  public var isSaving: Bool { saving != nil || !pending.isEmpty }
  public var changed: (() -> Void)?
  public var failed: ((String) -> Void)?

  public init() {
    Self.sessions.removeAll { $0.value == nil }
    Self.sessions.append(.init(value: self))
  }
  public func open(_ workbook: Workbook) async {
    await flush()
    self.workbook = workbook
    state = SpaceNavigationState()
    generation += 1
    changed?()
  }
  public func receive(_ value: SpaceNavigationState, generation expected: Int) {
    guard generation == expected, !isSaving else { return }
    state = value
    changed?()
  }
  public func visit(_ id: String) {
    guard id != "home", workbook != nil else { return }
    pending.removeAll { $0 == .visit(id) }
    pending.append(.visit(id))
    // Only the last eight distinct pending visits affect the saved recent list.
    var count = 0
    pending = pending.reversed().filter { edit in
      if case .visit = edit {
        count += 1
        return count <= 8
      }
      return true
    }.reversed()
    schedule()
  }
  public func pin(_ id: String, selected: Bool) {
    guard id != "home", workbook != nil, !isSaving else { return }
    pending.append(.pin(id, selected))
    schedule()
  }
  private func schedule() {
    generation += 1
    changed?()
    Task { await flush() }
  }
  public func flush() async {
    if let saving {
      await saving.value
      return
    }
    guard !pending.isEmpty, let workbook else { return }
    let task = Task { [self] in
      defer {
        saving = nil
        changed?()
      }
      while !pending.isEmpty {
        let batch = pending
        pending = []
        do {
          let result = try await Task.detached(priority: .userInitiated) {
            try workbook.updateSpaceNavigation(batch)
          }.value
          state = result
          generation += 1
          changed?()
        } catch {
          failed?("Could not save space navigation: " + error.localizedDescription)
        }
      }
    }
    saving = task
    await task.value
  }
  public static func flushAll() async {
    sessions.removeAll { $0.value == nil }
    for session in sessions.compactMap(\.value) { await session.flush() }
  }
}
