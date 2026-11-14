import SevraCore

extension NativeTools {
  static let excelBehaviorSchema = object(
    [
      "source": schema(
        "string",
        "Pure JavaScript function recreate(input). Read values with input.cells['sheet1!B2'], never c2 or input.c2. For recalculate return declared output cells; for actions return ONLY their changed non-formula write cells. All returned values are strings."
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
            "id": .object([
              "type": .string("string"), "minLength": .number(1), "maxLength": .number(64),
              "description": .string(
                "Case-sensitive action ID, up to 64 ASCII letters/digits/underscores, starting with a letter. Original macro names such as ShipStock are valid. Not recalculate."
              ),
            ]),
            "title": schema("string", "Human action name."),
            "writes": .object([
              "type": .string("array"), "maxItems": .number(64),
              "items": schema("string", "Exact non-formula cell this action can edit."),
            ]),
            "inputs": .object([
              "type": .string("array"), "maxItems": .number(16),
              "items": object(
                [
                  "id": .object([
                    "type": .string("string"), "minLength": .number(1), "maxLength": .number(64),
                    "description": .string(
                      "Case-sensitive argument key, up to 64 ASCII letters/digits/underscores, starting with a letter."
                    ),
                  ]),
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
      "Run candidate recreated behavior in isolation and compare with immutable original results and user-added original-result examples. Expected answers are host-owned. A match retains this exact behavior for this build: omit package.excelBehavior in save_native_app to reuse it. A later failed or mismatched comparison clears the draft. Fix differences before saving. A match covers only those examples.",
    parameters: object(["behavior": excelBehaviorSchema], required: ["behavior"]))
}
