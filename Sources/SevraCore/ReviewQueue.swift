import CryptoKit
import Foundation

/// Current non-row drafts, independent of recent activity and conversation pages.
public struct ReviewQueuePage: Codable, Equatable, Sendable {
  public let items: [ItemSummary]
  public let nextCursor: String?
  public let revision: Int
}

private struct ReviewCursor: Codable {
  let version: Int
  let workbook: String
  let revision: Int
  let created: String
  let id: String
}

extension Workbook {
  public func reviewQueue(
    cursor: String? = nil, limit: Int = 20, cancellation: Cancellation = .init(),
    deadlineSeconds: TimeInterval = 3
  ) throws -> ReviewQueuePage {
    try require((1...100).contains(limit), "review_limit", "Choose 1 to 100 drafts per page.")
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: deadlineSeconds)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: deadlineSeconds) {
        try db.readTransaction {
          guard
            let revision = try db.scalar("SELECT value FROM meta WHERE key='review-revision'").int,
            revision >= 0
          else { throw SevraError("integrity", "Invalid draft review revision.") }
          let scope = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
          var after: ReviewCursor?
          if let cursor {
            try require(cursor.utf8.count <= 2048, "review_cursor", "Invalid review page.")
            guard let bytes = Data(base64Encoded: cursor),
              let decoded = try? JSONDecoder().decode(ReviewCursor.self, from: bytes),
              decoded.version == 1, decoded.workbook == scope,
              decoded.id.utf8.count <= 256, decoded.created.utf8.count <= 128
            else { throw SevraError("review_cursor", "Invalid review page.") }
            try require(
              decoded.revision == revision, "stale_review_page",
              "The drafts changed. Refresh the list to see current versions.")
            after = decoded
          }
          let rows = try db.execute(
            """
            SELECT i.id,i.category,i.kind,i.title,i.meaning,i.status,i.asset_id,i.created
            FROM items i INDEXED BY items_review_order JOIN heads h ON h.item_id=i.id
            WHERE i.status='draft' AND i.kind NOT IN ('row','request')
            \(after == nil ? "" : "AND (i.created,i.id) > (?,?)")
            ORDER BY i.created,i.id LIMIT ?
            """,
            (after.map { [.string($0.created), .string($0.id)] } ?? [])
              + [.number(Double(limit + 1))])
          let page = Array(rows.prefix(limit))
          var next: String?
          if rows.count > limit, let last = page.last {
            next = try JSONEncoder().encode(
              ReviewCursor(
                version: 1, workbook: scope, revision: revision,
                created: last["created"]!.text, id: last["id"]!.text)
            ).base64EncodedString()
          }
          return ReviewQueuePage(
            items: page.map { row in
              ItemSummary(
                id: row["id"]!.text, category: row["category"]!.text,
                kind: row["kind"]!.text, title: row["title"]!.text,
                meaning: row["meaning"]!.text, status: row["status"]!.text,
                assetID: row["asset_id"]?.string)
            }, nextCursor: next, revision: revision)
        }
      }
    }
  }
}
