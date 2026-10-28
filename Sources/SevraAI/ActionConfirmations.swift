import Foundation
import SevraCore

/// Success receipts establish storage/navigation outcomes, not semantic fidelity
/// of the generated content. Keep confirmation text within that boundary.
package struct ActionConfirmations {
  private var entries: [Value] = []
  package var evidence: Value { .array(entries) }

  package mutating func recordFailure(
    tool: String, arguments: Value, result: Value, receiptID: String
  ) {
    let task: String
    switch tool {
    case "draft": task = "saving the draft"
    case "save_definition", "save_template": task = "saving reusable behavior"
    case "save_space", "edit_space", "restore_space", "pin_space": task = "saving the space"
    case "set_space_pinned": task = "changing the shortcut"
    case "open_space", "open_reviews": task = "opening the view"
    default: return
    }
    let attemptedTitle =
      arguments["content"]["title"].string.map(Value.string) ?? arguments["title"]
    entries.append(
      .object([
        "receiptID": .string(receiptID), "tool": .string(tool), "kind": .string("failure"),
        "targetID": .string(receiptID), "title": .string(task), "error": result["error"],
        "attemptedTitle": attemptedTitle,
      ]))
  }

  package mutating func record(tool: String, arguments: Value, result: Value, receiptID: String) {
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
    default: return
    }
    entries.append(
      .object([
        "receiptID": .string(receiptID), "tool": .string(tool), "kind": .string(kind),
        "targetID": .string(id), "title": .string(title), "qualifier": .string(qualifier),
      ]))
  }

  package var rendered: String? {
    guard !entries.isEmpty else { return nil }
    var seen = Set<String>()
    let lines = entries.enumerated().compactMap { index, entry -> String? in
      let kind = entry["kind"].text
      if kind == "failure", let attemptedTitle = entry["attemptedTitle"].string,
        !attemptedTitle.isEmpty,
        entries.dropFirst(index + 1).contains(where: {
          $0["tool"] == entry["tool"] && $0["kind"].text != "failure"
            && $0["title"].text == attemptedTitle
        })
      {
        return nil
      }
      let id = entry["targetID"].text
      let qualifier = entry["qualifier"].text
      guard seen.insert(kind + ":" + id + ":" + qualifier).inserted else { return nil }
      let title = entry["title"].text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
      switch kind {
      case "definition":
        return "Saved reusable behavior “" + title
          + "”. Business acceptance is separate."
      case "failure": return "Couldn’t finish " + title + ". " + entry["error"].text
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
    return lines.joined(separator: "\n")
  }
}
