import Foundation
import SevraCore

func evidenceChecks(_ root: URL, _ suite: inout Suite) {
  suite.check("A4 exact extracted text, paging, bounds and revision refusal") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Text.sevra"), title: "Synthetic text")
    let file = root.appendingPathComponent("image.txt")
    try Data("synthetic original".utf8).write(to: file)
    let source = try book.importFile(file)
    try book.index(
      source.id, chunks: (1...17).map { Chunk("Passage \($0)", locator: "page=\($0)") },
      state: "partial", parser: "headless-fixture")
    let revision = try book.revision()
    let first = try book.extractedTextPage(source.id)
    try expect(
      first["chunks"].array.count == 8 && first["hasMore"] == .bool(true), "First page coverage")
    try expect(first["chunks"].array.first?["body"] == .string("Passage 1"), "First passage")
    try expect(first["assetHash"].text == book.asset(source.assetID!).hash, "Exact asset hash")
    try expect(
      first["extraction"]["state"] == .string("partial") && first["extractionID"].string != nil,
      "Extraction identity and partial status")
    let second = try book.extractedTextPage(source.id, offset: 8, expectedRevision: revision)
    let final = try book.extractedTextPage(source.id, offset: 16, expectedRevision: revision)
    try expect(
      second["chunks"].array.count == 8 && final["chunks"].array.count == 1, "Paging counts")
    try expect(
      final["chunks"].array[0]["locator"] == .string("page=17; offset=0")
        && final["hasMore"] == .bool(false), "Final locator/end")
    try expect(try book.revision() == revision, "Reading must not mutate workbook")
    try refuses("extracted_text") { _ = try book.extractedTextPage(source.id, offset: -1) }
    try refuses("extracted_text") { _ = try book.extractedTextPage(source.id, offset: 1_000_001) }
    let note = try book.addItem(category: "source", kind: "note", title: "No asset")
    try refuses("extracted_text") { _ = try book.extractedTextPage(note.id) }
    try refuses("extracted_text_changed") {
      _ = try book.extractedTextPage(source.id, offset: 8, expectedRevision: revision)
    }
    let token = Cancellation()
    token.cancel()
    try refuses("cancelled") { _ = try book.extractedTextPage(source.id, cancellation: token) }
  }
  suite.check("A4 Unicode, embedded NUL, empty index and oversized passage") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Unicode.sevra"), title: "Unicode")
    let file = root.appendingPathComponent("unicode.txt")
    try Data("fixture".utf8).write(to: file)
    let source = try book.importFile(file)
    let blank = try book.extractedTextPage(source.id)
    try expect(
      blank["chunks"].array.isEmpty && blank["hasMore"] == .bool(false),
      "No synthetic text for unindexed original")
    let body = "Before\0After 👩🏽‍💻 Cafe\u{301}"
    try book.index(source.id, chunks: [Chunk(body, locator: "page=1")], parser: "fixture")
    let shown = try book.extractedTextPage(source.id)["chunks"].array[0]
    try expect(
      shown["body"].text.utf8.elementsEqual(body.utf8),
      "Recognized text must preserve embedded NUL and Unicode")
    let long = String(repeating: "文", count: 5000)
    try book.index(source.id, chunks: [Chunk(long)], parser: "fixture")
    let bounded = try book.extractedTextPage(source.id)["chunks"].array[0]
    try expect(
      bounded["body"].text.count == 2800 && bounded["truncated"].int == 0,
      "Ordinary indexed passages preserve existing chunk boundaries")
    let oversizedGrapheme = "e" + String(repeating: "\u{301}", count: 5000)
    try book.index(source.id, chunks: [Chunk(oversizedGrapheme)], parser: "fixture")
    let shortened = try book.extractedTextPage(source.id)["chunks"].array[0]
    try expect(
      shortened["body"].text.unicodeScalars.count == 4000 && shortened["truncated"].int == 1,
      "Oversized scalar content is bounded and disclosed")
  }
  suite.check(
    "A4 failed and unsupported extraction metadata cannot masquerade as readable passages"
  ) {
    let book = try Workbook.create(at: root.appendingPathComponent("Status.sevra"), title: "Status")
    let file = root.appendingPathComponent("status.txt")
    try Data("original".utf8).write(to: file)
    let source = try book.importFile(file)
    try book.index(source.id, chunks: [Chunk("Original text")], parser: "fixture")
    let previous = try book.extractedTextPage(source.id)
    for status in ["failed", "unsupported"] {
      try book.index(
        source.id, chunks: [Chunk("Import metadata, not extracted text")], state: status,
        parser: "fixture")
      let page = try book.extractedTextPage(source.id)
      try expect(
        page["chunks"].array.isEmpty && page["hasMore"] == .bool(false),
        "Non-readable extraction state: " + status)
      try refuses("extracted_text_changed") {
        _ = try book.extractedTextPage(source.id, expectedRevision: previous["revision"].int!)
      }
    }
    try book.index(
      source.id, chunks: [Chunk("Recovered text")], state: "partial", parser: "fixture")
    try expect(
      try book.extractedTextPage(source.id)["chunks"].array[0]["body"] == .string("Recovered text"),
      "Successful retry restores reading")
  }
  suite.check("A4 descriptions persist, reject stale writers and replay without duplicates") {
    let url = root.appendingPathComponent("Description.sevra")
    let book = try Workbook.create(at: url, title: "Description")
    let file = root.appendingPathComponent("description.txt")
    try Data("original".utf8).write(to: file)
    let source = try book.importFile(file)
    let originalHash = try book.asset(source.assetID!).hash
    let initial = try book.imageDescription(source.id)
    let first = try book.saveImageDescription(
      source.id, text: "Red valve", previousID: nil, expectedRevision: initial["revision"].int!,
      token: "description-one")
    let revision = try book.revision()
    let repeated = try book.saveImageDescription(
      source.id, text: "Red valve", previousID: nil, expectedRevision: initial["revision"].int!,
      token: "description-one")
    try expect(
      repeated.id == first.id && book.revision() == revision, "Replay must not write again")
    try refuses("idempotency") {
      _ = try book.saveImageDescription(
        source.id, text: "Blue valve", previousID: nil, expectedRevision: revision,
        token: "description-one")
    }
    try refuses("description_changed") {
      _ = try book.saveImageDescription(
        source.id, text: "Stale", previousID: nil, expectedRevision: revision, token: "stale")
    }
    try refuses("description_length") {
      _ = try book.saveImageDescription(
        source.id, text: String(repeating: "🟢", count: 2001), previousID: first.id,
        expectedRevision: revision, token: "oversize")
    }
    let second = try book.saveImageDescription(
      source.id, text: "Two red valves", previousID: first.id, expectedRevision: revision,
      token: "description-two")
    let reopened = try Workbook(url)
    try expect(
      try reopened.imageDescription(source.id)["id"] == .string(second.id),
      "Reopen current description")
    try expect(try reopened.item(first.id).text == "Red valve", "Preserve prior description")
    try expect(try reopened.asset(source.assetID!).hash == originalHash, "Preserve original bytes")
    _ = try book.addItem(category: "source", kind: "note", title: "Concurrent change")
    try refuses("stale_revision") {
      _ = try reopened.saveImageDescription(
        source.id, text: "Stale revision", previousID: second.id, expectedRevision: revision,
        token: "stale-revision")
    }
    try expect(
      try reopened.imageDescription(source.id)["body"] == .string("Two red valves"),
      "Other connection cannot overwrite unseen state")
    let beforeClear = try reopened.imageDescription(source.id)
    _ = try reopened.saveImageDescription(
      source.id, text: "", previousID: second.id, expectedRevision: beforeClear["revision"].int!,
      token: "clear")
    try expect(try reopened.imageDescription(source.id)["body"] == .string(""), "Explicit clear")
  }
}
