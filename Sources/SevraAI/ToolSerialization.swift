import Foundation
import SevraCore

extension NativeTools {
  package static let sqlDefinition = WorkbookToolDefinition(
    name: "sql",
    description:
      "Read and change workbook tables with SQLite SQL. Table and column names are listed under Tables for sql in the request. Reads: any SELECT, with joins, WHERE, GROUP BY and arithmetic. Row changes: INSERT, UPDATE, DELETE, saved at once with Undo. Tables: CREATE TABLE, ALTER TABLE (ADD, RENAME or DROP COLUMN, RENAME TO) and DROP TABLE, which archives. For a draft the user reviews first, send the UPDATE with draft=true.",
    parameters: object(
      [
        "statements": .object([
          "type": .string("array"), "minItems": .number(1), "maxItems": .number(8),
          "items": .object(["type": .string("string")]),
          "description": .string("One SQL statement per entry, run in order."),
        ]),
        "draft": schema(
          "boolean", "True saves UPDATEs as a proposal for the user to review. Nothing changes."),
        "tool": schema("string", "Run this saved SQL tool instead of statements."),
        "undo": schema(
          "string", "Sent alone: undo everything an earlier sql call saved, by its undo value."),
        "values": .object([
          "type": .string("object"), "description": .string("The saved tool's inputs by name."),
        ]),
      ], required: []))
  package static let runDefinition = WorkbookToolDefinition(
    name: "run",
    description:
      "Run JavaScript for work one SQL statement cannot do: several dependent steps, a loop, or logic over rows. Write the body of an async function and return the result. Inside it: await sql(statement, {name: value}) returns a SELECT's rows as objects with numbers as numbers, or {changedRows} for a change, and :name in the statement takes the value; await tool(name, {input: value}) runs a saved SQL tool the same way; await search(words); await read(id); today is the date as YYYY-MM-DD. Table changes are saved together when the script returns, with one Undo. A script that throws changes nothing. Or send tool and values to run a saved tool.",
    parameters: object(
      [
        "code": schema(
          "string",
          "The function body, such as: const rows = await sql('SELECT part, stock FROM parts'); return rows.filter(r => r.stock < 5).length;"
        ),
        "tool": schema("string", "Run this saved tool instead of code."),
        "values": .object([
          "type": .string("object"), "description": .string("The saved tool's inputs by name."),
        ]),
      ], required: []))
  package static let saveDefinition = WorkbookToolDefinition(
    name: "save",
    description:
      "Save a workbook tool the user wants to keep and run again, such as a report, a check or a form that adds rows: SQL statements that use each input as :name, or source, a script that reads inputs.name. Run it later with sql or run, tool=name and values.",
    parameters: object(
      [
        "kind": .object(["type": .string("string"), "enum": .array([.string("tool")])]),
        "name": schema("string", "Lower case with underscores, such as low_stock."),
        "description": schema("string", "One sentence on what it does."),
        "inputs": .object([
          "type": .string("array"), "maxItems": .number(16),
          "items": .object([
            "type": .string("object"),
            "properties": .object([
              "name": .object(["type": .string("string")]),
              "type": .object([
                "type": .string("string"),
                "enum": .array(["text", "number", "boolean", "date"].map(Value.string)),
              ]),
            ]),
            "required": .array([.string("name"), .string("type")]),
          ]),
        ]),
        "statements": .object([
          "type": .string("array"), "minItems": .number(1), "maxItems": .number(8),
          "items": .object(["type": .string("string")]),
        ]),
        "source": schema(
          "string",
          "Instead of statements: the body of an async function, as for run, that reads inputs.name and returns its result."),
      ], required: ["kind", "name", "description"]))

  package static func referenceDefinitions(
    itemReferenceIDs: [String] = [], conversationActions: [String]? = nil,
    toolScope: InferenceToolScope = .all, documentCopyIDs: [String]? = nil,
    nativeAppAuthoring: Bool = true, reviewContract: Value = .null, conversationInput: Bool = false,
    visualCaptureIDs: [String] = [], display: Bool = false
  ) throws
    -> [WorkbookToolDefinition]
  {
    if toolScope == .movementDirection { return [MovementDirectionReview.definition] }
    if toolScope == .actionDirection { return [ActionDirectionReview.definition] }
    if toolScope == .nativeAppReview { return [NativeAppReview.definition] }
    if toolScope == .nativeActionReview {
      return [NativeAppReview.actionDefinition(reviewContract)]
    }
    if toolScope == .excelPlan {
      return [
        ExcelConversionAgent.readDefinition, NativeTools.excelEvidenceDefinition,
        ExcelConversionAgent.definition,
      ]
    }
    if toolScope.specialized { return excelDefinitions(toolScope) }
    let ids = try ItemReferenceCandidates.normalized(itemReferenceIDs)
    let copies = try documentCopyIDs.map(DocumentCopyCandidates.normalized)
    if let conversationActions {
      try require(
        Set(conversationActions).isSubset(of: Set(WorkbookTools.conversationTools.values)),
        "tool_schema", "Invalid conversation capability.")
    }
    // A scope that only reads offers only the actions that only read.
    return GeneralTools.definitions(
      operations: toolScope.workspaceOperations.map(\.name),
      threads: conversationActions.map(Set.init), apps: nativeAppAuthoring,
      ask: toolScope.allows("request_input", conversationInput: conversationInput)
        ? inputDefinition : nil, readOnly: !toolScope.changes, items: ids, display: display,
      copies: copies, answersWorkflow: toolScope == .workflowAnswer
    ).map { definition in
      guard definition.name == "finish", !visualCaptureIDs.isEmpty else { return definition }
      var parameters = definition.parameters.object
      var properties = definition.parameters["properties"].object
      properties["visuals"] = .object([
        "type": .string("array"), "maxItems": .number(2),
        "description": .string("Inspected visual capture receipt IDs from this run."),
        "items": .object([
          "type": .string("string"), "enum": .array(visualCaptureIDs.map(Value.string)),
        ]),
      ])
      parameters["properties"] = .object(properties)
      return .init(
        name: definition.name, description: definition.description,
        parameters: .object(parameters))
    }
  }

