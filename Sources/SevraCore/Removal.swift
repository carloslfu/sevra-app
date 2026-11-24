import Foundation

/// One way to take a saved thing out of the workbook, and one way to bring it back.
///
/// Nothing is erased. Removing writes a `removal` marker Source, which keeps who removed what
/// and when, and the thing leaves every current list, search and the model's context. Restoring
/// writes the next version of that marker. What else a removal does depends on the thing:
///
/// - A document or record gets a new version with status rejected, so its effects stop, the
///   same as a withdrawn draft. Restoring saves its last version before the removal again.
/// - A table is archived. Restoring unarchives it.
/// - A view or an app is hidden. The app also loses this Mac's permission to run, in the app.
/// - A form, workflow, function, query, action, rule or automation is hidden and cannot start.
///   An automation is also paused, in the app.
/// - A saved tool is retired and disabled, as the Tools list does. Restoring brings back its
///   version before the removal and enables it again.
public struct RemovalTarget: Codable, Equatable, Sendable {
  /// item, table, view, app, definition or tool.
  public let type: String
  /// The identity that stays the same across versions: an item's logical ID, a table's or a
  /// view's ID, or a definition's logical ID.
  public let id: String
  public let title: String
  /// For a definition, its kind: form, workflow, function and so on.
  public let kind: String?
}

extension Workbook {
  static let removalKind = "removal"

  /// SQL that is true when the target named by `column` is removed now.
  static func removedSQL(_ column: String) -> String {
    "EXISTS(SELECT 1 FROM items r JOIN heads rh ON rh.item_id=r.id WHERE r.kind='removal' AND r.status='accepted' AND json_extract(r.data,'$.target')=\(column))"
  }

  /// The current marker for a target, removed or restored, if it was ever removed.
  func removalMarker(_ target: String) throws -> Item? {
    try db.execute(
      "SELECT r.* FROM items r JOIN heads h ON h.item_id=r.id WHERE r.kind='removal' AND json_extract(r.data,'$.target')=? LIMIT 1",
      [.string(target)]
    ).first.map(decodeItem)
  }

  public func isRemoved(_ target: String) throws -> Bool {
    try synchronized { try removalMarker(target)?.status == "accepted" }
  }

  /// What an ID names. A view and a table are found by their own IDs, a definition and an item
  /// by an exact version or their logical ID.
  public func removalTarget(_ id: String) throws -> RemovalTarget {
    let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
    try require(!id.isEmpty && id.utf8.count <= 512, "remove", "Which thing do you mean? Give its ID.")
    try require(
      id != "home", "remove", "Home cannot be removed. Change what it shows with view.edit instead.")
    return try synchronized {
      if let row = try db.execute("SELECT id,title,definition FROM spaces WHERE id=?", [.string(id)])
        .first
      {
        let app = (try? Value.parse(row["definition"]!.text))?["app"] ?? .null
        return .init(
          type: app == .null ? "view" : "app", id: id, title: row["title"]!.text, kind: nil)
      }
      if let row = try db.execute("SELECT id,title FROM datasets WHERE id=?", [.string(id)]).first {
        return .init(type: "table", id: id, title: row["title"]!.text, kind: nil)
      }
      if let saved = try? applicationDefinition(id) {
        return .init(
          type: saved.kind == "tool" ? "tool" : "definition", id: saved.logicalID,
          title: saved.title, kind: saved.kind)
      }
      if let found = try? item(id) {
        try require(
          found.category == "record" && !Item.hostOwnedKinds.contains(found.kind), "remove",
          found.kind == "row"
            ? "A table row is deleted with sql DELETE or table.change_rows, not removed."
            : found.category == "source"
              ? "Files and other Sources are evidence and stay in the workbook."
              : "This is a record the workbook keeps. Undo the change that made it instead.")
        return .init(type: "item", id: found.logicalID, title: found.title, kind: found.kind)
      }
      throw SevraError(
        "not_found", "Nothing saved has that ID. Search or read the list first for its exact ID.")
    }
  }

  /// Saves the next version of a target's marker in the current transaction.
  private func writeRemovalMarker(
    _ target: RemovalTarget, removed: Bool, version: String?, actor: ChangeActor
  ) throws -> String {
    var data: [String: Value] = [
      "target": .string(target.id), "type": .string(target.type), "title": .string(target.title),
    ]
    if let kind = target.kind { data["kind"] = .string(kind) }
    if let version { data["version"] = .string(version) }
    let marker = try insertItem(
      category: "source", kind: Self.removalKind,
      title: (removed ? "Removed " : "Restored ") + String(target.title.prefix(2000)),
      text: actor.label + (removed ? " removed “" : " restored “") + target.title + "”.",
      data: try decisionData(nil, additional: data), meaning: "actual",
      status: removed ? "accepted" : "rejected", scenario: "actual", inputs: [],
      transformation: removed ? "removal-v1" : "restoration-v1",
      supersedes: try removalMarker(target.id)?.id, inheritReferenceBindings: false,
      controlInputs: decisionInputs())
    // A marker is bookkeeping, not something to find by its words.
    try db.execute("UPDATE chunks SET is_current=0 WHERE item_id=?", [.string(marker)])
    return marker
  }

