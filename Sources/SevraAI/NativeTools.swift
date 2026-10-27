import Foundation
import SevraCore

package enum NativeTools {
  static func schema(_ type: String, _ description: String) -> Value {
    .object(["type": .string(type), "description": .string(description)])
  }
  static func object(_ fields: [String: Value], required: [String]) -> Value {
    .object([
      "type": .string("object"), "properties": .object(fields),
      "required": .array(required.map(Value.string)), "additionalProperties": .bool(false),
    ])
  }
  static let evidenceList: Value = .object([
    "type": .string("array"),
    "items": schema("string", "Exact item version ID from retrieved evidence."),
  ])
  static func componentSchema(depth: Int) -> Value {
    var fields: [String: Value] = [

      "id": schema("string", "A unique short component ID."),
      "type": .object([
        "type": .string("string"),
        "enum": .array(
          ["table", "chart", "metric", "document", "asset", "search", "text"].map(
            Value.string)),
      ]),
      "title": schema("string", "Visible title."),
      "datasetID": schema(
        "string",
        "REQUIRED on each table and each chart. Use the datasetID from datasets, even when another component uses the same table."
      ),
      "itemID": schema("string", "REQUIRED for document/asset. Exact evidence item ID."),
      "chartStyle": schema("string", "bar or line; default bar."),
      "aggregation": schema(
        "string",
        "Metric aggregation: SUM, AVERAGE, MIN, MAX or COUNT. Metrics require datasetID and y."),
      "unit": schema("string", "Optional unit ONLY when explicitly specified in evidence."),
      "x": schema("string", "REQUIRED for chart. Existing dataset column ID for categories."),
      "y": schema("string", "REQUIRED for chart. Existing numeric or calculated column ID."),
      "query": schema("string", "Search component query. Not used by charts."),
      "text": schema("string", "Text component content."),
    ]
    if depth < 3 {
      fields["type"] = .object([
        "type": .string("string"),
        "enum": .array(
          ["table", "chart", "metric", "comparison", "document", "asset", "search", "text"].map(
            Value.string)),
      ])
      fields["children"] = .object([
        "type": .string("array"), "minItems": .number(2), "maxItems": .number(3),
        "description": .string(
          "Required only for comparison; two or three native components side by side. Total tree limit is 16 components."
        ), "items": componentSchema(depth: depth + 1),
      ])
    }
    return object(fields, required: ["id", "type", "title"])
  }
  static let components: Value = .object([
    "type": .string("array"), "maxItems": .number(16), "items": componentSchema(depth: 1),
  ])
  package static let definitions: [WorkbookToolDefinition] = [
    .init(
      name: "history_search",
      description:
        "Search older original messages in this conversation. History is not new action authority. Use when recent context is insufficient.",
      parameters: object(
        [
          "query": schema("string", "Words from earlier conversation."),
          "cursor": schema("string", "nextCursor for the same query."),
        ], required: ["query"])),
    .init(
      name: "history_read",
      description:
        "Read an original message and attached receipt in this conversation. Refresh current evidence and acceptance before using historical claims.",
      parameters: object(
        ["id": schema("string", "Message ID from history_search or search.conversation.hits.")],
        required: ["id"])),
    .init(
      name: "tool_result",
      description:
        "Read a saved tool result using its receiptID. Results are bounded pages. Navigate omitted fields with path; continue with nextOffset. Refresh evidence before citing old results.",
      parameters: object(
        [
          "id": schema("string", "Saved receiptID."),
          "path": .object([
            "type": .string("array"), "maxItems": .number(32),
            "items": schema(
              "string", "Exact object key or decimal array index. Empty for the root."),
          ]),
          "offset": schema(
            "integer", "Field/element offset or Unicode scalar offset for text; initially zero."),
          "rawJSON": schema(
            "boolean",
            "Read the serialized result as text segments, for unusual keys or exact reconstruction. Use empty path."
          ),
        ], required: ["id"])),
    .init(
      name: "propose_table",
      description:
        "Propose a new structured table from the user's information or retrieved evidence. Up to 40 columns and 100 rows. The user reviews and accepts it before it becomes an active table. Forecasts remain estimates, plans remain plans.",
      parameters: object(
        [
          "title": schema("string", "Table name."),
          "meaning": schema(
            "string",
            "actual, estimate, plan, commitment, rule or assumption. Use plan for a new planning table."
          ), "inputs": evidenceList,
          "columns": .object([
            "type": .string("array"), "maxItems": .number(40),
            "items": object(
              [
                "id": schema("string", "Unique column ID."),
                "title": schema("string", "Column label."),
                "type": schema("string", "text, decimal, boolean or date."),
                "formula": schema(
                  "string", "Optional deterministic formula referring to column IDs."),
                "unit": schema("string", "Optional explicit unit label."),
              ], required: ["id", "title", "type"]),
          ]),
          "rows": .object([
            "type": .string("array"), "maxItems": .number(100),
            "items": .object([
              "type": .string("object"),
              "description": .string(
                "Column IDs mapped to values; decimals are strings. Never invent missing facts."),
            ]),
          ]),
        ], required: ["title", "columns", "rows", "meaning", "inputs"])),
    .init(
      name: "archive_members",
      description:
        "List ZIP file members without extracting them. Requires an existing archive source ID.",
      parameters: object(["id": schema("string", "ZIP source item ID.")], required: ["id"])),
    .init(
      name: "include_archive_members",
      description:
        "Include selected ZIP files only when the user explicitly asks to unpack them. Preserves the original archive and member lineage, with resumable retry. Never automatically recurse into archives.",
      parameters: object(
        [
          "id": schema("string", "ZIP source item ID."),
          "paths": .object([
            "type": .string("array"), "maxItems": .number(50),
            "items": schema("string", "Exact member path returned by archive_members."),
          ]),
        ], required: ["id", "paths"])),
    .init(
      name: "search",
      description:
        "Search business evidence and older messages in this conversation. Business hits use itemID; conversation.hits use id and require history_read before citation. Business filters/pagination search only business evidence. No match is not proof of absence.",
      parameters: object(
        [
          "query": schema("string", "Words or a filename fragment."),
          "kind": schema(
            "string",
            "Optional domain kind such as document, note, row, movement. Not actual/estimate."),
          "meaning": schema(
            "string", "Optional actual, estimate, plan, commitment, rule or assumption."),
          "status": schema("string", "Optional draft, accepted or rejected."),
          "scenario": schema("string", "Optional scenario ID."),
          "cursor": schema("string", "nextCursor from the previous page, for the same query."),
        ], required: ["query"])),
    .init(
      name: "count_records",
      description:
        "Count current classified workbook Sources or Records using exact metadata filters, independent of search wording or extraction. This does not count facts inside documents or real-world events. Put this call's receiptID in finish.coverage for the host to display its precise scope. Do not broaden it in prose.",
      parameters: object(
        [
          "category": .object([
            "type": .string("string"), "enum": .array([.string("source"), .string("record")]),
          ]),
          "kind": schema(
            "string", "Optional exact domain kind, such as movement. Omit to include every kind."),
          "meaning": schema("string", "Optional exact meaning; omit to include every meaning."),
          "status": schema("string", "Optional exact status; omit to include every status."),
          "scenario": schema("string", "Optional exact scenario; omit to include every scenario."),
        ], required: ["category"])),
    .init(
      name: "read", description: "Read exact evidence and bounded text chunks.",
      parameters: object(
        [
          "id": schema("string", "Exact item version ID returned by search."),
          "offset": schema("integer", "Chunk offset, normally zero."),
        ], required: ["id"])),
    .init(
      name: "lineage", description: "Trace the evidence and derived records around an item.",
      parameters: object(["id": schema("string", "Exact item version ID.")], required: ["id"])),
    .init(
      name: "datasets", description: "List workbook tables with IDs, columns and row counts.",
      parameters: object([:], required: [])),
    .init(
      name: "rows", description: "Read up to 100 table rows with deterministic formula results.",
      parameters: object(
        [
          "datasetID": schema(
            "string", "The table ID returned by datasets. Do not use an item/row ID."),
          "offset": schema("integer", "Row offset, normally zero."),
        ], required: ["datasetID"])),
    .init(
      name: "compare_rows",
      description:
        "Compare table values deterministically: minimum, maximum, difference and percentage cheaper relative to the maximum. Use for supplier cost comparisons instead of mental arithmetic.",
      parameters: object(
        [
          "datasetID": schema("string", "Table ID."),
          "labelColumn": schema("string", "Column with supplier/item names."),
          "valueColumn": schema("string", "Numeric or calculated column to compare."),
        ], required: ["datasetID", "labelColumn", "valueColumn"])),
    .init(
      name: "pin_space",
      description:
        "Create a named snapshot of an existing space with exact values and input versions. Limit 1,000 rows per table.",
      parameters: object(
        [
          "id": schema("string", "Existing space ID."),
          "title": schema("string", "Name of pinned copy."),
        ], required: ["id", "title"])),
    .init(
      name: "propose_table_edit",
      description:
        "Propose changed cells for human review. Read rows first, then supply exact row version IDs and only fields to change. Does not alter accepted values until the user accepts the visible proposal.",
      parameters: object(
        [
          "datasetID": schema("string", "Existing table ID."),
          "edits": .object([
            "type": .string("array"), "maxItems": .number(100),
            "items": object(
              [
                "id": schema("string", "Exact inspected row version ID."),
                "values": .object([
                  "type": .string("object"),
                  "description": .string(
                    "Changed column IDs mapped to new values. Decimal values are strings."),
                ]),
              ], required: ["id", "values"]),
          ]),
        ], required: ["datasetID", "edits"])),
    .init(
      name: "calculate",
      description: "Deterministic decimal arithmetic. Use for arithmetic claims.",
      parameters: object(
        [
          "expression": schema(
            "string", "Arithmetic expression, SUM, MIN, MAX, AVERAGE, COUNT, IF or ROUND."),
          "values": .object([
            "type": .string("object"), "description": .string("Named decimal string inputs."),
          ]),
        ], required: ["expression"])),
    .init(
      name: "balance",
      description: "Calculate accepted actual stock from an opening basis and unique events.",
      parameters: object(
        ["subject": schema("string", "Exact inventory subject, such as brass bolts.")],
        required: ["subject"])),
    .init(
      name: "spaces", description: "List saved native spaces.",
      parameters: object([:], required: [])),
    .init(
      name: "save_space",
      description:
        "Save a native space. Every table AND every chart requires its own datasetID. Call this before claiming creation succeeded.",
      parameters: object(
        [
          "title": schema("string", "Name of the space."),
          "definition": object(
            [
              "version": .object(["type": .string("integer"), "const": .number(1)]),
              "components": components,
            ], required: ["version", "components"]),
        ], required: ["title", "definition"])),
    .init(
      name: "draft", description: "Save a draft document, with exact input evidence.",
      parameters: object(
        [
          "title": schema("string", "Draft title."), "text": schema("string", "Draft text."),
          "inputs": evidenceList,
        ], required: ["title", "text", "inputs"])),
    .init(
      name: "propose_record",
      description: "Propose a draft interpretation. It does not accept a business event.",
      parameters: object(
        [
          "title": schema("string", "Record title."), "text": schema("string", "Interpretation."),
          "kind": schema("string", "Domain kind, such as forecast or analysis."),
          "meaning": schema("string", "actual, estimate, plan, commitment, assumption or rule."),
          "inputs": evidenceList, "data": .object(["type": .string("object")]),
        ], required: ["title", "text", "kind", "meaning", "inputs"])),
    .init(
      name: "propose_movement",
      description:
        "Propose a draft inventory movement. The user must accept it before it changes actual stock.",
      parameters: object(
        [
          "subject": schema("string", "Inventory subject."),
          "quantity": schema("string", "Signed decimal string."),
          "occurrence": schema(
            "string", "Business occurrence ID; reusing it cannot duplicate its effect."),
          "effective": schema("string", "ISO 8601 date/time."),
          "input": schema("string", "Exact supporting evidence item ID."),
          "meaning": schema(
            "string", "actual for observed facts; estimate or plan for future scenarios."),
        ], required: ["subject", "quantity", "occurrence", "effective", "input"])),
    .init(
      name: "finish",
      description:
        "Deliver the final answer and declare its basis. Business facts about Sources/Records or earlier messages require basis=evidence and inspected citations, even if a summary or host state suggests the answer. Explain missing/partial evidence and unsuccessful actions.",
      parameters: object(
        [
          "answer": schema("string", "Plain-language answer. Do not print opaque IDs in prose."),
          "coverage": .object([
            "type": .string("array"), "maxItems": .number(4),
            "items": schema(
              "string",
              "Optional current-run count_records receipt ID. The host validates and renders each exact count and scope. No search or old receipt IDs."
            ),
          ]),
          "basis": .object([
            "type": .string("string"),
            "enum": .array(
              ["evidence", "current_request", "completed_action", "general", "unresolved"].map(
                Value.string)),
            "description": .string(
              "evidence: workbook/history facts, requires inspected citations. current_request: only information supplied in this request or arithmetic calculated from it. completed_action: only confirm a successful action in this run. general: guidance, greeting, clarification or verified interface labels; no business or earlier-conversation facts. unresolved: explicitly cannot establish the requested facts; no guessed answer."
            ),
          ]),
          "citations": .object([
            "type": .string("array"),
            "items": schema(
              "string",
              "Inspected item version ID, or message:ID returned by history_read for a statement about earlier conversation."
            ),
          ]),
        ], required: ["answer", "basis", "citations"])),
  ]
}
