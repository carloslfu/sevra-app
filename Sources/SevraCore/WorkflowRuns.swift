import Foundation

/// Deliberate manual or scoped automation authority, held only in this process.
/// It is never serialized into a workbook or reconstructed from saved text.
public final class WorkflowExecutionSession: @unchecked Sendable {
  let workbook: Workbook
  public let runID: String
  let automation: AutomationExecutionSession?
  let manualSourceID: String?
  init(
    _ workbook: Workbook, runID: String, automation: AutomationExecutionSession? = nil,
    manualSourceID: String? = nil
  ) {
    self.workbook = workbook
    self.runID = runID
    self.automation = automation
    self.manualSourceID = manualSourceID
  }
}

extension Workbook {
  @discardableResult public func startWorkflow(
    _ definitionID: String, arguments: Value, token: String,
    readOnly: Bool = false, actor: ChangeActor? = nil,
    requestRunID: String? = nil, requestSourceID: String? = nil,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(!readOnly, "read_only_request", "This request does not permit a workflow.")
    try workflowToken(token)
    let actor = actor ?? ChangeAttribution.actor ?? .programmatic("SevraCore.workflow")
    return try mutation(
      "workflow_start", token: token,
      request: .object([
        "definitionID": .string(definitionID), "arguments": arguments,
        "requestRunID": requestRunID.map(Value.string) ?? .null,
        "requestSourceID": requestSourceID.map(Value.string) ?? .null,
      ]),
      cancellation: cancellation, actor: actor
    ) {
      if let requestRunID {
        try self.validateApplicationToolRun(requestRunID, requestSourceID: requestSourceID)
      } else {
        try require(requestSourceID == nil, "action_run", "A request Source needs its active run.")
      }
      return try self.insertWorkflowRun(
        definitionID, arguments: arguments, actor: actor,
        additionalInputs: requestSourceID.map { [$0] } ?? [])
    }
  }

  /// Trusted in-transaction body shared by direct starts and form submission.
  func insertWorkflowRun(
    _ definitionID: String, arguments: Value, actor: ChangeActor,
    additionalInputs: [String] = [], origin: Value = .null,
    policy: String = "manual-drafts-v1", runID: String = identifier()
  ) throws -> Value {
    let definition = try self.applicationDefinition(definitionID)
    try require(
      definition.id == definitionID && definition.kind == "workflow",
      "workflow_definition", "Start an exact saved workflow version.")
    let descriptor = try DefinitionDescriptor(definition.content)
    try self.validateWorkflowDefinition(descriptor)
    let workflow = try DefinitionWorkflow(descriptor)
    let supplied = try self.definitionArguments(descriptor, arguments)
    try require(
      ["manual-drafts-v1", "automation-drafts-v1"].contains(policy), "workflow_authority",
      "Unknown workflow policy.")
    let id = runID
    var inputs = Set([definition.sourceID] + additionalInputs)
    func captureItems(_ parameters: [DefinitionParameter], _ arguments: Value) {
      for parameter in parameters {
        let value = arguments[parameter.id]
        if parameter.type == "item", let id = value.string { inputs.insert(id) }
        if parameter.type == "entries" {
          for row in value.array { captureItems(parameter.fields, row) }
        }
      }
    }
    captureItems(descriptor.parameters, .object(supplied))
    let source = try self.insertItem(
      category: "source", kind: "application_invocation",
      title: "Start " + definition.title,
      text: actor.label
        + (policy == "automation-drafts-v1"
          ? " started an authorized scheduled workflow. Business changes remain drafts until reviewed."
          : " started a manual workflow. Business changes remain drafts until reviewed."),
      data: .object([
        "workflowRunID": .string(id), "definitionID": .string(definition.id),
        "arguments": arguments, "normalizedArguments": .object(supplied),
        "policy": .string(policy), "actor": try encoded(actor), "origin": origin,
      ]),
      meaning: "actual", status: "accepted", scenario: "actual",
      inputs: inputs.sorted(), transformation: "workflow-invocation-v1")
    try self.db.execute(
      "INSERT INTO workflow_runs VALUES(?,?,?,?,?,?,'queued','',?,?)",
      [
        .string(id), .string(definition.id), .string(source), .string(try encoded(actor).json()),
        .string(try Value.object(supplied).json()), .string(policy), .string(timestamp()),
        .string(timestamp()),
      ])
    for (index, step) in workflow.steps.enumerated() {
      try self.db.execute(
        "INSERT INTO workflow_steps VALUES(?,?,?,?,'pending','null','',?,0)",
        [
          .string(id), .string(step.id), .number(Double(index)), .string(step.kind),
          .string(timestamp()),
        ])
    }
    try self.workflowEvent(
      id, stepID: nil, kind: "started", payload: .object(["sourceID": .string(source)]))
    return try self.workflowRun(id)
  }

