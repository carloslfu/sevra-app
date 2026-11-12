import Foundation

extension Workbook {
  /// Human-authored reading aid for one exact file version, never inferred from OCR.
  public func imageDescription(_ id: String, cancellation: Cancellation = .init()) throws -> Value {
    try synchronized(cancellation: cancellation) {
      try db.budget(cancellation: cancellation, seconds: 3) {
        try db.readTransaction {
          let original = try item(id)
          try require(
            original.id == id && original.assetID != nil, "description_source",
            "Choose an exact file version.")
          let rows = try db.execute(
            """
            SELECT i.id,i.body FROM items i JOIN heads h ON h.item_id=i.id
            JOIN lineage l ON l.child=i.id AND l.parent=?
            WHERE i.category='source' AND i.kind='annotation'
              AND json_extract(i.data,'$.purpose')='image-description'
              AND json_extract(i.data,'$.imageVersionID')=?
            GROUP BY i.id LIMIT 2
            """, [.string(id), .string(id)])
          try require(
            rows.count <= 1, "description_conflict",
            "Multiple descriptions need review before another is saved.")
          return .object([
            "id": rows.first?["id"] ?? .null, "body": rows.first?["body"] ?? .string(""),
            "revision": .number(Double(try revision())),
          ])
        }
      }
    }
  }

  public func saveImageDescription(
    _ id: String, text: String, previousID: String?, expectedRevision: Int, token: String
  ) throws -> Item {
    try synchronized {
      try require(
        text.utf8.count <= 8_000, "description_length",
        "Keep the description within 8,000 UTF-8 bytes.")
      let current = try imageDescription(id)
      // A committed operation may be replayed after its response was lost. addItem
      // still validates the complete saved request before returning that receipt.
      let replaying =
        try db.scalar("SELECT EXISTS(SELECT 1 FROM operations WHERE id=?)", [.string(token)]).int
        == 1
      try require(
        replaying || current["id"].string == previousID, "description_changed",
        "The description changed. Reload before saving.")
      return try addItem(
        category: "source", kind: "annotation", title: "User image description",
        text: text,
        data: .object(["purpose": .string("image-description"), "imageVersionID": .string(id)]),
        status: "accepted", inputs: [id],
        transformation: "human image description; not OCR or verified evidence",
        supersedes: previousID, token: token, expectedRevision: expectedRevision)
    }
  }
}
