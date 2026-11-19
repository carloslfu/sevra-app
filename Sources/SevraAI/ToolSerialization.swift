import Foundation
import SevraCore

extension NativeTools {
  /// The ordinary chat tools a profile offers. `general` offers today's until its own exist.
  package static func definitions(for toolProfile: ToolProfile) -> [WorkbookToolDefinition] {
    switch toolProfile {
    case .current: return definitions
    case .general:
      // The general tools, and the fixed tools not yet folded into them.
      return [sqlDefinition, saveDefinition] + definitions.filter { generalKept.contains($0.name) }
    }
  }
  /// Today's tools the general profile still offers. Each leaves when a general tool covers it.
  package static let generalKept: Set<String> = [
    "search", "read", "finish", "balance", "spaces", "save_space", "draft", "history_search",
    "history_read", "tool_result", "start_thread", "start_thread_and_continue",
    "rename_current_thread", "return_to_main", "review_thread_summary", "workspace_actions",
    "workspace_action", "native_app_sdk", "read_native_app", "save_native_app",
  ]
  /// Today's tools that `sql` replaces under the general profile.
  package static let generalReplaced: Set<String> = [
    "datasets", "rows", "compare_rows", "calculate", "propose_table_edit", "propose_table",
  ]
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
        "tool": schema("string", "Run this saved tool instead of statements."),
        "values": .object([
          "type": .string("object"), "description": .string("The saved tool's inputs by name."),
        ]),
      ], required: []))
  package static let saveDefinition = WorkbookToolDefinition(
    name: "save",
    description:
      "Save a workbook tool: named SQL statements the user wants to keep and run again, such as a report, a check or a form that adds rows. Write each input in the statements as :name. Run it later with sql tool=name.",
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
                "type": .string("string"), "enum": .array([.string("text"), .string("number")]),
              ]),
            ]),
            "required": .array([.string("name"), .string("type")]),
          ]),
        ]),
        "statements": .object([
          "type": .string("array"), "minItems": .number(1), "maxItems": .number(8),
          "items": .object(["type": .string("string")]),
        ]),
      ], required: ["kind", "name", "description", "statements"]))

  package static func referenceDefinitions(
    itemReferenceIDs: [String] = [], conversationActions: [String]? = nil,
    toolScope: InferenceToolScope = .all, documentCopyIDs: [String]? = nil,
    historyReferenceIDs: [String]? = nil, nativeAppAuthoring: Bool = true,
    reviewContract: Value = .null, conversationInput: Bool = false, visualCaptureIDs: [String] = [],
    toolProfile: ToolProfile = .current
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
    let ids = try ItemReferenceCandidates.normalized(itemReferenceIDs)
    let copies = try documentCopyIDs.map(DocumentCopyCandidates.normalized)
    if let conversationActions {
      try require(
        Set(conversationActions).isSubset(of: Set(WorkbookTools.conversationTools.values)),
        "tool_schema", "Invalid conversation capability.")
    }
    let available =
      definitions(for: toolScope.specialized ? .current : toolProfile)
      + (toolScope.allows("request_input", conversationInput: conversationInput)
        ? [inputDefinition] : [])
      + ([.excelBuild, .excelCalculation, .excelInterface].contains(toolScope)
        ? [excelEvidenceDefinition, excelBehaviorDefinition] : [])
    return try available.compactMap { definition in
      if definition.name == "workspace_action" {
        let operations = toolScope.workspaceOperations
        guard !operations.isEmpty else { return nil }
        var parameters = definition.parameters.object
        var properties = definition.parameters["properties"].object
        var action = properties["action"]!.object
        action["enum"] = .array(operations.map { .string($0.name) })
        properties["action"] = .object(action)
        parameters["properties"] = .object(properties)
        return .init(
          name: definition.name, description: definition.description,
          parameters: .object(parameters))
      }
      if definition.name == "finish", !visualCaptureIDs.isEmpty {
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
      if definition.name == "save_native_app", !nativeAppAuthoring { return nil }
      if definition.name == "save_native_app", [.excelBuild, .excelInterface].contains(toolScope) {
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
      if let action = WorkbookTools.conversationTools[definition.name], let conversationActions {
        guard conversationActions.contains(action) else { return nil }
      }
      if definition.name == "draft", let copies {
        var parameters = definition.parameters.object
        var properties = definition.parameters["properties"].object
        var parts = properties["parts"]!.object
        var item = parts["items"]!.object
        var fields = item["properties"]!.object
        if copies.isEmpty {
          fields.removeValue(forKey: "copy")
        } else {
          var copy = fields["copy"]!.object
          copy["enum"] = .array(copies.map(Value.string))
          fields["copy"] = .object(copy)
        }
        item["properties"] = .object(fields)
        parts["items"] = .object(item)
        properties["parts"] = .object(parts)
        parameters["properties"] = .object(properties)
        return .init(
          name: definition.name, description: definition.description,
          parameters: .object(parameters))
      }
      if definition.name == "history_read", let historyReferenceIDs {
        guard !historyReferenceIDs.isEmpty else { return nil }
        var parameters = definition.parameters.object
        var properties = definition.parameters["properties"].object
        var id = properties["id"]!.object
        id["enum"] = .array(historyReferenceIDs.map(Value.string))
        properties["id"] = .object(id)
        parameters["properties"] = .object(properties)
        return .init(
          name: definition.name, description: definition.description,
          parameters: .object(parameters))
      }
      guard !ids.isEmpty else { return definition }
      guard ["read", "lineage", "references"].contains(definition.name) else { return definition }
      var parameters = definition.parameters.object
      var properties = definition.parameters["properties"].object
      var id = properties["id"]?.object ?? [:]
      try require(id["type"] == .string("string"), "tool_schema", "The item lookup schema changed.")
      id["enum"] = .array(ids.map(Value.string))
      properties["id"] = .object(id)
      parameters["properties"] = .object(properties)
      return WorkbookToolDefinition(
        name: definition.name, description: definition.description, parameters: .object(parameters))
    }
  }

  /// The same maintained declarations feed both backend boundaries.
  package static func serializedDefinitions(
    toolScope: InferenceToolScope = .all, itemReferenceIDs: [String] = [],
    conversationActions: [String]? = nil, documentCopyIDs: [String]? = nil,
    historyReferenceIDs: [String]? = nil, nativeAppAuthoring: Bool = true,
    reviewContract: Value = .null, conversationInput: Bool = false, visualCaptureIDs: [String] = [],
    toolProfile: ToolProfile = .current
  ) throws -> Data {
    let definitions = try referenceDefinitions(
      itemReferenceIDs: itemReferenceIDs, conversationActions: conversationActions,
      toolScope: toolScope, documentCopyIDs: documentCopyIDs,
      historyReferenceIDs: historyReferenceIDs, nativeAppAuthoring: nativeAppAuthoring,
      reviewContract: reviewContract, conversationInput: conversationInput,
      visualCaptureIDs: visualCaptureIDs, toolProfile: toolProfile
    )
    .filter { toolScope.allows($0.name, conversationInput: conversationInput) }
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
