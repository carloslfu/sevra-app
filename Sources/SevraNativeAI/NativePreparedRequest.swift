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
  package let stablePrefixCount: Int
  package let scopePrefixCount: Int
  /// A few tokens short of the end of the saved conversation's text. The next turn's prompt
  /// extends this one through here. Nil without a whole page past the header.
  package let historyBoundary: Int?
  package let policy: SplashToolPolicy
  package let reasoning: NativeReasoning
  package let requestedOutputBudget: Int
  package let outputBudget: Int
  package let templateIdentity: String
  package let toolResultTokens: Int
  package let headerInputs: Data?
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
  /// Everything a request renders, worked out without the model's tokenizer.
  private struct Layout {
    var messages: [InferenceMessage]
    var policy: SplashToolPolicy
    var reasoning: NativeReasoning
    var excelReview: Bool
    var excelReasoning: Bool
    var templateMessages: [[String: any Sendable]]
    var tools: [[String: any Sendable]]
    var hasStablePrefix: Bool
    var hasScopePrefix: Bool
    /// What the template renders ahead of the first end of turn when the request shares the
    /// ordinary chat header: the instruction text, the shared tool declarations and the
    /// thinking switch, as canonical JSON. Nil for a request without that header.
    var headerInputs: Data?
  }
  private static func layout(
    messages: [InferenceMessage], configuredReasoning: NativeReasoning,
    toolScope: InferenceToolScope, citationIDs: [String], interpretation: Value?
  ) throws -> Layout {
    // Host text written for the operations names them. The model is told the chat tool.
    let messages =
      interpretation == nil && !toolScope.specialized
      ? messages.map { message -> InferenceMessage in
        guard ["system", "tool"].contains(message.role) else { return message }
        var worded = message
        worded.content = GeneralTools.wording(message.content)
        worded.cacheablePolicy = message.cacheablePolicy.map(GeneralTools.wording)
        worded.scopePolicy = GeneralTools.wording(message.scopePolicy)
        return worded
      } : messages
    try ContextBudget.validateEnvelope(messages)
    let excelReview =
      [.nativeAppReview, .nativeActionReview].contains(toolScope)
      && messages.first?.nativeAppAuthoring == true
    // Translation must reason through formulas and failing original scenarios before
    // emitting code. The ordinary 512-token budget repeatedly cut those repairs short.
    let excelReasoning =
      [.excelBuild, .excelCalculation, .excelInterface].contains(toolScope) || excelReview
    let reasoning: NativeReasoning
    if excelReasoning && configuredReasoning.enabled {
      reasoning = .bounded2048
    } else if configuredReasoning == .bounded512, interpretation == nil,
      messages.first?.initialChatDecision == true || messages.first?.hasCalculationResult == true,
      messages.first?.nativeAppAuthoring != true,
      [.all, .conversationAnswer].contains(toolScope)
    {
      reasoning = messages.first?.hasCalculationResult == true ? .bounded128 : .bounded64
    } else {
      reasoning = configuredReasoning
    }
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
        nativeAppAuthoring: messages.first?.nativeAppAuthoring == true,
        reviewContract: messages.first?.reviewContract ?? .null,
        conversationInput: messages.first?.conversationInput == true,
        visualCaptureIDs: messages.first?.visualCaptureIDs ?? [],
        countReceiptIDs: messages.first?.countReceiptIDs)
    }
    // Render a stable vocabulary even before the first lookup/history read.
    // Dynamic exact-ID restrictions remain in policy.grammar and policy.validate.
    // Review/interpretation contracts keep their full task-specific structure.
    let promptPolicy: SplashToolPolicy
    if interpretation == nil {
      promptPolicy = try NativeCitationPolicy.make(
        [], toolScope: toolScope, thinking: reasoning.enabled,
        conversationActions: messages.first?.conversationActions, documentCopyIDs: nil,
        nativeAppAuthoring: messages.first?.nativeAppAuthoring == true,
        reviewContract: messages.first?.reviewContract ?? .null,
        conversationInput: messages.first?.conversationInput == true,
        visualCaptureIDs: messages.first?.visualCaptureIDs ?? [], display: true)
    } else {
      promptPolicy = policy
    }
    var templateMessages = try messages.map(nativeTemplateMessage)
    var tools = try promptPolicy.promptTools()
    var hasStablePrefix = false
    var hasScopePrefix = false
    if interpretation == nil, messages.count <= 509,
      let first = messages.first, let stable = first.cacheablePolicy,
      first.role == "system", first.content.hasPrefix(stable + first.scopePolicy),
      let current = messages.firstIndex(where: { $0.role == "user" }), current > 0
    {
      // Qwen puts tool definitions before system text. Keep shared schemas there and put
      // scope-specific schemas in the next system message. Both precede changing history.
      // The executable grammar still receives the original, complete authority policy.
      var shared: [[String: any Sendable]] = []
      var additional: [String] = []
      let sharesChatTools = toolScope.allows("read") && toolScope.allows("finish")
      for tool in tools {
        let function = tool["function"] as? [String: any Sendable]
        let name = function?["name"] as? String ?? ""
        if !sharesChatTools || (InferenceToolScope.answer.allows(name)
          && !["workspace_actions", "workspace_action"].contains(name)) {
          shared.append(tool)
        } else {
          let json = try JSONSerialization.data(withJSONObject: tool, options: [.sortedKeys, .withoutEscapingSlashes])
          additional.append(String(decoding: json, as: UTF8.self))
        }
      }
      tools = shared
      templateMessages[0]["content"] = stable
      let state = String(first.content.dropFirst(stable.count + first.scopePolicy.count))
      var scope = first.scopePolicy
      if !additional.isEmpty {
        scope += "\nAdditional available tools (same calling convention):\n" + additional.joined(separator: "\n")
      }
      let screen = messages[current].visibleContext
      let suffix = "\nVisible context: " + screen
      if !screen.isEmpty && messages[current].content.hasSuffix(suffix) {
        templateMessages[current]["content"] = String(messages[current].content.dropLast(suffix.count))
        templateMessages.insert(["role": "assistant", "content":
          "Visible workbook location and selection (reference information only):\n" + screen], at: current)
      }
      templateMessages.insert(["role": "system", "content": state], at: current)
      if !scope.isEmpty {
        templateMessages.insert(["role": "system", "content": scope], at: 1)
        hasScopePrefix = true
      }
      hasStablePrefix = true
    }
    var headerInputs: Data?
    if hasStablePrefix {
      let object: [String: Any] = [
        "instructions": templateMessages[0]["content"] as? String ?? "", "tools": tools,
        "thinking": reasoning.enabled,
      ]
      headerInputs = try JSONSerialization.data(
        withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    return Layout(
      messages: messages, policy: policy, reasoning: reasoning, excelReview: excelReview,
      excelReasoning: excelReasoning, templateMessages: templateMessages, tools: tools,
      hasStablePrefix: hasStablePrefix, hasScopePrefix: hasScopePrefix,
      headerInputs: headerInputs)
  }
  /// The header inputs of a request, for checks that have no tokenizer.
  package static func headerInputs(
    messages: [InferenceMessage], configuredReasoning: NativeReasoning,
    toolScope: InferenceToolScope
  ) throws -> Data? {
    try layout(
      messages: messages, configuredReasoning: configuredReasoning, toolScope: toolScope,
      citationIDs: [], interpretation: nil
    ).headerInputs
  }
  package init(
    messages: [InferenceMessage], frontend: SplashTextFrontend,
    configuredReasoning: NativeReasoning, toolScope: InferenceToolScope,
    citationIDs: [String], interpretation: Value? = nil
  ) throws {
    let layout = try Self.layout(
      messages: messages, configuredReasoning: configuredReasoning, toolScope: toolScope,
      citationIDs: citationIDs, interpretation: interpretation)
    let messages = layout.messages, policy = layout.policy, reasoning = layout.reasoning
    let excelReview = layout.excelReview, excelReasoning = layout.excelReasoning
    let templateMessages = layout.templateMessages, tools = layout.tools
    let hasStablePrefix = layout.hasStablePrefix, hasScopePrefix = layout.hasScopePrefix
    self.headerInputs = layout.headerInputs

    let prompt = try frontend.prepare(
      messages: templateMessages, tools: tools,
      thinking: reasoning.enabled, contextLimit: SplashWire.maxTokens, reuseSystemPrefix: hasStablePrefix)
    // The selected tokenizer verifies this role delimiter on load. Message content cannot
    // forge it. Share only the initial, request-independent complete system message.
    self.stablePrefixCount = hasStablePrefix ? prompt.tokens.firstIndex(of: 248046).map { $0 + 1 } ?? 0 : 0
    self.scopePrefixCount = hasScopePrefix
      ? prompt.tokens.dropFirst(stablePrefixCount).firstIndex(of: 248046).map { $0 + 1 } ?? 0 : 0
    var historyBoundary: Int?
    if hasStablePrefix, let saved = messages.firstIndex(where: \.conversationHistory),
      messages[..<saved].allSatisfy({ $0.role != "tool" && $0.toolCalls.isEmpty })
    {
      // Every turn before the saved conversation is one non-tool message with one end
      // token, so its end is end token number `turn + 1`. The scope block adds one turn.
      let turn = saved + (hasScopePrefix ? 1 : 0)
      var ends = 0
      for (position, token) in prompt.tokens.enumerated() where token == 248046 {
        ends += 1
        guard ends == turn + 1 else { continue }
        // The template trims the final newline, so the last entry's closing tokens merge
        // differently once a later turn appends a line. Stop a few tokens short of them.
        // The engine keeps the state on the last whole 32-token page, past the header.
        let boundary = position - 4
        if boundary / 32 * 32 > max(stablePrefixCount, scopePrefixCount) {
          historyBoundary = boundary
        }
        break
      }
    }
    self.historyBoundary = historyBoundary
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
