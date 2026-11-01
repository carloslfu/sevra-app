import Darwin
import Foundation
import SevraCore

func checkContextualIntake(at root: URL) {
  check("capture request retry survives a missing input and refuses changed intent") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("CaptureRetry.sevra"), title: "Retry")
    let file = root.appendingPathComponent("capture-retry.csv")
    try Data("sku,quantity\n0012,4\n".utf8).write(to: file)
    let first = try book.captureIntake(file, role: .reference, token: "one-capture")
    try FileManager.default.removeItem(at: file)
    let retry = try book.captureIntake(file, role: .reference, token: "one-capture")
    try expect(first.id == retry.id && first.sourceID == retry.sourceID)
    try expect(try book.counts()["sources"].int == 1)
    try refuses("idempotency") {
      _ = try book.captureIntake(file, role: .values, token: "one-capture")
    }
    try refuses("idempotency") {
      _ = try book.captureIntake(
        root.appendingPathComponent("another.csv"), role: .reference,
        token: "one-capture")
    }
    try expect(try book.runIntake(first.id).role == .reference)
    // A "/private" spelling standardizes differently once the file is gone.
    let plain = root.path.hasPrefix("/private/") ? String(root.path.dropFirst(8)) : root.path
    let spelled = URL(fileURLWithPath: "/private" + plain + "/capture-spelled.csv")
    try Data("sku,quantity\n0012,4\n".utf8).write(to: spelled)
    let kept = try book.captureIntake(spelled, role: .reference, token: "spelled")
    try FileManager.default.removeItem(at: spelled)
    try expect(try book.captureIntake(spelled, role: .reference, token: "spelled").id == kept.id)
  }
  check("interrupted capture registration recovers its requested use without guessing from suffix")
  {
    let book = try Workbook.create(
      at: root.appendingPathComponent("CaptureRecovery.sevra"), title: "Recovery")
    let file = root.appendingPathComponent("capture-recovery.csv")
    try Data("sku,quantity\n0012,4\n".utf8).write(to: file)
    // Fail job publication after the file receipt, rather than deleting a
    // committed receipt and pretending that committed history never happened.
    _ = try faultSQL(
      book,
      "CREATE TRIGGER registration_fault BEFORE INSERT ON intake_jobs BEGIN SELECT RAISE(ABORT,'interrupted registration'); END;"
    )
    try refuses { _ = try book.captureIntake(file, role: .reference, token: "interrupted-capture") }
    _ = try faultSQL(book, "DROP TRIGGER registration_fault;")
    let source = try book.items().first { $0.category == "source" && $0.kind == "document" }!
    try book.resumeIntake(source.id)
    let recovered = try book.intakeJobs(sourceID: source.id)[0]
    try expect(recovered.role == .reference)
    try expect(recovered.state == "ready" && book.datasets().isEmpty)
  }
  check("ambiguous capture survives reopen and reference resume never creates tables") {
    let book = try Workbook.create(at: root.appendingPathComponent("Roles.sevra"), title: "Roles")
    let file = root.appendingPathComponent("roles.csv")
    try Data("sku,quantity\n0012,4\n".utf8).write(to: file)
    let source = try book.importFile(file)
    let job = try book.beginIntake(sourceID: source.id, token: "ambiguous-role")
    let awaiting = try book.runIntake(job.id)
    try expect(awaiting.state == "awaiting_role" && awaiting.datasetIDs.isEmpty)
    try expect(try book.datasets().isEmpty)
    try FileManager.default.removeItem(at: file)
    let reopened = try Workbook(book.url)
    try expect(try reopened.intakeJob(job.id).state == "awaiting_role")
    _ = try reopened.chooseIntakeRole(job.id, role: .reference, token: "reference-choice")
    let ready = try reopened.runIntake(job.id)
    try reopened.resumeIntake(source.id)
    try expect(ready.role == .reference && ready.state == "ready")
    try expect(try reopened.datasets().isEmpty)
    try refuses("idempotency") {
      _ = try reopened.beginIntake(sourceID: source.id, role: .values, token: "ambiguous-role")
    }
    try refuses("intake_role") { _ = try reopened.chooseIntakeRole(job.id, role: .values) }
    try expect(try reopened.search("0012").hits.contains { $0.itemID == source.id })
  }
  check("analysis and explicit values share original identity with resumable conversion") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("RoleReuse.sevra"), title: "Reuse")
    let file = root.appendingPathComponent("reuse.csv")
    try Data("sku,quantity\n0012,4\n0013,5\n".utf8).write(to: file)
    let source = try book.importFile(file)
    let input = try book.beginIntake(sourceID: source.id, role: .analysis, token: "analysis-use")
    let analysis = try book.runIntake(input.id)
    try expect(analysis.report["inspection"]["sheets"].array[0]["rows"].int == 3)
    try expect(analysis.datasetIDs.isEmpty && analysis.state == "ready")
    try expect(try book.datasets().isEmpty)
    let conversion = try book.beginIntake(sourceID: source.id, role: .values, token: "values-use")
    let cancel = Cancellation()
    cancel.cancel()
    try refuses("cancelled") { _ = try book.runIntake(conversion.id, cancellation: cancel) }
    try expect(try book.intakeJob(conversion.id).state == "captured")
    let first = try book.runIntake(conversion.id)
    try expect(first.state == "ready" && first.datasetIDs.count == 1)
    let rows = try book.rows(first.datasetIDs[0])
    try expect(rows.count == 2 && rows[0].data["sku"].text == "0012")
    let revision = try book.revision()
    let retry = try book.runIntake(conversion.id)
    try expect(first.datasetIDs == retry.datasetIDs && book.revision() == revision)
    let again = try book.beginIntake(
      sourceID: source.id, role: .values, token: "another-values-use")
    try expect(try book.runIntake(again.id).datasetIDs == first.datasetIDs)
    try expect(try book.datasets().count == 1)
    let portable = root.appendingPathComponent("Roles.sevraz")
    try book.export(to: portable)
    let restored = try Workbook.openArchive(
      portable, at: root.appendingPathComponent("RolesRestored.sevra"))
    try expect(try restored.intakeJob(conversion.id).datasetIDs == first.datasetIDs)
    try expect(try restored.verify()["ok"] == .bool(true))
  }
  check("failed structured interpretation retains source and never reports a converted table") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("RoleFailure.sevra"), title: "Failure")
    let file = root.appendingPathComponent("bad-roles.csv")
    try Data("header\n\"unterminated".utf8).write(to: file)
    let source = try book.importFile(file)
    let job = try book.beginIntake(sourceID: source.id, role: .values)
    try refuses { _ = try book.runIntake(job.id) }
    let failed = try book.intakeJob(job.id)
    try expect(failed.state == "failed" && failed.datasetIDs.isEmpty)
    try expect(try book.assetURL(source.assetID!, verify: true).isFileURL)
    try expect(try book.datasets().isEmpty)
    let reference = try book.beginIntake(sourceID: source.id, role: .reference)
    try expect(try book.runIntake(reference.id).state == "ready")
    try expect(try book.datasets().isEmpty)
  }
  check("a use reuses an accepted index and an index failure leaves an explicit table role going") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("IndexReuse.sevra"), title: "Reuse")
    let file = root.appendingPathComponent("index-reuse.csv")
    try Data("sku,quantity\n0012,4\n".utf8).write(to: file)
    let source = try book.importFile(file)
    let first = try book.beginIntake(sourceID: source.id, role: .reference, token: "first-use")
    try expect(try book.runIntake(first.id).report["indexReused"] == .bool(false))
    // The next use runs with reindexing made to fail, as it does past the saved-change limit.
    _ = try faultSQL(
      book,
      "CREATE TRIGGER index_fault BEFORE DELETE ON chunks BEGIN SELECT RAISE(ABORT,'index fault'); END;"
    )
    let second = try book.beginIntake(sourceID: source.id, role: .values, token: "second-use")
    let converted = try book.runIntake(second.id)
    try expect(converted.state == "ready" && converted.report["indexReused"] == .bool(true))
    try expect(try book.rows(converted.datasetIDs[0]).count == 1)
    try refuses("database") { try book.extract(source.id) }
    _ = try faultSQL(book, "DROP TRIGGER index_fault;")
    // A table import gets past a file it cannot index. A plain reference has only its index.
    let other = root.appendingPathComponent("index-failure.csv")
    try Data("sku,quantity\n0013,5\n".utf8).write(to: other)
    let failing = try book.importFile(other)
    _ = try faultSQL(
      book,
      "CREATE TRIGGER index_fault BEFORE INSERT ON chunks WHEN NEW.item_id='\(failing.id)' BEGIN SELECT RAISE(ABORT,'index fault'); END;"
    )
    let reference = try book.beginIntake(sourceID: failing.id, role: .reference)
    try refuses("database") { _ = try book.runIntake(reference.id) }
    try expect(try book.intakeJob(reference.id).state == "failed")
    let values = try book.beginIntake(sourceID: failing.id, role: .values)
    let table = try book.runIntake(values.id)
    try expect(table.state == "ready" && table.report["index"]["state"].text == "failed")
    _ = try faultSQL(book, "DROP TRIGGER index_fault;")
    try expect(try book.rows(table.datasetIDs[0])[0].data["sku"].text == "0013")
  }
  check("a role-less intake killed while running still takes a use, and a late worker is fenced") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("RunningRole.sevra"), title: "Running")
    let file = root.appendingPathComponent("running-role.txt")
    try Data("Atlas note".utf8).write(to: file)
    let source = try book.importFile(file)
    let job = try book.beginIntake(sourceID: source.id, token: "killed-use")
    _ = try referenceSQL(
      book, "UPDATE intake_jobs SET state='running',attempt='gone' WHERE id='killed-use';")
    let chosen = try book.chooseIntakeRole(job.id, role: .reference)
    try expect(chosen.role == .reference && chosen.state == "captured")
    try expect(try book.runIntake(job.id).state == "ready")
    try refuses("intake_role") { _ = try book.chooseIntakeRole(job.id, role: .values) }
  }
  check("a semicolon file splits into columns and a comma file stays as it was") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Semicolons.sevra"), title: "Semicolons")
    func table(_ name: String, _ text: String) throws -> [Column] {
      let file = root.appendingPathComponent(name)
      try Data(text.utf8).write(to: file)
      let job = try book.captureIntake(file, role: .values)
      return try book.dataset(try book.runIntake(job.id).datasetIDs[0]).columns
    }
    try expect(try table("semi.csv", "Name;Menge\nSchraube;5\n").map(\.title) == ["Name", "Menge"])
    try expect(
      try table("comma.csv", "\"Name;Alt\",Menge\nA;B,5\n").map(\.title) == ["Name;Alt", "Menge"])
    try expect(try table("quoted.csv", "\"a;b\"\n\"c;d\"\n").map(\.title) == ["a;b"])
  }
  check("a query keeps its words when one term is only a mark, as an emoji's selector is") {
    let book = try Workbook.create(at: root.appendingPathComponent("Marks.sevra"), title: "Marks")
    let item = try book.addItem(
      category: "source", kind: "note", title: "Note", text: "Atlas invoice", status: "accepted")
    try book.index(item.id, chunks: [Chunk("Atlas invoice")])
    try expect(try book.search("invoice \u{2764}\u{FE0F}").hits.count == 1)
    try expect(try book.search("\u{2764}\u{FE0F}").hits.isEmpty)
    try expect(try book.search("missing \u{FE0F}").hits.isEmpty)
  }
  check("opening a workbook removes a killed import's copy and leaves one still being written") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Staging.sevra"), title: "Staging")
    let staging = book.url.appendingPathComponent("staging")
    let abandoned = staging.appendingPathComponent("abandoned")
    let folder = staging.appendingPathComponent("archive-abandoned")
    let live = staging.appendingPathComponent("live")
    try Data("partial".utf8).write(to: abandoned)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let held = open(live.path, O_CREAT | O_WRONLY | O_EXLOCK, 0o644)
    try expect(held >= 0)
    _ = try Workbook(book.url)
    let names = try FileManager.default.contentsOfDirectory(atPath: staging.path)
    try expect(names == ["live"])
    close(held)
    _ = try Workbook(book.url)
    try expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
  }
  check("including a linked file twice saves one copy, even when its contents cannot be read") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Including.sevra"), title: "Including")
    let file = root.appendingPathComponent("unreadable.pdf")
    try Data("not a pdf".utf8).write(to: file)
    let linked = try book.importFile(file, linked: true)
    let included = try book.includeLinked(linked.id)
    try expect(included.supersedes == linked.id)
    try expect(try book.extractionStatus(included.id)["state"].text == "failed")
    let sources = try book.counts()["sources"]
    try expect(try book.includeLinked(linked.id).id == included.id)
    try expect(try book.counts()["sources"] == sources)
    try expect(try book.verify()["ok"] == .bool(true))
  }
  check("previous development format is refused without erasing its contents") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("UnsupportedRoleV7.sevra"), title: "V7")
    _ = try book.addItem(category: "source", kind: "note", title: "Preserve me")
    _ = try referenceSQL(book, "DROP TABLE intake_jobs; PRAGMA user_version=7;")
    let database = book.url.appendingPathComponent("workbook.sqlite")
    let before = try Data(contentsOf: database)
    try refuses("schema") { _ = try Workbook(book.url) }
    try expect(try Data(contentsOf: database) == before)
  }
}