  /// Calling this is a new explicit manual resume decision. No open/import path
  /// calls it, and a session cannot be reused for another connection or copy.
  public func authorizeWorkflowExecution(
    _ runID: String, token: String = identifier(),
    actor: ChangeActor = .programmatic("SevraCore.manualWorkflowOperation")
  ) throws -> WorkflowExecutionSession {
    let run = try workflowRun(runID)
    if run["policy"] == .string("manual-drafts-v1") {
      return WorkflowExecutionSession(self, runID: runID)
    }
    try require(
      run["policy"] == .string("automation-drafts-v1"), "workflow_authority",
      "Unsupported workflow authority.")
    try workflowToken(token)
    let result = try mutation(
      "workflow_manual_authorize", token: token,
      request: .string(runID), cancellation: .init(), actor: actor
    ) {
      let run = try self.workflowRun(runID)
      let source = try self.insertItem(
        category: "source", kind: "workflow_authorization", title: "Manual scheduled-run operation",
        text: actor.label
          + " explicitly requested a manual operation on this scheduled run. Future schedules are not enabled.",
        data: .object([
          "runID": .string(runID), "policy": .string("manual-operation-v1"),
          "actor": try encoded(actor),
        ]),
        meaning: "actual", status: "accepted", scenario: "actual", inputs: [run["source_id"].text],
        transformation: "workflow-manual-authorization-v1")
      try self.workflowEvent(
        runID, stepID: nil, kind: "manual_authorized",
        payload: .object(["sourceID": .string(source)]))
      return .string(source)
    }
    return WorkflowExecutionSession(self, runID: runID, manualSourceID: result.text)
  }

  public func validateWorkflowExecution(_ session: WorkflowExecutionSession, forAI: Bool = false)
    throws
  {
    try synchronized { try db.readTransaction { try workflowSession(session, needsAI: forAI) } }
  }

  public func workflowRun(_ runID: String) throws -> Value {
    try synchronized {
      try db.readTransaction {
        guard
          var row = try db.execute("SELECT * FROM workflow_runs WHERE id=?", [.string(runID)]).first
        else {
          throw SevraError("workflow_not_found", "The workflow run was not found.")
        }
        for key in ["arguments", "actor"] { row[key] = try Value.parse(row[key]!.text) }
        row["steps"] = .array(
          try db.execute(
            "SELECT * FROM workflow_steps WHERE run_id=? ORDER BY ordinal LIMIT 16",
            [.string(runID)]
          ).map { step in
            var value = step
            value["output"] = try Value.parse(step["output"]!.text)
            return .object(value)
          })
        return .object(row)
      }
    }
  }

  public func workflowRuns(state: String? = nil, limit: Int = 20) throws -> [Value] {
    try require(
      (1...50).contains(limit)
        && (state == nil
          || ["queued", "running", "waiting_review", "needs_attention", "completed", "cancelled"]
            .contains(state!)),
      "workflow_limit", "Use a known run state and a limit from 1 to 50.")
    return try synchronized {
      try db.execute(
        "SELECT id,definition_id,state,detail,created,updated FROM workflow_runs"
          + (state == nil ? "" : " WHERE state=?") + " ORDER BY updated,id LIMIT ?",
        (state.map { [.string($0)] } ?? []) + [.number(Double(limit))]
      ).map(Value.object)
    }
  }

  public func workflowEvents(after: Int = 0, limit: Int = 20) throws -> Value {
    try require(
      after >= 0 && (1...50).contains(limit), "workflow_limit",
      "Use a nonnegative cursor and 1 to 50 events.")
    return try synchronized {
      let rows = try db.execute(
        "SELECT * FROM workflow_outbox WHERE sequence>? ORDER BY sequence LIMIT ?",
        [.number(Double(after)), .number(Double(limit + 1))])
      let page = Array(rows.prefix(limit))
      return .object([
        "events": .array(
          try page.map { row in
            var value = row
            value["payload"] = try Value.parse(row["payload"]!.text)
            return .object(value)
          }), "after": page.last?["sequence"] ?? .number(Double(after)),
        "hasMore": .bool(rows.count > limit),
      ])
    }
  }

  func workflowSession(_ session: WorkflowExecutionSession, needsAI: Bool = false) throws {
    try synchronized {
      try db.readTransaction {
        try require(
          session.workbook === self, "workflow_authority",
          "Explicitly authorize this open workbook before resuming.")
        let policy = try db.scalar(
          "SELECT policy FROM workflow_runs WHERE id=?", [.string(session.runID)]
        ).text
        if let automation = session.automation {
          try require(
            policy == "automation-drafts-v1", "workflow_authority",
            "The run has no scheduled execution scope.")
          try validateAutomationWorkflow(automation, runID: session.runID)
          try require(
            !needsAI || automation.allowAI, "automation_ai_scope",
            "This automation does not permit local AI.")
        } else if let sourceID = session.manualSourceID {
          let source = try item(sourceID)
          try require(
            source.kind == "workflow_authorization" && source.category == "source"
              && source.data["runID"] == .string(session.runID)
              && source.data["policy"] == .string("manual-operation-v1"),
            "workflow_authority", "The manual operation lost its exact authorization Source.")
        } else {
          try require(
            policy == "manual-drafts-v1", "workflow_authority",
            "A saved scheduled run grants no execution authority.")
        }
      }
    }
  }

  func workflowToken(_ token: String) throws {
    try require(
      !token.isEmpty && token.utf8.count <= 256, "workflow_token",
      "Use a nonempty token up to 256 bytes.")
  }
  func workflowEvent(_ runID: String, stepID: String?, kind: String, payload: Value) throws {
    try db.execute(
      "INSERT INTO workflow_outbox(event_id,run_id,step_id,kind,payload,created) VALUES(?,?,?,?,?,?)",
      [
        .string(identifier()), .string(runID), stepID.map(Value.string) ?? .null, .string(kind),
        .string(try payload.json()), .string(timestamp()),
      ])
  }
}
