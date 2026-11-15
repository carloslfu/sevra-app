import Foundation
import SevraCore

extension NativeTools {
  static let chatDefinitions: [WorkbookToolDefinition] = [
    .init(
      name: "workspace_actions",
      description:
        "Discover chat operations and required inputs before workspace_action. Ask the user for missing business values.",
      parameters: object(
        [
          "domain": .object([
            "type": .string("string"), "description": .string("Optional operation family."),
            "enum": .array(
              [
                "chat", "app", "record", "form", "document", "table", "workflow", "automation",
                "file", "intake", "excel",
              ].map(Value.string)),
          ])
        ], required: [])),
    .init(
      name: "workspace_action",
      description:
        "Use discovered arguments and inspected versions. Before app.run, check EVERY required input against what the user supplied. Missing quantity, price, date or other business values require a question with finish; never invent 1 or use incidental field defaults. Confirmation-required results are pending: ask the user to confirm in chat; never claim they ran.",
      parameters: object(
        [
          "action": .object([
            "type": .string("string"),
            "description": .string(
              "Exact workspace operation. Named mini-app actions go inside arguments.action for app.run."
            ),
            "enum": .array(ChatOperations.operations.map { .string($0.name) }),
          ]),
          "arguments": .object([
            "type": .string("object"),
            "description": .string("Only the required/optional input fields from discovery."),
          ]),
        ], required: ["action", "arguments"])),
  ]
}
