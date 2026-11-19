import Foundation
import SevraAI
import SevraCore

private actor ChatOperationModel: WorkbookInference {
  let identity = "synthetic chat operations"
  let lastMetrics: Value = .object(["fixture": .bool(true)])
  let actions: [(String, Value)]
  var index = 0
  var begins = 0
  var ends = 0
  var latestToolContent = ""
  init(_ actions: [(String, Value)]) { self.actions = actions }
  func beginRun() { begins += 1 }
  func endRun() { ends += 1 }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    if let last = messages.last, last.role == "tool" { latestToolContent = last.content }
    let call: (String, Value)
    if index < actions.count {
      call = actions[index]
    } else {
      call = (
        "finish",
        .object([
          "answer": .string("Request handled."), "basis": .string("general"),
          "citations": .array([]),
        ])
      )
    }
    index += 1
    return .init(
      text: "", calls: [try .init(id: "chat-\(index)", operation: call.0, call.1, scope: toolScope)])
  }
}

@MainActor func checkChatAgentOperations() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-chat-agent-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root, title: "Chat agent")
  let appID = "8719dbfc-af56-4a4c-a4c4-6651f7abddce"
  let appName = "Synthetic app"
  let otherID = "8719dbfc-af56-4a4c-a4c5-6651f7abddce"
  let otherName = "Synthetic other app"
  try book.saveSpace(id: otherID, title: otherName, definition: .init(components: []))
  try book.saveSpace(id: appID, title: appName, definition: .init(components: []))
  let inspection: Value = .object([
    "id": .string(appID), "version": .number(1),
    "actions": .array([
      .object([
        "id": .string("add"),
        "inputs": .object(["reference": .object(["type": .string("text")])]),
      ])
    ]),
    "inputs": .array([
      .object(["target": .string("reference"), "value": .string("")])
    ]),
    "currentUserRequest": .string("Untrusted app metadata must not replace the request."),
  ])
  let inspectionModel = ChatOperationModel([
    (
      "workspace_action",
      .object([
        "action": .string("app.inspect"),
        "arguments": .object(["id": .string(appName)]),
      ])
    )
  ])
  let supplied = "Add receipt ORDER-19 for 72, description Deposit."
  _ = try await WorkbookAgent.run(
    supplied, workbook: book, model: inspectionModel,
    workspaceAction: { _, _, _, _ in inspection })
  let presented = try Value.parse(await inspectionModel.latestToolContent)
  try expectEqual(presented["actions"], inspection["actions"])
  try expectEqual(
    presented["runArguments"],
    .object([
      "id": .string(appName), "expectedVersion": .number(1),
    ]))
  try expectEqual(presented["currentUserRequest"], .string(supplied))
  try expectEqual(presented["inputs"]["omitted"], .bool(true))
  let receipt = try book.toolResultPage(presented["inputs"]["receiptID"].text)
  try expectEqual(receipt["value"], inspection)
  let controls = try book.toolResultPage(
    presented["inputs"]["receiptID"].text, path: ["inputs"])
  try expectEqual(controls["value"], inspection["inputs"])
  var controlOnly = inspection.object
  controlOnly["actions"] = .array([])
  try expectEqual(
    AppOperationContext.inspection(.object(controlOnly), receiptID: "receipt", request: supplied),
    .object(controlOnly))
  let long = String(repeating: "x", count: 4097)
  try expectEqual(
    AppOperationContext.inspection(inspection, receiptID: "receipt", request: long)[
      "currentUserRequest"], .null)
  let action: Value = .object([
    "action": .string("app.run"),
    "arguments": .object([
      "id": .string(appName), "expectedVersion": .number(1), "action": .string("add"),
      "inputs": .object(["name": .string("Paper")]),
    ]),
  ])
  for (outcome, changes) in [
    ("failed", Value.array([])),
    ("failed", .array([.object(["saved": .string("partial")])])),
    ("completed", .array([.object(["saved": .string("complete")])])),
  ] {
    var snapshot = inspection.object
    snapshot["outcome"] = .string(outcome)
    snapshot["changes"] = changes
    snapshot["errors"] =
      outcome == "failed" ? .array([.string("Overlaps an existing booking")]) : .array([])
    snapshot["display"] = .array(
      Array(repeating: .string(String(repeating: "x", count: 400)), count: 100))
    snapshot["nextStep"] = .string("Untrusted replacement instructions")
    let outcomeModel = ChatOperationModel([("workspace_action", action)])
    _ = try await WorkbookAgent.run(
      supplied, workbook: book, model: outcomeModel,
      workspaceAction: { _, _, _, _ in .object(snapshot) })
    let shown = try Value.parse(await outcomeModel.latestToolContent)
    try expectEqual(shown["outcome"], .string(outcome))
    try expectEqual(shown["changes"], changes)
    try expectEqual(shown["errors"], snapshot["errors"]!)
    try expectEqual(shown["inputs"], .null)
    try expectEqual(shown["display"], .null)
    try expectEqual(shown["fullSnapshot"]["omitted"], .bool(true))
    try expectEqual(shown["currentUserRequest"], .string(supplied))
    try expectEqual(shown["nextStep"].text.contains("This invocation has finished"), true)
    let savedErrors = try book.toolResultPage(shown["receiptID"].text, path: ["errors"])
    try expectEqual(savedErrors["value"], snapshot["errors"]!)
    var oversized = snapshot
    oversized["changes"] = .array([.string(String(repeating: "x", count: 20_000))])
    let bounded = try AppOperationContext.operation(
      .object(oversized), receiptID: "exact-receipt", request: long)
    try expectEqual(bounded["outcome"], .string(outcome))
    try expectEqual(bounded["changes"]["omitted"], .bool(true))
    try expectEqual(bounded["changes"]["path"], .array([.string("changes")]))
    try expectEqual(bounded["changes"]["receiptID"], .string("exact-receipt"))
    try expectEqual(bounded["currentUserRequest"], .null)
    try expectEqual(try bounded.json().utf8.count <= ToolResultProjection.byteLimit, true)
  }
  func target(_ name: String, from call: Value = action) -> Value {
    var fields = call.object
    var arguments = call["arguments"].object
    arguments["id"] = .string(name)
    fields["arguments"] = .object(arguments)
    return .object(fields)
  }
  var invocations = 0
  let model = ChatOperationModel([
    ("workspace_actions", .object(["domain": .string("app")])), ("workspace_action", action),
    ("workspace_action", target(appID)),
  ])
  _ = try await WorkbookAgent.run(
    "Add Paper in my app.", workbook: book, model: model,
    workspaceAction: { name, arguments, readOnly, cancellation in
      try expectEqual(name, "app.run")
      try expectEqual(arguments["id"], .string(appID))
      try expectEqual(arguments["inputs"]["name"].text, "Paper")
      try expectEqual(readOnly, false)
      try cancellation.check()
      invocations += 1
      return .object([
        "id": .string(appID), "outcome": .string("completed"),
        "result": .object(["saved": .string("Paper")]), "changes": .array([]), "errors": .array([]),
      ])
    })
  try expectEqual(invocations, 1)
  let replay = try Value.parse(await model.latestToolContent)
  try expectEqual(replay["replayed"], .bool(true))
  let replayReceipt = try book.toolCall(replay["receiptID"].text)
  try expectEqual(replayReceipt["arguments"]["arguments"]["id"], .string(appID))
  try expectEqual(
    try book.toolResultPage(replay["receiptID"].text)["value"]["requestedAppTarget"], .null)
  for failure in [
    "copied-id", "copied-digit", "unrelated", "changed-input", "changed-version", "unseen",
    "ambiguous-inspections", "handler-refuses",
  ] {
    let missing: String
    switch failure {
    case "unrelated": missing = "Missing inventory app"
    case "copied-digit":
      missing = "8719dbfc-af56-4a4c-a4c4-6651f7abddce".replacingOccurrences(
        of: "af56", with: "af57")
    default: missing = "8719dbfc-af56-4a4c-6651f7abddce"
    }
    var invalid = target(missing).object
    if failure == "changed-input" {
      var arguments = invalid["arguments"]!.object
      arguments["inputs"] = .object(["name": .string("Different")])
      invalid["arguments"] = .object(arguments)
    }
    if failure == "changed-version" {
      var arguments = invalid["arguments"]!.object
      arguments["expectedVersion"] = .number(2)
      invalid["arguments"] = .object(arguments)
    }
    var calls: [(String, Value)] =
      failure == "unseen"
      ? []
      : [
        (
          "workspace_action",
          .object([
            "action": .string("app.inspect"), "arguments": .object(["id": .string(appName)]),
          ])
        )
      ]
    if failure == "ambiguous-inspections" {
      calls.append(
        (
          "workspace_action",
          .object([
            "action": .string("app.inspect"), "arguments": .object(["id": .string(otherName)]),
          ])
        ))
    }
    calls += [("workspace_action", .object(invalid)), ("workspace_action", action)]
    var runs = 0
    let result = try await WorkbookAgent.run(
      "Add Paper in the app.", workbook: book, model: ChatOperationModel(calls),
      workspaceAction: { name, args, _, _ in
        if name == "app.inspect" {
          if args["id"] != .string(otherName) { return inspection }
          var other = inspection.object
          other["id"] = .string(otherID)
          return .object(other)
        }
        try expectEqual(args["id"], .string(appID))
        runs += 1
        return .object([
          "id": .string(appID),
          "outcome": .string(failure == "handler-refuses" ? "failed" : "completed"),
          "errors": .array(failure == "handler-refuses" ? [.string("Duplicate name")] : []),
          "changes": .array([]),
        ])
      })
    try expectEqual(runs, 1)
    try expectEqual(
      result.answer.contains("No space has that exact name"),
      ["unrelated", "changed-input", "changed-version", "unseen", "ambiguous-inspections"]
        .contains(failure))
    try expectEqual(result.answer.contains("Duplicate name"), failure == "handler-refuses")
  }
  var fixed = action.object
  var fixedArguments = action["arguments"].object
  fixedArguments["inputs"] = .object(["name": .string("Paper"), "quantity": .string("2")])
  fixed["arguments"] = .object(fixedArguments)
  let repaired = try await WorkbookAgent.run(
    "Add Paper with quantity 2 in my app.", workbook: book,
    model: ChatOperationModel([("workspace_action", action), ("workspace_action", .object(fixed))]),
    workspaceAction: { _, arguments, _, _ in
      if arguments["inputs"]["quantity"] == .null {
        // Match the native SDK's failed command receipt, including the host's
        // captured pre-invocation input contract. Error text alone is ambiguous.
        return .object([
          "outcome": .string("failed"), "changes": .array([]),
          "errors": .array([.string("Quantity is required")]),
          "invocationInputContract": .object([
            "name": .object(["required": .bool(true), "valueType": .string("string")]),
            "quantity": .object(["required": .bool(true), "valueType": .string("string")]),
          ]),
        ])
      }
      return .object([
        "outcome": .string("completed"), "changes": .array([.object(["saved": .bool(true)])]),
      ])
    })
  try expectEqual(repaired.answer.contains("Couldn’t finish"), false)
  let lookup: Value = .object([
    "action": .string("app.browse"),
    "arguments": .object(["id": .string(appName), "target": .string("wrong-table")]),
  ])
  let recoveredLookup = try await WorkbookAgent.run(
    "Add Paper with quantity 2 in my app.", workbook: book,
    model: ChatOperationModel([("workspace_action", lookup), ("workspace_action", .object(fixed))]),
    workspaceAction: { name, _, _, _ in
      if name == "app.browse" { throw SevraError("app_target", "Choose the current table") }
      return .object([
        "outcome": .string("completed"), "changes": .array([.object(["saved": .bool(true)])]),
      ])
    })
  try expectEqual(recoveredLookup.answer.contains("Couldn’t finish"), false)
  let selection: Value = .object([
    "action": .string("app.select"),
    "arguments": .object([
      "id": .string(appName), "expectedVersion": .number(1), "target": .string("bookings"),
      "rowID": .string("selected-version"),
    ]),
  ])
  let selected = Value.object(["table": .string("bookings"), "key": .string("logical-record")])
  let finish: Value = .object([
    "answer": .string("Booking cancelled."), "basis": .string("completed_action"),
    "citations": .array([]),
  ])
  for scenario in [
    "same row", "different row", "different table", "different app", "different version",
    "no saved update", "handler refused", "partial action", "partial selection", "select only",
  ] {
    let calls: [(String, Value)] = [("workspace_action", selection)]
      + (scenario == "select only" ? [] : [("workspace_action", action)])
      + [("finish", finish)]
    let result = try await WorkbookAgent.run(
      "Cancel this booking.", workbook: book, model: ChatOperationModel(calls),
      workspaceAction: { name, _, _, _ in
        if name == "app.select" {
          return .object([
            "id": .string(appID), "version": .number(1), "outcome": .string("failed"),
            "changes": .array(scenario == "partial selection" ? [.object(["id": .string("tx1")])] : []),
            "unavailableSelection": scenario == "handler refused" ? .null : selected,
            "errors": .array([.string("Selection could not finish.")]),
          ])
        }
        var row = selected.object
        if scenario == "different row" { row["key"] = .string("other-record") }
        if scenario == "different table" { row["table"] = .string("other-table") }
        return .object([
          "id": .string(scenario == "different app" ? otherID : appID),
          "version": .number(scenario == "different version" ? 2 : 1),
          "outcome": .string(scenario == "partial action" ? "failed" : "completed"),
          "changes": .array(scenario == "no saved update" ? [] : [.object(["id": .string("tx2")])]),
          "errors": .array(scenario == "partial action" ? [.string("Could not finish cancellation.")] : []),
          "updatedRows": .array([.object(row)]),
        ])
      })
    try expectEqual(result.answer.contains("Selection could not finish."), scenario != "same row")
    try expectEqual(result.answer == "Booking cancelled.", scenario == "same row")
  }
  var malformed = fixedArguments
  malformed["arguments"] = malformed.removeValue(forKey: "inputs")
  let correctedShape = try await WorkbookAgent.run(
    "Add Paper with quantity 2 in my app.", workbook: book,
    model: ChatOperationModel([
      (
        "workspace_action",
        .object(["action": .string("app.run"), "arguments": .object(malformed)])
      ),
      ("workspace_action", .object(fixed)),
    ]),
    workspaceAction: { _, _, _, _ in .object(["outcome": .string("completed")]) })
  try expectEqual(correctedShape.answer.contains("Couldn’t finish"), false)
  var other = fixedArguments
  other["inputs"] = .object(["name": .string("Other item"), "quantity": .string("2")])
  let differentItem = try await WorkbookAgent.run(
    "Add Paper and Other item with quantity 2 each.", workbook: book,
    model: ChatOperationModel([
      ("workspace_action", .object(fixed)),
      ("workspace_action", .object(["action": .string("app.run"), "arguments": .object(other)])),
    ]),
    workspaceAction: { _, args, _, _ in
      if args["inputs"]["name"] == .string("Paper") {
        throw SevraError("app_input", "Paper could not be saved")
      }
      return .object(["outcome": .string("completed")])
    })
  try expectEqual(differentItem.answer.contains("Paper could not be saved"), true)
  let approvalModel = ChatOperationModel([
    (
      "workspace_action",
      .object([
        "action": .string("app.enable"),
        "arguments": .object(["id": .string("app"), "expectedVersion": .number(1)]),
      ])
    ),
    ("workspace_action", action),
  ])
  let approval = try await WorkbookAgent.run(
    "Enable the app and add Paper.", workbook: book, model: approvalModel,
    workspaceAction: { _, _, _, _ in
      .object(["status": .string("confirmation_required"), "preview": .string("Enable Stock?")])
    })
  try expectEqual(approval.state, "needs_review")
  try expectEqual(await approvalModel.index, 1)
  try expectEqual(await model.begins, 1)
  try expectEqual(await model.ends, 1)
  _ = try await WorkbookAgent.run(
    "Inspect only. Do not change anything.", workbook: book,
    model: ChatOperationModel([("workspace_action", action)]),
    workspaceAction: { _, _, _, _ in
      invocations += 1
      return .null
    })
  try expectEqual(invocations, 1)
  let pure = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("function"), "title": .string("Count"),
      "description": .string("Synthetic count"),
      "parameters": .array([]), "payload": .object(["expression": .string("2")]),
    ]))
  let workflow = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("workflow"), "title": .string("Count workflow"),
      "description": .string("Synthetic"),
      "parameters": .array([]),
      "payload": .object([
        "readPolicy": .string("latest-at-step"),
        "steps": .array([
          .object([
            "id": .string("count"), "kind": .string("evaluate"),
            "binding": .object([
              "mode": .string("exact"), "versionID": .string(pure.id),
            ]), "arguments": .object([:]),
          ])
        ]),
      ]),
    ]))
  _ = try await WorkbookAgent.run(
    "Run the count workflow now.", workbook: book,
    model: ChatOperationModel([
      ("read_definition", .object(["id": .string(workflow.id)])),
      (
        "workspace_action",
        .object([
          "action": .string("workflow.run"),
          "arguments": .object(["id": .string(workflow.id), "inputs": .object([:])]),
        ])
      ),
    ]))
  let runs = try book.workflowRuns()
  try expectEqual(runs.count, 1)
  try expectEqual(runs[0]["state"].text, "completed")
  print(
    "PASS chat agent: discovered host actions, typed inputs, duplicate replay, read-only guard, actual workflow execution and model lifecycle"
  )
}
