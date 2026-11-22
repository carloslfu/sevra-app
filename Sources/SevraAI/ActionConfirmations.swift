import CryptoKit
import Foundation
import SevraCore

/// Success receipts establish storage/navigation outcomes, not semantic fidelity
/// of the generated content. Keep confirmation text within that boundary.
package struct ActionConfirmations {
  private var entries: [Value] = []
  private var inspectedApps = Set<String>()
  package init() {}
  package var evidence: Value { .array(entries) }
  private func recoveredFailure(_ entry: Value, at index: Int) -> Bool {
    guard entry["kind"].text == "failure" else { return false }
    // Refusing a repeat means the first save stands, so an earlier success settles it too.
    let later = entries.dropFirst(index + 1)
    return (entry["error"].text.contains(Self.repeatRefused) ? entries[...] : later).contains {
      saved in
      if entry["unavailableSelection"] != .null,
        saved["appVersion"] == entry["appVersion"],
        saved["resolvedAppTarget"] == entry["resolvedAppTarget"],
        saved["updatedRows"].array.contains(entry["unavailableSelection"])
      {
        // A supported named action updated the same record after a selection
        // that never dispatched. The original refusal remains in tool history.
        return true
      }
      if let missing = entry["missingAppTarget"].string {
        // Only settle a demonstrated copying error from a known inspection.
        // This never resolves another target or authorizes a worker invocation.
        guard let actual = saved["resolvedAppTarget"].string,
          inspectedApps.contains(actual), entry["routedAction"] != .null,
          entry["routedAction"] == saved["routedAction"]
        else { return false }
        return inspectedApps.filter { Self.isCopiedID(missing, of: $0) } == [actual]
      }
      if entry["validationOnly"] == .bool(true), entry["envelopeRepair"] != .null {
        let repair = entry["envelopeRepair"]
        let removable = Set(repair["removableFields"].array.map(\.text))
        return saved["tool"] == entry["tool"] && saved["appTarget"] == repair["target"]
          && (saved["kind"].text != "failure" || saved["validationOnly"] == .bool(false))
          && repair["inputs"].object.allSatisfy { key, digest in
            let later = saved["inputDigests"][key]
            // A misplaced selector may disappear only when the pre-invocation
            // SDK contract proves it is not a business input with the same name.
            return later == digest
              || (later == .null && removable.contains(key)
                && saved["excludedEnvelopeInputs"].array.contains(.string(key)))
          }
      }
      // A one-level misplaced envelope can omit the outer app ID entirely. Match
      // only an unambiguous exact invocation, including its version and inputs.
      // This repairs reporting; it never repairs or executes the refused call.
      if entry["validationOnly"] == .bool(true),
        !entry["invocation"].text.isEmpty, saved["invocation"] == entry["invocation"],
        saved["tool"] == entry["tool"],
        saved["kind"].text != "failure" || saved["validationOnly"] == .bool(false)
      {
        return true
      }
      if entry["nestedAppEnvelope"] == .bool(true) { return false }
      // A corrected outer envelope must preserve every supplied business input.
      // Adding its missing version must not settle a different transaction.
      if entry["validationOnly"] == .bool(true), entry["appRun"] == .bool(true),
        !entry["inputDigests"].object.allSatisfy({ saved["inputDigests"][$0.key] == $0.value })
      {
        return false
      }
      if entry["inputRepair"] != .null, saved["tool"] == entry["tool"],
        saved["retryGroup"] == entry["retryGroup"], saved["inputRepair"] == .null,
        saved["kind"].text != "failure" || saved["validationOnly"] == .bool(false),
        entry["inputRepair"].object.allSatisfy({ saved["inputDigests"][$0.key] == $0.value })
      {
        return true
      }
      // A call refused before its handler, such as one that named the id under another
      // field, is settled once the same action reaches its handler for a value it carried.
      if entry["tool"].text == "workspace_action", entry["validationOnly"] == .bool(true),
        saved["tool"] == entry["tool"], saved["kind"].text != "failure",
        let action = saved["action"].string, action == entry["action"].string,
        let target = saved["inputID"].string, !target.isEmpty,
        entry["argumentValues"].array.contains(.string(target))
      {
        return true
      }
      // Once the same operation reaches its business handler, an earlier malformed
      // envelope is no longer the current failure. Preserve the handler's refusal
      // and both receipts, without claiming that the action succeeded.
      if entry["tool"].text == "workspace_action", saved["tool"] == entry["tool"],
        entry["validationOnly"] == .bool(true), saved["validationOnly"] == .bool(false),
        saved["retryGroup"] == entry["retryGroup"]
      {
        return true
      }
      if saved["tool"] == entry["tool"] && saved["kind"].text != "failure"
        && (saved["attempt"] == entry["attempt"]
          || (entry["validationOnly"] == .bool(true)
            && saved["retryGroup"] == entry["retryGroup"]))
      {
        return true
      }
      // A model can first choose the fixed-layout tool for a programmable app, or
      // repair an incorrect ID using its exact name. A later checked save settles
      // only those same-app edits. A failed snapshot/restore remains a different action.
      guard saved["kind"].text == "native_app",
        ["save_space", "edit_space", "save_native_app"].contains(entry["tool"].text)
      else { return false }
      return [entry["attempt"].text, entry["appName"].text].contains { target in
        !target.isEmpty
          && (target == saved["targetID"].text
            || target.caseInsensitiveCompare(saved["title"].text) == .orderedSame)
      }
    }
  }
  /// What a call acted on, so a later success can settle the failure before it.
  private static func attempt(_ tool: String, _ arguments: Value) -> String {
    if tool == "workspace_action" {
      let inputs = arguments["arguments"]
      if arguments["action"].text == "app.run",
        (try? ChatOperations.validate("app.run", arguments: inputs, readOnly: false)) != nil,
        let json = try? Value.array([inputs["id"], inputs["action"], inputs["inputs"]]).json()
      {
        // Refreshing a stale version can retry the same business request. A
        // different payload is a different transaction, even on the same action.
        return "app.run:" + digest(json)
      }
      if arguments["action"] == .string("app.select"),
        let json = try? Value.array([inputs["id"], inputs["target"], inputs["rowID"]]).json()
      {
        return "app.select:" + digest(json)
      }
      return arguments["action"].text + ":" + inputs["id"].text + ":"
        + inputs["action"].text + ":" + inputs["target"].text + ":"
        + inputs["inputs"]["name"].text
    }
    if tool == "save_native_app" {
      return arguments["id"].string ?? arguments["package"]["name"].text
    }
    return arguments["content"]["title"].string
      ?? ["id", "title", "target", "subject", "datasetID", "templateReceiptID"].lazy
      .compactMap { arguments[$0].string }.first ?? ""
  }
  private static func retryGroup(_ arguments: Value) -> String {
    let inputs = arguments["arguments"]
    return arguments["action"].text + ":" + inputs["id"].text + ":"
      + inputs["action"].text + ":" + inputs["target"].text + ":" + inputs["rowID"].text
  }
  private static let envelopeSelectors = ["id", "expectedVersion", "action"]

  private static func invocation(_ tool: String, _ arguments: Value) -> Value {
    guard tool == "workspace_action", arguments["action"].text == "app.run" else { return .null }
    let outer = arguments["arguments"].object
    let envelopeKeys = Self.envelopeSelectors + ["inputs"]
    guard Set(outer.keys).isSubset(of: Set(envelopeKeys + ["arguments"])) else { return .null }
    let nested: [String: Value]
    switch outer["arguments"] {
    case nil: nested = [:]
    case .object(let fields): nested = fields
    default: return .null
    }
    var fields: [String: Value] = [:]
    for key in envelopeKeys {
      if let a = outer[key], let b = nested[key], a != b { return .null }
      fields[key] = outer[key] ?? nested[key]
    }
    let value = Value.object(fields)
    guard (try? ChatOperations.validate("app.run", arguments: value, readOnly: false)) != nil,
      nested.allSatisfy({
        envelopeKeys.contains($0.key) || value["inputs"].object[$0.key] == $0.value
      }),
      let json = try? value.json()
    else { return .null }
    return .string(digest(json))
  }
  private static func isCopiedID(_ supplied: String, of actual: String) -> Bool {
    guard UUID(uuidString: actual) != nil, supplied.utf8.count <= 36 else { return false }
    let exact = actual.lowercased()
    let value = supplied.lowercased()
    let groups = exact.split(separator: "-")
    // A local model may drop one whole UUID group, or miscopy one hex digit.
    if groups.indices.dropFirst().dropLast().contains(where: { removed in
      groups.indices.filter { $0 != removed }.map { groups[$0] }.joined(separator: "-") == value
    }) {
      return true
    }
    return UUID(uuidString: value) != nil
      && zip(value.utf8, exact.utf8).filter { $0 != $1 }.count == 1
  }

  private static func routedAction(_ tool: String, _ arguments: Value) -> Value {
    let call = arguments["arguments"]
    guard tool == "workspace_action", arguments["action"] == .string("app.run"),
      (try? ChatOperations.validate("app.run", arguments: call, readOnly: false)) != nil,
      let json = try? Value.array([call["expectedVersion"], call["action"], call["inputs"]]).json()
    else { return .null }
    return .string(digest(json))
  }

  private static func appTarget(_ tool: String, _ arguments: Value) -> Value {
    let call = arguments["arguments"]
    guard tool == "workspace_action", arguments["action"] == .string("app.run"),
      (try? ChatOperations.validate("app.run", arguments: call, readOnly: false)) != nil,
      let json = try? Value.array([call["id"], call["expectedVersion"], call["action"]]).json()
    else { return .null }
    return .string(digest(json))
  }
  /// Describe two unambiguous formatting repairs for outcome reporting only.
  /// Never dispatch a rewritten call or discard a supplied business value.
  private static func envelopeRepair(_ tool: String, _ arguments: Value) -> Value {
    guard tool == "workspace_action", arguments["action"] == .string("app.run") else {
      return .null
    }
    var fields = arguments["arguments"].object
    let supplied: [String: Value]
    let removable: [String]
    if Set(fields.keys) == ["id", "expectedVersion", "inputs"],
      case .object(var inputs) = fields["inputs"], let action = inputs["action"]?.string,
      !action.isEmpty
    {
      supplied = inputs
      fields["action"] = .string(action)
      inputs.removeValue(forKey: "action")
      fields["inputs"] = .object(inputs)
      removable = ["action"]
    } else if Set(fields.keys) == ["id", "expectedVersion", "action", "arguments"],
      case .object(let inputs) = fields["arguments"]
    {
      // An inner object named inputs belongs to the nested-envelope check.
      if case .object = inputs["inputs"] { return .null }
      supplied = inputs
      // Identical duplicates can be routing noise. A conflicting value is
      // business data unless the corrected invocation preserves it exactly.
      removable = Self.envelopeSelectors.filter { inputs[$0] == fields[$0] }
      fields.removeValue(forKey: "arguments")
      fields["inputs"] = .object(inputs)
    } else {
      return .null
    }
    let target = appTarget(
      tool,
      .object([
        "action": .string("app.run"), "arguments": .object(fields),
      ]))
    guard target != .null else { return .null }
    return .object([
      "target": target, "inputs": inputDigests(.object(supplied)),
      "removableFields": .array(removable.map(Value.string)),
    ])
  }
  private static func excludedEnvelopeInputs(_ result: Value) -> Value {
    guard case .object(let fields) = result["invocationInputContract"] else { return .null }
    return .array(Self.envelopeSelectors.filter { fields[$0] == nil }.map(Value.string))
  }
  private static func digest(_ json: String) -> String {
    SHA256.hash(data: Data(json.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  /// A missing/mistyped declared input never reaches the SDK's business handler.
  /// Inspect structured host evidence, not words chosen by the app's error message.
  private static func repairableInputs(_ arguments: Value, _ result: Value) -> Value {
    guard arguments["action"].text == "app.run", result["changes"].array.isEmpty else {
      return .null
    }
    let call = arguments["arguments"]
    guard case .object(let fields) = result["invocationInputContract"],
      case .object(let inputs) = call["inputs"]
    else { return .null }
    var invalid = !Set(inputs.keys).isSubset(of: Set(fields.keys))
    var preserved: [String: Value] = [:]
    for (key, field) in fields {
      guard let value = inputs[key] else {
        if field["required"] != .bool(false) { invalid = true }
        continue
      }
      switch (field["valueType"].text, value) {
      case ("string", .string), ("boolean", .bool): break
      case ("number", .number(let number)) where number.isFinite: break
      case ("string", _), ("boolean", _), ("number", _):
        invalid = true
        continue
      default: return .null
      }
      if field["required"] != .bool(false), ["text", "record"].contains(field["type"].text),
        value.text.unicodeScalars.allSatisfy({ Self.sdkWhitespace.contains($0) })
      {
        invalid = true
        continue
      }
      preserved[key] = value
    }
    return invalid ? inputDigests(.object(preserved)) : .null
  }
  // Match ECMAScript String.trim, not Foundation's broader whitespace set:
  // U+0085, for example, is a valid nonblank SDK value and must be preserved.
  private static let sdkWhitespace = CharacterSet(
    charactersIn:
      "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}"
  )
  private static func inputDigests(_ inputs: Value) -> Value {
    .object(
      inputs.object.mapValues { value in
        (try? value.json()).map { .string(digest($0)) } ?? .null
      })
  }
  /// What the host says to the model after a repeat, never to the person.
  private static let repeatRefused = " Do not save it again."
  package var hasUnresolvedFailure: Bool {
    entries.enumerated().contains {
      $0.element["kind"].text == "failure" && !recoveredFailure($0.element, at: $0.offset)
    }
  }

  package mutating func recordFailure(
    tool: String, arguments: Value, result: Value, receiptID: String,
    appTargetNotFound: Bool = false
  ) {
    let task: String
    switch tool {
    case "workspace_action":
      // Discovery/lookup failures carry no mutation outcome, just like other
      // read-only tools. Keep them in tool history without masking a later save.
      guard
        let operation = ChatOperations.operations.first(where: {
          $0.name == arguments["action"].text
        }),
        !operation.readOnly
      else { return }
      task = "that action"
    case "draft": task = "saving the draft"
    case "save_definition", "save_template": task = "saving reusable behavior"
    case "start_workflow": task = "queueing the workflow"
    case "save_space", "edit_space", "restore_space", "pin_space", "save_native_app":
      task = "saving the space"
    case "set_space_pinned": task = "changing the shortcut"
    case "open_space", "open_reviews", "open_automation": task = "opening the view"
    case "propose_movement", "propose_record", "publish_result", "prepare_action":
      task = "preparing the proposal"
    case "include_archive_members": task = "including the archive files"
    case "prepare_workflow_answer": task = "preparing the answer"
    default:
      guard !WorkbookTools.readOnlyTools.contains(tool) else { return }
      task = "that action"
    }
    entries.append(
      .object([
        "receiptID": .string(receiptID), "tool": .string(tool), "kind": .string("failure"),
        "targetID": .string(receiptID), "title": .string(task),
        "error": result["error"] == .null
          ? .string(result["errors"].array.map(\.text).joined(separator: " ")) : result["error"],
        "attempt": .string(Self.attempt(tool, arguments)),
        "retryGroup": .string(Self.retryGroup(arguments)),
        "invocation": Self.invocation(tool, arguments),
        "appTarget": Self.appTarget(tool, arguments),
        "routedAction": Self.routedAction(tool, arguments),
        "missingAppTarget": appTargetNotFound ? arguments["arguments"]["id"] : .null,
        "resolvedAppTarget": result["outcome"] == .string("failed") ? result["id"] : .null,
        "appVersion": result["version"],
        "unavailableSelection": tool == "workspace_action"
          && arguments["action"] == .string("app.select") && result["id"].string != nil
          && result["version"].int != nil && result["outcome"] == .string("failed")
          && result["changes"] == .array([])
          ? result["unavailableSelection"] : .null,
        "envelopeRepair": Self.envelopeRepair(tool, arguments),
        "excludedEnvelopeInputs": Self.excludedEnvelopeInputs(result),
        "inputRepair": Self.repairableInputs(arguments, result),
        "inputDigests": Self.inputDigests(arguments["arguments"]["inputs"]),
        "appRun": .bool(tool == "workspace_action" && arguments["action"].text == "app.run"),
        "nestedAppEnvelope": .bool(
          tool == "workspace_action" && arguments["action"].text == "app.run"
            && arguments["arguments"]["arguments"] != .null),
        "validationOnly": .bool(
          tool == "workspace_action"
            && (try? ChatOperations.validate(
              arguments["action"].text, arguments: arguments["arguments"], readOnly: false)) == nil
        ),
        "appName": .string(tool == "save_native_app" ? arguments["package"]["name"].text : ""),
        "action": tool == "workspace_action" ? arguments["action"] : .null,
        "argumentValues": .array(
          tool == "workspace_action"
            ? arguments["arguments"].object.keys.sorted().prefix(16).compactMap {
              arguments["arguments"][$0].string.map(Value.string)
            } : []),
      ]))
  }

  package mutating func record(tool: String, arguments: Value, result: Value, receiptID: String) {
    let attempt = Self.attempt(tool, arguments)
    let kind: String
    let id: String
    let title: String
    var qualifier = ""
    switch tool {
    case "workspace_action":
      if arguments["action"] == .string("app.inspect"), let id = result["id"].string {
        inspectedApps.insert(id)
      }
      if result["status"] == .string("confirmation_required") {
        kind = "chat_approval"
      } else if result["status"] == .string("cancelled"), result["note"].string != nil,
        ChatOperations.operations.first(where: { $0.name == arguments["action"].text })?.host
          == true
      {
        // The person closed what the host asked them, such as a save panel. The host's note
        // says what did not happen, so the answer cannot claim it did.
        kind = "cancelled"
      } else {
        guard
          ChatOperations.operations.first(where: { $0.name == arguments["action"].text })?.readOnly
            == false
        else { return }
        // Recovery evidence only. The model describes arbitrary business results
        // from the structured receipt; a generic host success label cannot do that.
        kind = "workspace_completion"
      }
      id = receiptID
      title = kind == "cancelled" ? result["note"].text : result["preview"].text
    case "save_definition", "save_template":
      guard let value = result["id"].string, let name = result["title"].string else { return }
      kind = "definition"
      id = value
      title = name
    case "draft":
      guard let value = result["id"].string, result["status"].text == "draft" else { return }
      kind = "draft"
      id = value
      title = result["title"].text
    case "save_native_app":
      guard let value = result["spaceID"].string else { return }
      kind = "native_app"
      id = value
      title = result["title"].text
      qualifier = String(result["check"]["assertions"].int ?? 0)
    case "save_space", "edit_space", "restore_space", "pin_space":
      guard let value = result["spaceID"].string ?? result.string else { return }
      kind =
        tool == "pin_space"
        ? "snapshot"
        : tool == "edit_space"
          ? "space_edit"
          : tool == "restore_space" ? "space_restore" : "space"
      id = value
      title = result["title"].string ?? arguments["title"].text
    case "set_space_pinned":
      guard let value = result["spaceID"].string, case .bool(let pinned) = result["pinned"]
      else { return }
      kind = "shortcut"
      id = value
      title = result["title"].text
      qualifier = pinned ? "pinned" : id == "home" ? "permanent" : "unpinned"
    case "open_space", "open_reviews":
      guard result["status"].text == "opened" else { return }
      kind = "opened"
      id = result["spaceID"].string ?? "review-queue"
      title = result["title"].text
    default:
      // Nothing here to confirm, but a retry that worked settles the failure before it.
      guard
        entries.contains(where: {
          $0["kind"].text == "failure" && $0["tool"].text == tool && $0["attempt"].text == attempt
        })
      else { return }
      kind = "settled"
      id = receiptID
      title = ""
    }
    entries.append(
      .object([
        "receiptID": .string(receiptID), "tool": .string(tool), "kind": .string(kind),
        "targetID": .string(id), "title": .string(title), "qualifier": .string(qualifier),
        "attempt": .string(attempt),
        "retryGroup": .string(Self.retryGroup(arguments)),
        "invocation": Self.invocation(tool, arguments),
        "appTarget": Self.appTarget(tool, arguments),
        "routedAction": Self.routedAction(tool, arguments),
        "resolvedAppTarget": result["outcome"] == .string("completed") ? result["id"] : .null,
        "appVersion": result["version"],
        "updatedRows": tool == "workspace_action" && arguments["action"] == .string("app.run")
          && result["outcome"] == .string("completed") && !result["changes"].array.isEmpty
          ? result["updatedRows"] : .null,
        "excludedEnvelopeInputs": Self.excludedEnvelopeInputs(result),
        "inputDigests": Self.inputDigests(arguments["arguments"]["inputs"]),
        "action": tool == "workspace_action" ? arguments["action"] : .null,
        "inputID": tool == "workspace_action" ? arguments["arguments"]["id"] : .null,
      ]))
  }

  package var rendered: String? { rendered(excluding: nil) }
  /// A receipt that already speaks for one call leaves that call out of the list.
  package func rendered(excluding receiptID: String?) -> String? {
    var seen = Set<String>()
    let lines = entries.enumerated().compactMap { index, entry -> String? in
      let kind = entry["kind"].text
      if recoveredFailure(entry, at: index) || entry["receiptID"].string == receiptID { return nil }
      let id = entry["targetID"].text
      let qualifier = entry["qualifier"].text
      guard seen.insert(kind + ":" + id + ":" + qualifier).inserted else { return nil }
      let title = entry["title"].text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
      switch kind {
      case "chat_approval":
        return title + "\nType **Confirm** to apply this change. Nothing has been applied yet."
      case "definition":
        return "Saved reusable behavior “" + title
          + "”. Business acceptance is separate."
      case "failure":
        let reason = entry["error"].text.components(separatedBy: Self.repeatRefused)[0]
        return "Couldn’t finish " + title + ". " + reason
      case "draft": return "Saved draft [" + title + "](sevra://item/" + id + ")."
      case "native_app":
        return "Saved native app “" + title + "” after " + qualifier
          + (qualifier == "1" ? " synthetic check." : " synthetic checks.")
          + " Review table access and enable this version to use it."
      case "space": return "Saved space “" + title + "”."
      case "space_edit": return "Updated space “" + title + "”."
      case "space_restore": return "Restored a saved layout for “" + title + "”."
      case "snapshot": return "Saved snapshot “" + title + "”."
      case "shortcut":
        if qualifier == "permanent" { return "Home already has a permanent shortcut." }
        return qualifier == "pinned"
          ? "Pinned the shortcut for “" + title + "”."
          : "Removed the shortcut for “" + title + "”."
      case "opened": return "Opened “" + title + "”."
      case "cancelled": return title
      default: return nil
      }
    }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }
}
