import Foundation
import SevraCore

func checkSearchSnippets(at root: URL) {
  check("search passages remain exact across dense, sparse and filename-only hits") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Snippets.sevra"), title: "Snippets")
    let first = try book.addItem(category: "source", kind: "document", title: "First")
    let passage = String(repeating: "Delivery details precede the evidence. ", count: 30)
    try book.index(
      first.id, chunks: [Chunk(passage + "Café zirconium verified first.", locator: "page=4")])
    let spacer = try book.addItem(category: "source", kind: "document", title: "Spacer")
    try book.index(
      spacer.id, chunks: (0..<4200).map { Chunk("Unrelated filler", locator: "page=\($0)") })
    let last = try book.addItem(category: "source", kind: "document", title: "Last")
    try book.index(
      last.id, chunks: [Chunk(passage + "Café zirconium verified last.", locator: "page=9")])
    let named = try book.addItem(
      category: "source", kind: "document", title: "archive-zirconium-copy.pdf",
      text: "Filename-only excerpt.")
    let both = try book.addItem(
      category: "source", kind: "document", title: "zirconium.txt",
      text: "Café zirconium mixed match.")
    let page = try book.search("zirconium", limit: 100)
    try expect(Set(page.hits.map(\.itemID)) == [first.id, last.id, named.id, both.id])
    try expect(page.hits.count == 4 && page.nextCursor == nil)
    try expect(
      page.hits.first { $0.itemID == first.id }?.snippet.contains("verified first") == true)
    try expect(page.hits.first { $0.itemID == last.id }?.snippet.contains("verified last") == true)
    try expect(page.hits.first { $0.itemID == first.id }?.locator == "page=4; offset=0")
    try expect(page.hits.first { $0.itemID == last.id }?.locator == "page=9; offset=0")
    try expect(page.hits.first { $0.itemID == named.id }?.snippet == "Filename-only excerpt.")
    // A substring has no lexical hit, so the stored excerpt must survive.
    let filenameOnly = try book.search("rchive-zirc")
    try expect(filenameOnly.hits.map(\.itemID) == [named.id])
    try expect(filenameOnly.hits[0].snippet == "Filename-only excerpt.")
    let accented = try book.search("cafe zirconium")
    try expect(Set(accented.hits.map(\.itemID)) == [first.id, last.id, both.id])
    try expect(accented.hits.allSatisfy { $0.snippet.contains("Café zirconium") })
    // Changing the page size changes snippet batching, never the passage or ranking.
    var cursor: String?
    var individual: [SearchHit] = []
    repeat {
      let next = try book.search("zirconium", limit: 1, cursor: cursor)
      individual += next.hits
      cursor = next.nextCursor
    } while cursor != nil
    try expect(individual.count == page.hits.count)
    for (single, batched) in zip(individual, page.hits) {
      try expect(single.id == batched.id && single.rank == batched.rank)
      try expect(single.snippet == batched.snippet && single.locator == batched.locator)
    }
    try expect(try book.search("absentterm").hits.isEmpty)
  }
}
