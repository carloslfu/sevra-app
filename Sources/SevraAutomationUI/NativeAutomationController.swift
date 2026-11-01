import Combine
import Foundation
import SevraCore

/// One native app owner. Tests inject a deterministic runner; production supplies
/// the same ProductAI workflow coordinator used by explicit manual Continue.
@MainActor public final class NativeAutomationController: ObservableObject {
  public typealias Runner =
    @Sendable (
      Workbook, WorkflowExecutionSession, Cancellation
    ) async throws -> Value
  public let registry: AutomationDeviceRegistry
  @Published public private(set) var grants: [AutomationDeviceGrant] = []
  @Published public private(set) var statuses: [String: String] = [:]
  @Published public private(set) var failure: String?
  /// Other schedules keep running while this shows. `failure` stops all of them.
  @Published public private(set) var notice: String?
  @Published public private(set) var runningID: String?
  @Published public private(set) var gate = "Waiting for Sevra to become active."
  private let runner: Runner
  private var task: Task<Void, Never>?
  private var cancellation: Cancellation?
  private var cursor = 0
  private var nextChecks: [String: Date] = [:]
  private var seenRevisions: [String: Int] = [:]
  public init(registry: AutomationDeviceRegistry, runner: @escaping Runner) {
    self.registry = registry
    self.runner = runner
  }

  public func reload() async {
    do {
      let registry = registry
      let inventory = try await Task.detached { try registry.inventory() }.value
      grants = inventory.grants
      notice =
        inventory.unreadable == 0
        ? nil
        : "A saved schedule on this Mac could not be read and will not run. Open it and enable it again."
      failure = nil
      let ids = Set(grants.map(\.id))
      nextChecks = nextChecks.filter { ids.contains($0.key) }
      statuses = statuses.filter { ids.contains($0.key) }
    } catch { failure = error.localizedDescription }
  }

  public func deferWork(_ reason: String) {
    gate = reason
    cancellation?.cancel(reason: reason)
  }

  /// Caller provides current OS/UI eligibility each tick. No retained true state
  /// survives an app restart or loss of focus. Cancellation also fences publication.
  public func poll(now: Date = Date(), deferral: String? = nil) {
    if let deferral {
      deferWork(deferral)
      return
    }
    gate = "Runs while Sevra is active. Business changes require review."
    guard task == nil else { return }
    let control = Cancellation(deadlineAfterSeconds: 240)
    cancellation = control
    let registry = registry
    task = Task {
      defer {
        task = nil
        cancellation = nil
        runningID = nil
      }
      await reload()
      guard !grants.isEmpty, !control.isCancelled, failure == nil else { return }
      for _ in 0..<grants.count {
        let grant = grants[cursor % grants.count]
        cursor = (cursor + 1) % grants.count
        guard (nextChecks[grant.id] ?? .distantPast) <= now else { continue }
        runningID = grant.id
        do {
          let previousRevision = seenRevisions[grant.id]
          let result = try await Task.detached(priority: .utility) {
            try Self.prepare(
              registry, grant: grant, now: now,
              previousRevision: previousRevision, cancellation: control)
          }.value
          try control.check()
          nextChecks[grant.id] = result.nextCheck
          statuses[grant.id] = result.detail
          if let runID = result.runID {
            let book = result.book
            let session = try await Task.detached {
              try book.authorizeAutomationWorkflowExecution(result.session, runID: runID)
            }.value
            let run = try await runner(book, session, control)
            try control.check()
            statuses[grant.id] = Self.stateTitle(run["state"].text)
            seenRevisions[grant.id] = try await Task.detached { try book.revision() }.value
          }
        } catch {
          statuses[grant.id] =
            control.isCancelled
            ? "Deferred. Completed work is preserved."
            : error.localizedDescription
          // Busy leases and inaccessible files retry at a bounded rate, without
          // reviving a generation or consuming another occurrence.
          nextChecks[grant.id] = now.addingTimeInterval(30)
        }
        break
      }
    }
  }

  /// Quiescence is required before changing this owner's grant. Cancellation is
  /// cooperative, while live core fences prevent late automatic publication.
  public func quiesce(_ reason: String) async {
    deferWork(reason)
    await task?.value
  }
  package func waitForCurrentPoll() async { await task?.value }

  public func enable(
    _ book: Workbook, exactID: String, expectedGeneration: Int, allowAI: Bool,
    now: Date = Date(), token: String = identifier(), fromNow: Bool = false
  ) async throws {
    await quiesce("Updating device permission.")
    let registry = registry
    let grant = try await Task.detached {
      let definition = try book.applicationDefinition(exactID)
      let session: AutomationExecutionSession
      if definition.payload["policy"] == .string("inventory-condition-drafts-v1") {
        session = try book.authorizeInventoryConditionExecution(
          exactID, expectedGeneration: expectedGeneration, after: now, allowAI: allowAI,
          fromNow: fromNow, token: token, actor: .human("Sevra.native-condition-enable"))
      } else {
        try require(
          !fromNow, "automation_trigger",
          "From-now queue replacement applies to inventory conditions.")
        session = try book.authorizeAutomationExecution(
          exactID, expectedGeneration: expectedGeneration, after: now, allowAI: allowAI,
          token: token, actor: .human("Sevra.native-schedule-enable"))
      }
      return try registry.register(book, session: session)
    }.value
    nextChecks[grant.id] = nil
    seenRevisions[grant.id] = nil
    await reload()
    statuses[grant.id] = "Enabled on this Mac."
  }

