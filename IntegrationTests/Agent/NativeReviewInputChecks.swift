import Foundation
import SevraAI
import SevraCore

func checkNativeReviewInputContracts(
  package: NativeAppPackage, tables: [Dataset], coordinates: [[Int]], header: String
) throws {
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
    steps calls: [Value] = steps
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
      inputTypes: .object(types), package: package, tables: tables, coordinates: coordinates,
      inputCell: { cells[$0] })
  }
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
