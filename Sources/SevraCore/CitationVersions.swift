import Foundation

extension Workbook {
  /// Preserve exact citation identities while observing their heads in one read
  /// transaction. This does not retarget a citation or confer action authority.
  public func citationVersions(_ ids: [String], cancellation: Cancellation = .init()) throws
    -> Value
  {
    try require(ids.count <= 256, "citation_limit", "Too many cited versions.")
    return try synchronized(cancellation: cancellation) {
      try db.readTransaction {
        func metadata(_ row: [String: Value], _ prefix: String) throws -> Value {
          try require(
            (row[prefix + "version"]?.int ?? 0) > 0
              && ["draft", "accepted", "rejected"].contains(row[prefix + "status"]?.text ?? ""),
            "integrity", "Invalid record metadata.")
          return .object([
            "id": row[prefix + "id"]!, "logicalID": row["logical_id"]!,
            "version": row[prefix + "version"]!, "title": row[prefix + "title"]!,
            "status": row[prefix + "status"]!, "meaning": row[prefix + "meaning"]!,
          ])
        }
        let versions = try Set(ids).sorted().map { id -> Value in
          try cancellation.check()
          // Citation checking must not decode potentially large document bodies
          // or structured payloads merely to inspect a version's status.
          guard
            let row = try db.execute(
              "SELECT c.id AS cited_id,c.logical_id,c.version AS cited_version,c.title AS cited_title,c.status AS cited_status,c.meaning AS cited_meaning,n.id AS current_id,n.version AS current_version,n.title AS current_title,n.status AS current_status,n.meaning AS current_meaning FROM items c JOIN heads h ON h.logical_id=c.logical_id JOIN items n ON n.id=h.item_id WHERE c.id=?",
              [.string(id)]
            ).first
          else {
            throw SevraError("citation_version", "Cite an existing exact item version.")
          }
          return .object([
            "cited": try metadata(row, "cited_"), "current": try metadata(row, "current_"),
            "isCurrentVersion": .bool(row["cited_id"] == row["current_id"]),
          ])
        }
        return .object([
          "snapshotRevision": .number(Double(try revision())), "versions": .array(versions),
        ])
      }
    }
  }
}
