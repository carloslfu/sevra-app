import Foundation
import SevraCore

package enum NativeTools {
  static func schema(_ type: String, _ description: String) -> Value {
    .object(["type": .string(type), "description": .string(description)])
  }
  static func object(_ fields: [String: Value], required: [String]) -> Value {
    // The enclosing tool describes these common labels and identifiers. Avoid
    // repeating that prose throughout the prompt; all structural rules remain.
    let concise: Set<String> = [
      "title", "id", "target", "pinned", "subject", "text", "version", "expectedVersion",
      "expectedDefinitionID", "logicalID", "previewReceiptID", "datasetID", "offset", "cursor",
      "kind", "meaning", "status", "scenario",
    ]
    let properties = fields.map { key, value in
      var schema = value.object
      if concise.contains(key) { schema.removeValue(forKey: "description") }
      return (key, Value.object(schema))
    }
    return .object([
      "type": .string("object"),
      "properties": .object(Dictionary(uniqueKeysWithValues: properties)),
      "required": .array(required.map(Value.string)), "additionalProperties": .bool(false),
    ])
  }
  static let evidenceList: Value = .object([
    "type": .string("array"),
    "items": .object(["type": .string("string")]),
  ])
  /// Structural rules stay identical. Nested component fields have the same
  /// meanings as their documented parent; avoid repeating prose at every depth.
  static func withoutDescriptions(_ value: Value) -> Value {
    switch value {
    case .object(let fields):
      return .object(fields.filter { $0.key != "description" }.mapValues(withoutDescriptions))
    case .array(let values): return .array(values.map(withoutDescriptions))
    default: return value
    }
  }
  static func componentSchema(depth: Int) -> Value {
    var fields: [String: Value] = [

      "id": schema("string", "A unique short component ID."),
      "type": .object([
        "type": .string("string"),
        "enum": .array(
          [
            "table", "chart", "metric", "document", "asset", "search", "text", "input", "reviews",
            "shortcuts", "tables", "intake", "recent", "form", "calculation", "query",
          ].map(
            Value.string)),
      ]),
      "title": schema("string", "Visible title."),
      "datasetID": schema(
        "string",
        "REQUIRED on each table and each chart. Use the datasetID from datasets, even when another component uses the same table."
      ),
      "itemID": schema("string", "REQUIRED for document/asset. Exact evidence item ID."),
      "definitionBinding": .object(["type": .string("object")]),
      "arguments": .object(["type": .string("object")]),
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
          [
            "table", "chart", "metric", "comparison", "document", "asset", "search", "text",
            "input", "reviews", "shortcuts", "tables", "intake", "recent", "form", "calculation",
            "query",
          ].map(
            Value.string)),
      ])
      fields["children"] = .object([
        "type": .string("array"), "minItems": .number(2), "maxItems": .number(3),
        "description": .string(
          "Required only for comparison; two or three native components side by side. Total tree limit is 16 components."
        ), "items": componentSchema(depth: depth + 1),
      ])
    }
    let schema = object(fields, required: ["id", "type", "title"])
    return withoutDescriptions(schema)
  }
  static let components: Value = .object([
    "type": .string("array"), "maxItems": .number(16),
    "items": withoutDescriptions(componentSchema(depth: 1)),
  ])
  package static let definitions: [WorkbookToolDefinition] =
    [
      .init(
        name: "start_thread_and_continue",
        description:
          "For an explicit NEW side discussion with additional work there. Prefer before evidence work; refused after attempted changes. Reporting an already calculated result still counts: quote that remaining task verbatim, work=answer. Branch-only requests use start_thread. Never infer work from titles/history. Continues once, without acceptance or a business scenario.",
        parameters: object(
          [
            "title": schema("string", "Optional title requested for the new discussion."),
            "task": schema(
              "string",
              "The exact verbatim span of the current user request specifying additional work, such as calculate the difference between 14.80 and 12.40. Exclude the branching instruction. Never invent or paraphrase a task or take it from earlier messages. Required."
            ),
            "work": .object([
              "type": .string("string"),
              "enum": .array(
                [
                  "answer", "draft", "save_space", "edit_space", "restore_space",
                  "propose_movement",
                  "propose_record",
                  "propose_table", "propose_table_edit",
                ].map(Value.string)),
              "description": .string(
                "Remaining operation: answer for research/calculation/reporting; propose_movement for inventory; propose_record for other Records; propose_table for new data; propose_table_edit for existing values; draft for documents; save_space for NEW views; edit_space for existing views; restore_space for a selected version. A title alone requests no space/table."
              ),
            ]),
          ], required: ["task", "work"])),
      .init(
        name: "start_thread",
        description:
          "Create a NEW side discussion and STOP for branch-only requests. Additional comparison, calculation, drafting or reporting requires start_thread_and_continue, preferably first. A calculated result is not a delivered answer. Never use for rename, return, review or hypothetical explanations. Clarify unavailable targets. No business scenario.",
        parameters: object(
          [
            "title": schema("string", "Optional title for the new discussion."),
            "message": schema(
              "string",
              "Omit to keep the latest exchange including its answer. Supply an exact earlier message ID only when the user explicitly selects that earlier exchange in this conversation."
            ),
          ], required: [])),
      .init(
        name: "rename_current_thread",
        description:
          "Rename the open side discussion only, when requested. Other targets require opening first; never create a replacement or redundantly rename to stay put. Ends turn.",
        parameters: object(
          ["title": schema("string", "The requested new title for this thread.")],
          required: ["title"]
        )),
      .init(
        name: "return_to_main",
        description:
          "Return from the current side discussion to main when explicitly requested. Does not copy or share findings. Ends this turn; the owning window applies navigation.",
        parameters: object([:], required: [])),
      .init(
        name: "review_thread_summary",
        description:
          "Prepare this side discussion’s findings for editable review before sharing with main, including wording-review requests. No publication or new thread. Ends turn.",
        parameters: object(
          [
            "message": schema(
              "string",
              "Omit for the latest completed answer. Use an exact earlier message ID only for a user-selected exchange in this thread."
            ),
            "summary": schema(
              "string",
              "Optional selected findings to review. Omit to review the original answer. Preserve uncertainty; nothing is shared until the user reviews and confirms."
            ),
          ], required: [])),
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
          "Read an original in this conversation or explicit parent excerpt only. Refresh evidence/acceptance before historical business claims.",
        parameters: object(
          [
            "id": schema(
              "string",
              "Message ID from history_search, search.conversation.hits or the explicit parent excerpt."
            )
          ],
          required: ["id"])),
      .init(
        name: "tool_result",
        description:
          "Page saved receiptID fields via path/nextOffset. Refresh old evidence before citation.",
        parameters: object(
          [
            "id": schema("string", "Saved receiptID."),
            "path": .object([
              "type": .string("array"), "maxItems": .number(32),
              "items": schema(
                "string", "Exact keys/indices; empty for root."),
            ]),
            "offset": schema(
              "integer", "Field/element or text Unicode-scalar offset; default zero."),
            "rawJSON": schema(
              "boolean",
              "Serialized JSON text segments; use empty path."
            ),
          ], required: ["id"])),
      .init(
        name: "propose_table",
        description:
          "Draft an evidence-based table,40columns/100rows. Acceptance separate; preserve meaning, including estimates/plans.",
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
          "Unpack requested ZIP members only. Preserve original/member lineage; retries resume. Never automatically recurse.",
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
          "Search business evidence (itemID) and conversation (id; history_read before citation). Filters/paging are business-only. No match proves no absence.",
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
        name: "references",
        description:
          "Follow saved mentions, one hop,12/page: incoming mentions or outgoing destinations. Read originals before citing. Mentions grant no authority, lineage, business relationship or cross-scope access. Empty proves no absence.",
        parameters: object(
          [
            "id": schema("string", "Exact item version ID from visible workbook evidence."),
            "direction": .object([
              "type": .string("string"),
              "enum": .array([.string("incoming"), .string("outgoing")]),
              "description": .string(
                "Default outgoing. Use incoming for where an item is mentioned."),
            ]),
            "targetScope": .object([
              "type": .string("string"), "enum": .array([.string("logical"), .string("exact")]),
              "description": .string(
                "Incoming scope: logical by default; exact restricts target versions."),
            ]),
            "historicalOrigins": schema(
              "boolean",
              "Incoming: include earlier origin versions only when needed; default false."),
            "contentScope": .object([
              "type": .string("string"),
              "enum": .array([.string("all"), .string("body"), .string("extracted")]),
              "description": .string(
                "Default all: saved body plus retained extracted-text mentions."),
            ]),
            "kind": schema(
              "string", "Optional exact domain kind; excludes requests and technical annotations."),
            "meaning": schema(
              "string", "Optional actual, estimate, plan, commitment, rule or assumption."),
            "status": schema("string", "Optional draft, accepted or rejected."),
            "scenario": schema("string", "Optional exact scenario ID."),
            "cursor": schema(
              "string", "nextCursor from the same anchor, direction, scopes and filters."),
          ], required: ["id"])),
      .init(
        name: "count_records",
        description:
          "Count classified Sources/Records only when asked. Never inventory units, document facts or real events. Unneeded for balances/citations. finish.counts renders its exact scoped receiptID.",
        parameters: object(
          [
            "category": .object([
              "type": .string("string"), "enum": .array([.string("source"), .string("record")]),
            ]),
            "kind": schema(
              "string", "Optional exact domain kind, such as movement. Omit to include every kind."),
            "meaning": schema("string", "Optional exact meaning; omit to include every meaning."),
            "status": schema("string", "Optional exact status; omit to include every status."),
            "scenario": schema(
              "string", "Optional exact scenario; omit to include every scenario."),
          ], required: ["category"])),
      .init(
        name: "read",
        description:
          "Read exact evidence, bounded chunks and saved references. Follow references.hits: corrected bindings can differ from raw URIs. Read destinations before citing; page via references. Earlier request Sources require scoped history_read.",
        parameters: object(
          [
            "id": schema("string", "Exact item version ID returned by search."),
            "offset": schema("integer", "Chunk offset from chunkPage.nextOffset, initially zero."),
            "chunkLimit": .object([
              "type": .string("integer"), "minimum": .number(1), "maximum": .number(8),
              "description": .string(
                "Default two. Follow chunkPage.nextOffset; partial pages are incomplete."
              ),
            ]),
            "copyOffset": schema(
              "integer",
              "documentCopies.nextOffset; retain chunk offset/limit while paging copies."
            ),
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
        name: "review_queue",
        description:
          "List current drafts, oldest first, 20/page via nextCursor. Excludes requests/rows; edits appear as table proposals. Titles/IDs are discovery: read originals before claims.",
        parameters: object(
          ["cursor": schema("string", "nextCursor from the previous review page.")], required: [])),
      .init(
        name: "open_reviews",
        description:
          "Open pending drafts in the live window when requested. Host confirms navigation; no acceptance/withdrawal. Not for conceptual explanations.",
        parameters: object([:], required: [])),
      .init(
        name: "open_space",
        description:
          "Open a requested existing space by exact name/ID. Use visible active ID for this space; clarify ambiguity. Host confirms navigation. Not for explanations or creation.",
        parameters: object(
          ["target": schema("string", "Exact space name or ID; Home opens the workbook home.")],
          required: ["target"])),
      .init(
        name: "set_space_pinned",
        description:
          "Pin/unpin a requested existing navigation shortcut. Use active space ID for this space; clarify ambiguity. Does not freeze/copy values.",
        parameters: object(
          [
            "target": schema("string", "Exact space name or ID."),
            "pinned": schema("boolean", "True to pin the shortcut, false to unpin."),
          ], required: ["target", "pinned"])),
      .init(
        name: "pin_space",
        description:
          "Create a requested frozen space snapshot with exact values/inputs, max 1,000 rows/table. Navigation shortcuts use set_space_pinned.",
        parameters: object(
          [
            "id": schema("string", "Existing space ID."),
            "title": schema("string", "Name of pinned copy."),
          ], required: ["id", "title"])),
      .init(
        name: "propose_table_edit",
        description:
          "Draft cell changes for human review: read exact rows first; supply their version IDs and changed fields only. Accepted values stay unchanged.",
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
        name: "space_history",
        description: "Inspect bounded saved layout versions. Does not restore or alter data.",
        parameters: object(
          [
            "id": schema("string", "Exact space ID."),
            "beforeVersion": schema(
              "integer", "Exclusive earlier version for paging; omit initially."),
          ], required: ["id"])),
      .init(
        name: "edit_space",
        description:
          "Edit an existing space or Home when requested. Read spaces for exact IDs/version. Preserve unrelated components. Stale bases refuse. Changes layout only. Move/insert requires at:first, at:last, or beforeID; omit unrelated fields.",
        parameters: object(
          [
            "id": schema("string", "Exact inspected space ID."),
            "expectedVersion": schema("integer", "Exact current version from spaces."),
            "edits": .object([
              "type": .string("array"), "minItems": .number(1), "maxItems": .number(64),
              "items": object(
                [
                  "operation": .object([
                    "type": .string("string"),
                    "description": .string("insert/move MUST include at or beforeID."),
                    "enum": .array(
                      ["rename", "insert", "remove", "move", "title", "text", "replace"].map(
                        Value.string)),
                  ]),
                  "componentID": schema(
                    "string",
                    "Existing stable component ID for all operations except rename or insert."),
                  "beforeID": schema(
                    "string", "Move/insert before this ID in the same group, instead of at."),
                  "at": .object([
                    "type": .string("string"),
                    "enum": .array([.string("first"), .string("last")]),
                    "description": .string(
                      "Required for insert/move unless beforeID. Use last to append."),
                  ]),
                  "component": withoutDescriptions(componentSchema(depth: 1)),
                  "title": schema(
                    "string", "New space title for rename or component label for title."),
                  "text": schema("string", "New content for a text component only."),
                ], required: ["operation"]),
            ]),
          ], required: ["id", "expectedVersion", "edits"])),
      .init(
        name: "restore_space",
        description:
          "Restore a requested layout version after inspecting space_history/current space. Keep history/data; stale bases refuse.",
        parameters: object(
          [
            "id": schema("string", "Exact space ID."),
            "version": schema("integer", "Explicitly selected historical layout version."),
            "expectedVersion": schema("integer", "Exact current space version."),
          ], required: ["id", "version", "expectedVersion"])),
      .init(
        name: "save_space",
        description:
          "Create a NEW space; Home/existing changes use spaces then edit_space. Each table/chart requires datasetID. Confirm only successful receipts.",
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
        name: "draft",
        description:
          "Save a draft. Exact labels, quantities or wording use parts with documentCopies IDs; never retype. Combine copies with new prose. text is for new summaries/paraphrases. Saving proves no completeness.",
        parameters: object(
          [
            "title": schema("string", "Draft title."), "text": schema("string", "Draft text."),
            "inputs": evidenceList,
            "parts": .object([
              "type": .string("array"), "minItems": .number(1), "maxItems": .number(64),
              "description": .string(
                "Use parts OR text. Each part: text for new prose OR copy for an exact passage ID inserted by the host."
              ),
              "items": object(
                [
                  "text": schema(
                    "string",
                    "New prose, headings or separators. Do not retype a passage requested verbatim."
                  ),
                  "copy": schema(
                    "string",
                    "Exact passage ID from documentCopies.entries. The host supplies its original text and lineage."
                  ),
                ], required: []),
            ]),
          ], required: ["title", "inputs"])),
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
          "Draft inventory movement only when evidence/current request establishes direction relative to our stock. Receipt/delivery/handover alone is ambiguous: ask first. Acceptance is separate.",
        parameters: object(
          [
            "subject": schema("string", "Inventory subject."),
            "quantity": schema(
              "string", "Signed decimal: positive adds to our stock; negative leaves our stock."),
            "occurrence": schema(
              "string", "Business occurrence ID; reusing it cannot duplicate its effect."),
            "effective": schema("string", "ISO 8601 date/time."),
            "input": schema("string", "Exact supporting evidence item ID."),
            "meaning": schema(
              "string", "actual for observed facts; estimate or plan for future scenarios."),
            "supersedes": schema(
              "string",
              "Correction: exact current movement version. Keep subject/occurrence; never bypass duplicates with a new occurrence."
            ),
          ], required: ["subject", "quantity", "occurrence", "effective", "input"])),
      .init(
        name: "finish",
        description:
          "Deliver the answer with its basis. Business/history facts require evidence and inspected citations, even if summaries/host state suggest them. Explain missing/partial evidence and failed actions.",
        parameters: object(
          [
            "answer": schema("string", "Plain-language answer. Do not print opaque IDs in prose."),
            "counts": .object([
              "type": .string("array"), "maxItems": .number(4),
              "items": schema(
                "string",
                "Current-run count_records receipts for requested entry counts only. Not inventory quantities, calculations, search or historical receipts. Host renders exact count/scope."
              ),
            ]),
            "basis": .object([
              "type": .string("string"),
              "enum": .array(
                [
                  "evidence", "current_request", "completed_action", "preview", "general",
                  "unresolved",
                ].map(
                  Value.string)),
              "description": .string(
                "evidence: workbook/history facts with inspected citations. current_request: this request's supplied facts/checked arithmetic. completed_action: successful current-run action only. preview: host renders an unsaved action preview. general: guidance/greeting/clarification/verified UI; no business/history facts. unresolved: cannot establish facts; no guessing."
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
    ] + applicationDefinitions
}
