import AppKit
import Foundation
import SevraCore
import SevraDocumentUI

private struct Failure: Error { let message: String }
private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
  if try !condition() { throw Failure(message: message) }
}
private func refuses(_ code: String, _ body: () throws -> Void) throws {
  do {
    try body()
    throw Failure(message: "Expected refusal: " + code)
  } catch let error as SevraError { try expect(error.code == code, "Wrong refusal: " + error.code) }
}
@MainActor private final class PreviousDelegate: NSObject, NSWindowDelegate {
  var allowed = true
  var requests = 0
  var closes = 0
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    requests += 1
    return allowed
  }
  func windowWillClose(_ notification: Notification) { closes += 1 }
}

@main private struct DocumentChecks {
  @MainActor static func main() async {
    setbuf(stdout, nil)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sevra-document-checks-" + UUID().uuidString)
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var passed = 0
    var failures: [String] = []
    func check(_ name: String, _ body: () throws -> Void) {
      do {
        try body()
        passed += 1
        print("PASS \(name)")
      } catch {
        failures.append(name + ": " + String(describing: error))
        print("FAIL \(name): \(error)")
      }
    }
    func checkAsync(_ name: String, _ body: () async throws -> Void) async {
      do {
        try await body()
        passed += 1
        print("PASS \(name)")
      } catch {
        failures.append(name + ": " + String(describing: error))
        print("FAIL \(name): \(error)")
      }
    }
    func fixture(title: String = "Packing proposal") throws -> (Workbook, Item) {
      let book = try Workbook.create(
        at: root.appendingPathComponent(UUID().uuidString + ".sevra"), title: "Document fixture")
      let source = try book.addItem(
        category: "source", kind: "assumption", title: "Packing assumption",
        text: "Estimated sample is 0.10 kg.", meaning: "estimate", status: "accepted",
        scenario: "plan-a")
      let document = try book.addItem(
        category: "record", kind: "document", title: title, text: "Use exactly 0.10 kg per sample.",
        data: .object(["owner": .string("Workshop")]), meaning: "estimate", scenario: "plan-a",
        inputs: [source.id])
      return (book, document)
    }
    func window() -> NSWindow {
      let window = NSWindow(
        contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 100),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      return window
    }

    check("A document edit is one atomic source-and-record revision") {
      let (book, original) = try fixture()
      let before = try book.counts()
      let edited = try book.editDocument(
        original.id, text: "Use exactly 0.25 kg per sample.", token: "once")
      let after = try book.counts()
      try expect(
        after["revision"].int == before["revision"].int! + 1, "Edit used multiple transactions")
      try expect(
        after["sources"].int == before["sources"].int! + 1 && after["records"] == before["records"],
        "Wrong current source/record counts")
      try expect(
        edited.logicalID == original.logicalID && edited.version == 2
          && edited.supersedes == original.id, "Broken document version chain")
      try expect(
        edited.meaning == "estimate" && edited.scenario == "plan-a" && edited.status == "draft"
          && edited.data == original.data, "Document semantics or metadata changed")
      try expect(try book.item(original.id).text == original.text, "Original text was overwritten")
      let allParents = try book.lineage(edited.id).filter { $0["child"].text == edited.id }.map {
        $0["parent"].text
      }
      try expect(
        Set(allParents).count == 2 && allParents.contains(original.id),
        "Human input lineage is missing")
      let sourceID = Set(allParents).first { $0 != original.id }!
      let submission = try book.item(sourceID)
      try expect(
        submission.category == "source" && submission.text == edited.text
          && submission.meaning == edited.meaning, "Human source changed meaning or bytes")
      try expect(try book.verify()["ok"] == .bool(true), "Invalid workbook")
    }
    check("Exact retries do not create another source or draft") {
      let (book, original) = try fixture()
      let first = try book.editDocument(original.id, text: "Revised", token: "retry")
      let counts = try book.counts()
      let repeated = try book.editDocument(original.id, text: "Revised", token: "retry")
      try expect(try first.id == repeated.id && book.counts() == counts, "Retry duplicated an edit")
      try refuses("idempotency") {
        _ = try book.editDocument(original.id, text: "Different", token: "retry")
      }
      try expect(try book.counts() == counts, "Refused retry left data")
    }
    check("Stale edits cannot leave orphan submissions or overwrite a competing version") {
      let (book, original) = try fixture()
      let other = try Workbook(book.url)
      let winning = try other.editDocument(original.id, text: "Other window text")
      let counts = try book.counts()
      try refuses("stale_revision") {
        _ = try book.editDocument(original.id, text: "My unsaved text")
      }
      try expect(
        try book.counts() == counts && book.item(original.logicalID).id == winning.id,
        "Failed edit mutated the workbook")
      let copy = try book.editDocument(original.id, text: "My unsaved text", separate: true)
      try expect(
        copy.logicalID != original.logicalID && copy.supersedes == nil && copy.status == "draft",
        "Separate draft replaced the other document")
      try expect(
        try book.item(original.logicalID).id == winning.id
          && book.item(copy.id).text == "My unsaved text", "One of the competing drafts was lost")
    }
    check("Only exact generated-document versions admit editing") {
      let (book, original) = try fixture()
      let before = try book.counts()
      try refuses("document_version") {
        _ = try book.editDocument(original.logicalID, text: "Wrong reference")
      }
      try expect(try book.counts() == before, "Logical reference created a submission")
      let file = root.appendingPathComponent(UUID().uuidString + ".txt")
      try Data("Original asset bytes".utf8).write(to: file)
      let source = try book.importFile(file)
      let attached = try book.addItem(
        category: "record", kind: "document", title: "Attached original", inputs: [source.id],
        assetID: source.assetID)
      let counts = try book.counts()
      for id in [source.id, attached.id] {
        try refuses("document_edit") {
          _ = try book.editDocument(id, text: "Not a text editor target")
        }
      }
      try expect(
        try book.counts() == counts && Data(contentsOf: file) == Data("Original asset bytes".utf8),
        "Original file was changed")
    }
    check("Bounds, cancellation and revision refusal leave all state unchanged") {
      let (book, original) = try fixture()
      let counts = try book.counts()
      try refuses("limit") {
        _ = try book.editDocument(original.id, text: String(repeating: "x", count: 16_000_001))
      }
      let cancellation = Cancellation()
      cancellation.cancel()
      try refuses("cancelled") {
        _ = try book.editDocument(original.id, text: "Cancelled", cancellation: cancellation)
      }
      try refuses("stale_revision") {
        _ = try book.editDocument(original.id, text: "Stale", expectedRevision: 0)
      }
      try expect(try book.counts() == counts, "Refusal left a partial human edit")
    }
    check("Maximum Unicode titles and explicit empty document bodies remain editable") {
      let (book, original) = try fixture(title: String(repeating: "é", count: 2048))
      let blank = try book.editDocument(original.id, text: "")
      try expect(
        blank.text.isEmpty && blank.title == original.title, "Empty edit or full title was lost")
      let copy = try book.editDocument(blank.id, text: "Café 👩🏽‍💻", separate: true)
      try expect(
        copy.title.utf8.count <= 4096 && !copy.title.contains("�") && copy.text == "Café 👩🏽‍💻",
        "Copy split Unicode or lost text")
    }
    check("Editor saves expose the current version for acceptance") {
      let (book, original) = try fixture()
      let editor = DocumentDraft(workbook: book, item: original)
      try expect(editor.begin(), "Cannot begin current draft")
      editor.update("Edited text")
      try expect(
        editor.end() && !editor.editing && !editor.dirty && editor.current.id != original.id,
        "Editor did not commit its current version")
      try refuses("stale_revision") { _ = try book.accept(original.id) }
      let accepted = try book.accept(editor.current.id)
      try expect(
        accepted.text == "Edited text" && accepted.meaning == "estimate",
        "Acceptance used the old text or changed meaning")
    }
    check("Refused save retains editing text and explicit copy preserves both versions") {
      let (book, original) = try fixture()
      let editor = DocumentDraft(workbook: book, item: original)
      try expect(editor.begin(), "Cannot begin")
      editor.update("Keep my changes")
      let other = try book.editDocument(original.id, text: "Competing edit")
      let counts = try book.counts()
      try expect(
        !editor.end() && editor.editing && editor.dirty && editor.text == "Keep my changes",
        "Failure discarded editor contents")
      try expect(editor.newerVersionID == other.id && editor.failure != nil, "Conflict was hidden")
      try expect(
        try editor.begin() && editor.text == "Keep my changes" && book.counts() == counts,
        "Re-entering reset the buffer or created evidence")
      try expect(
        editor.keepSeparate() && editor.end() && !editor.dirty,
        "Could not preserve an explicit copy")
      try expect(
        try book.item(original.logicalID).id == other.id
          && editor.current.logicalID != other.logicalID, "Copy replaced the competing version")
    }
    check("Opening an earlier citation does not silently retarget its editor") {
      let (book, original) = try fixture()
      let newer = try book.editDocument(original.id, text: "Newest")
      let editor = DocumentDraft(workbook: book, item: original)
      editor.refreshHead()
      try expect(
        editor.current.id == original.id && editor.text == original.text
          && editor.newerVersionID == newer.id, "Historical view was silently replaced")
      try expect(!editor.begin() && !editor.editing, "A stale citation entered editing")
    }
    await checkAsync("Debounced autosave coalesces typing and a later flush is idempotent") {
      let (book, original) = try fixture()
      let editor = DocumentDraft(workbook: book, item: original)
      let revision = try book.revision()
      editor.begin()
      editor.update("First partial")
      editor.update("Final typed text")
      try await Task.sleep(nanoseconds: 800_000_000)
      try expect(
        try !editor.dirty && editor.current.text == "Final typed text"
          && book.revision() == revision + 1, "Autosave missed or duplicated the final text")
      try expect(
        try editor.flush() && book.revision() == revision + 1, "Close flush duplicated autosave")
    }
    check("Window scope flushes pending text and refuses a conflicted close") {
      let (book, original) = try fixture()
      let editor = DocumentDraft(workbook: book, item: original)
      let scope = DocumentDraftScope()
      scope.register(editor)
      scope.register(editor)
      editor.begin()
      editor.update("First window save")
      try expect(
        scope.flush() && !editor.dirty && editor.current.version == 2,
        "Window close missed pending text")
      editor.update("My next edit")
      _ = try book.editDocument(editor.current.id, text: "Other writer")
      var revealed = false
      scope.revealFailure = { revealed = true }
      try expect(
        !scope.flush() && revealed && editor.dirty && editor.text == "My next edit",
        "Close did not protect unsaved changes")
      try expect(
        editor.keepSeparate() && scope.flush(), "Conflict resolution did not unblock close")
    }
    check("Application flush saves every live window without retaining closed editors") {
      let (book, original) = try fixture()
      let scope = DocumentDraftScope()
      var editor: DocumentDraft? = DocumentDraft(workbook: book, item: original)
      weak var reference = editor
      scope.register(editor!)
      editor!.begin()
      editor!.update("Quit immediately after typing")
      try expect(
        DocumentDraftScope.flushAll() && !editor!.dirty, "Application quit missed pending changes")
      try expect(
        try book.item(original.logicalID).text == "Quit immediately after typing",
        "Quit text was not durable")
      editor = nil
      try expect(reference == nil, "Registry retained its editor")
    }
    check("Native close guard preserves the original delegate and blocks refused saves") {
      let window = window()
      let original = PreviousDelegate()
      var savesAllowed = false
      let guarder = DocumentCloseGuard { savesAllowed }
      window.delegate = original
      guarder.attach(to: window)
      guarder.attach(to: window)
      window.orderFront(nil)
      window.performClose(nil)
      try expect(
        window.isVisible && original.requests == 0, "Refused save closed the native window")
      savesAllowed = true
      original.allowed = false
      window.performClose(nil)
      try expect(window.isVisible && original.requests == 1, "Original delegate veto was lost")
      original.allowed = true
      window.performClose(nil)
      try expect(
        !window.isVisible && original.requests == 2 && original.closes == 1,
        "Original close notification was not forwarded")
    }
    check("Moving a close guard restores the first window delegate") {
      let first = window()
      let second = window()
      let previous = PreviousDelegate()
      first.delegate = previous
      let guarder = DocumentCloseGuard { true }
      guarder.attach(to: first)
      guarder.attach(to: second)
      try expect(
        first.delegate === previous && second.delegate === guarder,
        "Guard left a detached window without its delegate")
    }
    print(
      "\(passed) passed; \(failures.count) failed. Programmatic lifecycle checks do not replace visible editor journeys."
    )
    exit(failures.isEmpty ? 0 : 1)
  }
}
