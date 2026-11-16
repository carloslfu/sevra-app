import Foundation
import SevraCore

extension NativeAppReview {
  package static func numericInputs(_ contracts: Value) -> Value {
    .array(
      contracts.object.keys.sorted().flatMap { action in
        contracts[action].object.keys.sorted().compactMap { field -> Value? in
          let input = contracts[action][field]
          guard ["number", "decimal"].contains(input["type"].text) else { return nil }
          return .object([
            "action": .string(action), "input": .string(field),
            "type": input["type"], "valueType": input["valueType"],
          ])
        }
      })
  }

  /// Keep reviewer protocol/setup diagnostics in the exact receipt, separate from
  /// source-repair instructions. A reproduced app defect never takes this path.
  package static func presentedFailure(_ value: Value, receiptID: String) -> Value {
    guard value["failureStage"] == .string("independent_review"),
      value["reviewDiagnostic"] != .null
    else { return value }
    var fields = value.object
    fields["reviewDiagnostic"] = .object([
      "omitted": .bool(true), "receiptID": .string(receiptID),
      "path": .array([.string("reviewDiagnostic")]),
      "notice": .string(
        "Reviewer-only diagnostic, retained for inspection with tool_result. It is not a demonstrated app defect or an SDK source-edit instruction."
      ),
    ])
    return .object(fields)
  }

