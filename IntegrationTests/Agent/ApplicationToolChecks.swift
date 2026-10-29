import Foundation
import SevraAI
import SevraCore

private actor ApplicationToolModel: WorkbookInference {
  let identity = "synthetic application tools"
  let lastMetrics: Value = .object(["fixture": .bool(true)])
  let formID: String
  let input: Value
  let evidence: String
  let verdictMode: String
  var steps = 0
  var reviewInput: Value = .null
  var scopes: [InferenceToolScope] = []
  init(formID: String, input: Value, evidence: String, verdictMode: String = "valid") {
    self.formID = formID
    self.input = input
    self.evidence = evidence
    self.verdictMode = verdictMode
  }
  func beginRun() {}
  func endRun() {}
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    scopes.append(toolScope)
    var name: String
    var args: Value
    if toolScope == .actionDirection {
      reviewInput = try Value.parse(messages.last!.content)
      name = "review_action_directions"
      let values = reviewInput["movements"].array.map { movement -> Value in
        let index = movement["index"].int!
        let uncertain = verdictMode == "unclear" || (verdictMode == "lateUnclear" && index >= 10)
        return .object([
          "index": .number(Double(verdictMode == "duplicate" ? 0 : index)),
          "direction": .string(
            uncertain ? "unclear" : verdictMode == "opposite" ? "outgoing" : "incoming"),
          "basis": .string(uncertain ? "none" : "evidence"),
          "quote": .string(
            uncertain
              ? ""
              : verdictMode == "forged"
                ? "Invented receipt proof" : "We received 3 bolts and 2 nuts into our stock."),
        ])
      }
      args = .object([
        "directions": .array(verdictMode == "missing" ? Array(values.prefix(1)) : values)
      ])
    } else {
      steps += 1
      if verdictMode == "noPreview" {
        return .init(
          text: "",
          calls: [
            .init(
              id: identifier(), name: "finish",
              inputJSON: try Value.object([
                "answer": .string(
                  steps == 1 ? "Saved fabricated proposals." : "No preview is available."),
                "basis": .string(steps == 1 ? "preview" : "general"), "citations": .array([]),
              ]).json())
          ])
      }
      switch steps {
      case 1:
        name = "find_definitions"
        args = .object(["query": .string("Receive")])
      case 2:
        name = "read_definition"
        args = .object(["id": .string(formID)])
      case 3:
        name = "read"
        args = .object(["id": .string(evidence)])
      case 4:
        name = "preview_action"
        args = .object(["id": .string(formID), "arguments": input])
      case 5 where ["previewOnly", "overclaimRecover"].contains(verdictMode):
        name = "finish"
        args = .object([
          "answer": .string("Saved fabricated proposals."),
          "basis": .string(verdictMode == "previewOnly" ? "preview" : "evidence"),
          "citations": .array([.string(evidence)]),
        ])
      case let step where step == 5 || (step == 6 && verdictMode == "overclaimRecover"):
        name = "prepare_action"
        args = .object(["id": .string(formID), "arguments": input])
      default:
        name = "finish"
        args = .object([
          "answer": .string("I could not submit this action."),
          "basis": .string(
            ["readOnly", "documentSubmit"].contains(verdictMode) ? "preview" : "unresolved"),
          "citations": .array([]),
        ])
      }
    }
    return .init(text: "", calls: [.init(id: identifier(), name: name, inputJSON: try args.json())])
  }
}

