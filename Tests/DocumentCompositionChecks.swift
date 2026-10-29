import CryptoKit
import Foundation
import SevraCore

private func compositionFixture(at root: URL) throws -> (
  book: Workbook, source: Item, run: String, receipt: String, text: String
) {
  let book = try Workbook.create(
    at: root.appendingPathComponent("Composition-" + identifier() + ".sevra"), title: "Composition")
  let request = try book.startAgentRequest(
    "Create a receiving report with the exact inspection labels.", conversation: "main",
    model: "fixture")
  let text = "X-CHECK-14 | 0.10 kg\r\nCafe\u{301} 👩🏽‍💻\0HOLD: clearance 0.25 mm"
  let source = try book.addItem(
    category: "source", kind: "document", title: "Receiving original", text: text,
    status: "accepted")
  try book.index(source.id, chunks: [Chunk(text, locator: "page 2")])
  let arguments: Value = .object(["id": .string(source.id)])
  let receipt = try book.prepareToolCall(
    runID: request.runID, callID: "original", tool: "read", arguments: arguments)
  let result = try WorkbookTools(book, runID: request.runID).execute("read", arguments)
  _ = try book.completeToolCall(receipt, result: result)
  return (book, source, request.runID, receipt, text)
}

private func originalCopy(
  _ fixture: (book: Workbook, source: Item, run: String, receipt: String, text: String)
) throws -> DocumentCopy {
  try fixture.book.documentCopy(
    receiptID: fixture.receipt, path: ["chunks", "0", "body"], startScalar: 0,
    scalarCount: fixture.text.unicodeScalars.count, runID: fixture.run)
}

