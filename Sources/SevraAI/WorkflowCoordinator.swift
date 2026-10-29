import Foundation
import SevraCore

/// An explicit foreground continuation. No scheduler, persisted activation or
/// reconstruction path calls this coordinator.
package enum WorkflowCoordinator {
  package static func run(
    workbook: Workbook, session: WorkflowExecutionSession, owner: String,
    directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void,
    model: () async throws -> any WorkbookInference
  ) async throws -> Value {
    var run = try workbook.workflowRun(session.runID)
    for _ in 0..<16 {
      try cancellation.check()
      if ["completed", "cancelled", "needs_attention"].contains(run["state"].text) { return run }
      guard let next = run["steps"].array.first(where: { $0["state"] != .string("completed") })
      else {
        throw SevraError("workflow_integrity", "The active workflow has no unfinished step.")
      }
      if next["kind"] == .string("extract") {
        run = try await claimed(
          workbook: workbook, session: session, owner: owner, cancellation: cancellation
        ) { claim, control in
          progress("Preparing the included document…")
          return try await Task.detached {
            let worker = ExtractionWorker()
            let request = try workbook.prepareWorkflowExtraction(
              session, claim: claim, worker: worker.workflowIdentity(cancellation: control),
              cancellation: control)
            let result = try workbook.performWorkflowExtraction(
              session, claim: claim, request: request, worker: worker, cancellation: control)
            return try workbook.completeWorkflowStep(
              session, claim: claim, extraction: result, cancellation: control)
          }.value
        }
      } else if next["kind"] == .string("intake") {
        run = try await claimed(
          workbook: workbook, session: session, owner: owner, cancellation: cancellation
        ) { claim, control in
          progress("Preparing the mapped table update for review…")
          return try await Task.detached {
            let worker = ExtractionWorker()
            let request = try workbook.prepareWorkflowIntake(
              session, claim: claim, worker: worker.workflowIdentity(cancellation: control),
              cancellation: control)
            let result = try workbook.performWorkflowIntake(
              session, claim: claim, request: request, worker: worker, cancellation: control)
            return try workbook.completeWorkflowStep(
              session, claim: claim, intake: result, cancellation: control)
          }.value
        }
      } else if next["kind"] == .string("interpret") {
        let inference = try await model()
        try await inference.beginRun()
        do {
          run = try await interpret(
            workbook: workbook, session: session, owner: owner, model: inference,
            directory: directory, cancellation: cancellation, progress: progress)
          await inference.endRun()
        } catch {
          await inference.endRun()
          throw error
        }
      } else {
        run = try await Task.detached {
          try workbook.advanceWorkflow(session, owner: owner, cancellation: cancellation)
        }.value
      }
      if run["state"] == .string("waiting_review") { return run }
    }
    return run
  }

  private static func interpret(
    workbook: Workbook, session: WorkflowExecutionSession, owner: String,
    model: any WorkbookInference, directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void
  ) async throws -> Value {
    try await claimed(
      workbook: workbook, session: session, owner: owner, cancellation: cancellation
    ) { claim, control in
      let identity = await model.identity
      let request = try await Task.detached {
        try workbook.prepareWorkflowInterpretation(
          session, claim: claim, model: identity, cancellation: control)
      }.value
      let result = try await model.interpret(
        request: request, directory: directory, cancellation: control, progress: progress)
      try control.check()
      return try await Task.detached {
        try workbook.retainWorkflowInterpretationResponse(
          session, claim: claim, response: result, cancellation: control)
        return try workbook.completeWorkflowStep(
          session, claim: claim, interpretation: result, cancellation: control)
      }.value
    }
  }

  private static func claimed(
    workbook: Workbook, session: WorkflowExecutionSession, owner: String,
    cancellation: Cancellation, operation: (Value, Cancellation) async throws -> Value
  ) async throws -> Value {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 180)
    let claim = try await Task.detached {
      try workbook.claimWorkflowStep(session, owner: owner, cancellation: control)
    }.value
    if claim == .null { return try workbook.workflowRun(session.runID) }
    let heartbeat = Task.detached {
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: 5_000_000_000)
          try control.check()
          _ = try workbook.heartbeatWorkflowStep(session, claim: claim)
        } catch {
          if !Task.isCancelled {
            control.cancel(
              reason:
                "The workflow lost its worker lease. Completed work is preserved; inspect Activity before continuing."
            )
          }
          return
        }
      }
    }
    defer { heartbeat.cancel() }
    do {
      return try await operation(claim, control)
    } catch {
      _ = try? await Task.detached {
        try workbook.failWorkflowStep(
          session, claim: claim, detail: String(error.localizedDescription.prefix(1000)))
      }.value
      throw error
    }
  }
}
