import CSQLite
import Foundation

@testable import SevraCore

func checkPersistence(at root: URL) {
  check(
    "complete history reconstructs business, tables, evidence, conversation and presentation without execution"
  ) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("PersistenceFamilies.sevra"), title: "History")
    let original = try book.addItem(
      category: "source", kind: "observation", title: "Opening", text: "20 parts",
      status: "accepted")
    try book.setOpeningBalance(
      subject: "parts", quantity: "20", effective: "2026-01-01", sourceID: original.id)
    let proposed = try book.movement(
      subject: "parts", quantity: "-2", occurrence: "unique-sale", effective: "2026-01-02",
      input: original.id)
    let accepted = try book.accept(proposed.id, actor: .human("fixture.review"))
    let undone = try book.undoItem(accepted.id, actor: .human("fixture.review"))
    _ = try book.undoItem(undone.id, actor: .human("fixture.review"))
    let declined = try book.addItem(
      category: "record", kind: "forecast", title: "Declined", inputs: [original.id])
    _ = try book.withdrawDraft(declined.id)
    let table = try book.createDataset(
      title: "Parts",
      columns: [
        .init(id: "sku", title: "SKU"), .init(id: "qty", title: "Quantity", type: "decimal"),
      ], rows: [["sku": .string("0012"), "qty": .string("4")]], sourceID: original.id)
    let first = try book.rows(table.id)[0]
    _ = try book.editRow(first.id, values: ["sku": .string("0012"), "qty": .string("7")])
    let text = "Cafe\u{301} 👩🏽‍💻\0 [opening](sevra://item/\(original.id))"
    let file = root.appendingPathComponent("history-source.md")
    try Data(text.utf8).write(to: file)
    let document = try book.importFile(file)
    try book.index(
      document.id, chunks: [Chunk(text, locator: "page=2")], parser: "saved-extractor-v1")
    let retained = try book.fileReferenceSnapshot(document.id)
    try book.index(
      document.id, chunks: [Chunk("New extraction [[Missing]]", locator: "page=9")],
      parser: "saved-extractor-v2")
    let source = try book.addItem(
      category: "source", kind: "note", title: "Manual references", text: "opening")
    _ = try book.annotateReferences(
      source.id,
      selections: [
        .init(startScalar: 0, scalarCount: 7, target: .init(mode: .pinned, identity: original.id))
      ], expectedSnapshotID: nil)
    let request = try book.startAgentRequest(
      "Create report", conversation: "main", model: "saved-model")
    let call = try book.prepareToolCall(
      runID: request.runID, callID: "read", tool: "read",
      arguments: .object(["id": .string(document.id)]))
    let result = try WorkbookTools(book, runID: request.runID).execute(
      "read", .object(["id": .string(document.id)]))
    _ = try book.completeToolCall(call, result: result)
    let copy = try book.documentCopy(
      receiptID: call, path: ["chunks", "0", "body"], startScalar: 0,
      scalarCount: "New extraction [[Missing]]".unicodeScalars.count, runID: request.runID)
    let report = try book.saveComposedDraft(
      title: "Report", parts: [.init(copy: copy.reference)], runID: request.runID)
    _ = try book.addMessage(
      "Report saved", role: "assistant", payload: .object(["report": .string(report.id)]))
    _ = try book.saveContextCheckpoint(
      book.historySlice(), summary: "Report saved from evidence", model: "saved-model",
      template: "fixture-v1", evidenceIDs: [document.id], runID: request.runID)
    try book.chapter(title: "Report", message: request.messageID)
    try book.chapter(title: "Keep", message: request.messageID, bookmark: true)
    let tangent = try book.tangent(title: "Follow-up", parentMessage: request.messageID)
    _ = try book.addMessage("Unsent elsewhere", role: "assistant", conversation: tangent)
    let pending = try book.prepareToolCall(
      runID: request.runID, callID: "pending", tool: "propose_record",
      arguments: .object(["title": .string("Never execute")]))
    let ambiguousArguments: Value = .object([
      "title": .string("Already drafted"), "text": .string("Saved before the final receipt"),
      "kind": .string("forecast"), "meaning": .string("estimate"),
    ])
    let ambiguous = try book.prepareToolCall(
      runID: request.runID, callID: "ambiguous", tool: "propose_record",
      arguments: ambiguousArguments)
    let savedOutcome = try WorkbookTools(book, runID: request.runID, requestSourceID: original.id)
      .execute("propose_record", ambiguousArguments)
    // Simulate process death after the mutation but before completeToolCall.
    let space = try book.saveSpace(
      title: "Review",
      definition: .init(components: [.init(type: "text", title: "Summary", text: "Saved")]))
    _ = try book.saveSpace(
      id: space, title: "Review 2",
      definition: .init(components: [.init(type: "text", title: "Summary", text: "Revised")]),
      expectedVersion: 1)
    _ = try book.updateSpaceNavigation([.pin(space, true), .visit(space)])
    _ = try book.saveConversationViewState(
      "main", draft: "Keep my draft", reading: .init(message: request.messageID, fraction: 0.25),
      expectedDraft: "")
    let csv = root.appendingPathComponent("history-intake.csv")
    try Data("sku,qty\n0021,3\n".utf8).write(to: csv)
    let intake = try book.captureIntake(csv, role: .values)
    let ready = try book.runIntake(intake.id)
    let preview = try book.previewTableUpdate(
      sourceID: ready.sourceID, datasetID: table.id, mode: .append,
      mapping: [.init(position: 0, target: "sku"), .init(position: 1, target: "qty")])
    let update = try book.proposeTableUpdate(
      sourceID: ready.sourceID, datasetID: table.id, mode: .append, mapping: preview.mapping,
      newRowMeaning: "estimate", newRowScenario: "forecast", expectedRevision: preview.revision,
      expectedFingerprint: preview.fingerprint)
    let updated = try book.accept(update.id)
    let reversed = try book.undoItem(updated.id)
    _ = try book.undoItem(reversed.id)
    try FileManager.default.removeItem(at: csv)
    try FileManager.default.removeItem(at: file)
    let restored = try book.reconstruct(to: root.appendingPathComponent("Reconstructed.sevra"))
    try expect(restored.id == book.id && restored.revision() == book.revision())
    try expect(try restored.balance(subject: "parts") == book.balance(subject: "parts"))
    try expect(try restored.rows(table.id)[0].data == book.rows(table.id)[0].data)
    try expect(try restored.item(report.id) == book.item(report.id))
    try expect(
      try restored.fileReferenceRegion(document.id, snapshotID: retained["id"].text, region: 0)[
        "text"
      ].text.utf8.elementsEqual(text.utf8))
    try expect(try restored.intakeJob(ready.id).datasetIDs == ready.datasetIDs)
    try expect(try restored.conversationViewState("main").draft == "Keep my draft")
    try expect(try restored.readSpaceNavigation().pinned == [space])
    try expect(try restored.toolCall(pending)["state"].text == "prepared")
    try expect(try restored.toolCall(ambiguous)["state"].text == "prepared")
    try expect(try restored.item(savedOutcome["id"].text).status == "draft")
    try expect(try restored.agentRuns()[0]["status"].text == "running")
    try expect(try restored.search("extraction").hits.count == book.search("extraction").hits.count)
    try expect(
      try restored.searchHistory("Report")["hits"].array.count
        == book.searchHistory("Report")["hits"].array.count)
    try expect(try restored.db.scalar("SELECT count(*) FROM extraction_attempts").int == 0)
    try expect(try restored.verify()["ok"] == .bool(true))
    let archive = root.appendingPathComponent("Replay.sevraz")
    try restored.export(to: archive)
    let portable = try Workbook.openArchive(
      archive, at: root.appendingPathComponent("ReplayPortable.sevra"))
    _ = try portable.reconstruct(to: root.appendingPathComponent("ReplayAgain.sevra"))
  }
  check("saved decision actors are distinct and actor changes cannot reuse an acceptance token") {
    let book = try Workbook.create(at: root.appendingPathComponent("Actors.sevra"), title: "Actors")
    let source = try book.addItem(category: "source", kind: "note", title: "Basis")
    let rule = try book.addItem(
      category: "source", kind: "rule", title: "Fixture forecast policy",
      text:
        "Synthetic qualification policy version 1. This fixture does not enable automatic execution.",
      meaning: "rule", status: "accepted")
    let guarded = try book.addItem(
      category: "record", kind: "forecast", title: "Guarded forecast", meaning: "estimate",
      inputs: [source.id])
    let beforeInvalid = try book.revision()
    try refuses("decision_policy") {
      _ = try book.accept(
        guarded.id, actor: .ai("fixture", model: "model-hash", policy: "invented-policy"))
    }
    try expect(try book.revision() == beforeInvalid && book.item(guarded.id).status == "draft")
    for actor in [
      ChangeActor.human("native-review"), .programmatic("external-harness"),
      .ai("rule-runner", model: "model-hash", policy: rule.id),
    ] {
      let draft = try book.addItem(
        category: "record", kind: "forecast", title: actor.kind, meaning: "estimate",
        inputs: [source.id])
      let token = identifier()
      let result = try book.accept(draft.id, token: token, actor: actor)
      try expect(try book.accept(draft.id, token: token, actor: actor).id == result.id)
      try refuses("idempotency") {
        _ = try book.accept(draft.id, token: token, actor: .programmatic("different"))
      }
      let history = try book.committedHistory()[0]
      try expect(history["actor"] == encoded(actor))
      let decisions = try book.lineage(result.id).filter {
        $0["transformation"].text == "accept-v1"
      }
      let decision = try decisions.compactMap { try book.item($0["parent"].text) }.first {
        $0.kind == "decision"
      }!
      try expect(decision.data["attribution"] == encoded(actor))
      try expect(actor.kind == "human" || !decision.text.contains("The user"))
      if actor.kind == "ai" {
        try expect(try book.lineage(decision.id).contains { $0["parent"].text == rule.id })
      }
    }
    _ = try book.addItem(
      category: "source", kind: "rule", title: "Revoked fixture policy", meaning: "rule",
      status: "rejected", supersedes: rule.id)
    try refuses("decision_policy") {
      _ = try book.accept(guarded.id, actor: .ai("fixture", model: "model-hash", policy: rule.id))
    }
    let run = try book.startAgentRequest(
      "Draft a forecast", conversation: "main", model: "fixture-local-model")
    _ = try WorkbookTools(book, runID: run.runID, requestSourceID: source.id).execute(
      "propose_record",
      .object([
        "title": .string("Generated forecast"), "text": .string("Possible demand"),
        "kind": .string("forecast"), "meaning": .string("estimate"),
      ]))
    try expect(try book.committedHistory()[0]["actor"]["kind"].text == "ai")
    try expect(try book.committedHistory()[0]["actor"]["model"].text == "fixture-local-model")
    let replay = try book.reconstruct(to: root.appendingPathComponent("ActorsReplay.sevra"))
    try expect(try replay.committedHistory() == book.committedHistory())
  }
  check("saved SQLite values keep large integers, exact UTF-8, empty blobs and IEEE-754 bits") {
    let database = try Database(root.appendingPathComponent("Typed.sqlite"), create: true)
    try database.script("CREATE TABLE values_fixture(a,b,c,d,e);")
    let cells: [ChangeCell] = [
      .integer("9223372036854775806"), .text(Data("a\0Cafe\u{301} 👩🏽‍💻".utf8)), .blob(Data()),
      .blob(Data([0, 255, 0])), .real(String(Double(0.1).bitPattern)),
    ]
    let roundTrip = try JSONDecoder().decode(
      [ChangeCell].self, from: Data(ChangeFormat.encode(cells).utf8))
    try expect(roundTrip == cells)
    try database.executeCells("INSERT INTO values_fixture VALUES(?,?,?,?,?)", roundTrip)
    var statement: OpaquePointer?
    try expect(
      sqlite3_prepare_v2(database.handle, "SELECT * FROM values_fixture", -1, &statement, nil)
        == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    try expect(sqlite3_step(statement) == SQLITE_ROW)
    for index in 0..<5 {
      try expect(ChangeCell.read(sqlite3_column_value(statement, Int32(index))) == cells[index])
    }
  }
  check(
    "capture publication failure rolls back state, receipts and retry while retaining flushed asset bytes"
  ) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("CaptureFault.sevra"), title: "Fault")
    _ = try faultSQL(
      book,
      "CREATE TRIGGER fault_commit BEFORE INSERT ON committed_changes BEGIN SELECT RAISE(ABORT,'injected commit failure'); END;"
    )
    let file = root.appendingPathComponent("fault.txt")
    try Data("Retain complete original".utf8).write(to: file)
    try refuses { _ = try book.importFile(file, token: "retry-import") }
    try expect(try book.counts()["sources"].int == 0 && book.revision() == 0)
    try expect(try book.committedHistory().isEmpty)
    try expect(try book.db.scalar("SELECT count(*) FROM assets").int == 0)
    _ = try faultSQL(book, "DROP TRIGGER fault_commit;")
    let imported = try book.importFile(file, token: "retry-import")
    try expect(try book.assetURL(imported.assetID!, verify: true).lastPathComponent.contains("."))
    try expect(try book.importFile(file, token: "retry-import").id == imported.id)
    try expect(try book.committedHistory().count == 1)
    let target = try Database(root.appendingPathComponent("Apply.sqlite"), create: true)
    try target.script(Schema.sql)
    try target.execute("PRAGMA trusted_schema=ON")
    try target.execute("INSERT INTO meta VALUES('workbook-id',?)", [.string(book.id)])
    let entry = try book.db.execute("SELECT payload,hash FROM committed_changes")[0]
    // Application uses saved rows, with all storage triggers disabled.
    try expect(sevra_enable_triggers(target.handle, 0) == SQLITE_OK)
    try target.applyCommitted(entry["payload"]!.text, hash: entry["hash"]!.text)
    try target.applyCommitted(entry["payload"]!.text, hash: entry["hash"]!.text)
    try expect(try target.scalar("SELECT count(*) FROM assets").int == 1)
    var changed = try JSONDecoder().decode(
      CommittedChange.self, from: Data(entry["payload"]!.text.utf8))
    changed = .init(
      version: changed.version, storageVersion: changed.storageVersion, id: changed.id,
      workbookID: changed.workbookID, previousID: changed.previousID,
      previousHash: changed.previousHash, recorded: changed.recorded, writerID: "another-writer",
      actor: changed.actor, changes: changed.changes)
    let payload = try ChangeFormat.encode(changed)
    try refuses("idempotency") {
      try target.applyCommitted(payload, hash: ChangeFormat.hash(payload))
    }
    let missing = try Database(
      root.appendingPathComponent("MissingDependency.sqlite"), create: true)
    try missing.script(Schema.sql)
    try missing.execute("PRAGMA trusted_schema=ON")
    try missing.execute("INSERT INTO meta VALUES('workbook-id',?)", [.string(book.id)])
    try expect(sevra_enable_triggers(missing.handle, 0) == SQLITE_OK)
    let incomplete = CommittedChange(
      version: changed.version, storageVersion: changed.storageVersion, id: changed.id,
      workbookID: changed.workbookID, previousID: changed.previousID,
      previousHash: changed.previousHash, recorded: changed.recorded, writerID: changed.writerID,
      actor: changed.actor, changes: changed.changes.filter { $0.table != "assets" })
    let incompletePayload = try ChangeFormat.encode(incomplete)
    try refuses {
      try missing.applyCommitted(incompletePayload, hash: ChangeFormat.hash(incompletePayload))
    }
    try expect(try missing.scalar("SELECT count(*) FROM items").int == 0)
    try expect(try missing.scalar("SELECT count(*) FROM committed_changes").int == 0)
  }
  check(
    "corrupt, missing, unsupported and out-of-band history refuses without publishing a reconstruction"
  ) {
    for mode in ["hash", "missing", "version", "base", "unlogged"] {
      let book = try Workbook.create(
        at: root.appendingPathComponent("Corrupt-" + mode + ".sevra"), title: mode)
      _ = try book.addItem(category: "source", kind: "note", title: "First")
      _ = try book.addItem(category: "source", kind: "note", title: "Second")
      switch mode {
      case "hash":
        _ = try referenceSQL(book, "UPDATE committed_changes SET hash='wrong' WHERE rowid=1;")
      case "missing": _ = try referenceSQL(book, "DELETE FROM committed_changes WHERE rowid=1;")
      case "unlogged":
        _ = try referenceSQL(book, "UPDATE items SET body='unlogged edit' WHERE rowid=1;")
      default:
        let row = try book.db.execute(
          "SELECT payload FROM committed_changes ORDER BY rowid LIMIT 1")[0]
        var object = try Value.parse(row["payload"]!.text).object
        if mode == "version" {
          object["version"] = .number(999)
        } else {
          object["previousID"] = .string("missing-base")
        }
        let payload = try Value.object(object).json()
        // Faults modify only a selected disposable synthetic fixture through an independent handle.
        let raw = try Database(book.url.appendingPathComponent("workbook.sqlite"))
        try raw.execute(
          "UPDATE committed_changes SET payload=?,hash=? WHERE rowid=1",
          [.string(payload), .string(ChangeFormat.hash(payload))])
      }
      let destination = root.appendingPathComponent("NoPublish-" + mode + ".sevra")
      try refuses { _ = try book.verify() }
      try refuses { _ = try book.reconstruct(to: destination) }
      try expect(!FileManager.default.fileExists(atPath: destination.path))
      try expect(try book.counts()["sources"].int == 2)
    }
  }
  check(
    "linked bytes and grants are unresolved while included historical dependencies are mandatory"
  ) {
    let book = try Workbook.create(
      at: root.appendingPathComponent("ReplayAssets.sevra"), title: "Assets")
    let file = root.appendingPathComponent("external.txt")
    try Data("External original".utf8).write(to: file)
    let linked = try book.importFile(file, linked: true)
    let included = try book.importFile(file)
    try FileManager.default.removeItem(at: file)
    let restored = try book.reconstruct(to: root.appendingPathComponent("Unresolved.sevra"))
    try expect(try restored.asset(linked.assetID!).path.isEmpty)
    try expect(
      try restored.db.scalar("SELECT bookmark FROM assets WHERE id=?", [.string(linked.assetID!)])
        == .null)
    try expect(try restored.verify()["assetIssues"].array.count == 1)
    try expect(try restored.assetURL(included.assetID!, verify: true).isFileURL)
    let archive = root.appendingPathComponent("ReplayLinked.sevraz")
    try book.export(to: archive)
    let portable = try Workbook.openArchive(
      archive, at: root.appendingPathComponent("ReplayLinkedPortable.sevra"))
    let replayed = try portable.reconstruct(
      to: root.appendingPathComponent("ReplayLinkedAgain.sevra"))
    try expect(try replayed.verify()["assetIssues"].array.count == 1)
    try expect(
      try !book.db.execute("SELECT payload FROM committed_changes").contains {
        $0["payload"]!.text.contains(file.path)
      })
    try FileManager.default.removeItem(at: book.assetURL(included.assetID!))
    let destination = root.appendingPathComponent("MissingIncluded.sevra")
    try refuses { _ = try book.reconstruct(to: destination) }
    try expect(!FileManager.default.fileExists(atPath: destination.path))
  }
}
