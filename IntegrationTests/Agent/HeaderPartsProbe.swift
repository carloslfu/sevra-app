import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash
import SevraSplashText

/// What the prepared chat header holds, in tokens. No model: only the selected pack's
/// tokenizer and chat template are loaded.
///
/// A tool's count is what the chat template adds for it beside the other tools, and an
/// instruction line's count is that line alone. The parts add up to the header within the
/// template's own framing. A second path receives the header's inputs as JSON.
func runHeaderPartsProbe(modelsRoot: String, inputs: String? = nil) throws {
  if let inputs {
    // The header's text as the app serializes it, to read beside the counts.
    try PromptHeader.inputs(reasoning: .bounded512).write(to: URL(fileURLWithPath: inputs))
  }
  let assembly = try SplashModelPreparation.installed(
    pack: SplashModelPack.selected(), modelsRoot: URL(fileURLWithPath: modelsRoot))
  let frontend = try SplashTextFrontend(modelFolder: assembly.appendingPathComponent("tokenizer"))
  let reasoning = NativeReasoning.bounded512
  let system = PromptHeader.ordinaryMessages[0]
  let tools = try NativeCitationPolicy.make(
    [], toolScope: .all, thinking: reasoning.enabled, documentCopyIDs: nil,
    nativeAppAuthoring: system.nativeAppAuthoring, reviewContract: system.reviewContract,
    conversationInput: system.conversationInput, visualCaptureIDs: system.visualCaptureIDs,
    display: true
  ).promptTools()
  let base: [[String: any Sendable]] = [
    ["role": "system", "content": "Rules."], ["role": "user", "content": "Question."],
  ]
  func count(_ list: [[String: any Sendable]]) throws -> Int {
    try frontend.prepare(
      messages: base, tools: list.isEmpty ? nil : list, thinking: reasoning.enabled,
      contextLimit: SplashWire.maxTokens
    ).tokens.count
  }
  let all = try count(tools)
  var rows: [[String: Any]] = []
  var listed = 0
  for (index, tool) in tools.enumerated() {
    var rest = tools
    rest.remove(at: index)
    let tokens = all - (try count(rest))
    listed += tokens
    let json = try JSONSerialization.data(
      withJSONObject: tool, options: [.sortedKeys, .withoutEscapingSlashes])
    let function = tool["function"] as? [String: any Sendable]
    rows.append([
      "name": function?["name"] as? String ?? "", "tokens": tokens, "bytes": json.count,
      "descriptionTokens": frontend.encode(function?["description"] as? String ?? "").count,
    ])
  }
  let lines = system.content.components(separatedBy: "\n").map { line -> [String: Any] in
    ["tokens": frontend.encode(line + "\n").count, "starts": String(line.prefix(48))]
  }
  let output: [String: Any] = [
    "header": try PromptHeader.tokens(frontend: frontend, reasoning: reasoning).count,
    "instructions": frontend.encode(system.content).count,
    "instructionLines": lines,
    "tools": rows,
    "toolFraming": all - (try count([])) - listed,
  ]
  FileHandle.standardOutput.write(
    try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .prettyPrinted]))
  print()
}
