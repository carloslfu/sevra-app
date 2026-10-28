import Foundation

extension Workbook {
  public func evaluateApplicationDefinition(
    _ id: String, arguments: Value = .object([:]), cursor: String? = nil,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction {
          let definition = try applicationDefinition(id)
          try require(
            ["function", "query"].contains(definition.kind), "definition_kind",
            "Actions and forms require explicit preview and invocation, not pure evaluation.")
          let descriptor = try DefinitionDescriptor(definition.content)
          let supplied = try definitionArguments(descriptor, arguments)
          let state = DefinitionEvaluation(control)
          let result: Value
          var next: Value = .null
          if definition.kind == "function" {
            try require(cursor == nil, "definition_cursor", "A pure function has no continuation.")
            result = try evaluateFunction(definition, arguments: arguments, state: state, depth: 0)
          } else {
            try state.enter(definition, depth: 0)
            let query = try resolvedDefinitionQuery(descriptor, arguments: supplied)
            var queryCursor: String?
            if let cursor {
              guard cursor.utf8.count <= 16_384, let bytes = Data(base64Encoded: cursor),
                let saved = try? Value.parse(String(decoding: bytes, as: UTF8.self)),
                saved["definitionID"] == .string(definition.id),
                let position = saved["queryCursor"].string
              else {
                throw SevraError(
                  "definition_cursor",
                  "The query definition changed or its continuation is invalid.")
              }
              queryCursor = position
            }
            let output = try queryDataset(query, cursor: queryCursor, cancellation: control)
            if let position = output["nextCursor"].string {
              next = .string(
                Data(
                  try Value.object([
                    "definitionID": .string(definition.id), "queryCursor": .string(position),
                  ]).json().utf8
                ).base64EncodedString())
            }
            result = output
          }
          let snapshot = try db.scalar(
            "SELECT id FROM committed_changes ORDER BY rowid DESC LIMIT 1"
          ).text
          return .object([
            "workbookID": .string(self.id), "definitionID": .string(definition.id),
            "logicalID": .string(definition.logicalID), "kind": .string(definition.kind),
            "snapshot": .string(snapshot), "arguments": .object(supplied),
            "submittedArguments": arguments, "result": result, "nextCursor": next,
            "unit": descriptor.payload["unit"], "rounding": descriptor.payload["rounding"],
            "resolvedDefinitions": .array(
              state.resolved.values.sorted { $0.id < $1.id }.map {
                .object([
                  "id": .string($0.id), "logicalID": .string($0.logicalID),
                  "sourceID": .string($0.sourceID),
                ])
              }),
            "arithmetic": .string(
              "Foundation Decimal, up to 38 significant digits; division/plain rounding may lose precision"
            ),
            "readOnly": .bool(true),
          ])
        }
      }
    }
  }
}
