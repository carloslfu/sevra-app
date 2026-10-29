import Foundation

@testable import SevraCore

/// Inject faults on this connection without adding an untrusted object to the
/// persisted schema. Main-schema alterations now refuse before any mutation.
func faultSQL(_ book: Workbook, _ script: String) throws -> String {
  let sql = script.replacingOccurrences(of: "CREATE TRIGGER ", with: "CREATE TEMP TRIGGER ")
    .replacingOccurrences(of: "DROP TRIGGER IF EXISTS ", with: "DROP TRIGGER IF EXISTS temp.")
  let scoped =
    sql.contains("DROP TRIGGER IF EXISTS")
    ? sql
    : sql.replacingOccurrences(of: "DROP TRIGGER ", with: "DROP TRIGGER temp.")
  try book.db.script(scoped)
  return ""
}

func referenceSQL(_ book: Workbook, _ script: String) throws -> String {
  let process = Process()
  let input = Pipe()
  let output = Pipe()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
  process.arguments = [book.url.appendingPathComponent("workbook.sqlite").path]
  process.standardInput = input
  process.standardOutput = output
  try process.run()
  try input.fileHandleForWriting.write(contentsOf: Data(script.utf8))
  try input.fileHandleForWriting.close()
  let bytes = output.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  try expect(process.terminationStatus == 0, "Reference fixture SQL failed")
  return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func selection(
  _ label: String, in text: String, target: ReferenceTarget? = nil, id: String? = nil
) -> ReferenceSelection {
  let range = text.range(of: label)!
  return ReferenceSelection(
    startScalar: text[..<range.lowerBound].unicodeScalars.count,
    scalarCount: text[range].unicodeScalars.count, target: target, id: id)
}

func checkReferences(at root: URL) {
  check("current-format reopening preserves saved bindings and projections") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReferenceV5.sevra"), title: "V5")
    let target = try book.addItem(category: "source", kind: "observation", title: "Target")
    let origin = try book.addItem(
      category: "source", kind: "observation", title: "Origin", text: "mention",
      references: [
        selection("mention", in: "mention", target: .init(mode: .pinned, identity: target.id))
      ])
    let saved = try book.referenceSnapshot(origin.id)
    let before = try referenceSQL(
      book, "SELECT * FROM items; SELECT * FROM reference_sets; SELECT * FROM reference_bindings;")
    let opened = try Workbook(book.url)
    try expect(
      try referenceSQL(
        opened,
        "SELECT * FROM items; SELECT * FROM reference_sets; SELECT * FROM reference_bindings;")
        == before)
    try expect(try opened.referenceSnapshot(origin.id) == saved)
    try expect(try opened.referenceLinks(target.id, direction: .incoming)["hits"].array.count == 1)
    try expect(try opened.verify()["ok"] == .bool(true))
  }
  check("corrupted derived backlink rows are detected and repaired without reinterpretation") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReferenceRepair.sevra"), title: "Repair")
    let target = try book.addItem(category: "source", kind: "observation", title: "Target")
    let origin = try book.addItem(
      category: "source", kind: "observation", title: "Origin",
      text: "[[Later]] [target](sevra://item/\(target.id))")
    let saved = try book.referenceSnapshot(origin.id)
    _ = try referenceSQL(book, "UPDATE reference_index SET current_origin=0;")
    try refuses("integrity") { _ = try book.verify() }
    _ = try book.addItem(category: "source", kind: "observation", title: "Later")
    let sourceCount = try book.counts()["sources"]
    try book.rebuildReferenceIndex()
    try expect(
      try book.referenceSnapshot(origin.id) == saved && book.counts()["sources"] == sourceCount)
    try expect(try book.referenceLinks(target.id, direction: .incoming)["hits"].array.count == 1)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("automatic parse failure rolls back body, annotation, projection and operation together") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReferenceAutoFault.sevra"), title: "Fault")
    let before = try book.counts()
    _ = try faultSQL(
      book,
      "CREATE TRIGGER injected_auto_failure BEFORE INSERT ON reference_bindings WHEN NEW.ordinal=1 BEGIN SELECT RAISE(ABORT,'injected'); END;"
    )
    defer { _ = try? faultSQL(book, "DROP TRIGGER IF EXISTS injected_auto_failure;") }
    try refuses("database") {
      _ = try book.addItem(
        category: "source", kind: "observation", title: "AtomicFault", text: "[[one]] [[two]]",
        token: "automatic-fault")
    }
    try expect(try book.counts() == before && book.search("AtomicFault").hits.isEmpty)
    try expect(
      try referenceSQL(
        book,
        "SELECT count(*) FROM reference_coverage; SELECT count(*) FROM reference_index; SELECT count(*) FROM operations WHERE id='automatic-fault';"
      ) == "0\n0\n0")
    _ = try faultSQL(book, "DROP TRIGGER injected_auto_failure;")
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("automatic parse integrity ties a saved binding to its declared stable route") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReferenceRouteIntegrity.sevra"), title: "Routes")
    let target = try book.addItem(category: "source", kind: "observation", title: "Original")
    let other = try book.addItem(category: "source", kind: "observation", title: "Other")
    let origin = try book.addItem(
      category: "source", kind: "observation", title: "Origin",
      text: "[original](sevra://item/\(target.id))")
    let snapshot = try book.referenceSnapshot(origin.id)
    _ = try referenceSQL(
      book,
      "UPDATE reference_bindings SET target_version='\(other.id)',target_logical='\(other.logicalID)' WHERE set_id='\(snapshot.id!)'; UPDATE items SET data=json_set(data,'$.references[0].target_version','\(other.id)','$.references[0].target_logical','\(other.logicalID)') WHERE id='\(snapshot.sourceID!)';"
    )
    var correctRefusal = false
    do { _ = try book.verify() } catch {
      correctRefusal =
        (error as? SevraError)?.message == "A parsed stable route changed its target."
    }
    try expect(correctRefusal)
    _ = try referenceSQL(
      book,
      "UPDATE reference_bindings SET target_version='\(target.id)',target_logical='\(target.logicalID)' WHERE set_id='\(snapshot.id!)'; UPDATE items SET data=json_set(data,'$.references[0].target_version','\(target.id)','$.references[0].target_logical','\(target.logicalID)') WHERE id='\(snapshot.sourceID!)';"
    )
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("reference identity survives rename, duplicate title and reopen; pins remain historical") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReferenceIdentity.sevra"), title: "References")
    let target = try book.addItem(
      category: "source", kind: "observation", title: "Quote", text: "Original 0.10 kg")
    let text = "\0👩🏽‍💻 See Cafe\u{301}\r\nthen pinned."
    let origin = try book.addItem(
      category: "source", kind: "observation", title: "Notes", text: text)
    let beforeRecords = try book.counts()["records"]
    let snapshot = try book.annotateReferences(
      origin.id,
      selections: [
        selection("Cafe\u{301}", in: text, target: .init(mode: .live, identity: target.logicalID)),
        selection("pinned", in: text, target: .init(mode: .pinned, identity: target.id)),
      ], expectedSnapshotID: nil)
    try expect(snapshot.coverage == "partial" && snapshot.references.count == 2)
    try expect(snapshot.references[0].label.utf8.elementsEqual("Cafe\u{301}".utf8))
    try expect(try book.item(origin.id) == origin && book.item(origin.logicalID).id == origin.id)
    try expectTechnicalReference(book, origin: origin.id, annotation: snapshot.sourceID!)
    try expect(try book.counts()["records"] == beforeRecords)
    let revised = try book.addItem(
      category: "source", kind: "observation", title: "Renamed quote", text: "Corrected 0.25 kg",
      supersedes: target.id)
    _ = try book.addItem(category: "source", kind: "observation", title: "Quote", text: "Unrelated")
    let reopened = try Workbook(book.url)
    try expect(reopened.id == book.id && reopened.referenceSnapshot(origin.id) == snapshot)
    let live = try reopened.resolveReference(snapshot.references[0].id, originVersionID: origin.id)
    let pinned = try reopened.resolveReference(
      snapshot.references[1].id, originVersionID: origin.id)
    try expect(live["destination"]["id"].text == revised.id)
    try expect(
      pinned["destination"]["id"].text == target.id && pinned["destination"]["is_current"].int == 0)
    try expect(pinned["label"].text == "pinned" && pinned["destination"]["title"].text == "Quote")
    try book.rebuildSearch()
    try expect(try book.referenceSnapshot(origin.id) == snapshot)
    try expect(try book.verify()["ok"] == .bool(true))
  }

  check("unresolved references never guess; correction history and competing writers are explicit")
  {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReferenceUnresolved.sevra"), title: "Unresolved")
    let origin = try book.addItem(
      category: "source", kind: "observation", title: "Notes", text: "Later")
    let initial = [selection("Later", in: origin.text)]
    let first = try book.annotateReferences(
      origin.id, selections: initial, expectedSnapshotID: nil, token: "first")
    let otherWriter = try Workbook(book.url)
    let target = try book.addItem(category: "source", kind: "observation", title: "Later")
    _ = try book.addItem(category: "source", kind: "observation", title: "Later")
    try expect(try book.referenceSnapshot(origin.id) == first)
    try expect(
      try book.resolveReference(first.references[0].id, originVersionID: origin.id)["destination"]
        == .null)
    let resolved = [
      selection(
        "Later", in: origin.text, target: .init(mode: .pinned, identity: target.id),
        id: first.references[0].id)
    ]
    let second = try book.annotateReferences(
      origin.id, selections: resolved, expectedSnapshotID: first.id, token: "resolve")
    let counts = try book.counts()
    try refuses("stale_reference") {
      _ = try otherWriter.annotateReferences(
        origin.id, selections: [], expectedSnapshotID: first.id)
    }
    try expect(try book.counts() == counts)
    let third = try book.annotateReferences(
      origin.id, selections: [], expectedSnapshotID: second.id)
    try expect(third.references.isEmpty && third.version == 3)
    try expect(
      try book.annotateReferences(
        origin.id, selections: resolved, expectedSnapshotID: first.id, token: "resolve") == second)
    try refuses("idempotency") {
      _ = try book.annotateReferences(
        origin.id, selections: [], expectedSnapshotID: nil, token: "first")
    }
    try expect(try book.referenceSnapshot(origin.id, snapshotID: first.id) == first)
    let page = try book.referenceHistory(origin.id, limit: 1)
    try expect(
      page["versions"].array.first?["id"].text == third.id && page["nextBeforeVersion"].int == 3)
    let next = try book.referenceHistory(
      origin.id, beforeVersion: page["nextBeforeVersion"].int, limit: 1)
    try expect(next["versions"].array.first?["id"].text == second.id)
    try expect(try book.item(origin.id) == origin && book.verify()["ok"] == .bool(true))
  }

  check("foreign references stay external; stable-target modes reject names and routes") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReferenceForeign.sevra"), title: "Foreign")
    let target = try book.addItem(
      category: "source", kind: "observation", title: "Quote", text: "Private local body")
    let origin = try book.addItem(
      category: "source", kind: "observation", title: "Note", text: "Quote")
    let foreign = try book.annotateReferences(
      origin.id,
      selections: [
        selection(
          "Quote", in: origin.text,
          target: .init(mode: .pinned, identity: target.id, workbookID: "different-workbook"))
      ], expectedSnapshotID: nil)
    let resolved = try book.resolveReference(foreign.references[0].id, originVersionID: origin.id)
    try expect(resolved["resolution"].text == "external" && resolved["destination"] == .null)
    for target in [
      ReferenceTarget(mode: .pinned, identity: target.logicalID),
      .init(mode: .live, identity: target.id), .init(mode: .pinned, identity: "Quote"),
    ] {
      try refuses("reference_target") {
        _ = try book.annotateReferences(
          origin.id, selections: [selection("Quote", in: origin.text, target: target)],
          expectedSnapshotID: foreign.id)
      }
    }
    try refuses("reference_identity") {
      _ = try book.annotateReferences(
        origin.id,
        selections: [
          selection(
            "Quote", in: origin.text, target: .init(mode: .pinned, identity: "sevra://item/abc"))
        ], expectedSnapshotID: foreign.id)
    }
    try refuses("reference_origin") { _ = try book.referenceSnapshot(origin.logicalID) }
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses("cancelled") {
      _ = try book.resolveReference(
        foreign.references[0].id, originVersionID: origin.id, cancellation: cancelled)
    }
    try expect(try book.verify()["ok"] == .bool(true))
  }

  check("authored text and references commit atomically with edit retry and stale refusal") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReferenceEdit.sevra"), title: "Edit")
    let input = try book.addItem(category: "source", kind: "observation", title: "Quote")
    let original = try book.addItem(
      category: "record", kind: "document", title: "Summary", text: "See quote", inputs: [input.id],
      references: [
        selection("quote", in: "See quote", target: .init(mode: .pinned, identity: input.id))
      ])
    let first = try book.referenceSnapshot(original.id)
    try refuses("reference_annotation") {
      _ = try book.annotateReferences(original.id, selections: [], expectedSnapshotID: first.id)
    }
    let changed = "Updated: See quote."
    let entries = [
      selection(
        "quote", in: changed, target: .init(mode: .pinned, identity: input.id),
        id: first.references[0].id)
    ]
    let edited = try book.editDocument(
      original.id, text: changed, token: "linked-edit", references: entries)
    let second = try book.referenceSnapshot(edited.id)
    try expect(
      second.references[0].id == first.references[0].id && second.references[0].startScalar == 13)
    let counts = try book.counts()
    try expect(
      try book.editDocument(original.id, text: changed, token: "linked-edit", references: entries)
        .id == edited.id)
    try expect(try book.counts() == counts)
    try refuses("stale_revision") { _ = try book.editDocument(original.id, text: "Other") }
    try refuses("reference_target") {
      _ = try book.editDocument(
        edited.id, text: "Bad quote",
        references: [
          selection("quote", in: "Bad quote", target: .init(mode: .pinned, identity: "missing"))
        ])
    }
    try expect(try book.counts() == counts && book.item(edited.logicalID).id == edited.id)
    try expect(
      try book.referenceSnapshot(original.id) == first
        && book.referenceSnapshot(edited.id) == second)
    try expect(try book.verify()["ok"] == .bool(true))
  }

  check("status changes and Undo preserve bindings; free-text edits cannot assert stale spans") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReferenceUndo.sevra"), title: "Undo")
    let input = try book.addItem(category: "source", kind: "observation", title: "Quote")
    let original = try book.addItem(
      category: "record", kind: "document", title: "Summary", text: "quote", meaning: "estimate",
      inputs: [input.id],
      references: [
        selection("quote", in: "quote", target: .init(mode: .pinned, identity: input.id))
      ])
    let first = try book.referenceSnapshot(original.id)
    let accepted = try book.accept(original.id)
    try expect(try book.referenceSnapshot(accepted.id).references == first.references)
    let restored = try book.undoItem(accepted.id)
    try expect(try book.referenceSnapshot(restored.id).references == first.references)
    try expect(restored.status == "rejected")
    let newDraft = try book.editDocument(restored.id, text: "quote", separate: true)
    let withdrawn = try book.withdrawDraft(newDraft.id)
    try expect(try book.referenceSnapshot(withdrawn.id).references == first.references)
    let draft = try book.undoItem(withdrawn.id)
    let edited = try book.editDocument(draft.id, text: "Everything changed")
    try expect(
      try book.referenceSnapshot(edited.id).coverage == "ready"
        && book.referenceSnapshot(edited.id).references.isEmpty)
    let undone = try book.undoItem(edited.id)
    try expect(undone.text == "quote" && undone.meaning == "estimate")
    try expect(try book.referenceSnapshot(undone.id).references == first.references)
    let separate = try book.editDocument(undone.id, text: "quote", separate: true)
    try expect(try book.referenceSnapshot(separate.id).references == first.references)
    try expect(try book.verify()["ok"] == .bool(true))
  }

  check("failed multi-reference publication rolls back annotation Source, edges, head and receipt")
  {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReferenceFault.sevra"), title: "Fault")
    let origin = try book.addItem(
      category: "source", kind: "observation", title: "Notes", text: "one two")
    let first = try book.annotateReferences(
      origin.id, selections: [selection("one", in: origin.text)], expectedSnapshotID: nil)
    let counts = try book.counts()
    _ = try faultSQL(
      book,
      "CREATE TRIGGER injected_reference_failure BEFORE INSERT ON reference_bindings WHEN NEW.ordinal=1 BEGIN SELECT RAISE(ABORT,'injected reference publication failure'); END;"
    )
    defer { _ = try? faultSQL(book, "DROP TRIGGER IF EXISTS injected_reference_failure;") }
    try refuses("database") {
      _ = try book.annotateReferences(
        origin.id,
        selections: [selection("one", in: origin.text), selection("two", in: origin.text)],
        expectedSnapshotID: first.id, token: "failed-reference")
    }
    try expect(try book.counts() == counts && book.referenceSnapshot(origin.id) == first)
    try expect(try book.referenceHistory(origin.id)["versions"].array.count == 1)
    try expect(
      try referenceSQL(book, "SELECT count(*) FROM operations WHERE id='failed-reference';") == "0")
    _ = try faultSQL(book, "DROP TRIGGER injected_reference_failure;")
    try expect(try book.verify()["ok"] == .bool(true))
  }

  check("reference bounds and occurrence identity refuse atomically without blocking plain text") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReferenceBounds.sevra"), title: "Bounds")
    let source = try book.addItem(
      category: "source", kind: "observation", title: "Labels", text: "one two")
    let before = try book.counts()
    for invalid in [
      ReferenceSelection(startScalar: Int.max, scalarCount: Int.max),
      .init(startScalar: 0, scalarCount: 0), .init(startScalar: -1, scalarCount: 1),
    ] {
      try refuses("reference_range") {
        _ = try book.annotateReferences(source.id, selections: [invalid], expectedSnapshotID: nil)
      }
    }
    try refuses("reference_range") {
      _ = try book.annotateReferences(
        source.id,
        selections: [.init(startScalar: 0, scalarCount: 4), .init(startScalar: 2, scalarCount: 2)],
        expectedSnapshotID: nil)
    }
    try refuses("reference_identity") {
      _ = try book.annotateReferences(
        source.id, selections: [.init(startScalar: 0, scalarCount: 3, id: "invented-reference")],
        expectedSnapshotID: nil)
    }
    try refuses("reference_limit") {
      _ = try book.annotateReferences(
        source.id, selections: Array(repeating: selection("one", in: source.text), count: 129),
        expectedSnapshotID: nil)
    }
    try refuses("reference_range") {
      _ = try book.addItem(
        category: "source", kind: "observation", title: "RolledBackMarker", text: "one",
        references: [.init(startScalar: 100, scalarCount: 1)])
    }
    try expect(try book.counts() == before && book.search("RolledBackMarker").hits.isEmpty)
    let large = try book.addItem(
      category: "source", kind: "observation", title: "Large",
      text: String(repeating: "x", count: 1_000_001))
    let after = try book.counts()
    try refuses("reference_limit") {
      _ = try book.annotateReferences(large.id, selections: [], expectedSnapshotID: nil)
    }
    try expect(
      try book.counts() == after && book.referenceSnapshot(large.id).coverage == "unsupported")
    try expect(try book.verify()["ok"] == .bool(true))
  }

  check(
    "portable export retains reference identity, annotation history, unresolved labels and assets"
  ) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReferencePortable.sevra"), title: "Portable")
    let file = root.appendingPathComponent("reference-original.txt")
    try Data("Immutable asset\r\n".utf8).write(to: file)
    let asset = try book.importFile(file)
    let originalBytes = try Data(contentsOf: book.assetURL(asset.assetID!))
    let origin = try book.addItem(
      category: "source", kind: "observation", title: "Note", text: "asset later")
    let first = try book.annotateReferences(
      origin.id,
      selections: [
        selection("asset", in: origin.text, target: .init(mode: .pinned, identity: asset.id)),
        selection("later", in: origin.text),
      ], expectedSnapshotID: nil)
    let second = try book.annotateReferences(
      origin.id,
      selections: [
        selection(
          "asset", in: origin.text, target: .init(mode: .live, identity: asset.logicalID),
          id: first.references[0].id),
        selection("later", in: origin.text, id: first.references[1].id),
      ], expectedSnapshotID: first.id)
    let archive = root.appendingPathComponent("References.sevraz")
    try book.export(to: archive)
    let opened = try Workbook.openArchive(
      archive, at: root.appendingPathComponent("ReferenceReopened.sevra"))
    try expect(opened.id == book.id)
    try expect(
      try opened.referenceSnapshot(origin.id) == second
        && opened.referenceSnapshot(origin.id, snapshotID: first.id) == first)
    try expect(
      try opened.resolveReference(first.references[0].id, originVersionID: origin.id)[
        "destination"]["id"].text == asset.id)
    try expect(try Data(contentsOf: opened.assetURL(asset.assetID!)) == originalBytes)
    try opened.rebuildSearch()
    try expect(
      try opened.referenceSnapshot(origin.id) == second && opened.verify()["ok"] == .bool(true))
  }

  check("integrity refuses changed bindings, changed labels and annotation heads") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReferenceIntegrity.sevra"), title: "Integrity")
    let source = try book.addItem(
      category: "source", kind: "observation", title: "Quote", text: "quote")
    let first = try book.annotateReferences(
      source.id, selections: [selection("quote", in: source.text)], expectedSnapshotID: nil)
    _ = try referenceSQL(book, "UPDATE reference_bindings SET label='wrong';")
    try refuses("integrity") { _ = try book.verify() }
    _ = try referenceSQL(book, "UPDATE reference_bindings SET label='quote';")
    _ = try referenceSQL(book, "UPDATE reference_sets SET inherited_from=id;")
    try refuses("integrity") { _ = try book.verify() }
    _ = try referenceSQL(book, "UPDATE reference_sets SET inherited_from=NULL;")
    _ = try referenceSQL(book, "UPDATE reference_bindings SET ordinal=7;")
    try refuses("integrity") { _ = try book.verify() }
    _ = try referenceSQL(book, "UPDATE reference_bindings SET ordinal=0;")
    _ = try referenceSQL(
      book,
      "PRAGMA ignore_check_constraints=ON; UPDATE reference_bindings SET resolution='bound',target_workbook='\(book.id)',target_mode=NULL,target_version='missing';"
    )
    try refuses("integrity") { _ = try book.referenceSnapshot(source.id) }
    _ = try referenceSQL(
      book,
      "UPDATE reference_bindings SET resolution='unresolved',target_workbook=NULL,target_version=NULL;"
    )
    let second = try book.annotateReferences(
      source.id, selections: [], expectedSnapshotID: first.id)
    _ = try referenceSQL(book, "UPDATE reference_heads SET set_id='\(first.id!)';")
    try refuses("integrity") { _ = try book.verify() }
    _ = try referenceSQL(book, "UPDATE reference_heads SET set_id='\(second.id!)';")
    try expect(try book.item(source.id) == source && book.verify()["ok"] == .bool(true))
  }

  check("manifest identity cannot silently redirect saved local references") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReferenceManifest.sevra"), title: "Identity")
    let url = book.url.appendingPathComponent("manifest.json")
    let original = try Data(contentsOf: url)
    var manifest = try Value.parse(String(decoding: original, as: UTF8.self)).object
    manifest["id"] = .string("another-workbook")
    try Data(Value.object(manifest).json().utf8).write(to: url)
    try refuses("workbook_identity") { _ = try Workbook(book.url) }
    try original.write(to: url)
    try expect(try Workbook(book.url).id == book.id)
  }
}
