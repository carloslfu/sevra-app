import Foundation

extension Workbook {
  /// A preview grants no authority and publishes no mutation, receipt or Source.
  public func previewApplicationAction(
    _ id: String, arguments: Value, cancellation: Cancellation = .init()
  ) throws -> Value {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction {
          try self.applicationActionPlan(id, arguments: arguments, cancellation: control)
        }
      }
    }
  }

  @discardableResult public func invokeApplicationAction(
    _ id: String, arguments: Value, preview: Value, token: String,
    requestSourceID: String? = nil, readOnly: Bool = false, actor: ChangeActor? = nil,
    requestRunID: String? = nil, cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(!readOnly, "read_only_request", "This request does not permit changes.")
    try require(
      !token.isEmpty && token.utf8.count <= 256, "action_token",
      "Use a bounded nonempty retry token.")
    let actual = actor ?? ChangeAttribution.actor ?? .programmatic("SevraCore.applicationAction")
    let request: Value = .object([
      "id": .string(id), "arguments": arguments, "preview": preview,
      "requestSourceID": requestSourceID.map(Value.string) ?? .null,
      "requestRunID": requestRunID.map(Value.string) ?? .null,
    ])
    try require(
      try request.json().utf8.count <= 256_000, "action_limit", "Action request exceeds 256 KB.")
    if preview["primitive"]["id"] == .string(ActionRegistry.toolID) {
      return try invokeToolAction(
        id, arguments: arguments, preview: preview, token: token, request: request,
        requestSourceID: requestSourceID, actor: actual, requestRunID: requestRunID,
        cancellation: cancellation)
    }
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try mutation(
      "invoke_application_action", token: token, request: request, cancellation: control,
      actor: actual
    ) {
      if let requestRunID {
        try validateApplicationToolRun(requestRunID, requestSourceID: requestSourceID)
      }
      let plan = try self.applicationActionPlan(id, arguments: arguments, cancellation: control)
      try require(
        plan == preview, "stale_action_preview",
        "The action or its inputs changed. Keep your draft and preview it again.")
      return try self.insertApplicationAction(
        plan: plan, request: request, actor: actual, requestSourceID: requestSourceID,
        cancellation: control)
    }
  }

  /// Called only inside the owning core mutation. A workflow commits this same
  /// registered effect body and its step checkpoint in one captured transaction.
  func insertApplicationAction(
    plan: Value, request: Value, actor actual: ChangeActor, requestSourceID: String? = nil,
    additionalInputs: [String] = [], controlInputs: [String] = [], producerInputs: [String] = [],
    cancellation: Cancellation
  ) throws -> Value {
    if let requestSourceID {
      let source = try self.item(requestSourceID)
      try require(
        source.id == requestSourceID && source.category == "source" && source.kind == "request",
        "action_request", "Use the captured current request Source.")
    }
    let definitionInputs = plan["resolvedDefinitions"].array.map { $0["sourceID"].text }
    let invocation = try self.insertItem(
      category: "source", kind: "application_invocation",
      title: "Submitted " + plan["title"].text,
      text: actual.label + " submitted draft proposals. Acceptance remains separate.",
      data: .object([
        "submitted": request, "plan": plan, "actor": try encoded(actual),
        "producerPolicy": .string("application-action-v1"),
      ]),
      meaning: "actual", status: "accepted", scenario: "actual",
      inputs: Array(
        Set(
          additionalInputs + [plan["primitiveArguments"]["evidence"].text]
            + (requestSourceID.map { [$0] } ?? []))
      ).sorted(),
      transformation: "application-action-invocation-v1",
      controlInputs: definitionInputs + controlInputs,
      producerInputs: producerInputs)
    var proposals: [Value] = []
    for document in plan["documents"].array {
      try cancellation.check()
      let proposal = try self.insertItem(
        category: "record", kind: "document", title: document["title"].text,
        text: document["body"].text,
        data: .object([
          "origin": .string("application-prose-v1"), "definitionID": plan["definitionID"],
          "invocationSourceID": .string(invocation),
        ]),
        meaning: document["meaning"].text, status: "draft", scenario: document["scenario"].text,
        inputs: Array(Set([document["evidence"].text] + additionalInputs)).sorted(),
        transformation: "application-document-v1", controlInputs: controlInputs,
        producerInputs: [invocation] + producerInputs)
      proposals.append(.string(proposal))
    }
    return .object([
      "workbookID": .string(self.id), "definitionID": plan["definitionID"],
      "sourceID": .string(invocation), "proposals": .array(proposals),
      "state": .string("draft"),
      "resolvedDefinitions": plan["resolvedDefinitions"], "fingerprint": plan["fingerprint"],
    ])
  }

  func applicationActionPlan(_ id: String, arguments: Value, cancellation: Cancellation) throws
    -> Value
  {
    let root = try applicationDefinition(id)
    let descriptor = try DefinitionDescriptor(root.content)
    try require(
      ["action", "form"].contains(root.kind), "definition_kind", "Preview an action or form.")
    let supplied = try definitionArguments(descriptor, arguments)
    let state = DefinitionEvaluation(cancellation)
    try state.enter(root, depth: 0)
    let action: ApplicationDefinition
    if root.kind == "form" {
      let form = try DefinitionForm(descriptor)
      try require(
        form.targetKind == "action", "definition_kind",
        "Use workflow-form submission for this form.")
      action = try resolveDefinition(form.binding)
      try validateForm(form, descriptor: descriptor, action: action)
      try state.enter(action, depth: 1)
    } else {
      action = root
    }
    let actionDescriptor = try DefinitionDescriptor(action.content)
    let primitive = try definitionAction(actionDescriptor)
    let mapped = try validateActionMapping(
      primitive, caller: actionDescriptor, state: state,
      arguments: supplied, depth: root.kind == "form" ? 1 : 0)
    try cancellation.check()
    if let binding = primitive.tool {
      let tool = try runnableTool(version: resolveDefinition(binding))
      _ = try toolInputs(tool, mapped)
      var plan: [String: Value] = [
        "workbookID": .string(self.id), "requestedID": .string(id),
        "definitionID": .string(root.id), "actionID": .string(action.id),
        "title": .string(root.title), "arguments": .object(supplied),
        "submittedArguments": arguments, "primitiveArguments": .object(mapped),
        "primitive": .object(["id": .string(ActionRegistry.toolID), "version": .number(1)]),
        "resolvedDefinitions": .array(
          state.resolved.values.sorted { $0.id < $1.id }.map {
            .object([
              "id": .string($0.id), "logicalID": .string($0.logicalID),
              "sourceID": .string($0.sourceID),
            ])
          }),
        "tool": .object([
          "name": .string(tool.name), "definitionID": .string(tool.definitionID),
          "language": .string(tool.language), "signature": .string(tool.signature),
        ]),
        "readOnly": .bool(true),
        "effect": .string(
          "Run the saved tool \(tool.name). Its changes are saved at once and can be undone."),
        "units": .string("tool inputs"),
      ]
      plan["fingerprint"] = .string(ChangeFormat.hash(try Value.object(plan).json()))
      return .object(plan)
    }
    let documents = try proposedDocuments(mapped)
    var plan: [String: Value] = [
      "workbookID": .string(self.id), "requestedID": .string(id), "definitionID": .string(root.id),
      "actionID": .string(action.id), "title": .string(root.title), "arguments": .object(supplied),
      "submittedArguments": arguments, "primitiveArguments": .object(mapped),
      "primitive": .object([
        "id": .string(primitive.primitiveID),
        "version": .number(Double(primitive.primitiveVersion)),
      ]),
      "resolvedDefinitions": .array(
        state.resolved.values.sorted { $0.id < $1.id }.map {
          .object([
            "id": .string($0.id), "logicalID": .string($0.logicalID),
            "sourceID": .string($0.sourceID),
          ])
        }),
      "documents": .array(documents), "readOnly": .bool(true),
      "effect": .string(
        "Save one draft document (\(documents[0]["meaning"].text), scenario \(documents[0]["scenario"].text)). New prose with evidence lineage; verify its claims separately. Nothing is accepted in this step."
      ),
      "units": .string("new prose"),
    ]
    plan["fingerprint"] = .string(ChangeFormat.hash(try Value.object(plan).json()))
    return .object(plan)
  }

  private func proposedDocuments(_ arguments: [String: Value]) throws -> [Value] {
    let title = arguments["title"]!.text
    let body = arguments["body"]!.text
    let scenario = arguments["scenario"]!.text
    try require(
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.utf8.count <= 2048
        && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !scenario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && scenario.utf8.count <= 256,
      "action_document", "Enter a document title, bounded new prose and an explicit scenario.")
    let evidence = try item(arguments["evidence"]!.text)
    try require(
      evidence.id == arguments["evidence"]!.text && evidence.isBusinessEvidence,
      "action_document", "Use one exact local business evidence item.")
    if arguments["meaning"] == .string("actual") {
      try require(
        evidence.meaning == "actual" && evidence.scenario == scenario,
        "interpretation_meaning",
        "Actual documents cannot promote estimates or change their evidence scenario.")
    }
    return [.object(arguments)]
  }
}

