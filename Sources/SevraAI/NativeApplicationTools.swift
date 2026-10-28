import Foundation
import SevraCore

extension NativeTools {
  package static let applicationDefinitions: [WorkbookToolDefinition] = [
    .init(
      name: "find_definitions",
      description:
        "Find behavior metadata, never evidence/authority. Empty query lists.",
      parameters: object(
        [
          "query": schema("string", "Words in saved behavior; empty lists."),
          "kind": .object([
            "type": .string("string"),
            "enum": .array(["function", "query", "action", "form"].map(Value.string)),
          ]),
          "historical": schema("boolean", "Earlier versions; default false."),
          "cursor": schema("string", "nextCursor; keep query/kind/historical."),
        ], required: ["query"])),
    .init(
      name: "read_definition",
      description:
        "Inspect behavior/dependencies. Metadata grants no authority. Fill nativeComponent’s typed arguments.",
      parameters: object(["id": schema("string", "Exact definition version.")], required: ["id"])),
    .init(
      name: "definition_registry",
      description:
        "Trusted primitives/formats; no execution.",
      parameters: object([:], required: [])),
    .init(
      name: "receiving_template",
      description:
        "Receiving template. Use save_template with receiptID; never retype.",
      parameters: object([:], required: [])),
    .init(
      name: "form_template",
      description:
        "Current action’s form template. Save receiptID; never retype.",
      parameters: object(
        ["id": schema("string", "Exact current saved action version.")], required: ["id"])),
    .init(
      name: "evaluate_definition",
      description:
        "Read-only function/query. Page with same arguments; preserve meaning/scope/coverage. Aggregates need originals.",
      parameters: object(
        [
          "id": schema("string", "Exact function/query version."),
          "arguments": .object([
            "type": .string("object"),
            "description": .string(
              "Decimal strings; omission differs from null."
            ),
          ]),
          "cursor": schema("string", "Saved-query continuation only."),
        ], required: ["id", "arguments"])),
    .init(
      name: "publish_result",
      description:
        "Publish complete current-run evaluation as draft with lineage. Stale/partial refuses; acceptance separate.",
      parameters: object(
        [
          "evaluationReceiptID": schema(
            "string", "This run’s successful first-page evaluation receiptID."),
          "title": schema("string", "Result title."),
          "meaning": .object([
            "type": .string("string"),
            "enum": .array(
              ["actual", "estimate", "plan", "commitment", "assumption", "rule"].map(Value.string)),
          ]),
          "scenario": schema("string", "Scenario."), "inputs": evidenceList,
        ], required: ["evaluationReceiptID", "title", "meaning"])),
    .init(
      name: "save_definition",
      description:
        "Save behavior, no execution/acceptance. New: omit IDs; edits need both. Templates: save_template.",
      parameters: object(
        [
          "logicalID": schema("string", "Edit logical identity."),
          "expectedDefinitionID": schema(
            "string", "Exact current edit base."),
          "content": .object([
            "type": .string("object"),
            "description": .string(
              "Typed formats: definition_registry."
            ),
          ]),
          "inputs": evidenceList,
        ], required: ["content"])),
    .init(
      name: "save_template",
      description:
        "Copy this run’s template. No execution/acceptance. Edits need both IDs.",
      parameters: object(
        [
          "templateReceiptID": schema(
            "string", "This run's successful receiving_template/form_template receiptID."),
          "title": schema("string", "Optional template title override."),
          "logicalID": schema("string", "Existing edit identity only."),
          "expectedDefinitionID": schema("string", "Current exact edit base only."),
          "inputs": evidenceList,
        ], required: ["templateReceiptID"])),
    .init(
      name: "preview_action",
      description:
        "Preview inspected action/form, no effects. Clarify missing facts. Returns plan/receiptID.",
      parameters: object(
        [
          "id": schema("string", "Exact inspected saved action/form version ID."),
          "arguments": .object([
            "type": .string("object"),
            "description": .string(
              "Decimal strings, exact item IDs; no invented facts."
            ),
          ]),
        ], required: ["id", "arguments"])),
    .init(
      name: "prepare_action",
      description:
        "Prepare drafts, never accept. Host previews action/form and checks directions before atomic save. Unsaved plan: preview_action.",
      parameters: object(
        [
          "id": schema("string", "Exact inspected action/form version."),
          "arguments": .object([
            "type": .string("object"),
            "description": .string("Declared typed inputs; no invented facts."),
          ]),
        ], required: ["id", "arguments"])),
  ]
}
