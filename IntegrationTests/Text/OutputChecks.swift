import Foundation
import SevraSplash
import SevraSplashText

func checkOutput(frontend: SplashTextFrontend) throws {
  struct Decoder: Decodable {
    let name: String
    let tokens: [UInt32]
    let stops: [String]
    let deltas: [String]
    let tail: String
    let output: String
    let matchedStop: String?
  }
  struct Fixtures: Decodable { let decoders: [Decoder] }
  let fixtures = try JSONDecoder().decode(
    Fixtures.self,
    from: Data(
      contentsOf:
        Bundle.module.url(forResource: "output-fixtures", withExtension: "json")!))
  var differences = 0
  for fixture in fixtures.decoders {
    let decoder = try frontend.makeDecoder(stopSequences: fixture.stops)
    var output = ""
    for (index, token) in fixture.tokens.enumerated() {
      let delta = try decoder.append(token)
      output += delta
      if !delta.utf8.elementsEqual(fixture.deltas[index].utf8) {
        print(
          "FAIL \(fixture.name) stream delta \(index): \(delta.debugDescription), expected \(fixture.deltas[index].debugDescription)"
        )
        differences += 1
      }
    }
    let tail = try decoder.finish()
    output += tail
    guard tail.utf8.elementsEqual(fixture.tail.utf8),
      output.utf8.elementsEqual(fixture.output.utf8),
      decoder.matchedStop == fixture.matchedStop
    else { throw SplashError("Final decode differs: \(fixture.name)") }
  }
  guard differences == 0 else { throw SplashError("\(differences) streaming deltas differ") }
  print(
    "PASS \(fixtures.decoders.count) exact upstream streaming decodes, UTF-8, special tokens and stops"
  )
  try checkProjection()
  func refuses(_ action: () throws -> Void) throws {
    var refused = false
    do { try action() } catch { refused = true }
    guard refused else { throw SplashError("Invalid text stream accepted") }
  }
  try refuses { _ = try frontend.makeDecoder(stopSequences: [""]) }
  try refuses { _ = try frontend.makeDecoder(stopSequences: Array(repeating: "x", count: 17)) }
  try refuses { _ = try frontend.makeDecoder(stopSequences: [String(repeating: "x", count: 257)]) }
  let ended = try frontend.makeDecoder()
  _ = try ended.finish()
  try refuses { _ = try ended.append(1) }
  try refuses { _ = try ended.finish() }
  let failed = try frontend.makeDecoder()
  try refuses { _ = try failed.append(SplashTextFrontend.vocabularySize) }
  try refuses { _ = try failed.finish() }
  let tool = SplashOutputTool(name: "read", parameters: ["id": ["string"]])
  let call =
    "<tool_call>\n<function=read>\n<parameter=id>\nsource-1\n</parameter>\n</function>\n</tool_call>"
  for reason in [SplashWire.Finish.stop, .length, .cancelled] {
    let stream = try SplashOutputStream(frontend: frontend, tools: [tool])
    var streamed: [SplashOutputDelta] = []
    for token in frontend.encode("Looking.\n" + call) {
      streamed += try stream.append(tokens: [token])
    }
    let (result, _) = try stream.finish(reason)
    let text = streamed.compactMap {
      if case .text(let value) = $0 { return value }
      return nil
    }.joined()
    guard result.calls.count == (reason == .stop ? 1 : 0), result.text == "Looking.\n",
      text == "Looking.\n"
    else {
      throw SplashError("Generation pipeline terminal gating failed")
    }
  }
  let stopped = try SplashOutputStream(frontend: frontend, tools: [tool], stopSequences: ["STOP"])
  _ = try stopped.append(tokens: frontend.encode(call + "STOP"))
  guard try stopped.finish(.stop).0.calls.isEmpty else {
    throw SplashError("Stop sequence authorized a tool")
  }
  print("PASS decoder lifecycle, invalid token and stop limits")
}