extension Workbook {
  /// A tool action runs its tool through the button's path, outside one transaction, since the
  /// tool's own saves are recorded changes. Its receipt is saved after, under the action's
  /// token, so an exact retry returns that receipt and does not run the tool again.
  private func invokeToolAction(
    _ id: String, arguments: Value, preview: Value, token: String, request: Value,
    requestSourceID: String?, actor: ChangeActor, requestRunID: String?,
    cancellation: Cancellation
  ) throws -> Value {
    let receipt: () throws -> Value = {
      try self.mutation(
        "invoke_application_action", token: token, request: request,
        cancellation: Cancellation(parent: cancellation, deadlineAfterSeconds: 3), actor: actor
      ) {
        throw SevraError("action_token", "The action's receipt is missing.")
      }
    }
    if try synchronized({
      try db.scalar("SELECT EXISTS(SELECT 1 FROM operations WHERE id=?)", [.string(token)]).int == 1
    }) {
      return try receipt()
    }
    let plan = try synchronized(cancellation: cancellation) {
      try db.readTransaction {
        if let requestRunID {
          try validateApplicationToolRun(requestRunID, requestSourceID: requestSourceID)
        }
        return try applicationActionPlan(id, arguments: arguments, cancellation: cancellation)
      }
    }
    try require(
      plan == preview, "stale_action_preview",
      "The action or its inputs changed. Keep your draft and preview it again.")
    let run = try runPlannedTool(
      plan, token: "action-" + token, requestSourceID: requestSourceID, actor: actor,
      cancellation: cancellation)
    return try mutation(
      "invoke_application_action", token: token, request: request,
      cancellation: Cancellation(parent: cancellation, deadlineAfterSeconds: 3), actor: actor
    ) {
      try self.insertToolInvocation(
        plan: plan, run: run, request: request, actor: actor, requestSourceID: requestSourceID)
    }
  }

