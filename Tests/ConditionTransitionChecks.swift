import Foundation
import SevraCore

func checkConditionTransitions() {
  func definition(_ op: String = "<", _ threshold: String = "10", scope: String = "stock:bolts")
    -> Value
  {
    .object([
      "policy": .string("native-condition-v1"), "scope": .string(scope),
      "operator": .string(op), "threshold": .string(threshold),
    ])
  }
  func observation(_ id: String, _ number: String?) -> Value {
    if let number { return .object(["id": .string(id), "value": .string(number)]) }
    return .object([
      "id": .string(id), "value": .null, "reason": .string("Missing complete input."),
    ])
  }
  func plan(_ values: [String?], rule: Value? = nil) throws -> Value {
    try NativeConditionRule(rule ?? definition()).preview(
      .array(values.enumerated().map { observation("v" + String($0.offset), $0.element) }))
  }
  func dispositions(_ result: Value) -> [String] {
    result["observations"].array.map { $0["disposition"].text }
  }

  check("condition rules require exact typed fields and normalize plain decimal identity") {
    let original = definition("<", "+0010.000")
    let rule = try NativeConditionRule(original)
    try expect(rule.definition == definition())
    try expect(try NativeConditionRule(rule.definition).definition == rule.definition)
    try expect(
      try NativeConditionRule(definition("=", "-000.00")).definition["threshold"] == .string("0"))
    for (key, value) in [
      ("policy", Value.string("condition-v0")), ("scope", .number(1)),
      ("operator", .string("< 10; run")), ("threshold", .number(10)), ("extra", .null),
    ] {
      var fields = original.object
      fields[key] = value
      try refuses("condition") { _ = try NativeConditionRule(.object(fields)) }
    }
    for scope in ["", " whitespace", "line\nbreak", String(repeating: "x", count: 257)] {
      try refuses("condition_limit") { _ = try NativeConditionRule(definition(scope: scope)) }
    }
  }
  check("all six numeric comparisons retain exact equality boundaries") {
    let expected: [String: [Bool]] = [
      "<": [true, false, false], "<=": [true, true, false],
      ">": [false, false, true], ">=": [false, true, true],
      "=": [false, true, false], "<>": [true, false, true],
    ]
    for (op, truths) in expected {
      let result = try plan(["9.999", "10.000", "10.001"], rule: definition(op))
      try expect(result["observations"].array.map { $0["truth"] } == truths.map(Value.bool))
    }
    let exact = try plan(
      ["9007199254740992.0000000000000001", "9007199254740992.0000000000000002"],
      rule: definition(">", "9007199254740992.0000000000000001"))
    try expect(exact["transitionCount"].int == 1)
  }
  check("an initially true or unknown condition cannot invent a crossing") {
    for values: [String?] in [["5"], [nil, "5"], [nil, nil, "5", "4"]] {
      let result = try plan(values)
      try expect(result["transitionCount"].int == 0 && result["lastCertainTruth"] == .bool(true))
      try expect(
        result["observations"].array.filter { $0["disposition"] == .string("baseline") }.count == 1)
    }
    let empty = try plan([])
    try expect(empty["lastCertainTruth"] == .null && empty["unresolvedGap"] == .bool(false))
    let unknown = try plan([nil, nil])
    try expect(unknown["lastCertainTruth"] == .null && unknown["unresolvedGap"] == .bool(true))
  }
  check("remaining below a threshold produces one transition until a known reset") {
    let result = try plan(["20", "9", "8", "8", "0", "-1"])
    try expect(
      dispositions(result) == [
        "baseline", "transition", "unchanged", "unchanged", "unchanged", "unchanged",
      ])
    try expect(result["transitionCount"].int == 1)
  }
  check("independent re-crossings and corrections keep distinct candidate identities") {
    let result = try plan(["20", "5", "11", "5", "10", "9"])
    let transitions = result["transitions"].array
    try expect(transitions.map { $0["id"].text } == ["v1", "v3", "v5"])
    try expect(Set(transitions.map { $0["occurrenceID"].text }).count == 3)
    try expect(dispositions(result).filter { $0 == "reset" }.count == 2)
  }
  check("unknown observations do not reset truth and label uncertain transition coverage") {
    let fire = try plan(["20", nil, "5"])
    try expect(fire["transitions"].array.count == 1)
    try expect(fire["transitions"].array[0]["coverageGap"] == .bool(true))
    try expect(fire["transitions"].array[0]["previousCertainObservationID"] == .string("v0"))
    try expect(try plan(["5", nil, "5"])["transitionCount"].int == 0)
    let reset = try plan(["5", nil, "20", "5"])
    try expect(reset["transitionCount"].int == 1)
    try expect(reset["transitions"].array[0]["coverageGap"] == .bool(false))
    try expect(try plan(["20", nil])["unresolvedGap"] == .bool(true))
  }
  check("duplicate delivery cannot rewind state or consume an independent crossing") {
    let values = [
      observation("a", "20"), observation("b", "05.00"), observation("c", "20"),
      observation("b", "+5"), observation("d", "5"), observation("c", "020.000"),
      observation("e", "5"),
    ]
    let result = try NativeConditionRule(definition()).preview(.array(values))
    try expect(result["uniqueCount"].int == 5 && result["transitionCount"].int == 2)
    try expect(
      dispositions(result) == [
        "baseline", "transition", "reset", "duplicate", "transition", "duplicate", "unchanged",
      ])
    let unknown = observation("missing", nil)
    let noRepeat = try NativeConditionRule(definition()).preview(
      .array([unknown, observation("a", "20"), unknown, observation("b", "5")]))
    try expect(noRepeat["transitions"].array[0]["coverageGap"] == .bool(false))
  }
  check("changed content under one observation identity refuses the entire preview") {
    let rule = try NativeConditionRule(definition())
    for values in [
      [observation("a", "20"), observation("b", "5"), observation("a", "5")],
      [observation("a", nil), observation("a", "20")],
      [observation("a", "5"), observation("a", nil)],
    ] {
      try refuses("condition_identity") { _ = try rule.preview(.array(values)) }
    }
  }
  check("candidate identities are stable across delivery but change with rule and scope") {
    let values = ["20", "5"]
    let first = try plan(values)
    try expect(try plan(values) == first)
    try expect(try plan(values, rule: definition("<", "010.00")) == first)
    let id = first["transitions"].array[0]["occurrenceID"]
    try expect(
      try plan(values, rule: definition("<", "11"))["transitions"].array[0]["occurrenceID"] != id)
    try expect(
      try plan(values, rule: definition(scope: "stock:other"))["transitions"].array[0][
        "occurrenceID"] != id)
    try expect(first["businessEvidence"] == .bool(false) && first["execution"] == .string("inert"))
    try expect(
      first["enabled"] == .bool(false) && first["scope"] == .string("fixture-observations"))
  }
  check("observation shapes, unknown reasons and numeric precision refuse ambiguity") {
    let rule = try NativeConditionRule(definition())
    let malformed: [Value] = [
      .null, .object([:]), .object(["id": .string("x")]),
      .object(["id": .string("x"), "value": .number(5)]),
      .object(["id": .string("x"), "value": .string("5"), "reason": .string("known")]),
      .object(["id": .string("x"), "value": .null, "reason": .bool(false)]),
    ]
    for value in malformed { try refuses("condition") { _ = try rule.preview(.array([value])) } }
    try refuses("condition") { _ = try rule.preview(.object([:])) }
    for number in ["NaN", "1e10", "1,000", " 1", "."] {
      try refuses("number") { _ = try plan([number]) }
    }
    try refuses("precision") { _ = try plan([String(repeating: "1", count: 39)]) }
    try refuses("condition_limit") { _ = try plan([String(repeating: "0", count: 129)]) }
    try refuses("condition_limit") {
      _ = try rule.preview(
        .array([.object(["id": .string("x"), "value": .null, "reason": .string(" ")])]))
    }
  }
  check("count and encoded-byte budgets are enforced before transition publication") {
    let rule = try NativeConditionRule(definition())
    let hundred = (0..<100).map { observation("v" + String($0), $0 % 2 == 0 ? "20" : "5") }
    try expect(try rule.preview(.array(hundred))["transitionCount"].int == 50)
    try refuses("condition_limit") {
      _ = try rule.preview(.array(hundred + [observation("extra", "5")]))
    }
    let large: [Value] = (0..<100).map {
      .object([
        "id": .string(String($0) + String(repeating: "x", count: 200)),
        "value": .null, "reason": .string(String(repeating: "r", count: 512)),
      ])
    }
    try refuses("condition_limit") { _ = try rule.preview(.array(large)) }
  }
  check("all 243 five-observation truth trajectories retain only known false-to-true changes") {
    for encoded in 0..<243 {
      var code = encoded
      var values: [String?] = []
      for _ in 0..<5 {
        values.append(["20", "5", nil][code % 3])
        code /= 3
      }
      let certain = values.enumerated().compactMap { pair -> (Int, Bool)? in
        pair.element.map { (pair.offset, $0 == "5") }
      }
      let expected = zip(certain, certain.dropFirst()).filter { !$0.0.1 && $0.1.1 }.map {
        "v" + String($0.1.0)
      }
      let result = try plan(values)
      try expect(result["transitions"].array.map { $0["id"].text } == expected)
      try expect(result["lastCertainTruth"] == (certain.last.map { .bool($0.1) } ?? .null))
    }
  }
  check("canceled previews refuse even empty input and never return partial candidates") {
    let control = Cancellation()
    control.cancel(reason: "Preview cancelled.")
    let rule = try NativeConditionRule(definition())
    for values in [Value.array([]), .array([observation("a", "20"), observation("b", "5")])] {
      try refuses("cancelled") { _ = try rule.preview(values, cancellation: control) }
    }
  }
}
