import CryptoKit
import Foundation
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
      thinking: item.thinking, contextLimit: 65536)
    guard prompt.tokens.count <= 8192 else {
      throw SplashError(
        "Workbook tool prompt uses \(prompt.tokens.count) tokens, over its 8192-token check")
    }
    guard !prompt.tokens.isEmpty else { throw SplashError("Workbook tool prompt is empty") }
  }
  print(
    "PASS \(fixture.cases.count) actual-tool grammars, \(masks) exact reference masks, completed argument validation and prompts"
  )
}
