import Foundation
import SevraAI
import SevraCore

func checkNativeReviewInputContracts(
  package: NativeAppPackage, tables: [Dataset], coordinates: [[Int]], header: String
) throws {
  let paired = try Value.parse(
    #"{"probes":[{"action":"ship","inputs":{"quantity":3},"inputRoles":{"quantity":{"kind":"number","maximum":null,"minimum":0,"nonzero":true,"whole":false}},"expect":[{"kind":"expect_row","table":"ledger","values":{"reference":"NEW","quantity":"-3"}}]},{"action":"ship","inputs":{"quantity":0},"expect":[{"kind":"reject"}]}]}"#
  )
  let expanded = try NativeAppReview.actionProbes(paired, actions: ["ship"]).steps
  try expectEqual(expanded.count, 3)
  try expectEqual(expanded[0]["kind"], .string("run_action"))
  try expectEqual(expanded[0]["inputs"]["quantity"], .number(3))
  try expectEqual(expanded[1], paired["probes"].array[0]["expect"].array[0])
  try expectEqual(expanded[2]["reject"], .bool(true))
  try expectEqual(NativeAppReview.assertedSuccessfulActions(expanded), ["ship"])
  var multiple = paired.object
  var successful = paired["probes"].array[0].object
  successful["expect"] = .array([
    successful["expect"]!.array[0],
    .object(["kind": .string("expect_text"), "value": .string("Remaining 7")]),
  ])
  multiple["probes"] = .array([.object(successful), paired["probes"].array[1]])
  let effects = try NativeAppReview.actionProbes(.object(multiple), actions: ["ship"]).steps
  try expectEqual(
    effects.map { $0["kind"].text },
    ["run_action", "expect_row", "expect_text", "run_action"])
  try expectEqual(effects[3]["reject"], .bool(true))
  let sharedReference = try Value.parse(
    #"{"probes":[{"action":"plan","inputs":{"reference":"NEW"},"inputRoles":{"reference":{"kind":"value"}},"expect":[{"kind":"expect_row","table":"sheet1","values":{"c1":"NEW"}}]},{"action":"complete","inputs":{"reference":"NEW"},"inputRoles":{"reference":{"kind":"existingKey","table":"sheet1","column":"c1","headerRow":1}},"expect":[{"kind":"expect_row","table":"sheet1","values":{"c1":"NEW","c2":"Completed"}}]}]}"#
  )
  let shared = try NativeAppReview.actionProbes(sharedReference, actions: ["plan", "complete"])
  try expectEqual(shared.inputRoles["plan"]["reference"]["kind"], .string("value"))
  try expectEqual(shared.inputRoles["complete"]["reference"]["kind"], .string("existingKey"))
  try expectEqual(
    shared.steps.map { $0["kind"].text }, ["run_action", "expect_row", "run_action", "expect_row"])
  var conflicting = sharedReference.object
  var second = sharedReference["probes"].array[1].object
  second["action"] = .string("plan")
  conflicting["probes"] = .array([sharedReference["probes"].array[0], .object(second)])
  try expectThrows(try NativeAppReview.actionProbes(.object(conflicting), actions: ["plan"]))
  for invalid in [
    #"{"tests":[{"kind":"expect_text","value":"Ready"}]}"#,
    #"{"probes":[]}"#,
    #"{"probes":[{"action":"ship","inputs":{},"expect":[]}]}"#,
    #"{"probes":[{"action":"ship","inputs":{},"expect":{"kind":"reject"}}]}"#,
    #"{"probes":[{"action":"ship","inputs":{},"expect":[{"kind":"reject"},{"kind":"expect_text","value":"Done"}]}]}"#,
    #"{"probes":[{"action":"typo","inputs":{},"expect":[{"kind":"reject"}]}]}"#,
    #"{"probes":[{"action":"ship","inputs":{},"inputRoles":{},"expect":[{"kind":"expect_rows","table":"ledger","count":1}]}]}"#,
    #"{"probes":[{"action":"ship","inputs":{},"inputRoles":{},"expect":[{"kind":"expect_row","table":"ledger","values":{}}]}]}"#,
    #"{"probes":[{"action":"ship","inputs":{"quantity":3},"inputRoles":{"quantity":{"kind":"number"}},"expect":[{"kind":"expect_row","table":"ledger","values":{"quantity":-3}}]}]}"#,
    #"{"probes":[{"action":"ship","inputs":{"quantity":3},"expect":[{"kind":"expect_text","value":"Saved"}]}]}"#,
    #"{"probes":[{"action":"ship","inputs":{"quantity":3},"inputRoles":{"wrong":{"kind":"value"}},"expect":[{"kind":"expect_text","value":"Saved"}]}]}"#,
    #"{"probes":[{"action":"ship","inputs":{},"inputRoles":{},"expect":[{"kind":"reject"}]}]}"#,
    #"{"probes":[{"action":"ship","inputs":{},"expect":[{"kind":"reject","error":false}]}]}"#,
    #"{"probes":[{"action":"ship","inputs":{}}]}"#,
    #"{"probes":[{"action":"ship","inputs":{},"expect":[{"kind":"reject"}],"source":"execute me"}]}"#,
  ] {
    try expectThrows(try NativeAppReview.actionProbes(Value.parse(invalid), actions: ["ship"]))
  }
  var hiddenCall = paired.object
  hiddenCall["interfaceTests"] = .array([expanded[0]])
  try expectThrows(try NativeAppReview.actionProbes(.object(hiddenCall), actions: ["ship"]))
  var oversized = paired.object
  oversized["probes"] = .array(Array(repeating: paired["probes"].array[0], count: 9))
  try expectThrows(try NativeAppReview.actionProbes(.object(oversized), actions: ["ship"]))
  // An unchanged retry gets its own prior diagnostic, never another candidate's
  // fixture/source/test context, another request's state, or a passed check.
  let arguments: Value = .object([
    "package": .object(["source": .string("first")]),
    "fixtures": .object(["rows": .array([])]), "tests": .array([.string("first")]),
  ])
  let metric: Value = .object([
    "host": .string("native_app_review_probe"),
    "probe": .object(["result": .object(["error": .string("Correct test setup")])]),
  ])
  var retry = NativeAppReviewRetry()
  try expectEqual(try retry.context(for: arguments), .null)
  retry.observe(metric, receiptID: "prior-review")
  try expectEqual(try retry.context(for: arguments)["receiptID"], .string("prior-review"))
  for key in ["package", "fixtures", "tests"] {
    _ = try retry.context(for: arguments)
    retry.observe(metric, receiptID: "prior-review")
    var changed = arguments.object
    changed[key] = .string("different")
    try expectEqual(try retry.context(for: .object(changed)), .null)
  }
  _ = try retry.context(for: arguments)
  retry.observe(
    .object(["host": .string("other"), "probe": .string("unrelated")]), receiptID: "other")
  try expectEqual(try retry.context(for: arguments), .null)
  retry.observe(
    .object([
      "host": .string("native_app_review_probe"),
      "probe": .object([
        "verdict": .string(String(repeating: "x", count: 20_000)),
        "result": .object(["error": .string("Retain this bounded diagnostic")]),
      ]),
    ]), receiptID: "large")
  let bounded = try retry.context(for: arguments)
  try expectEqual(bounded["probe"]["verdict"], .null)
  try expectEqual(bounded["probe"]["result"]["error"], .string("Retain this bounded diagnostic"))
  try expectEqual(try bounded.json().utf8.count < 16_384, true)
  for hostileText in [
    "a" + String(repeating: "\u{301}", count: 20_000),
    String(repeating: "\u{1}", count: 20_000),
  ] {
    retry.observe(
      .object([
        "host": .string("native_app_review_probe"),
        "probe": .object([
          "result": .object([
            "status": .string(hostileText), "error": .string(hostileText),
          ])
        ]),
      ]), receiptID: "bounded-unicode")
    try expectEqual(try retry.context(for: arguments).json().utf8.count < 16_384, true)
  }
  retry.discard()
  try expectEqual(try retry.context(for: arguments), .null)
  var otherRequest = NativeAppReviewRetry()
  try expectEqual(try otherRequest.context(for: arguments), .null)
  let roles = try Value.parse(
    #"{"lookup":{"key":{"kind":"existingKey","table":"sheet1","column":"c1","headerRow":1},"reference":{"kind":"value"}}}"#
  )
  let steps = try Value.parse(
    #"[{"kind":"expect_text","value":"Ready"},{"kind":"run_action","action":"lookup","inputs":{"key":"ENTITY","reference":"NEW"}},{"kind":"expect_text","value":"ENTITY"}]"#
  ).array
  let fixtures: Value = .object([
    "sheet1": .array([.object(["c1": .string(header)]), .object(["c1": .string("ENTITY")])])
  ])
  let evidence: Value = .object(["sheet1!A1": .string(header)])
  func probes(
    _ classification: Value, _ rows: Value = fixtures, _ cells: Value = evidence,
    steps calls: [Value] = steps, contracts: Value = .null
  ) throws
    -> [Value]
  {
    var types: [String: Value] = [:]
    for (index, call) in calls.enumerated() where call["kind"] == .string("run_action") {
      types[String(index)] = .object(
        call["inputs"].object.mapValues { value in
          if case .number = value { return .string("number") }
          if case .bool = value { return .string("boolean") }
          return .string("text")
        })
    }
    return try NativeAppReview.inputProbes(
      actions: ["lookup"], roles: classification, steps: calls, fixtures: rows,
      inputTypes: .object(types), contracts: contracts, package: package, tables: tables,
      coordinates: coordinates,
      inputCell: { cells[$0] })
  }
  let plausibleCustomerKeys: Value = .object([
    "sheet1": .array([
      .object(["c1": .string(header)]),
      .object(["c1": .string("ENTITY")]),
      .object(["c1": .string("SECOND")]),
    ])
  ])
  let declaredText: Value = .object([
    "lookup": .object([
      "key": .object(["title": .string(header), "type": .string("text")]),
      "reference": .object(["title": .string("Reference"), "type": .string("text")]),
    ])
  ])
  let unclassified = try Value.parse(
    #"{"lookup":{"key":{"kind":"value"},"reference":{"kind":"value"}}}"#)
  try expectThrows(try probes(unclassified, plausibleCustomerKeys, contracts: declaredText))
  let withoutHeader: Value = .object([
    "sheet1": .array(Array(plausibleCustomerKeys["sheet1"].array.dropFirst()))
  ])
  try expectThrows(try probes(unclassified, withoutHeader, contracts: declaredText))
  try expectEqual(
    try probes(roles, plausibleCustomerKeys, contracts: declaredText).count, 1)
  var newValue = steps
  var call = newValue[1].object
  var fields = newValue[1]["inputs"].object
  fields["key"] = .string("Novel text")
  call["inputs"] = .object(fields)
  newValue[1] = .object(call)
  try expectEqual(
    try probes(
      unclassified, withoutHeader, steps: newValue, contracts: declaredText
    ).count, 0)
  try expectEqual(
    try probes(
      unclassified, plausibleCustomerKeys, .object(["sheet1!A1": .string("Another field")]),
      contracts: declaredText
    ).count, 0)
  let finiteValues: Value = .object([
    "lookup": .object([
      "key": .object([
        "title": .string(header), "type": .string("text"),
        "choices": .array([.string("ENTITY"), .string("SECOND")]),
      ]),
      "reference": declaredText["lookup"]["reference"],
    ])
  ])
  try expectEqual(try probes(unclassified, plausibleCustomerKeys, contracts: finiteValues).count, 0)
  let checked = try probes(roles)
  try expectEqual(checked.count, 1)
  try expectEqual(checked[0]["tests"].array.count, 2)
  try expectEqual(checked[0]["tests"].array[0], steps[0])
  try expectEqual(
    checked[0]["tests"].array[1]["inputs"],
    .object(["key": .string(header), "reference": .string("NEW")]))
  try expectEqual(checked[0]["tests"].array[1]["reject"], .bool(true))
  try expectEqual(steps[1]["inputs"]["key"], .string("ENTITY"))
  // Replay only setup, never the successful insert itself: its duplicate guard
  // must not make the subsequent invalid key appear to have been rejected.
  try expectEqual(checked[0]["tests"].array.filter { $0["kind"] == .string("run_action") }.count, 1)
  // A new reference cannot become a fabricated existing-key refusal.
  let newReference = try Value.parse(
    #"{"lookup":{"key":{"kind":"existingKey","table":"sheet1","column":"c1","headerRow":1},"reference":{"kind":"existingKey","table":"sheet1","column":"c1","headerRow":1}}}"#
  )
  try expectThrows(try probes(newReference))
  let preceding = try Value.parse(
    #"[{"kind":"run_action","action":"create","inputs":{"reference":"NEW"}},{"kind":"expect_row","table":"sheet1","values":{"c1":"NEW"}}]"#
  ).array
  let existing = try probes(newReference, steps: preceding + steps)
  try expectEqual(existing.count, 2)
  try expectEqual(Array(existing[1]["tests"].array.prefix(2)), preceding)
  for invalid in [Value.null, .object([:]), .object(["lookup": .object([:])])] {
    try expectThrows(try probes(invalid))
  }
  for (field, value) in [
    ("table", Value.string("foreign")), ("column", .string("c999")),
    ("headerRow", .number(999)), ("headerRow", .number(1.5)),
    ("kind", .string("unknown")), ("ignored", .bool(true)),
  ] {
    var key = roles["lookup"]["key"].object
    key[field] = value
    try expectThrows(
      try probes(
        .object([
          "lookup": .object([
            "key": .object(key), "reference": roles["lookup"]["reference"],
          ])
        ])))
  }
  try expectThrows(try probes(roles, .object([:]), evidence))
  try expectThrows(try probes(roles, fixtures, .object([:])))
  try expectThrows(try probes(roles, fixtures, .object(["sheet1!A1": .string("forged")])))
  try expectThrows(
    try probes(
      roles,
      .object([
        "sheet1": .array([.object(["c1": .string(header)]), .object(["c1": .string(header)])])
      ])))
  for value in [Value.number(42), .bool(true), .null, .array([])] {
    var call = steps[1].object
    call["inputs"] = .object(["key": value, "reference": .string("NEW")])
    let calls = [steps[0], .object(call), steps[2]]
    if value == .null || value == .array([]) {
      try expectThrows(try probes(roles, steps: calls))
    } else {
      try expectEqual(try probes(roles, steps: calls).count, 0)
    }
  }
}
