import Foundation
import SevraAI
import SevraCore

/// Reports what today's chat tools do to a table when a model run asks for the change. Each
/// call goes through WorkbookAgent, so it runs under the AI actor a real model's run gets.
/// It asserts no outcome: one JSON line per operation says whether the workbook changed and
/// what the tool answered. Phase 1 of the general chat tools plan records this output.
func runModelActorTableProbe() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-model-actor-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: root) }
  let book = try Workbook(
    URL(fileURLWithPath: Demo.create(at: root.appendingPathComponent("Probe.sevra"))["path"].text))
  let tableID = try expectValue(try book.datasets().first { $0.title == "Supplier comparison" }).id

  func state() throws -> Value {
    let table = try book.dataset(tableID)
    return .object([
      "title": .string(table.title),
      "columns": .array(table.columns.map { .string($0.id + ":" + $0.title) }),
      "rows": .array(
        try book.rows(tableID).map { .object(book.calculatedValues($0, columns: table.columns)) }),
      "tables": .array(try book.datasets().map { .string($0.title) }),
      "drafts": .array(
        try book.items().filter { $0.status == "draft" }.map { .string($0.kind + ": " + $0.title) }),
    ])
  }
  func attempt(_ name: String, _ tool: String, _ arguments: () throws -> Value) async throws {
    let before = try state()
    let model = ScriptedCalls([call(tool, try arguments()), finish("Stopped.", basis: "unresolved")])
    var thrown: Value = .null
    var ended: Value = .null
    do {
      let result = try await WorkbookAgent.run(
        "Change the supplier table as asked.", workbook: book, model: model)
      ended = .object(["state": .string(result.state), "answer": .string(result.answer)])
    } catch {
      thrown = .string(error.localizedDescription)
    }
    // A call the host closes the turn on gives the model no second prompt to read.
    let answer = await model.prompts.dropFirst().first?.last { $0.role == "tool" }?.content
    let result = try answer.map(Value.parse) ?? .null
    let after = try state()
    print(
      try Value.object([
        "operation": .string(name), "tool": .string(tool),
        "actor": .string("ai, as WorkbookTools sets for a model run"),
        "workbookChanged": .bool(after != before),
        "toolError": result["error"], "runError": thrown, "turn": ended,
        "result": result["error"] == .null ? result : .null, "after": after,
      ]).json())
  }
  func tableAction(_ action: String, _ fields: [String: Value]) throws -> Value {
    let table = try book.dataset(tableID)
    var arguments = fields
    arguments["id"] = .string(tableID)
    arguments["expectedDefinitionID"] = .string(table.definitionID)
    if action != "table.change_rows" { arguments["expectedVersion"] = .number(Double(table.version)) }
    return .object(["action": .string(action), "arguments": .object(arguments)])
  }
  func row(_ supplier: String) throws -> String {
    try expectValue(try book.rows(tableID).first { $0.data["supplier"].text == supplier }).id
  }

  try await attempt("insert a row", "workspace_action") {
    try tableAction(
      "table.change_rows",
      [
        "operations": .array([
          .object([
            "op": .string("insert"),
            "values": .object([
              "supplier": .string("Birch Metals"), "quantity": .string("10"),
              "unit_cost": .string("2.55"),
            ]),
          ])
        ])
      ])
  }
  try await attempt("update a row", "workspace_action") {
    try tableAction(
      "table.change_rows",
      [
        "operations": .array([
          .object([
            "op": .string("update"), "id": .string(try row("Cedar Tools")),
            "values": .object(["unit_cost": .string("2.60")]),
          ])
        ])
      ])
  }
  try await attempt("delete a row", "workspace_action") {
    try tableAction(
      "table.change_rows",
      ["operations": .array([.object(["op": .string("delete"), "id": .string(try row("Oak Supply"))])])])
  }
  try await attempt("rename a column", "workspace_action") {
    var columns = try book.dataset(tableID).columns
    columns[0].title = "Vendor"
    return try tableAction("table.edit_schema", ["columns": try encoded(columns)])
  }
  try await attempt("add a column", "workspace_action") {
    let columns = try book.dataset(tableID).columns + [Column(id: "notes", title: "Notes")]
    return try tableAction("table.edit_schema", ["columns": try encoded(columns)])
  }
  try await attempt("rename the table", "workspace_action") {
    try tableAction("table.edit_schema", ["title": .string("Supplier quotes compared")])
  }
  try await attempt("draft a row update (proposal)", "propose_table_edit") {
    .object([
      "datasetID": .string(tableID),
      "edits": .array([
        .object([
          "id": .string(try row("Cedar Tools")),
          "values": .object(["unit_cost": .string("2.60")]),
        ])
      ]),
    ])
  }
  try await attempt("draft a new table (proposal)", "propose_table") {
    .object([
      "title": .string("Reorder levels"), "meaning": .string("plan"), "inputs": .array([]),
      "columns": .array([
        .object(["id": .string("item"), "title": .string("Item"), "type": .string("text")]),
        .object(["id": .string("level"), "title": .string("Level"), "type": .string("decimal")]),
      ]),
      "rows": .array([.object(["item": .string("Brass bolts"), "level": .string("12")])]),
    ])
  }
}
