import Foundation
import SevraCore

func checkSearchSnippets(at root: URL) {
  check(
    "ordinary search excludes technical Sources before paging while owner inspection stays explicit"
  ) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("SearchKinds.sevra"), title: "Search kinds")
    var evidence = Set<String>()
    for n in 0..<12 {
      let item = try book.addItem(
        category: "source", kind: "document", title: "crystal-\(n).txt",
        text: "Crystal evidence \(n).")
      evidence.insert(item.id)
    }
    var annotations = Set<String>()
    for n in 0..<40 {
      let item = try book.addItem(
        category: "source", kind: "annotation", title: "crystal-annotation-\(n).txt",
        text: "Crystal crystal crystal crystal technical annotation \(n).")
      annotations.insert(item.id)
    }
    let request = try book.addItem(
      category: "source", kind: "request", title: "crystal-request.txt",
      text: "Crystal crystal crystal submitted request.")
    let revision = try book.revision()
    let full = try book.search("crystal", limit: 100)
    try expect(Set(full.hits.map(\.itemID)) == evidence && full.nextCursor == nil)
    var cursor: String?
    var pages: [SearchHit] = []
    repeat {
      let page = try book.search("crystal", limit: 5, cursor: cursor)
      try expect(page.hits.count == (pages.count == 10 ? 2 : 5), "Hidden Sources consumed a page")
      pages += page.hits
      cursor = page.nextCursor
    } while cursor != nil
    try expect(pages.map(\.itemID) == full.hits.map(\.itemID))
    try expect(
      try book.search("ystal-", limit: 100).hits.count == evidence.count,
      "Filename-only matching bypassed the kind exclusion")
    try expect(
      try book.search("crystal", kind: "annotation", limit: 100).hits.map(\.itemID).count
        == annotations.count, "Explicit owner annotation search was lost")
    try expect(try book.search("crystal", kind: "request").hits.map(\.itemID) == [request.id])
    try expect(try book.search("crystal", kind: "annotation", businessOnly: true).hits.isEmpty)
    try expect(try book.search("crystal", kind: "request", businessOnly: true).hits.isEmpty)
    try expect(try book.items(kind: "annotation").count == annotations.count)
    try expect(try book.item(request.id).text == request.text)
    try expect(try book.revision() == revision && book.verify()["ok"] == .bool(true))
  }
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
