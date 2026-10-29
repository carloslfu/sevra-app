import Foundation
import SevraCore
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

func checkInterpretationGrammar(frontend: SplashTextFrontend, factory: SplashGrammarFactory) throws
{
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "interpretation-grammar-" + identifier() + ".sevra")
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook.create(at: root, title: "Synthetic interpretation grammar")
  let source = try book.addItem(
    category: "source", kind: "observation", title: "Missing count",
    text: "The count was not recorded.")
  let parameters: Value = .array([
    .object([
      "id": .string("evidence"), "label": .string("Evidence"), "type": .string("item"),
      "required": .bool(true),
    ])
  ])
  let definition = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("interpretation"), "title": .string("Read count"),
      "description": .string("Synthetic schema check"), "parameters": parameters,
      "payload": .object([
        "instruction": .string("Ask if count is missing."),
        "evidence": .array([.string("evidence")]),
        "outputs": .array([
          .object([
            "id": .string("quantity"), "label": .string("Count"), "type": .string("decimal"),
            "unit": .string("items"), "required": .bool(true),
          ]),
          .object([
            "id": .string("confirmed"), "label": .string("Confirmed"), "type": .string("boolean"),
            "required": .bool(false),
          ]),
        ]), "meaning": .string("actual"), "scenario": .string("actual"),
      ]),
    ]))
  let workflow = try book.saveApplicationDefinition(
    logicalID: identifier(),
    content: .object([
      "kind": .string("workflow"), "title": .string("Read"), "description": .string("Synthetic"),
      "parameters": parameters,
      "payload": .object([
        "readPolicy": .string("latest-at-step"),
        "steps": .array([
          .object([
            "id": .string("read"), "kind": .string("interpret"),
            "binding": .object(["mode": .string("exact"), "versionID": .string(definition.id)]),
            "arguments": .object(["evidence": .object(["parameter": .string("evidence")])]),
          ])
        ]),
      ]),
    ]))
  let run = try book.startWorkflow(
    workflow.id, arguments: .object(["evidence": .string(source.id)]), token: "start")
  let session = try book.authorizeWorkflowExecution(run["id"].text)
  let claim = try book.claimWorkflowStep(session, owner: "synthetic")
  let schema = try book.prepareWorkflowInterpretation(session, claim: claim, model: "synthetic")[
    "schema"]
  try expectThrows(
    try SplashToolPolicy.interpretationResult(schemaJSON: Data("{\"type\":\"string\"}".utf8)))
  func response(_ state: String, values: Value, issues: [Value] = []) -> Value {
    .object([
      "state": .string(state), "values": values, "citations": .array([]), "issues": .array(issues),
    ])
  }
  let valid = [
    response("needs_input", values: .object([:]), issues: [.string("Supply the missing count.")]),
    response("ready", values: .object(["quantity": .string("5")])),
    response("ready", values: .object(["quantity": .string("0"), "confirmed": .bool(false)])),
  ]
  let invalid = [
    response(
      "needs_input", values: .object(["quantity": .string("0")]),
      issues: [.string("Missing count.")]),
    response("needs_input", values: .object([:])),
    response("ready", values: .object([:])),
    response("ready", values: .object(["quantity": .null])),
  ]
  for thinking in [false, true] {
    let policy = try SplashToolPolicy.interpretationResult(
      schemaJSON: Data(schema.json().utf8), thinking: thinking)
    _ = try frontend.prepare(
      messages: [["role": "user", "content": "Read the count."]],
      tools: policy.promptTools(), thinking: thinking)
    func call(_ value: Value) throws -> (String, SplashToolCandidate) {
      // Native JSON grammar orders required fields before optional fields.
      let values = try ["quantity", "confirmed"].compactMap { name -> String? in
        guard let field = value["values"].object[name] else { return nil }
        return try Value.string(name).json() + ":" + field.json()
      }.joined(separator: ",")
      let response =
        try "{\"state\":" + value["state"].json()
        + ",\"values\":{" + values + "},\"citations\":[],\"issues\":"
        + value["issues"].json() + "}"
      let body =
        "<tool_call>\n<function=interpretation_result>\n<parameter=result>\n"
        + response + "\n</parameter>\n</function>\n</tool_call>"
      let parser = try SplashOutputParser(tools: policy.outputTools)
      _ = try parser.append(body)
      return (
        (thinking ? "Check the evidence.</think>" : "") + body,
        try expectValue(parser.finish(.stop).0.calls.first)
      )
    }
    for value in valid {
      let (text, candidate) = try call(value)
      let grammar = try factory.create(grammar: policy.grammar)
      try grammar.finish(committed: frontend.encode(text), requireComplete: true)
      try policy.validate(candidate)
    }
    for value in invalid {
      let (text, candidate) = try call(value)
      let grammar = try factory.create(grammar: policy.grammar)
      try expectThrows(
        try grammar.finish(committed: frontend.encode(text), requireComplete: true))
      try expectThrows(try policy.validate(candidate))
    }
  }
  print(
    "PASS interpretation grammar: needs_input has empty values and issues; ready requires typed fields; zero/false remain valid"
  )
}
