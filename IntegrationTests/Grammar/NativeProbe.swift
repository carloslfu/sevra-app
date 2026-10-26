import Darwin
import Foundation
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

/// Synthetic, development-only requests through the real native engine. No Python.
func runNativeGrammar(
  frontend: SplashTextFrontend, factory: SplashGrammarFactory, fixtures: Fixtures,
  engine: String, assembly: String
) throws {
  let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Application Support/Sevra")
  try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
  let descriptor = Darwin.open(
    support.appendingPathComponent("inference.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
  guard descriptor >= 0 else { throw SplashError("Cannot open Sevra inference lock") }
  defer { Darwin.close(descriptor) }
  guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
    throw SplashError("Another Sevra process owns inference; unload it before the explicit probe")
  }
  defer { flock(descriptor, LOCK_UN) }
  let memory =
    ProcessInfo.processInfo.environment["SEVRA_SPLASH_PROBE_MEMORY_BYTES"] ?? "12884901888"
  guard UInt64(memory) != nil else { throw SplashError("Invalid probe memory budget") }
  let helper = try SplashNativeProcess(
    executable: URL(fileURLWithPath: engine),
    arguments: [
      "serve-native", assembly, "8192", memory,
      "--persistent-cache", "off", "--idle-sleep", "allow", "--verify-rows", "all",
    ],
    timeout: 180)
  defer { helper.close() }
  var maskCalls = 0
  for id: UInt64 in 1...5 {
    let fixture = fixtures.cases[(id == 2) ? 1 : (id == 3) ? 3 : 0]
    let instruction: String
    var tools: [[String: any Sendable]]?
    if id == 2 {
      instruction =
        "Reply with JSON only. Use label 'Bogotá 日本語 🧮' and values [1.25, -2, true, null]."
    } else if id == 3 {
      instruction = "Call find_evidence to find invoice 1042, with limit 4."
      tools = [
        [
          "type": "function",
          "function": [
            "name": "find_evidence",
            "description": "Search workbook evidence.",
            "parameters": [
              "type": "object",
              "properties": ["query": ["type": "string"], "limit": ["type": "integer"]],
              "required": ["query", "limit"], "additionalProperties": false,
            ],
          ],
        ]
      ]
    } else {
      instruction = "Reply with JSON only: {\"answer\":\"ready\"}."
    }
    let prompt = try frontend.prepare(
      messages: [
        ["role": "system", "content": "Follow the requested response format."],
        ["role": "user", "content": instruction],
      ], tools: tools)
    let grammar = try factory.create(grammar: fixture.grammar, type: fixture.type)
    var request = SplashWire.Request(
      id: id, prompt: prompt.tokens,
      absoluteDeadline: UInt64((Date().timeIntervalSince1970 + 180) * 1e6),
      remainingDeadline: 180_000_000)
    request.generationTokens = prompt.generationTokens
    request.tokenMask = true
    request.maxOutput = 256
    let result = try helper.generate(
      request, cancelled: { id == 4 },
      mask: { committed, simulation, words in
        maskCalls += 1
        return try grammar.masks(committed: committed, simulation: simulation, words: words)
      })
    let cancelled = result.done.reason == .cancelled
    guard cancelled == (id == 4) else { throw SplashError("Native cancellation state differs") }
    try grammar.finish(committed: result.tokens, requireComplete: !cancelled)
    let output = frontend.decode(result.tokens, skipSpecialTokens: true)
    if !cancelled && id != 3 {
      guard let parsed = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
      else {
        throw SplashError("Native response did not decode as a JSON object")
      }
      if id == 2 {
        guard (parsed["label"] as? String) == "Bogotá 日本語 🧮",
          let values = parsed["values"] as? [Any], values.count == 4,
          (values[0] as? Double) == 1.25, (values[1] as? Int) == -2,
          (values[2] as? Bool) == true, values[3] is NSNull
        else {
          throw SplashError("Native Unicode JSON response differs from the request")
        }
      } else if parsed["answer"] as? String != "ready" {
        throw SplashError("Native constrained answer differs from request")
      }
    }
    let row: [String: Any] = [
      "request": id, "output": output, "tokens": result.tokens,
      "finish": result.done.reason.rawValue, "seconds": result.requestSeconds,
      "firstTokenSeconds": result.firstTokenSeconds as Any? ?? NSNull(),
      "decodeMicros": result.done.decodeMicros, "prefillMicros": result.done.prefillMicros,
    ]
    print(
      String(
        decoding: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
        as: UTF8.self))
  }
  guard
    let status = try JSONSerialization.jsonObject(with: helper.status(id: 100, release: true))
      as? [String: Any],
    let weights = status["weights"] as? [String: Any], weights["released"] as? Bool == true,
    let metal = status["metal"] as? [String: Any], metal["healthy"] as? Bool == true,
    let requests = status["requests"] as? [String: Any], requests["completed"] as? Int == 4,
    requests["cancelled"] as? Int == 1, requests["failed"] as? Int == 0,
    maskCalls > 0
  else { throw SplashError("Native grammar probe did not complete/release healthily") }
  print(
    String(
      decoding: try JSONSerialization.data(
        withJSONObject: ["status": status, "maskCalls": maskCalls], options: [.sortedKeys]),
      as: UTF8.self))
}