  /// An Excel conversion stage's own tools.
  private static func excelDefinitions(_ toolScope: InferenceToolScope) -> [WorkbookToolDefinition] {
    (definitions + [excelEvidenceDefinition, excelBehaviorDefinition]).map { definition in
      guard definition.name == "save_native_app", toolScope != .excelCalculation else {
        return definition
      }
      var parameters = definition.parameters.object
      var properties = definition.parameters["properties"].object
      properties.removeValue(forKey: "id")
      properties.removeValue(forKey: "expectedVersion")
      var package = properties["package"]!.object
      var fields = package["properties"]!.object
      if toolScope == .excelBuild {
        fields["excelBehavior"] = excelBehaviorSchema
      } else {
        fields.removeValue(forKey: "excelBehavior")
      }
      fields["datasets"] = .object([
        "type": .string("object"),
        "additionalProperties": NativeTools.object(
          ["writable": .object(["type": .string("boolean")])], required: ["writable"]),
        "description": .string(
          "Use every supplied short alias (sheet1, sheet2, …), each with only writable:true or false. The HOST fills in datasetID, title and exact columns. Do not supply them."
        ),
      ])
      package["properties"] = .object(fields)
      properties["package"] = .object(package)
      parameters["properties"] = .object(properties)
      parameters["required"] = .array(
        Array(
          Set(parameters["required"]?.array.map(\.text) ?? [])
            .union(["fixtures"])
        ).sorted().map(Value.string))
      return .init(
        name: definition.name,
        description: (toolScope == .excelInterface
          ? "Author the interface and shared record actions only. Calculation behavior is host-owned in this stage; do not supply excelBehavior or reimplement working formulas. "
          : "")
          + "Save this Excel conversion's native workspace. Omit package.excelBehavior to reuse the last host-matched calculation draft from this request, or supply a replacement explicitly. Calculation drafts survive later UI/test/review failures; failed compare_excel_behavior calls clear them. The host supplies app identity, version and exact table bindings. package.datasets is only {sheet1:{writable:true/false},...}. Use all supplied aliases; do not supply datasetID/title/columns inside bindings or id/expectedVersion. Tests use synthetic fixtures, never imported rows. Include fixture rows before selecting/editing them. Failed checks save no app; fix the error and resubmit.",
        parameters: .object(parameters))
    }
  }

  /// The same maintained declarations feed both backend boundaries.
  package static func serializedDefinitions(
    toolScope: InferenceToolScope = .all, itemReferenceIDs: [String] = [],
    conversationActions: [String]? = nil, documentCopyIDs: [String]? = nil,
    nativeAppAuthoring: Bool = true, reviewContract: Value = .null, conversationInput: Bool = false,
    visualCaptureIDs: [String] = [], display: Bool = false
  ) throws -> Data {
    let definitions = try referenceDefinitions(
      itemReferenceIDs: itemReferenceIDs, conversationActions: conversationActions,
      toolScope: toolScope, documentCopyIDs: documentCopyIDs,
      nativeAppAuthoring: nativeAppAuthoring,
      reviewContract: reviewContract, conversationInput: conversationInput,
      visualCaptureIDs: visualCaptureIDs, display: display
    )
    .filter {
      toolScope.specialized
        ? toolScope.allows($0.name, conversationInput: conversationInput)
        : GeneralTools.allowed($0.name, in: toolScope, conversationInput: conversationInput)
    }
    let values: [[String: Any]] = try definitions.map {
      [
        "type": "function",
        "function": [
          "name": $0.name, "description": $0.description,
          "parameters": try JSONSerialization.jsonObject(with: Data(try $0.parameters.json().utf8)),
        ],
      ]
    }
    return try JSONSerialization.data(
      withJSONObject: values, options: [.sortedKeys, .withoutEscapingSlashes])
  }
}
