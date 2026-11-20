import Foundation

extension Workbook {
  /// What else the workbook holds, by name, for the request's context: its views, its apps with
  /// the actions their checks found, and its other saved definitions. Tables and saved tools
  /// are listed beside it. Nothing here runs anything; an app's action runs only once the app
  /// is enabled on this Mac.
  public func chatWorkbookListing(byteLimit: Int = 1_600) throws -> String {
    var views: [String] = []
    var apps: [String] = []
    // Home is in every workbook, so it says nothing about this one.
    for space in try spaces() where space.id != "home" {
      if space.definition.app != nil {
        // An action's inputs are named fields, each with its type.
        let actions = space.definition.actions?.array.map { action -> String in
          action["id"].text + "("
            + action["inputs"].object.keys.sorted().map { name in
              name + (action["inputs"][name]["type"].string.map { " " + $0 } ?? "")
            }.joined(separator: ", ") + ")"
        } ?? []
        apps.append(
          space.title + " [" + space.id + "]"
            + (actions.isEmpty ? "" : ": " + actions.joined(separator: ", ")))
      } else {
        views.append(space.title + " [" + space.id + "]")
      }
    }
    let rows = try db.execute(
      "SELECT d.id,d.kind,d.title FROM app_definitions d JOIN app_definition_heads h ON h.definition_id=d.id WHERE d.kind<>'tool' ORDER BY d.kind,d.title LIMIT 40",
      maxRows: 40, maxBytes: 262_144)
    let definitions = rows.map {
      ($0["kind"]?.text ?? "") + " " + ($0["title"]?.text ?? "") + " [" + ($0["id"]?.text ?? "") + "]"
    }
    var lines: [String] = []
    var bytes = 0
    for (label, entries) in [
      ("Views", views), ("Apps, with their actions", apps), ("Saved definitions", definitions),
    ] where !entries.isEmpty {
      var line = label + ": "
      for (index, entry) in entries.enumerated() {
        let piece = (index == 0 ? "" : "; ") + entry
        guard bytes + line.utf8.count + piece.utf8.count <= byteLimit else { break }
        line += piece
      }
      bytes += line.utf8.count
      lines.append(line)
    }
    return lines.joined(separator: "\n")
  }
}
