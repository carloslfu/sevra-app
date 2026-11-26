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
    let name: String
    let args: Value
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
      args = .object(["query": .string("Supplier")])
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
    return .init(text: "", calls: [try .init(id: identifier(), operation: name, args, scope: toolScope)])
  }
}

func checkApplicationTools() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-application-tools-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
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
        "kind": .string("action"), "title": .string("Supplier report"),
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
      "title": .string("Supplier memo"), "body": .string("Oak Supply appears to be cheaper."),
      "evidence": .string(source.id), "meaning": .string("estimate"), "scenario": .string("actual"),
    ])
    let model = ApplicationToolModel(
      formID: form.id, input: input, evidence: source.id,
      verdictMode: previewOnly ? "previewOnly" : "documentSubmit")
    let result = try await WorkbookAgent.run(
      previewOnly
        ? "Preview the supplier memo; save nothing."
        : "Use the saved form to draft the supplier memo.",
      workbook: book, model: model)
    try expectEqual(try book.items(kind: "document").isEmpty, true)
    try expectEqual(try book.items(kind: "application_invocation").isEmpty, true)
    if previewOnly {
      try expectEqual(result.answer.contains("Supplier memo"), true)
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
            && $0["result"]["error"].text.contains("workspace_action form.submit")
        }, true)
    }
    try expectEqual(try book.verify()["ok"], .bool(true))
  }
  print(
    "PASS document action preview identifies meaning and new prose; unreviewed direct preparation stays closed and routes to conversational form submission"
  )
  try expectEqual(InferenceToolScope.all.allows("prepare_action"), true)
  try expectEqual(InferenceToolScope.answer.allows("prepare_action"), false)
  let row: Value = .object([
    "values": .object(["count": .string("2")]),
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
    "PASS visible query rows are the evidence a definition result offers, and aggregates or omitted rows offer none"
  )
}
