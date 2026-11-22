import Foundation
import SevraAI
import SevraCore

/// Checks ask in the chat a new workbook starts with unless they name another chat.
extension WorkbookAgent {
  static func run(
    _ prompt: String, workbook: Workbook, context: String = "",
    modelDirectory: URL = FileManager.default.temporaryDirectory,
    cancellation: Cancellation = .init(),
    progress: @escaping @Sendable (String) -> Void = { _ in },
    answerPreview: @escaping @Sendable (AnswerPreview) -> Void = { _ in },
    model: any WorkbookInference,
    enableCompaction: Bool = true,
    requestStarted: @escaping @Sendable (AgentRequest, String) -> Void = { _, _ in },
    openSpace: SpaceOpener? = nil,
    openReviews: ReviewQueueOpener? = nil,
    workspaceAction: WorkspaceActionHandler? = nil,
    excelConversion: ExcelConversionBuild? = nil,
    conversationInput: Bool = false, inputAnswerID: String? = nil
  ) async throws -> AgentResult {
    try await run(
      prompt, workbook: workbook, conversation: workbook.startChat, context: context,
      modelDirectory: modelDirectory, cancellation: cancellation, progress: progress,
      answerPreview: answerPreview, model: model, enableCompaction: enableCompaction,
      requestStarted: requestStarted, openSpace: openSpace, openReviews: openReviews,
      workspaceAction: workspaceAction, excelConversion: excelConversion,
      conversationInput: conversationInput, inputAnswerID: inputAnswerID)
  }
}
