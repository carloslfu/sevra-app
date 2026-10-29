import AppKit
import Foundation
import PDFKit
import SevraCore
import SevraDocumentUI
import SwiftUI

private actor ReferenceReadGate<T: Sendable> {
  var ready = false
  var continuation: CheckedContinuation<T, Never>?
  var early: T?
  func read() async -> T {
    ready = true
    if let early { return early }
    return await withCheckedContinuation { continuation = $0 }
  }
  func finish(_ value: T) {
    if let continuation {
      continuation.resume(returning: value)
      self.continuation = nil
    } else {
      early = value
    }
  }
}

@MainActor func checkNativeReferences(
  at root: URL,
  check: (String, () throws -> Void) -> Void,
  checkAsync: (String, () async throws -> Void) async -> Void
) async {
  func fixture() throws -> (Workbook, Item, Item) {
    let book = try Workbook.create(
      at: root.appendingPathComponent(identifier() + ".sevra"), title: "References")
    let target = try book.addItem(
      category: "source", kind: "observation", title: "Target", text: "Original quote",
      status: "accepted")
    let source = try book.addItem(
      category: "source", kind: "document", title: "Notes",
      text:
        "👩🏽‍💻\0 Cafe\u{301}\r\n[[Unchosen|Alias]] [quote](sevra://item/\(target.id)) `[[example]]` [web](https://example.invalid)",
      status: "accepted")
    return (book, source, target)
  }
  check("Native reading labels use canonical spans without opening raw source URLs") {
    let (book, source, target) = try fixture()
    let document = try ReferenceDocument.read(source, workbook: book)
    let expected = "👩🏽‍💻\0 Cafe\u{301}\r\nAlias quote `[[example]]` [web](https://example.invalid)"
    try expect(
      document.presentation.plainText.utf8.elementsEqual(expected.utf8),
      "Reader changed Unicode, literals or labels")
    try expect(document.occurrences.count == 2, "Examples or web links became workbook actions")
    try expect(
      document.presentation.parts.filter { $0.occurrence != nil }.map(\.text) == [
        "Alias", "quote",
      ], "Reader exposed route markup")
    try expect(
      document.occurrences.allSatisfy { $0.url.scheme == "sevra-ref" && $0.origin == source.id },
      "Raw URL escaped saved occurrence routing")
    try expect(
      try document.resolve(document.occurrences[1], workbook: book)["destination"]["id"].text
        == target.id, "Reader retargeted a pin")
    try expect(
      try book.item(source.id).text.utf8.elementsEqual(source.text.utf8),
      "Reader rewrote original text")
    try refuses("reference_body") {
      _ = try ReferencePresentation.make(text: source.text + "changed", snapshot: document.body)
    }
    let cancel = Cancellation()
    cancel.cancel()
    try refuses("cancelled") {
      _ = try ReferenceDocument.read(source, workbook: book, cancellation: cancel)
    }
  }
  check(
    "Choosing one Source link preserves all other occurrences, original bytes and retry identity"
  ) {
    let (book, source, target) = try fixture()
    let document = try ReferenceDocument.read(source, workbook: book)
    let occurrence = document.occurrences[0]
    let chosen = ReferenceTarget(mode: .live, identity: target.logicalID)
    let first = try document.choose(
      occurrence, target: chosen, item: source, workbook: book, token: "choose-source")
    let after = try ReferenceDocument.read(source, workbook: book)
    let counts = try book.counts()
    let retry = try document.choose(
      occurrence, target: chosen, item: source, workbook: book, token: "choose-source")
    try expect(
      first.id == source.id && retry.id == first.id && book.counts() == counts,
      "Choice retried as another mutation")
    try expect(
      after.occurrences.count == 2
        && after.occurrences[1].reference == document.occurrences[1].reference,
      "Choice dropped another occurrence")
    try expect(
      after.occurrences[0].reference.targetLogicalID == target.logicalID
        && after.body.coverage == "partial", "Choice was guessed or claimed complete coverage")
    try expect(
      try book.item(source.id).text.utf8.elementsEqual(source.text.utf8),
      "Source choice rewrote evidence")
    try refuses("stale_reference") {
      _ = try document.choose(
        occurrence, target: nil, item: source, workbook: book, token: "stale-source")
    }
    let newer = try book.addItem(
      category: "source", kind: "observation", title: "Renamed target", text: "New quote",
      supersedes: target.id)
    try expect(
      try after.resolve(after.occurrences[0], workbook: book)["destination"]["id"].text == newer.id,
      "Live link did not follow its saved logical identity")
    try expect(
      try after.resolve(after.occurrences[1], workbook: book)["destination"]["id"].text
        == target.id, "Pinned link lost history")
    try expect(try book.verify()["ok"] == .bool(true), "Source choice damaged the workbook")
  }
  check("File-link choices retain page input, other bindings and portable asset bytes") {
    let (book, _, target) = try fixture()
    let file = root.appendingPathComponent(identifier() + ".txt")
    let bytes = Data("[[First]] [[Second]]".utf8)
    try bytes.write(to: file)
    let source = try book.importFile(file)
    try book.index(
      source.id,
      chunks: [Chunk("[[First]]", locator: "page=2"), Chunk("[[Second]]", locator: "page=3")])
    let document = try ReferenceDocument.read(source, workbook: book)
    try expect(
      document.occurrences.count == 2 && document.occurrences[0].kind == .extracted,
      "Wrong file occurrence origin")
    _ = try document.choose(
      document.occurrences[0], target: .init(mode: .pinned, identity: target.id), item: source,
      workbook: book, token: "file-choice")
    let after = try ReferenceDocument.read(source, workbook: book)
    try expect(
      after.file["input_id"] == document.file["input_id"]
        && after.occurrences[1].reference == document.occurrences[1].reference,
      "File choice rewrote retained input or dropped a link")
    try expect(
      after.occurrences[0].locator.hasPrefix("page=2;") && after.occurrences[0].region == 0,
      "File choice moved its locator")
    try expect(
      try Data(contentsOf: book.assetURL(source.assetID!)) == bytes,
      "File choice changed asset bytes")
    try refuses("reference_snapshot") {
      _ = try after.choose(
        document.occurrences[0], target: nil, item: source, workbook: book, token: "old-snapshot")
    }
    try expect(try book.verify()["ok"] == .bool(true), "Invalid file annotation")
  }
  check("Binding-only document revisions preserve exact copy evidence; prose edits do not") {
    let (book, _, target) = try fixture()
    let original = try book.addItem(
      category: "source", kind: "document", title: "Original copy",
      text: "[[Choose]] Cafe\u{301}\r\n", status: "accepted")
    let run = try book.startAgentRequest(
      "Quote the original", conversation: "main", model: "fixture"
    ).runID
    let args: Value = .object(["id": .string(original.id)])
    let receipt = try book.prepareToolCall(
      runID: run, callID: identifier(), tool: "read", arguments: args)
    let result = try WorkbookTools(book, runID: run).execute("read", args, receiptID: receipt)
    _ = try book.completeToolCall(receipt, result: result)
    let choice = DocumentCopyChoices.entries(result)[0]["id"].text
    let copy = try book.documentCopyChoice(choice, runID: run).reference
    let composed = try book.saveComposedDraft(
      title: "Quotation", parts: [.init(copy: copy)], runID: run)
    let document = try ReferenceDocument.read(composed, workbook: book)
    let occurrence = document.occurrences[0]
    let revised = try document.choose(
      occurrence, target: .init(mode: .pinned, identity: target.id), item: composed, workbook: book,
      token: "record-choice")
    try expect(
      revised.id != composed.id && revised.logicalID == composed.logicalID
        && revised.status == "draft", "Choice did not create an ordinary draft version")
    try expect(
      revised.text.utf8.elementsEqual(composed.text.utf8)
        && revised.data["documentComposition"] == composed.data["documentComposition"],
      "Binding-only revision discarded exact copy evidence")
    try expect(
      DocumentProvenance.make(revised).passages.count == 1
        && !DocumentProvenance.make(revised).unavailable,
      "Copy presentation lost the unchanged passage")
    try expect(
      try document.choose(
        occurrence, target: .init(mode: .pinned, identity: target.id), item: composed,
        workbook: book, token: "record-choice"
      ).id == revised.id, "Record choice retry created another version")
    try refuses("stale_revision") {
      _ = try document.choose(
        occurrence, target: nil, item: composed, workbook: book, token: "record-stale")
    }
    let edited = try book.editDocument(revised.id, text: "Edited passage")
    try expect(
      edited.data["documentComposition"] == .null
        && DocumentProvenance.make(edited).passages.isEmpty,
      "Prose edit claimed unchanged original spans")
    try expect(try book.verify()["ok"] == .bool(true), "Binding-only provenance did not verify")
  }
  check("Document reading positions restore geometry, reflow and finite bounds") {
    let position = DocumentReadingPosition(offset: 250, scrollable: 1000, width: 500)
    try expect(
      position.restoredOffset(width: 500, scrollable: 1000) == 250,
      "Back lost the same-layout offset")
    try expect(
      position.restoredOffset(width: 250, scrollable: 2000) == 500,
      "Reflow lost proportional reading position")
    try expect(
      position.restoredOffset(width: 500, scrollable: 0) == 0, "Shorter content overscrolled")
    try expect(
      DocumentReadingPosition(offset: .infinity, scrollable: .nan, width: -.infinity) == .init(),
      "Invalid geometry was retained")
    try expect(
      DocumentReadingPosition(offset: 2000, scrollable: 1000).offset == 1000,
      "Position escaped the document")
  }
  check("PDF locators revisit the same file without resetting manual page navigation") {
    let path = root.appendingPathComponent("reading.pdf")
    var box = CGRect(x: 0, y: 0, width: 200, height: 300)
    let context = CGContext(path as CFURL, mediaBox: &box, nil)!
    for _ in 0..<3 {
      context.beginPDFPage(nil)
      context.endPDFPage()
    }
    context.closePDF()
    let view = PDFView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
    view.displayMode = .singlePage
    let navigation = PDFReadingNavigation()
    try expect(
      navigation.apply(view, url: path, locator: "page=2;scalars=4:7"), "Page request lost")
    let loaded = view.document!
    try expect(view.currentPage === loaded.page(at: 1), "Wrong initial page")
    view.go(to: loaded.page(at: 2)!)
    try expect(
      !navigation.apply(view, url: path, locator: "page=2;scalars=4:7")
        && view.currentPage === loaded.page(at: 2), "An update reset manual reading")
    try expect(
      navigation.apply(view, url: path, locator: "page=1")
        && view.currentPage === loaded.page(at: 0) && view.document === loaded,
      "A new locator in the same file was ignored or reloaded the file")
    for invalid in ["page=0", "page=4", "notpage=2", "page=999999999999999999999999"] {
      try expect(
        !navigation.apply(view, url: path, locator: invalid)
          && view.currentPage === loaded.page(at: 0), "Invalid locator changed the reading page")
    }
  }
  await checkAsync("Native scroll observation restores and retains a real clip-view position") {
    let initial = DocumentReadingPosition(offset: 400, scrollable: 1600, width: 400)
    var saved = initial
    let host = NSHostingView(
      rootView: ScrollView {
        VStack {
          Text("Long synthetic document").frame(height: 2000)
        }.frame(maxWidth: .infinity)
          .background(DocumentScrollObserver(position: saved) { saved = $0 })
      })
    host.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
    let window = NSWindow(
      contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    @MainActor func findScroll(_ view: NSView) -> NSScrollView? {
      if let scroll = view as? NSScrollView { return scroll }
      return view.subviews.lazy.compactMap(findScroll).first
    }
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    var scroll: NSScrollView?
    var lastGeometry: CGRect?
    var stableLayouts = 0
    while ProcessInfo.processInfo.systemUptime < deadline {
      host.layoutSubtreeIfNeeded()
      scroll = findScroll(host)
      if let scroll, let content = scroll.documentView {
        let geometry = CGRect(
          x: scroll.contentView.bounds.width, y: scroll.contentView.bounds.height,
          width: content.bounds.width, height: content.bounds.height)
        stableLayouts = lastGeometry == geometry ? stableLayouts + 1 : 0
        lastGeometry = geometry
        if stableLayouts >= 3 && scroll.contentView.bounds.minY > 0 { break }
      }
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    guard let scroll, let content = scroll.documentView else {
      throw SevraError("scroll_check", "The native scroll view did not attach")
    }
    let expected = initial.restoredOffset(
      width: scroll.contentView.bounds.width,
      scrollable: content.bounds.height - scroll.contentView.bounds.height)
    try expect(abs(scroll.contentView.bounds.minY - expected) < 1, "Clip view did not restore")
    for offset in [700.0, 900.0] {
      scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
      scroll.reflectScrolledClipView(scroll.contentView)
      // Bounds notifications are delivered through the native run loop. Wait
      // for the observed state, rather than assuming a hosted Mac delivers it
      // within10ms. A wrong or missing value still fails at the deadline.
      let observationDeadline = ProcessInfo.processInfo.systemUptime + 2
      while abs(saved.offset - offset) >= 1
        && ProcessInfo.processInfo.systemUptime < observationDeadline
      {
        try await Task.sleep(nanoseconds: 5_000_000)
      }
      try expect(
        abs(saved.offset - offset) < 1,
        "Manual scrolling was not retained: requested \(offset), clip \(scroll.contentView.bounds.minY), saved \(saved.offset), stable layouts \(stableLayouts)"
      )
    }
    withExtendedLifetime(window) {}
  }
  await checkAsync("Cancelled and superseded link reads cannot replace the current preview") {
    let (book, source, target) = try fixture()
    let first = try ReferenceDocument.read(source, workbook: book)
    let second = try ReferenceDocument.read(target, workbook: book)
    let gate = ReferenceReadGate<ReferenceDocument>()
    let session = ReferenceDocumentSession()
    let old = Task { await session.load(source.id) { _ in await gate.read() } }
    for _ in 0..<1000 {
      if await gate.ready { break }
      await Task.yield()
    }
    let started = await gate.ready
    try expect(started, "Old reader did not start")
    await session.load(target.id) { _ in second }
    await gate.finish(first)
    await old.value
    try expect(
      session.document?.body.originVersionID == target.id && !session.loading
        && session.failure == nil, "Late reader replaced the new preview")
    let stopped = ReferenceReadGate<ReferenceDocument>()
    let task = Task { await session.load(source.id) { _ in await stopped.read() } }
    for _ in 0..<1000 {
      if await stopped.ready { break }
      await Task.yield()
    }
    session.cancel()
    await stopped.finish(first)
    await task.value
    try expect(
      session.document == nil && !session.loading && session.failure == nil,
      "Cancelled cross-document reader changed state")
    await session.load(source.id) { _ in second }
    try expect(
      session.document == nil && session.failure != nil && !session.loading,
      "A wrong-origin result was published")
  }
  await checkAsync(
    "Mention browser pages have exact keysets and a failed next page preserves the current one"
  ) {
    let (book, _, target) = try fixture()
    for index in 0..<24 {
      _ = try book.addItem(
        category: "source", kind: "observation", title: "Mention \(index)",
        text: "[target](sevra://item/\(target.id))")
    }
    let query = ReferenceBrowserQuery(origin: target.id, revision: try book.revision())
    let browser = ReferenceBrowserSession()
    await browser.load(query, workbook: book)
    let first = browser.hits
    try expect(
      first.count == 20 && browser.nextCursor != nil && browser.page == 1,
      "Initial mention page was not bounded")
    await browser.load(query, step: 1) { _, _ in throw SevraError("test", "Synthetic read failure")
    }
    try expect(
      browser.hits == first && browser.failure != nil && browser.page == 1,
      "Failed next page discarded visible results")
    await browser.load(query, workbook: book, step: 1)
    try expect(
      browser.hits.count == 5 && browser.nextCursor == nil && browser.canGoBack,
      "Next mention page was lost")
    let last = browser.hits
    try expect(
      Set((first + last).map { $0["evidence"]["id"].text }).count == 25,
      "Mention pages repeated or skipped a version")
    await browser.load(query, workbook: book, step: -1)
    try expect(
      browser.hits == first && !browser.canGoBack && browser.page == 1,
      "Previous page did not restore the same keyset")
    let gate = ReferenceReadGate<Value>()
    let old = Task { await browser.load(query) { _, _ in await gate.read() } }
    for _ in 0..<1000 {
      if await gate.ready { break }
      await Task.yield()
    }
    let other = ReferenceBrowserQuery(
      origin: sourceID(first), revision: try book.revision(), historical: true, exact: true)
    await browser.load(other, workbook: book)
    let expected = browser.hits
    await gate.finish(.object(["hits": .array(first), "nextCursor": .string("stale")]))
    await old.value
    try expect(
      browser.loadedQuery == other && browser.hits == expected && browser.nextCursor != "stale",
      "Superseded mention query escaped its scope")
  }
}

private func sourceID(_ hits: [Value]) -> String { hits[0]["evidence"]["id"].text }
