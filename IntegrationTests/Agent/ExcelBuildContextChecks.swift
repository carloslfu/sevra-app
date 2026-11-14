import Foundation
import SevraAI
import SevraCore

func checkExcelBuildContext() throws {
  let system = InferenceMessage(role: "system", content: "Host policy")
  let request = InferenceMessage(role: "user", content: "Exact request and original evidence")
  func pair(_ id: String, _ tool: String, _ result: Value) throws -> [InferenceMessage] {
    [
      .init(
        role: "assistant", content: "candidate " + id,
        toolCalls: [.init(id: id, name: tool, inputJSON: "{\"candidate\":\"\(id)\"}")],
        reasoning: "obsolete reasoning " + id),
      .init(role: "tool", content: try result.json(), toolCallId: id, toolName: tool),
    ]
  }
  let error: Value = .object(["error": .string("Fix the actual defect")])
  let evidence = try pair("read", "inspect_excel_evidence", .string("Original VBA"))
  let oldComparison = try pair("oldCompare", "compare_excel_behavior", .string("matched"))
  let oldFailure = try pair("oldFailure", "save_native_app", error)
  let success = try pair("saved", "save_native_app", .object(["status": .string("saved_disabled")]))
  let latestComparison = try pair("badCompare", "compare_excel_behavior", error)
  let latestFailure = try pair("latestFailure", "save_native_app", error)
  let input =
    [system, request] + evidence + oldComparison + oldFailure + success
    + latestComparison + latestFailure
  let refreshed = ExcelBuildContext.refresh(input)
  try expectEqual(refreshed.prefix(2).map(\.content), [system.content, request.content])
  try expectEqual(
    refreshed.compactMap(\.toolCallId), ["read", "saved", "badCompare", "latestFailure"])
  try expectEqual(refreshed.allSatisfy { $0.reasoning.isEmpty }, true)
  try expectEqual(refreshed.last?.content, try error.json())
  try expectEqual(ExcelBuildContext.refresh(refreshed).map(\.content), refreshed.map(\.content))
  // Never discard an incomplete/mismatched group or confuse untrusted result prose with a call.
  let incomplete = try pair("pending", "save_native_app", error).prefix(1)
  let malformed = InferenceMessage(
    role: "tool", content: try error.json(), toolCallId: "unrelated", toolName: "save_native_app")
  let guarded = ExcelBuildContext.refresh(input + incomplete + [malformed])
  try expectEqual(guarded.suffix(2).map(\.content), (incomplete + [malformed]).map(\.content))

  func comparison(_ count: Int, version: String = "original-v1") -> Value {
    .object([
      "status": .string(count == 0 ? "matched" : "mismatch"),
      "conversionVersion": .string(version), "compared": .number(13),
      "differences": .array(Array(repeating: .object(["actual": .string("wrong")]), count: count)),
    ])
  }
  let first = try pair("first", "compare_excel_behavior", comparison(5))
  let best = try pair("best", "compare_excel_behavior", comparison(2))
  let regressed = try pair("regressed", "compare_excel_behavior", comparison(7))
  let anchored = ExcelBuildContext.refresh([system, request] + first + best + regressed)
  try expectEqual(anchored.compactMap(\.toolCallId), ["best", "regressed"])
  let projected = try Value.parse(anchored.last!.content)
  try expectEqual(projected["repairAnchor"]["toolCallID"], .string("best"))
  try expectEqual(projected["repairAnchor"]["reportedDifferences"], .number(2))
  try expectEqual(projected["status"], .string("mismatch"))
  try expectEqual(projected["differences"].array.count, 7)
  try expectEqual(ExcelBuildContext.refresh(anchored).map(\.content), anchored.map(\.content))
  let lostAnchor = ExcelBuildContext.refresh([system, request] + Array(anchored.suffix(2)))
  try expectEqual(try Value.parse(lostAnchor.last!.content)["repairAnchor"], .null)
  let improved = try pair("improved", "compare_excel_behavior", comparison(1))
  try expectEqual(
    ExcelBuildContext.refresh(anchored + improved).compactMap(\.toolCallId), ["improved"])
  let matched = try pair("matched", "compare_excel_behavior", comparison(0))
  try expectEqual(
    ExcelBuildContext.refresh(anchored + matched + regressed).compactMap(\.toolCallId),
    ["regressed"])
  let replacement = try pair("replacement", "compare_excel_behavior", comparison(8, version: "new"))
  try expectEqual(
    ExcelBuildContext.refresh(anchored + replacement).compactMap(\.toolCallId), ["replacement"])
  var large = comparison(1).object
  large["diagnostic"] = .string(String(repeating: "x", count: 24_001))
  let oversized = try pair("oversized", "compare_excel_behavior", .object(large))
  try expectEqual(
    ExcelBuildContext.refresh([system, request] + oversized + regressed).compactMap(\.toolCallId),
    ["regressed"])
}
