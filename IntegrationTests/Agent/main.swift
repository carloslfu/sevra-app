import CryptoKit
import Foundation
import SevraAI
import SevraNativeAI
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

final class ToolPolicyChecks {
  func actualTools() throws -> Data {
    let definitions: [[String: Any]] = try NativeTools.definitions.map {
      [
        "type": "function",
        "function": [
          "name": $0.name, "description": $0.description,
          "parameters": try JSONSerialization.jsonObject(with: Data($0.parameters.jsonText.utf8)),
        ],
      ]
    }
    return try JSONSerialization.data(
      withJSONObject: definitions, options: [.sortedKeys, .withoutEscapingSlashes])
  }

  func testActualWorkbookSchemas() throws {
    let policy = try SplashToolPolicy(toolsJSON: actualTools())
    try expectEqual(policy.outputTools.count, NativeTools.definitions.count)
    let normalized = try JSONSerialization.jsonObject(with: policy.toolsJSON) as! [[String: Any]]
    func function(_ name: String) -> [String: Any] {
      (normalized.first { ($0["function"] as! [String: Any])["name"] as? String == name }![
        "function"] as! [String: Any])
    }
    let fields = function("propose_table")["parameters"] as! [String: Any]
    let properties = fields["properties"] as! [String: Any]
    let rows = properties["rows"] as! [String: Any]
    let item = rows["items"] as! [String: Any]
    try expectEqual(item["additionalProperties"] as? Bool, true)
    try expectEqual(fields["additionalProperties"] as? Bool, false)
    let export = ProcessInfo.processInfo.environment["SEVRA_SCHEMA_FIXTURE_OUTPUT"]
    if let export {
      try policy.toolsJSON.write(to: URL(fileURLWithPath: export), options: .atomic)
    } else {
      let stored = try Data(
        contentsOf: Bundle.module.url(forResource: "workbook-tools", withExtension: "json")!)
      try expectEqual(policy.toolsJSON, stored)
    }
    let prompt = try policy.promptTools()
    try expectEqual(prompt.count, NativeTools.definitions.count)
  }

  func candidate(_ name: String, _ fields: [(String, String)], policy: SplashToolPolicy) throws
    -> SplashToolCandidate
  {
    let parser = try SplashOutputParser(tools: policy.outputTools)
    let body = fields.map { "<parameter=\($0.0)>\n\($0.1)\n</parameter>\n" }.joined()
    _ = try parser.append("<tool_call>\n<function=\(name)>\n" + body + "</function>\n</tool_call>")
    return try expectValue(parser.finish(.stop).0.calls.first)
  }

  func testWorkbookArguments() throws {
    let policy = try SplashToolPolicy(toolsJSON: actualTools())
    try policy.validate(candidate("datasets", [], policy: policy))
    try policy.validate(
      candidate(
        "propose_table",
        [
          ("title", "Suppliers"), ("meaning", "plan"), ("inputs", "[\"source-1\"]"),
          ("columns", "[{\"id\":\"price\",\"title\":\"Price\",\"type\":\"decimal\"}]"),
          ("rows", "[{\"price\":\"12.40\",\"optional\":null}]"),
        ], policy: policy))
    try policy.validate(
      candidate(
        "propose_record",
        [
          ("title", "Forecast"), ("text", "Estimate"),
          ("kind", "forecast"), ("meaning", "estimate"), ("inputs", "[]"),
          ("data", "{\"units\":12,\"note\":null}"),
        ], policy: policy))
    try policy.validate(
      candidate(
        "calculate", [("expression", "cost * 2"), ("values", "{\"cost\":\"12.40\"}")],
        policy: policy))
    try expectThrows(
      try policy.validate(
        candidate(
          "propose_record",
          [
            ("title", "Large ID"), ("text", "Preserve exactly"), ("kind", "analysis"),
            ("meaning", "estimate"), ("inputs", "[]"), ("data", "{\"id\":9007199254740993}"),
          ], policy: policy)))
    let emptyEvidence = try NativeCitationPolicy.make([])
    try emptyEvidence.validate(
      candidate("finish", [("answer", "Saved space"), ("citations", "[]")], policy: emptyEvidence))
    try expectThrows(
      try emptyEvidence.validate(
        candidate(
          "finish", [("answer", "Saved"), ("citations", "[\"space-id\"]")], policy: emptyEvidence)))
    let knownEvidence = try NativeCitationPolicy.make(["source-one"])
    try knownEvidence.validate(
      candidate(
        "finish", [("answer", "Observed"), ("citations", "[\"source-one\"]")], policy: knownEvidence
      ))
    try expectThrows(
      try knownEvidence.validate(
        candidate(
          "finish", [("answer", "Observed"), ("citations", "[\"stale-id\"]")], policy: knownEvidence
        )))
    try expectThrows(
      try policy.validate(candidate("finish", [("answer", "Ready")], policy: policy)))
    try expectThrows(
      try policy.validate(
        candidate("finish", [("answer", "Ready"), ("citations", "[1]")], policy: policy)))
    try expectThrows(
      try policy.validate(
        candidate(
          "save_space",
          [
            ("title", "Dashboard"),
            ("definition", "{\"version\":true,\"components\":[]}"),
          ], policy: policy)))
    try expectThrows(
      try policy.validate(
        candidate(
          "save_space",
          [
            ("title", "Dashboard"),
            ("definition", "{\"version\":2,\"components\":[]}"),
          ], policy: policy)))
    try expectThrows(
      try policy.validate(
        candidate(
          "save_space",
          [
            ("title", "Dashboard"),
            (
              "definition",
              "{\"version\":1,\"components\":[{\"id\":\"a\",\"type\":\"script\",\"title\":\"No\"}]}"
            ),
          ], policy: policy)))
    try expectThrows(
      try policy.validate(
        candidate(
          "save_space",
          [
            ("title", "Dashboard"),
            ("definition", "{\"version\":1,\"components\":[],\"unexpected\":true}"),
          ], policy: policy)))
  }

