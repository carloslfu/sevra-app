import Foundation
import SevraAI
import SevraCore
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

/// One rendering path for measurement and dispatch, including all host schema metadata.
/// Generation dispatches these exact tokens after admission; it never renders again.
package struct NativePreparedRequest {
  package let prompt: SplashTextFrontend.Prompt
  package let policy: SplashToolPolicy
  package let reasoning: NativeReasoning
  package let requestedOutputBudget: Int
  package let outputBudget: Int
  package let templateIdentity: String
  package let toolResultTokens: Int
  package static func toolResultReserve(
    frontend: SplashTextFrontend, toolScope: InferenceToolScope, nativeAppAuthoring: Bool
  ) throws -> Int {
    guard nativeAppAuthoring || toolScope.allows("native_app_sdk") else { return 2048 }
    // Preserve the complete SDK/testing contract when the next permitted result
    // may supply it. A fixed 2K projection made authoring proceed with a partial guide.
    let sdk = try Value.object([
      "guide": .string(NativeAppAuthoring.guide), "sdkVersion": .number(1),
    ]).json()
    let count = try resultTokens(sdk, frontend: frontend)
    try require(count <= 8192, "context_limit", "The SDK guide exceeds its declared result budget.")
    return max(2048, count)
  }
  package static func resultTokens(_ json: String, frontend: SplashTextFrontend) throws -> Int {
    try frontend.prepare(
      messages: [
        ["role": "user", "content": ""],
        ["role": "tool", "content": json],
      ], contextLimit: SplashWire.maxTokens
    ).tokens.count
  }
  package init(
    messages: [InferenceMessage], frontend: SplashTextFrontend,
    configuredReasoning: NativeReasoning, toolScope: InferenceToolScope,
    citationIDs: [String], interpretation: Value? = nil
  ) throws {
    try ContextBudget.validateEnvelope(messages)
    let excelReview =
      [.nativeAppReview, .nativeActionReview].contains(toolScope)
      && messages.first?.nativeAppAuthoring == true
    // Translation must reason through formulas and failing original scenarios before
    // emitting code. The ordinary 512-token budget repeatedly cut those repairs short.
    let excelReasoning =
      [.excelBuild, .excelCalculation, .excelInterface].contains(toolScope) || excelReview
    let reasoning =
      excelReasoning && configuredReasoning.enabled
      ? NativeReasoning.bounded2048 : configuredReasoning
    let policy: SplashToolPolicy
    if let interpretation {
      policy = try SplashToolPolicy.interpretationResult(
        schemaJSON: Data(interpretation["schema"].json().utf8), thinking: reasoning.enabled)
    } else {
      policy = try NativeCitationPolicy.make(
        citationIDs, toolScope: toolScope, thinking: reasoning.enabled,
        itemReferenceIDs: ItemReferenceCandidates.ids(in: messages),
        conversationActions: messages.first?.conversationActions,
        documentCopyIDs: DocumentCopyCandidates.ids(in: messages),
        historyReferenceIDs: ItemReferenceCandidates.historyIDs(in: messages),
        nativeAppAuthoring: messages.first?.nativeAppAuthoring == true,
        reviewContract: messages.first?.reviewContract ?? .null,
        conversationInput: messages.first?.conversationInput == true,
        visualCaptureIDs: messages.first?.visualCaptureIDs ?? [])
    }
    let prompt = try frontend.prepare(
      messages: messages.map(nativeTemplateMessage), tools: policy.promptTools(),
      thinking: reasoning.enabled, contextLimit: SplashWire.maxTokens)
    let requestedOutputBudget =
      interpretation?["maxOutputTokens"].int
      ?? (excelReview
        ? 4096 : excelReasoning || messages.first?.nativeAppAuthoring == true ? 8192 : 1800)
    // Preserve P1's effective interpretation ceiling; a larger one needs its own comparison.
    let outputBudget =
      interpretation == nil ? requestedOutputBudget : min(1800, requestedOutputBudget)
    self.requestedOutputBudget = requestedOutputBudget
    try require((256...8192).contains(outputBudget), "context_limit", "Invalid response budget.")
    _ = try reasoning.budget(outputTokens: outputBudget)
    self.prompt = prompt
    self.policy = policy
    self.reasoning = reasoning
    self.outputBudget = outputBudget
    self.templateIdentity = frontend.templateIdentity
    self.toolResultTokens =
      interpretation == nil
      ? try Self.toolResultReserve(
        frontend: frontend, toolScope: toolScope,
        nativeAppAuthoring: messages.first?.nativeAppAuthoring == true) : 2048
  }
  package func measurement(capacity: Int) -> ContextMeasurement {
    .init(
      promptTokens: prompt.tokens.count, capacity: capacity,
      templateIdentity: templateIdentity, outputTokens: outputBudget,
      toolResultTokens: toolResultTokens)
  }
}
