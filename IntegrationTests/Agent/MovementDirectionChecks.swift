import Foundation
import SevraAI
import SevraCore

private actor DirectionModel: WorkbookInference {
  let identity = "Synthetic inventory review"
  let lastMetrics: Value = .null
  let arguments: Value
  let verdict: Value
  var scopes: [InferenceToolScope] = []
  var reviewMessages: [InferenceMessage] = []
  init(_ arguments: Value, _ verdict: Value) {
    self.arguments = arguments
    self.verdict = verdict
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    scopes.append(toolScope)
    if toolScope == .movementDirection {
      reviewMessages = messages
      return .init(
        text: "",
        calls: [
          .init(id: identifier(), name: "review_movement_direction", inputJSON: try verdict.json())
        ])
    }
    return .init(
      text: "",
      calls: [.init(id: identifier(), name: "propose_movement", inputJSON: try arguments.json())])
  }
}

func checkMovementDirection() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "direction-" + identifier())
  defer { try? FileManager.default.removeItem(at: root) }
  let b = try Workbook.create(at: root, title: "Direction")
  let source = try b.addItem(
    category: "source", kind: "observation", title: "Receipt",
    text: "Two units handed over.")
  _ = try b.addMessage("Prior assistant guess sentinel: units entered stock.", role: "assistant")
  let args: Value = .object([
    "subject": .string("stock"), "quantity": .string("-2"),
    "occurrence": .string("delivery"), "effective": .string("2026-01-02"),
    "input": .string(source.id),
  ])
  let explicit = "Two units left our stock for the customer. Prepare a proposal."
  let verdict: Value = .object([
    "direction": .string("outgoing"), "basis": .string("request"),
    "quote": .string("Two units left our stock for the customer."),
  ])
  let uncertain = DirectionModel(
    args,
    .object([
      "direction": .string("unclear"),
      "basis": .string("none"), "quote": .string(""),
    ]))
  let refused = try await WorkbookAgent.run(
    "Prepare the receipt's movement.", workbook: b, model: uncertain)
  try expectEqual(refused.answer.contains("enter your stock or leave it"), true)
  try expectEqual(try b.items(kind: "movement").count, 0)
  try expectEqual(await uncertain.scopes, [.all, .movementDirection])
  let isolated = await uncertain.reviewMessages
  try expectEqual(isolated.count, 2)
  try expectEqual(
    isolated.map(\.content).joined().contains("Prior assistant guess sentinel"), false)
  try expectEqual(isolated.map(\.content).joined().contains("Two units handed over."), true)
  let forged = DirectionModel(args, verdict)
  _ = try await WorkbookAgent.run("Prepare the receipt's movement.", workbook: b, model: forged)
  try expectEqual(try b.items(kind: "movement").count, 0)
  var opposite = args.object
  opposite["quantity"] = .string("2")
  _ = try await WorkbookAgent.run(
    explicit, workbook: b, model: DirectionModel(.object(opposite), verdict))
  try expectEqual(try b.items(kind: "movement").count, 0)
  let valid = DirectionModel(args, verdict)
  let proposal = try await WorkbookAgent.run(explicit, workbook: b, model: valid)
  try expectEqual(proposal.state, "needs_review")
  try expectEqual(try b.items(kind: "movement").count, 1)
  let duplicate = DirectionModel(args, verdict)
  let stopped = try await WorkbookAgent.run(explicit, workbook: b, model: duplicate)
  try expectEqual(stopped.answer.contains("already has an inventory record"), true)
  try expectEqual(await duplicate.scopes, [.all, .movementDirection])
  try expectEqual(try b.items(kind: "movement").count, 1)
  for kind in Item.technicalKinds.sorted() {
    let technical = try b.addHostOwnedItem(
      category: "source", kind: kind, title: "Technical metadata",
      text: "We received 2 units into our stock.")
    var attempted = args.object
    attempted["input"] = .string(technical.id)
    attempted["occurrence"] = .string("technical-" + kind)
    attempted["quantity"] = .string("2")
    let reviewer = DirectionModel(
      .object(attempted),
      .object([
        "direction": .string("incoming"), "basis": .string("evidence"),
        "quote": .string("We received 2 units into our stock."),
      ]))
    _ = try await WorkbookAgent.run(
      "Prepare the referenced movement.", workbook: b, model: reviewer)
    let review = try Value.parse(await reviewer.reviewMessages.last!.content)
    try expectEqual(review["evidence"], .string(""))
    try expectEqual(try b.items(kind: "movement").count, 1)
  }
  let receipts = try b.messages().filter { $0.role == "tool" }.map { try Value.parse($0.body) }
  try expectEqual(
    receipts.contains { $0["result"]["directionReview"]["matches"] == .bool(true) }, true)
  try expectEqual(try b.unresolvedToolCalls().count, 0)
  try expectEqual(try b.verify()["ok"], .bool(true))
  try expectEqual(InferenceToolScope.all.allows("review_movement_direction"), false)
  try expectEqual(InferenceToolScope.movementDirection.allows("propose_movement"), false)
  print(
    "PASS isolated inventory direction, exact quotes, wrong-sign refusal, original history, draft-only success and terminal duplicate refusal"
  )
}
