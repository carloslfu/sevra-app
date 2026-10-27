import Foundation
import SevraAI
import SevraCore

extension WorkbookAgent {
  public static func run(
    _ prompt: String, workbook: Workbook, conversation: String = "main", context: String = "",
    modelDirectory: URL = LocalModel.defaultDirectory, cancellation: Cancellation = .init(),
    progress: @escaping @Sendable (String) -> Void = { _ in }
  ) async throws -> AgentResult {
    try await run(
      prompt, workbook: workbook, conversation: conversation, context: context,
      modelDirectory: modelDirectory, cancellation: cancellation, progress: progress,
      model: LocalModel.shared)
  }

}
