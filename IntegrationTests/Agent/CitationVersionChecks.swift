import Foundation
import SevraAI
import SevraCore

private actor VersionModel: WorkbookInference {
  let identity = "Synthetic citation freshness"
  let lastMetrics: Value = .null
  let old: Item
  let current: Item
  let dropsCitation: Bool
  var step = 0
  init(_ old: Item, _ current: Item, dropsCitation: Bool) {
    self.old = old
    self.current = current
    self.dropsCitation = dropsCitation
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    step += 1
    var tool = "read"
    var a: Value = .object(["id": .string(old.id)])
    if step == 2 {
      tool = "finish"
      a = .object([
        "answer": .string("The proposal is waiting for review."), "basis": .string("evidence"),
        "citations": .array([.string(old.id)]),
      ])
    } else if step == 3 {
      try expectEqual(toolScope, .inspection)
      try expectEqual(messages.last!.content.contains("A cited version is historical"), true)
      try expectEqual(messages.last!.content.contains(current.id), true)
      if dropsCitation {
        tool = "datasets"
        a = .object([:])
      } else {
        a = .object(["id": .string(current.id)])
      }
    } else if step == 4 && dropsCitation {
      tool = "finish"
      a = .object([
        "answer": .string("The proposal is waiting for review."), "basis": .string("general"),
        "citations": .array([]),
      ])
    } else if step == 5 && dropsCitation {
      try expectEqual(toolScope, .inspection)
      try expectEqual(messages.last!.content.contains(current.id), true)
      a = .object(["id": .string(current.id)])
    } else if step >= 4 {
      tool = "finish"
      a = .object([
        "answer": .string("The original version was a draft; it has since been withdrawn."),
        "basis": .string("evidence"), "citations": .array([.string(old.id), .string(current.id)]),
      ])
    }
    return .init(text: "", calls: [.init(id: identifier(), name: tool, inputJSON: try a.json())])
  }
}

func checkCitationVersions() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "citation-versions-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  for drops in [false, true] {
    let b = try Workbook.create(
      at: root.appendingPathComponent("\(drops).sevra"), title: "Versions")
    let input = try b.addItem(category: "source", kind: "assumption", title: "Sales assumption")
    let old = try b.addItem(
      category: "record", kind: "forecast", title: "Sales projection", meaning: "estimate",
      inputs: [input.id])
    let current = try b.withdrawDraft(old.id)
    let m = VersionModel(old, current, dropsCitation: drops)
    let answer = try await WorkbookAgent.run(
      "What was the original proposal, and is it still waiting for review?", workbook: b,
      context: "Selected historical proposal: \(old.id)", model: m)
    try expectEqual(answer.steps, drops ? 6 : 4)
    try expectEqual(answer.answer.contains("waiting for review"), false)
    try expectEqual(answer.answer.contains("version 2, withdrawn"), true)
    try expectEqual(answer.answer.contains("cited version 1 is historical"), true)
    try expectEqual(answer.citations.contains(old.id), true)
    try expectEqual(try b.item(old.id), old)
    try expectEqual(try b.item(old.logicalID), current)
    let outputs = try b.messages().filter { $0.role == "assistant" }
    try expectEqual(outputs.count, 1)
    let payload = try b.messagePayload(outputs[0].id)
    try expectEqual(payload["citationVersions"]["versions"].array.count, 2)
    try expectEqual(try b.verify()["ok"], .bool(true))
  }
  print(
    "PASS stale citation refusal, current-version refresh, citation-drop bypass refusal and preserved historical evidence"
  )
}