  /// Removes one thing. A person's decision: the chat asks them to confirm first.
  @discardableResult public func remove(
    _ id: String, token: String = identifier(), actor: ChangeActor
  ) throws -> Value {
    let target = try removalTarget(id)
    try require(
      try !isRemoved(target.id), "already_removed",
      "“" + target.title + "” is already removed. restore brings it back.")
    switch target.type {
    case "table":
      let table = try dataset(target.id)
      if !table.archived {
        _ = try updateDatasetDefinition(
          table.id, expectedVersion: table.version, expectedDefinitionID: table.definitionID,
          archived: true, token: token + ":table", actor: actor)
      }
    case "tool":
      let current = try applicationDefinition(target.id)
      if try !DefinitionTool(DefinitionDescriptor(current.content)).retired {
        _ = try retireTool(DefinitionTool(DefinitionDescriptor(current.content)).name, token: token + ":tool")
      }
    default: break
    }
    return try mutation(
      "remove", token: token, request: .object(["id": .string(target.id)]), actor: actor
    ) {
      try validateDecisionActor(actor)
      var version: String?
      if target.type == "item" {
        let current = try item(target.id)
        let next = try insertItem(
          category: current.category, kind: current.kind, title: current.title,
          text: current.text, data: current.data, meaning: current.meaning, status: "rejected",
          scenario: current.scenario, inputs: [current.id], transformation: "remove-v1",
          assetID: current.assetID, supersedes: current.id, referenceOrigin: current.id)
        try db.execute("UPDATE chunks SET is_current=0 WHERE item_id=?", [.string(next)])
        version = current.id
      } else if target.type == "tool" {
        // The version before retirement is the one to bring back.
        version = try applicationDefinition(target.id).previousID
      } else if target.type == "definition" {
        version = try applicationDefinition(target.id).id
      }
      let marker = try writeRemovalMarker(target, removed: true, version: version, actor: actor)
      return .object([
        "status": .string("removed"), "type": .string(target.type), "id": .string(target.id),
        "title": .string(target.title), "marker": .string(marker),
        "note": .string("History keeps it. restore with this id brings it back."),
      ])
    }
  }

  /// Brings back one removed thing. Restoring does not turn an app or an automation on again:
  /// the person enables it, as for any app or automation.
  @discardableResult public func restore(
    _ id: String, token: String = identifier(), actor: ChangeActor
  ) throws -> Value {
    let target = try removalTarget(id)
    let marker = try synchronized { try removalMarker(target.id) }
    let tool = target.type == "tool"
      ? try DefinitionTool(DefinitionDescriptor(applicationDefinition(target.id).content)) : nil
    try require(
      marker?.status == "accepted" || tool?.retired == true, "not_removed",
      "“" + target.title + "” is not removed.")
    switch target.type {
    case "table":
      let table = try dataset(target.id)
      if table.archived {
        _ = try updateDatasetDefinition(
          table.id, expectedVersion: table.version, expectedDefinitionID: table.definitionID,
          archived: false, token: token + ":table", actor: actor)
      }
    case "tool":
      let current = try applicationDefinition(target.id)
      var previous = marker?.status == "accepted" ? marker?.data["version"].string : nil
      if previous == nil { previous = current.previousID }
      guard let previous else {
        throw SevraError("restore", "This tool has no version before its removal.")
      }
      let restored = try restoreApplicationDefinition(
        current.logicalID, versionID: previous, expectedDefinitionID: current.id,
        token: token + ":tool", actor: actor)
      if try !DefinitionTool(DefinitionDescriptor(restored.content)).retired {
        try enableTool(restored.id)
      }
      if marker?.status != "accepted" {
        return .object([
          "status": .string("restored"), "type": .string("tool"), "id": .string(target.id),
          "title": .string(target.title),
        ])
      }
    default: break
    }
    return try mutation(
      "restore", token: token, request: .object(["id": .string(target.id)]), actor: actor
    ) {
      try validateDecisionActor(actor)
      if target.type == "item" {
        let current = try item(target.id)
        let prior = try item(marker!.data["version"].text)
        let next = try insertItem(
          category: prior.category, kind: prior.kind, title: prior.title, text: prior.text,
          data: prior.data, meaning: prior.meaning, status: prior.status,
          scenario: prior.scenario, inputs: [prior.id], transformation: "restore-v1",
          assetID: prior.assetID, supersedes: current.id, referenceOrigin: prior.id)
        try db.execute(
          "INSERT INTO effects SELECT occurrence,subject,kind,?,quantity,effective FROM effects WHERE item_id=?",
          [.string(next), .string(prior.id)])
      }
      _ = try writeRemovalMarker(target, removed: false, version: nil, actor: actor)
      var result: [String: Value] = [
        "status": .string("restored"), "type": .string(target.type), "id": .string(target.id),
        "title": .string(target.title),
      ]
      if target.type == "app" || target.kind == "automation" {
        result["note"] = .string("It is back, turned off. The person enables it to run it again.")
      }
      return .object(result)
    }
  }

  /// Everything removed now, newest first, with what restore needs.
  public func removedThings(limit: Int = 100) throws -> [Value] {
    try synchronized {
      var seen = Set<String>()
      var list: [Value] = try db.execute(
        "SELECT r.title,r.data,r.created FROM items r JOIN heads h ON h.item_id=r.id WHERE r.kind='removal' AND r.status='accepted' ORDER BY r.created DESC LIMIT ?",
        [.number(Double(min(max(limit, 1), 400)))]
      ).map { row in
        let data = try Value.parse(row["data"]!.text)
        seen.insert(data["target"].text)
        var entry: [String: Value] = [
          "id": data["target"], "type": data["type"], "title": data["title"],
          "removed": .string(row["created"]!.text),
        ]
        if data["kind"] != .null { entry["kind"] = data["kind"] }
        return .object(entry)
      }
      // A tool removed from the Tools list has no marker, and is just as removed.
      for tool in try savedTools(includeRetired: true) where !seen.contains(tool.logicalID) {
        let saved = try applicationDefinition(tool.definitionID)
        guard try DefinitionTool(DefinitionDescriptor(saved.content)).retired else { continue }
        list.append(
          .object([
            "id": .string(tool.logicalID), "type": .string("tool"), "title": .string(tool.name),
          ]))
      }
      return list
    }
  }
}
