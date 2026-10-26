import CoreFoundation
import Foundation
import SevraSplash
import SevraSplashText

func value(_ input: Any) throws -> any Sendable {
  if let x = input as? String { return x }
  if let x = input as? NSNumber {
    if CFGetTypeID(x) == CFBooleanGetTypeID() { return x.boolValue }
    if ["f", "d"].contains(String(cString: x.objCType)) { return x.doubleValue }
    return x.intValue
  }
  if let x = input as? [String: Any] { return try x.mapValues(value) }
  if let x = input as? [Any] { return try x.map(value) }
  if input is NSNull { return NSNull() }
  throw SplashError("Unexpected fixture type")
}
do {
  guard CommandLine.arguments.count == 2 else {
    throw SplashError("Usage: sevra-splash-text-checks /path/to/verified/model-or-tokenizer-folder")
  }
  let folder = URL(fileURLWithPath: CommandLine.arguments[1])
  let frontend = try SplashTextFrontend(modelFolder: folder)
  let file = Bundle.module.url(forResource: "fixtures", withExtension: "json")!
  let fixtures = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
  var failures = 0
  for fixture in fixtures["cases"] as! [[String: Any]] {
    do {
      let messages = try (fixture["messages"] as! [[String: Any]]).map { try $0.mapValues(value) }
      let tools = try (fixture["tools"] as? [[String: Any]])?.map { try $0.mapValues(value) }
      let prompt = try frontend.prepare(
        messages: messages, tools: tools,
        thinking: fixture["thinking"] as! Bool,
        preserveThinking: fixture["preserveThinking"] as! Bool)
      let expected = (fixture["tokens"] as! [NSNumber]).map(\.uint32Value)
      guard prompt.tokens == expected,
        prompt.generationTokens == (fixture["generationTokens"] as! NSNumber).uint32Value
      else {
        let first = zip(prompt.tokens, expected).enumerated().first {
          $0.element.0 != $0.element.1
        }?.offset
        throw SplashError(
          "Prompt token mismatch, actual \(prompt.tokens.count), expected \(expected.count), first \(String(describing: first))"
        )
      }
      guard frontend.decode(prompt.tokens) == fixture["rendered"] as? String else {
        throw SplashError("Round-trip decoded prompt differs")
      }
      print("PASS \(fixture["name"]!) exact prompt and generation-prefix tokens")
    } catch {
      failures += 1
      print("FAIL \(fixture["name"]!): \(error)")
    }
  }
  guard failures == 0 else { throw SplashError("\(failures) text fixture checks failed") }
  let invalid: [() throws -> Void] = [
    { _ = try frontend.prepare(messages: []) },
    {
      _ = try frontend.prepare(messages: [["role": "user", "content": "Hello"]], contextLimit: 1)
    },
    { _ = try frontend.prepare(messages: [["role": "user", "content": [["type": "image"]]]]) },
    { _ = try frontend.prepare(messages: [["role": "unknown", "content": "Hello"]]) },
    {
      _ = try frontend.prepare(
        messages: [["role": "user", "content": "Hello"]],
        tools: [["name": String(repeating: "x", count: 2 * 1024 * 1024)]])
    },
    {
      _ = try frontend.prepare(
        messages: [["role": "user", "content": "Hello"]], tools: [["value": Double.nan]])
    },
  ]
  for attempt in invalid {
    var rejected = false
    do { try attempt() } catch { rejected = true }
    guard rejected else { throw SplashError("Invalid frontend input was accepted") }
  }
  print("PASS context, modality, role, size and numeric input limits")
  print("All 14 pinned-reference text checks passed")
  try checkOutput(frontend: frontend)
} catch {
  fputs("\(error)\n", stderr)
  exit(1)
}
