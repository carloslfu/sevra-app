import Foundation

extension Workbook {
  /// Submission identity and incomplete inputs are owned by the saved form draft.
  /// Creating a workflow run does not authorize a background worker.
  public func submitFormDraft(
    _ state: FormDraftState, preview: Value, readOnly: Bool = false,
    actor: ChangeActor? = nil, cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(!readOnly, "read_only_request", "This request does not permit form submission.")
    try synchronized { try validateFormDraft(state) }
    let definition = try applicationDefinition(state.definitionID)
    let form = try DefinitionForm(DefinitionDescriptor(definition.content))
    let actual = actor ?? ChangeAttribution.actor ?? .programmatic("SevraCore.form")
    if form.targetKind == "action" {
      return try invokeApplicationAction(
        definition.id, arguments: state.arguments, preview: preview,
        token: state.invocationToken, actor: actual, cancellation: cancellation)
    }
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    let receipt = try mutation(
      "submit_workflow_form", token: state.invocationToken,
      request: .object([
        "id": .string(state.definitionID), "arguments": state.arguments, "preview": preview,
        "openedBindings": .array(state.resolvedDefinitions.map(Value.string)),
      ]), cancellation: control, actor: actual
    ) {
      let plan = try self.previewFormDraft(state, cancellation: control)
      try require(
        plan == preview, "stale_workflow_preview",
        "The workflow form changed. Your inputs are retained; preview it again.")
      let run = try self.insertWorkflowRun(
        plan["workflowID"].text, arguments: state.arguments, actor: actual,
        additionalInputs: [definition.sourceID],
        origin: .object(["formID": .string(definition.id), "plan": plan]))
      WorkflowPublicationProbe.observer?(.prepared, run["id"].text)
      return .object([
        "kind": .string("workflow"), "workbookID": .string(self.id),
        "definitionID": .string(definition.id), "workflowDefinitionID": plan["workflowID"],
        "workflowRunID": run["id"], "sourceID": run["source_id"], "state": .string("queued"),
        "acceptedBalanceChanged": .bool(false),
      ])
    }
    WorkflowPublicationProbe.observer?(.committed, receipt["workflowRunID"].text)
    return receipt
  }

  /// Definition and parameter validation only. Steps can still fail against the
  /// latest data when the user explicitly continues the saved run.
  func workflowFormPlan(_ formID: String, arguments: Value, cancellation: Cancellation) throws
    -> Value
  {
    let definition = try applicationDefinition(formID)
    try require(definition.kind == "form", "definition_kind", "Preview a workflow form.")
    let descriptor = try DefinitionDescriptor(definition.content)
    let form = try DefinitionForm(descriptor)
    try require(form.targetKind == "workflow", "definition_kind", "This form targets an action.")
    let target = try resolveDefinition(form.binding)
    try validateForm(form, descriptor: descriptor, action: target)
    let state = DefinitionEvaluation(cancellation)
    try validateDefinitionGraph(definition, state: state, depth: 0)
    let supplied = try definitionArguments(descriptor, arguments)
    let workflow = try DefinitionWorkflow(DefinitionDescriptor(target.content))
    var steps: [Value] = []
    for step in workflow.steps {
      try cancellation.check()
      let title =
        try step.binding.map { try applicationDefinition($0.target).title }
        ?? "Review proposals"
      steps.append(
        .object(["id": .string(step.id), "kind": .string(step.kind), "title": .string(title)]))
    }
    var plan: [String: Value] = [
      "kind": .string("workflow"), "workbookID": .string(id),
      "definitionID": .string(definition.id), "workflowID": .string(target.id),
      "title": .string(definition.title), "arguments": .object(supplied),
      "submittedArguments": arguments,
      "resolvedDefinitions": .array(state.resolved.keys.sorted().map(Value.string)),
      "steps": .array(steps), "readPolicy": .string("latest-at-step"), "readOnly": .bool(true),
      "effect": .string(
        "Start a manual workflow with \(steps.count) steps. It may create draft proposals; acceptance remains separate. This preview checks definitions and inputs only. Each step reads current data and may require attention."
      ),
    ]
    plan["fingerprint"] = .string(ChangeFormat.hash(try Value.object(plan).json()))
    return .object(plan)
  }
}
