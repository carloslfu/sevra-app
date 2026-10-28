import Foundation

extension WorkbookTools {
  /// Business objects are workbook-wide. Request Sources are conversation
  /// material: only this run's already-visible submission may use item reading.
  /// Earlier messages go through history_read and its exact inherited excerpt.
  func readableItem(_ identity: String) throws -> Item {
    let item = try workbook.item(identity)
    try require(
      item.isBusinessEvidence || (item.kind == "request" && item.id == requestSourceID),
      "item_scope",
      "This item is outside the business-evidence read scope. Inspect saved behavior with read_definition, not its technical authoring/invocation Source. Request Source IDs are not conversation-message IDs. Use history_read for a known accessible original message; if that original is outside scope, explain that it is unavailable. More history searches cannot grant access."
    )
    return item
  }

  func referenceEvidence(_ arguments: Value) throws -> Value {
    let allowed: Set<String> = [
      "id", "direction", "targetScope", "historicalOrigins", "contentScope", "kind", "meaning",
      "status", "scenario", "cursor",
    ]
    try require(
      Set(arguments.object.keys).isSubset(of: allowed), "arguments", "Unknown reference option.")
    for key in allowed.subtracting(["historicalOrigins"]) {
      try require(
        arguments[key] == .null || arguments[key].string != nil, "arguments",
        "Reference options must be text.")
    }
    if arguments["historicalOrigins"] != .null {
      guard case .bool = arguments["historicalOrigins"] else {
        throw SevraError("arguments", "Choose whether to include earlier origin versions.")
      }
    }
    guard let id = arguments["id"].string, !id.isEmpty,
      let direction = ReferenceDirection(rawValue: arguments["direction"].string ?? "outgoing"),
      let target = ReferenceTargetScope(rawValue: arguments["targetScope"].string ?? "logical"),
      let content = ReferenceContentScope(rawValue: arguments["contentScope"].string ?? "all")
    else { throw SevraError("arguments", "Choose an exact item and supported reference scope.") }
    var result = try workbook.referenceLinks(
      id, direction: direction, targetScope: target,
      historicalOrigins: arguments["historicalOrigins"] == .bool(true), contentScope: content,
      kind: arguments["kind"].string, meaning: arguments["meaning"].string,
      status: arguments["status"].string, scenario: arguments["scenario"].string,
      limit: 12, cursor: arguments["cursor"].string, cancellation: cancellation,
      businessOnly: true
    ).object
    // Names and foreign routes are not local lookup authority. A model can
    // search the visible label, but must not reinterpret a foreign target ID.
    result["hits"] = .array(
      result["hits"]!.array.map { hit in
        var fields = hit.object
        fields.removeValue(forKey: "lookup")
        return .object(fields)
      })
    result["accessScope"] = .string("workbook-business-items")
    result["notice"] = .string(
      "One hop over saved mentions, at most 12 results per page. Requests, annotations and technical definition/invocation Sources are excluded. Use history_search/history_read for accessible conversation. Read each exact destination or incoming origin before citing it; these titles and links are not inspected evidence. Keep all filters with nextCursor. Coverage describes this anchor only; no match is not proof of absence. A mention is not derivation, payment, support or corroboration. External workbooks are never opened."
    )
    return .object(result)
  }

  func scopedLineage(_ identity: String) throws -> Value {
    try workbook.synchronized(cancellation: cancellation) {
      try workbook.db.budget(cancellation: cancellation, seconds: 3) {
        try workbook.db.readTransaction {
          let item = try readableItem(identity)
          let rows = try workbook.db.execute(
            "SELECT l.* FROM lineage l JOIN items p ON p.id=l.parent JOIN items c ON c.id=l.child WHERE (l.child=? OR l.parent=?) AND p.kind NOT IN (\(Item.technicalKindSQL)) AND c.kind NOT IN (\(Item.technicalKindSQL)) ORDER BY l.child,l.parent LIMIT 200",
            [.string(item.id), .string(item.id)])
          return .array(rows.map(Value.object))
        }
      }
    }
  }
}
