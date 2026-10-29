import Foundation

/// Deliberate manual execution authority, held only in the invoking process.
/// It is never serialized into a workbook or reconstructed from saved text.
public final class WorkflowExecutionSession: @unchecked Sendable {
  let workbook: Workbook
  public let runID: String
  init(_ workbook: Workbook, runID: String) {
    self.workbook = workbook
    self.runID = runID
  }
}

extension Workbook {
  @discardableResult public func startWorkflow(
    _ definitionID: String, arguments: Value, token: String,
    readOnly: Bool = false, actor: ChangeActor? = nil,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(!readOnly, "read_only_request", "This request does not permit a workflow.")
    try workflowToken(token)
    let actor = actor ?? ChangeAttribution.actor ?? .programmatic("SevraCore.workflow")
    return try mutation(
      "workflow_start", token: token,
      request: .object(["definitionID": .string(definitionID), "arguments": arguments]),
      cancellation: cancellation, actor: actor
    ) {
      let definition = try self.applicationDefinition(definitionID)
      try require(
        definition.id == definitionID && definition.kind == "workflow",
        "workflow_definition", "Start an exact saved workflow version.")
      let descriptor = try DefinitionDescriptor(definition.content)
      try self.validateWorkflowDefinition(descriptor)
      let workflow = try DefinitionWorkflow(descriptor)
      let supplied = try self.definitionArguments(descriptor, arguments)
      let id = identifier()
      var inputs = Set([definition.sourceID])
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
          + " started a manual workflow. Inventory changes remain drafts until reviewed.",
        data: .object([
          "workflowRunID": .string(id), "definitionID": .string(definition.id),
          "arguments": arguments, "normalizedArguments": .object(supplied),
          "policy": .string("manual-drafts-v1"), "actor": try encoded(actor),
        ]),
        meaning: "actual", status: "accepted", scenario: "actual",
        inputs: inputs.sorted(), transformation: "workflow-invocation-v1")
      try self.db.execute(
        "INSERT INTO workflow_runs VALUES(?,?,?,?,?,'manual-drafts-v1','queued','',?,?)",
        [
          .string(id), .string(definition.id), .string(source), .string(try encoded(actor).json()),
          .string(try Value.object(supplied).json()), .string(timestamp()), .string(timestamp()),
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
  }

  /// Calling this is a new explicit manual resume decision. No open/import path
  /// calls it, and a session cannot be reused for another connection or copy.
  public func authorizeWorkflowExecution(_ runID: String) throws -> WorkflowExecutionSession {
    let run = try workflowRun(runID)
    try require(
      run["policy"] == .string("manual-drafts-v1"), "workflow_authority",
      "Unsupported workflow authority.")
    return WorkflowExecutionSession(self, runID: runID)
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

  func workflowSession(_ session: WorkflowExecutionSession) throws {
    try require(
      session.workbook === self, "workflow_authority",
      "Explicitly authorize this open workbook before resuming.")
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
