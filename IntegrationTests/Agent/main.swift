import CryptoKit
import Foundation
import SevraAI
import SevraBaseline
import SevraCore
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
          "parameters": try JSONSerialization.jsonObject(with: Data(try $0.parameters.json().utf8)),
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
    try expectEqual(
      (function("save_definition")["parameters"] as! [String: Any])["required"] as? [String],
      ["content"])
    try expectEqual(
      (function("save_template")["parameters"] as! [String: Any])["required"] as? [String],
      ["templateReceiptID"])
    for name in ["save_definition", "save_template"] {
      let properties =
        (function(name)["parameters"] as! [String: Any])["properties"] as! [String: Any]
      try expectEqual(properties["logicalID"] == nil, true)
    }
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
      candidate(
        "finish", [("answer", "Saved space"), ("basis", "completed_action"), ("citations", "[]")],
        policy: emptyEvidence))
    try expectThrows(
      try emptyEvidence.validate(
        candidate(
          "finish", [("answer", "Saved"), ("basis", "evidence"), ("citations", "[\"space-id\"]")],
          policy: emptyEvidence)))
    let knownEvidence = try NativeCitationPolicy.make(["source-one"])
    try knownEvidence.validate(
      candidate(
        "finish",
        [("answer", "Observed"), ("basis", "evidence"), ("citations", "[\"source-one\"]")],
        policy: knownEvidence
      ))
    let knownMessage = try NativeCitationPolicy.make(["message:history-one"])
    try knownMessage.validate(
      candidate(
        "finish",
        [
          ("answer", "You supplied this earlier."), ("basis", "evidence"),
          ("citations", "[\"message:history-one\"]"),
        ],
        policy: knownMessage))
    try expectThrows(
      try knownMessage.validate(
        candidate(
          "finish",
          [
            ("answer", "Unseen"), ("basis", "evidence"), ("citations", "[\"message:history-two\"]"),
          ],
          policy: knownMessage)))
    try expectThrows(
      try knownEvidence.validate(
        candidate(
          "finish",
          [("answer", "Observed"), ("basis", "evidence"), ("citations", "[\"stale-id\"]")],
          policy: knownEvidence
        )))
    try expectThrows(
      try policy.validate(candidate("finish", [("answer", "Ready")], policy: policy)))
    try expectThrows(
      try policy.validate(
        candidate("finish", [("answer", "Ready"), ("citations", "[]")], policy: policy)))
    try expectThrows(
      try policy.validate(
        candidate(
          "finish", [("answer", "Ready"), ("basis", "unsupported"), ("citations", "[]")],
          policy: policy)))
    try expectThrows(
      try policy.validate(
        candidate(
          "finish", [("answer", "Ready"), ("basis", "evidence"), ("citations", "[1]")],
          policy: policy)))
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
  if CommandLine.arguments.dropFirst() == ["--export-tools"] {
    let checks = ToolPolicyChecks()
    try checks.testActualWorkbookSchemas()
    exit(0)
  }
  try checkContextBudget()
  try await checkContextThreshold()
  try checkReasoningBudget()
  try await checkReasoningHistory()
  try await checkAgentLifecycle()
  try await checkConversationActions()
  try await checkSpaceActions()
  try await checkRequestHandoffs()
  try await checkHandoffEvidence()
  try await checkInterfaceGuidance()
  try await checkRequestEnvelopes()
  try await checkRequestAdmission()
  try await checkMovementDirection()
  try await checkApplicationTools()
  try await checkWorkflowAgentTools()
  try await checkComputationTools()
  try await checkCitationVersions()
  try await checkActionConfirmations()
  try await checkDocumentCopies()
  try await checkCurrencyRejection()
  try await checkHistoryTools()
  try await checkParentHistory()
  try await checkScopedSearch()
  try await checkItemReferences()
  try await checkReferenceTraversal()
  try await checkReferenceScope()
  try await checkSearchCoverage()
  try await checkCompaction()
  try await checkRunningCompaction()
  let checks = ToolPolicyChecks()
  try checks.testActualWorkbookSchemas()
  try checks.testWorkbookArguments()
  try checks.testUnsupportedSchemasFailClosed()
  print(
    "PASS actual workbook schemas, open row/record data, full argument validation and schema refusals"
  )
  if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--baseline-continuity" {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sevra-baseline-continuity-" + identifier())
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = LocalModel(enableContextMaintenance: true)
    do {
      try await runNativeContinuityProbe(
        model: model, directory: URL(fileURLWithPath: CommandLine.arguments[2]), root: root)
      try expectEqual(await model.unload(), true)
    } catch {
      _ = await model.unload()
      throw error
    }
  } else if CommandLine.arguments.count == 5 && CommandLine.arguments[1] == "--currency-recovery" {
    try await runCurrencyRecoveryProbe(
      modelsRoot: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4])
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--computation" {
    try await runComputationProbe(
      modelsRoot: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], output: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6
    && CommandLine.arguments[1] == "--workflow-interpretation"
  {
    try await runWorkflowInterpretationProbe(
      modelsRoot: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], output: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--workflow-tools" {
    try await runWorkflowToolProbe(
      modelsRoot: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], output: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--intake-authoring" {
    try await runIntakeAuthoringProbe(
      modelsRoot: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], output: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--application-tools" {
    try await runApplicationToolProbe(
      modelsRoot: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], output: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--movement-direction" {
    try await runMovementDirectionProbe(
      modelsRoot: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], output: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--request-handoff" {
    try await runRequestHandoffProbe(
      modelsRoot: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], output: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6
    && ["--interpretation-authoring", "--preparation-authoring"].contains(CommandLine.arguments[1])
  {
    try await runInterpretationAuthoringProbe(
      modelsRoot: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], output: CommandLine.arguments[5],
      preparation: CommandLine.arguments[1] == "--preparation-authoring")
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--interface-guidance" {
    try await runInterfaceGuidanceProbe(
      modelsRoot: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], output: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--conversation-actions"
  {
    try await runConversationActionProbe(
      modelsRoot: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], output: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--coverage" {
    try await runCoverageProbe(
      modelFolder: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], modelsRoot: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--inspection-recovery"
  {
    try await runInspectionRecoveryProbe(
      modelFolder: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], modelsRoot: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--continuity-workflow"
  {
    try await runContinuityWorkflowProbe(
      modelsRoot: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], output: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--document-composition"
  {
    try await runDocumentCompositionProbe(
      modelsRoot: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], output: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--reference-traversal"
  {
    try await runReferenceTraversalProbe(
      modelFolder: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], output: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6
    && ["--active-context", "--active-context-maintained"].contains(CommandLine.arguments[1])
  {
    try await runActiveContextProbe(
      modelsRoot: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], output: CommandLine.arguments[5],
      maintainedOnly: CommandLine.arguments[1] == "--active-context-maintained")
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--reasoning-boundary" {
    try runReasoningBoundaryProbe(
      modelFolder: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], modelsRoot: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6 && CommandLine.arguments[1] == "--reasoning-comparison"
  {
    try await runReasoningComparison(
      modelFolder: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], modelsRoot: CommandLine.arguments[5])
  } else if CommandLine.arguments.count == 6
    && [
      "--autonomous", "--inventory", "--occupied", "--history", "--continuity",
      "--context-recovery",
    ].contains(
      CommandLine.arguments[1])
  {
    try await runNativeAgentProbe(
      modelFolder: CommandLine.arguments[2], library: CommandLine.arguments[3],
      engine: CommandLine.arguments[4], modelsRoot: CommandLine.arguments[5],
      inventoryOnly: CommandLine.arguments[1] != "--autonomous",
      occupiedContext: CommandLine.arguments[1] == "--occupied",
      historyOnly: CommandLine.arguments[1] == "--history",
      continuityOnly: CommandLine.arguments[1] == "--continuity",
      contextRecoveryOnly: CommandLine.arguments[1] == "--context-recovery")
  } else if [3, 5].contains(CommandLine.arguments.count) {
    let frontend = try SplashTextFrontend(
      modelFolder: URL(fileURLWithPath: CommandLine.arguments[1]))
    let library = URL(fileURLWithPath: CommandLine.arguments[2])
    let digest = SHA256.hash(data: try Data(contentsOf: library)).map { String(format: "%02x", $0) }
      .joined()
    let factory = try SplashGrammarFactory(
      frontend: frontend, library: library, librarySHA256: digest)
    try checkWorkbookGrammars(frontend: frontend, factory: factory)
    try checkReasoningGrammar(frontend: frontend, factory: factory)
    try checkItemReferenceGrammar(frontend: frontend, factory: factory)
    try checkDocumentCopyGrammar(frontend: frontend, factory: factory)
    try checkConversationActionGrammar(frontend: frontend, factory: factory)
    try checkActionDirectionGrammar(frontend: frontend, factory: factory)
    if CommandLine.arguments.count == 5 {
      try runNativeWorkbookProbe(
        frontend: frontend, factory: factory, engine: CommandLine.arguments[3],
        assembly: CommandLine.arguments[4])
    }
  } else if CommandLine.arguments.count != 1 {
    throw SplashError(
      "Usage: sevra-agent-checks --reference-traversal MODEL_FOLDER PINNED_NATIVE_LIBRARY ENGINE NEW_OUTPUT_DIRECTORY or --document-composition/--movement-direction/--request-handoff/--interface-guidance/--conversation-actions MODELS_ROOT PINNED_NATIVE_LIBRARY ENGINE NEW_OUTPUT_DIRECTORY or --active-context/--active-context-maintained MODELS_ROOT PINNED_NATIVE_LIBRARY ENGINE NEW_OUTPUT_DIRECTORY or --continuity-workflow MODELS_ROOT PINNED_NATIVE_LIBRARY ENGINE NEW_OUTPUT_DIRECTORY or --baseline-continuity MODEL_FOLDER or [MODEL_FOLDER PINNED_NATIVE_LIBRARY [ENGINE ASSEMBLY]] or --autonomous/--inventory/--occupied/--history/--continuity/--context-recovery/--reasoning-comparison/--reasoning-boundary/--inspection-recovery/--coverage MODEL_FOLDER PINNED_NATIVE_LIBRARY ENGINE MODELS_ROOT. The continuity workflow uses native-installed models, 32K and bounded512; reference traversal uses local-pack models at those same budgets. SEVRA_NATIVE_CONTEXT_TOKENS selects 8192/32768/65536 and SEVRA_NATIVE_REASONING selects 0/512 in other development checks. Reasoning comparison fixes 32K and accepts SEVRA_REASONING_SAVE_FIXTURES or SEVRA_REASONING_FIXTURES; SEVRA_REASONING_BOUNDED_ONLY=1 runs only the bounded arm."
    )
  }
} catch {
  fputs("\(error)\n", stderr)
  exit(1)
}
