import CoreText
import Foundation
import SevraCore

private final class FileReferenceRace: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Error?
  func set(_ error: Error) {
    lock.lock()
    value = error
    lock.unlock()
  }
  var error: Error? {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

func checkFileReferences(at root: URL) {
  check(
    "retained extraction locators survive FTS replacement, correction, retry and portable reopening"
  ) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ExtractedReferences.sevra"), title: "Extraction")
    let target = try book.addItem(category: "source", kind: "observation", title: "Quote")
    let text = "👩🏽‍💻\0 Cafe\u{301}\r\n[quote](sevra://item/\(target.id)) [[Later]] `[[example]]`"
    let file = root.appendingPathComponent("references.md")
    try Data(text.utf8).write(to: file)
    let origin = try book.importFile(file)
    let chunks = [Chunk(text, locator: "page=2"), Chunk("[[Second page]]", locator: "page=3")]
    try book.index(origin.id, chunks: chunks, parser: "fixture-pages-v1")
    let first = try book.fileReferenceSnapshot(origin.id)
    try expect(first["coverage"].text == "ready" && first["references"].array.count == 3)
    try expect(first["input"]["asset_hash"].text == book.asset(origin.assetID!).hash)
    let refs = first["references"].array
    try expect(refs[0]["locator"].text.hasPrefix("page=2; scalar="))
    let savedText = try book.fileReferenceRegion(
      origin.id, snapshotID: first["id"].text, region: 0, limit: 6000)
    try expect(savedText["text"].text.utf8.elementsEqual(text.utf8))
    let secondLookup = refs[1]["reference"]
    let corrected = try book.annotateFileReferences(
      origin.id,
      selections: [
        .init(
          region: 0,
          selection: .init(
            startScalar: secondLookup["startScalar"].int!,
            scalarCount: secondLookup["scalarCount"].int!,
            target: .init(mode: .live, identity: target.logicalID), lookup: "Later",
            id: secondLookup["id"].text))
      ], expectedSnapshotID: first["id"].text, token: "file-correction")
    try expect(corrected["coverage"].text == "partial")
    try refuses("stale_reference") {
      _ = try book.annotateFileReferences(
        origin.id, selections: [], expectedSnapshotID: first["id"].text)
    }
    try book.index(origin.id, chunks: chunks, parser: "fixture-pages-v1")
    try expect(try book.fileReferenceSnapshot(origin.id) == corrected)
    try book.index(
      origin.id, chunks: [Chunk("Reflowed [[Different]]", locator: "page=2")],
      parser: "fixture-pages-v2")
    try expect(try book.fileReferenceSnapshot(origin.id)["id"] != corrected["id"])
    try expect(
      try book.fileReferenceRegion(origin.id, snapshotID: first["id"].text, region: 0)["text"].text
        .utf8.elementsEqual(text.utf8))
    try book.index(origin.id, chunks: chunks, parser: "fixture-pages-v1")
    let restored = try book.fileReferenceSnapshot(origin.id)
    try expect(
      restored["references"] == corrected["references"]
        && restored["input_id"] == corrected["input_id"])
    let version = try book.addItem(
      category: "source", kind: "observation", title: "Renamed", supersedes: target.id)
    try expect(
      try book.resolveFileReference(secondLookup["id"].text, originVersionID: origin.id)[
        "destination"]["id"].text == version.id)
    try expect(
      try book.resolveFileReference(
        refs[0]["reference"]["id"].text, originVersionID: origin.id, snapshotID: first["id"].text)[
          "destination"]["id"].text == target.id)
    try book.rebuildReferenceIndex()
    try expect(try book.fileReferenceSnapshot(origin.id) == restored)
    let archive = root.appendingPathComponent("Extracted.sevraz")
    try book.export(to: archive)
    let opened = try Workbook.openArchive(
      archive, at: root.appendingPathComponent("ExtractedOpened.sevra"))
    try expect(try opened.fileReferenceSnapshot(origin.id) == restored)
    try expect(try Data(contentsOf: opened.assetURL(origin.assetID!)) == Data(text.utf8))
    try expect(try opened.fileReferenceHistory(origin.id, limit: 1)["nextBeforeVersion"].int == 4)
    try expect(try opened.verify()["ok"] == .bool(true))
  }
  check("body and extracted backlinks share deduplicated keyset pages without widening filters") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("MixedReferences.sevra"), title: "Mixed")
    let target = try book.addItem(category: "source", kind: "observation", title: "Target")
    let file = root.appendingPathComponent("mixed.txt")
    try Data("Original".utf8).write(to: file)
    var expected: Set<String> = []
    for index in 0..<70 {
      let original = try book.importFile(file)
      let origin = try book.addItem(
        category: "source", kind: "document", title: "Origin \(index)",
        text: "[body](sevra://item/\(target.id))", meaning: index % 2 == 0 ? "actual" : "estimate",
        assetID: original.assetID, supersedes: original.id)
      try book.index(
        origin.id, chunks: [Chunk("[file](sevra://item/\(target.id))", locator: "page=1")])
      if index % 2 == 0 { expected.insert(origin.id) }
      let out = try book.referenceLinks(origin.id)
      try expect(out["hits"].array.count == 1 && out["hits"].array[0]["mentionCount"].int == 2)
    }
    var cursor: String?
    var found: Set<String> = []
    repeat {
      let page = try book.referenceLinks(
        target.id, direction: .incoming, meaning: "actual", limit: 9, cursor: cursor)
      for hit in page["hits"].array {
        try expect(
          found.insert(hit["evidence"]["id"].text).inserted && hit["mentionCount"].int == 2)
        try expect(hit["discoveryScopes"].array.count == 2)
      }
      cursor = page["nextCursor"].string
    } while cursor != nil
    try expect(found == expected)
    let fileOnly = try book.referenceLinks(
      target.id, direction: .incoming, contentScope: .extracted, limit: 50)
    try expect(
      fileOnly["hits"].array.count == 50 && fileOnly["hits"].array[0]["mentionCount"].int == 1)
    let bodyOnly = try book.referenceLinks(
      target.id, direction: .incoming, contentScope: .body, limit: 50)
    try expect(
      bodyOnly["hits"].array.count == 50 && bodyOnly["hits"].array[0]["mentionCount"].int == 1)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("file bindings follow unchanged assets through version changes and Undo") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("FileReferenceLifecycle.sevra"), title: "Lifecycle")
    let target = try book.addItem(category: "source", kind: "observation", title: "Target")
    let file = root.appendingPathComponent("lifecycle.txt")
    try Data("Original".utf8).write(to: file)
    let original = try book.importFile(file)
    try book.index(original.id, chunks: [Chunk("[target](sevra://item/\(target.id))")])
    let first = try book.fileReferenceSnapshot(original.id)
    let renamed = try book.addItem(
      category: "source", kind: "document", title: "Renamed", assetID: original.assetID,
      supersedes: original.id)
    try expect(try book.fileReferenceSnapshot(renamed.id)["references"] == first["references"])
    let restored = try book.undoItem(renamed.id)
    try expect(try book.fileReferenceSnapshot(restored.id)["references"] == first["references"])
    let current = try book.referenceLinks(target.id, direction: .incoming)
    try expect(
      current["hits"].array.count == 1
        && current["hits"].array[0]["evidence"]["id"].text == restored.id)
    try expect(
      try book.referenceLinks(target.id, direction: .incoming, historicalOrigins: true)["hits"]
        .array.count == 3)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("extraction text and occurrence limits remain partial and cancellable") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("FileReferenceBounds.sevra"), title: "Bounds")
    let file = root.appendingPathComponent("bounds.txt")
    try Data("Original".utf8).write(to: file)
    let origin = try book.importFile(file)
    let text = String(repeating: "[[name]] ", count: 130) + String(repeating: "é", count: 510_000)
    try book.index(origin.id, chunks: [Chunk(text)])
    let snapshot = try book.fileReferenceSnapshot(origin.id)
    try expect(
      snapshot["coverage"].text == "partial" && snapshot["references"].array.count == 128
        && snapshot["input"]["truncated"].int == 1)
    let cancelled = Cancellation()
    cancelled.cancel()
    let before = try book.counts()
    try refuses("cancelled") {
      try book.index(origin.id, chunks: [Chunk("Other")], cancellation: cancelled)
    }
    try expect(try book.counts() == before && book.fileReferenceSnapshot(origin.id) == snapshot)
    try book.index(origin.id, chunks: [], state: "unsupported")
    try expect(try book.fileReferenceSnapshot(origin.id)["coverage"].text == "unsupported")
    try book.index(
      origin.id, chunks: [Chunk("[[Some]]")], state: "partial", detail: "OCR may contain errors")
    try expect(try book.fileReferenceSnapshot(origin.id)["coverage"].text == "partial")
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("failed file-reference publication preserves old search, bindings and receipts atomically")
  {
    let book = try Workbook.create(
      at: root.appendingPathComponent("FileReferenceFault.sevra"), title: "Fault")
    let file = root.appendingPathComponent("fault.txt")
    try Data("Original".utf8).write(to: file)
    let origin = try book.importFile(file)
    try book.index(origin.id, chunks: [Chunk("[[Retained]]")])
    let previous = try book.fileReferenceSnapshot(origin.id)
    let before = try book.counts()
    _ = try referenceSQL(
      book,
      "CREATE TRIGGER injected_file_failure BEFORE INSERT ON file_reference_index WHEN NEW.ordinal=1 BEGIN SELECT RAISE(ABORT,'injected'); END;"
    )
    defer { _ = try? referenceSQL(book, "DROP TRIGGER IF EXISTS injected_file_failure;") }
    try refuses("database") { try book.index(origin.id, chunks: [Chunk("[[one]] [[two]]")]) }
    try expect(try book.counts() == before, "Failed publication changed counts or revision")
    try expect(
      try book.fileReferenceSnapshot(origin.id) == previous,
      "Failed publication changed annotations")
    try expect(
      try book.search("Retained").hits.contains(where: { $0.itemID == origin.id }),
      "Failed publication lost the old index")
    try expect(try book.search("two").hits.isEmpty, "Failed publication leaked new search text")
    _ = try referenceSQL(book, "DROP TRIGGER injected_file_failure;")
    _ = try referenceSQL(book, "DELETE FROM file_reference_index;")
    try refuses("integrity") { _ = try book.verify() }
    try book.rebuildReferenceIndex()
    try expect(
      try book.fileReferenceSnapshot(origin.id) == previous && book.verify()["ok"] == .bool(true))
    _ = try referenceSQL(book, "UPDATE file_reference_inputs SET regions='[]';")
    try refuses("integrity") { _ = try book.verify() }
  }
  check("stale extraction completion cannot replace newer text, annotations or status") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("FileReferenceRace.sevra"), title: "Race")
    let file = root.appendingPathComponent("race.txt")
    try Data("Original".utf8).write(to: file)
    let origin = try book.importFile(file)
    let started = root.appendingPathComponent("extract-started")
    let release = root.appendingPathComponent("extract-release")
    let oldJSON =
      #"{"version":1,"result":{"chunks":[{"text":"[[Old]]","locator":"text"}],"state":"ready","detail":"Old"}}"#
    let newJSON =
      #"{"version":1,"result":{"chunks":[{"text":"[[New]]","locator":"text"}],"state":"ready","detail":"New"}}"#
    // Fixture paths are generated UUID temp paths, not user-supplied shell input.
    let old = ExtractionWorker(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: [
        "-c",
        "touch '\(started.path)'; while [ ! -e '\(release.path)' ]; do sleep 0.02; done; printf '%s' '\(oldJSON)'",
        "--",
      ], timeout: 5)
    let new = ExtractionWorker(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "printf '%s' '\(newJSON)'", "--"], timeout: 5)
    let state = FileReferenceRace()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
      defer { group.leave() }
      do { try book.extract(origin.id, worker: old) } catch { state.set(error) }
    }
    defer {
      FileManager.default.createFile(atPath: release.path, contents: Data())
      _ = group.wait(timeout: .now() + 6)
    }
    for _ in 0..<300 {
      if FileManager.default.fileExists(atPath: started.path) { break }
      Thread.sleep(forTimeInterval: 0.01)
    }
    try expect(FileManager.default.fileExists(atPath: started.path))
    try book.extract(origin.id, worker: new)
    let saved = try book.fileReferenceSnapshot(origin.id)
    FileManager.default.createFile(atPath: release.path, contents: Data())
    try expect(group.wait(timeout: .now() + 6) == .success)
    try expect((state.error as? SevraError)?.code == "stale_extraction")
    try expect(
      try book.fileReferenceSnapshot(origin.id) == saved
        && book.extractionStatus(origin.id)["detail"].text == "New")
    try expect(try book.search("New").hits.count == 1 && book.search("Old").hits.isEmpty)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check(
    "native PDF extraction retains page-specific mention coordinates without changing asset bytes"
  ) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("PDFReferences.sevra"), title: "PDF")
    let file = root.appendingPathComponent("mentions.pdf")
    var box = CGRect(x: 0, y: 0, width: 1000, height: 300)
    let context = CGContext(file as CFURL, mediaBox: &box, nil)!
    for number in 1...2 {
      context.beginPDFPage(nil)
      context.textPosition = CGPoint(x: 40, y: 150)
      let text = NSAttributedString(
        string: "[[Page \(number) mention]]",
        attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
            "Helvetica" as CFString, 20, nil)
        ])
      CTLineDraw(CTLineCreateWithAttributedString(text), context)
      context.endPDFPage()
    }
    context.closePDF()
    let bytes = try Data(contentsOf: file)
    let origin = try book.importFile(file)
    try book.extract(origin.id)
    let snapshot = try book.fileReferenceSnapshot(origin.id)
    try expect(
      snapshot["references"].array.count == 2
        && snapshot["references"].array[0]["locator"].text.hasPrefix("page=1;"))
    try expect(snapshot["references"].array[1]["locator"].text.hasPrefix("page=2;"))
    try expect(
      try Data(contentsOf: book.assetURL(origin.assetID!)) == bytes
        && book.item(origin.id).text.isEmpty)
    try expect(try book.verify()["ok"] == .bool(true))
  }
}
