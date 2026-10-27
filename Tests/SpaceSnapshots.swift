import Foundation
import SevraCore

func checkSpaceSnapshots(at root: URL) {
  func fixture() throws -> Workbook {
    try Workbook.create(
      at: root.appendingPathComponent(identifier() + ".sevra"), title: "Pinned views")
  }
  func definition(_ book: Workbook, _ id: String) throws -> SpaceDefinition {
    guard let space = try book.spaces().first(where: { $0.id == id }) else {
      throw SevraError("test", "Missing space")
    }
    return space.definition
  }
  check("Pinned document and asset bindings retain exact versions through reopen and export") {
    let book = try fixture()
    let source = try book.addItem(
      category: "source", kind: "submission", title: "Input", text: "Plan")
    let old = try book.addItem(
      category: "record", kind: "document", title: "Plan", text: "Original",
      meaning: "estimate", inputs: [source.id])
    let file = root.appendingPathComponent(identifier() + ".txt")
    try Data("Original bytes".utf8).write(to: file)
    let asset = try book.importFile(file)
    let live = try book.saveSpace(
      title: "Live",
      definition: .init(components: [
        .init(
          type: "comparison", title: "Evidence",
          children: [
            .init(type: "document", title: "Plan", itemID: old.logicalID),
            .init(type: "asset", title: "File", itemID: asset.logicalID),
          ]),
        .init(type: "document", title: "Exact original", itemID: old.id),
      ]))
    let pinned = try book.pinSpace(live, token: "pin-items")
    let frozen = try definition(book, pinned)
    try expect(frozen.pinnedAt != nil)
    try expect(frozen.components[0].children?.map(\.itemID) == [old.id, asset.id])
    let revised = try book.editDocument(old.id, text: "New draft")
    let changedAsset = try book.addItem(
      category: "source", kind: asset.kind, title: "Revised file label",
      text: "New metadata", status: "accepted", assetID: asset.assetID, supersedes: asset.id)
    let original = try definition(book, live)
    try expect(try book.item(original.components[0].children![0].itemID!).id == revised.id)
    try expect(try book.item(original.components[0].children![1].itemID!).id == changedAsset.id)
    try expect(try book.item(original.components[1].itemID!).text == "Original")
    try expect(try definition(Workbook(book.url), pinned) == frozen)
    let archive = root.appendingPathComponent(identifier() + ".sevraz")
    try book.export(to: archive)
    let reopened = try Workbook.openArchive(
      archive, at: root.appendingPathComponent(identifier() + ".sevra"))
    try expect(try definition(reopened, pinned) == frozen)
    try expect(try reopened.item(frozen.components[0].children![0].itemID!).text == "Original")
    try expect(try reopened.verify()["ok"] == .bool(true))
  }
  check("Pinned search preserves its bounded hits, locators and index gaps after corrections") {
    let book = try fixture()
    var originals: [Item] = []
    for index in 0..<10 {
      originals.append(
        try book.addItem(
          category: "source", kind: "observation",
          title: "Saffron sample \(index)", text: "Saffron evidence \(index)"))
    }
    try book.index(
      originals[0].id, chunks: [Chunk("Saffron evidence", locator: "page=7")],
      state: "partial", detail: "Synthetic missing pages")
    let live = try book.saveSpace(
      title: "Findings",
      definition: .init(components: [
        .init(type: "search", title: "Samples", query: "saffron")
      ]))
    let visible = try book.search("saffron", limit: 8)
    let pinned = try book.pinSpace(live, token: "pin-search")
    let frozen = try definition(book, pinned)
    let result = frozen.components[0].searchSnapshot!
    try expect(result.hits == visible.hits && result.hasMore && result.incomplete == 1)
    try expect(result.query == "saffron" && result.captured == frozen.pinnedAt)
    for old in originals {
      _ = try book.addItem(
        category: "source", kind: old.kind, title: "Current label", text: "Revised",
        supersedes: old.id)
    }
    try expect(try book.search("saffron").hits.isEmpty)
    try expect(try definition(book, pinned) == frozen)
    try expect(try book.pinSpace(live, token: "pin-search") == pinned)
    for hit in result.hits {
      try expect(try book.item(hit.itemID).id == hit.itemID)
      try expect(originals.contains { $0.id == hit.itemID })
    }
    let repinned = try book.pinSpace(pinned)
    try expect(
      try definition(book, repinned) == frozen, "Re-pinning reran or relabeled old results")
  }
  check("Empty pinned search retains its original gap after indexing and new evidence") {
    let book = try fixture()
    let source = try book.addItem(
      category: "source", kind: "observation", title: "Unindexed", text: "")
    try book.index(
      source.id, chunks: [], state: "unsupported", detail: "Synthetic unsupported file")
    let live = try book.saveSpace(
      title: "Missing",
      definition: .init(components: [
        .init(type: "search", title: "Renewal", query: "hibiscus")
      ]))
    let pinned = try book.pinSpace(live)
    let result = try definition(book, pinned).components[0].searchSnapshot!
    try expect(result.hits.isEmpty && result.incomplete == 1 && !result.hasMore)
    try book.index(source.id, chunks: [Chunk("hibiscus renewal", locator: "page=2")])
    try expect(try book.search("hibiscus").hits.count == 1)
    try expect(try definition(book, pinned).components[0].searchSnapshot == result)
  }
  check("An unpinnable component refuses the whole copy without a partial space") {
    let book = try fixture()
    let source = try book.addItem(category: "source", kind: "submission", title: "Rows")
    let table = try book.createDataset(
      title: "Too many", columns: [.init(id: "n", title: "N")],
      rows: (0..<1001).map { ["n": .string(String($0))] }, sourceID: source.id)
    let live = try book.saveSpace(
      title: "Mixed",
      definition: .init(components: [
        .init(type: "search", title: "Rows", query: "rows"),
        .init(type: "table", title: "Large table", datasetID: table.id),
      ]))
    let revision = try book.revision()
    let spaces = try book.spaces().count
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses("cancelled") { _ = try book.pinSpace(live, cancellation: cancelled) }
    try expect(try book.revision() == revision && book.spaces().count == spaces)
    try refuses("view_limit") { _ = try book.pinSpace(live, token: "refuse-all") }
    try expect(try book.revision() == revision && book.spaces().count == spaces)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("Pinned labels cannot be saved over live bindings and legacy spaces remain readable") {
    let book = try fixture()
    let item = try book.addItem(category: "source", kind: "submission", title: "Input")
    let components = [Component(type: "document", title: "Input", itemID: item.logicalID)]
    let revision = try book.revision()
    try refuses("view") {
      _ = try book.saveSpace(
        title: "Misleading",
        definition: .init(
          components: components,
          pinnedAt: "2026-10-27T00:00:00Z"))
    }
    try refuses("view") {
      _ = try book.saveSpace(
        title: "Misleading search",
        definition: .init(
          components: [
            .init(type: "search", title: "Find", query: "input")
          ], pinnedAt: "2026-10-27T00:00:00Z"))
    }
    try refuses("query_limit") {
      _ = try book.saveSpace(
        title: "Oversized",
        definition: .init(components: [
          .init(type: "search", title: "Find", query: String(repeating: "x", count: 2049))
        ]))
    }
    try expect(try book.revision() == revision)
    let old = try JSONDecoder().decode(
      SpaceDefinition.self,
      from: Data("{\"version\":1,\"components\":[]}".utf8))
    try expect(old.pinnedAt == nil && old.components.isEmpty)
  }
}