  /// Runs a planned tool action's tool. A run whose changes were already saved under `token`,
  /// by an earlier attempt that stopped before its receipt, is not run again.
  func runPlannedTool(
    _ plan: Value, token: String, requestSourceID: String?, actor: ChangeActor,
    cancellation: Cancellation
  ) throws -> Value {
    let tool = try synchronized {
      try runnableTool(version: applicationDefinition(plan["tool"]["definitionID"].text))
    }
    for saved in ["tool-" + token, "run-" + token]
    where try synchronized({ !(try chatSQLSteps(saved)).isEmpty }) {
      return .object(["undo": .string(saved), "recovered": .bool(true)])
    }
    return try ChangeAttribution.$actor.withValue(actor) {
      try WorkbookTools(
        self, cancellation: cancellation, requestSourceID: requestSourceID, conversation: ""
      ).runTool(tool, values: plan["primitiveArguments"].object, readOnly: false, token: token)
    }
  }

  /// The receipt of one tool action: an invocation Source that names what ran and its undo.
  func insertToolInvocation(
    plan: Value, run: Value, request: Value, actor: ChangeActor, requestSourceID: String?,
    additionalInputs: [String] = [], controlInputs: [String] = [], producerInputs: [String] = []
  ) throws -> Value {
    if let requestSourceID {
      let source = try self.item(requestSourceID)
      try require(
        source.id == requestSourceID && source.category == "source" && source.kind == "request",
        "action_request", "Use the captured current request Source.")
    }
    let definitionInputs = plan["resolvedDefinitions"].array.map { $0["sourceID"].text }
    let summary = Self.describeRun(run)
    var outcome: [String: Value] = [:]
    for key in ["undo", "changes", "shape", "results", "value", "recovered"] {
      if let value = run.object[key] { outcome[key] = value }
    }
    let invocation = try self.insertItem(
      category: "source", kind: "application_invocation",
      title: "Ran " + plan["title"].text,
      text: actor.label + " ran the saved tool " + plan["tool"]["name"].text + ". " + summary,
      data: .object([
        "submitted": request, "plan": plan, "actor": try encoded(actor),
        "outcome": .object(outcome), "producerPolicy": .string("application-tool-v1"),
      ]),
      meaning: "actual", status: "accepted", scenario: "actual",
      inputs: Array(Set(additionalInputs + (requestSourceID.map { [$0] } ?? []))).sorted(),
      transformation: "application-tool-invocation-v1",
      controlInputs: definitionInputs + controlInputs, producerInputs: producerInputs)
    var result: [String: Value] = [
      "workbookID": .string(self.id), "definitionID": plan["definitionID"],
      "sourceID": .string(invocation), "tool": plan["tool"]["signature"],
      "state": .string("applied"), "summary": .string(summary),
      "resolvedDefinitions": plan["resolvedDefinitions"], "fingerprint": plan["fingerprint"],
    ]
    for key in ["undo", "changes", "results"] {
      if let value = run.object[key] { result[key] = value }
    }
    return .object(result)
  }
}
