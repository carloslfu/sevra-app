import Foundation
import SevraAI
import SevraCore

private actor HandoffModel: WorkbookInference {
  let identity = "synthetic request handoff"
  let lastMetrics: Value = .object(["fixture": .bool(true)])
  let mode: String
  var calls = 0
  var begins = 0
  var ends = 0
  init(_ mode: String = "calculate") { self.mode = mode }
  func beginRun() { begins += 1 }
  func endRun() { ends += 1 }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    calls += 1
    if calls > ((mode == "after_read" || mode == "invalid_task") ? 2 : 1) && mode != "late" {
      try expectEqual(messages[0].conversationActions, [])
      try expectEqual(
        messages.map(\.content).joined().contains("Unselected secret parent detail"), false)
      try expectEqual(messages[0].content.contains("already created the requested thread"), true)
    }
    if calls == 2 && mode == "fail" {
      throw SevraError("fixture_failure", "Synthetic continuation failed")
    }
    let tool: String
    let arguments: Value
    if (calls == 1 && !["late", "after_read"].contains(mode))
      || (calls == 2 && ["late", "after_read", "invalid_task"].contains(mode))
    {
      tool = "start_thread_and_continue"
      arguments = .object([
        "title": .string("Delivery comparison"),
        "task": .string(
          mode == "invalid_task" && calls == 1
            ? "Invented task" : "calculate the difference between 14.80 and 12.40"),
      ])
    } else if calls == 1 && mode == "late" {
      tool = "save_space"
      arguments = .object([
        "title": .string("Already saved"),
        "definition": .object(["version": .number(1), "components": .array([])]),
      ])
    } else if calls == 2 && mode == "repeat" {
      tool = "start_thread"
      arguments = .object(["title": .string("Should not exist")])
    } else if mode == "budget" {
      tool = "datasets"
      arguments = .object([:])
    } else if (calls == 2 && mode != "late") || (mode == "after_read" && calls == 1)
      || (["after_read", "invalid_task"].contains(mode) && calls == 3)
    {
      tool = "calculate"
      arguments = .object(["expression": .string("14.80-12.40")])
    } else {
      tool = "finish"
      arguments = .object([
        "answer": .string(
          mode == "late" ? "The saved view remains here." : "The difference is 2.4."),
        "basis": .string(mode == "late" ? "completed_action" : "current_request"),
        "citations": .array([]),
      ])
    }
    return .init(
      text: "", calls: [.init(id: identifier(), name: tool, inputJSON: try arguments.json())])
  }
}

