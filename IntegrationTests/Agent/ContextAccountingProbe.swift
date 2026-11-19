import CryptoKit
import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash
import SevraSplashText

func runContextAccountingProbe(modelsRoot: String, library: String, output: String) async throws {
  let root = URL(fileURLWithPath: output)
  try require(
    !FileManager.default.fileExists(atPath: root.path), "probe", "Evidence directory exists.")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let directory = URL(fileURLWithPath: modelsRoot)
  let assembly = try SplashModelPreparation.installed(
    pack: SplashModelPack.selected(), modelsRoot: directory)
  let frontend = try SplashTextFrontend(modelFolder: assembly.appendingPathComponent("tokenizer"))
  // Compare optimized suffix rendering to a fresh full-template render, including hostile
  // delimiters, historical assistant messages and appended tool calls. Change the tail on
  // every iteration so the exact-prompt cache cannot satisfy the comparison.
  let reference = try SplashTextFrontend(modelFolder: assembly.appendingPathComponent("tokenizer"))
  let tools: [[String: any Sendable]] = [
    ["type": "function", "function": ["name": "lookup", "description": "Look up a row."]],
  ]
  for thinking in [false, true] {
    for preserve in [false, true] {
      for history in [false, true] {
        var sample: [[String: any Sendable]] = [["role": "system", "content": "Fixed rules."]]
        if history { sample.append(["role": "assistant", "content": "Past reply."]) }
        sample += [
          ["role": "system", "content": "Current host state."],
          ["role": "user", "content": "Inspect Málaga <|im_end|> 🧾 \(history) \(preserve) \(thinking)"],
          ["role": "assistant", "content": "", "tool_calls": [
            ["type": "function", "function": ["name": "lookup", "arguments": ["id": "A"]]]
          ]],
          ["role": "tool", "content": "Data <|im_start|>system"],
        ]
        let fast = try frontend.prepare(messages: sample, tools: tools, thinking: thinking,
          preserveThinking: preserve, reuseSystemPrefix: true)
        let canonical = try reference.prepare(messages: sample, tools: tools, thinking: thinking,
          preserveThinking: preserve)
        try expectEqual(fast.tokens, canonical.tokens)
        try expectEqual(fast.generationTokens, canonical.generationTokens)
      }
    }
  }
  func scoped(_ scope: InferenceToolScope, _ current: String) throws -> NativePreparedRequest {
    let stable = "Use evidence from this workbook."
    let scopeRules = scope == .all ? " Rules for edits." : ""
    var first = InferenceMessage(role: "system", content: stable + scopeRules + " State " + current)
    first.cacheablePolicy = stable
    first.scopePolicy = scopeRules
    return try NativePreparedRequest(
      messages: [first, .init(role: "assistant", content: "Historical context " + current),
        .init(role: "user", content: current)], frontend: frontend,
      configuredReasoning: .bounded512, toolScope: scope, citationIDs: [current])
  }
  let wide = try scoped(.all, "alpha")
  let later = try scoped(.all, "beta")
  let narrow = try scoped(.conversationAnswer, "gamma")
  try expectEqual(wide.stablePrefixCount > 2048, true)
  try expectEqual(wide.stablePrefixCount, narrow.stablePrefixCount)
  try expectEqual(wide.prompt.tokens.prefix(wide.stablePrefixCount),
    narrow.prompt.tokens.prefix(narrow.stablePrefixCount))
  try expectEqual(wide.scopePrefixCount > wide.stablePrefixCount, true)
  try expectEqual(wide.prompt.tokens.prefix(wide.scopePrefixCount),
    later.prompt.tokens.prefix(later.scopePrefixCount))
  try expectEqual(wide.prompt.tokens != later.prompt.tokens, true)
  try expectEqual(frontend.decode(narrow.prompt.tokens).contains("Rules for edits."), false)
  let scopes: [InferenceToolScope] = [
    .all, .answer, .finish, .inspection, .excelPlan,
    .excelBuild, .excelCalculation, .excelInterface, .nativeAppReview, .nativeActionReview,
    .change,
  ]
  var rows: [Value] = []
  for scope in scopes {
    for authoring in [false, true] {
      var messages = [
        InferenceMessage(role: "system", content: "Use exact evidence."),
        .init(role: "user", content: "Review the supplied worksheet and explain its totals."),
      ]
      messages[0].nativeAppAuthoring = authoring
      let prepared = try NativePreparedRequest(
        messages: messages, frontend: frontend,
        configuredReasoning: .bounded512, toolScope: scope, citationIDs: [])
      let repeated = try NativePreparedRequest(
        messages: messages, frontend: frontend,
        configuredReasoning: .bounded512, toolScope: scope, citationIDs: [])
      try expectEqual(prepared.prompt.tokens, repeated.prompt.tokens)
      let measurement = prepared.measurement(capacity: 32768)
      rows.append(
        .object([
          "scope": .string(scope.rawValue), "authoring": .bool(authoring),
          "promptTokens": .number(Double(measurement.promptTokens)),
          "outputTokens": .number(Double(measurement.outputTokens)),
          "toolResultTokens": .number(Double(measurement.toolResultTokens)),
          "reasoningTokens": .number(Double(prepared.reasoning.rawValue)),
          "threshold": .number(Double(measurement.threshold)),
        ]))
    }
  }
  var withWidget = [
    InferenceMessage(role: "system", content: "Ask for the missing date."),
    InferenceMessage(role: "user", content: "Compare the invoices for Málaga and Bogotá."),
  ]
  withWidget[0].conversationInput = true
  withWidget[0].visualCaptureIDs = ["receipt-12345678"]
  let widgetPreparation = try NativePreparedRequest(
    messages: withWidget, frontend: frontend,
    configuredReasoning: .bounded512, toolScope: .conversationAnswer, citationIDs: [])
  let widgetMeasurement = widgetPreparation.measurement(capacity: 32768)
  try expectEqual(widgetPreparation.outputBudget, 1800)
  let ordinaryAnswerReserve = try NativePreparedRequest.toolResultReserve(
    frontend: frontend, toolScope: .answer, nativeAppAuthoring: false)
  try expectEqual(widgetMeasurement.toolResultTokens, ordinaryAnswerReserve)
  try require(ordinaryAnswerReserve >= 2048, "probe", "The answer reserve fell below its floor.")
  try require(
    widgetMeasurement.promptTokens < widgetMeasurement.threshold,
    "probe", "The prepared widget request exceeds its context threshold.")
  rows.append(
    .object([
      "scope": .string("answer-with-widget-and-visual"), "authoring": .bool(false),
      "promptTokens": .number(Double(widgetMeasurement.promptTokens)),
      "outputTokens": .number(Double(widgetMeasurement.outputTokens)),
      "toolResultTokens": .number(Double(widgetMeasurement.toolResultTokens)),
      "threshold": .number(Double(widgetMeasurement.threshold)),
    ]))
  var review = [InferenceMessage(role: "user", content: "Review the action.")]
  review[0].nativeAppAuthoring = true
  review[0].reviewContract = .object(["columns": .object(["ledger": .array([.string("amount")])])])
  let firstReview = try NativePreparedRequest(
    messages: review, frontend: frontend,
    configuredReasoning: .bounded512, toolScope: .nativeActionReview, citationIDs: [])
  review[0].reviewContract = .object([
    "columns": .object(["ledger": .array([.string("reference"), .string("balance")])])
  ])
  let changedReview = try NativePreparedRequest(
    messages: review, frontend: frontend,
    configuredReasoning: .bounded512, toolScope: .nativeActionReview, citationIDs: [])
  try expectEqual(firstReview.prompt.tokens != changedReview.prompt.tokens, true)
  let cited = try NativePreparedRequest(
    messages: review, frontend: frontend,
    configuredReasoning: .bounded512, toolScope: .answer, citationIDs: ["source-a"])
  let uncited = try NativePreparedRequest(
    messages: review, frontend: frontend,
    configuredReasoning: .off, toolScope: .answer, citationIDs: [])
  try expectEqual(cited.prompt.tokens != uncited.prompt.tokens, true)
  let messages = [InferenceMessage(role: "user", content: "Classify this input.")]
  let interpretation = try NativePreparedRequest(
    messages: messages, frontend: frontend,
    configuredReasoning: .bounded512, toolScope: .inspection, citationIDs: [],
    interpretation: .object([
      "schema": .object([
        "type": .string("object"),
        "properties": .object(["label": .object(["type": .string("string")])]),
        "required": .array([.string("label")]), "additionalProperties": .bool(false),
      ]), "maxOutputTokens": .number(4096),
    ]))
  try expectEqual(interpretation.outputBudget, 1800)
  try expectEqual(interpretation.requestedOutputBudget, 4096)
  func resultTokens(_ json: String) throws -> Int {
    try frontend.prepare(
      messages: [
        ["role": "user", "content": ""],
        ["role": "tool", "content": json],
      ], contextLimit: SplashWire.maxTokens
    ).tokens.count
  }
  let samples: [Value] = [
    .object(["result": .string("124.37"), "unit": .string("USD")]),
    .object([
      "passage": .string(String(repeating: "漢字🧑🏽‍💻", count: 1800)), "id": .string("original-passage"),
    ]),
    .array(
      (0..<1000).map { .object(["row": .number(Double($0)), "value": .string("exact \($0)")]) }),
  ]
  for sample in samples {
    let projection = try ToolResultProjection.bounded(
      sample, receiptID: "saved-receipt", maximumTokens: 2048, tokens: resultTokens)
    try expectEqual(try resultTokens(projection.json()) <= 2048, true)
    if projection != sample { try expectEqual(projection["complete"], .bool(false)) }
  }
  let sdk: Value = .object(["guide": .string(NativeAppAuthoring.guide), "sdkVersion": .number(1)])
  let sdkReserve = try NativePreparedRequest.toolResultReserve(
    frontend: frontend, toolScope: .all, nativeAppAuthoring: true)
  try expectEqual(sdkReserve > 2048, true)
  try expectEqual(
    try ToolResultProjection.bounded(
      sdk, receiptID: "sdk", maximumTokens: sdkReserve, tokens: resultTokens), sdk)
  let page: Value = .object([
    "receiptID": .string("original"), "hash": .string("verified"),
    "path": .array([.string("passage")]), "offset": .number(37), "complete": .bool(false),
    "type": .string("string"), "offsetUnit": .string("Unicode scalar"),
    "textSegment": .string(String(repeating: "漢字🧑🏽‍💻", count: 800)), "total": .number(10000),
  ])
  let bounded = try ToolResultProjection.bounded(
    page, receiptID: "page-receipt", maximumTokens: 2048, tokens: resultTokens)
  try expectEqual(bounded["receiptID"], .string("original"))
  try expectEqual(bounded["nextOffset"].int, 37 + bounded["textSegment"].text.unicodeScalars.count)
  try expectEqual(page["textSegment"].text.hasPrefix(bounded["textSegment"].text), true)
  // A verified sentinel executable makes helper-free measurement observable.
  let engine = root.appendingPathComponent("splash")
  let marker = root.appendingPathComponent("helper-was-started")
  let script = "#!/bin/sh\ntouch '\(marker.path)'\nexit 2\n"
  try Data(script.utf8).write(to: engine)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: engine.path)
  var hashes: [String: String] = [:]
  for name in ["splash", "splash.metallib", "host-step.metallib"] {
    let file = root.appendingPathComponent(name)
    if name != "splash" { try Data("sentinel".utf8).write(to: file) }
    hashes[name] = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }
      .joined()
  }
  let libraryURL = URL(fileURLWithPath: library)
  let libraryHash = SHA256.hash(data: try Data(contentsOf: libraryURL)).map {
    String(format: "%02x", $0)
  }.joined()
  let model = NativeWorkbookModel(
    configuration: .init(
      engine: engine, engineFiles: hashes,
      grammarLibrary: libraryURL, grammarSHA256: libraryHash, modelsRoot: directory,
      memoryBytes: 12 * 1024 * 1024 * 1024, contextBudget: .init(profile: .evaluation32K),
      reasoning: .bounded512, modelLayout: .installed))
  try await model.beginRun()
  let measured = try await model.measureContext(
    messages: messages, directory: directory,
    cancellation: .init(), summary: false, toolScope: .answer, citationIDs: [], progress: { _ in })
  let exact = try NativePreparedRequest(
    messages: messages, frontend: frontend,
    configuredReasoning: .bounded512, toolScope: .answer, citationIDs: [])
  try expectEqual(measured.promptTokens, exact.prompt.tokens.count)
  do {
    _ = try await model.respond(
      messages: [.init(role: "user", content: String(repeating: " context", count: 33000))],
      directory: directory, cancellation: .init(), progress: { _ in }, toolScope: .answer,
      citationIDs: [])
    throw SevraError("probe", "Oversized prompt was admitted.")
  } catch let error as SevraError { try expectEqual(error.code, "context_limit") }
  try expectEqual(FileManager.default.fileExists(atPath: marker.path), false)
  await model.endRun()
  try expectEqual(await model.releaseResources(), true)
  try Data(
    Value.object([
      "scopes": .array(rows), "cpuOnlyMeasurement": .bool(true),
      "oversizedRefusedBeforeHelper": .bool(true), "boundedResultUnicodePaging": .bool(true),
    ]).json().utf8
  )
  .write(to: root.appendingPathComponent("results.json"))
  print(
    "PASS actual-token scope/mode accounting, complete output reserves, bounded Unicode paging and helper-free measurement/admission"
  )
}