func checkDocumentComposition(at root: URL) {
  check(
    "manual revisions keep old copy evidence without claiming edited text is still an exact copy"
  ) {
    let f = try compositionFixture(at: root)
    let copy = try originalCopy(f)
    let original = try f.book.saveComposedDraft(
      title: "Original quote", parts: [.init(copy: copy.reference)], runID: f.run)
    let replacement =
      "Operator correction\n" + f.text.replacingOccurrences(of: "0.10", with: "0.12")
    let revised = try f.book.editDocument(original.id, text: replacement)
    try expect(try f.book.verify()["ok"] == .bool(true))
    try expect(revised.data["documentComposition"] == .null)
    try expect(revised.text == replacement && revised.meaning == "estimate")
    try expect(try f.book.item(original.id).data == original.data)
    try expect(try f.book.lineage(revised.id).contains { $0["parent"].text == original.id })
    let accepted = try f.book.accept(revised.id)
    let separate = try f.book.editDocument(original.id, text: f.text, separate: true)
    try expect(separate.data["documentComposition"] == .null)
    try expect(accepted.status == "accepted" && separate.status == "draft")
    try expect(try f.book.verify()["ok"] == .bool(true))
    let archive = root.appendingPathComponent(identifier() + ".sevraz")
    try f.book.export(to: archive)
    let restored = try Workbook.openArchive(
      archive, at: root.appendingPathComponent(identifier() + ".sevra"))
    try expect(try restored.item(accepted.id).text == replacement)
    try expect(try restored.verify()["ok"] == .bool(true))
  }
  check("source-bound composition preserves exact Unicode bytes and original version lineage") {
    let f = try compositionFixture(at: root)
    let copy = try originalCopy(f)
    try expect(Data(copy.text.utf8) == Data(f.text.utf8))
    try expect(copy.sourceVersionID == f.source.id && copy.locator == "page 2; offset=0")
    let prefix = "# Receiving\n"
    let suffix = "\nCheck before accepting."
    try f.book.setOpeningBalance(
      subject: "stock", quantity: "20", effective: "2026-01-01", sourceID: f.source.id)
    let revision = try f.book.revision()
    let draft = try f.book.saveComposedDraft(
      title: "Receiving",
      parts: [.init(text: prefix), .init(copy: copy.reference), .init(text: suffix)],
      runID: f.run, expectedRevision: revision)
    try expect(Data(draft.text.utf8) == Data((prefix + f.text + suffix).utf8))
    try expect(draft.status == "draft" && draft.meaning == "estimate" && draft.kind == "document")
    try expect(try f.book.revision() == revision + 1)
    try expect(try f.book.lineage(draft.id).contains { $0["parent"].text == f.source.id })
    let saved = draft.data["documentComposition"]["copies"].array
    try expect(saved.count == 1)
    try expect(saved[0]["sourceVersionID"].text == f.source.id)
    let hash = SHA256.hash(data: Data(f.text.utf8)).map { String(format: "%02x", $0) }.joined()
    try expect(saved[0]["reference"]["sha256"].text == hash)
    try expect(saved[0]["outputStartScalar"].int == prefix.unicodeScalars.count)
    try expect(try f.book.item(f.source.id).status == "accepted")
    try expect(try f.book.balance(subject: "stock")["quantity"].text == "20")
    try expect(try f.book.verify()["ok"] == .bool(true))
  }
  check("receipt copy survives changed extraction, superseding source, review and portable export")
  {
    let f = try compositionFixture(at: root)
    let copy = try originalCopy(f)
    try f.book.index(f.source.id, chunks: [Chunk("Re-extracted with different line breaks")])
    let newer = try f.book.addItem(
      category: "source", kind: "document", title: "Receiving correction", text: "X-CHECK-99",
      status: "accepted", supersedes: f.source.id)
    let original = try originalCopy(f)
    try expect(Data(original.text.utf8) == Data(f.text.utf8))
    try expect(original.sourceVersionID == f.source.id && original.sourceVersionID != newer.id)
    let draft = try f.book.saveComposedDraft(
      title: "Historical copy", parts: [.init(copy: copy.reference)], runID: f.run)
    let declined = try f.book.withdrawDraft(draft.id)
    try expect(declined.status == "rejected" && declined.data == draft.data)
    let returned = try f.book.undoItem(declined.id)
    try expect(returned.status == "draft" && returned.data == draft.data)
    let accepted = try f.book.accept(returned.id)
    try expect(accepted.meaning == "estimate" && accepted.status == "accepted")
    try expect(accepted.data == draft.data && Data(accepted.text.utf8) == Data(f.text.utf8))
    let undone = try f.book.undoItem(accepted.id)
    try expect(undone.data == draft.data && Data(undone.text.utf8) == Data(f.text.utf8))
    try expect(undone.status == "rejected")
    try f.book.finishAgentRun(f.run, status: "complete", steps: 1, metrics: .object([:]))
    try expect(try f.book.verify()["ok"] == .bool(true))
    let archive = root.appendingPathComponent("Composition-" + identifier() + ".sevraz")
    try f.book.export(to: archive)
    if let fixture = ProcessInfo.processInfo.environment["SEVRA_COMPOSITION_FIXTURE"] {
      try FileManager.default.copyItem(at: archive, to: URL(fileURLWithPath: fixture))
    }
    let restored = try Workbook.openArchive(
      archive, at: root.appendingPathComponent("Restored-" + identifier() + ".sevra"))
    try expect(Data(try restored.item(draft.id).text.utf8) == Data(f.text.utf8))
    try expect(
      try restored.documentCopy(
        receiptID: f.receipt, path: copy.reference.path, startScalar: 0,
        scalarCount: f.text.unicodeScalars.count, runID: f.run
      ).reference == copy.reference)
    try expect(try restored.verify()["ok"] == .bool(true))
  }
  check("copy resolution rejects wrong scope, incomplete reads, invalid paths and scalar ranges") {
    let f = try compositionFixture(at: root)
    func span(_ start: Int, _ count: Int, _ path: [String] = ["chunks", "0", "body"]) throws {
      _ = try f.book.documentCopy(
        receiptID: f.receipt, path: path, startScalar: start, scalarCount: count, runID: f.run)
    }
    try refuses("document_copy_range") { try span(-1, 1) }
    try refuses("document_copy_range") { try span(0, 0) }
    try refuses("document_copy_range") { try span(Int.max, 1) }
    try refuses("document_copy_range") { try span(0, Int.max) }
    for path in [
      ["item", "title"], ["chunks", "00", "body"], ["chunks", "-1", "body"],
      ["chunks", "9", "body"],
    ] {
      try refuses("document_copy_path") { try span(0, 1, path) }
    }
    let itemCopy = try f.book.documentCopy(
      receiptID: f.receipt, path: ["item", "text"], startScalar: 0, scalarCount: 1, runID: f.run)
    try expect(itemCopy.text == "X")
    try refuses("document_copy_scope") {
      _ = try f.book.documentCopy(
        receiptID: f.receipt, path: ["item", "text"], startScalar: 0, scalarCount: 1, runID: "other"
      )
    }
    let arguments: Value = .object(["id": .string(f.source.id)])
    let prepared = try f.book.prepareToolCall(
      runID: f.run, callID: "pending", tool: "read", arguments: arguments)
    try refuses("document_copy_scope") {
      _ = try f.book.documentCopy(
        receiptID: prepared, path: ["item", "text"], startScalar: 0, scalarCount: 1, runID: f.run)
    }
    _ = try f.book.completeToolCall(
      prepared, result: .object(["error": .string("failed")]), failed: true)
    try refuses("document_copy_scope") {
      _ = try f.book.documentCopy(
        receiptID: prepared, path: ["item", "text"], startScalar: 0, scalarCount: 1, runID: f.run)
    }
    let other = try f.book.prepareToolCall(
      runID: f.run, callID: "search", tool: "search",
      arguments: .object(["query": .string("receiving")]))
    _ = try f.book.completeToolCall(other, result: .object(["item": try encoded(f.source)]))
    try refuses("document_copy_scope") {
      _ = try f.book.documentCopy(
        receiptID: other, path: ["item", "text"], startScalar: 0, scalarCount: 1, runID: f.run)
    }
    let parent = try f.book.addMessage("Separate discussion", role: "user")
    let tangent = try f.book.tangent(title: "Separate", parentMessage: parent)
    try refuses("tool_scope") {
      _ = try f.book.documentCopy(
        receiptID: f.receipt, path: ["item", "text"], startScalar: 0, scalarCount: 1,
        runID: f.run, conversation: tangent)
    }
  }
  check("composition failures roll back atomically and idempotent retries survive terminal runs") {
    let f = try compositionFixture(at: root)
    let copy = try originalCopy(f)
    let wrong = DocumentCopyReference(
      receiptID: f.receipt, path: copy.reference.path, startScalar: 0,
      scalarCount: copy.reference.scalarCount, sha256: String(repeating: "0", count: 64))
    let revision = try f.book.revision()
    let count = try f.book.items().count
    try refuses("document_copy_hash") {
      _ = try f.book.saveComposedDraft(
        title: "Atomic", parts: [.init(copy: copy.reference), .init(copy: wrong)], runID: f.run)
    }
    try expect(try f.book.revision() == revision && f.book.items().count == count)
    try refuses("stale_revision") {
      _ = try f.book.saveComposedDraft(
        title: "Stale", parts: [.init(copy: copy.reference)], runID: f.run,
        expectedRevision: revision - 1)
    }
    try expect(try f.book.revision() == revision)
    let token = identifier()
    let parts = [DocumentPart(copy: copy.reference)]
    let draft = try f.book.saveComposedDraft(
      title: "Retry", parts: parts, runID: f.run, token: token, expectedRevision: revision)
    try f.book.finishAgentRun(f.run, status: "complete", steps: 1, metrics: .object([:]))
    let terminalRevision = try f.book.revision()
    let retry = try f.book.saveComposedDraft(
      title: "Retry", parts: parts, runID: f.run, token: token, expectedRevision: revision)
    try expect(retry.id == draft.id && f.book.revision() == terminalRevision)
    try refuses("idempotency") {
      _ = try f.book.saveComposedDraft(title: "Changed", parts: parts, runID: f.run, token: token)
    }
    try refuses("document_copy_scope") {
      _ = try f.book.saveComposedDraft(title: "New after completion", parts: parts, runID: f.run)
    }
    try expect(try f.book.revision() == terminalRevision)
  }
  check("composition validates union shape, bounded sizes and cancellation before mutation") {
    let f = try compositionFixture(at: root)
    let copy = try originalCopy(f)
    let revision = try f.book.revision()
    let malformed: [Value] = [
      .object([:]), .object(["text": .string("invented"), "copy": try encoded(copy.reference)]),
    ]
    for value in malformed {
      let part = try JSONDecoder().decode(DocumentPart.self, from: Data(value.json().utf8))
      try refuses("document_parts") {
        _ = try f.book.saveComposedDraft(title: "Malformed", parts: [part], runID: f.run)
      }
    }
    for parts in [
      [], Array(repeating: DocumentPart(text: ""), count: 65),
      [.init(text: String(repeating: "x", count: 64001))],
      [.init(text: String(repeating: "x", count: 64000)), .init(copy: copy.reference)],
    ] {
      try refuses("document_parts") {
        _ = try f.book.saveComposedDraft(title: "Oversized", parts: parts, runID: f.run)
      }
    }
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses("cancelled") {
      _ = try f.book.saveComposedDraft(
        title: "Cancelled", parts: [.init(copy: copy.reference)], runID: f.run,
        cancellation: cancelled)
    }
    try refuses("cancelled") {
      _ = try f.book.documentCopy(
        receiptID: f.receipt, path: copy.reference.path, startScalar: 0, scalarCount: 1,
        runID: f.run, cancellation: cancelled)
    }
    try expect(try f.book.revision() == revision)
    let prose = try f.book.saveComposedDraft(
      title: "Prose with evidence", parts: [.init(text: "Interpretation, not a literal copy.")],
      inputs: [f.source.id], runID: f.run)
    try expect(prose.data["documentComposition"]["copies"].array.isEmpty)
    try expect(prose.text == "Interpretation, not a literal copy.")
    try expect(try f.book.verify()["ok"] == .bool(true))
  }
  check("copy inspection bounds UTF-8 bytes and stored receipt size before decoding") {
    let f = try compositionFixture(at: root)
    let text = String(repeating: "👩🏽‍💻", count: 1500)
    let source = try f.book.addItem(
      category: "source", kind: "document", title: "Wide Unicode", text: text)
    let arguments: Value = .object(["id": .string(source.id)])
    let receipt = try f.book.prepareToolCall(
      runID: f.run, callID: "wide", tool: "read", arguments: arguments)
    _ = try f.book.completeToolCall(
      receipt, result: WorkbookTools(f.book, runID: f.run).execute("read", arguments))
    try refuses("document_copy_limit") {
      _ = try f.book.documentCopy(
        receiptID: receipt, path: ["chunks", "0", "body"], startScalar: 0,
        scalarCount: text.unicodeScalars.count, runID: f.run)
    }
    let small = try f.book.documentCopy(
      receiptID: receipt, path: ["chunks", "0", "body"], startScalar: 0,
      scalarCount: 4, runID: f.run)
    try expect(Data(small.text.utf8) == Data("👩🏽‍💻".utf8))
    let huge = try f.book.prepareToolCall(
      runID: f.run, callID: "huge", tool: "read", arguments: arguments)
    _ = try f.book.completeToolCall(
      huge,
      result: .object([
        "item": try encoded(source), "padding": .string(String(repeating: "x", count: 128001)),
      ]))
    try refuses("document_copy_limit") {
      _ = try f.book.documentCopy(
        receiptID: huge, path: ["item", "text"], startScalar: 0,
        scalarCount: 1, runID: f.run)
    }
    let alias = try f.book.prepareToolCall(
      runID: f.run, callID: "alias", tool: "read", arguments: arguments)
    var info = try encoded(source).object
    info["id"] = .string(source.logicalID)
    _ = try f.book.completeToolCall(alias, result: .object(["item": .object(info)]))
    try refuses("document_copy_scope") {
      _ = try f.book.documentCopy(
        receiptID: alias, path: ["item", "text"], startScalar: 0,
        scalarCount: 1, runID: f.run)
    }
    let foreign = try Workbook.create(
      at: root.appendingPathComponent(identifier() + ".sevra"), title: "Other")
    try refuses("tool_scope") {
      _ = try foreign.documentCopy(
        receiptID: f.receipt, path: ["item", "text"], startScalar: 0,
        scalarCount: 1, runID: f.run)
    }
  }
  check("workbook verification detects modified copied bytes and provenance") {
    for field in ["body", "data"] {
      let f = try compositionFixture(at: root)
      let copy = try originalCopy(f)
      let draft = try f.book.saveComposedDraft(
        title: "Check integrity", parts: [.init(copy: copy.reference)], runID: f.run)
      let tamper = Process()
      tamper.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
      let value =
        field == "body"
        ? "'invented'" : "json_set(data,'$.documentComposition.copies[0].outputStartScalar',99999)"
      tamper.arguments = [
        f.book.url.appendingPathComponent("workbook.sqlite").path,
        "UPDATE items SET \(field)=\(value) WHERE id='\(draft.id)';",
      ]
      try tamper.run()
      tamper.waitUntilExit()
      try expect(tamper.terminationStatus == 0)
      try refuses("integrity") { _ = try f.book.verify() }
    }
  }
  check("business data fields cannot be mistaken for composed-document metadata") {
    let f = try compositionFixture(at: root)
    let field: Value = .object(["documentComposition": .string("Supplier-provided field")])
    _ = try f.book.addItem(
      category: "source", kind: "document", title: "Imported source data", data: field)
    _ = try f.book.addItem(
      category: "record", kind: "analysis", title: "Business field", data: field,
      inputs: [f.source.id])
    _ = try f.book.createDataset(
      title: "Imported column",
      columns: [.init(id: "documentComposition", title: "documentComposition", type: "text")],
      rows: [["documentComposition": .string("Original field value")]], sourceID: f.source.id)
    try expect(try f.book.verify()["ok"] == .bool(true))
    _ = try f.book.addItem(
      category: "record", kind: "document", title: "Malformed reserved metadata", data: field,
      inputs: [f.source.id])
    try refuses("integrity") { _ = try f.book.verify() }
  }
}
