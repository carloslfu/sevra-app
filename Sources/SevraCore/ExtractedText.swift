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
          let page = try db.execute(
            "SELECT id,substr(body,1,4000) AS body,locator,length(body)>4000 AS truncated FROM chunks WHERE item_id=? ORDER BY id LIMIT 9 OFFSET ?",
            [.string(id), .number(Double(offset))]
          ).map(Value.object)
          let extractionID = try db.scalar(
            "SELECT s.input_id FROM file_reference_heads h JOIN file_reference_sets s ON s.id=h.set_id WHERE h.origin_id=?",
            [.string(id)])
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