  /// An exact title match with an original heading and a unique inventory of
  /// fixture keys is enough to demand a disambiguating test, not to infer a rule.
  private static func possibleLookupColumns(
    field: String, title: String, value: Value, fixtures: Value,
    package: NativeAppPackage, tables: [Dataset], coordinates: [[Int]],
    inputCell: (String) throws -> Value
  ) -> [String] {
    guard let entered = value.string, !entered.isEmpty else { return [] }
    func normalized(_ text: String) -> String {
      text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    let names = Set([normalized(field), normalized(title)]).subtracting([""])
    var matches: [String] = []
    for (alias, binding) in package.datasets.sorted(by: { $0.key < $1.key }) {
      guard let sheet = tables.firstIndex(where: { $0.id == binding.datasetID }),
        coordinates.indices.contains(sheet), let row = coordinates[sheet].first
      else { continue }
      let rows = fixtures[alias].array
      for (index, column) in binding.columns.enumerated() {
        let keys = rows.compactMap { $0[column.id].string }.filter { !$0.isEmpty }
        guard Set(keys).count == keys.count, keys.contains(entered) else {
          continue
        }
        // Review fixtures can omit the very heading needed to detect a lookup.
        // The exact original cell supplies the label, even in a headerless sample.
        let cell = "sheet\(sheet + 1)!" + Workbook.spreadsheetColumn(index) + String(row)
        guard let label = (try? inputCell(cell))?.string, names.contains(normalized(label)) else {
          continue
        }
        matches.append(alias + "." + column.id + " (" + cell + ")")
      }
    }
    return matches
  }

  /// Accept a field-indexed classification only when each supplied field belongs
  /// to exactly one exercised action. It must carry the same complete roles.
  package static func actionIndexedRoles(
    _ roles: Value, actions: Set<String>, registeredActions: Set<String>, steps: [Value]
  ) -> Value {
    guard registeredActions.isDisjoint(with: roles.object.keys) else { return roles }
    var actionFields: [String: Set<String>] = [:]
    var allFields = Set<String>()
    for index in steps.indices.dropLast() {
      let step = steps[index]
      let action = step["action"].text
      guard actions.contains(action), actionFields[action] == nil,
        !assertedSuccessfulActions(Array(steps[index...index + 1])).isEmpty
      else { continue }
      let fields = Set(step["inputs"].object.keys)
      guard allFields.isDisjoint(with: fields) else { return roles }
      allFields.formUnion(fields)
      actionFields[action] = fields
    }
    guard Set(actionFields.keys) == actions, allFields == Set(roles.object.keys) else {
      return roles
    }
    var normalized: [String: Value] = [:]
    for (action, fields) in actionFields {
      var mapped: [String: Value] = [:]
      for field in fields {
        let entry = roles[field]
        let role =
          Set(entry.object.keys) == ["kind"] && entry["kind"].string == nil
          ? entry["kind"] : entry
        guard role["kind"].string != nil else { return roles }
        mapped[field] = role
      }
      normalized[action] = .object(mapped)
    }
    return .object(normalized)
  }

  /// The reviewer classifies business meaning. The host verifies its references
  /// and derives the actual probes, so a declared lookup cannot skip its header.
  package static func inputProbes(
    actions: Set<String>, registeredActions: Set<String>? = nil,
    roles: Value, steps: [Value], fixtures: Value,
    inputTypes: Value, contracts: Value = .null, package: NativeAppPackage, tables: [Dataset],
    coordinates: [[Int]],
    inputCell: (String) throws -> Value
  ) throws -> [Value] {
    try require(
      actions.isSubset(of: Set(roles.object.keys))
        && Set(roles.object.keys).isSubset(of: registeredActions ?? actions), "app_review_inputs",
      "inputRoles must classify every tested action and each of its supplied inputs: "
        + actions.sorted().joined(separator: ", ")
        + ". Roles for other registered actions are allowed but do not count as tested coverage. Unknown action IDs are not allowed. Use value for text/boolean entered values; number with whole/minimum/maximum/nonzero rules for numeric inputs; existingKey with the original table/column/headerRow for record lookups. Derive rules from the request, not from what the candidate accepts."
    )
    // A one-action counterexample can carry the reviewer's full classification.
    // Only actually exercised actions acquire probes or readiness evidence.
    var probes: [Value] = []
    var total = 0
    var misclassified = Set<String>()
    for index in steps.indices.dropLast()
    where actions.contains(steps[index]["action"].text)
      && !Self.assertedSuccessfulActions(Array(steps[index...index + 1])).isEmpty
    {
      let action = steps[index]["action"].text
      for (field, type) in inputTypes[String(index)].object
      where ["number", "decimal"].contains(type.text)
        && roles[action][field]["kind"] == .string("value")
      {
        misclassified.insert(action + "." + field + " (" + type.text + ")")
      }
    }
    try require(
      misclassified.isEmpty, "app_review_inputs",
      "Correct these numeric fields in the review-only inputRoles: "
        + misclassified.sorted().joined(separator: ", ")
        + ". Decimal values are JSON strings but still require numeric rules. Use kind:number with whole, minimum, maximum and nonzero derived from the request; existingKey is only for an actual record lookup. Do not add these review fields to Sevra.action input metadata or ask the builder to change its source."
    )
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
          let contract = contracts[action][field]
          if ["text", "record"].contains(type), contract != .null,
            contract["choices"].array.isEmpty
          {
            let candidates = Self.possibleLookupColumns(
              field: field, title: contract["title"].text,
              value: inputs[field]!, fixtures: fixtures, package: package,
              tables: tables, coordinates: coordinates, inputCell: inputCell)
            try require(
              candidates.isEmpty, "app_review_inputs",
              action + "." + field + " repeats an existing key from "
                + candidates.prefix(4).joined(separator: ", ")
                + " under a matching original heading. If the request needs an existing record, classify it as existingKey, choosing the actual source. If the request allows an independently entered value, repeat your successful test with a valid value that is not a fixture key. This is a review-only classification; it does not establish a code defect."
            )
          }
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
        var revised = call.object
        revised["inputs"] = .object(changed)
        if !Self.allowedNumberProbeRules.contains(variant["rule"].text) {
          revised["reject"] = .bool(true)
        }
        var probe = variant.object
        probe["action"] = .string(action)
        probe["tests"] = .array(Array(steps.prefix(index)) + [.object(revised)])
        probes.append(.object(probe))
      }
    }
    return probes
  }
}
