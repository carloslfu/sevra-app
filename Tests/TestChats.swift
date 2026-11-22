import Foundation
@testable import SevraCore

/// Checks work in the chat a new workbook starts with unless they name another chat. These
/// overloads exist only for checks; the app and the agent always name the chat.
extension Workbook {
  /// The chat a new workbook starts with, which stays first by row order.
  var startChat: String {
    (try? synchronized {
      try db.scalar("SELECT id FROM conversations ORDER BY rowid LIMIT 1")
    })?.text ?? ""
  }
  @discardableResult func addMessage(
    _ body: String, role: String, state: String = "complete", payload: Value = .null
  ) throws -> String {
    try addMessage(body, role: role, conversation: startChat, state: state, payload: payload)
  }
  func messages(limit: Int = 100, beforeMessage: String? = nil) throws -> [Message] {
    try messages(conversation: startChat, limit: limit, beforeMessage: beforeMessage)
  }
  func historySlice(
    after: String? = nil, through: String? = nil, limit: Int = 200,
    byteLimit: Int = 2 * 1024 * 1024, cancellation: Cancellation = .init()
  ) throws -> HistorySlice {
    try historySlice(
      conversation: startChat, after: after, through: through, limit: limit,
      byteLimit: byteLimit, cancellation: cancellation)
  }
  func historyMessage(_ id: String) throws -> Message {
    try historyMessage(id, conversation: startChat)
  }
  func messagePayload(_ id: String) throws -> Value {
    try messagePayload(id, conversation: startChat)
  }
  func readHistoryEvidence(_ id: String, beforeMessage: String? = nil) throws -> Value {
    try readHistoryEvidence(id, conversation: startChat, beforeMessage: beforeMessage)
  }
  func searchHistory(
    _ query: String, cursor: String? = nil, limit: Int = 30, beforeMessage: String? = nil,
    cancellation: Cancellation = .init(), visibleOnly: Bool = false
  ) throws -> Value {
    try searchHistory(
      query, conversation: startChat, cursor: cursor, limit: limit,
      beforeMessage: beforeMessage, cancellation: cancellation, visibleOnly: visibleOnly)
  }
  func contextCheckpoints(limit: Int = 20) throws -> [Value] {
    try contextCheckpoints(conversation: startChat, limit: limit)
  }
  func contextCheckpoint(_ id: String) throws -> Value {
    try contextCheckpoint(id, conversation: startChat)
  }
  func toolCall(_ id: String) throws -> Value { try toolCall(id, conversation: startChat) }
  func unresolvedToolCalls(limit: Int = 8) throws -> [Value] {
    try unresolvedToolCalls(conversation: startChat, limit: limit)
  }
  func toolResultPage(
    _ id: String, path: [String] = [], offset: Int = 0, rawJSON: Bool = false,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try toolResultPage(
      id, conversation: startChat, path: path, offset: offset, rawJSON: rawJSON,
      cancellation: cancellation)
  }
  func documentCopyChoice(_ id: String, runID: String, cancellation: Cancellation = .init())
    throws -> DocumentCopy
  {
    try documentCopyChoice(id, runID: runID, conversation: startChat, cancellation: cancellation)
  }
  func documentCopy(
    receiptID: String, path: [String], startScalar: Int, scalarCount: Int, runID: String,
    cancellation: Cancellation = .init()
  ) throws -> DocumentCopy {
    try documentCopy(
      receiptID: receiptID, path: path, startScalar: startScalar, scalarCount: scalarCount,
      runID: runID, conversation: startChat, cancellation: cancellation)
  }
  func saveComposedDraft(
    title: String, parts: [DocumentPart], inputs: [String] = [], runID: String,
    token: String = identifier(), expectedRevision: Int? = nil,
    cancellation: Cancellation = .init()
  ) throws -> Item {
    try saveComposedDraft(
      title: title, parts: parts, inputs: inputs, runID: runID, conversation: startChat,
      token: token, expectedRevision: expectedRevision, cancellation: cancellation)
  }
}

extension WorkbookTools {
  init(
    _ workbook: Workbook, runID: String = identifier(), cancellation: Cancellation = .init(),
    requestSourceID: String? = nil, readOnly: Bool = false,
    excelConversion: ExcelConversionBuild? = nil
  ) {
    self.init(
      workbook, runID: runID, cancellation: cancellation, requestSourceID: requestSourceID,
      conversation: workbook.startChat, readOnly: readOnly, excelConversion: excelConversion)
  }
}
