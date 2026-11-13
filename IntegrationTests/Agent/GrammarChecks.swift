import CryptoKit
import Foundation
import SevraAI
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

func checkWorkbookGrammars(frontend: SplashTextFrontend, factory: SplashGrammarFactory) throws {
  struct Fixture: Decodable {
    struct Case: Decodable {
      struct Step: Decodable {
        let committed: [UInt32]
        let simulation: [UInt32]
        let maskSHA256: String
      }
      let name: String
      let choice: String
      let thinking: Bool
      let output: String
      let tokens: [UInt32]
      let steps: [Step]
    }
    let toolsSHA256: String
    let cases: [Case]
  }
  let tools = try Data(
    contentsOf: Bundle.module.url(forResource: "workbook-tools", withExtension: "json")!)
  let fixture = try JSONDecoder().decode(
    Fixture.self,
    from: Data(
      contentsOf:
        Bundle.module.url(forResource: "tool-grammar-fixtures", withExtension: "json")!))
  guard SHA256.hash(data: tools).map({ String(format: "%02x", $0) }).joined() == fixture.toolsSHA256
  else {
    throw SplashError("Workbook tool fixtures do not match their declaration bytes")
  }
  var masks = 0
  var largestPrompt = 0
  // Only SDK/source discovery is offered in ordinary chat. The detailed save/test
  // schema becomes available after the host enters authoring mode.
  let ordinary = try SplashToolPolicy(
    toolsJSON: NativeTools.serializedDefinitions(nativeAppAuthoring: false), choice: .required,
    thinking: false)
  let ordinaryPrompt = try frontend.prepare(
    messages: [["role": "user", "content": "Read the workbook."]], tools: ordinary.promptTools(),
    thinking: false, contextLimit: 32768)
  try expectEqual(ordinaryPrompt.tokens.count <= 8448, true)
  let ordinaryNames = try NativeTools.referenceDefinitions(nativeAppAuthoring: false).map(\.name)
  try expectEqual(ordinaryNames.contains("save_native_app"), false)
  try expectEqual(ordinaryNames.contains("native_app_sdk"), true)
  for item in fixture.cases {
    let choice: SplashToolPolicy.Choice =
      item.choice == "named_finish" ? .named("finish") : item.choice == "auto" ? .auto : .required
    let policy = try SplashToolPolicy(toolsJSON: tools, choice: choice, thinking: item.thinking)
    let constraint = try factory.create(grammar: policy.grammar)
    try expectEqual(frontend.encode(item.output), item.tokens)
    for (index, step) in item.steps.enumerated() {
      let actual = try constraint.masks(
        committed: step.committed, simulation: step.simulation,
        words: (SplashTextFrontend.vocabularySize + 31) / 32)
      let hash = actual.withUnsafeBytes {
        SHA256.hash(data: Data($0)).map { String(format: "%02x", $0) }.joined()
      }
      guard hash == step.maskSHA256 else {
        throw SplashError("Workbook grammar differs: \(item.name) step \(index)")
      }
      masks += 1
    }
    try constraint.finish(committed: item.tokens, requireComplete: true)
    let stream = try SplashOutputStream(
      frontend: frontend, tools: policy.outputTools, thinking: item.thinking)
    _ = try stream.append(tokens: item.tokens)
    let output = try stream.finish(.stop).0
    if item.choice != "auto" { try expectEqual(output.calls.count, 1) }
    for call in output.calls { try policy.validate(call) }
    let prompt = try frontend.prepare(
      messages: [["role": "user", "content": "Read the workbook."]], tools: policy.promptTools(),
      thinking: item.thinking, contextLimit: 32768)
    largestPrompt = max(largestPrompt, prompt.tokens.count)
    guard prompt.tokens.count <= 10240 else {
      throw SplashError(
        "Authoring tool prompt uses \(prompt.tokens.count) tokens, over its 10240-token check")
    }
    guard !prompt.tokens.isEmpty else { throw SplashError("Workbook tool prompt is empty") }
  }
  print(
    "PASS \(fixture.cases.count) actual-tool grammars, \(masks) exact reference masks, completed argument validation; ordinary prompt \(ordinaryPrompt.tokens.count)/8448, authoring \(largestPrompt)/10240 tokens"
  )
}