func checkRequestHandoffs() async throws {
  for scope in [
    InferenceToolScope.answer, .draft, .save_space, .propose_movement, .propose_record,
    .propose_table, .propose_table_edit,
  ] {
    let values = try Value.parse(
      String(decoding: NativeTools.serializedDefinitions(toolScope: scope), as: UTF8.self))
    let names = Set(values.array.map { $0["function"]["name"].text })
    let extra = scope == .answer ? [] : [scope.rawValue]
    try expectEqual(names, WorkbookTools.readOnlyTools.union(["finish"]).union(extra))
    try expectEqual(scope.allows("start_thread"), false)
  }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-handoffs-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let prompt =
    "Start a thread called Delivery comparison and calculate the difference between 14.80 and 12.40."
  for mode in [
    "calculate", "after_read", "invalid_task", "repeat", "late", "fail", "cancel", "budget",
  ] {
    let book = try Workbook.create(at: root.appendingPathComponent(mode + ".sevra"), title: mode)
    _ = try book.addMessage("Unselected secret parent detail", role: "user")
    _ = try book.addMessage("This must stay outside the selected exchange", role: "assistant")
    for index in 0..<6 {
      _ = try book.addMessage("Closed parent note \(index).", role: "assistant")
    }
    _ = try book.addMessage("Compare these quotes next.", role: "user")
    let parent = try book.addMessage(
      "Both quotes are available for the comparison.", role: "assistant")
    let model = HandoffModel(mode)
    let cancellation = Cancellation()
    var result: AgentResult?
    do {
      result = try await WorkbookAgent.run(
        prompt, workbook: book, context: "Visible selection: quotes",
        cancellation: cancellation,
        progress: { text in
          if mode == "cancel" && text == "Continuing in the new thread…" { cancellation.cancel() }
        }, model: model, enableCompaction: false)
      try expectEqual(["calculate", "after_read", "invalid_task", "late"].contains(mode), true)
    } catch let error as SevraError {
      try expectEqual(
        error.code,
        mode == "cancel"
          ? "cancelled"
          : mode == "budget" ? "step_limit" : mode == "repeat" ? "tool_scope" : "fixture_failure")
    }
    try expectEqual(await model.begins, 1)
    try expectEqual(await model.ends, 1)
    try expectEqual(try book.items().filter { $0.kind == "request" }.count, 1)
    let source = try book.items().first { $0.kind == "request" }!
    let exactSource = try book.item(source.id)
    try expectEqual(exactSource.text, prompt)
    let runs = try book.agentRuns()
    try expectEqual(runs.count, mode == "late" ? 1 : 2)
    if mode == "late" {
      try expectEqual(try book.conversations().count, 1)
      try expectEqual(result?.conversationAction, nil)
      // Error prose is intentionally not coupled to internal error codes.
      try expectEqual(
        try book.messages().contains {
          $0.role == "tool" && $0.body.contains("already attempted changes")
        }, true)
    } else {
      try expectEqual(try book.conversations().count, 2)
      let child = runs.first { $0["conversation_id"].text != "main" }!
      let origin = runs.first { $0["conversation_id"].text == "main" }!
      let target = child["conversation_id"].text
      try expectEqual(origin["status"].text, "continued")
      try expectEqual(try book.requestRunStatus(origin["request_message_id"].text), "continued")
      try expectEqual(try book.conversationIdentity(target)["parent_message"].text, parent)
      let carried = try book.messages(conversation: target).first { $0.role == "user" }!
      try expectEqual(carried.body, prompt)
      try expectEqual(
        try book.messages().filter { $0.role == "user" && $0.body == prompt }.count, 1)
      let originalRequest = try book.messages().first {
        $0.id == origin["request_message_id"].text
      }!
      try expectEqual(
        try WorkbookAgent.stoppedRequestReference(book, message: originalRequest)?["referenceOnly"],
        .bool(true))
      let receipt = try book.messages().first {
        $0.role == "tool" && (try? Value.parse($0.body)["result"]["kind"].text) == "created"
      }!
      let receiptID = try Value.parse(receipt.body)["receiptID"].text
      let replay = try book.handoffAgentRequest(
        runID: origin["id"].text, receiptID: receiptID,
        sourceID: source.id, steps: 1, metrics: .array([]))
      try expectEqual(replay.request.runID, child["id"].text)
      try expectEqual(replay.request.messageID, carried.id)
      try expectEqual(try book.agentRuns().count, 2)
      if let result {
        try expectEqual(result.conversationAction?.conversation, target)
        try expectEqual(result.steps, ["after_read", "invalid_task"].contains(mode) ? 4 : 3)
        try expectEqual(child["status"].text, "complete")
        try expectEqual(try book.messages(conversation: target).last?.body, result.answer)
      } else {
        try expectEqual(child["status"].text, mode == "cancel" ? "cancelled" : "failed")
        try expectEqual(
          try book.messages(conversation: target).last?.state,
          mode == "cancel" ? "cancelled" : "failed")
      }
      if mode == "budget" { try expectEqual(await model.calls, 12) }
      if mode == "cancel" { try expectEqual(await model.calls, 1) }
    }
    try expectEqual(try book.verify()["ok"], .bool(true))
    let reopened = try Workbook(book.url)
    try expectEqual(try reopened.agentRuns().count, runs.count)
    try expectEqual(try reopened.verify()["ok"], .bool(true))
  }
  let pending = try Workbook.create(
    at: root.appendingPathComponent("pending.sevra"), title: "Pending")
  let admission = try pending.startAgentRequest(prompt, conversation: "main", model: "fixture")
  let original = try pending.addItem(
    category: "source", kind: "request", title: "User request", text: prompt,
    data: .object(["messageID": .string(admission.messageID), "conversationID": .string("main")]),
    status: "accepted")
  let args: Value = .object([
    "title": .string("Pending comparison"),
    "task": .string("calculate the difference between 14.80 and 12.40"),
  ])
  let receipt = try pending.prepareToolCall(
    runID: admission.runID, callID: "create", tool: "start_thread_and_continue", arguments: args,
    assistantText: "")
  let tools = WorkbookTools(
    pending, runID: admission.runID, requestSourceID: original.id,
    conversationTitle: "Main conversation")
  let creation = try tools.execute("start_thread_and_continue", args)
  _ = try pending.completeToolCall(receipt, result: creation)
  let cancelled = Cancellation()
  cancelled.cancel()
  try expectThrows(
    try pending.handoffAgentRequest(
      runID: admission.runID, receiptID: receipt, sourceID: original.id,
      steps: 1, metrics: .array([]), cancellation: cancelled))
  try expectEqual(try pending.agentRuns().count, 1)
  try expectEqual(try pending.messages(conversation: creation["conversation"].text).count, 0)
  let wrong = try pending.addItem(
    category: "source", kind: "note", title: "Wrong input", text: prompt)
  try expectThrows(
    try pending.handoffAgentRequest(
      runID: admission.runID, receiptID: receipt, sourceID: wrong.id,
      steps: 1, metrics: .array([])))
  try expectEqual(try pending.agentRuns().count, 1)
  let carried = try pending.handoffAgentRequest(
    runID: admission.runID, receiptID: receipt, sourceID: original.id,
    steps: 1, metrics: .array([]))
  let reopened = try Workbook(pending.url)
  try expectEqual(try reopened.agentRuns().count, 2)
  try expectEqual(try reopened.messages(conversation: carried.conversation).count, 1)
  _ = try reopened.startAgentRequest(
    "A new request, not a retry.", conversation: "main", model: "fixture")
  try expectEqual(try reopened.requestRunStatus(carried.request.messageID), "interrupted")
  try expectEqual(try reopened.requestRunStatus(admission.messageID), "continued")
  try expectEqual(try reopened.messages(conversation: carried.conversation).count, 1)
  let observation = try reopened.addItem(
    category: "source", kind: "observation", title: "Stock handover",
    text: "Two fittings left stock.")
  let movementTools = WorkbookTools(reopened, requestSourceID: original.id)
  let movementArguments: Value = .object([
    "subject": .string("fittings"), "quantity": .string("-2"),
    "occurrence": .string("handover-test"), "effective": .string("2026-01-02"),
    "input": .string(observation.id),
  ])
  let movement = try movementTools.execute("propose_movement", movementArguments)
  try expectEqual(try movementTools.execute("propose_movement", movementArguments), movement)
  try expectEqual(
    Set(try reopened.lineage(movement["id"].text).map { $0["parent"].text }),
    Set([original.id, observation.id]))
  try expectEqual(movement["status"].text, "draft")
  try expectThrows(
    try reopened.movement(
      subject: "fittings", quantity: "-2", occurrence: "invalid-request",
      effective: "2026-01-02", input: observation.id, requestSourceID: observation.id))
  try expectEqual(try reopened.items().filter { $0.kind == "movement" }.count, 1)
  try expectEqual(try reopened.verify()["ok"], .bool(true))
  print(
    "PASS exact request handoff, one lease/Source, scoped child history, no repeats, cancellation, failure, shared step budget and reopen"
  )
}
