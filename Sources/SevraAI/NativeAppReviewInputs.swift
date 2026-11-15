import Foundation
import SevraCore

extension NativeAppReview {
  /// The reviewer classifies business meaning. The host verifies its references
  /// and derives the actual probes, so a declared lookup cannot skip its header.
  package static func inputProbes(
    actions: Set<String>, roles: Value, steps: [Value], fixtures: Value,
    inputTypes: Value, package: NativeAppPackage, tables: [Dataset], coordinates: [[Int]],
    inputCell: (String) throws -> Value
  ) throws -> [Value] {
    try require(
      Set(roles.object.keys) == actions, "app_review_inputs",
      "inputRoles must classify every tested action and each of its supplied inputs: "
        + actions.sorted().joined(separator: ", ")
        + ". Use value for text/boolean entered values; number with whole/minimum/maximum/nonzero rules for numeric inputs; existingKey with the original table/column/headerRow for record lookups. Derive rules from the request, not from what the candidate accepts."
    )
    var probes: [Value] = []
    var total = 0
    for action in actions.sorted() {
      guard
        let index = steps.indices.dropLast().first(where: {
          steps[$0]["action"] == .string(action)
            && Self.assertedSuccessfulActions(Array(steps[$0...($0 + 1)])).contains(action)
        })
      else { throw SevraError("app_review_inputs", "Missing successful action: " + action) }
      let call = steps[index]
      let inputs = call["inputs"].object
      var variants: [Value] = []
      guard case .object = roles[action] else {
        throw SevraError(
          "app_review_inputs", "Classify the inputs of " + action + " with an object.")
      }
      try require(
        Set(roles[action].object.keys) == Set(inputs.keys), "app_review_inputs",
        "Classify EVERY supplied input of " + action + ": "
          + inputs.keys.sorted().joined(separator: ", "))
      for (field, role) in roles[action].object.sorted(by: { $0.key < $1.key }) {
        let type = inputTypes[String(index)][field].text
        try require(!type.isEmpty, "app_review_inputs", "Missing executed action input type.")
        if role["kind"] == .string("value") {
          try require(
            Set(role.object.keys) == ["kind"] && !["number", "decimal"].contains(type),
            "app_review_inputs",
            action + "." + field + " is " + type
              + ". Numeric inputs require kind:number with whole, minimum, maximum and nonzero rules; other value roles only have kind."
          )
          continue
        }
        if role["kind"] == .string("number") {
          try require(
            ["number", "decimal"].contains(type), "app_review_inputs",
            "Numeric rules must describe an actual number/decimal input.")
          for (rule, value) in try Self.numberProbes(role: role, input: inputs[field]!) {
            variants.append(
              .object(["input": .string(field), "rule": .string(rule), "value": value]))
          }
          continue
        }
        let alias = role["table"].text
        let column = role["column"].text
        guard role["kind"] == .string("existingKey"),
          Set(role.object.keys) == ["kind", "table", "column", "headerRow"],
          let binding = package.datasets[alias],
          let sheet = tables.firstIndex(where: { $0.id == binding.datasetID }),
          let columnIndex = binding.columns.firstIndex(where: { $0.id == column }),
          coordinates.indices.contains(sheet), let row = role["headerRow"].int,
          row > 0, role["headerRow"] == .number(Double(row)),
          let position = coordinates[sheet].firstIndex(of: row)
        else {
          throw SevraError(
            "app_review_inputs", "Invalid existing-key mapping for " + action + "." + field)
        }
        let cell = "sheet\(sheet + 1)!" + Workbook.spreadsheetColumn(columnIndex) + String(row)
        guard let header = try inputCell(cell).string, !header.isEmpty else {
          throw SevraError(
            "app_review_inputs", "The declared header needs original input evidence: " + cell)
        }
        try require(
          fixtures[alias].array.indices.contains(position)
            && fixtures[alias].array[position][column] == .string(header)
            && fixtures[alias].array.filter({ $0[column] == .string(header) }).count == 1,
          "app_review_inputs",
          "Preserve the original header " + header + " in synthetic " + alias + "." + column
            + " only at fixture position \(position) before testing " + action + "." + field
            + ". Use a distinct invented key for valid data rows.")
        // The successful call already passed the SDK's exact type check. A
        // numeric/boolean key cannot receive a text header through that contract;
        // reject:true deliberately refuses type errors as business-rule evidence.
        if ["number", "decimal", "boolean"].contains(type) { continue }
        try require(
          inputs[field]?.string != nil, "app_review_inputs", "Existing keys must use scalar inputs."
        )
        variants.append(
          .object([
            "input": .string(field), "rule": .string("header"), "cell": .string(cell),
            "value": .string(header),
          ]))
      }
      guard !variants.isEmpty else { continue }
      total += variants.count
      try require(
        total <= 64 && index + 1 <= 32, "app_review_inputs",
        "Keep derived input checks within 32 steps per probe and 64 variants per review batch.")
      // Each variant gets a fresh worker state and precisely the pre-call setup.
      // Even a refusal with no data writes can change signals/closure state and
      // mask a later invalid input. Never run other variants or the successful
      // insert first; its duplicate guard could also conceal a missing rule.
      for variant in variants {
        var changed = inputs
        changed[variant["input"].text] = variant["value"]
        var rejected = call.object
        rejected["inputs"] = .object(changed)
        rejected["reject"] = .bool(true)
        var probe = variant.object
        probe["action"] = .string(action)
        probe["tests"] = .array(Array(steps.prefix(index)) + [.object(rejected)])
        probes.append(.object(probe))
      }
    }
    return probes
  }
}
