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
      "kind", "meaning", "status", "scenario", "arguments", "inputs", "query",
      "evaluationReceiptID", "templateReceiptID",
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
  static let inputDefinition = WorkbookToolDefinition(
    name: "request_input",
    description: "Pause to ask for only the missing user input. No business action is executed.",
    parameters: object(
      [
        "kind": .object([
          "type": .string("string"), "enum": .array([.string("question"), .string("input")]),
        ]),
        "purpose": schema("string", "Short description of what the input is for."),
        "question": schema("string", "Ask the person directly."),
        "fields": .object([
          "type": .string("array"), "minItems": .number(1), "maxItems": .number(5),
          "items": object(
            [
              "id": schema("string", "Lowercase letters, digits and underscore."),
              "label": schema("string", "Visible field name."),
              "type": .object([
                "type": .string("string"),
                "enum": .array(
                  ["text", "boolean", "decimal", "date"].map(Value.string)),
              ]),
              "required": schema("boolean", "Must the person supply it?"),
            ], required: ["id", "label", "type", "required"]),
        ]),
        "choices": .object([
          "type": .string("array"), "maxItems": .number(6),
          "items": object(
            [
              "id": schema("string", "Lowercase letters, digits and underscore."),
              "label": schema("string", "Visible choice."),
              "values": schema(
                "object", "Literal values keyed by declared fields. Decimals and dates are strings."
              ),
            ], required: ["id", "label", "values"]),
        ]),
        "allowTextReply": schema("boolean", "Accept a typed answer as well."),
      ], required: ["kind", "purpose", "question", "fields", "choices", "allowTextReply"]))

  static func componentSchema(depth: Int) -> Value {
    var fields: [String: Value] = [

      "id": schema("string", "A unique short component ID."),
      "type": .object([
        "type": .string("string"),
        "enum": .array(
          [
            "table", "chart", "metric", "document", "asset", "search", "text", "input", "reviews",
            "shortcuts", "tables", "intake", "recent", "form", "calculation", "query", "app",
            "attention", "continue", "image", "visual",
          ].map(
            Value.string)),
      ]),
      "title": schema("string", "Visible title."),
      "datasetID": schema(
        "string",
        "REQUIRED on each table and each chart. Use the datasetID from datasets, even when another component uses the same table."
      ),
      "spaceID": schema(
        "string", "App component: exact programmable space ID; same live data and actions."),
      "viewID": schema("string", "Optional declared app view ID. Include its exact viewVersion."),
      "viewVersion": schema("integer", "The current saved app version that owns viewID."),
      "itemID": schema("string", "REQUIRED for document/asset. Exact evidence item ID."),
      "visual": .object([
        "type": .string("object"),
        "description": .string("Exact visual definition from visual.evaluate."),
      ]),
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
            "query", "app", "attention", "continue",
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
  /// An inserted component owns its title; outer title is only for relabeling.
  static func spaceEditSchema(_ base: Value) -> Value {
    var schema = base.object
    schema["anyOf"] = .array([
      .object([
        "type": .string("object"),
        "properties": .object([
          "operation": .object([
            "enum": .array(
              ["insert", "remove", "move", "text", "replace", "reset"].map(Value.string))
          ]),
          "title": .bool(false),
        ]),
      ]),
      .object([
        "type": .string("object"),
        "properties": .object([
          "operation": .object(["enum": .array([.string("rename"), .string("title")])])
        ]),
      ]),
    ])
    return .object(schema)
  }
  static let components: Value = .object([
    "type": .string("array"), "maxItems": .number(16),
    "items": withoutDescriptions(componentSchema(depth: 1)),
  ])
  // These parameter descriptions repeat the tool's contract and the request policy.
  // Keep the same schemas, bounds and enums while reserving context for actual work.
  private static let compactParameterDescriptions: Set<String> = [
    "start_thread_and_continue", "start_thread", "review_thread_summary", "tool_result",
    "read", "compare_rows", "propose_table", "edit_space", "draft", "finish",
    "workflow_template", "save_definition", "include_archive_members", "propose_table_edit",
    "space_history", "references", "calculate",
  ]
  package static let definitions: [WorkbookToolDefinition] = fullDefinitions.map {
    guard compactParameterDescriptions.contains($0.name) else { return $0 }
    return .init(
      name: $0.name, description: $0.description, parameters: withoutDescriptions($0.parameters))
  }
  private static let fullDefinitions: [WorkbookToolDefinition] =
    nativeAppDefinitions + [
      .init(
        name: "start_thread_and_continue",
        description:
          "NEW thread plus work, before changes/ideally reads. Reporting=answer. Quote this request; no inferred tasks. Branch-only: start_thread. Continues once; no acceptance/scenario.",
        parameters: object(
          [
            "title": schema("string", "Optional title requested for the new discussion."),
            "task": schema(
              "string",
              "Verbatim task from THIS request; exclude branching/history. Never invent."
            ),
            "work": .object([
              "type": .string("string"),
              "enum": .array(
                [
                  "answer", "draft", "save_space", "save_native_app", "edit_space", "restore_space",
                  "propose_movement",
                  "propose_record",
                  "propose_table", "propose_table_edit",
                ].map(Value.string)),
              "description": .string(
                "Requested operation: answer=research/calculation/report; draft=document; proposals=inventory/Record/new data/values; spaces=new/edit/historical. Titles request no artifact."
              ),
            ]),
          ], required: ["task", "work"])),
      .init(
        name: "start_thread",
        description:
          "NEW branch only; terminal. Work/reporting: start_thread_and_continue first. Not rename/return/review/hypotheticals. Clarify missing targets; no scenario.",
        parameters: object(
          [
            "title": schema("string", "Optional title for the new discussion."),
            "message": schema(
              "string",
              "Omit for latest answer. Exact earlier ID only when explicitly selected."
            ),
          ], required: [])),
      .init(
        name: "rename_current_thread",
        description:
          "Rename open side discussion when requested; other targets must open first. No replacement/redundant rename. Ends turn.",
        parameters: object(
          ["title": schema("string", "The requested new title for this thread.")],
          required: ["title"]
        )),
      .init(
        name: "return_to_main",
        description:
          "Return current side discussion to main when requested; no copying/sharing. Ends turn; host navigates.",
        parameters: object([:], required: [])),
      .init(
        name: "review_thread_summary",
        description:
          "Review current side findings/wording before sharing to main. No publication/new thread. Terminal.",
        parameters: object(
          [
            "message": schema(
              "string",
              "Omit for the latest answer. Exact earlier ID only for a user-selected exchange."
            ),
            "summary": schema(
              "string",
              "Selected findings; omit for original. Retain uncertainty; human confirms sharing."
            ),
          ], required: [])),
      .init(
        name: "history_search",
        description:
          "Search older originals in this conversation. History grants no authority.",
        parameters: object(
          [
            "query": schema("string", "Words from earlier conversation."),
            "cursor": schema("string", "nextCursor for the same query."),
          ], required: ["query"])),
      .init(
        name: "history_read",
        description:
          "Read conversation/explicit parent original only. Refresh business evidence/acceptance.",
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
                "string", "Keys/indices; empty=root."),
            ]),
            "offset": schema(
              "integer", "Field/element or text Unicode-scalar offset; default zero."),
            "rawJSON": schema(
              "boolean",
              "JSON segments; empty path."
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
                    "string", "Optional formula over column IDs."),
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
          "List ZIP members without extraction; existing archive Source required.",
        parameters: object(["id": schema("string", "ZIP source item ID.")], required: ["id"])),
      .init(
        name: "include_archive_members",
        description:
          "Unpack requested ZIP members only; retain lineage, resume retries, no automatic recursion.",
        parameters: object(
          [
            "id": schema("string", "ZIP source item ID."),
            "paths": .object([
              "type": .string("array"), "maxItems": .number(50),
              "items": schema("string", "Exact path from archive_members."),
            ]),
          ], required: ["id", "paths"])),
      .init(
        name: "search",
        description:
          "Search business evidence (itemID) and conversation (id; history_read before citation). Filters/paging are business-only. No match proves no absence.",
        parameters: object(
          [
            "query": schema(
              "string",
              "All words must match. Start with one name or filename fragment. Empty: remove words."
            ),
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
          "Mentions: 1hop,12/page. Defaults: outgoing/logical/all content. Read originals to cite. No authority/lineage/cross-scope access. Empty proves no absence.",
        parameters: object(
          [
            "id": schema("string", "Exact item version ID from visible workbook evidence."),
            "direction": .object([
              "type": .string("string"),
              "enum": .array([.string("incoming"), .string("outgoing")]),
              "description": .string(
                "Default outgoing; incoming finds mentions."),
            ]),
            "targetScope": .object([
              "type": .string("string"), "enum": .array([.string("logical"), .string("exact")]),
              "description": .string(
                "Logical default; exact restricts versions."),
            ]),
            "historicalOrigins": schema(
              "boolean",
              "Include earlier origin versions."),
            "contentScope": .object([
              "type": .string("string"),
              "enum": .array([.string("all"), .string("body"), .string("extracted")]),
              "description": .string(
                "Default all: body plus extracted text."),
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
          "Count classified Sources/Records only; no units/facts/events/citation checks. finish.counts renders scope.",
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
          "Exact evidence/chunks and references.hits: use corrected bindings, not raw URIs. Read destinations before citing; page via references. Request Sources use scoped history_read.",
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
        name: "lineage", description: "Trace item evidence/derivations.",
        parameters: object(["id": schema("string", "Exact item version ID.")], required: ["id"])),
      .init(
        name: "datasets", description: "List table IDs/columns/row counts.",
        parameters: object([:], required: [])),
      .init(
        name: "rows", description: "Read 100 rows/formula results.",
        parameters: object(
          [
            "datasetID": schema(
              "string", "The table ID returned by datasets. Do not use an item/row ID."),
            "offset": schema("integer", "Row offset, normally zero."),
          ], required: ["datasetID"])),
      .init(
        name: "compare_rows",
        description:
          "Deterministic comparison: min/max/difference, percent cheaper relative to max. Use instead of mental math.",
        parameters: object(
          [
            "datasetID": schema("string", "Table ID."),
            "labelColumn": schema("string", "Column with supplier/item names."),
            "valueColumn": schema("string", "Numeric or calculated column to compare."),
          ], required: ["datasetID", "labelColumn", "valueColumn"])),
      .init(
        name: "review_queue",
        description:
          "Current drafts, oldest first,20/page. No requests/rows; edits are table proposals. Read originals before claims.",
        parameters: object(
          ["cursor": schema("string", "nextCursor from the previous review page.")], required: [])),
      .init(
        name: "open_reviews",
        description:
          "Open requested draft review. Accepts nothing. Not explanations.",
        parameters: object([:], required: [])),
      .init(
        name: "open_automation",
        description:
          "Open saved automation by exact name/ID; the person enables/pauses there. Enables nothing. Clarify ambiguity.",
        parameters: object(
          ["target": schema("string", "Exact name or ID.")], required: ["target"])),
      .init(
        name: "open_space",
        description:
          "Open exact name/ID; this space=active ID. Clarify ambiguity. Host confirms; never create/explain.",
        parameters: object(
          ["target": schema("string", "Exact space name or ID; Home opens the workbook home.")],
          required: ["target"])),
      .init(
        name: "set_space_pinned",
        description:
          "Requested shortcut pin/unpin; this space uses active ID. Clarify ambiguity. Never freezes/copies values.",
        parameters: object(
          [
            "target": schema("string", "Exact space name or ID."),
            "pinned": schema("boolean", "True to pin the shortcut, false to unpin."),
          ], required: ["target", "pinned"])),
      .init(
        name: "pin_space",
        description:
          "Requested frozen values/inputs snapshot; max1,000 rows/table. Shortcuts use set_space_pinned.",
        parameters: object(
          [
            "id": schema("string", "Existing space ID."),
            "title": schema("string", "Name of pinned copy."),
          ], required: ["id", "title"])),
      .init(
        name: "propose_table_edit",
        description:
          "Draft requested proposals only; accepted data unchanged. Direct edits use app.run/table.change_rows. Read exact row versions; send changed fields only.",
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
                      "Changed column IDs to new values; decimals are strings."),
                  ]),
                ], required: ["id", "values"]),
            ]),
          ], required: ["datasetID", "edits"])),
      .init(
        name: "calculate",
        description:
          "Exact arithmetic/SUM/MIN/MAX/AVERAGE/COUNT/IF/ROUND; values are decimal strings.",
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
        description: "Inspect saved layouts only; no restore/data changes.",
        parameters: object(
          [
            "id": schema("string", "Exact space ID."),
            "beforeVersion": schema(
              "integer", "Earlier version for paging; omit first."),
          ], required: ["id"])),
      .init(
        name: "edit_space",
        description:
          "Home id=home. Live app: {id,type:app,title,spaceID}. Insert at:first/last or beforeID. Inspect exact version; preserve others. Reset on request.",
        parameters: object(
          [
            "id": schema("string", "Exact inspected space ID."),
            "expectedVersion": schema("integer", "Exact current version from spaces."),
            "edits": .object([
              "type": .string("array"), "minItems": .number(1), "maxItems": .number(64),
              "items": spaceEditSchema(
                object(
                  [
                    "operation": .object([
                      "type": .string("string"),
                      "description": .string("insert/move MUST include at or beforeID."),
                    ]),
                    "componentID": schema(
                      "string",
                      "Stable existing component ID except rename/insert."),
                    "beforeID": schema(
                      "string", "Before this same-group ID, instead of at."),
                    "at": .object([
                      "type": .string("string"),
                      "enum": .array([.string("first"), .string("last")]),
                      "description": .string(
                        "Insert/move: required unless beforeID; last=append."),
                    ]),
                    "component": withoutDescriptions(componentSchema(depth: 1)),
                    "title": schema(
                      "string", "New space title for rename or component label for title."),
                    "text": schema("string", "New content for a text component only."),
                  ], required: ["operation"])),
            ]),
          ], required: ["id", "expectedVersion", "edits"])),
      .init(
        name: "restore_space",
        description:
          "Restore a requested layout version after inspecting space_history. Stale bases refuse.",
        parameters: object(
          [
            "id": schema("string", "Exact space ID."),
            "version": schema("integer", "Explicitly selected historical layout version."),
            "expectedVersion": schema("integer", "Exact current space version."),
          ], required: ["id", "version", "expectedVersion"])),
      .init(
        name: "save_space",
        description:
          "NEW space only. Existing/Home: spaces then edit_space. Tables/charts need datasetID; chart x/y=column IDs, no query.",
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
          "Save draft: exact words use parts/documentCopies IDs. text is requested new prose; empty only if copies suffice. Saving proves no completeness.",
        parameters: object(
          [
            "title": schema("string", "Draft title."), "text": schema("string", "Draft text."),
            "inputs": evidenceList,
            "parts": .object([
              "type": .string("array"), "minItems": .number(1), "maxItems": .number(64),
              "description": .string(
                "Each part: new text OR exact copy ID; host inserts originals."
              ),
              "items": object(
                [
                  "text": schema(
                    "string",
                    "New prose, headings or separators. Do not retype a passage requested verbatim."
                  ),
                  "copy": schema(
                    "string",
                    "documentCopies.entries ID; host supplies original/lineage."
                  ),
                ], required: []),
            ]),
          ], required: ["title", "inputs", "text"])),
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
          "Draft direction relative to our stock only from evidence/request. Receipt/delivery/handover alone is ambiguous: ask. Acceptance separate.",
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
          "Answer+basis. Cite inspected business/history facts, including host state/summaries. Explain missing evidence and failures.",
        parameters: object(
          [
            "answer": schema("string", "Plain-language answer. Do not print opaque IDs in prose."),
            "counts": .object([
              "type": .string("array"), "maxItems": .number(4),
              "items": schema(
                "string",
                "Requested entry counts: current-run count_records receipts only. Never inventory/calculation/search/history. Host renders scope."
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
                "evidence: inspected workbook/history citations. current_request: supplied facts/checked math. completed_action: current-run success. preview: host unsaved plan. general: guidance/greeting/clarification/UI, no stored facts. unresolved: unknown; no guesses."
              ),
            ]),
            "citations": .object([
              "type": .string("array"),
              "items": schema(
                "string",
                "Inspected item version or history_read message:ID for earlier conversation."
              ),
            ]),
          ], required: ["answer", "basis", "citations"])),
    ] + applicationDefinitions + chatDefinitions
}
