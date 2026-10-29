import SevraCore

/// Describes the dispatched tool, not the model's claimed intent or conclusion.
enum ToolActivityLabel {
  static func title(_ tool: String, arguments: Value) -> String {
    switch tool {
    case "search", "history_search":
      return "Searching for “\(arguments["query"].text.prefix(160))”…"
    case "read": return "Reading an original…"
    case "history_read": return "Reading earlier conversation…"
    case "datasets": return "Inspecting tables…"
    case "rows": return "Reading table rows…"
    case "calculate": return "Calculating…"
    case "compare_rows": return "Comparing table rows…"
    case "save_space": return "Saving a space…"
    case "edit_space": return "Updating a space…"
    case "references": return "Following references…"
    default: return tool.replacingOccurrences(of: "_", with: " ").capitalized + "…"
    }
  }
}