private func checkProjection() throws {
  let root =
    try JSONSerialization.jsonObject(
      with: Data(
        contentsOf:
          Bundle.module.url(forResource: "output-fixtures", withExtension: "json")!))
    as! [String: Any]
  let tools = (root["tools"] as! [[String: Any]]).map {
    SplashOutputTool(
      name: $0["name"] as! String,
      parameters: ($0["parameters"] as! [String: [String]]).mapValues(Set.init))
  }
  let projections = root["projections"] as! [[String: Any]]
  var runs = 0
  func canonical(_ value: Any) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
  }
  for fixture in projections {
    let output = fixture["output"] as! String
    let scalars = output.unicodeScalars.map(String.init)
    var splits = [[output], scalars]
    for index in 0...scalars.count {
      splits.append([scalars[..<index].joined(), scalars[index...].joined()])
    }
    for split in splits {
      let parser = try SplashOutputParser(
        tools: fixture["tools"] as! Bool ? tools : [],
        thinking: fixture["thinking"] as! Bool, structured: fixture["structured"] as! Bool)
      var deltas: [SplashOutputDelta] = []
      for chunk in split { deltas += try parser.append(chunk) }
      let (result, tail) = try parser.finish(.stop)
      deltas += tail
      let text = deltas.compactMap {
        if case .text(let value) = $0 { return value }
        return nil
      }.joined()
      let reasoning = deltas.compactMap {
        if case .reasoning(let value) = $0 { return value }
        return nil
      }.joined()
      guard result.text.utf8.elementsEqual((fixture["text"] as! String).utf8),
        result.reasoning.utf8.elementsEqual((fixture["reasoning"] as! String).utf8),
        text.utf8.elementsEqual(result.text.utf8),
        reasoning.utf8.elementsEqual(result.reasoning.utf8)
      else {
        throw SplashError(
          "Projection text differs: \(fixture["name"]!) actual \(result.text.debugDescription) expected \((fixture["text"] as! String).debugDescription)"
        )
      }
      let expected = fixture["calls"] as! [[String: Any]]
      guard result.calls.count == expected.count else {
        throw SplashError("Projection call count differs: \(fixture["name"]!)")
      }
      for (call, expected) in zip(result.calls, expected) {
        let arguments = try JSONSerialization.jsonObject(with: call.arguments)
        guard call.name == expected["name"] as? String,
          try canonical(arguments) == canonical(expected["arguments"]!)
        else {
          throw SplashError(
            "Projection arguments differ: \(fixture["name"]!) actual \(String(decoding: call.arguments, as: UTF8.self))"
          )
        }
      }
      runs += 1
    }
  }
  print("PASS \(projections.count) upstream output projections across \(runs) chunk layouts")
  func refuses(_ text: String) throws {
    let parser = try SplashOutputParser(tools: tools)
    var refused = false
    do {
      _ = try parser.append(text)
      _ = try parser.finish(.stop)
    } catch { refused = true }
    guard refused else { throw SplashError("Unsafe tool projection was accepted") }
    var poisoned = false
    do { _ = try parser.append("next") } catch { poisoned = true }
    guard poisoned else { throw SplashError("Failed output parser was reused") }
  }
  let call = projections.first { $0["name"] as? String == "one_call" }!["output"] as! String
  try refuses(call.replacingOccurrences(of: "find_evidence", with: "unavailable"))
  try refuses(call.replacingOccurrences(of: "parameter=query", with: "parameter=unknown"))
  try refuses(call.replacingOccurrences(of: "parameter=limit", with: "parameter=query"))
  try refuses("<tool_call>\n<function=" + String(repeating: "x", count: 257))
  try refuses(
    "<tool_call>\n<function=find_evidence>\n<parameter=query>\n"
      + String(repeating: "x", count: 256 * 1024 + 1))
  try refuses(String(repeating: "x", count: SplashTextStream.maximumBytes + 1))
  try refuses(String(repeating: call, count: 17))
  // A value the workbook cannot keep comes back for correction instead of ending the request.
  func corrected(_ text: String, _ reason: String) throws {
    let parser = try SplashOutputParser(tools: tools)
    _ = try parser.append(text)
    let output = try parser.finish(.stop).0
    guard output.calls.isEmpty, output.refusal?.contains(reason) == true else {
      throw SplashError("A refused tool argument did not come back as a refusal")
    }
  }
  func tags(_ json: String) -> String {
    "<tool_call>\n<function=find_evidence>\n<parameter=tags>\n" + json
      + "\n</parameter>\n</function>\n</tool_call>"
  }
  try corrected(
    call.replacingOccurrences(of: "\n4\n", with: "\n9223372036854775808\n"), "Tool integer")
  try corrected(
    tags(String(repeating: "[", count: 40) + "0" + String(repeating: "]", count: 40)),
    "structure exceeds")
  try corrected(tags(#"[{"a":1,"a":2}]"#), "repeats a key")
  try corrected(tags("[1234567890123456.789]"), "more digits")
  let scalars = call.unicodeScalars.map(String.init)
  for length in 0...scalars.count {
    let cut = scalars.prefix(length).joined()
    for reason in [SplashWire.Finish.length, .cancelled] {
      let parser = try SplashOutputParser(tools: tools)
      _ = try parser.append(cut)
      guard try parser.finish(reason).0.calls.isEmpty else {
        throw SplashError("Incomplete output exposed a tool")
      }
    }
  }
  for cut in [
    "<tool_call>\n<function=", "<tool_call>\n<function=find_evidence>",
    "<tool_call>\n<function=find_evidence>\n<parameter=query>",
    "<tool_call>\n<function=find_evidence>\n<parameter=query>\nincomplete",
  ] { try refuses(cut) }
  let complete = try SplashOutputParser(tools: tools)
  _ = try complete.append(call)
  _ = try complete.finish(.stop)
  var refusedTwice = false
  do { _ = try complete.finish(.stop) } catch { refusedTwice = true }
  guard refusedTwice else { throw SplashError("Complete output parser reused") }
  print(
    "PASS unknown/duplicate/malformed/oversized tool refusal and every cancellation/truncation boundary"
  )
}