  func testUnsupportedSchemasFailClosed() throws {
    for schema: [String: Any] in [
      [
        "type": "object", "properties": ["x": ["$ref": "https://invalid.test/schema"]],
        "additionalProperties": false,
      ],
      [
        "type": "object", "properties": [:], "required": ["missing"], "additionalProperties": false,
      ],
      ["type": "object", "properties": ["x": ["type": "unknown"]], "additionalProperties": false],
      [
        "type": "object", "properties": ["x": ["type": "array", "minItems": 4, "maxItems": 2]],
        "additionalProperties": false,
      ],
      ["type": "object", "properties": [:], "additionalProperties": true],
    ] {
      let data = try JSONSerialization.data(withJSONObject: [
        [
          "type": "function",
          "function": [
            "name": "invalid", "description": "Invalid fixture", "parameters": schema,
          ],
        ]
      ])
      try expectThrows(try SplashToolPolicy(toolsJSON: data))
    }
  }
}

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #fileID, line: UInt = #line)
  throws
{
  guard lhs == rhs else {
    throw SplashError("Tool policy assertion failed at \(file):\(line): \(lhs) != \(rhs)")
  }
}
func expectThrows<T>(_ value: @autoclosure () throws -> T) throws {
  do { _ = try value() } catch { return }
  throw SplashError("Invalid tool policy or arguments were accepted")
}
func expectValue<T>(_ value: T?) throws -> T {
  guard let value else { throw SplashError("Expected complete tool candidate") }
  return value
}
do {
  try checkContextBudget()
  try await checkAgentLifecycle()
  try await checkHistoryTools()
  let checks = ToolPolicyChecks()
  try checks.testActualWorkbookSchemas()
  try checks.testWorkbookArguments()
  try checks.testUnsupportedSchemasFailClosed()
  print(
    "PASS actual workbook schemas, open row/record data, full argument validation and schema refusals"
  )
  if CommandLine.arguments.count == 6
    && ["--autonomous", "--inventory", "--occupied", "--history"].contains(CommandLine.arguments[1])
  {
    try await runNativeAgentProbe(
      modelFolder: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], modelsRoot: CommandLine.arguments[5],
      inventoryOnly: CommandLine.arguments[1] != "--autonomous",
      occupiedContext: CommandLine.arguments[1] == "--occupied",
      historyOnly: CommandLine.arguments[1] == "--history")
  } else if [3, 5].contains(CommandLine.arguments.count) {
    let frontend = try SplashTextFrontend(
      modelFolder: URL(fileURLWithPath: CommandLine.arguments[1]))
    let library = URL(fileURLWithPath: CommandLine.arguments[2])
    let digest = SHA256.hash(data: try Data(contentsOf: library)).map { String(format: "%02x", $0) }
      .joined()
    let factory = try SplashGrammarFactory(
      frontend: frontend, library: library, librarySHA256: digest)
    try checkWorkbookGrammars(frontend: frontend, factory: factory)
    if CommandLine.arguments.count == 5 {
      try runNativeWorkbookProbe(
        frontend: frontend, factory: factory, engine: CommandLine.arguments[3],
        assembly: CommandLine.arguments[4])
    }
  } else if CommandLine.arguments.count != 1 {
    throw SplashError(
      "Usage: sevra-agent-checks [MODEL_FOLDER PINNED_NATIVE_LIBRARY [ENGINE ASSEMBLY]] or --autonomous/--inventory/--occupied/--history MODEL_FOLDER PINNED_NATIVE_LIBRARY ENGINE MODELS_ROOT. SEVRA_NATIVE_CONTEXT_TOKENS selects 8192/32768/65536 in development checks."
    )
  }
} catch {
  fputs("\(error)\n", stderr)
  exit(1)
}
