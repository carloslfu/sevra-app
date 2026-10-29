import Foundation

extension Workbook {
  /// Discovery is versioned metadata, never permission to execute a definition.
  public func searchApplicationDefinitions(
    _ query: String, kind: String? = nil, historical: Bool = false,
    limit: Int = 20, cursor: String? = nil, cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      (1...50).contains(limit)
        && (kind == nil
          || ["function", "query", "action", "form", "workflow", "interpretation", "extraction"]
            .contains(kind!)),
      "definition_limit",
      "Use function/query/action/form/workflow scope and a page limit from 1 to 50.")
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction {
          let terms = try Self.searchTerms(query)
          let identity = ChangeFormat.hash(
            try Value.object([
              "query": .string(query), "kind": kind.map(Value.string) ?? .null,
              "historical": .bool(historical), "limit": .number(Double(limit)),
            ]).json())
          let snapshot = try definitionReadSnapshot()
          var after = ""
          if let cursor {
            guard cursor.utf8.count <= 8192, let bytes = Data(base64Encoded: cursor),
              let saved = try? Value.parse(String(decoding: bytes, as: UTF8.self)),
              saved["workbookID"] == .string(id), saved["query"] == .string(identity),
              let position = saved["after"].string, UUID(uuidString: position) != nil
            else {
              throw SevraError("definition_cursor", "Invalid definition search continuation.")
            }
            try require(
              saved["snapshot"] == .string(snapshot), "stale_definition_search",
              "Definitions or workbook state changed. Search again.")
            after = position
          }
          var joins = ""
          var predicates = ["d.id>?"]
          var values: [Value] = [.string(after)]
          if !terms.isEmpty {
            joins += " JOIN definition_fts ON definition_fts.rowid=d.rowid"
            predicates.append("definition_fts MATCH ?")
            values.append(.string(terms))
          } else {
            try require(
              query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              "definition_query", "Search needs letters or digits.")
          }
          if !historical { joins += " JOIN app_definition_heads h ON h.definition_id=d.id" }
          if let kind {
            predicates.append("d.kind=?")
            values.append(.string(kind))
          }
          values.append(.number(Double(limit + 1)))
          let rows = try db.execute(
            "SELECT d.id,d.logical_id,d.version,d.kind,d.title,d.description,d.source_id,EXISTS(SELECT 1 FROM app_definition_heads h WHERE h.definition_id=d.id) AS is_current FROM app_definitions d"
              + joins + " WHERE " + predicates.joined(separator: " AND ")
              + " ORDER BY d.id LIMIT ?",
            values, maxRows: limit + 1, maxBytes: 2_097_152)
          let page = Array(rows.prefix(limit))
          var next: Value = .null
          if rows.count > limit {
            next = .string(
              Data(
                try Value.object([
                  "workbookID": .string(id), "query": .string(identity),
                  "snapshot": .string(snapshot),
                  "after": page.last!["id"]!,
                ]).json().utf8
              ).base64EncodedString())
          }
          return .object([
            "workbookID": .string(id), "snapshot": .string(snapshot),
            "historical": .bool(historical),
            "hits": .array(page.map(Value.object)), "nextCursor": next,
            "order": .string("exact version ID"),
          ])
        }
      }
    }
  }

  func verifyApplicationDefinitions() throws {
    let invalid = try db.scalar(
      """
      SELECT count(*) FROM app_definitions d
      LEFT JOIN app_definitions p ON p.id=d.previous_id
      JOIN items s ON s.id=d.source_id
      WHERE s.category!='source' OR typeof(d.version)!='integer'
      OR (d.version=1 AND d.previous_id IS NOT NULL)
      OR (d.version>1 AND (p.id IS NULL OR p.logical_id!=d.logical_id OR p.kind!=d.kind OR p.version!=d.version-1))
      """
    ).int
    let invalidHeads = try db.scalar(
      """
      SELECT count(*) FROM app_definition_heads h JOIN app_definitions d ON d.id=h.definition_id
      WHERE h.logical_id!=d.logical_id OR d.version!=(SELECT max(v.version) FROM app_definitions v WHERE v.logical_id=h.logical_id)
      """
    ).int
    let missing = try db.scalar(
      """
      SELECT count(*) FROM (SELECT d.logical_id FROM app_definitions d LEFT JOIN app_definition_heads h ON h.logical_id=d.logical_id
      GROUP BY d.logical_id HAVING count(*)!=max(d.version) OR min(d.version)!=1 OR max(h.logical_id) IS NULL)
      """
    ).int
    let collided = try db.scalar(
      "SELECT count(*) FROM app_definition_heads h JOIN app_definitions d ON d.id=h.logical_id"
    ).int
    try require(
      invalid == 0 && invalidHeads == 0 && missing == 0 && collided == 0,
      "definition_integrity", "Application definition history or heads are inconsistent.")
    var after = ""
    while true {
      let rows = try db.execute(
        "SELECT * FROM app_definitions WHERE id>? ORDER BY id LIMIT 100", [.string(after)])
      if rows.isEmpty { break }
      for row in rows {
        let saved = try ApplicationDefinition(row)
        let descriptor = try DefinitionDescriptor(saved.content)
        let source = try item(saved.sourceID)
        try require(
          source.category == "source" && source.kind == "application_definition"
            && source.data["submitted"]["logicalID"] == .string(saved.logicalID)
            && source.data["submitted"]["base"] == (saved.previousID.map(Value.string) ?? .null)
            && source.data["submitted"]["content"] == saved.content,
          "definition_integrity", "The definition disagrees with its exact authoring Source.")
        try JSONDecoder().decode(ChangeActor.self, from: Data(source.data["actor"].json().utf8))
          .validate()
        try require(
          row["parameter_text"]
            == .string(descriptor.parameters.map { $0.id + " " + $0.label }.joined(separator: " ")),
          "definition_integrity", "Parameter search text disagrees with its definition.")
        let dependencies = try applicationDefinitionDependencies(saved.id)
        if saved.kind == "function" {
          let function = try DefinitionFunction(descriptor)
          try require(
            dependencies.count == function.calls.count, "definition_integrity",
            "Missing function dependencies.")
          for (index, call) in function.calls.enumerated() {
            let dependency = dependencies[index]
            let target = try applicationDefinition(dependency["target_version"].text)
            try require(
              dependency["ordinal"].int == index && dependency["kind"].text == "definition"
                && target.id == dependency["target_version"].text
                && target.logicalID == dependency["target_logical"].text
                && target.kind == "function"
                && dependency["mode"].text == call.binding.mode
                && (call.binding.mode == "live" ? target.logicalID : target.id)
                  == call.binding.target,
              "definition_integrity", "Saved call dependency differs from its declared binding.")
            _ = try mapDefinitionCall(
              call, caller: descriptor, target: DefinitionDescriptor(target.content),
              arguments: nil, validateOnly: true)
          }
        } else if saved.kind == "extraction" {
          _ = try DefinitionExtraction(descriptor)
          try require(
            dependencies.isEmpty, "definition_integrity", "Extraction cannot call behavior.")
        } else if saved.kind == "interpretation" {
          _ = try DefinitionInterpretation(descriptor)
          try require(
            dependencies.isEmpty, "definition_integrity", "Interpretations cannot call behavior.")
        } else if saved.kind == "workflow" {
          try validateWorkflowDefinition(descriptor, historical: true)
          let bindings = try definitionBindings(descriptor)
          try require(
            dependencies.count == bindings.count, "workflow_integrity",
            "Missing workflow dependencies.")
          for (index, binding) in bindings.enumerated() {
            let target = try resolveDefinition(binding)
            let row = dependencies[index]
            try require(
              row["ordinal"].int == index && row["kind"].text == "definition"
                && row["mode"].text == "exact" && row["target_version"].text == target.id
                && row["target_logical"].text == target.logicalID,
              "workflow_integrity", "The retained workflow dependency is inconsistent.")
          }
        } else if saved.kind == "action" || saved.kind == "form" {
          let bindings = try definitionBindings(descriptor)
          try require(
            dependencies.count == bindings.count, "definition_integrity",
            "Missing action/form dependencies.")
          for (index, binding) in bindings.enumerated() {
            let dependency = dependencies[index]
            let target = try applicationDefinition(dependency["target_version"].text)
            try require(
              dependency["ordinal"].int == index && dependency["kind"].text == "definition"
                && dependency["mode"].text == binding.mode
                && target.id == dependency["target_version"].text
                && target.logicalID == dependency["target_logical"].text
                && (binding.mode == "live" ? target.logicalID : target.id) == binding.target,
              "definition_integrity",
              "Saved action/form binding differs from its retained dependency.")
            if saved.kind == "form" {
              try validateForm(DefinitionForm(descriptor), descriptor: descriptor, action: target)
            } else {
              let action = try DefinitionAction(descriptor)
              let call = try action.calls[index]
              let targetDescriptor = try DefinitionDescriptor(target.content)
              let parameter = action.target.parameters.first { $0.id == call.alias }
              try require(
                target.kind == "function" && parameter?.type == "decimal"
                  && (try DefinitionFunction(targetDescriptor)).unit == parameter?.unit,
                "definition_integrity", "Computed action input has the wrong type or unit.")
              _ = try mapDefinitionCall(
                call, caller: descriptor, target: targetDescriptor, arguments: nil,
                validateOnly: true)
            }
          }
          if saved.kind == "action" {
            let action = try DefinitionAction(descriptor)
            let calls = try action.calls
            var plain = action.arguments.filter { $0.value.object["function"] == nil }
            for call in calls {
              let parameter = action.target.parameters.first { $0.id == call.alias }!
              var literal: [String: Value] = ["literal": parameter.sample]
              if let unit = parameter.unit { literal["unit"] = .string(unit) }
              plain[call.alias] = .object(literal)
            }
            let dummy = DefinitionFunction.Call(
              alias: "primitive",
              binding: try DefinitionBinding(
                .object(["mode": .string("exact"), "versionID": .string(saved.id)])),
              arguments: plain)
            _ = try mapDefinitionCall(
              dummy, caller: descriptor, target: action.target, arguments: nil, validateOnly: true)
          }
        } else {
          _ = try resolvedDefinitionQuery(
            descriptor, arguments: [:], samples: true, verifyHistorical: true)
          let payload = try definitionObject(saved.payload, keys: ["query", "dataMode"])
          let sources = payload["query"]?["sources"].array ?? []
          try require(
            dependencies.count == sources.count && !sources.isEmpty,
            "definition_integrity", "Missing query dependencies.")
          for (index, source) in sources.enumerated() {
            let dependency = dependencies[index]
            try require(
              dependency["ordinal"].int == index && dependency["kind"].text == "dataset"
                && dependency["mode"] == payload["dataMode"]
                && dependency["target_dataset"] == source["datasetID"]
                && dependency["target_dataset_definition"] == source["definitionID"],
              "definition_integrity", "Saved query dependency differs from its bound schema.")
          }
        }
        after = saved.id
      }
    }
  }
}
