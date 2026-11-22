import Foundation
import SevraCore

func checkChatOperations() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-chat-core-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root, title: "Chat operations")
  let source = try book.addItem(category: "source", kind: "note", title: "Synthetic inputs")
  let table = try book.createDataset(
    title: "Orders",
    columns: [
      .init(id: "quantity", title: "Quantity", type: "decimal"),
      .init(id: "price", title: "Price", type: "decimal"),
      .init(id: "total", title: "Total", type: "decimal", formula: "quantity*price"),
    ], rows: [], sourceID: source.id)
  let tools = WorkbookTools(book)
  try refuses("arguments") {
    _ = try tools.execute(
      "workspace_action",
      .object([
        "action": .string("table.history"),
        "arguments": .object(["id": .string(table.id), "beforeVersion": .string("1")]),
      ]))
  }
  try refuses("arguments") {
    _ = try ChatOperations.validate(
      "app.set",
      arguments: .object([
        "id": .string("app"), "expectedVersion": .number(1.5), "target": .string("Name"),
        "value": .string("Paper"),
      ]), readOnly: false)
  }
  do {
    _ = try ChatOperations.validate(
      "app.run",
      arguments: .object([
        "id": .string("app"), "action": .string("receive"),
        "arguments": .object(["quantity": .string("7")]),
      ]), readOnly: false)
    throw SevraError("test", "A malformed action envelope was accepted")
  } catch let error as SevraError {
    try expect(error.code == "arguments")
    try expect(error.localizedDescription.contains("Missing fields: expectedVersion, inputs"))
    try expect(error.localizedDescription.contains("Unexpected fields: arguments"))
    try expect(error.localizedDescription.contains("expectedVersion:integer"))
  }
  _ = try ChatOperations.validate(
    "app.run",
    arguments: .object([
      "id": .string("app"), "expectedVersion": .number(1), "action": .string("receive"),
      "inputs": .object(["quantity": .string("7")]),
    ]), readOnly: false)
  let arguments: Value = .object([
    "action": .string("table.change_rows"),
    "arguments": .object([
      "id": .string(table.id), "expectedDefinitionID": .string(table.definitionID),
      "operations": .array([
        .object([
          "op": .string("insert"),
          "values": .object(["quantity": .string("3"), "price": .string("2.50")]),
        ])
      ]),
    ]),
  ])
  let first = try tools.execute("workspace_action", arguments)
  try expect(book.rows(table.id).count == 1)
  try expect(
    book.calculatedValues(book.rows(table.id)[0], columns: table.columns)["total"] == .string("7.5")
  )
  try expect(
    tools.execute("workspace_action", arguments) == first,
    "Repeated operation must replay without inserting again")
  try expect(book.rows(table.id).count == 1)
  try refuses("read_only_request") {
    _ = try WorkbookTools(book, readOnly: true).execute("workspace_action", arguments)
  }
  try refuses("arguments") {
    _ = try tools.execute(
      "workspace_action",
      .object([
        "action": .string("table.schema"),
        "arguments": .object(["id": .string(table.id), "sql": .string("anything")]),
      ]))
  }
  let old = try book.rows(table.id)[0]
  let changed = try book.chatTableTransaction(
    table.id, expectedDefinitionID: table.definitionID,
    operations: [
      .object([
        "op": .string("update"), "id": .string(old.id),
        "values": .object(["quantity": .string("4")]),
      ])
    ])
  try expect(
    book.calculatedValues(book.rows(table.id)[0], columns: table.columns)["total"] == .string("10"))
  try refuses("stale_revision") {
    _ = try book.chatTableTransaction(
      table.id, expectedDefinitionID: table.definitionID,
      operations: [
        .object(["op": .string("delete"), "id": .string(old.id)])
      ])
  }
  _ = try book.chatTableTransaction(
    table.id, expectedDefinitionID: table.definitionID, operations: [], undo: changed["token"].text)
  try expect(
    book.calculatedValues(book.rows(table.id)[0], columns: table.columns)["total"] == .string("7.5")
  )
  let current = try book.rows(table.id)[0]
  let deleted = try book.chatTableTransaction(
    table.id, expectedDefinitionID: table.definitionID,
    operations: [.object(["op": .string("delete"), "id": .string(current.id)])])
  try expect(book.rows(table.id).isEmpty)
  _ = try book.chatTableTransaction(
    table.id, expectedDefinitionID: table.definitionID, operations: [], undo: deleted["token"].text)
  try expect(book.rows(table.id).count == 1)
  _ = try book.updateDatasetDefinition(
    table.id, expectedVersion: table.version, expectedDefinitionID: table.definitionID,
    title: "Renamed")
  try refuses("stale_revision") {
    _ = try book.chatTableTransaction(
      table.id, expectedDefinitionID: table.definitionID, operations: [],
      undo: deleted["token"].text)
  }
  try expect(Workbook(root).rows(table.id).count == 1)
  let approvalArgs: Value = .object(["id": .string("app"), "expectedVersion": .number(1)])
  let approvalID = try book.prepareChatApproval(
    action: "app.enable", arguments: approvalArgs, title: "Enable Stock?", conversation: book.startChat)
  let reopened = try Workbook(root)
  try expect(reopened.pendingChatApproval(conversation: reopened.startChat)?.id == approvalID)
  let modelMessage = try book.addMessage("Confirm", role: "assistant")
  try refuses("chat_approval") {
    _ = try book.claimChatApproval(conversation: book.startChat, messageID: modelMessage)
  }
  let anotherChat = try book.createChat()
  let wrongChat = try book.addMessage("Confirm", role: "user", conversation: anotherChat)
  try refuses("chat_approval") {
    _ = try book.claimChatApproval(conversation: book.startChat, messageID: wrongChat)
  }
  let confirmation = try book.addMessage("Confirm", role: "user")
  let claimed = try book.claimChatApproval(conversation: book.startChat, messageID: confirmation)
  try expect(claimed.arguments == approvalArgs)
  try expect(
    Workbook(root).pendingChatApproval(conversation: book.startChat) == nil,
    "Uncertain claimed actions must not replay after reopening")
  try refuses("chat_approval") {
    _ = try book.claimChatApproval(conversation: book.startChat, messageID: confirmation)
  }
  try book.finishChatApproval(
    claimed, conversation: book.startChat, result: .object(["status": .string("enabled")]))
  _ = try book.prepareChatApproval(
    action: "app.enable", arguments: approvalArgs, title: "Enable Stock?", conversation: book.startChat)
  try refuses("chat_approval") {
    _ = try book.claimChatApproval(conversation: book.startChat, messageID: confirmation)
  }
  let cancel = try book.addMessage("Cancel approval", role: "user")
  _ = try book.claimChatApproval(conversation: book.startChat, messageID: cancel, cancel: true)
  try expect(book.pendingChatApproval(conversation: book.startChat) == nil)
  _ = try book.verify()
}
