import CoreFoundation
import Foundation
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

// Development-only worker. It exercises the production frontend/transport/
// grammar/output primitives with the same request envelopes as the reference.
func sendable(_ value: Any) throws -> any Sendable {
  switch value {
  case let number as NSNumber:
    if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
    if let integer = Int64(exactly: number) { return integer }
    return number.doubleValue
  case let string as String: return string
  case is NSNull: return NSNull()
  case let array as [Any]: return try array.map(sendable)
  case let object as [String: Any]: return try object.mapValues(sendable)
  default: throw SplashError("Unsupported performance input")
  }
}
func emit(_ value: [String: Any]) throws {
  let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  FileHandle.standardOutput.write(bytes + Data([10]))
}
func now() -> Double { ProcessInfo.processInfo.systemUptime }

do {
  guard CommandLine.arguments.count == 2,
    let config = try JSONSerialization.jsonObject(
      with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as? [String: Any],
    let engine = config["engine"] as? String, let assembly = config["assembly"] as? String,
    let grammar = config["grammarLibrary"] as? String,
    let digest = config["grammarSHA256"] as? String,
    let context = config["contextTokens"] as? Int,
    let memory = config["memoryBytes"] as? UInt64,
    let cases = config["cases"] as? [[String: Any]]
  else { throw SplashError("Usage: sevra-inference-performance CONFIG.json") }
  let start = now()
  let frontend = try SplashTextFrontend(
    modelFolder: URL(fileURLWithPath: assembly).appendingPathComponent("tokenizer"))
  let factory = try SplashGrammarFactory(
    frontend: frontend, library: URL(fileURLWithPath: grammar), librarySHA256: digest)
  let helper = try SplashNativeProcess(
    executable: URL(fileURLWithPath: engine),
    arguments: ["serve-native", assembly, String(context), String(memory),
      "--persistent-cache", "off", "--idle-sleep", "allow", "--verify-rows", "all"],
    timeout: 180)
  defer { helper.close() }
  try emit(["ready": true, "pid": ProcessInfo.processInfo.processIdentifier,
    "helperPID": helper.processID, "setupSeconds": now() - start,
    "thermalState": ProcessInfo.processInfo.thermalState.rawValue])
  var requestID: UInt64 = 0
  while let line = readLine() {
    guard let command = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    else { throw SplashError("Invalid performance command") }
    if command["op"] as? String == "close" {
      try emit(["closed": helper.close()])
      break
    }
    guard let index = command["case"] as? Int, cases.indices.contains(index),
      let body = cases[index]["body"] as? [String: Any],
      let messages = body["messages"] as? [[String: Any]],
      let maximum = body["max_tokens"] as? UInt32
    else { throw SplashError("Invalid request case") }
    let began = now()
    let thinking = (body["chat_template_kwargs"] as? [String: Any])?["enable_thinking"] as? Bool ?? false
    var policy: SplashToolPolicy?
    if let tools = body["tools"] as? [[String: Any]] {
      let choice: SplashToolPolicy.Choice
      if let named = body["tool_choice"] as? [String: Any],
        let function = named["function"] as? [String: Any], let name = function["name"] as? String {
        choice = .named(name)
      } else { choice = .required }
      policy = try SplashToolPolicy(
        toolsJSON: JSONSerialization.data(withJSONObject: tools), choice: choice, thinking: thinking)
    }
    let prompt = try frontend.prepare(
      messages: messages.map { try $0.mapValues(sendable) }, tools: policy?.promptTools(),
      thinking: thinking, preserveThinking: false, contextLimit: context)
    var constraint: SplashGrammarConstraint?
    if let policy { constraint = try factory.create(grammar: policy.grammar) }
    else if let format = body["response_format"] as? [String: Any],
      var schema = (format["json_schema"] as? [String: Any])?["schema"] as? [String: Any] {
      // This frozen schema uses only type/properties/required/const. Match the
      // reference response_format wrapper, including its whitespace bound.
      schema["x-guidance"] = ["lenient": true, "whitespace_pattern": #"[ \t\n\r]{0,64}"#]
      let encoded = String(decoding: try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys]), as: UTF8.self)
      constraint = try factory.create(grammar: "%llguidance {}\nstart: WS %json " + encoded + "\nWS: /[ \\t\\n\\r]{0,64}/\n", type: "lark")
    }
    let output = try SplashOutputStream(
      frontend: frontend, tools: policy?.outputTools ?? [], thinking: thinking,
      structured: body["response_format"] != nil)
    requestID += 1
    var request = SplashWire.Request(id: requestID, prompt: prompt.tokens,
      absoluteDeadline: UInt64((Date().timeIntervalSince1970 + 180) * 1e6),
      remainingDeadline: 180_000_000)
    request.generationTokens = prompt.generationTokens
    request.maxOutput = maximum
    request.tokenMask = constraint != nil
    if thinking, let budget = body["thinking_token_budget"] as? UInt32 {
      request.thinking = .init(tokens: budget, end: [248069], alsoEnds: 248058)
    }
    let prepared = now()
    var matchedPrompt = 0
    let result = try helper.generate(request, cancelled: { false },
      mask: constraint.map { constraint in
        { committed, simulation, words in
          try constraint.masks(committed: committed, simulation: simulation, words: words)
        }
      }, event: { event in
        if case .tokens(_, _, let tokens) = event { _ = try output.append(tokens: tokens) }
        if case .start(_, _, let matched) = event { matchedPrompt = Int(matched) }
      })
    try constraint?.finish(committed: result.tokens, requireComplete: result.done.reason == .stop)
    let parsed = try output.finish(result.done.reason).0
    for call in parsed.calls { try policy?.validate(call) }
    if body["response_format"] != nil {
      // This worker's only JSON workload has these three required primitive
      // fields and forbids additional properties. Include its terminal check
      // in timing, as the reference does. This is not a general JSON API.
      guard cases[index]["id"] as? String == "unicode_json",
        let value = try JSONSerialization.jsonObject(with: Data(parsed.text.utf8)) as? [String: Any],
        Set(value.keys) == Set(["label", "note", "quantity"]),
        value["label"] is String, value["note"] is String,
        let quantity = value["quantity"] as? NSNumber,
        CFGetTypeID(quantity) != CFBooleanGetTypeID(), Int64(exactly: quantity) != nil
      else { throw SplashError("Invalid frozen JSON workload result") }
    }
    let elapsed = now() - began
    // Status is outside request timing. The coordinator samples both process
    // footprints during the request independently of these engine counters.
    let status = try JSONSerialization.jsonObject(with: helper.status(id: requestID + 1_000_000))
    let row: [String: Any] = [
      "case": index, "id": cases[index]["id"]!, "completeSeconds": elapsed,
      "prepareSeconds": prepared - began,
      "firstTokenSeconds": result.firstTokenSeconds.map { $0 + prepared - began } as Any? ?? NSNull(),
      "engineRequestSeconds": result.requestSeconds,
      "prefillSeconds": Double(result.done.prefillMicros) / 1e6,
      "decodeSeconds": Double(result.done.decodeMicros) / 1e6,
      "promptTokens": prompt.tokens, "generationTokens": prompt.generationTokens,
      "matchedPromptTokens": matchedPrompt,
      "tokens": result.tokens, "text": parsed.text, "reasoning": parsed.reasoning,
      "calls": try parsed.calls.map { ["name": $0.name,
        "arguments": try JSONSerialization.jsonObject(with: $0.arguments)] },
      "finish": result.done.reason.rawValue, "bounded": result.done.bounded,
      "drafted": result.done.drafted, "accepted": result.done.accepted,
      "thermalState": ProcessInfo.processInfo.thermalState.rawValue, "status": status,
    ]
    try emit(row)
  }
} catch {
  try? emit(["error": error.localizedDescription])
  exit(1)
}