  public func pause(_ grant: AutomationDeviceGrant) async throws {
    // Remove first so another process and any old live capability are fenced.
    let registry = registry
    let removed = try await Task.detached { try registry.remove(grant) }.value
    try require(removed, "stale_automation", "Device permission changed. Refresh before pausing.")
    await quiesce("Pausing schedule.")
    await reload()
    do {
      try await Task.detached {
        let book = try Workbook(registry.resolvedURL(grant))
        let state = try book.automationActivation(grant.activationID)
        guard
          state["source_id"] == .string(grant.sourceID)
            && state["generation"].int == grant.generation
        else { return }
        _ = try book.pauseAutomation(
          grant.activationID, expectedGeneration: grant.generation,
          token: identifier(), actor: .human("Sevra.native-schedule-pause"))
      }.value
    } catch {
      throw SevraError(
        "automation_pause",
        "Scheduling is disabled on this Mac, but its workbook pause could not be recorded. "
          + error.localizedDescription)
    }
  }

  private struct Preparation: Sendable {
    let book: Workbook
    let session: AutomationExecutionSession
    let runID: String?
    let nextCheck: Date
    let detail: String
  }
  nonisolated private static func prepare(
    _ registry: AutomationDeviceRegistry, grant: AutomationDeviceGrant, now: Date,
    previousRevision: Int?, cancellation: Cancellation
  ) throws -> Preparation {
    let (book, session) = try registry.restore(grant, cancellation: cancellation)
    let state = try book.automationActivation(grant.activationID)
    func result(_ runID: String? = nil, _ detail: String, next: Date? = nil) -> Preparation {
      Preparation(
        book: book, session: session, runID: runID,
        nextCheck: next ?? now.addingTimeInterval(10), detail: detail)
    }
    if let runID = state["active_run_id"].string {
      let run = try book.workflowRun(runID)
      if !["completed", "cancelled"].contains(run["state"].text) {
        if run["state"] == .string("needs_attention") {
          return result(nil, "Needs attention. Open the saved run.")
        }
        if run["state"] == .string("waiting_review"), previousRevision == (try book.revision()) {
          return result(nil, "Waiting for review.")
        }
        return result(runID, "Continuing saved work.")
      }
    }
    let definition = try book.applicationDefinition(grant.definitionID)
    if definition.payload["policy"] == .string("inventory-condition-drafts-v1") {
      var probe = try book.deviceConditionWork(session, through: now, cancellation: cancellation)
      if probe["horizonAhead"] == .bool(true) {
        return result(
          nil, "Waiting for the retained observation time.", next: now.addingTimeInterval(60))
      }
      if probe["needsStep"] == .bool(true) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        _ = try book.stepAutomationCondition(
          session, through: formatter.string(from: now),
          token: identifier(), cancellation: cancellation)
        probe = try book.deviceConditionWork(session, through: now, cancellation: cancellation)
      }
      if (probe["pendingCandidates"].int ?? 0) > 0 {
        let dispatch = try book.dispatchInventoryCondition(
          session, observedAt: now,
          token: identifier(), cancellation: cancellation)
        return result(
          dispatch["runID"].string ?? dispatch["run"]["id"].string,
          "\(probe["pendingCandidates"].int ?? 0) transitions waiting.")
      }
      return result(
        nil,
        probe["needsStep"] == .bool(true)
          ? "Catching up on stock changes." : "Watching stock changes.",
        next: probe["needsStep"] == .bool(true) ? now : nil)
    }
    let schedule = try NativeCalendarSchedule(definition.payload["schedule"])
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let pending = try book.deviceAutomationPending(session)
    if let instant = pending["due"].string.flatMap(formatter.date(from:)), instant > now {
      return result(
        nil, "Deferred until the saved request is due.",
        next: min(instant, now.addingTimeInterval(60)))
    }
    guard let cursor = formatter.date(from: state["cursor"].text) else {
      throw SevraError("automation_time", "The saved schedule cursor is invalid.")
    }
    let next = try schedule.preview(after: cursor, count: 1, cancellation: cancellation)
    let due = next["occurrences"].array.first?["due"].string.flatMap(formatter.date(from:))
    let covered = state["catch_up_remaining"].int == 0 && due.map { $0 > now } == true
    if covered, pending == .null, let due {
      return result(
        nil, "Next: " + due.formatted(date: .abbreviated, time: .shortened),
        next: min(due, now.addingTimeInterval(60)))
    }
    // A failed dispatch retries every 30 seconds, and each plan saves a Source. With no new slot
    // there is nothing to plan, and dispatch applies the same 24-hour limit to the pending one.
    if !covered {
      let planned = try book.planAutomationOccurrences(
        session.planning, through: now,
        token: identifier(), cancellation: cancellation)
      guard planned["catchUpRemaining"] == .bool(false) else {
        return result(nil, "Catching up on missed times.", next: now)
      }
    }
    let dispatch = try book.dispatchAutomationOccurrence(
      session, observedAt: now,
      token: identifier(), cancellation: cancellation)
    return result(
      dispatch["runID"].string ?? dispatch["run"]["id"].string,
      dispatch["status"] == .string("late")
        ? "Skipped a request older than 24 hours." : "Schedule checked.")
  }

  nonisolated private static func stateTitle(_ state: String) -> String {
    switch state {
    case "waiting_review": return "Waiting for review."
    case "needs_attention": return "Needs attention. Open the saved run."
    case "completed": return "Completed."
    case "cancelled": return "Stopped."
    default: return "Saved work is ready to continue."
    }
  }
}
