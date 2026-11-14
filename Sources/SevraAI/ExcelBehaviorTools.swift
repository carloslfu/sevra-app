import SevraCore

extension NativeTools {
  static let excelBehaviorSchema = object(
    [
      "source": schema(
        "string",
        "Pure JavaScript function recreate(input), returning a flat cell:string object. Read native_app_sdk."
      ),
      "outputs": .object([
        "type": .string("array"), "maxItems": .number(2000),
        "items": schema(
          "string", "Exact derived cell, e.g. sheet1!D2. Include every original formula."),
      ]),
      "actions": .object([
        "type": .string("array"), "maxItems": .number(24),
        "items": object(
          [
            "id": schema("string", "Short action ID, not recalculate."),
            "title": schema("string", "Human action name."),
            "writes": .object([
              "type": .string("array"), "maxItems": .number(64),
              "items": schema("string", "Exact non-formula cell this action can edit."),
            ]),
            "inputs": .object([
              "type": .string("array"), "maxItems": .number(16),
              "items": object(
                [
                  "id": schema("string", "Argument key used by this action."),
                  "title": schema("string", "Visible input label."),
                ], required: ["id", "title"]),
            ]),
          ], required: ["id", "title", "writes", "inputs"]),
      ]),
      "gaps": .object([
        "type": .string("array"), "maxItems": .number(24),
        "items": schema(
          "string", "Specific original behavior not recreated; never hide an unresolved dependency."
        ),
      ]),
    ], required: ["source", "outputs", "actions", "gaps"])

  static let excelEvidenceDefinition = WorkbookToolDefinition(
    name: "inspect_excel_evidence",
    description:
      "Read the current original's inert source evidence: VBA modules, formulas, names, validation, layout, charts, pivot definitions and connections. Omit part to list the catalog; use nextOffset to read more. Never executes the original.",
    parameters: object(
      [
        "part": schema("string", "Exact evidence ID from the catalog."),
        "offset": schema("integer", "Character offset, default zero."),
      ], required: []))
  static let excelBehaviorDefinition = WorkbookToolDefinition(
    name: "compare_excel_behavior",
    description:
      "Run candidate recreated behavior in isolation and compare with immutable original results and user-added original-result examples. Expected answers are host-owned. Fix differences before saving. A match covers only those examples.",
    parameters: object(["behavior": excelBehaviorSchema], required: ["behavior"]))
}
