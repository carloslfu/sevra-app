import Foundation
import SevraAI
import SevraCore
import SevraSplashGrammar

/// Evidence IDs come only from the workbook agent's inspected-result set.
/// Constrain references before generation; table/space IDs and IDs recalled
/// from earlier conversations do not become evidence merely by looking valid.
package enum NativeCitationPolicy {
  package static func make(_ citationIDs: [String], finishOnly: Bool = false) throws
    -> SplashToolPolicy
  {
    let ids = Array(Set(citationIDs)).sorted()
    try require(
      ids.count <= 256 && ids.allSatisfy { !$0.isEmpty && $0.utf8.count <= 128 },
      "context_limit",
      "This exploration has too many evidence references. Continue with a narrower question.")
    var tools =
      try JSONSerialization.jsonObject(
        with: NativeTools.serializedDefinitions(finishOnly: finishOnly)) as! [[String: Any]]
    guard
      let index = tools.firstIndex(where: {
        ($0["function"] as? [String: Any])?["name"] as? String == "finish"
      }),
      var function = tools[index]["function"] as? [String: Any],
      var parameters = function["parameters"] as? [String: Any],
      var properties = parameters["properties"] as? [String: Any],
      var citations = properties["citations"] as? [String: Any],
      var items = citations["items"] as? [String: Any]
    else { throw SevraError("tool_schema", "The workbook citation schema changed.") }
    citations["description"] =
      "Only inspected Source/Record versions or exact message:ID references from history_read. Message references support prior conversation, not current business facts. Never cite a space or table ID."
    if ids.isEmpty {
      citations["maxItems"] = 0
    } else {
      items["enum"] = ids
      citations["items"] = items
    }
    properties["citations"] = citations
    parameters["properties"] = properties
    function["parameters"] = parameters
    tools[index]["function"] = function
    return try SplashToolPolicy(
      toolsJSON: JSONSerialization.data(
        withJSONObject: tools,
        options: [.sortedKeys, .withoutEscapingSlashes]), choice: .required)
  }
}
