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
        /// Each draft token's parent: the first's is `SplashWire.noParent`, the others earlier.
        let parents: [UInt32]
        let maskSHA256: String
        let forced: [UInt32]
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
  // Without app authoring, chat can read the app guide but cannot save an app.
  let ordinary = try SplashToolPolicy(
    toolsJSON: NativeTools.serializedDefinitions(nativeAppAuthoring: false), choice: .required,
    thinking: false)
  let ordinaryPrompt = try frontend.prepare(
    messages: [["role": "user", "content": "Read the workbook."]], tools: ordinary.promptTools(),
    thinking: false, contextLimit: 32768)
  guard ordinaryPrompt.tokens.count <= 8448 else {
    throw SplashError(
      "Ordinary tool prompt uses \(ordinaryPrompt.tokens.count) tokens, over its 8448-token check")
  }
  let ordinaryTools = try NativeTools.referenceDefinitions(nativeAppAuthoring: false)
  try expectEqual(ordinaryTools.map(\.name), GeneralTools.names.filter { $0 != "ask" })
  let save = try expectValue(ordinaryTools.first { $0.name == "save" })
  try expectEqual(save.parameters["properties"]["app"], .null)
  let read = try expectValue(ordinaryTools.first { $0.name == "read" })
  try expectEqual(
    read.parameters["properties"]["kind"]["enum"].array.contains(.string("app_guide")), true)
  let layoutPolicy = try SplashToolPolicy(
    toolsJSON: NativeTools.serializedDefinitions(nativeAppAuthoring: false),
    choice: .named("run"), thinking: false)
  let component = #""component":{"id":"stock","type":"app","title":"Stock","spaceID":"app-id"}"#
  for (edit, allowed) in [
    (#"{"operation":"insert","at":"last","# + component + "}", true),
    (#"{"operation":"insert","beforeID":"continue","# + component + "}", true),
    (#"{"operation":"reset"}"#, true),
    (#"{"operation":"title","componentID":"stock","title":"Renamed"}"#, true),
    (#"{"operation":"insert","# + component + #", "title":"Stock"}"#, false),
    (#"{"operation":"insert","at":"last","# + component + #", "title":"Stock"}"#, false),
    (#"{"operation":"reset","title":"Stock"}"#, false),
    // Only a visual or an image takes visual.
    (#"{"operation":"insert","at":"last","component":{"id":"v","type":"visual","title":"V","visual":{}}}"#, true),
    (#"{"operation":"insert","at":"last","component":{"id":"b","type":"button","title":"B","visual":{}}}"#, false),
  ] {
    let tokens = frontend.encode(
      "<tool_call>\n<function=run>\n<parameter=action>\n"
        + #"{"name":"view.edit","arguments":{"id":"home","expectedVersion":1,"edits":["#
        + edit + "]}}\n</parameter>\n</function>\n</tool_call>")
    let grammar = try factory.create(grammar: layoutPolicy.grammar)
    if allowed {
      try grammar.finish(committed: tokens, requireComplete: true)
    } else {
      try expectThrows(try grammar.finish(committed: tokens, requireComplete: true))
    }
  }
  print("PASS layout grammar keeps insert labels in components, refuses fields from other edits and a visual on a button")
  // A button keeps its tool binding after other components, including ones with a query, so
  // a view retried after an error can bind its button again.
  do {
    let savePolicy = try SplashToolPolicy(
      toolsJSON: NativeTools.serializedDefinitions(nativeAppAuthoring: false),
      choice: .named("save"), thinking: false)
    let button = #"{"id":"button1","type":"button","title":"Add","definitionBinding":{"tool":"add_expense"},"size":"medium"}"#
    let queryTable = #"{"id":"t1","type":"table","title":"E","datasetID":"e426","query":"SELECT 1 as a"}"#
    let queryMetric = #"{"id":"m1","type":"metric","title":"Total","datasetID":"e426","query":"SELECT 1 as total","y":"total","size":"medium"}"#
    for comps in [button, queryTable + "," + queryMetric + "," + button] {
      let tokens = frontend.encode(
        "<tool_call>\n<function=save>\n<parameter=view>\n"
          + #"{"title":"T","definition":{"version":1,"components":["# + comps + #"]}}"#
          + "\n</parameter>\n</function>\n</tool_call>")
      try factory.create(grammar: savePolicy.grammar).finish(committed: tokens, requireComplete: true)
    }
  }
  print("PASS save grammar keeps a button's tool binding after query components")
  for item in fixture.cases {
    let choice: SplashToolPolicy.Choice =
      item.choice == "named_finish" ? .named("finish") : item.choice == "auto" ? .auto : .required
    let policy = try SplashToolPolicy(toolsJSON: tools, choice: choice, thinking: item.thinking)
    let constraint = try factory.create(grammar: policy.grammar)
    try expectEqual(frontend.encode(item.output), item.tokens)
    for (index, step) in item.steps.enumerated() {
      let reply = try constraint.masks(
        .init(
          committed: step.committed, simulation: step.simulation, parents: step.parents,
          words: (SplashTextFrontend.vocabularySize + 31) / 32))
      let actual = reply.words
      guard reply.forced == step.forced else {
        throw SplashError("Workbook grammar forced tokens differ: \(item.name) step \(index)")
      }
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
