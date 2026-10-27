import Foundation
import SevraAI
import SevraCore

private actor AdmissionModel: WorkbookInference {
  let identity = "Synthetic request admission"
  let lastMetrics: Value = .null
  let rejectsLease: Bool
  var begins = 0
  var ends = 0
  var captured: [InferenceMessage] = []
  init(rejectsLease: Bool = false) { self.rejectsLease = rejectsLease }
  func beginRun() throws {
    begins += 1
    if rejectsLease { throw SevraError("model_busy", "Synthetic model lease is held elsewhere.") }
  }
  func endRun() { ends += 1 }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    captured = messages
    return NativeReply(
      text: "",
      calls: [
        .init(
          id: "ready", name: "finish",
          inputJSON: "{\"answer\":\"Ready\",\"basis\":\"general\",\"citations\":[]}")
      ])
  }
}

func checkRequestAdmission() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-admission-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(
    at: root.appendingPathComponent("Recovery.sevra"), title: "Recovery")
  let oldPrompt = "Make a draft titled Abandoned instruction sentinel."
  let oldMessage = try book.addMessage(oldPrompt, role: "user")
  let oldRun = try book.startAgentRun(
    conversation: "main", model: "abandoned", requestMessageID: oldMessage)
  let basis = try book.addItem(
    category: "source", kind: "request", title: "Original request", text: oldPrompt, meaning: "plan"
  )
  let arguments: Value = .object([
    "title": .string("Already saved draft"), "text": .string("Saved before process death."),
    "inputs": .array([.string(basis.id)]),
  ])
  let uncertain = try book.prepareToolCall(
    runID: oldRun, callID: "uncertain", tool: "draft", arguments: arguments)
  _ = try WorkbookTools(book, runID: oldRun).execute("draft", arguments)
  let savedDrafts = try book.items(kind: "document")
  let model = AdmissionModel()
  let result = try await WorkbookAgent.run(
    "Reply Ready. Do not change the workbook.", workbook: book, model: model)
  let projected = await model.captured.filter { $0.role == "assistant" }.map(\.content).joined(
    separator: "\n")
  let closedBeforeProjection =
    !projected.contains(oldPrompt) && projected.contains("status interrupted")
  try expectEqual(try book.requestRunStatus(oldMessage), "interrupted")
  try expectEqual(try book.historyMessage(oldMessage).body, oldPrompt)
  try expectEqual(result.answer, "Ready")
  try expectEqual(await model.ends, 1)
  try expectEqual(await model.captured.filter { $0.role == "user" }.count, 1)
  try expectEqual(try book.items(kind: "document"), savedDrafts)
  try expectEqual(projected.contains(uncertain) && projected.contains("committedOperation"), true)

  let busyBook = try Workbook.create(at: root.appendingPathComponent("Busy.sevra"), title: "Busy")
  let liveMessage = try busyBook.addMessage("Existing live request", role: "user")
  let liveRun = try busyBook.startAgentRun(
    conversation: "main", model: "live", requestMessageID: liveMessage)
  let busyModel = AdmissionModel(rejectsLease: true)
  do {
    _ = try await WorkbookAgent.run(
      "Rejected request sentinel", workbook: busyBook, model: busyModel)
    throw SevraError("fixture", "Busy model accepted work")
  } catch let error as SevraError { try expectEqual(error.code, "model_busy") }
  let rejected = try expectValue(
    busyBook.messages().first { $0.body == "Rejected request sentinel" })
  let rejectionRecorded =
    try busyBook.requestRunStatus(rejected.id) == "failed"
    && busyBook.messages().last?.state == "failed"
  try expectEqual(try busyBook.requestRunStatus(liveMessage), "running")
  try expectEqual(await busyModel.ends, 0)
  try expectEqual(await busyModel.captured.isEmpty, true)
  let rejectedHistory = try WorkbookAgent.conversationHistory(busyBook, conversation: "main")
    .map(\.content).joined(separator: "\n")
  try expectEqual(rejectedHistory.contains("Rejected request sentinel"), false)

  let cancelledModel = AdmissionModel()
  let cancelled = Cancellation()
  cancelled.cancel(reason: "Stopped before model acquisition")
  do {
    _ = try await WorkbookAgent.run(
      "Cancelled before starting", workbook: busyBook, cancellation: cancelled,
      model: cancelledModel)
    throw SevraError("fixture", "Cancelled request acquired a model")
  } catch let error as SevraError {
    try expectEqual(error.code, "cancelled")
    try expectEqual(error.message, "Stopped before model acquisition")
  }
  try expectEqual(await cancelledModel.begins, 0)
  try expectEqual(await cancelledModel.ends, 0)
  let cancelledMessage = try expectValue(
    busyBook.messages().first { $0.body == "Cancelled before starting" })
  try expectEqual(try busyBook.requestRunStatus(cancelledMessage.id), "cancelled")
  try expectEqual(try busyBook.requestRunStatus(liveMessage), "running")

  let revision = try busyBook.revision()
  let messagesBeforeFailure = try busyBook.messages()
  let runsBeforeFailure = try busyBook.agentRuns()
  let invalidModel = AdmissionModel()
  do {
    _ = try await WorkbookAgent.run(
      "Invalid conversation must roll back", workbook: busyBook, conversation: "missing",
      model: invalidModel)
    throw SevraError("fixture", "Invalid request was admitted")
  } catch let error as SevraError { try expectEqual(error.code == "fixture", false) }
  try expectEqual(await invalidModel.ends, 1)
  try expectEqual(await invalidModel.captured.isEmpty, true)
  try expectEqual(try busyBook.revision(), revision)
  try expectEqual(try encoded(busyBook.messages()), encoded(messagesBeforeFailure))
  try expectEqual(try busyBook.agentRuns(), runsBeforeFailure)
  let admitted = try busyBook.startAgentRequest(
    "Current boundary", conversation: "main", model: "fixture")
  try expectEqual(try busyBook.revision(), revision + 1)
  try expectEqual(try busyBook.requestRunStatus(admitted.messageID), "running")
  try expectEqual(try busyBook.requestRunStatus(liveMessage), "interrupted")
  _ = try busyBook.addMessage("Later request is not earlier context", role: "user")
  let bounded = try busyBook.messages(beforeMessage: admitted.messageID)
  try expectEqual(try encoded(bounded), encoded(messagesBeforeFailure))
  let tangent = try busyBook.tangent(title: "Other conversation", parentMessage: liveMessage)
  try expectThrows(try busyBook.messages(conversation: tangent, beforeMessage: admitted.messageID))
  try expectThrows(try busyBook.messages(beforeMessage: "missing"))
  try expectEqual(try book.verify()["ok"], .bool(true))
  try expectEqual(try busyBook.verify()["ok"], .bool(true))
  print(
    try Value.object([
      "check": .string("request_admission"),
      "abandonedRunClosedBeforeProjection": .bool(closedBeforeProjection),
      "failedLeaseHasLinkedTerminalRequest": .bool(rejectionRecorded),
      "activeOtherRunPreserved": .bool(true),
      "oldRun": .string(oldRun), "liveRun": .string(liveRun),
    ]).json())
  try expectEqual(closedBeforeProjection, true)
  try expectEqual(rejectionRecorded, true)
  print(
    "PASS abandoned-run projection and terminal lease-refusal history preserve originals and active work"
  )
  print(
    "PASS atomic request/run writes roll back together, release acquired leases on failure and bound earlier history"
  )
}
