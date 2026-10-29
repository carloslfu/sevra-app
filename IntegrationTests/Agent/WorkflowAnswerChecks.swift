import Foundation
import SevraAI
import SevraCore

private actor WorkflowAnswerModel: WorkbookInference {
  let identity = "Synthetic workflow answer preparation"
  let lastMetrics: Value = .object(["synthetic": .bool(true)])
  let runID: String
  var step = 0
  init(_ runID: String) { self.runID = runID }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    step += 1
    if step == 1 {
      try expectEqual(toolScope, .all)
      return .init(
        text: "",
        calls: [
          .init(
            id: identifier(), name: "read_workflow",
            inputJSON: try Value.object(["id": .string(runID)]).json())
        ])
    }
    try expectEqual(toolScope, .workflowAnswer)
    let read = try Value.parse(messages.last!.content)
    return .init(
      text: "",
      calls: [
        .init(
          id: identifier(), name: "prepare_workflow_answer",
          inputJSON: try Value.object([
            "readReceiptID": read["receiptID"], "values": .object(["quantity": .string("5")]),
            "quotes": .object(["quantity": .string("I counted 5 received bolts.")]),
            "reason": .string("The current message supplies the missing count."),
          ]).json())
      ])
  }
}

func checkWorkflowAnswerAgent() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "workflow-answer-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(
    at: root.appendingPathComponent("Answer.sevra"), title: "Synthetic answer")
  let source = try book.addItem(
    category: "source", kind: "observation", title: "Missing count",
    text: "The count was not recorded.")
  let parameter: Value = .object([
    "id": .string("evidence"), "label": .string("Evidence"), "type": .string("item"),
    "required": .bool(true),
  ])
  let interpretation = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("interpretation"), "title": .string("Read count"),
      "description": .string("Synthetic"),
      "parameters": .array([parameter]),
      "payload": .object([
        "instruction": .string("Ask if the count is missing."),
        "evidence": .array([.string("evidence")]),
        "outputs": .array([
          .object([
            "id": .string("quantity"), "label": .string("Received count"),
            "type": .string("decimal"), "unit": .string("items"), "required": .bool(true),
          ])
        ]),
        "meaning": .string("actual"), "scenario": .string("actual"),
      ]),
    ]))
  let workflow = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("workflow"), "title": .string("Receive"), "description": .string("Synthetic"),
      "parameters": .array([parameter]),
      "payload": .object([
        "readPolicy": .string("latest-at-step"),
        "steps": .array([
          .object([
            "id": .string("read"), "kind": .string("interpret"),
            "binding": .object(["mode": .string("exact"), "versionID": .string(interpretation.id)]),
            "arguments": .object(["evidence": .object(["parameter": .string("evidence")])]),
          ])
        ]),
      ]),
    ]))
  let run = try book.startWorkflow(
    workflow.id, arguments: .object(["evidence": .string(source.id)]), token: identifier())
  let session = try book.authorizeWorkflowExecution(run["id"].text)
  let claim = try book.claimWorkflowStep(session, owner: "synthetic")
  let request = try book.prepareWorkflowInterpretation(session, claim: claim, model: "synthetic")
  let original = try book.completeWorkflowStep(
    session, claim: claim,
    interpretation: .object([
      "request": request,
      "response": .object([
        "state": .string("needs_input"), "values": .object([:]), "citations": .array([]),
        "issues": .array([.string("Supply the count.")]),
      ]), "metrics": .object(["synthetic": .bool(true)]),
    ]))
  let result = try await WorkbookAgent.run(
    "I counted 5 received bolts. Prepare my answer for review.", workbook: book,
    model: WorkflowAnswerModel(session.runID))
  try expectEqual(result.answer.contains("unsent"), true)
  try expectEqual(result.focus?.id, session.runID)
  try expectEqual(try book.workflowRun(session.runID), original)
  let draft = try expectValue(book.workflowClarificationDraft(session.runID))
  try expectEqual(draft.entry.values, .object(["quantity": .string("5")]))
  try expectEqual(draft.entry.receipt == nil, true)
  try expectEqual(draft.entry.preparation?["values"], draft.entry.values)
  try expectEqual(InferenceToolScope.all.allows("prepare_workflow_answer"), false)
  try expectEqual(InferenceToolScope.answer.allows("prepare_workflow_answer"), false)
  try expectEqual(InferenceToolScope.workflowAnswer.allows("prepare_workflow_answer"), true)
  try expectEqual(InferenceToolScope.workflowAnswer.allows("start_workflow"), false)
  let all = try NativeTools.serializedDefinitions()
  let scoped = try NativeTools.serializedDefinitions(toolScope: .workflowAnswer)
  try expectEqual(String(decoding: all, as: UTF8.self).contains("prepare_workflow_answer"), false)
  try expectEqual(String(decoding: scoped, as: UTF8.self).contains("prepare_workflow_answer"), true)
  try expectEqual(try book.verify()["ok"], .bool(true))
  print(
    "PASS conversation workflow answer: contextual scope, exact current-message preparation, host unsent confirmation, original output and no business submission"
  )
}
