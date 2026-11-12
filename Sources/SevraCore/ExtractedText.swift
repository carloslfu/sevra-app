import Foundation

extension Workbook {
  /// One bounded page from an exact asset version and a single database revision.
  /// Any intervening write refuses further paging rather than mixing extractions.
  public func extractedTextPage(
    _ id: String, offset: Int = 0, expectedRevision: Int? = nil,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try synchronized(cancellation: cancellation) {
      try db.budget(cancellation: cancellation, seconds: 3) {
        try db.readTransaction {
          try cancellation.check()
          let item = try self.item(id)
          try require(
            item.id == id && item.assetID != nil, "extracted_text", "Open an exact file version.")
          let revision = try self.revision()
          try require(
            expectedRevision == nil || expectedRevision == revision, "extracted_text_changed",
            "The workbook changed. Reload extracted text before reading another page.")
          try require(offset >= 0 && offset <= 1_000_000, "extracted_text", "Invalid text page.")
          let asset = try self.asset(item.assetID!)
          let status = try extractionStatus(id)
          let extractionID = try db.scalar(
            "SELECT s.input_id FROM file_reference_heads h JOIN file_reference_sets s ON s.id=h.set_id WHERE h.origin_id=?",
            [.string(id)])
          // Import, failed and unsupported indexes can contain discovery metadata, not extracted text.
          // Read a bounded byte prefix: SQLite text substr/length stop at an embedded NUL.
          let readable =
            extractionID.string != nil && ["ready", "partial"].contains(status["state"].text)
          let rows =
            !readable
            ? []
            : try db.execute(
              "SELECT id,CAST(substr(CAST(body AS BLOB),1,16000) AS TEXT) AS body,locator,length(CAST(body AS BLOB))>16000 AS byte_truncated FROM chunks WHERE item_id=? ORDER BY id LIMIT 9 OFFSET ?",
              [.string(id), .number(Double(offset))])
          let page = rows.map { row -> Value in
            var value = row
            let scalars = row["body"]!.text.unicodeScalars
            value["body"] = .string(String(String.UnicodeScalarView(scalars.prefix(4000))))
            value["truncated"] = .number(
              row["byte_truncated"]?.int == 1 || scalars.count > 4000 ? 1 : 0)
            value.removeValue(forKey: "byte_truncated")
            return .object(value)
          }
          return .object([
            "itemID": .string(id), "title": .string(item.title), "assetHash": .string(asset.hash),
            "revision": .number(Double(revision)), "extractionID": extractionID,
            "extraction": status, "chunks": .array(Array(page.prefix(8))),
            "offset": .number(Double(offset)), "hasMore": .bool(page.count > 8),
          ])
        }
      }
    }
  }
}
