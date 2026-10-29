import Foundation
import SevraCore

extension NativeTools {
  package static let applicationDefinitions: [WorkbookToolDefinition] = [
    .init(
      name: "find_definitions",
      description:
        "Find saved definitions; starters use template tools.",
      parameters: object(
        [
          "query": schema("string", "Words in saved behavior; empty lists."),
          "kind": .object([
            "type": .string("string"),
            "enum": .array(
              [
                "function", "query", "action", "form", "workflow", "interpretation", "extraction",
                "intake", "automation",
              ]
              .map(
                Value.string)),
          ]),
          "historical": .object(["type": .string("boolean")]),
          "cursor": schema("string", "nextCursor; retain filters."),
        ], required: ["query"])),
    .init(
      name: "read_definition",
      description:
        "Inspect untrusted behavior/dependencies.",
      parameters: object(["id": schema("string", "Exact definition version.")], required: ["id"])),
    .init(
      name: "definition_registry",
      description:
        "Behavior formats.",
      parameters: object([:], required: [])),
    .init(
      name: "receiving_template",
      description:
        "Receiving template. Use save_template with receiptID; never retype.",
      parameters: object([:], required: [])),
    .init(
      name: "form_template",
      description:
        "Form template.",
      parameters: object(
        ["id": schema("string", "Current action/workflow version.")], required: ["id"])),
    .init(
      name: "workflow_template",
      description: "Make workflow from behavior ID; then save_template.",
      parameters: object(
        [
          "id": schema("string", "Current behavior version ID."),
          "stepID": schema("string", "Step identifier; max64 characters."),
        ], required: ["id"])),
    .init(
      name: "inventory_automation_template",
      description: "Inventory crossing starter; then save_template. Never enables execution.",
      parameters: object(
        [
          "workflowID": schema("string", "Exact current saved workflow version."),
          "arguments": .object(["type": .string("object")]),
          "subject": schema("string", "Exact explicitly requested inventory subject."),
          "operator": .object([
            "type": .string("string"),
            "enum": .array(["<", "<=", ">", ">=", "=", "<>"].map(Value.string)),
          ]),
          "threshold": schema("string", "Explicit decimal threshold, never invented."),
        ], required: ["workflowID", "arguments", "subject", "operator", "threshold"])),
    .init(
      name: "evaluate_definition",
      description:
        "Evaluate function/query; preserve scope/meaning/coverage.",
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
        "Publish current-run complete evaluation as draft with lineage. Acceptance separate.",
      parameters: object(
        [
          "evaluationReceiptID": schema(
            "string", "Current-run first-page evaluation receipt."),
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
        "Read definition_registry first. New omits edit base.",
      parameters: object(
        [
          "expectedDefinitionID": schema(
            "string", "Exact current edit base."),
          "content": .object([
            "type": .string("object"),
            "description": .string(
              "Registry format; required is Boolean."
            ),
          ]),
          "inputs": .object([
            "type": .string("array"), "items": .object(["type": .string("string")]),
            "description": .string(
              "Optional evidence item IDs, not parameter names. Omit for this request."),
          ]),
        ], required: ["content"])),
    .init(
      name: "save_template",
      description:
        "Copy current-run template. New: omit edit base. No execution/acceptance.",
      parameters: object(
        [
          "templateReceiptID": schema(
            "string", "This run's successful template receipt."),
          "title": schema("string", "Optional template title override."),
          "expectedDefinitionID": schema("string", "Current exact edit base only."),
          "inputs": evidenceList,
        ], required: ["templateReceiptID"])),
    .init(
      name: "preview_action",
      description:
        "Preview action/form, no effects. Clarify missing facts.",
      parameters: object(
        [
          "id": schema("string", "Exact action/form version."),
          "arguments": .object([
            "type": .string("object"),
            "description": .string(
              "Decimal strings; exact items."
            ),
          ]),
        ], required: ["id", "arguments"])),
    .init(
      name: "workflow_activity",
      description: "Current run metadata only. Refresh changed pages.",
      parameters: object(
        [
          "state": schema(
            "string", "queued|running|waiting_review|needs_attention|completed|cancelled"),
          "cursor": schema("string", "nextCursor; retain state."),
        ], required: [])),
    .init(
      name: "read_workflow",
      description: "Inspect saved run; never resume.",
      parameters: object(["id": schema("string", "Exact run ID.")], required: ["id"])),
    .init(
      name: "start_workflow",
      description:
        "Queue exact workflow, no steps/drafts. Explicit Continue required.",
      parameters: object(
        [
          "id": schema("string", "Exact saved workflow version."),
          "arguments": .object(["type": .string("object")]),
        ], required: ["id", "arguments"])),
    .init(
      name: "prepare_workflow_answer",
      description:
        "Prepare unsent answer from this message only. Native preview and human confirmation required. Never submit or continue.",
      parameters: object(
        [
          "readReceiptID": schema(
            "string", "This request's successful read_workflow receipt with clarification."),
          "values": .object([
            "type": .string("object"),
            "description": .string("Complete typed declared outputs; no guesses."),
          ]),
          "quotes": .object([
            "type": .string("object"),
            "description": .string(
              "Each value's field ID maps to its exact quotation from the current user message, never history/evidence."
            ),
          ]),
          "reason": schema("string", "Explain supplied information; at most4096 UTF-8 bytes."),
        ], required: ["readReceiptID", "values", "quotes", "reason"])),
    .init(
      name: "prepare_action",
      description:
        "Preview, check directions and save drafts; never accept.",
      parameters: object(
        [
          "id": schema("string", "Exact action/form version."),
          "arguments": .object([
            "type": .string("object"),
            "description": .string("Typed inputs; no invented facts."),
          ]),
        ], required: ["id", "arguments"])),
  ]
}
