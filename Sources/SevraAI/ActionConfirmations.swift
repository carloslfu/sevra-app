import Foundation
import SevraCore

/// Success receipts establish storage/navigation outcomes, not semantic fidelity
/// of the generated content. Keep confirmation text within that boundary.
package struct ActionConfirmations {
  private var entries: [Value] = []
  package init() {}
  package var evidence: Value { .array(entries) }
  private func recoveredFailure(_ entry: Value, at index: Int) -> Bool {
    guard entry["kind"].text == "failure" else { return false }
    // Refusing a repeat means the first save stands, so an earlier success settles it too.
    let later = entries.dropFirst(index + 1)
    return (entry["error"].text.contains(Self.repeatRefused) ? entries[...] : later).contains {
      $0["tool"] == entry["tool"] && $0["kind"].text != "failure"
        && $0["attempt"] == entry["attempt"]
    }
  }
  /// What a call acted on, so a later success can settle the failure before it. A thread tool
  /// acts on the current conversation whatever its arguments say.
  private static func attempt(_ tool: String, _ arguments: Value) -> String {
    if WorkbookTools.conversationTools[tool] != nil { return "" }
    return arguments["content"]["title"].string
      ?? ["id", "title", "target", "subject", "datasetID", "templateReceiptID"].lazy
      .compactMap { arguments[$0].string }.first ?? ""
  }
  /// What the host says to the model after a repeat, never to the person.
  private static let repeatRefused = " Do not save it again."
  package var hasUnresolvedFailure: Bool {
    entries.enumerated().contains {
      $0.element["kind"].text == "failure" && !recoveredFailure($0.element, at: $0.offset)
    }
  }

  package mutating func recordFailure(
    tool: String, arguments: Value, result: Value, receiptID: String
  ) {
    let task: String
    switch tool {
    case "draft": task = "saving the draft"
    case "save_definition", "save_template": task = "saving reusable behavior"
    case "start_workflow": task = "queueing the workflow"
    case "save_space", "edit_space", "restore_space", "pin_space": task = "saving the space"
    case "set_space_pinned": task = "changing the shortcut"
    case "open_space", "open_reviews", "open_automation": task = "opening the view"
    case "propose_table", "propose_table_edit", "propose_movement", "propose_record",
      "publish_result", "prepare_action":
      task = "preparing the proposal"
    case "include_archive_members": task = "including the archive files"
    case "prepare_workflow_answer": task = "preparing the answer"
    case "conversation_action", _ where WorkbookTools.conversationTools[tool] != nil:
      task = "changing the thread"
    default:
      guard !WorkbookTools.readOnlyTools.contains(tool) else { return }
      task = "that action"
    }
    entries.append(
      .object([
        "receiptID": .string(receiptID), "tool": .string(tool), "kind": .string("failure"),
        "targetID": .string(receiptID), "title": .string(task), "error": result["error"],
        "attempt": .string(Self.attempt(tool, arguments)),
      ]))
  }

  package mutating func record(tool: String, arguments: Value, result: Value, receiptID: String) {
    let attempt = Self.attempt(tool, arguments)
    let kind: String
    let id: String
    let title: String
    var qualifier = ""
    switch tool {
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
      case "definition":
        return "Saved reusable behavior “" + title
          + "”. Business acceptance is separate."
      case "failure":
        // What refuses a thread change speaks to the model, not to the person.
        if title == "changing the thread" { return "Couldn’t finish changing the thread." }
        let reason = entry["error"].text.components(separatedBy: Self.repeatRefused)[0]
        return "Couldn’t finish " + title + ". " + reason
      case "draft": return "Saved draft [" + title + "](sevra://item/" + id + ")."
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
      default: return nil
      }
    }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }
}
