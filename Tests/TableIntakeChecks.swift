import Foundation
import SevraCore

func checkTableIntake(at root: URL) {
  func fixture(_ name: String, text: String) throws -> (Workbook, Item, Dataset) {
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    let basis = try book.addItem(category: "source", kind: "observation", title: "Starting values")
    let table = try book.createDataset(
      title: "Parts",
      columns: [
        .init(id: "sku", title: "SKU"), .init(id: "qty", title: "Quantity", type: "decimal"),
      ],
      rows: [
        ["sku": .string("0012"), "qty": .string("4")],
        ["sku": .string("0013"), "qty": .string("5")],
      ], sourceID: basis.id)
    let file = root.appendingPathComponent(name + ".csv")
    try Data(text.utf8).write(to: file)
    return (book, try book.importFile(file), table)
  }
  let mapping = [
    IntakeColumnMapping(position: 0, target: "sku"), .init(position: 1, target: "qty"),
  ]
  check("merge preview binds exact target and discloses changes without publishing data") {
    let (book, source, table) = try fixture(
      "MergePreview", text: "code,amount\n0012,7\n0013,5\n0014,2\n")
    let before = try book.counts()
    try refuses("proposal_tool") {
      _ = try book.addItem(
        category: "record", kind: "table-intake-update", title: "Forged update",
        data: .object(["datasetID": .string(table.id)]), inputs: [source.id])
    }
    let preview = try book.previewTableUpdate(
      sourceID: source.id, datasetID: table.id, mode: .merge, mapping: mapping, keys: ["sku"])
    try expect(
      preview.added == 1 && preview.changed == 1 && preview.unchanged == 1 && preview.removed == 0)
    try expect(
      preview.mapping == mapping && preview.keys == ["sku"]
        && preview.headings == ["code", "amount"])
    try expect(preview.rowsMatchingTarget == 1 && preview.fingerprint.count == 64)
    try expect(
      preview.examples[0]["before"]["sku"].text == "0012"
        && preview.examples[0]["after"]["qty"].text == "7")
    try expect(try book.counts() == before && book.rows(table.id)[0].data["qty"].text == "4")
    let row = try book.rows(table.id)[0]
    _ = try book.editRow(row.id, values: ["sku": .string("0012"), "qty": .string("8")])
    let newer = try book.previewTableUpdate(
      sourceID: source.id, datasetID: table.id, mode: .merge, mapping: mapping, keys: ["sku"])
    try expect(newer.fingerprint != preview.fingerprint && newer.revision > preview.revision)
  }
  check("append retains duplicates explicitly and replacement can preview clearing the target") {
    let (book, source, table) = try fixture(
      "AppendPreview", text: "code,amount\n0012,4\n0012,4\n0014,2\n")
    let preview = try book.previewTableUpdate(
      sourceID: source.id, datasetID: table.id, mode: .append, mapping: mapping)
    try expect(
      preview.added == 3 && preview.repeatedIncomingRows == 1 && preview.rowsMatchingTarget == 2)
    try expect(preview.changed == 0 && preview.removed == 0)
    let empty = root.appendingPathComponent("ClearPreview.csv")
    try Data("code,amount\n".utf8).write(to: empty)
    let original = try book.importFile(empty)
    let clear = try book.previewTableUpdate(
      sourceID: original.id, datasetID: table.id, mode: .replace, mapping: mapping)
    try expect(clear.incoming == 0 && clear.removed == 2 && clear.added == 0)
    try expect(try book.dataset(table.id).rowCount == 2)
  }
  check("ambiguous merge keys and incomplete mappings refuse without any working changes") {
    for (name, text, code) in [
      ("DuplicateInput", "code,amount\n0012,4\n0012,7\n", "update_key_duplicate"),
      ("MissingKey", "code,amount\n,4\n", "update_key_missing"),
      ("WrongType", "code,amount\n0012,1.234,56\n", "update_mapping"),
    ] {
      let (book, source, table) = try fixture(name, text: text)
      let before = try book.counts()
      try refuses(code) {
        _ = try book.previewTableUpdate(
          sourceID: source.id, datasetID: table.id, mode: .merge, mapping: mapping, keys: ["sku"])
      }
      try refuses("update_mapping") {
        _ = try book.previewTableUpdate(
          sourceID: source.id, datasetID: table.id, mode: .append,
          mapping: [.init(position: 0, target: "sku")])
      }
      try expect(try book.counts() == before)
    }
    let (book, source, table) = try fixture("DuplicateTarget", text: "code,amount\n0012,7\n")
    let second = try book.rows(table.id)[1]
    _ = try book.editRow(second.id, values: ["sku": .string("0012"), "qty": .string("5")])
    let before = try book.counts()
    try refuses("update_key_duplicate") {
      _ = try book.previewTableUpdate(
        sourceID: source.id, datasetID: table.id, mode: .merge, mapping: mapping, keys: ["sku"])
    }
    try expect(try book.counts() == before)
  }
  check("reviewed merge, append and replacement apply once and support checked undo and redo") {
    for mode in [TableUpdateMode.merge, .append, .replace] {
      let (book, source, table) = try fixture(
        "Apply-" + mode.rawValue, text: "code,amount\n0012,7\n0013,5\n0014,2\n")
      let original = try book.rows(table.id)
      try book.setOpeningBalance(
        subject: "stock", quantity: "20", effective: "2026-01-01", sourceID: source.id)
      let preview = try book.previewTableUpdate(
        sourceID: source.id, datasetID: table.id, mode: mode,
        mapping: mapping, keys: mode == .merge ? ["sku"] : [])
      let proposal = try book.proposeTableUpdate(
        sourceID: source.id, datasetID: table.id, mode: mode,
        mapping: mapping, keys: mode == .merge ? ["sku"] : [],
        newRowMeaning: "estimate", newRowScenario: "forecast",
        expectedRevision: preview.revision, expectedFingerprint: preview.fingerprint,
        token: "propose-once")
      try expect(proposal.status == "draft" && book.dataset(table.id).rowCount == 2)
      let accepted = try book.accept(proposal.id, token: "apply-once")
      let applied = try book.rows(table.id)
      try expect(applied.count == (mode == .append ? 5 : 3))
      try expect(applied.last?.data["sku"].text == "0014" && applied.last?.meaning == "estimate")
      if mode == .merge {
        try expect(
          applied[0].logicalID == original[0].logicalID && applied[0].data["qty"].text == "7")
        try expect(applied[1].id == original[1].id)
      }
      if mode == .replace { try expect(try book.item(original[0].logicalID).status == "rejected") }
      let revision = try book.revision()
      try expect(
        try book.accept(proposal.id, token: "apply-once").id == accepted.id
          && book.revision() == revision)
      let undone = try book.undoItem(accepted.id, token: "undo-once")
      let restored = try book.rows(table.id)
      try expect(restored.map(\.logicalID) == original.map(\.logicalID))
      try expect(restored.map(\.data) == original.map(\.data))
      let undoRevision = try book.revision()
      try expect(
        try book.undoItem(accepted.id, token: "undo-once").id == undone.id
          && book.revision() == undoRevision)
      let redone = try book.undoItem(undone.id, token: "redo-once")
      try expect(
        redone.status == "accepted" && book.rows(table.id).map(\.data) == applied.map(\.data))
      try expect(try book.balance(subject: "stock")["quantity"].text == "20")
      try expect(try book.verify()["ok"] == .bool(true))
      let archive = root.appendingPathComponent("Update-" + mode.rawValue + ".sevraz")
      try book.export(to: archive)
      let copy = try Workbook.openArchive(
        archive, at: root.appendingPathComponent("UpdateRestored-" + mode.rawValue + ".sevra"))
      _ = try copy.undoItem(redone.id)
      try expect(try copy.rows(table.id).map(\.data) == original.map(\.data))
      try expect(try copy.verify()["ok"] == .bool(true))
    }
  }
  check("stale preview, acceptance and undo refuse without partial working changes") {
    let (book, source, table) = try fixture("StaleUpdate", text: "code,amount\n0012,7\n")
    let preview = try book.previewTableUpdate(
      sourceID: source.id, datasetID: table.id, mode: .merge, mapping: mapping, keys: ["sku"])
    let proposal = try book.proposeTableUpdate(
      sourceID: source.id, datasetID: table.id, mode: .merge,
      mapping: mapping, keys: ["sku"], newRowMeaning: "actual", newRowScenario: "actual",
      expectedRevision: preview.revision, expectedFingerprint: preview.fingerprint)
    let row = try book.rows(table.id)[0]
    _ = try book.editRow(row.id, values: ["sku": .string("0012"), "qty": .string("9")])
    let before = try book.counts()
    try refuses("stale_revision") { _ = try book.accept(proposal.id) }
    try refuses("stale_revision") {
      _ = try book.proposeTableUpdate(
        sourceID: source.id, datasetID: table.id, mode: .merge,
        mapping: mapping, keys: ["sku"], newRowMeaning: "actual", newRowScenario: "actual",
        expectedRevision: preview.revision, expectedFingerprint: preview.fingerprint)
    }
    try expect(try book.counts() == before && book.rows(table.id)[0].data["qty"].text == "9")
    let fresh = try book.previewTableUpdate(
      sourceID: source.id, datasetID: table.id, mode: .merge, mapping: mapping, keys: ["sku"])
    let next = try book.proposeTableUpdate(
      sourceID: source.id, datasetID: table.id, mode: .merge,
      mapping: mapping, keys: ["sku"], newRowMeaning: "actual", newRowScenario: "actual",
      expectedRevision: fresh.revision, expectedFingerprint: fresh.fingerprint)
    let accepted = try book.accept(next.id)
    let changed = try book.rows(table.id)[0]
    _ = try book.editRow(changed.id, values: ["sku": .string("0012"), "qty": .string("11")])
    let beforeUndo = try book.counts()
    try refuses("stale_revision") { _ = try book.undoItem(accepted.id) }
    try expect(try book.counts() == beforeUndo && book.rows(table.id)[0].data["qty"].text == "11")
  }

  check("failed publication rolls back removed rows, heads, lineage and the acceptance receipt") {
    let (book, source, table) = try fixture("RollbackUpdate", text: "code,amount\n0014,2\n")
    let preview = try book.previewTableUpdate(
      sourceID: source.id, datasetID: table.id, mode: .replace, mapping: mapping)
    let proposal = try book.proposeTableUpdate(
      sourceID: source.id, datasetID: table.id, mode: .replace,
      mapping: mapping, newRowMeaning: "actual", newRowScenario: "actual",
      expectedRevision: preview.revision, expectedFingerprint: preview.fingerprint)
    let before = try book.counts()
    let oldRows = try book.rows(table.id)
    let oldLineage = try referenceSQL(
      book,
      "SELECT count(*) FROM lineage; SELECT count(*) FROM items; SELECT count(*) FROM operations;")
    _ = try faultSQL(
      book,
      "CREATE TRIGGER table_intake_fault AFTER INSERT ON items WHEN new.kind='row' AND new.status='accepted' AND json_extract(new.data,'$.sku')='0014' BEGIN SELECT RAISE(ABORT,'synthetic table update fault'); END;"
    )
    try refuses("database") { _ = try book.accept(proposal.id, token: "retry-after-fault") }
    try expect(try book.counts() == before && book.rows(table.id).map(\.id) == oldRows.map(\.id))
    try expect(
      try referenceSQL(
        book,
        "SELECT count(*) FROM lineage; SELECT count(*) FROM items; SELECT count(*) FROM operations;"
      ) == oldLineage)
    _ = try faultSQL(book, "DROP TRIGGER table_intake_fault;")
    let cancel = Cancellation()
    cancel.cancel()
    try refuses("cancelled") {
      _ = try book.accept(proposal.id, token: "retry-after-fault", cancellation: cancel)
    }
    try expect(try book.counts() == before)
    let accepted = try book.accept(proposal.id, token: "retry-after-fault")
    try expect(accepted.status == "accepted" && book.dataset(table.id).rowCount == 1)
    let row = try book.rows(table.id)[0]
    try expect(
      try book.lineage(row.id).contains {
        $0["parent"].text == source.id && $0["transformation"].text.contains("source-record=2")
      })
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("proposal retry precedes linked-file access and rejects changed mapping arguments") {
    let (book, _, table) = try fixture("LinkedUpdate", text: "code,amount\n0014,2\n")
    let file = root.appendingPathComponent("LinkedUpdate.csv")
    let source = try book.importFile(file, linked: true)
    let preview = try book.previewTableUpdate(
      sourceID: source.id, datasetID: table.id, mode: .append, mapping: mapping)
    func propose(_ mode: TableUpdateMode) throws -> Item {
      try book.proposeTableUpdate(
        sourceID: source.id, datasetID: table.id, mode: mode,
        mapping: mapping, newRowMeaning: "actual", newRowScenario: "actual",
        expectedRevision: preview.revision, expectedFingerprint: preview.fingerprint,
        token: "linked-once")
    }
    let first = try propose(.append)
    _ = try book.accept(first.id)
    try FileManager.default.removeItem(at: file)
    let before = try book.counts()
    try expect(try propose(.append).id == first.id && book.counts() == before)
    try refuses("idempotency") { _ = try propose(.replace) }
    try expect(try book.counts() == before)
  }

  check("update intake persists the selected use and draft identity without applying rows") {
    let (book, source, table) = try fixture("UpdateJob", text: "code,amount\n0012,7\n")
    let job = try book.beginIntake(sourceID: source.id, role: .update)
    let pending = try book.runIntake(job.id)
    try expect(pending.state == "awaiting_update" && pending.datasetIDs.isEmpty)
    let preview = try book.previewTableUpdate(
      sourceID: source.id, datasetID: table.id,
      mode: .merge, mapping: mapping, keys: ["sku"])
    let proposal = try book.proposeTableUpdate(
      sourceID: source.id, datasetID: table.id,
      mode: .merge, mapping: mapping, keys: ["sku"], newRowMeaning: "actual",
      newRowScenario: "actual",
      expectedRevision: preview.revision, expectedFingerprint: preview.fingerprint,
      intakeID: job.id,
      token: "job-draft")
    let reopened = try Workbook(book.url)
    let ready = try reopened.intakeJob(job.id)
    try expect(ready.state == "ready" && ready.report["proposalID"].text == proposal.id)
    try expect(try reopened.rows(table.id)[0].data["qty"].text == "4")
    try expect(try reopened.runIntake(job.id).report == ready.report)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check(
    "source inspection rejects invalid headers and merge keeps calculated columns and exact locators"
  ) {
    let (book, source, table) = try fixture("CalculatedUpdate", text: "code,amount\n\"0012\",7\n")
    for header in [0, -1, 3, Int.max] {
      try refuses("update_header") {
        _ = try book.inspectTableUpdateSource(source.id, headerRow: header)
      }
    }
    let inspection = try book.inspectTableUpdateSource(source.id)
    try expect(
      inspection.headings == ["code", "amount"] && inspection.examples == [["0012", "7"]])
    try book.setColumns(
      table.id,
      columns: table.columns + [
        .init(id: "total", title: "Total", type: "decimal", formula: "qty*2")
      ])
    let preview = try book.previewTableUpdate(
      sourceID: source.id, datasetID: table.id,
      mode: .merge, mapping: mapping, keys: ["sku"])
    let proposal = try book.proposeTableUpdate(
      sourceID: source.id, datasetID: table.id,
      mode: .merge, mapping: mapping, keys: ["sku"], newRowMeaning: "actual",
      newRowScenario: "actual",
      expectedRevision: preview.revision, expectedFingerprint: preview.fingerprint)
    _ = try book.accept(proposal.id)
    let page = try book.tablePage(table.id)
    try expect(page.values[0]["total"]?.text == "14" && page.rows[0].data["total"] == .null)
    try expect(
      preview.examples[0]["sourceRecord"].int == 2 && preview.columns.last?.formula == "qty*2")
  }
  check("concurrent handles accepting one update share a receipt and never duplicate rows") {
    final class Results: @unchecked Sendable {
      let lock = NSLock()
      var values: [String] = []
      var errors: [String] = []
      func record(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value)
      }
      func fail(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        errors.append(error.localizedDescription)
      }
    }
    let (book, source, table) = try fixture("ConcurrentUpdate", text: "code,amount\n0014,2\n")
    let preview = try book.previewTableUpdate(
      sourceID: source.id, datasetID: table.id, mode: .append, mapping: mapping)
    let proposal = try book.proposeTableUpdate(
      sourceID: source.id, datasetID: table.id, mode: .append,
      mapping: mapping, newRowMeaning: "actual", newRowScenario: "actual",
      expectedRevision: preview.revision,
      expectedFingerprint: preview.fingerprint)
    let handles = [try Workbook(book.url), try Workbook(book.url)]
    let results = Results()
    let group = DispatchGroup()
    let start = DispatchSemaphore(value: 0)
    for handle in handles {
      group.enter()
      DispatchQueue.global().async {
        defer { group.leave() }
        start.wait()
        do { results.record(try handle.accept(proposal.id, token: "shared-accept").id) } catch {
          results.fail(error)
        }
      }
    }
    start.signal()
    start.signal()
    try expect(group.wait(timeout: .now() + 20) == .success)
    try expect(
      results.errors.isEmpty && results.values.count == 2 && Set(results.values).count == 1)
    try expect(try book.dataset(table.id).rowCount == 3 && book.verify()["ok"] == .bool(true))
  }

}
