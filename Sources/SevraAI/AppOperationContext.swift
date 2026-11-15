import Foundation
import SevraCore

/// Named-action arguments come from conversation, independently of visual drafts.
/// Keep the exact inspection in its receipt; controls remain explicitly retrievable.
package enum AppOperationContext {
  package static func inspection(_ value: Value, receiptID: String, request: String) -> Value {
    guard !value["actions"].array.isEmpty, case .array = value["inputs"] else { return value }
    var fields = value.object
    fields["inputs"] = .object([
      "omitted": .bool(true), "receiptID": .string(receiptID),
      "path": .array([.string("inputs")]),
      "notice": .string(
        "Visual control drafts are separate from named-action inputs. Use actions for app.run; map its typed fields to the current user request. An empty visual draft does not mean a chat value is missing. Use tool_result at this path only when you need to inspect or operate visual controls."
      ),
    ])
    // A short request can stay adjacent to the discovered contract. Never truncate
    // a longer request into apparent complete instructions; it remains in the user message.
    fields.removeValue(forKey: "currentUserRequest")
    if request.utf8.count <= 4096 {
      fields["currentUserRequest"] = .string(request)
    }
    return .object(fields)
  }
}
