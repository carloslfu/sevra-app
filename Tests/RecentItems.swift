import Foundation
import SevraCore

func checkRecentItems(at root: URL) {
  check("recent catalog stays bounded and preserves exact current evidence metadata") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Recent.sevra"), title: "Recent")
    let body = String(repeating: "large evidence ", count: 140_000)
    let payload = Value.object(["original": .string(String(repeating: "x", count: 1_000_000))])
    let source = try book.addItem(
      category: "source", kind: "note", title: "Large source", text: body, data: payload)
    let forecast = try book.addItem(
      category: "record", kind: "forecast", title: "Accepted estimate", meaning: "estimate",
      status: "accepted", inputs: [source.id])
    let old = try book.addItem(category: "source", kind: "note", title: "Earlier observation")
    let current = try book.addItem(
      category: "source", kind: "note", title: "Corrected observation", supersedes: old.id)
    let file = root.appendingPathComponent("recent-original.txt")
    try Data("File evidence".utf8).write(to: file)
    let included = try book.importFile(file)

    // Excluded entries are deliberately newer than all visible evidence. Applying
    // the result limit before these exclusions would leave Home empty.
    try FixtureContext.$current.withValue(
      FixtureContext(seed: 9481, date: "2099-01-01T00:00:00Z")
    ) {
      for index in 0..<10 {
        _ = try book.addItem(
          category: "source", kind: index.isMultiple(of: 2) ? "row" : "request",
          title: "Internal \(index)")
      }
    }
    let revision = try book.revision()
    let rows = try book.recentItemSummaries(limit: 4)
    try expect(Set(rows.map(\.id)) == Set([source.id, forecast.id, current.id, included.id]))
    let accepted = rows.first { $0.id == forecast.id }
    try expect(
      accepted?.category == "record" && accepted?.kind == "forecast"
        && accepted?.meaning == "estimate" && accepted?.status == "accepted",
      "A catalog entry changed acceptance or meaning")
    try expect(rows.first { $0.id == included.id }?.assetID == included.assetID)
    let encoded = try JSONEncoder().encode(rows)
    try expect(encoded.count < 2_000, "Catalog serialization expanded with the large body/payload")
    let decoded = try JSONSerialization.jsonObject(with: encoded) as! [[String: Any]]
    try expect(decoded.allSatisfy { $0["text"] == nil && $0["data"] == nil })
    try expect(try book.recentItemSummaries(limit: 1).count == 1)
    try expect(try book.item(source.id).text == body && book.item(source.id).data == payload)
    try expect(try book.item(old.id).title == "Earlier observation")
    try expect(try book.revision() == revision && book.verify()["ok"] == .bool(true))
  }
}