func checkApplicationTools() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-application-tools-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  for mode in [
    "valid", "unclear", "opposite", "forged", "duplicate", "missing", "readOnly", "valid50",
    "lateUnclear", "previewOnly", "overclaimRecover", "noPreview", "technical",
  ] {
    let book = try Workbook.create(at: root.appendingPathComponent(mode + ".sevra"), title: mode)
    let source = try book.addItem(
      category: "source", kind: mode == "technical" ? "application_definition" : "observation",
      title: "R1",
      text: "We received 3 bolts and 2 nuts into our stock.")
    _ = try book.addMessage(
      "Prior assistant guess sentinel: assume every receipt is incoming.", role: "assistant")
    try book.setOpeningBalance(
      subject: "bolts", quantity: "20", effective: "2026-01-01", sourceID: source.id)
    let action = try book.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.receivingDefinition())
    let form = try book.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.formDefinition(target: action))
    let large = ["valid50", "lateUnclear"].contains(mode)
    let lines: [Value] =
      large
      ? (1...50).map {
        .object([
          "line": .string(String($0)), "subject": .string("bolts"), "quantity": .string("3"),
        ])
      }
      : [
        .object(["line": .string("1"), "subject": .string("bolts"), "quantity": .string("3")]),
        .object(["line": .string("2"), "subject": .string("nuts"), "quantity": .string("2")]),
      ]
    let input: Value = .object([
      "delivery": .string("R1"), "effective": .string("2026-10-28"), "evidence": .string(source.id),
      "lines": .array(lines),
    ])
    let model = ApplicationToolModel(
      formID: form.id, input: input, evidence: source.id, verdictMode: mode)
    let result = try await WorkbookAgent.run(
      mode == "readOnly"
        ? "Only preview the saved receiving form. Do not make changes."
        : "Use our saved receiving form for delivery R1 and prepare its proposals.",
      workbook: book, model: model)
    let valid = ["valid", "valid50", "overclaimRecover"].contains(mode)
    let count = large ? 50 : 2
    try expectEqual(try book.items(kind: "movement").count, valid ? count : 0)
    try expectEqual(try book.items(kind: "application_invocation").count, valid ? 1 : 0)
    try expectEqual(try book.balance(subject: "bolts")["quantity"], .string("20"))
    try expectEqual(result.state == "needs_review", valid)
    if valid {
      try expectEqual(result.answer.contains("Accepted balances are unchanged"), true)
      try expectEqual(result.citations.count, count)
      let invocation = try book.items(kind: "application_invocation")[0]
      try expectEqual(invocation.data["actor"]["kind"], .string("ai"))
      let input = await model.reviewInput
      let json = try input.json()
      try expectEqual(json.contains("Prior assistant guess sentinel"), false)
      try expectEqual(json.contains("primitive"), false)
      try expectEqual(input["movements"].array.allSatisfy { $0["quantity"] == .null }, true)
      try expectEqual(input["movements"].array.count, large ? 10 : 2)
      let receipt = try book.messages().filter { $0.role == "tool" }.map {
        try Value.parse($0.body)
      }.first { $0["tool"].text == "prepare_action" }
      let match = try book.toolResultPage(
        receipt!["receiptID"].text, path: ["directionReview", "matches"])
      try expectEqual(match["value"], .bool(true))
      if large { try expectEqual(await model.scopes.filter { $0 == .actionDirection }.count, 5) }
    }
    if ["previewOnly", "readOnly"].contains(mode) {
      try expectEqual(result.answer.contains("Preview only. No draft proposals were saved"), true)
      try expectEqual(result.answer.contains("fabricated"), false)
    }
    if ["overclaimRecover", "noPreview"].contains(mode) {
      let refusals = try book.messages().filter { $0.role == "tool" }.map {
        try Value.parse($0.body)
      }
      try expectEqual(
        refusals.contains { $0["tool"].text == "finish" && $0["validation"].string != nil }, true)
    }
    if mode == "technical" {
      let input = await model.reviewInput
      try expectEqual(input["evidence"].array.allSatisfy { $0["text"] == .string("") }, true)
    }
    if mode == "lateUnclear" {
      try expectEqual(await model.scopes.filter { $0 == .actionDirection }.count, 2)
    }
    if mode == "readOnly" { try expectEqual(await model.scopes.contains(.actionDirection), false) }
    try expectEqual(try book.unresolvedToolCalls().count, 0)
    try expectEqual(try book.verify()["ok"], .bool(true))
  }
  try expectEqual(InferenceToolScope.all.allows("review_action_directions"), false)
  for previewOnly in [true, false] {
    let book = try Workbook.create(
      at: root.appendingPathComponent(
        previewOnly ? "document-preview.sevra" : "document-submit.sevra"),
      title: "Report form")
    let source = try book.addItem(
      category: "source", kind: "observation", title: "R1", text: "Received 5 bolts.")
    let primitive = ActionRegistry.actions().array.first {
      $0["id"] == .string("records.draftDocument")
    }!
    let action = try book.saveApplicationDefinition(
      logicalID: identifier(),
      content: .object([
        "kind": .string("action"), "title": .string("Receiving report"),
        "description": .string("New report prose for review"),
        "parameters": primitive["parameters"],
        "payload": .object([
          "primitive": .object(["id": primitive["id"], "version": primitive["version"]]),
          "arguments": .object(
            Dictionary(
              uniqueKeysWithValues: primitive["parameters"].array.map {
                ($0["id"].text, Value.object(["parameter": $0["id"]]))
              })),
        ]),
      ]))
    let form = try book.saveApplicationDefinition(
      logicalID: identifier(), content: ActionRegistry.formDefinition(target: action))
    let input: Value = .object([
      "title": .string("Receiving memo"), "body": .string("Five bolts appear to have arrived."),
      "evidence": .string(source.id), "meaning": .string("estimate"), "scenario": .string("actual"),
    ])
    let model = ApplicationToolModel(
      formID: form.id, input: input, evidence: source.id,
      verdictMode: previewOnly ? "previewOnly" : "documentSubmit")
    let result = try await WorkbookAgent.run(
      previewOnly
        ? "Preview the receiving memo; save nothing."
        : "Use the saved form to draft the receiving memo.",
      workbook: book, model: model)
    try expectEqual(try book.items(kind: "document").isEmpty, true)
    try expectEqual(try book.items(kind: "application_invocation").isEmpty, true)
    try expectEqual(await model.scopes.contains(.actionDirection), false)
    if previewOnly {
      try expectEqual(result.answer.contains("Receiving memo"), true)
      try expectEqual(result.answer.contains("estimate"), true)
      try expectEqual(result.answer.lowercased().contains("new prose"), true)
      try expectEqual(result.answer.contains("fabricated"), false)
    } else {
      let failures = try book.messages().filter { $0.role == "tool" }.map {
        try Value.parse($0.body)
      }
      try expectEqual(
        failures.contains {
          $0["tool"] == .string("prepare_action")
            && $0["result"]["error"].text.contains("not qualified yet")
        }, true)
    }
    try expectEqual(try book.verify()["ok"], .bool(true))
  }
  print(
    "PASS document action preview identifies meaning and new prose; unqualified direct chat submission stays closed without inventory review"
  )
  try expectEqual(InferenceToolScope.actionDirection.allows("prepare_action"), false)
  try expectEqual(InferenceToolScope.propose_movement.allows("prepare_action"), true)
  try expectEqual(InferenceToolScope.draft.allows("prepare_action"), false)
  let unusual = "a" + String(repeating: "\u{301}", count: 30_000) + "incoming"
  let clipped = ActionDirectionReview.excerpt([unusual], maximumBytes: 320)
  try expectEqual(clipped.utf8.count <= 320 && unusual.utf8.starts(with: clipped.utf8), true)
  try expectEqual(ActionDirectionReview.excerpt(["💡"], maximumBytes: 3), "")
  let row: Value = .object([
    "values": .object(["stock": .string("2")]),
    "inputs": .array([.object(["versionID": .string("visible-row")])]),
  ])
  try expectEqual(
    WorkbookAgent.visibleEvidence(
      tool: "evaluate_definition",
      result: .object(["kind": .string("query"), "result": .object(["rows": .array([row])])])
    ).map { $0.0 }, ["visible-row"])
  try expectEqual(
    WorkbookAgent.visibleEvidence(
      tool: "evaluate_definition", result: row, path: ["result", "rows", "0"]
    ).map { $0.0 }, ["visible-row"])
  let aggregate: Value = .object(["values": .object(["total": .string("50")])])
  try expectEqual(
    WorkbookAgent.visibleEvidence(
      tool: "evaluate_definition", result: .array([aggregate]), path: ["result", "rows"]
    ).isEmpty, true)
  let omitted: Value = .object([
    "values": .object(["omitted": .bool(true), "type": .string("object")]), "inputs": row["inputs"],
  ])
  try expectEqual(
    WorkbookAgent.visibleEvidence(
      tool: "evaluate_definition", result: omitted, path: ["result", "rows", "0"]
    ).isEmpty, true)
  try expectEqual(
    WorkbookAgent.visibleEvidence(
      tool: "find_definitions", result: .object(["sourceID": .string("not-business-proof")])
    ).isEmpty, true)
  print(
    "PASS saved form discovery/inspection/preview/submission, isolated complete batch directions, exact quotes, malformed/wrong-sign/read-only refusal, AI lineage and draft-only review"
  )
}
