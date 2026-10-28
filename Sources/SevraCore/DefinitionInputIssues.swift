import Foundation

extension Workbook {
  /// Bounded field diagnostics for incomplete forms, never an action or permission check.
  public func applicationInputIssues(_ id: String, arguments: Value) throws -> [Value] {
    let control = Cancellation(deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction {
          let descriptor = try DefinitionDescriptor(applicationDefinition(id).content)
          guard case .object(let supplied) = arguments, try arguments.json().utf8.count <= 64_000
          else {
            throw SevraError("definition_input", "Arguments must be an object of at most 64 KB.")
          }
          var issues: [Value] = []
          func issue(_ path: [Value], _ error: Error) {
            if issues.count < 100 {
              issues.append(
                .object([
                  "path": .array(path),
                  "code": .string((error as? SevraError)?.code ?? "definition_input"),
                  "message": .string(error.localizedDescription),
                ]))
            }
          }
          func inspect(_ parameter: DefinitionParameter, _ raw: Value?, _ path: [Value]) throws {
            try control.check()
            guard let value = raw ?? parameter.defaultValue else {
              if parameter.required {
                issue(path, SevraError("definition_input", "Enter " + parameter.label + "."))
              }
              return
            }
            if parameter.type == "entries", case .array(let rows) = value,
              (1...(parameter.maxEntries ?? 1)).contains(rows.count)
            {
              for (index, row) in rows.enumerated() {
                guard case .object(let values) = row else {
                  issue(
                    path + [.number(Double(index))],
                    SevraError("definition_input", "Enter a structured line."))
                  continue
                }
                let keys = Set(parameter.fields.map(\.id))
                for key in values.keys.sorted() where !keys.contains(key) {
                  issue(
                    path + [.number(Double(index)), .string(key)],
                    SevraError("definition_input", "Undeclared entry field."))
                }
                for field in parameter.fields {
                  try inspect(
                    field, values[field.id], path + [.number(Double(index)), .string(field.id)])
                }
              }
            } else {
              do {
                let normalized = try parameter.normalize(value)
                try validateDefinitionItemReferences(parameter, normalized)
              } catch { issue(path, error) }
            }
          }
          let keys = Set(descriptor.parameters.map(\.id))
          for key in supplied.keys.sorted() where !keys.contains(key) {
            issue([.string(key)], SevraError("definition_input", "Undeclared parameter."))
          }
          for parameter in descriptor.parameters {
            try inspect(parameter, supplied[parameter.id], [.string(parameter.id)])
          }
          return issues
        }
      }
    }
  }
}
