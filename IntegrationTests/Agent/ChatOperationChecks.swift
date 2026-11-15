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
  init(_ actions: [(String, Value)]) { self.actions = actions }
  func beginRun() { begins += 1 }
  func endRun() { ends += 1 }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
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
      text: "", calls: [.init(id: "chat-\(index)", name: call.0, inputJSON: try call.1.json())])
  }
}

@MainActor func checkChatAgentOperations() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-chat-agent-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root, title: "Chat agent")
  let action: Value = .object([
    "action": .string("app.run"),
    "arguments": .object([
      "id": .string("synthetic-app"), "expectedVersion": .number(1), "action": .string("add"),
      "inputs": .object(["name": .string("Paper")]),
    ]),
  ])
  var invocations = 0
  let model = ChatOperationModel([
    ("workspace_actions", .object(["domain": .string("app")])), ("workspace_action", action),
    ("workspace_action", action),
  ])
  _ = try await WorkbookAgent.run(
    "Add Paper in my app.", workbook: book, model: model,
    workspaceAction: { name, arguments, readOnly, cancellation in
      try expectEqual(name, "app.run")
      try expectEqual(arguments["inputs"]["name"].text, "Paper")
      try expectEqual(readOnly, false)
      try cancellation.check()
      invocations += 1
      return .object([
        "outcome": .string("completed"), "result": .object(["saved": .string("Paper")]),
      ])
    })
  try expectEqual(invocations, 1)
  var fixed = action.object
  var fixedArguments = action["arguments"].object
  fixedArguments["inputs"] = .object(["name": .string("Paper"), "quantity": .string("2")])
  fixed["arguments"] = .object(fixedArguments)
  let repaired = try await WorkbookAgent.run(
    "Add Paper with quantity 2 in my app.", workbook: book,
    model: ChatOperationModel([("workspace_action", action), ("workspace_action", .object(fixed))]),
    workspaceAction: { _, arguments, _, _ in
      if arguments["inputs"]["quantity"] == .null {
        throw SevraError("app_input", "Quantity is required")
      }
      return .object([
        "outcome": .string("completed"), "changes": .array([.object(["saved": .bool(true)])]),
      ])
    })
  try expectEqual(repaired.answer.contains("Couldn’t finish"), false)
  let lookup: Value = .object([
    "action": .string("app.browse"),
    "arguments": .object(["id": .string("synthetic-app"), "target": .string("wrong-table")]),
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
